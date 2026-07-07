local M = {}

--- Ask for a query, then search. Used by the `search` keybind in both views.
function M.prompt()
  vim.ui.input({ prompt = "YouTube search: " }, function(input)
    if input and input ~= "" then
      M.run(input)
    end
  end)
end

--- Run a search in the results browser.
function M.run(query)
  require("yt.ui").search(query)
end

return M
