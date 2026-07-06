local config = require("yt.config")

local M = {}

local state = {
  open = false,
  left_win = nil,
  left_buf = nil,
  right_win = nil,
  right_buf = nil,
  results = {}, -- results[i] corresponds to line i in the left buffer
  preview_id = nil, -- id currently shown in the preview pane
  image = nil, -- current image.nvim handle
  ns = vim.api.nvim_create_namespace("yt_nvim"),
}

function M.state()
  return state
end

function M.is_open()
  return state.open
    and state.left_win
    and vim.api.nvim_win_is_valid(state.left_win)
    and state.right_win
    and vim.api.nvim_win_is_valid(state.right_win)
end

local function make_buf(ft)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = ft
  vim.bo[buf].modifiable = false
  return buf
end

function M.set_lines(buf, lines)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

function M.open()
  if M.is_open() then
    vim.api.nvim_set_current_win(state.left_win)
    return
  end

  vim.cmd("tabnew")
  local right = vim.api.nvim_get_current_win() -- becomes the preview pane
  vim.cmd("vsplit")
  local left = vim.api.nvim_get_current_win() -- new window, on the left

  state.left_buf = make_buf("ytresults")
  state.right_buf = make_buf("ytpreview")
  vim.api.nvim_win_set_buf(left, state.left_buf)
  vim.api.nvim_win_set_buf(right, state.right_buf)
  state.left_win, state.right_win = left, right

  pcall(vim.api.nvim_win_set_width, left, math.floor(vim.o.columns * (1 - config.options.preview_width)))

  for _, w in ipairs({ left, right }) do
    vim.wo[w].number = false
    vim.wo[w].relativenumber = false
    vim.wo[w].signcolumn = "no"
    vim.wo[w].list = false
  end
  vim.wo[left].wrap = false
  vim.wo[left].cursorline = true
  vim.wo[right].wrap = true

  state.results = {}
  state.preview_id = nil
  state.open = true

  M.set_lines(state.left_buf, { "  Type a search…" })
  M.setup_keymaps()
  M.setup_autocmds()
  vim.api.nvim_set_current_win(left)
end

function M.set_query(query)
  if state.left_win and vim.api.nvim_win_is_valid(state.left_win) then
    vim.wo[state.left_win].winbar = "  YouTube: " .. (query or "")
  end
end

local function format_result_line(r)
  return "  " .. (r.title or "")
end

--- Re-render the whole results list. Cheap for ~10 items and keeps line i == results[i].
function M.render_results()
  local lines = {}
  for i, r in ipairs(state.results) do
    lines[i] = format_result_line(r)
  end
  if #lines == 0 then
    lines = { "  Searching…" }
  end
  M.set_lines(state.left_buf, lines)
end

function M.current_result()
  if not (state.left_win and vim.api.nvim_win_is_valid(state.left_win)) then
    return nil
  end
  local line = vim.api.nvim_win_get_cursor(state.left_win)[1]
  return state.results[line]
end

function M.setup_keymaps()
  local km = config.options.keymaps
  local opts = { buffer = state.left_buf, nowait = true, silent = true }
  vim.keymap.set("n", km.play, function()
    local r = M.current_result()
    if r then
      require("yt.player").play(r)
    end
  end, opts)
  vim.keymap.set("n", km.search, function()
    require("yt").open()
  end, opts)
  vim.keymap.set("n", km.quit, function()
    M.close()
  end, opts)
end

function M.setup_autocmds()
  local grp = vim.api.nvim_create_augroup("yt_nvim", { clear = true })

  local on_move = require("yt.job").debounce(config.options.debounce_ms, function()
    if not M.is_open() or vim.api.nvim_get_current_win() ~= state.left_win then
      return
    end
    local r = M.current_result()
    if r and r.id ~= state.preview_id then
      require("yt.preview").update(r)
    end
  end)

  vim.api.nvim_create_autocmd("CursorMoved", {
    group = grp,
    buffer = state.left_buf,
    callback = on_move,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = grp,
    callback = function()
      if not (state.left_win and vim.api.nvim_win_is_valid(state.left_win)) then
        M.teardown()
      end
    end,
  })
end

--- Drop image + state without touching windows (windows already gone).
function M.teardown()
  if state.image then
    pcall(function()
      state.image:clear()
    end)
    state.image = nil
  end
  state.open = false
  state.results = {}
  state.preview_id = nil
end

--- User-invoked close: wipe our windows (buffers are bufhidden=wipe) then teardown.
function M.close()
  local wins = { state.right_win, state.left_win }
  M.teardown()
  for _, w in ipairs(wins) do
    if w and vim.api.nvim_win_is_valid(w) then
      pcall(vim.api.nvim_win_close, w, true)
    end
  end
end

return M
