-- dual-rail gutter: a statuscolumn function reading the active buffer's line map
-- map lookup is O(1); rail strings are pre-formatted at render time

local M = {}

---@type table<integer, string[]> -- bufnr -> pre-formatted rail string per lnum
local rails = {}

-- pre-format the gutter string for every line of a column from its map. pure, so
-- the statuscolumn callback only does an O(1) index per redraw (§11). a unified
-- column shows both rails (old left / new right); a side column shows only its
-- own number; absent sides and meta/filler rows render as blanks
---@param column dipher.Column
---@return string[]
function M.format(column)
    local lines = column.map.lines
    local wo, wn = 1, 1
    for _, l in ipairs(lines) do
        if l.old then
            wo = math.max(wo, #tostring(l.old))
        end
        if l.new then
            wn = math.max(wn, #tostring(l.new))
        end
    end
    local function cell(num, width)
        if not num then
            return string.rep(" ", width)
        end
        local s = tostring(num)
        return string.rep(" ", width - #s) .. s
    end
    local out = {}
    for i, l in ipairs(lines) do
        if column.side == "old" then
            out[i] = cell(l.old, wo) .. " "
        elseif column.side == "new" then
            out[i] = cell(l.new, wn) .. " "
        else
            out[i] = cell(l.old, wo) .. " " .. cell(l.new, wn) .. " "
        end
    end
    return out
end

-- store pre-formatted rail strings for a buffer after a render
---@param bufnr integer
---@param strings string[]
function M.set(bufnr, strings)
    rails[bufnr] = strings
end

-- drop a buffer's cached rail strings
---@param bufnr integer
function M.clear(bufnr)
    rails[bufnr] = nil
end

-- statuscolumn callback: return the rail string for the current line
---@return string
function M.render()
    local buf = vim.g.statusline_winid and vim.api.nvim_win_get_buf(vim.g.statusline_winid)
    local cache = buf and rails[buf]
    if not cache then
        return ""
    end
    return cache[vim.v.lnum] or ""
end

return M
