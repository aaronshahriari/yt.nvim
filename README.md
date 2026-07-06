# yt.nvim

Search and watch YouTube directly from Neovim. A two-pane UI: type a query, results
stream into the left pane, and moving your cursor over a result renders its thumbnail
(inline, via the Kitty graphics protocol) with title/description in the right pane.
Hit `<CR>` to play the video in mpv.

```
┌── YouTube: lofi ─────────────┬──────────────────────────────┐
│  lofi hip hop radio 📚 …     │   ┌────────────────────────┐ │
│  lofi hip hop radio- 24/7 …  │   │      (thumbnail)       │ │
│▸ 90's Lofi City 🌧️ Rainy …  │   └────────────────────────┘ │
│  Coffee Shop Radio - 24/7 …  │   90's Lofi City 🌧️ …        │
│  …                           │   Lofi Girl • 1.2M views      │
│                              │   beats to relax/study to …   │
└──────────────────────────────┴──────────────────────────────┘
```

## How it works

A small **Rust helper binary** (`yt`) hits YouTube's internal **InnerTube API** (no API
key, no quota) and streams results as NDJSON, falling back to **yt-dlp** if the format
drifts. Neovim spawns it async, populates the list, and renders thumbnails with
[image.nvim](https://github.com/3rd/image.nvim). Playback shells out to **mpv** (which
resolves the stream via yt-dlp).

## Requirements

- Neovim ≥ 0.10 (uses `vim.system`)
- A terminal that speaks the **Kitty graphics protocol**: Kitty, Ghostty, or WezTerm
- [`imagemagick`](https://imagemagick.org) — required by image.nvim
- [`mpv`](https://mpv.io) — playback
- [`yt-dlp`](https://github.com/yt-dlp/yt-dlp) — fallback search + mpv stream resolver
- Rust toolchain (`cargo`) to build the helper binary
- [3rd/image.nvim](https://github.com/3rd/image.nvim) (optional — without it you still get
  results, metadata, and playback, just no thumbnails)

> **Using tmux?** The Kitty graphics protocol only tunnels through tmux with passthrough
> enabled. Add this to your `tmux.conf`, or thumbnails silently won't render:
>
> ```tmux
> set -gq allow-passthrough on
> ```

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "aaronshahriari/yt.nvim",
  build = "cargo build --release",
  dependencies = { "3rd/image.nvim" },
  opts = {},
}
```

The `build` step compiles the helper binary into `target/release/yt`; the plugin finds it
automatically. On Nix, `nix develop` provides `cargo`, `imagemagick`, `mpv`, and `yt-dlp`.

## Usage

- `:Yt` — open the UI and prompt for a search
- `:Yt <query>` — open and search immediately

In the results pane:

| Key     | Action                          |
| ------- | ------------------------------- |
| `j`/`k` | move — preview updates on hover |
| `<CR>`  | play the highlighted video (mpv)|
| `s`     | new search                      |
| `q`     | close                           |

## Configuration

Defaults (pass overrides to `opts` / `require("yt").setup{}`):

```lua
{
  bin_path = nil,            -- explicit path to the `yt` helper (auto-resolved otherwise)
  limit = 10,               -- results per search
  preview_width = 0.5,      -- right pane fraction of total width
  debounce_ms = 100,        -- hover debounce before rendering a preview
  use_ytdlp_fallback = true,
  image = { height = 18 },  -- thumbnail height in rows
  player = { cmd = { "mpv" } }, -- youtube URL is appended
  keymaps = { play = "<CR>", quit = "q", search = "s" },
}
```

Want audio-only, or to open in a browser instead? Swap `player.cmd`, e.g.
`{ "mpv", "--no-video" }` or `{ "xdg-open" }`.

## Helper binary

Usable standalone:

```sh
yt search "rust tutorial" --limit 10   # NDJSON, one video per line
yt thumbnail <video_id> --out <dir>    # downloads <dir>/<id>.jpg
```
