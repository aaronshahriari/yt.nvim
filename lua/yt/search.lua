local config = require("yt.config")
local job = require("yt.job")

local M = {}

--- Ask for a query, then search. Used by the `search` keybind in both views.
function M.prompt()
  vim.ui.input({ prompt = "YouTube search: " }, function(input)
    if input and input ~= "" then
      M.run(input)
    end
  end)
end

function M.run(query)
  local home = require("yt.home")
  if home.is_open() then
    home.close()
  end

  local ui = require("yt.ui")
  if not ui.is_open() then
    ui.open()
  end
  local st = ui.state()

  local bin = config.bin_path()
  if not bin then
    vim.notify(
      "yt.nvim: helper binary not found. Run :YtBuild to download or build it.",
      vim.log.levels.ERROR
    )
    return
  end

  st.results = {}
  st.page = 1
  ui.set_query(query)
  ui.render_results() -- shows "Searching…"

  local preview = require("yt.preview")
  preview.attach(st.preview_win, st.preview_buf) -- reset preview for the new search
  local total = config.options.per_page * config.options.max_pages
  local cmd = { bin, "search", query, "--limit", tostring(total) }
  if not config.options.use_ytdlp_fallback then
    table.insert(cmd, "--no-fallback")
  end

  job.stream(cmd, {
    on_line = function(line)
      local ok, obj = pcall(vim.json.decode, line)
      if not ok or type(obj) ~= "table" or not obj.id then
        return
      end
      st.results[#st.results + 1] = obj
      ui.render_results()
      if #st.results == 1 then
        preview.update(obj) -- preview the top hit immediately
      end
      -- Only warm the first page here; later pages prefetch on navigation so we
      -- don't spawn one thumbnail process per result all at once.
      if #st.results <= config.options.per_page then
        preview.prefetch(obj)
      end
    end,
    on_exit = function()
      if #st.results == 0 then
        ui.set_lines(st.results_buf, { "  No results." })
      end
    end,
    stderr = function() end,
  })
end

return M
