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

return M
