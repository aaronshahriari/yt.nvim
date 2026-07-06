local config = require("yt.config")

local M = {}

-- image.nvim is optional; without it we still show title/metadata text.
local has_image, image_api = pcall(require, "image")

local function cache_dir()
  local dir = vim.fn.stdpath("cache") .. "/yt.nvim"
  vim.fn.mkdir(dir, "p")
  return dir
end

local function thumb_path(id)
  return cache_dir() .. "/" .. id .. ".jpg"
end

--- Kick off a background thumbnail download (no-op if cached or no binary).
function M.prefetch(result)
  if vim.fn.filereadable(thumb_path(result.id)) == 1 then
    return
  end
  local bin = config.bin_path()
  if not bin then
    return
  end
  require("yt.job").stream({ bin, "thumbnail", result.id, "--out", cache_dir() }, {})
end

local function render_image(path)
  local st = require("yt.ui").state()
  if st.image then
    pcall(function()
      st.image:clear()
    end)
    st.image = nil
  end
  if not (has_image and st.right_win and vim.api.nvim_win_is_valid(st.right_win)) then
    return
  end
  local ok, img = pcall(image_api.from_file, path, {
    window = st.right_win,
    buffer = st.right_buf,
    x = 0,
    y = 0,
    height = config.options.image.height,
  })
  if ok and img then
    st.image = img
    pcall(function()
      img:render()
    end)
  end
end

local function render_text(result)
  local ui = require("yt.ui")
  local st = ui.state()
  local h = config.options.image.height

  local lines = {}
  for _ = 1, h do
    lines[#lines + 1] = ""
  end
  lines[#lines + 1] = result.title or ""

  local meta = {}
  for _, field in ipairs({ result.channel, result.views, result.published, result.duration }) do
    if field and field ~= "" then
      meta[#meta + 1] = field
    end
  end
  lines[#lines + 1] = table.concat(meta, "  •  ")
  lines[#lines + 1] = ""
  if result.description_snippet and result.description_snippet ~= "" then
    lines[#lines + 1] = result.description_snippet
  end

  ui.set_lines(st.right_buf, lines)
  vim.api.nvim_buf_clear_namespace(st.right_buf, st.ns, 0, -1)
  vim.api.nvim_buf_set_extmark(st.right_buf, st.ns, h, 0, { line_hl_group = "Title" })
  vim.api.nvim_buf_set_extmark(st.right_buf, st.ns, h + 1, 0, { line_hl_group = "Comment" })
end

--- Show a result in the preview pane: text immediately, image once available.
function M.update(result)
  local st = require("yt.ui").state()
  st.preview_id = result.id
  render_text(result)

  local path = thumb_path(result.id)
  if vim.fn.filereadable(path) == 1 then
    render_image(path)
    return
  end

  local bin = config.bin_path()
  if not bin then
    return
  end
  require("yt.job").stream({ bin, "thumbnail", result.id, "--out", cache_dir() }, {
    on_exit = function(res)
      -- only render if the user is still on this result
      if res.code == 0 and st.preview_id == result.id and vim.fn.filereadable(path) == 1 then
        render_image(path)
      end
    end,
  })
end

return M
