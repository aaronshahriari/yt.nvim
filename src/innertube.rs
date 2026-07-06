use crate::model::{parse_duration_secs, SearchResult};
use serde_json::{json, Value};

/// Public web client key baked into youtube.com's own frontend. Not secret.
const KEY: &str = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8";
const UA: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 \
(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";
/// Safety cap so a runaway/looping token never spins forever. Each round yields ~20.
const MAX_CONTINUATIONS: usize = 12;

fn context() -> Value {
    json!({ "client": {
        "clientName": "WEB",
        "clientVersion": "2.20240401.00.00",
        "hl": "en", "gl": "US"
    }})
}

fn post_search(client: &reqwest::blocking::Client, body: &Value) -> Result<Value, String> {
    let url = format!("https://www.youtube.com/youtubei/v1/search?key={KEY}&prettyPrint=false");
    let resp = client
        .post(&url)
        .header("User-Agent", UA)
        .header("Content-Type", "application/json")
        .json(body)
        .send()
        .map_err(|e| e.to_string())?;
    if !resp.status().is_success() {
        return Err(format!("innertube HTTP {}", resp.status()));
    }
    resp.json().map_err(|e| e.to_string())
}

/// Search YouTube via the internal InnerTube API. No API key/quota. A single response
/// only carries ~20 videos, so we follow continuation tokens until we have `limit`.
pub fn search(
    client: &reqwest::blocking::Client,
    query: &str,
    limit: usize,
) -> Result<Vec<SearchResult>, String> {
    let mut out = Vec::new();

    // Initial page. A hard error here propagates so the caller can fall back to yt-dlp.
    let json = post_search(client, &json!({ "context": context(), "query": query }))?;
    let mut token = match json
        .pointer("/contents/twoColumnSearchResultsRenderer/primaryContents/sectionListRenderer/contents")
        .and_then(Value::as_array)
    {
        Some(sections) => {
            collect_videos(sections, &mut out, limit);
            find_token(sections)
        }
        None => None,
    };

    // Follow continuations. Failures here are non-fatal: return what we have.
    let mut rounds = 0;
    while out.len() < limit && rounds < MAX_CONTINUATIONS {
        let Some(t) = token.take() else {
            break;
        };
        rounds += 1;
        let Ok(json) = post_search(client, &json!({ "context": context(), "continuation": t })) else {
            break;
        };
        let Some(items) = json
            .pointer("/onResponseReceivedCommands/0/appendContinuationItemsAction/continuationItems")
            .and_then(Value::as_array)
        else {
            break;
        };
        collect_videos(items, &mut out, limit);
        token = find_token(items);
    }

    Ok(out)
}

/// Pull text out of an InnerTube `{simpleText}` or `{runs:[{text}]}` node.
fn text_of(v: &Value) -> String {
    if let Some(s) = v.get("simpleText").and_then(Value::as_str) {
        return s.to_string();
    }
    if let Some(runs) = v.get("runs").and_then(Value::as_array) {
        return runs
            .iter()
            .filter_map(|r| r.get("text").and_then(Value::as_str))
            .collect();
    }
    String::new()
}

/// Walk a list of section-like items (`itemSectionRenderer.contents[].videoRenderer`),
/// appending parsed videos until `limit` is reached. Shared by the initial and
/// continuation responses, which use the same shape.
fn collect_videos(sections: &[Value], out: &mut Vec<SearchResult>, limit: usize) {
    for section in sections {
        let Some(items) = section
            .pointer("/itemSectionRenderer/contents")
            .and_then(Value::as_array)
        else {
            continue;
        };
        for item in items {
            let Some(vr) = item.get("videoRenderer") else {
                continue;
            };
            if let Some(r) = parse_video(vr) {
                out.push(r);
                if out.len() >= limit {
                    return;
                }
            }
        }
    }
}

/// Find the "load more" token in a section list, if any.
fn find_token(sections: &[Value]) -> Option<String> {
    sections.iter().find_map(|s| {
        s.pointer("/continuationItemRenderer/continuationEndpoint/continuationCommand/token")
            .and_then(Value::as_str)
            .map(str::to_string)
    })
}

fn parse_video(vr: &Value) -> Option<SearchResult> {
    let id = vr.get("videoId")?.as_str()?.to_string();
    let title = text_of(vr.get("title")?);
    let channel = vr
        .get("ownerText")
        .or_else(|| vr.get("longBylineText"))
        .map(text_of)
        .unwrap_or_default();
    let duration = vr.get("lengthText").map(text_of).unwrap_or_default();
    let duration_secs = parse_duration_secs(&duration);
    let views = vr.get("viewCountText").map(text_of).unwrap_or_default();
    let published = vr.get("publishedTimeText").map(text_of).unwrap_or_default();
    let description_snippet = vr
        .pointer("/detailedMetadataSnippets/0/snippetText")
        .or_else(|| vr.get("descriptionSnippet"))
        .map(text_of)
        .unwrap_or_default();

    Some(SearchResult {
        id,
        title,
        channel,
        duration,
        duration_secs,
        views,
        published,
        description_snippet,
    })
}
