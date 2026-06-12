-- Shared text helpers, pure Lua, no Neovim API

local M = {}

-- Split text into lines, tolerating a missing trailing newline.
-- A terminating newline does not yield a trailing empty line; an unterminated
-- final line is kept. Pure so renderers stay golden-testable without Neovim.
---@param text string
---@return string[]
function M.to_lines(text)
    if text == "" then
        return {}
    end
    local lines = {}
    local start = 1
    while true do
        local nl = text:find("\n", start, true)
        if nl then
            lines[#lines + 1] = text:sub(start, nl - 1)
            start = nl + 1
        else
            local rest = text:sub(start)
            if rest ~= "" then
                lines[#lines + 1] = rest
            end
            break
        end
    end
    return lines
end

-- vim.text.diff is line-oriented; an unterminated final line reads as changed,
-- so normalise to newline-terminated before diffing
---@param text string
---@return string
function M.ensure_trailing_nl(text)
    if text == "" or text:sub(-1) == "\n" then
        return text
    end
    return text .. "\n"
end

return M
