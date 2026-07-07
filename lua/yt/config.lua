local M = {}

local defaults = {
  bin_path = nil, -- explicit path to the `yt` helper; auto-resolved if nil
  per_page = 10, -- results shown per page
  max_pages = 5, -- max pages fetched per search (total = per_page * max_pages)
  history_limit = 30, -- recently watched entries kept on disk
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
    cmd = { "mpv", "--save-position-on-quit=yes" }, -- youtube URL is appended
  },
  keymaps = {
    play = "<CR>", -- play highlighted result via the player
    quit = "q", -- close the yt.nvim tab
    search = "s", -- start a new search
    pin = "p", -- pin/unpin highlighted result
    add_to_playlist = "a", -- add highlighted result to a local playlist
    page_next = "L", -- next page of results
    page_prev = "H", -- previous page of results
  },
  home_keymaps = {
    play = "<CR>", -- play highlighted video / expand playlist
    quit = "q", -- close the yt.nvim tab
    search = "s", -- start a search
    pin = "p", -- pin/unpin highlighted video
    add_to_playlist = "a", -- add highlighted video to a local playlist
    remove = "d", -- remove highlighted item from its section
    jump_recent = "gr", -- jump to recently watched
    jump_pinned = "gp", -- jump to pinned
    jump_playlists = "gl", -- jump to playlists
  },
}

M.options = vim.deepcopy(defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
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
