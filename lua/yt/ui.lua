local config = require("yt.config")

local M = {}

local state = {
  open = false,
  results_win = nil,
  results_buf = nil,
  preview_win = nil,
  preview_buf = nil,
  results = {}, -- all fetched results (across pages)
  page = 1, -- 1-based current page
  query = "", -- current query (shown in the winbar)
  preview_id = nil, -- id currently shown in the preview pane
  image = nil, -- current image.nvim handle
  ns = vim.api.nvim_create_namespace("yt_nvim"),
}

-- Pagination geometry -------------------------------------------------------

local function per_page()
  return math.max(1, config.options.per_page or 10)
end

--- Number of pages currently available, capped by `max_pages`.
function M.page_count()
  if #state.results == 0 then
    return 1
  end
  local pages = math.ceil(#state.results / per_page())
  return math.min(pages, config.options.max_pages or pages)
end

local function page_start()
  return (state.page - 1) * per_page() + 1
end

local function page_finish()
  return math.min(page_start() + per_page() - 1, #state.results)
end

function M.state()
  return state
end

function M.is_open()
  return state.open
    and state.results_win
    and vim.api.nvim_win_is_valid(state.results_win)
    and state.preview_win
    and vim.api.nvim_win_is_valid(state.preview_win)
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
    vim.api.nvim_set_current_win(state.results_win)
    return
  end

  vim.cmd("tabnew")
  local rightmost = vim.api.nvim_get_current_win() -- stays on the right after vsplit
  vim.cmd("vsplit")
  local leftmost = vim.api.nvim_get_current_win() -- new window, on the left

  -- Place results/preview per config; the other pane fills the opposite side.
  local results_win, preview_win = leftmost, rightmost
  if config.options.results_side == "right" then
    results_win, preview_win = rightmost, leftmost
  end

  state.results_buf = make_buf("ytresults")
  state.preview_buf = make_buf("ytpreview")
  vim.api.nvim_win_set_buf(results_win, state.results_buf)
  vim.api.nvim_win_set_buf(preview_win, state.preview_buf)
  state.results_win, state.preview_win = results_win, preview_win
  require("yt.preview").attach(preview_win, state.preview_buf)

  pcall(vim.api.nvim_win_set_width, preview_win, math.floor(vim.o.columns * config.options.preview_width))

  for _, w in ipairs({ results_win, preview_win }) do
    vim.wo[w].number = false
    vim.wo[w].relativenumber = false
    vim.wo[w].signcolumn = "no"
    vim.wo[w].list = false
  end
  vim.wo[results_win].wrap = false
  vim.wo[results_win].cursorline = true
  vim.wo[preview_win].wrap = true

  state.results = {}
  state.page = 1
  state.query = ""
  state.preview_id = nil
  state.open = true

  M.set_lines(state.results_buf, { "  Type a search…" })
  M.setup_keymaps()
  M.setup_autocmds()
  vim.api.nvim_set_current_win(results_win)
end

function M.update_winbar()
  if not (state.results_win and vim.api.nvim_win_is_valid(state.results_win)) then
    return
  end
  local wb = "  YouTube: " .. (state.query or "")
  if #state.results > 0 then
    wb = wb .. ("   ·   page %d/%d"):format(state.page, M.page_count())
  end
  vim.wo[state.results_win].winbar = wb
end

function M.set_query(query)
  state.query = query or ""
  M.update_winbar()
end

local function format_result_line(r)
  return "  " .. (r.title or "")
end

--- Render only the current page's slice; line i maps to results[page_start()+i-1].
function M.render_results()
  local lines = {}
  if #state.results == 0 then
    lines = { "  Searching…" }
  else
    for i = page_start(), page_finish() do
      lines[#lines + 1] = format_result_line(state.results[i])
    end
  end
  M.set_lines(state.results_buf, lines)
  M.update_winbar()
end

function M.current_result()
  if not (state.results_win and vim.api.nvim_win_is_valid(state.results_win)) then
    return nil
  end
  local row = vim.api.nvim_win_get_cursor(state.results_win)[1]
  return state.results[page_start() + row - 1]
end

function M.preview_current()
  local r = M.current_result()
  if r then
    require("yt.preview").update(r)
  end
end

local function add_to_playlist(video)
  local store = require("yt.store")
  local choices = vim.list_extend({ "New playlist..." }, store.playlist_names())
  vim.ui.select(choices, { prompt = "Add to playlist:" }, function(choice)
    if not choice then
      return
    end
    if choice == "New playlist..." then
      vim.ui.input({ prompt = "New playlist name: " }, function(name)
        if name and name ~= "" then
          store.playlist_add(name, video)
          vim.notify("yt.nvim: added to " .. name, vim.log.levels.INFO)
        end
      end)
    else
      store.playlist_add(choice, video)
      vim.notify("yt.nvim: added to " .. choice, vim.log.levels.INFO)
    end
  end)
end

--- Warm the thumbnail cache for the current page's results.
function M.prefetch_page()
  local preview = require("yt.preview")
  for i = page_start(), page_finish() do
    preview.prefetch(state.results[i])
  end
end

--- Switch pages (clamped). Resets the cursor to the top and previews it.
function M.goto_page(n)
  if not M.is_open() then
    return
  end
  n = math.max(1, math.min(n, M.page_count()))
  if n == state.page then
    return
  end
  state.page = n
  M.render_results()
  M.prefetch_page()
  pcall(vim.api.nvim_win_set_cursor, state.results_win, { 1, 0 })
  M.preview_current()
end

function M.next_page()
  M.goto_page(state.page + 1)
end

function M.prev_page()
  M.goto_page(state.page - 1)
end

function M.setup_keymaps()
  local km = config.options.keymaps
  local opts = { buffer = state.results_buf, nowait = true, silent = true }
  -- Each default is skippable: set the keymap entry to false/nil to drop it.
  local function map(lhs, rhs)
    if lhs then
      vim.keymap.set("n", lhs, rhs, opts)
    end
  end
  map(km.play, function()
    local r = M.current_result()
    if r then
      require("yt.player").play(r)
    end
  end)
  map(km.search, function()
    require("yt.search").prompt()
  end)
  map(km.pin, function()
    local r = M.current_result()
    if r then
      local store = require("yt.store")
      local was_pinned = store.is_pinned(r.id)
      store.pinned_toggle(r)
      vim.notify(
        "yt.nvim: " .. (was_pinned and "unpinned " or "pinned ") .. (r.title or r.id),
        vim.log.levels.INFO
      )
    end
  end)
  map(km.add_to_playlist, function()
    local r = M.current_result()
    if r then
      add_to_playlist(r)
    end
  end)
  map(km.install, function()
    local r = M.current_result()
    if r then
      require("yt.install").install(r)
    end
  end)
  map(km.home, function()
    require("yt").open() -- closes search, opens the home screen
  end)
  map(km.quit, function()
    M.close()
  end)
  map(km.page_next, M.next_page)
  map(km.page_prev, M.prev_page)
end

function M.setup_autocmds()
  local grp = vim.api.nvim_create_augroup("yt_nvim", { clear = true })

  local on_move = require("yt.job").debounce(config.options.debounce_ms, function()
    if not M.is_open() or vim.api.nvim_get_current_win() ~= state.results_win then
      return
    end
    M.preview_current()
  end)

  vim.api.nvim_create_autocmd("CursorMoved", {
    group = grp,
    buffer = state.results_buf,
    callback = on_move,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = grp,
    callback = function()
      if not (state.results_win and vim.api.nvim_win_is_valid(state.results_win)) then
        M.teardown()
      end
    end,
  })
end

--- Drop image + state without touching windows (windows already gone).
function M.teardown()
  require("yt.preview").detach()
  state.open = false
  state.results = {}
  state.page = 1
  state.query = ""
  state.preview_id = nil
end

--- User-invoked close: wipe our windows (buffers are bufhidden=wipe) then teardown.
function M.close()
  local wins = { state.preview_win, state.results_win }
  M.teardown()
  for _, w in ipairs(wins) do
    if w and vim.api.nvim_win_is_valid(w) then
      pcall(vim.api.nvim_win_close, w, true)
    end
  end
end

return M
