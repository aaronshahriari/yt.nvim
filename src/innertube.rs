use crate::model::{parse_duration_secs, SearchResult};
use serde_json::Value;

/// Public web client key baked into youtube.com's own frontend. Not secret.
const KEY: &str = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8";
const UA: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 \
(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

/// Search YouTube via the internal InnerTube API. No API key/quota.
pub fn search(
    client: &reqwest::blocking::Client,
    query: &str,
    limit: usize,
) -> Result<Vec<SearchResult>, String> {
    let url = format!("https://www.youtube.com/youtubei/v1/search?key={KEY}&prettyPrint=false");
    let body = serde_json::json!({
        "context": { "client": {
            "clientName": "WEB",
            "clientVersion": "2.20240401.00.00",
            "hl": "en", "gl": "US"
        }},
        "query": query,
    });
    let resp = client
        .post(&url)
        .header("User-Agent", UA)
        .header("Content-Type", "application/json")
        .json(&body)
        .send()
        .map_err(|e| e.to_string())?;
    if !resp.status().is_success() {
        return Err(format!("innertube HTTP {}", resp.status()));
    }
    let json: Value = resp.json().map_err(|e| e.to_string())?;
    Ok(parse_search(&json, limit))
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

fn parse_search(json: &Value, limit: usize) -> Vec<SearchResult> {
    let mut out = Vec::new();
    let sections = json
        .pointer("/contents/twoColumnSearchResultsRenderer/primaryContents/sectionListRenderer/contents")
        .and_then(Value::as_array);
    let Some(sections) = sections else {
        return out;
    };
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
                    return out;
                }
            }
        }
    }
    out
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
