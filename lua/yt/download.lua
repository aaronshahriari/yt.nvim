local M = {}

local BIN = "yt"
local REPO = "aaronshahriari/yt.nvim"

local function plugin_root()
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then
    return src:sub(2):gsub("/lua/yt/download%.lua$", "")
  end
end

local function detect_platform()
  local uname = vim.uv.os_uname()
  local sys = uname.sysname:lower()
  local machine = uname.machine:lower()

  local os_name
  if sys == "darwin" then
    os_name = "macos"
  elseif sys == "linux" then
    os_name = "linux"
  else
    return nil, "unsupported OS: " .. uname.sysname
  end

  local arch
  if machine == "x86_64" or machine == "amd64" then
    arch = "x86_64"
  elseif machine == "aarch64" or machine == "arm64" then
    arch = "aarch64"
  else
    return nil, "unsupported architecture: " .. uname.machine
  end

  return arch .. "-" .. os_name
end

local function latest_release_tag()
  local r = vim.system({
    "curl", "--fail", "--silent", "--show-error",
    "--header", "Accept: application/vnd.github.v3+json",
    ("https://api.github.com/repos/%s/releases/latest"):format(REPO),
  }, { text = true }):wait()
  if r.code ~= 0 then
    return nil, "GitHub API request failed: " .. (r.stderr or "")
  end
  local tag = r.stdout:match('"tag_name"%s*:%s*"(v[^"]+)"')
  if not tag then
    return nil, "no releases found on GitHub"
  end
  return tag
end

-- Download a pre-built binary from GitHub Releases.
-- Returns nil on success, or an error string on failure.
local function try_download(root)
  local platform, err = detect_platform()
  if not platform then
    return err
  end

  local version, verr = latest_release_tag()
  if not version then
    return verr
  end

  local dest = root .. "/bin/" .. BIN
  local dest_tmp = dest .. ".tmp"
  local url = ("https://github.com/%s/releases/download/%s/%s-%s"):format(REPO, version, BIN, platform)

  vim.fn.mkdir(root .. "/bin", "p")

  local r = vim.system({
    "curl", "--fail", "--location", "--silent", "--show-error",
    "--output", dest_tmp, url,
  }, { text = true }):wait()

  if r.code ~= 0 then
    vim.fn.delete(dest_tmp)
    return ("curl failed (HTTP error or network issue): %s"):format(r.stderr or "")
  end

  vim.fn.system({ "chmod", "+x", dest_tmp })

  local ok, rename_err = os.rename(dest_tmp, dest)
  if not ok then
    vim.fn.delete(dest_tmp)
    return "rename failed: " .. (rename_err or "")
  end

  return nil
end

-- Build from source via cargo, then stage the binary at bin/yt.
-- Returns nil on success, or an error string on failure.
local function try_build(root)
  if vim.fn.executable("cargo") ~= 1 then
    return "cargo not found on PATH"
  end
  local r = vim.system({ "cargo", "build", "--release" }, { cwd = root, text = true }):wait()
  if r.code ~= 0 then
    return "build failed:\n" .. (r.stderr or "")
  end
  vim.fn.mkdir(root .. "/bin", "p")
  local cp = vim.system(
    { "cp", root .. "/target/release/" .. BIN, root .. "/bin/" .. BIN },
    { text = true }
  ):wait()
  if cp.code ~= 0 then
    return "copy failed: " .. (cp.stderr or "")
  end
  return nil
end

-- Try downloading a pre-built binary from GitHub Releases; fall back to a cargo build.
-- Runs synchronously (suspends coroutine, does not block the event loop).
function M.download_or_build()
  local root = plugin_root()
  if not root then
    vim.notify("yt.nvim: cannot determine plugin root", vim.log.levels.ERROR)
    return
  end

  vim.notify("yt.nvim: downloading binary...", vim.log.levels.INFO)
  local dl_err = try_download(root)

  if not dl_err then
    vim.notify("yt.nvim: binary downloaded", vim.log.levels.INFO)
    return
  end

  vim.notify(
    ("yt.nvim: download skipped (%s) — building from source..."):format(dl_err),
    vim.log.levels.WARN
  )

  local build_err = try_build(root)
  if build_err then
    vim.notify("yt.nvim: " .. build_err, vim.log.levels.ERROR)
  else
    vim.notify("yt.nvim: binary built from source", vim.log.levels.INFO)
  end
end

-- Check if the binary exists; download only if missing. Safe to call every startup.
function M.ensure_binary()
  local root = plugin_root()
  if not root then
    return
  end
  if vim.fn.filereadable(root .. "/bin/" .. BIN) == 1 then
    return
  end
  M.download_or_build()
end

return M
