local config = require("yt.config")

-- Persistent state for the home screen: recently watched, pinned videos, and
-- user-defined playlists. Each is a JSON file under stdpath("data")/yt.nvim/.
local M = {}

local FIELDS = {
  "id",
  "title",
  "channel",
  "duration",
  "duration_secs",
  "views",
  "published",
  "description_snippet",
}

--- Keep only the fields we render, so stored entries stay small and stable.
local function clean(video)
  local out = {}
  for _, k in ipairs(FIELDS) do
    out[k] = video[k]
  end
  return out
end

local function dir()
  local d = vim.fn.stdpath("data") .. "/yt.nvim"
  vim.fn.mkdir(d, "p")
  return d
end

local function read(name, default)
  local path = dir() .. "/" .. name
  if vim.fn.filereadable(path) ~= 1 then
    return default
  end
  local ok, data = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
  end)
  if ok and type(data) == "table" then
    return data
  end
  return default
end

local function write(name, data)
  vim.fn.writefile({ vim.json.encode(data) }, dir() .. "/" .. name)
end

local function index_of(list, id)
  for i, v in ipairs(list) do
    if v.id == id then
      return i
    end
  end
end

-- Recently watched ----------------------------------------------------------

function M.history_list()
  return read("history.json", {})
end

--- Record a play: move to the front, dedupe by id, cap to `history_limit`.
function M.history_add(video)
  if not (video and video.id) then
    return
  end
  local h = M.history_list()
  local existing = index_of(h, video.id)
  if existing then
    table.remove(h, existing)
  end
  table.insert(h, 1, clean(video))
  local cap = config.options.history_limit or 30
  while #h > cap do
    table.remove(h)
  end
  write("history.json", h)
end

function M.history_remove(id)
  local h = M.history_list()
  local i = index_of(h, id)
  if i then
    table.remove(h, i)
    write("history.json", h)
  end
end

-- Pinned --------------------------------------------------------------------

function M.pinned_list()
  return read("pinned.json", {})
end

function M.is_pinned(id)
  return index_of(M.pinned_list(), id) ~= nil
end

function M.pin(video)
  if not (video and video.id) then
    return
  end
  local p = M.pinned_list()
  if not index_of(p, video.id) then
    table.insert(p, clean(video))
    write("pinned.json", p)
  end
end

function M.unpin(id)
  local p = M.pinned_list()
  local i = index_of(p, id)
  if i then
    table.remove(p, i)
    write("pinned.json", p)
  end
end

function M.pinned_toggle(video)
  if M.is_pinned(video.id) then
    M.unpin(video.id)
  else
    M.pin(video)
  end
end

-- Installed (locally downloaded videos) -------------------------------------

function M.installed_list()
  return read("installed.json", {})
end

function M.is_installed(id)
  return index_of(M.installed_list(), id) ~= nil
end

--- Absolute path to the downloaded file for `id`, or nil.
function M.installed_path(id)
  local list = M.installed_list()
  local i = index_of(list, id)
  return i and list[i].path or nil
end

--- Record a downloaded video (front of the list, deduped by id).
function M.install_add(video, path)
  if not (video and video.id) then
    return
  end
  local list = M.installed_list()
  if not index_of(list, video.id) then
    local entry = clean(video)
    entry.path = path
    table.insert(list, 1, entry)
    write("installed.json", list)
  end
end

--- Drop the installed record; delete the file too when `delete_file`.
function M.uninstall(id, delete_file)
  local list = M.installed_list()
  local i = index_of(list, id)
  if i then
    local path = list[i].path
    table.remove(list, i)
    write("installed.json", list)
    if delete_file and path and path ~= "" then
      vim.fn.delete(path)
    end
  end
end

-- Playlists (named local lists of videos) -----------------------------------

function M.playlists()
  return read("playlists.json", {})
end

function M.playlist_names()
  local names = {}
  for _, pl in ipairs(M.playlists()) do
    names[#names + 1] = pl.name
  end
  return names
end

local function playlist_index(list, name)
  for i, pl in ipairs(list) do
    if pl.name == name then
      return i
    end
  end
end

--- Create an empty playlist. Returns true if created, false if the name is
--- blank or already taken.
function M.playlist_create(name)
  if not (name and name ~= "") then
    return false
  end
  local lists = M.playlists()
  if playlist_index(lists, name) then
    return false
  end
  table.insert(lists, { name = name, items = {} })
  write("playlists.json", lists)
  return true
end

--- Add a video to a playlist, creating the playlist if it doesn't exist.
function M.playlist_add(name, video)
  if not (name and name ~= "" and video and video.id) then
    return
  end
  local lists = M.playlists()
  local i = playlist_index(lists, name)
  if not i then
    table.insert(lists, { name = name, items = {} })
    i = #lists
  end
  local pl = lists[i]
  if not index_of(pl.items, video.id) then
    table.insert(pl.items, clean(video))
    write("playlists.json", lists)
  end
end

function M.playlist_remove_video(name, id)
  local lists = M.playlists()
  local i = playlist_index(lists, name)
  if not i then
    return
  end
  local j = index_of(lists[i].items, id)
  if j then
    table.remove(lists[i].items, j)
    write("playlists.json", lists)
  end
end

function M.playlist_delete(name)
  local lists = M.playlists()
  local i = playlist_index(lists, name)
  if i then
    table.remove(lists, i)
    write("playlists.json", lists)
  end
end

return M
