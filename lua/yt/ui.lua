local config = require("yt.config")

-- The results browser. A stack of "screens" (search / channel / playlist) share
-- one list window and the preview pane. Each screen streams a `yt` subcommand,
-- buckets the tagged NDJSON into sections (channels / videos / playlists), and
-- renders them. Opening a channel or playlist pushes a new screen; `back` pops.
local M = {}

local state = {
  open = false,
  results_win = nil,
  results_buf = nil,
  preview_win = nil,
  preview_buf = nil,
  stack = {}, -- screens; the last is the active one
  ns = vim.api.nvim_create_namespace("yt_nvim"),
}

-- Screens --------------------------------------------------------------------

local function screen()
  return state.stack[#state.stack]
end

--- A fresh screen descriptor. `sections` is the ordered list of section keys it
--- renders; `cmd` is the `yt` subcommand streamed to fill its buckets.
local function new_screen(kind, title, sections, cmd)
  return {
    kind = kind,
    title = title,
    sections = sections,
    cmd = cmd,
    channels = {},
    videos = {},
    playlists = {},
    page = 1,
    rows = {}, -- one descriptor per rendered line
    done = false,
  }
end

-- Pagination geometry (videos only) -----------------------------------------

local function per_page()
  return math.max(1, config.options.per_page or 10)
end

function M.page_count()
  local scr = screen()
  if not scr or #scr.videos == 0 then
    return 1
  end
  local pages = math.ceil(#scr.videos / per_page())
  return math.min(pages, config.options.max_pages or pages)
end

local function page_start(scr)
  return (scr.page - 1) * per_page() + 1
end

local function page_finish(scr)
  return math.min(page_start(scr) + per_page() - 1, #scr.videos)
end

-- Window plumbing ------------------------------------------------------------

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
  local rightmost = vim.api.nvim_get_current_win()
  vim.cmd("vsplit")
  local leftmost = vim.api.nvim_get_current_win()

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

  state.stack = {}
  state.open = true

  M.setup_keymaps()
  M.setup_autocmds()
  vim.api.nvim_set_current_win(results_win)
end

-- Rendering ------------------------------------------------------------------

--- A trailing marker for a video row (download spinner / installed icon).
local function marker(v)
  local install = require("yt.install")
  local store = require("yt.store")
  if install.is_downloading(v.id) then
    return " " .. config.options.icons.downloading
  elseif store.is_installed(v.id) then
    return " " .. config.options.icons.installed
  end
  return ""
end

--- Build `scr.rows` and the buffer lines for the active screen.
local function build(scr)
  local rows, lines = {}, {}
  local function add(row, text)
    rows[#rows + 1] = row
    lines[#lines + 1] = text
  end
  local function header(label)
    add({ kind = "header" }, "  " .. label)
  end
  local function hint(text)
    add({ kind = "hint" }, "     " .. text)
  end
  local function blank()
    add({ kind = "blank" }, "")
  end

  local renderers = {
    channels = function()
      if #scr.channels == 0 then
        return
      end
      header("Channels")
      local limit = config.options.search.channels.limit
      for i = 1, (limit and math.min(limit, #scr.channels) or #scr.channels) do
        local c = scr.channels[i]
        add({ kind = "channel", channel = c }, "   " .. config.options.icons.channel .. " " .. (c.title or c.id))
      end
      blank()
    end,
    videos = function()
      header("Videos")
      if #scr.videos == 0 then
        hint(scr.done and "(no videos)" or "Searching…")
      else
        for i = page_start(scr), page_finish(scr) do
          local v = scr.videos[i]
          add({ kind = "video", video = v }, "   " .. config.options.icons.video .. " " .. (v.title or v.id) .. marker(v))
        end
      end
      blank()
    end,
    playlists = function()
      if #scr.playlists == 0 then
        return
      end
      header("Playlists")
      for _, pl in ipairs(scr.playlists) do
        -- yt-dlp's flat extraction reports an unreliable playlist_count, so we
        -- render only the title rather than show a misleading number.
        add({ kind = "playlist", playlist = pl }, "   " .. config.options.icons.playlist .. " " .. (pl.title or pl.id))
      end
      blank()
    end,
  }

  for _, section in ipairs(scr.sections) do
    local render = renderers[section]
    if render then
      render()
    end
  end

  scr.rows = rows
  return lines
end

local function winbar(scr)
  local wb = "  " .. (scr.title or "")
  if #scr.videos > 0 and M.page_count() > 1 then
    wb = wb .. ("   ·   page %d/%d"):format(scr.page, M.page_count())
  end
  if #state.stack > 1 then
    wb = wb .. "   ·   <BS> back"
  end
  return wb
end

function M.render()
  local scr = screen()
  if not (scr and state.results_buf and vim.api.nvim_buf_is_valid(state.results_buf)) then
    return
  end
  M.set_lines(state.results_buf, build(scr))
  vim.api.nvim_buf_clear_namespace(state.results_buf, state.ns, 0, -1)
  for i, row in ipairs(scr.rows) do
    if row.kind == "header" then
      vim.api.nvim_buf_set_extmark(state.results_buf, state.ns, i - 1, 0, { line_hl_group = "Title" })
    elseif row.kind == "hint" then
      vim.api.nvim_buf_set_extmark(state.results_buf, state.ns, i - 1, 0, { line_hl_group = "Comment" })
    end
  end
  if state.results_win and vim.api.nvim_win_is_valid(state.results_win) then
    vim.wo[state.results_win].winbar = winbar(scr)
  end
end

-- Selection / preview --------------------------------------------------------

local function current_row()
  if not (state.results_win and vim.api.nvim_win_is_valid(state.results_win)) then
    return nil
  end
  local scr = screen()
  return scr and scr.rows[vim.api.nvim_win_get_cursor(state.results_win)[1]] or nil
end

--- The video under the cursor, or nil (used by pin/install/add/play).
function M.current_result()
  local row = current_row()
  return row and row.kind == "video" and row.video or nil
end

--- Preview the item under the cursor. Channels/playlists are shown as text
--- (their id isn't a video thumbnail id, so no image is fetched).
function M.preview_current()
  local row = current_row()
  if not row then
    return
  end
  local preview = require("yt.preview")
  if row.kind == "video" then
    preview.update(row.video)
  elseif row.kind == "channel" then
    local c = row.channel
    preview.update({ id = c.id, title = c.title, channel = c.handle, views = c.subscribers, description_snippet = c.description_snippet })
  elseif row.kind == "playlist" then
    local pl = row.playlist
    preview.update({ id = pl.id, title = pl.title, channel = pl.video_count })
  end
end

local function cursor_to_first_selectable()
  local scr = screen()
  for i, row in ipairs(scr.rows) do
    if row.kind == "video" or row.kind == "channel" or row.kind == "playlist" then
      pcall(vim.api.nvim_win_set_cursor, state.results_win, { i, 0 })
      M.preview_current()
      return
    end
  end
end

--- Warm the thumbnail cache for the current page's videos.
local function prefetch_page()
  local scr = screen()
  local preview = require("yt.preview")
  for i = page_start(scr), page_finish(scr) do
    preview.prefetch(scr.videos[i])
  end
end

-- Streaming ------------------------------------------------------------------

--- Stream `scr.cmd`, routing each tagged line into the screen's buckets and
--- re-rendering while the screen stays on top of the stack.
local function stream_screen(scr)
  local bin = config.bin_path()
  if not bin then
    vim.notify("yt.nvim: helper binary not found. Run :YtBuild to download or build it.", vim.log.levels.ERROR)
    return
  end
  local job = require("yt.job")
  local preview = require("yt.preview")
  local first_preview = true

  job.stream(scr.cmd, {
    on_line = function(line)
      local ok, obj = pcall(vim.json.decode, line)
      if not ok or type(obj) ~= "table" or not obj.id then
        return
      end
      if obj.kind == "channel" then
        scr.channels[#scr.channels + 1] = obj
      elseif obj.kind == "playlist" then
        scr.playlists[#scr.playlists + 1] = obj
      else -- "video" or untagged
        scr.videos[#scr.videos + 1] = obj
        if #scr.videos <= per_page() then
          preview.prefetch(obj)
        end
      end
      if screen() ~= scr then
        return -- user navigated away; keep filling buckets but don't touch the view
      end
      M.render()
      if first_preview then
        first_preview = false
        cursor_to_first_selectable()
      end
    end,
    on_exit = function()
      scr.done = true
      if screen() == scr then
        M.render()
      end
    end,
    stderr = function() end,
  })
end

--- Push a screen: reset the preview, render its loading state, and stream it.
local function push(scr)
  state.stack[#state.stack + 1] = scr
  require("yt.preview").attach(state.preview_win, state.preview_buf)
  M.render()
  pcall(vim.api.nvim_win_set_cursor, state.results_win, { 1, 0 })
  stream_screen(scr)
end

-- Entry points ---------------------------------------------------------------

--- Open (or reuse) the browser and run a search as the root screen.
function M.search(query)
  local home = require("yt.home")
  if home.is_open() then
    home.close()
  end
  if not M.is_open() then
    M.open()
  end

  local bin = config.bin_path()
  if not bin then
    vim.notify("yt.nvim: helper binary not found. Run :YtBuild to download or build it.", vim.log.levels.ERROR)
    return
  end
  local total = config.options.per_page * config.options.max_pages
  local cmd = { bin, "search", query, "--limit", tostring(total) }
  if not config.options.use_ytdlp_fallback then
    cmd[#cmd + 1] = "--no-fallback"
  end

  state.stack = {} -- a new search starts a fresh stack
  push(new_screen("search", "YouTube: " .. query, config.options.search.sections, cmd))
end

--- Open a channel's page (Videos + Playlists) as a new screen on the stack.
function M.open_channel(ch)
  local bin = config.bin_path()
  if not (bin and ch and ch.id) then
    return
  end
  local cmd = { bin, "channel", ch.id, "--limit", tostring(config.options.channel.fetch_limit) }
  push(new_screen("channel", "Channel: " .. (ch.title or ch.id), config.options.channel.sections, cmd))
end

--- Open a playlist's videos as a new screen on the stack.
function M.open_playlist(pl)
  local bin = config.bin_path()
  if not (bin and pl and pl.id) then
    return
  end
  local cmd = { bin, "playlist", pl.id, "--limit", tostring(config.options.channel.fetch_limit) }
  push(new_screen("playlist", "Playlist: " .. (pl.title or pl.id), { "videos" }, cmd))
end

--- <CR>: play a video, or open the channel/playlist under the cursor.
function M.activate()
  local row = current_row()
  if not row then
    return
  end
  if row.kind == "video" then
    require("yt.player").play(row.video)
  elseif row.kind == "channel" then
    M.open_channel(row.channel)
  elseif row.kind == "playlist" then
    M.open_playlist(row.playlist)
  end
end

--- Pop back to the previous screen; no-op on the root.
function M.back()
  if #state.stack <= 1 then
    return
  end
  state.stack[#state.stack] = nil
  require("yt.preview").attach(state.preview_win, state.preview_buf)
  M.render()
  cursor_to_first_selectable()
end

-- Pagination -----------------------------------------------------------------

function M.goto_page(n)
  local scr = screen()
  if not (M.is_open() and scr) then
    return
  end
  n = math.max(1, math.min(n, M.page_count()))
  if n == scr.page then
    return
  end
  scr.page = n
  M.render()
  prefetch_page()
  pcall(vim.api.nvim_win_set_cursor, state.results_win, { 1, 0 })
  cursor_to_first_selectable()
end

function M.next_page()
  local scr = screen()
  if scr then
    M.goto_page(scr.page + 1)
  end
end

function M.prev_page()
  local scr = screen()
  if scr then
    M.goto_page(scr.page - 1)
  end
end

-- Keymaps / autocmds ---------------------------------------------------------

function M.setup_keymaps()
  local km = config.options.keymaps
  local opts = { buffer = state.results_buf, nowait = true, silent = true }
  local function map(lhs, rhs)
    if lhs then
      vim.keymap.set("n", lhs, rhs, opts)
    end
  end
  map(km.play, M.activate)
  map(km.open, function()
    local r = M.current_result()
    if r then
      vim.ui.open(require("yt.player").url(r))
    end
  end)
  map(km.back, M.back)
  map(km.home, function()
    require("yt").open() -- closes the browser, opens the home screen
  end)
  map(km.search, function()
    require("yt.search").prompt()
  end)
  map(km.pin, function()
    local r = M.current_result()
    if r then
      local store = require("yt.store")
      local was = store.is_pinned(r.id)
      store.pinned_toggle(r)
      vim.notify("yt.nvim: " .. (was and "unpinned " or "pinned ") .. (r.title or r.id), vim.log.levels.INFO)
    end
  end)
  map(km.add_to_playlist, function()
    local r = M.current_result()
    if r then
      require("yt.playlist_add").pick(r, M.render)
    end
  end)
  map(km.install, function()
    local r = M.current_result()
    if r then
      require("yt.install").install(r, M.render)
    end
  end)
  map(km.quit, M.close)
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

-- Teardown -------------------------------------------------------------------

function M.teardown()
  require("yt.preview").detach()
  state.open = false
  state.stack = {}
end

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
