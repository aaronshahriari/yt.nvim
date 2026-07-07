mod innertube;
mod model;
mod ytdlp;

use model::Item;
use std::io::Write;
use std::path::PathBuf;
use std::process::exit;

const UA: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 \
(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let code = match args.get(1).map(String::as_str) {
        Some("search") => cmd_search(&args[2..]),
        Some("channel") => cmd_channel(&args[2..]),
        Some("playlist") => cmd_playlist(&args[2..]),
        Some("thumbnail") => cmd_thumbnail(&args[2..]),
        _ => {
            eprintln!("usage: yt <search|channel|playlist|thumbnail> ...");
            eprintln!("  yt search \"<query>\" [--limit N] [--channel-limit N] [--no-fallback]");
            eprintln!("  yt channel <id> [--limit N]");
            eprintln!("  yt playlist <id> [--limit N]");
            eprintln!("  yt thumbnail <id> [--out <dir>]");
            2
        }
    };
    exit(code);
}

/// Write each item as a flushed NDJSON line to stdout.
fn emit_items(items: &[Item]) {
    let stdout = std::io::stdout();
    let mut lock = stdout.lock();
    for item in items {
        match serde_json::to_string(item) {
            Ok(line) => {
                let _ = writeln!(lock, "{line}");
                let _ = lock.flush();
            }
            Err(e) => eprintln!("serialize error: {e}"),
        }
    }
}

fn http_client() -> reqwest::blocking::Client {
    reqwest::blocking::Client::builder()
        .timeout(std::time::Duration::from_secs(15))
        .build()
        .expect("build http client")
}

/// Grab the value following `--flag` in an arg slice, if present.
fn flag_value<'a>(args: &'a [String], name: &str) -> Option<&'a str> {
    args.iter()
        .position(|a| a == name)
        .and_then(|i| args.get(i + 1))
        .map(String::as_str)
}

fn cmd_search(args: &[String]) -> i32 {
    let Some(query) = args.iter().find(|a| !a.starts_with("--")) else {
        eprintln!("search: missing query");
        return 2;
    };
    let limit = flag_value(args, "--limit")
        .and_then(|s| s.parse::<usize>().ok())
        .unwrap_or(10);
    let channel_limit = flag_value(args, "--channel-limit")
        .and_then(|s| s.parse::<usize>().ok())
        .unwrap_or(5);
    let fallback = !args.iter().any(|a| a == "--no-fallback");

    // yt-dlp only yields videos; wrap them as tagged items for the fallback paths.
    let ytdlp_items = |query: &str, limit: usize| -> Result<Vec<Item>, String> {
        ytdlp::search(query, limit).map(|v| v.into_iter().map(Item::Video).collect())
    };

    let client = http_client();
    let items = match innertube::search(&client, query, limit, channel_limit) {
        Ok(r) if !r.is_empty() => r,
        Ok(_) if fallback => {
            eprintln!("innertube returned no results; trying yt-dlp");
            ytdlp_items(query, limit).unwrap_or_else(|e| {
                eprintln!("yt-dlp fallback failed: {e}");
                Vec::new()
            })
        }
        Ok(empty) => empty,
        Err(e) if fallback => {
            eprintln!("innertube failed ({e}); trying yt-dlp");
            match ytdlp_items(query, limit) {
                Ok(r) => r,
                Err(e2) => {
                    eprintln!("yt-dlp fallback failed: {e2}");
                    return 1;
                }
            }
        }
        Err(e) => {
            eprintln!("innertube failed: {e}");
            return 1;
        }
    };

    emit_items(&items);
    0
}

fn cmd_channel(args: &[String]) -> i32 {
    let Some(id) = args.iter().find(|a| !a.starts_with("--")) else {
        eprintln!("channel: missing channel id");
        return 2;
    };
    let limit = flag_value(args, "--limit")
        .and_then(|s| s.parse::<usize>().ok())
        .unwrap_or(30);

    match ytdlp::channel(id, limit) {
        Ok((videos, playlists)) => {
            let mut items: Vec<Item> = Vec::new();
            items.extend(videos.into_iter().map(Item::Video));
            items.extend(playlists.into_iter().map(Item::Playlist));
            emit_items(&items);
            0
        }
        Err(e) => {
            eprintln!("channel failed: {e}");
            1
        }
    }
}

fn cmd_playlist(args: &[String]) -> i32 {
    let Some(id) = args.iter().find(|a| !a.starts_with("--")) else {
        eprintln!("playlist: missing playlist id");
        return 2;
    };
    let limit = flag_value(args, "--limit")
        .and_then(|s| s.parse::<usize>().ok())
        .unwrap_or(50);

    match ytdlp::playlist(id, limit) {
        Ok(videos) => {
            let items: Vec<Item> = videos.into_iter().map(Item::Video).collect();
            emit_items(&items);
            0
        }
        Err(e) => {
            eprintln!("playlist failed: {e}");
            1
        }
    }
}

fn cmd_thumbnail(args: &[String]) -> i32 {
    let Some(id) = args.iter().find(|a| !a.starts_with("--")) else {
        eprintln!("thumbnail: missing video id");
        return 2;
    };
    let out_dir = flag_value(args, "--out")
        .map(PathBuf::from)
        .unwrap_or_else(default_cache_dir);
    let path = out_dir.join(format!("{id}.jpg"));
    if path.exists() {
        println!("{}", path.display());
        return 0;
    }
    if let Err(e) = std::fs::create_dir_all(&out_dir) {
        eprintln!("mkdir {}: {e}", out_dir.display());
        return 1;
    }

    let client = http_client();
    // Highest quality first: maxresdefault (1280x720) is sharpest but not always
    // generated, so fall through to progressively smaller sizes on a 404. hqdefault
    // is always present as the floor.
    for quality in ["maxresdefault", "sddefault", "hqdefault", "mqdefault"] {
        let url = format!("https://i.ytimg.com/vi/{id}/{quality}.jpg");
        match client.get(&url).header("User-Agent", UA).send() {
            Ok(resp) if resp.status().is_success() => match resp.bytes() {
                Ok(bytes) if !bytes.is_empty() => {
                    if let Err(e) = std::fs::write(&path, &bytes) {
                        eprintln!("write {}: {e}", path.display());
                        return 1;
                    }
                    println!("{}", path.display());
                    return 0;
                }
                _ => continue,
            },
            _ => continue,
        }
    }
    eprintln!("thumbnail: could not fetch for {id}");
    1
}

fn default_cache_dir() -> PathBuf {
    let base = std::env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".cache")))
        .unwrap_or_else(|| PathBuf::from("."));
    base.join("yt.nvim")
}
