local config = require("yt.config")

local M = {}

function M.url(result)
  return "https://www.youtube.com/watch?v=" .. result.id
end

--- Launch the configured player (mpv by default), detached into its own session
--- so it outlives the editor and terminal. Plays the local file when the video is
--- installed; otherwise the YouTube URL (mpv resolves the stream via yt-dlp).
--- stdio is ignored (not piped to nvim) so mpv never dies from a closed pipe.
function M.play(result)
  local store = require("yt.store")
  local local_path = store.installed_path(result.id)
  local target = (local_path and vim.fn.filereadable(local_path) == 1) and local_path or M.url(result)

  local cmd = vim.deepcopy(config.options.player.cmd)
  cmd[#cmd + 1] = target
  local ok, err = pcall(vim.system, cmd, {
    detach = true,
    stdin = false,
    stdout = false,
    stderr = false,
  })
  if ok then
    pcall(store.history_add, result)
    vim.notify("yt.nvim: playing " .. (result.title or result.id), vim.log.levels.INFO)
  else
    vim.notify("yt.nvim: failed to launch player: " .. tostring(err), vim.log.levels.ERROR)
  end
end

return M
