local M = {}

--- Run a command asynchronously, invoking `on_line` for each newline-delimited
--- stdout line (on the main loop) and `on_exit` with the result when finished.
--- Returns the vim.system handle.
function M.stream(cmd, opts)
  opts = opts or {}
  local pending = ""

  local function emit(line)
    if line ~= "" and opts.on_line then
      vim.schedule(function()
        opts.on_line(line)
      end)
    end
  end

  return vim.system(cmd, {
    text = true,
    stdout = function(err, data)
      if err or not data then
        return
      end
      pending = pending .. data
      while true do
        local nl = pending:find("\n", 1, true)
        if not nl then
          break
        end
        emit(pending:sub(1, nl - 1))
        pending = pending:sub(nl + 1)
      end
    end,
    stderr = opts.stderr,
  }, function(res)
    emit(pending)
    if opts.on_exit then
      vim.schedule(function()
        opts.on_exit(res)
      end)
    end
  end)
end

--- Trailing debounce: returns a function that defers `fn` until `ms` after the
--- last call. Later calls cancel the pending one.
function M.debounce(ms, fn)
  local timer
  return function(...)
    local args = { ... }
    if timer then
      timer:stop()
    end
    timer = vim.defer_fn(function()
      timer = nil
      fn(unpack(args))
    end, ms)
  end
end

return M
