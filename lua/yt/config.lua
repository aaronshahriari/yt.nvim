local M = {}

local defaults = {
  bin_path = nil, -- explicit path to the `yt` helper; auto-resolved if nil
  per_page = 10, -- results shown per page
  max_pages = 5, -- max pages fetched per search (total = per_page * max_pages)
  history_limit = 30, -- recently watched entries kept on disk (feeds home + page)
  results_side = "left", -- which side the results list sits on ("left"|"right")
  preview_width = 0.5, -- preview pane fraction of total columns
  debounce_ms = 100, -- hover debounce before rendering a preview
  use_ytdlp_fallback = true, -- pass-through to the helper (fallback is on by default there)
  image = {
    -- Optional max thumbnail height in rows. nil (default) fills the split width
    -- and lets the height follow the aspect ratio; set a number to cap it shorter.
    height = nil,
  },
  player = {
    cmd = { "mpv", "--save-position-on-quit=yes" }, -- youtube URL (or local file) is appended
  },
  download = {
    -- Where installed videos are stored. nil => stdpath("data")/yt.nvim/downloads.
    dir = nil,
    -- yt-dlp format selector. nil lets yt-dlp choose (needs ffmpeg to merge).
    format = nil,
    -- Extra args appended to every yt-dlp download.
    args = {},
  },
  icons = {
    installed = "", -- shown next to a locally downloaded video (nf-fa-download)
    downloading = "", -- shown while a download is in progress (nf-fa-cloud_download)
    video = "●", -- bullet for a video row
    channel = "", -- channel row (nf-fa-users)
    playlist = "", -- playlist row (nf-fa-list)
  },
  -- Search results: which sections appear (in order) and their caps. Channels
  -- come from the same request as videos, so showing them is free.
  search = {
    sections = { "channels", "videos" },
    channels = { limit = 5 }, -- max channels shown atop the results
  },
  -- The channel page (opened with <CR> on a channel): its sections + caps.
  channel = {
    sections = { "videos", "playlists" },
    videos = { limit = nil }, -- nil = show everything fetched
    playlists = { limit = nil },
    fetch_limit = 30, -- how many videos/playlists to pull from the channel
  },
  -- The home dashboard: which sections show (in this order) and how many items
  -- each shows in the compact combined view. Drop a section from `sections` to
  -- hide it; its jump key still opens the full page. Set a `limit` to nil to show
  -- everything on the dashboard too.
  home = {
    sections = { "recent", "pinned", "installed", "playlists" },
    recent = { limit = 5 },
    pinned = { limit = 5 },
    installed = { limit = 5 },
    playlists = { limit = 5, items = 5 }, -- 5 playlists, 5 videos per expanded one
  },
  -- The dedicated single-section pages (opened with gr/gp/gi/gl). A nil `limit`
  -- shows everything (recent is still bounded by history_limit on disk).
  pages = {
    recent = { limit = nil },
    pinned = { limit = nil },
    installed = { limit = nil },
    playlists = { limit = nil, items = nil },
  },
  keymaps = {
    play = "<CR>", -- play video / open channel or playlist under the cursor
    open = "gw", -- open highlighted video in the web browser
    quit = "q", -- close the yt.nvim tab
    home = "gh", -- go back to the home screen
    back = "<BS>", -- pop back one view (channel/playlist -> where you came from)
    search = "s", -- start a new search
    pin = "p", -- pin/unpin highlighted result
    add_to_playlist = "a", -- add highlighted result to a local playlist
    install = "i", -- download highlighted result for offline playback
    page_next = "L", -- next page of results
    page_prev = "H", -- previous page of results
  },
  home_keymaps = {
    play = "<CR>", -- play highlighted video / expand playlist
    open = "gw", -- open highlighted video in the web browser
    quit = "q", -- close the yt.nvim tab
    search = "s", -- start a search
    pin = "p", -- pin/unpin highlighted video
    add_to_playlist = "a", -- add highlighted video to a local playlist
    new_playlist = "N", -- create a new empty playlist
    install = "i", -- download highlighted video for offline playback
    remove = "d", -- remove highlighted item from its section
    home = "gh", -- return to the full home view from a section page
    jump_recent = "gr", -- open the Recently watched page
    jump_pinned = "gp", -- open the Pinned page
    jump_installed = "gi", -- open the Installed page
    jump_playlists = "gl", -- open the Playlists page
  },
}

M.options = vim.deepcopy(defaults)

-- Options whose value is a list. tbl_deep_extend merges lists index-wise (so a
-- shorter user list would leave stale tail entries), so these must replace outright.
local LIST_OVERRIDES = {
  { "home", "sections" },
  { "search", "sections" },
  { "channel", "sections" },
  { "player", "cmd" },
  { "download", "args" },
}

function M.setup(opts)
  opts = opts or {}
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
  for _, path in ipairs(LIST_OVERRIDES) do
    local src, dst = opts, M.options
    for i = 1, #path - 1 do
      src = src and src[path[i]]
      dst = dst[path[i]]
    end
    local leaf = path[#path]
    if src and src[leaf] ~= nil then
      dst[leaf] = src[leaf]
    end
  end
end

--- Resolve the helper binary: explicit config > downloaded `bin/yt` > local
--- `target/release/yt` (dev builds) > `yt` on PATH.
function M.bin_path()
  if M.options.bin_path then
    return M.options.bin_path
  end
  local src = debug.getinfo(1, "S").source:sub(2) -- .../lua/yt/config.lua
  local root = vim.fn.fnamemodify(src, ":h:h:h") -- repo root
  for _, p in ipairs({ root .. "/bin/yt", root .. "/target/release/yt" }) do
    if vim.fn.executable(p) == 1 then
      return p
    end
  end
  if vim.fn.executable("yt") == 1 then
    return "yt"
  end
  return nil
end

return M
