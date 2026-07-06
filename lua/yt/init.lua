local M = {}

function M.setup(opts)
  require("yt.config").setup(opts)
end

--- Open the yt.nvim UI. With a query, search immediately; otherwise prompt.
function M.open(query)
  require("yt.ui").open()
  if query and query ~= "" then
    require("yt.search").run(query)
  else
    vim.ui.input({ prompt = "YouTube search: " }, function(input)
      if input and input ~= "" then
        require("yt.search").run(input)
      end
    end)
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
  local r = require("yt.ui").current_result()
  if r then
    require("yt.player").play(r)
  end
end

--- Close the yt.nvim tab.
function M.close()
  require("yt.ui").close()
end

return M
