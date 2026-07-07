local config = require("yt.config")
local store = require("yt.store")

-- The home screen: a sectioned dashboard (Recently watched / Pinned / Playlists)
-- in the left pane, with the shared preview pane on the right. Reuses yt.preview.
local M = {}

local ICON_VIDEO = "●"
local ICON_COLLAPSED = "▸"
local ICON_EXPANDED = "▾"

local state = {
  open = false,
  list_win = nil,
  list_buf = nil,
  preview_win = nil,
  preview_buf = nil,
  rows = {}, -- one row descriptor per buffer line
  expanded = {}, -- playlist name -> bool
  ns = vim.api.nvim_create_namespace("yt_home"),
}

function M.is_open()
  return state.open
    and state.list_win
    and vim.api.nvim_win_is_valid(state.list_win)
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

local function set_lines(buf, lines)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

-- Build rows + lines ---------------------------------------------------------

--- Rebuild `state.rows` and return the buffer lines. Row `i` maps to line `i`.
local function build()
  local rows, lines = {}, {}
  local function add(row, text)
    rows[#rows + 1] = row
    lines[#lines + 1] = text
  end
  local function header(label, section)
    add({ kind = "header", section = section }, "  " .. label)
  end
  local function video(v, section, playlist, indent)
    add(
      { kind = "video", video = v, section = section, playlist = playlist },
      (indent or "   ") .. " " .. ICON_VIDEO .. " " .. (v.title or v.id)
    )
  end
  local function hint(text)
    add({ kind = "hint" }, "     " .. text)
  end
  local function blank()
    add({ kind = "blank" }, "")
  end

  header("Recently watched", "recent")
  local recent = store.history_list()
  if #recent == 0 then
    hint("(nothing yet — press s to search)")
  else
    for _, v in ipairs(recent) do
      video(v, "recent")
    end
  end
  blank()

  header("Pinned", "pinned")
  local pinned = store.pinned_list()
  if #pinned == 0 then
    hint("(press p on a video to pin it)")
  else
    for _, v in ipairs(pinned) do
      video(v, "pinned")
    end
  end
  blank()

  header("Playlists", "playlists")
  local playlists = store.playlists()
  if #playlists == 0 then
    hint("(press a on a video to start one)")
  else
    for _, pl in ipairs(playlists) do
      local exp = state.expanded[pl.name]
      add(
        { kind = "playlist", name = pl.name },
        "   " .. (exp and ICON_EXPANDED or ICON_COLLAPSED) .. " " .. pl.name .. " (" .. #pl.items .. ")"
      )
      if exp then
        for _, v in ipairs(pl.items) do
          video(v, "playlist", pl.name, "       ")
        end
      end
    end
  end

  state.rows = rows
  return lines
end

function M.render()
  set_lines(state.list_buf, build())
  vim.api.nvim_buf_clear_namespace(state.list_buf, state.ns, 0, -1)
  for i, row in ipairs(state.rows) do
    if row.kind == "header" then
      vim.api.nvim_buf_set_extmark(state.list_buf, state.ns, i - 1, 0, { line_hl_group = "Title" })
    elseif row.kind == "hint" then
      vim.api.nvim_buf_set_extmark(state.list_buf, state.ns, i - 1, 0, { line_hl_group = "Comment" })
    end
  end
end

-- Cursor / selection ---------------------------------------------------------

local function current_row()
  if not (state.list_win and vim.api.nvim_win_is_valid(state.list_win)) then
    return nil
  end
  return state.rows[vim.api.nvim_win_get_cursor(state.list_win)[1]]
end

local function current_video()
  local row = current_row()
  return row and row.kind == "video" and row.video or nil
end

function M.preview_current()
  local v = current_video()
  if v then
    require("yt.preview").update(v)
  end
end

local function refresh_keep_cursor()
  local pos = vim.api.nvim_win_get_cursor(state.list_win)
  M.render()
  pos[1] = math.min(pos[1], vim.api.nvim_buf_line_count(state.list_buf))
  pcall(vim.api.nvim_win_set_cursor, state.list_win, pos)
end

--- Put the cursor on the first video row and preview it.
local function cursor_to_first_video()
  for i, row in ipairs(state.rows) do
    if row.kind == "video" then
      pcall(vim.api.nvim_win_set_cursor, state.list_win, { i, 0 })
      M.preview_current()
      return
    end
  end
end

local function jump_to_section(section)
  for i, row in ipairs(state.rows) do
    if row.kind == "header" and row.section == section then
      pcall(vim.api.nvim_win_set_cursor, state.list_win, { i, 0 })
      return
    end
  end
end

-- Actions --------------------------------------------------------------------

--- <CR>: play a video (records history) or toggle a playlist's expansion.
function M.action_play()
  local row = current_row()
  if not row then
    return
  end
  if row.kind == "playlist" then
    state.expanded[row.name] = not state.expanded[row.name]
    refresh_keep_cursor()
  elseif row.kind == "video" then
    require("yt.player").play(row.video)
    M.render() -- the played video jumps to the top of "Recently watched"
    cursor_to_first_video()
  end
end

function M.action_pin()
  local v = current_video()
  if v then
    store.pinned_toggle(v)
    refresh_keep_cursor()
  end
end

function M.action_add_to_playlist()
  local v = current_video()
  if not v then
    return
  end
  local choices = vim.list_extend({ "New playlist..." }, store.playlist_names())
  vim.ui.select(choices, { prompt = "Add to playlist:" }, function(choice)
    if not choice then
      return
    end
    if choice == "New playlist..." then
      vim.ui.input({ prompt = "New playlist name: " }, function(name)
        if name and name ~= "" then
          store.playlist_add(name, v)
          refresh_keep_cursor()
        end
      end)
    else
      store.playlist_add(choice, v)
      refresh_keep_cursor()
    end
  end)
end

--- Remove the item under the cursor from its section (context-dependent).
function M.action_remove()
  local row = current_row()
  if not row then
    return
  end
  if row.kind == "playlist" then
    store.playlist_delete(row.name)
  elseif row.kind == "video" then
    if row.section == "pinned" then
      store.unpin(row.video.id)
    elseif row.section == "recent" then
      store.history_remove(row.video.id)
    elseif row.section == "playlist" then
      store.playlist_remove_video(row.playlist, row.video.id)
    end
  else
    return
  end
  refresh_keep_cursor()
end

function M.action_search()
  M.close()
  require("yt.search").prompt()
end

-- Lifecycle ------------------------------------------------------------------

function M.setup_keymaps()
  local km = config.options.home_keymaps
  local opts = { buffer = state.list_buf, nowait = true, silent = true }
  local function map(lhs, fn)
    if lhs then
      vim.keymap.set("n", lhs, fn, opts)
    end
  end
  map(km.play, M.action_play)
  map(km.search, M.action_search)
  map(km.pin, M.action_pin)
  map(km.add_to_playlist, M.action_add_to_playlist)
  map(km.remove, M.action_remove)
  map(km.jump_recent, function()
    jump_to_section("recent")
  end)
  map(km.jump_pinned, function()
    jump_to_section("pinned")
  end)
  map(km.jump_playlists, function()
    jump_to_section("playlists")
  end)
  map(km.quit, M.close)
end

function M.setup_autocmds()
  local grp = vim.api.nvim_create_augroup("yt_nvim_home", { clear = true })

  local on_move = require("yt.job").debounce(config.options.debounce_ms, function()
    if not M.is_open() or vim.api.nvim_get_current_win() ~= state.list_win then
      return
    end
    M.preview_current()
  end)

  vim.api.nvim_create_autocmd("CursorMoved", {
    group = grp,
    buffer = state.list_buf,
    callback = on_move,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = grp,
    callback = function()
      if not (state.list_win and vim.api.nvim_win_is_valid(state.list_win)) then
        M.teardown()
      end
    end,
  })
end

function M.open()
  if M.is_open() then
    M.render()
    vim.api.nvim_set_current_win(state.list_win)
    return
  end

  vim.cmd("tabnew")
  local rightmost = vim.api.nvim_get_current_win()
  vim.cmd("vsplit")
  local leftmost = vim.api.nvim_get_current_win()

  local list_win, preview_win = leftmost, rightmost
  if config.options.results_side == "right" then
    list_win, preview_win = rightmost, leftmost
  end

  state.list_buf = make_buf("ythome")
  state.preview_buf = make_buf("ytpreview")
  vim.api.nvim_win_set_buf(list_win, state.list_buf)
  vim.api.nvim_win_set_buf(preview_win, state.preview_buf)
  state.list_win, state.preview_win = list_win, preview_win

  pcall(vim.api.nvim_win_set_width, preview_win, math.floor(vim.o.columns * config.options.preview_width))

  for _, w in ipairs({ list_win, preview_win }) do
    vim.wo[w].number = false
    vim.wo[w].relativenumber = false
    vim.wo[w].signcolumn = "no"
    vim.wo[w].list = false
  end
  vim.wo[list_win].wrap = false
  vim.wo[list_win].cursorline = true
  vim.wo[preview_win].wrap = true
  vim.wo[list_win].winbar = "  YouTube — Home"

  state.expanded = {}
  state.open = true
  require("yt.preview").attach(preview_win, state.preview_buf)

  M.render()
  M.setup_keymaps()
  M.setup_autocmds()
  vim.api.nvim_set_current_win(list_win)
  cursor_to_first_video()
end

--- Drop preview + state without touching windows (windows already gone).
function M.teardown()
  require("yt.preview").detach()
  state.open = false
  state.rows = {}
  state.expanded = {}
end

function M.close()
  local wins = { state.preview_win, state.list_win }
  M.teardown()
  for _, w in ipairs(wins) do
    if w and vim.api.nvim_win_is_valid(w) then
      pcall(vim.api.nvim_win_close, w, true)
    end
  end
end

return M
