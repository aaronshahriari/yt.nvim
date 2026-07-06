-- Standalone way to try yt.nvim with thumbnails, without touching your real config.
--   nvim -u demo/init.lua
-- (run from the repo root). Delete this file/dir anytime — it's just a harness.

local this = debug.getinfo(1, "S").source:sub(2)
local repo = vim.fn.fnamemodify(this, ":h:h") -- repo root
vim.opt.runtimepath:prepend(repo)

-- Bootstrap image.nvim into a scratch dir (optional — plugin works without it, just no thumbnails).
local scratch = vim.fn.stdpath("data") .. "/yt-demo"
local img_dir = scratch .. "/image.nvim"
if vim.fn.isdirectory(img_dir) == 0 then
  vim.fn.mkdir(scratch, "p")
  vim.notify("cloning image.nvim…")
  vim.fn.system({ "git", "clone", "--depth=1", "https://github.com/3rd/image.nvim", img_dir })
end
vim.opt.runtimepath:prepend(img_dir)

local ok = pcall(function()
  require("image").setup({
    backend = "kitty", -- Kitty + Ghostty speak this
    processor = "magick_cli", -- use the `magick` CLI, no luarock needed
  })
end)
if not ok then
  vim.notify("image.nvim not available — running without thumbnails", vim.log.levels.WARN)
end

require("yt").setup({})
vim.schedule(function()
  vim.notify("yt.nvim demo ready — run :Yt <query>")
end)
