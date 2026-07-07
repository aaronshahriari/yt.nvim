local store = require("yt.store")

-- Shared "add a video to a playlist" flow, used by the home screen and the
-- results browser. Goes through vim.ui.select/vim.ui.input, so it honours
-- whatever picker the user has wired up (telescope-ui-select, dressing, etc.).
local M = {}

--- Prompt to add `video` to a playlist, creating a new one on demand.
--- `on_change` runs after a successful add (to refresh the calling view).
function M.pick(video, on_change)
  if not (video and video.id) then
    return
  end
  local function added(name)
    store.playlist_add(name, video)
    vim.notify("yt.nvim: added to " .. name, vim.log.levels.INFO)
    if on_change then
      on_change()
    end
  end

  local choices = vim.list_extend({ "New playlist..." }, store.playlist_names())
  vim.ui.select(choices, { prompt = "Add to playlist:" }, function(choice)
    if not choice then
      return
    end
    if choice == "New playlist..." then
      vim.ui.input({ prompt = "New playlist name: " }, function(name)
        if name and name ~= "" then
          added(name)
        end
      end)
    else
      added(choice)
    end
  end)
end

return M
