local config = require("yt.config")
local job = require("yt.job")

local M = {}

function M.run(query)
  local ui = require("yt.ui")
  if not ui.is_open() then
    ui.open()
  end
  local st = ui.state()

  local bin = config.bin_path()
  if not bin then
    vim.notify(
      "yt.nvim: helper binary not found. Build it with `cargo build --release`.",
      vim.log.levels.ERROR
    )
    return
  end

  st.results = {}
  st.preview_id = nil
  ui.set_query(query)
  ui.render_results() -- shows "Searching…"

  local preview = require("yt.preview")
  local cmd = { bin, "search", query, "--limit", tostring(config.options.limit) }
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
      preview.prefetch(obj) -- warm the thumbnail cache
    end,
    on_exit = function()
      if #st.results == 0 then
        ui.set_lines(st.left_buf, { "  No results." })
      end
    end,
    stderr = function() end,
  })
end

return M
