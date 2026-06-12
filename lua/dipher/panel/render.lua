-- panel rendering (pure): flatten section "blocks" of tree rows into buffer lines
-- plus per-line metadata. byte-column offsets for the status letter and names are
-- computed here so the runtime highlighter (panel/init.lua) and navigation read
-- authoritative positions rather than re-deriving them. no nvim API

local M = {}

local INDENT = "  "
local FOLD_OPEN, FOLD_CLOSED = "▾", "▸"

---@class dipher.panel.LineMeta
---@field kind "root"|"help"|"blank"|"header"|"dir"|"file"
---@field entry dipher.FileEntry|nil
---@field path string|nil
---@field status string|nil
---@field collapsed boolean|nil
---@field status_col integer|nil  -- byte col of the status letter (file rows)
---@field name_col integer|nil    -- byte col where the name starts
---@field icon_col integer|nil    -- byte range of the devicon glyph (when shown)
---@field icon_end integer|nil
---@field icon_hl string|nil      -- devicon highlight group
---@field add_col integer|nil     -- byte range of the +N count (file rows, when shown)
---@field add_end integer|nil
---@field del_col integer|nil     -- byte range of the -M count
---@field del_end integer|nil

---@class dipher.panel.Block
---@field title string|nil               -- section header, nil = no header row
---@field rows dipher.panel.Row[]

---@param rows dipher.panel.Row[]
---@return integer
local function count_files(rows)
    local n = 0
    for _, r in ipairs(rows) do
        if r.kind == "file" then
            n = n + 1
        end
    end
    return n
end

---@class dipher.panel.Header
---@field path string|nil   -- repo/worktree path shown on the top line
---@field help string|nil   -- keymap hint (rendered as "Help: <help>")

-- build the panel buffer lines and a parallel metadata list (one per line). an
-- optional header (repo path + `Help: g?` + blank) prefixes the sections (§8.6).
-- `icon_for(path)` (supplied by the runtime layer, nvim-web-devicons, so this
-- stays pure) returns a `(glyph, hl_group)` pair painted before each filename
---@param blocks dipher.panel.Block[]
---@param header dipher.panel.Header|nil
---@param icon_for nil|fun(path: string): string|nil, string|nil
---@return { lines: string[], meta: dipher.panel.LineMeta[] }
function M.lines(blocks, header, icon_for)
    local lines, meta = {}, {}
    if header then
        if header.path then
            lines[#lines + 1] = header.path
            meta[#meta + 1] = { kind = "root" }
        end
        if header.help then
            lines[#lines + 1] = "Help: " .. header.help
            meta[#meta + 1] = { kind = "help" }
        end
        lines[#lines + 1] = ""
        meta[#meta + 1] = { kind = "blank" }
    end
    for _, block in ipairs(blocks) do
        if block.title then
            lines[#lines + 1] = ("%s (%d)"):format(block.title, count_files(block.rows))
            meta[#meta + 1] = { kind = "header" }
        end
        for _, row in ipairs(block.rows) do
            local indent = INDENT:rep(row.depth)
            if row.kind == "dir" then
                local prefix = indent .. (row.collapsed and FOLD_CLOSED or FOLD_OPEN) .. " "
                lines[#lines + 1] = prefix .. row.name .. "/"
                meta[#meta + 1] =
                    { kind = "dir", path = row.path, collapsed = row.collapsed, name_col = #prefix }
            else
                local e = row.entry
                local prefix = indent .. e.status .. " "
                local m = {
                    kind = "file",
                    entry = e,
                    path = row.path,
                    status = e.status,
                    status_col = #indent,
                }
                if icon_for then
                    local glyph, hl = icon_for(e.path)
                    if glyph and glyph ~= "" then
                        m.icon_col = #prefix
                        m.icon_end = #prefix + #glyph
                        m.icon_hl = hl
                        prefix = prefix .. glyph .. " "
                    end
                end
                m.name_col = #prefix
                local line = prefix .. row.name
                if e.additions and (e.additions > 0 or e.deletions > 0) then
                    local add = ("+%d"):format(e.additions)
                    local del = ("-%d"):format(e.deletions)
                    m.add_col = #line + 2 -- after the two-space separator
                    m.add_end = m.add_col + #add
                    m.del_col = m.add_end + 1 -- after the single space
                    m.del_end = m.del_col + #del
                    line = line .. "  " .. add .. " " .. del
                end
                lines[#lines + 1] = line
                meta[#meta + 1] = m
            end
        end
    end
    return { lines = lines, meta = meta }
end

return M
