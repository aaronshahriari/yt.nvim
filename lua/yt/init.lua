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
