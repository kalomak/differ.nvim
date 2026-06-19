-- window helpers, runtime-only (uses the nvim API)

local M = {}

-- set a window-local option without disturbing the global default. plain
-- `vim.wo[win].opt = v` omits scope, so it sets the global value too (like :set,
-- not :setlocal), which leaks a window's dressing (gutter, folds, cursorline) onto
-- every other window in the session
---@param win integer
---@param opt string
---@param val any
function M.set_local(win, opt, val)
    vim.api.nvim_set_option_value(opt, val, { scope = "local", win = win })
end

return M
