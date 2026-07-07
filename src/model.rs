use serde::Serialize;

/// A single item in a stream: a video, a channel, or a playlist. Serialized as
/// one NDJSON line with a `kind` discriminator (e.g. `{"kind":"video",...}`) so
/// the Lua side can bucket each line into the right section.
#[derive(Serialize, Debug, Clone)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum Item {
    Video(SearchResult),
    Channel(ChannelResult),
    Playlist(PlaylistResult),
}

/// A channel hit from search. NOTE: YouTube's `channelRenderer` field names are
/// misleading — the handle lives in `subscriberCountText` and the subscriber
/// count in `videoCountText` — so those are mapped deliberately, not swapped.
#[derive(Serialize, Debug, Clone)]
pub struct ChannelResult {
    /// Channel id, e.g. "UCwzCMiicL-hBUzyjWiJaseg".
    pub id: String,
    /// Channel name, e.g. "Kill Tony".
    pub title: String,
    /// Handle, e.g. "@KillTony". Empty if unknown.
    pub handle: String,
    /// e.g. "2.71M subscribers". Empty if unknown.
    pub subscribers: String,
    /// Truncated channel description. May be empty.
    pub description_snippet: String,
}

/// A playlist hit (from a channel's Playlists tab).
#[derive(Serialize, Debug, Clone)]
pub struct PlaylistResult {
    /// Playlist id, e.g. "PL...".
    pub id: String,
    pub title: String,
    /// e.g. "42 videos". Empty if unknown.
    pub video_count: String,
}

/// One YouTube search result. Serialized as a single NDJSON line to stdout so the
/// Lua side can append results to the buffer progressively.
#[derive(Serialize, Debug, Clone)]
pub struct SearchResult {
    pub id: String,
    pub title: String,
    pub channel: String,
    /// Human duration, e.g. "3:32" or "1:02:03". Empty for live/unknown.
    pub duration: String,
    /// Duration in seconds, 0 if unknown.
    pub duration_secs: u64,
    /// e.g. "1.4B views" or "watching now".
    pub views: String,
    /// e.g. "14 years ago". Empty if unknown.
    pub published: String,
    /// Truncated description shown under the preview. May be empty (yt-dlp fallback).
    pub description_snippet: String,
}

/// Format a second count as H:MM:SS or M:SS. Empty string for 0.
pub fn fmt_duration(secs: u64) -> String {
    if secs == 0 {
        return String::new();
    }
    let (h, m, s) = (secs / 3600, (secs % 3600) / 60, secs % 60);
    if h > 0 {
        format!("{h}:{m:02}:{s:02}")
    } else {
        format!("{m}:{s:02}")
    }
}

/// Parse "3:32" / "1:02:03" into seconds. 0 on anything unparseable.
pub fn parse_duration_secs(s: &str) -> u64 {
    if s.is_empty() {
        return 0;
    }
    let mut secs = 0u64;
    for part in s.split(':') {
        secs = secs * 60 + part.trim().parse::<u64>().unwrap_or(0);
    }
    secs
}
