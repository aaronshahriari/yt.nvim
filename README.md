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
resolves the stream via yt-dlp). The binary is fetched pre-built on install, falling back
to a source build only if no release matches your platform.

## Requirements

- Neovim ≥ 0.11 (uses `vim.system`; `vim.pack` needs 0.12+)
- A terminal that speaks the **Kitty graphics protocol**: Kitty, Ghostty, or WezTerm
- [`imagemagick`](https://imagemagick.org) — required by image.nvim
- [`mpv`](https://mpv.io) — playback
- [`yt-dlp`](https://github.com/yt-dlp/yt-dlp) — fallback search + mpv stream resolver
- [3rd/image.nvim](https://github.com/3rd/image.nvim) (optional — without it you still get
  results, metadata, and playback, just no thumbnails)
- Only if building from source (no prebuilt binary for your platform): Rust toolchain (`cargo`)

> **Using tmux?** The Kitty graphics protocol only tunnels through tmux with passthrough
> enabled. Add this to your `tmux.conf`, or thumbnails silently won't render:
>
> ```tmux
> set -gq allow-passthrough on
> ```

## Installation

The helper binary is fetched automatically on install and update.

**vim.pack (Neovim 0.12+)** — register the `PackChanged` hook **before** `vim.pack.add()`:

```lua
vim.api.nvim_create_autocmd('PackChanged', {
  callback = function(ev)
    local name, kind = ev.data.spec.name, ev.data.kind
    if name == 'yt.nvim' and (kind == 'install' or kind == 'update') then
      require('yt.download').download_or_build()
    end
  end,
})

vim.pack.add({
  { src = 'https://github.com/3rd/image.nvim' },
  { src = 'https://github.com/aaronshahriari/yt.nvim' },
})

require('image').setup()
require('yt').setup()
```

If the hook wasn't in place on first install, run `:YtBuild` manually.

**lazy.nvim** — the bundled `build.lua` is picked up automatically, so no `build =` key is needed:

```lua
{
  'aaronshahriari/yt.nvim',
  dependencies = { '3rd/image.nvim' },
  config = function() require('yt').setup() end,
}
```

<details>
<summary>Other plugin managers</summary>

```vim
" vim-plug
Plug 'aaronshahriari/yt.nvim', { 'do': ':YtBuild' }
```

```lua
-- packer.nvim
use { 'aaronshahriari/yt.nvim', run = ':YtBuild' }
```

```sh
# Manual
git clone https://github.com/aaronshahriari/yt.nvim
```

For a manual install, add the directory to `runtimepath`, call `require('yt').setup()`, and
run `:YtBuild`.

</details>

On Nix, `nix develop` provides `cargo`, `imagemagick`, `mpv`, and `yt-dlp` for local builds.

## Usage

- `:Yt` — open the UI and prompt for a search
- `:Yt <query>` — open and search immediately
- `:YtBuild` — (re)download or build the helper binary

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
