local M = {}

function M.setup(opts)
  require("yt.config").setup(opts)
end

--- Open yt.nvim. With a query, search immediately; otherwise show the home screen.
function M.open(query)
  if query and query ~= "" then
    local home = require("yt.home")
    if home.is_open() then
      home.close()
    end
    require("yt.search").run(query)
  else
    local ui = require("yt.ui")
    if ui.is_open() then
      ui.close()
    end
    require("yt.home").open()
  end
end

--- Programmatic search entry point.
function M.search(query)
  M.open(query)
end

-- Public actions — bind these to your own keys, e.g.
--   vim.keymap.set("n", "<C-n>", require("yt").next_page)
function M.next_page()
  require("yt.ui").next_page()
end

function M.prev_page()
  require("yt.ui").prev_page()
end

--- Play the result under the cursor via the configured player.
function M.play()
  local ui = require("yt.ui")
  if ui.is_open() then
    local r = ui.current_result()
    if r then
      require("yt.player").play(r)
    end
    return
  end
  local home = require("yt.home")
  if home.is_open() then
    home.action_play()
  end
end

--- Create a new empty playlist from anywhere. Refreshes the home screen if open.
--- Returns true if created, false if the name is blank or already taken.
function M.create_playlist(name)
  local ok = require("yt.store").playlist_create(name)
  if ok then
    local home = require("yt.home")
    if home.is_open() then
      home.render()
    end
    vim.notify("yt.nvim: created playlist " .. name, vim.log.levels.INFO)
  end
  return ok
end

--- Download the result/video under the cursor for offline playback.
function M.install()
  local ui = require("yt.ui")
  if ui.is_open() then
    local r = ui.current_result()
    if r then
      require("yt.install").install(r)
    end
    return
  end
  local home = require("yt.home")
  if home.is_open() then
    home.action_install()
  end
end

--- Close the yt.nvim tab.
function M.close()
  local ui = require("yt.ui")
  if ui.is_open() then
    ui.close()
  end
  local home = require("yt.home")
  if home.is_open() then
    home.close()
  end
end

return M
