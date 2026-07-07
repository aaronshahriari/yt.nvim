local config = require("yt.config")
local store = require("yt.store")
local job = require("yt.job")

-- Downloads videos with yt-dlp for offline playback, tracking each installed
-- file in the store. Installed videos keep their place in every section (recent,
-- pinned, playlists) and just gain a marker; a dedicated Installed section also
-- lists them all.
local M = {}

local active = {} -- id -> true while a download is running

function M.is_downloading(id)
  return active[id] == true
end

local function download_dir()
  local d = config.options.download.dir or (vim.fn.stdpath("data") .. "/yt.nvim/downloads")
  vim.fn.mkdir(d, "p")
  return d
end

--- Download a video into the downloads dir, then record it as installed.
--- `on_done(ok)` runs on completion (used by the UI to refresh). No-ops if the
--- video is already installed or currently downloading.
function M.install(video, on_done)
  if not (video and video.id) then
    return
  end
  if store.is_installed(video.id) then
    vim.notify("yt.nvim: already installed — " .. (video.title or video.id), vim.log.levels.INFO)
    return
  end
  if active[video.id] then
    return
  end
  if vim.fn.executable("yt-dlp") ~= 1 then
    vim.notify("yt.nvim: yt-dlp not found on PATH", vim.log.levels.ERROR)
    return
  end

  local dir = download_dir()
  local cmd = { "yt-dlp", "--no-playlist", "-o", dir .. "/%(id)s.%(ext)s" }
  if config.options.download.format then
    vim.list_extend(cmd, { "-f", config.options.download.format })
  end
  vim.list_extend(cmd, config.options.download.args or {})
  cmd[#cmd + 1] = "https://www.youtube.com/watch?v=" .. video.id

  active[video.id] = true
  vim.notify("yt.nvim: downloading " .. (video.title or video.id) .. "…", vim.log.levels.INFO)
  if on_done then
    on_done() -- let the UI paint a "downloading" marker right away
  end

  job.stream(cmd, {
    on_exit = function(res)
      active[video.id] = nil
      if res.code == 0 then
        -- The extension depends on the chosen format, so glob for id.* and skip
        -- any partial (.part) leftovers.
        local path
        for _, m in ipairs(vim.fn.glob(dir .. "/" .. video.id .. ".*", false, true)) do
          if not m:match("%.part$") then
            path = m
            break
          end
        end
        store.install_add(video, path)
        vim.notify("yt.nvim: installed " .. (video.title or video.id), vim.log.levels.INFO)
      else
        vim.notify("yt.nvim: download failed — " .. (video.title or video.id), vim.log.levels.ERROR)
      end
      if on_done then
        on_done(res.code == 0)
      end
    end,
    stderr = function() end,
  })
end

return M
