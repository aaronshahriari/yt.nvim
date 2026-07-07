use crate::model::{fmt_duration, PlaylistResult, SearchResult};
use serde_json::Value;
use std::process::Command;

/// Run yt-dlp with `--flat-playlist --dump-json` on a target (a URL or a
/// `ytsearchN:` spec) and return each output line parsed as JSON.
fn dump_flat(target: &str, extra: &[&str]) -> Result<Vec<Value>, String> {
    let mut args = vec![target, "--flat-playlist", "--dump-json", "--no-warnings"];
    args.extend_from_slice(extra);
    let output = Command::new("yt-dlp")
        .args(&args)
        .output()
        .map_err(|e| format!("failed to spawn yt-dlp: {e}"))?;
    if !output.status.success() {
        return Err(format!(
            "yt-dlp exited {}: {}",
            output.status,
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }
    Ok(String::from_utf8_lossy(&output.stdout)
        .lines()
        .filter(|l| !l.trim().is_empty())
        .filter_map(|l| serde_json::from_str::<Value>(l).ok())
        .collect())
}

/// A channel's recent videos and its playlists, via the `/videos` and `/playlists`
/// tabs. Either half failing is non-fatal — we return whatever we got.
pub fn channel(id: &str, limit: usize) -> Result<(Vec<SearchResult>, Vec<PlaylistResult>), String> {
    let end = limit.to_string();
    let extra = ["--playlist-end", end.as_str()];
    let videos = dump_flat(&format!("https://www.youtube.com/channel/{id}/videos"), &extra)
        .unwrap_or_default()
        .iter()
        .filter_map(map_entry)
        .collect();
    let playlists = dump_flat(&format!("https://www.youtube.com/channel/{id}/playlists"), &extra)
        .unwrap_or_default()
        .iter()
        .filter_map(map_playlist)
        .collect();
    Ok((videos, playlists))
}

/// The videos in a playlist.
pub fn playlist(id: &str, limit: usize) -> Result<Vec<SearchResult>, String> {
    let end = limit.to_string();
    let entries = dump_flat(
        &format!("https://www.youtube.com/playlist?list={id}"),
        &["--playlist-end", end.as_str()],
    )?;
    Ok(entries.iter().filter_map(map_entry).collect())
}

fn map_playlist(v: &Value) -> Option<PlaylistResult> {
    let id = v.get("id")?.as_str()?.to_string();
    let title = v
        .get("title")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    let video_count = match v.get("playlist_count").and_then(Value::as_u64) {
        Some(n) => format!("{n} videos"),
        None => String::new(),
    };
    Some(PlaylistResult {
        id,
        title,
        video_count,
    })
}

/// Fallback search using yt-dlp's `ytsearchN:` extractor. Slower (Python cold start)
/// but survives InnerTube format drift. `--flat-playlist` keeps it cheap; note it
/// yields no description, which the preview pane tolerates.
pub fn search(query: &str, limit: usize) -> Result<Vec<SearchResult>, String> {
    let spec = format!("ytsearch{limit}:{query}");
    let output = Command::new("yt-dlp")
        .args([&spec, "--flat-playlist", "--dump-json", "--no-warnings"])
        .output()
        .map_err(|e| format!("failed to spawn yt-dlp: {e}"))?;
    if !output.status.success() {
        return Err(format!(
            "yt-dlp exited {}: {}",
            output.status,
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }
    let mut out = Vec::new();
    for line in String::from_utf8_lossy(&output.stdout).lines() {
        if line.trim().is_empty() {
            continue;
        }
        if let Ok(v) = serde_json::from_str::<Value>(line) {
            if let Some(r) = map_entry(&v) {
                out.push(r);
            }
        }
    }
    Ok(out)
}

fn map_entry(v: &Value) -> Option<SearchResult> {
    let id = v.get("id")?.as_str()?.to_string();
    let title = v
        .get("title")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    let channel = v
        .get("channel")
        .or_else(|| v.get("uploader"))
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    let duration_secs = v.get("duration").and_then(Value::as_f64).unwrap_or(0.0) as u64;
    let views = match v.get("view_count").and_then(Value::as_u64) {
        Some(n) => format!("{n} views"),
        None => String::new(),
    };

    Some(SearchResult {
        id,
        title,
        channel,
        duration: fmt_duration(duration_secs),
        duration_secs,
        views,
        published: String::new(),
        description_snippet: String::new(),
    })
}
