-- pure parser for git conflict markers in a working-tree file (§8.5). no nvim API,
-- so it runs under test/unit. recognises the default `merge` style (ours/theirs only)
-- and `diff3`/`zdiff3` (a base slab between ||||||| and =======). marker lines are
-- matched on their leading 7-char run, the ref label after them ignored

---@class dipher.merge.Region
---@field index integer         -- 1-based, conflict order in the file
---@field result_start integer  -- line of the `<<<<<<<` marker (1-based)
---@field result_end integer    -- line of the `>>>>>>>` marker
---@field ours string[]         -- ours slab (<<<<<<< .. ||||||| / =======)
---@field base string[]|nil     -- base slab (||||||| .. =======), nil under default style
---@field theirs string[]       -- theirs slab (======= .. >>>>>>>)

local M = {}

---@param line string
---@param ch string  -- the marker char
---@return boolean
local function marker(line, ch)
    return line:sub(1, 7) == ch:rep(7)
end

-- parse line-split file content into ordered conflict regions. an unterminated region
-- (EOF before `>>>>>>>`, which git never emits) is discarded rather than half-emitted,
-- and a stray `<<<<<<<` inside a region counts as content (markers don't nest)
---@param lines string[]
---@return dipher.merge.Region[]
function M.parse(lines)
    local regions = {}
    local cur, slot
    for lnum, line in ipairs(lines) do
        if not cur then
            if marker(line, "<") then
                cur = { result_start = lnum, ours = {}, theirs = {} }
                slot = "ours"
            end
        elseif slot == "ours" and marker(line, "|") then
            cur.base = {}
            slot = "base"
        elseif (slot == "ours" or slot == "base") and marker(line, "=") then
            slot = "theirs"
        elseif slot == "theirs" and marker(line, ">") then
            cur.result_end = lnum
            cur.index = #regions + 1
            regions[#regions + 1] = cur
            cur, slot = nil, nil
        else
            local slab = slot == "ours" and cur.ours or slot == "base" and cur.base or cur.theirs
            slab[#slab + 1] = line
        end
    end
    return regions
end

return M
