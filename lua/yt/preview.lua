local config = require("yt.config")

local M = {}

-- image.nvim is optional; without it we still show title/metadata text.
local has_image, image_api = pcall(require, "image")
local ns = vim.api.nvim_create_namespace("yt_preview")

-- The preview pane is shared between the search and home views; whichever view
-- is active attaches its right-hand window/buffer here.
local pane = { win = nil, buf = nil, image = nil, current_id = nil }

local function cache_dir()
  local dir = vim.fn.stdpath("cache") .. "/yt.nvim"
  vim.fn.mkdir(dir, "p")
  return dir
end

local function thumb_path(id)
  return cache_dir() .. "/" .. id .. ".jpg"
end

-- Only videos have i.ytimg.com thumbnails. Video ids are 11 chars; channel (UC…)
-- and playlist (PL…) ids are longer, so skip the doomed fetch for those.
local function is_video_id(id)
  return type(id) == "string" and #id == 11
end

--- Kick off a background thumbnail download (no-op if cached or no binary).
function M.prefetch(result)
  if not is_video_id(result.id) or vim.fn.filereadable(thumb_path(result.id)) == 1 then
    return
  end
  local bin = config.bin_path()
  if not bin then
    return
  end
  require("yt.job").stream({ bin, "thumbnail", result.id, "--out", cache_dir() }, {})
end

local function clear_image()
  if pane.image then
    pcall(function()
      pane.image:clear()
    end)
    pane.image = nil
  end
end

--- Bind the preview to a window/buffer (call on view open). Resets prior state.
function M.attach(win, buf)
  M.detach()
  pane.win, pane.buf = win, buf
end

--- Clear the current image and unbind.
function M.detach()
  clear_image()
  pane.win, pane.buf, pane.current_id = nil, nil, nil
end

local function set_buf_lines(buf, lines)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function render_image(path)
  clear_image()
  if not (has_image and pane.win and vim.api.nvim_win_is_valid(pane.win)) then
    return
  end
  -- Anchor at the empty first buffer line and let image.nvim reserve the space:
  --   * with_virtual_padding pushes the text below by the image's *actual* height
  --   * max_width fills the pane, so the image tracks the split as it resizes
  --   * max_height caps it to the pane so a wide image never overflows a short one
  -- image.height is an optional ceiling; without it the width fit drives the size.
  local opts = {
    window = pane.win,
    buffer = pane.buf,
    x = 0,
    y = 0,
    max_width_window_percentage = 100,
    max_height_window_percentage = 100,
    with_virtual_padding = true,
  }
  if config.options.image.height then
    opts.height = config.options.image.height
  end
  local ok, img = pcall(image_api.from_file, path, opts)
  if ok and img then
    pane.image = img
    pcall(function()
      img:render()
    end)
  end
end

local function render_text(result)
  local lines = {}
  if has_image then
    lines[#lines + 1] = "" -- anchor row the thumbnail is drawn over
  end
  local title_idx = #lines
  lines[#lines + 1] = result.title or ""

  local meta = {}
  for _, field in ipairs({ result.channel, result.views, result.published, result.duration }) do
    if field and field ~= "" then
      meta[#meta + 1] = field
    end
  end
  local meta_idx = #lines
  lines[#lines + 1] = table.concat(meta, "  •  ")

  if result.description_snippet and result.description_snippet ~= "" then
    lines[#lines + 1] = ""
    lines[#lines + 1] = result.description_snippet
  end

  set_buf_lines(pane.buf, lines)
  if pane.buf and vim.api.nvim_buf_is_valid(pane.buf) then
    vim.api.nvim_buf_clear_namespace(pane.buf, ns, 0, -1)
    vim.api.nvim_buf_set_extmark(pane.buf, ns, title_idx, 0, { line_hl_group = "Title" })
    vim.api.nvim_buf_set_extmark(pane.buf, ns, meta_idx, 0, { line_hl_group = "Comment" })
  end
end

--- Show a result in the preview pane: text immediately, image once available.
--- Deduped by id, so repeat calls for the same video are cheap.
function M.update(result)
  if not (result and result.id) or pane.current_id == result.id then
    return
  end
  pane.current_id = result.id
  render_text(result)

  if not is_video_id(result.id) then
    clear_image() -- channels/playlists have no thumbnail; show text only
    return
  end

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
      if res.code == 0 and pane.current_id == result.id and vim.fn.filereadable(path) == 1 then
        render_image(path)
      end
    end,
  })
end

return M
