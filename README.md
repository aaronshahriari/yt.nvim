# yt.nvim

Search and watch YouTube directly from Neovim. `:Yt` opens a home screen with
recently watched videos, pinned videos, and local playlists; `:Yt <query>` jumps
straight into search. Both views use a two-pane UI: videos on one side, thumbnail
(inline, via the Kitty graphics protocol) and metadata preview on the other.
Hit `<CR>` to play the video in mpv.

```
┌── YouTube: lofi ─────────────┬──────────────────────────────┐
│  lofi hip hop radio 📚 …     │   ┌────────────────────────┐ │
│  lofi hip hop radio- 24/7 …  │   │      (thumbnail)       │ │
│▸ 90's Lofi City 🌧️ Rainy …   │   └────────────────────────┘ │
│  Coffee Shop Radio - 24/7 …  │   90's Lofi City 🌧️ …        │
│  …                           │   Lofi Girl • 1.2M views     │
│                              │   beats to relax/study to …  │
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
- [`yt-dlp`](https://github.com/yt-dlp/yt-dlp) — fallback search, mpv stream resolver, and offline downloads
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

- `:Yt` — open the home screen
- `:Yt <query>` — open and search immediately
- `:YtBuild` — (re)download or build the helper binary
- `:YtPlaylistNew [name]` — create a new empty playlist (prompts if no name)
- `:YtInstall` — download the highlighted video for offline playback

The home screen stores its runtime state under `stdpath("data")/yt.nvim/`:
recently watched videos, pinned videos, local playlists, and installed (downloaded)
videos. Playback records a video into history, and the default mpv command
saves/resumes playback position.

**Offline downloads.** Press `i` on any video to download it with yt-dlp into
`stdpath("data")/yt.nvim/downloads/`. Installed videos are marked with a  icon
everywhere they appear (including inside playlists) and gain their own **Installed**
section. Playing an installed video uses the local file, so it works offline. mpv is
launched fully detached, so it keeps running after you close Neovim or the terminal.

The dashboard is a compact summary — each section shows a handful of items (see
`home` in [Configuration](#configuration)), with a `… and N more` line when
there's more. The jump keys open each section as its own dedicated page showing
everything (configured under `pages`); `gh` returns to the full home. Deleting a
playlist, or removing a video from one, asks for confirmation first.

In the home pane:

| Key    | Action                                      |
| ------ | ------------------------------------------- |
| `j`/`k` | move — preview updates on hover             |
| `<CR>` | play video / expand or collapse playlist    |
| `s`    | new search                                  |
| `p`    | pin/unpin highlighted video                 |
| `a`    | add highlighted video to a local playlist   |
| `N`    | create a new empty playlist                 |
| `i`    | download highlighted video for offline play |
| `d`    | remove highlighted item (deletes the file in Installed) |
| `gh`   | back to the full home view                  |
| `gr`   | Recently watched page                       |
| `gp`   | Pinned page                                 |
| `gi`   | Installed page                              |
| `gl`   | Playlists page                              |
| `q`    | close                                       |

Search results are grouped into a **Channels** section and a **Videos** section
(the channels come free with the same request). Press `<CR>` on a channel to open
its **channel page** — that channel's videos and playlists — and `<CR>` on one of
those playlists to open it as its own video list. `<BS>` pops back up that stack
(playlist → channel → search). Everything you can do to a video in search (play,
pin, download, add to playlist) works on those pages too.

In the results pane:

| Key     | Action                                       |
| ------- | -------------------------------------------- |
| `j`/`k` | move — preview updates on hover              |
| `H`/`L` | previous / next page (videos)                |
| `<CR>`  | play video / open channel / open playlist    |
| `<BS>`  | back one view (channel/playlist → previous)  |
| `s`     | new search                                   |
| `p`     | pin/unpin highlighted video                  |
| `a`     | add video to a local playlist                |
| `i`     | download video for offline play              |
| `gh`    | back to the home screen                      |
| `q`     | close                                        |

## Configuration

Pass overrides to `require("yt").setup{}` (or the `opts` table with lazy.nvim). Anything
you omit keeps its default:

```lua
require("yt").setup({
  per_page = 10,            -- results shown per page
  max_pages = 5,            -- max pages fetched per search (total = per_page * max_pages)
  history_limit = 30,       -- recently watched entries kept on disk
  results_side = "left",    -- which side the results list sits on: "left" | "right"
  preview_width = 0.5,      -- preview pane width as a fraction of the editor columns
  debounce_ms = 100,        -- hover delay (ms) before a preview renders
  use_ytdlp_fallback = true,-- fall back to yt-dlp if InnerTube returns nothing
  bin_path = nil,           -- explicit path to the `yt` helper (auto-resolved otherwise)
  image = { height = nil },  -- optional max thumbnail height in rows (nil = fill the split width)
  player = { cmd = { "mpv", "--save-position-on-quit=yes" } }, -- video URL (or local file) appended
  download = {
    dir = nil,              -- where installed videos go (nil = stdpath("data")/yt.nvim/downloads)
    format = nil,           -- yt-dlp format selector (nil = yt-dlp's default; merging needs ffmpeg)
    args = {},              -- extra args appended to every yt-dlp download
  },
  icons = {
    installed = "",        -- marker for a downloaded video
    downloading = "",      -- marker shown while a download runs
    video = "●",            -- bullet for a video row
    channel = "",          -- channel row
    playlist = "",         -- playlist row
  },
  -- Search results: which sections show (in order) and their caps. Channels come
  -- from the same request as videos, so showing them costs nothing extra.
  search = {
    sections = { "channels", "videos" },
    channels = { limit = 5 },   -- max channels shown atop the results
  },
  -- The channel page (opened with <CR> on a channel).
  channel = {
    sections = { "videos", "playlists" },
    videos = { limit = nil },   -- nil = show everything fetched
    playlists = { limit = nil },
    fetch_limit = 30,           -- how many videos/playlists to pull per channel
  },
  -- The compact home dashboard: which sections appear (in this order) and how
  -- many items each shows. Remove a section from `sections` to hide it — its
  -- jump key (below) still opens the full page. A nil `limit` shows everything.
  home = {
    sections = { "recent", "pinned", "installed", "playlists" },
    recent    = { limit = 5 },
    pinned    = { limit = 5 },
    installed = { limit = 5 },
    playlists = { limit = 5, items = 5 }, -- 5 playlists, 5 videos per expanded one
  },
  -- The dedicated single-section pages (gr/gp/gi/gl). nil `limit` = show all
  -- (recent is still bounded by history_limit on disk).
  pages = {
    recent    = { limit = nil },
    pinned    = { limit = nil },
    installed = { limit = nil },
    playlists = { limit = nil, items = nil },
  },
  keymaps = {
    play = "<CR>",          -- play video / open channel or playlist under the cursor
    home = "gh",            -- back to the home screen
    back = "<BS>",          -- pop back one view (channel/playlist -> previous)
    search = "s",           -- start a new search
    pin = "p",              -- pin/unpin the highlighted result
    add_to_playlist = "a",  -- add the highlighted result to a local playlist
    install = "i",          -- download the highlighted result for offline playback
    quit = "q",             -- close the yt.nvim tab
    page_next = "L",        -- next page
    page_prev = "H",        -- previous page
  },
  home_keymaps = {
    play = "<CR>",          -- play highlighted video / expand playlist
    search = "s",           -- start a new search
    pin = "p",              -- pin/unpin highlighted video
    add_to_playlist = "a",  -- add highlighted video to a local playlist
    new_playlist = "N",     -- create a new empty playlist
    install = "i",          -- download highlighted video for offline playback
    remove = "d",           -- remove highlighted item from its section
    home = "gh",            -- return to the full home view
    jump_recent = "gr",     -- open the Recently watched page
    jump_pinned = "gp",     -- open the Pinned page
    jump_installed = "gi",  -- open the Installed page
    jump_playlists = "gl",  -- open the Playlists page
    quit = "q",             -- close the yt.nvim tab
  },
})
```

| Option               | Default        | What it does                                                        |
| -------------------- | -------------- | ------------------------------------------------------------------- |
| `per_page`           | `10`           | Results shown per page.                                             |
| `max_pages`          | `5`            | Max pages fetched per search (total results = `per_page × max_pages`). |
| `history_limit`      | `30`           | Recently watched entries kept on disk.                              |
| `results_side`       | `"left"`       | Side the results list appears on; the preview takes the other side. |
| `preview_width`      | `0.5`          | Fraction of the window width given to the preview pane (`0`–`1`).    |
| `debounce_ms`        | `100`          | Delay after cursor movement before the preview updates.             |
| `use_ytdlp_fallback` | `true`         | Use yt-dlp when the InnerTube API returns no results.               |
| `bin_path`           | `nil`          | Path to the `yt` helper binary; auto-detected when `nil`.           |
| `image.height`       | `nil`          | Optional max thumbnail height in rows; `nil` fills the split width.  |
| `player.cmd`         | `{ "mpv", "--save-position-on-quit=yes" }` | Command used for playback; the video URL is appended. |
| `keymaps`            | see above      | Buffer-local keys in the results pane.                              |
| `home_keymaps`       | see above      | Buffer-local keys in the home pane.                                 |

### Recipes

```lua
-- Results on the right, wider preview, more per page and more pages
require("yt").setup({ results_side = "right", preview_width = 0.6, per_page = 20, max_pages = 10 })

-- Audio only
require("yt").setup({ player = { cmd = { "mpv", "--save-position-on-quit=yes", "--no-video" } } })

-- Open in the browser instead of mpv
require("yt").setup({ player = { cmd = { "xdg-open" } } })
```

### Lua API

The built-in keymaps just call these — bind them to your own keys instead if you prefer.
Set the corresponding `keymaps.*` entry to `false`/`nil` to drop a default binding.

```lua
local yt = require("yt")
yt.open("lofi hip hop") -- open + search (omit the arg to be prompted)
yt.next_page()          -- next page of results
yt.prev_page()          -- previous page
yt.play()               -- play the result under the cursor
yt.close()              -- close the tab

-- e.g. page with Ctrl-n / Ctrl-p on top of the default H / L
vim.keymap.set("n", "<C-n>", yt.next_page)
vim.keymap.set("n", "<C-p>", yt.prev_page)
```

## Helper binary

Usable standalone:

```sh
yt search "rust tutorial" --limit 10   # NDJSON, one video per line
yt thumbnail <video_id> --out <dir>    # downloads <dir>/<id>.jpg
```
