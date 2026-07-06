local M = {}

local defaults = {
  bin_path = nil, -- explicit path to the `yt` helper; auto-resolved if nil
  limit = 10, -- results per search
  preview_width = 0.5, -- right pane fraction of total columns
  debounce_ms = 100, -- hover debounce before rendering a preview
  use_ytdlp_fallback = true, -- pass-through to the helper (fallback is on by default there)
  image = {
    height = 18, -- rows the thumbnail occupies at the top of the preview pane
  },
  player = {
    cmd = { "mpv" }, -- youtube URL is appended; mpv drives yt-dlp
  },
  keymaps = {
    play = "<CR>", -- play highlighted result via the player
    quit = "q", -- close the yt.nvim tab
    search = "s", -- start a new search
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
