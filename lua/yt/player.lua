local config = require("yt.config")

local M = {}

function M.url(result)
  return "https://www.youtube.com/watch?v=" .. result.id
end

--- Launch the configured player (mpv by default) on the result's URL, detached
--- so it outlives the editor call. mpv resolves the stream via yt-dlp.
function M.play(result)
  local cmd = vim.deepcopy(config.options.player.cmd)
  cmd[#cmd + 1] = M.url(result)
  local ok, err = pcall(vim.system, cmd, { detach = true })
  if ok then
    pcall(require("yt.store").history_add, result)
    vim.notify("yt.nvim: playing " .. (result.title or result.id), vim.log.levels.INFO)
  else
    vim.notify("yt.nvim: failed to launch player: " .. tostring(err), vim.log.levels.ERROR)
  end
end

return M
