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
  section_filter = nil, -- nil = full home; else render only this section
  ns = vim.api.nvim_create_namespace("yt_home"),
}

-- Human labels for the section pages (winbar + headers).
local SECTION_LABELS = {
  recent = "Recently watched",
  pinned = "Pinned",
  installed = "Installed",
  playlists = "Playlists",
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

--- A trailing marker for a video row: a spinner while downloading, or the
--- installed icon once the local file exists. Empty otherwise.
local function marker(v)
  local icons = config.options.icons
  if require("yt.install").is_downloading(v.id) then
    return " " .. icons.downloading
  elseif store.is_installed(v.id) then
    return " " .. icons.installed
  end
  return ""
end

--- Rebuild `state.rows` and return the buffer lines. Row `i` maps to line `i`.
--- On the dashboard (no filter) each section is capped by config.home; on a
--- dedicated page (filter set) it's capped by config.pages instead.
local function build()
  local rows, lines = {}, {}
  local filter = state.section_filter
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
      (indent or "   ") .. " " .. ICON_VIDEO .. " " .. (v.title or v.id) .. marker(v)
    )
  end
  local function hint(text, indent)
    add({ kind = "hint" }, (indent or "     ") .. text)
  end
  local function blank()
    add({ kind = "blank" }, "")
  end
  -- `limit` items shown, then a "… and N more" line when truncated.
  local function more(total, limit, indent)
    if limit and total > limit then
      hint(("… and %d more"):format(total - limit), indent)
    end
  end

  -- A flat list section (recent / pinned / installed).
  local function list_section(label, section, items, empty_hint, limit)
    header(label, section)
    if #items == 0 then
      hint(empty_hint)
    else
      for i = 1, (limit and math.min(limit, #items) or #items) do
        video(items[i], section)
      end
      more(#items, limit)
    end
  end

  local function playlists_section(limit, item_limit)
    header("Playlists", "playlists")
    local lists = store.playlists()
    if #lists == 0 then
      hint("(press N to create one, or a on a video)")
      return
    end
    for i = 1, (limit and math.min(limit, #lists) or #lists) do
      local pl = lists[i]
      local exp = state.expanded[pl.name]
      add(
        { kind = "playlist", name = pl.name, count = #pl.items },
        "   " .. (exp and ICON_EXPANDED or ICON_COLLAPSED) .. " " .. pl.name .. " (" .. #pl.items .. ")"
      )
      if exp then
        for j = 1, (item_limit and math.min(item_limit, #pl.items) or #pl.items) do
          video(pl.items[j], "playlist", pl.name, "       ")
        end
        more(#pl.items, item_limit, "         ")
      end
    end
    more(#lists, limit)
  end

  -- One renderer per section; each takes its resolved limits.
  local renderers = {
    recent = function(cfg)
      list_section("Recently watched", "recent", store.history_list(), "(nothing yet — press s to search)", cfg.limit)
    end,
    pinned = function(cfg)
      list_section("Pinned", "pinned", store.pinned_list(), "(press p on a video to pin it)", cfg.limit)
    end,
    installed = function(cfg)
      list_section("Installed", "installed", store.installed_list(), "(press i on a video to download it)", cfg.limit)
    end,
    playlists = function(cfg)
      playlists_section(cfg.limit, cfg.items)
    end,
  }

  if filter then
    local render = renderers[filter]
    if render then
      render(config.options.pages[filter] or {})
    end
  else
    -- Separate sections with a single blank line (between, not trailing) so the
    -- spacing stays right whatever order `home.sections` puts them in.
    local first = true
    for _, section in ipairs(config.options.home.sections) do
      local render = renderers[section]
      if render then
        if not first then
          blank()
        end
        render(config.options.home[section] or {})
        first = false
      end
    end
  end

  state.rows = rows
  return lines
end

local function update_winbar()
  if not (state.list_win and vim.api.nvim_win_is_valid(state.list_win)) then
    return
  end
  if state.section_filter then
    local label = SECTION_LABELS[state.section_filter] or state.section_filter
    vim.wo[state.list_win].winbar = "  YouTube — " .. label .. "   ·   gh: home"
  else
    vim.wo[state.list_win].winbar = "  YouTube — Home"
  end
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
  update_winbar()
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

--- Render a single section as its own dedicated page.
function M.show_section(section)
  state.section_filter = section
  M.render()
  cursor_to_first_video()
end

--- Return to the full home view showing every section.
function M.show_home()
  state.section_filter = nil
  M.render()
  cursor_to_first_video()
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
  if v then
    require("yt.playlist_add").pick(v, refresh_keep_cursor)
  end
end

--- Download the video under the cursor for offline playback.
function M.action_install()
  local v = current_video()
  if v then
    require("yt.install").install(v, function()
      -- Fires immediately (spinner) and again on completion; both refresh.
      if M.is_open() then
        refresh_keep_cursor()
      end
    end)
  end
end

--- Create a new empty playlist.
function M.action_new_playlist()
  vim.ui.input({ prompt = "New playlist name: " }, function(name)
    if not (name and name ~= "") then
      return
    end
    if store.playlist_create(name) then
      state.expanded[name] = true
      refresh_keep_cursor()
    else
      vim.notify("yt.nvim: playlist already exists — " .. name, vim.log.levels.WARN)
    end
  end)
end

--- Blocking yes/no prompt; defaults to No. Returns true only on an explicit Yes.
local function confirm(prompt)
  return vim.fn.confirm(prompt, "&Yes\n&No", 2) == 1
end

--- Remove the item under the cursor from its section (context-dependent).
--- In the Installed section this uninstalls and deletes the local file.
--- Deleting a playlist, or removing a video from one, asks for confirmation.
function M.action_remove()
  local row = current_row()
  if not row then
    return
  end
  if row.kind == "playlist" then
    if not confirm(("Delete playlist %q (%d item%s)?"):format(row.name, row.count or 0, row.count == 1 and "" or "s")) then
      return
    end
    store.playlist_delete(row.name)
  elseif row.kind == "video" then
    if row.section == "pinned" then
      store.unpin(row.video.id)
    elseif row.section == "recent" then
      store.history_remove(row.video.id)
    elseif row.section == "installed" then
      store.uninstall(row.video.id, true)
    elseif row.section == "playlist" then
      if not confirm(("Remove %q from playlist %q?"):format(row.video.title or row.video.id, row.playlist)) then
        return
      end
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
  map(km.new_playlist, M.action_new_playlist)
  map(km.install, M.action_install)
  map(km.remove, M.action_remove)
  map(km.home, M.show_home)
  map(km.jump_recent, function()
    M.show_section("recent")
  end)
  map(km.jump_pinned, function()
    M.show_section("pinned")
  end)
  map(km.jump_installed, function()
    M.show_section("installed")
  end)
  map(km.jump_playlists, function()
    M.show_section("playlists")
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

  state.expanded = {}
  state.section_filter = nil
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
  state.section_filter = nil
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
