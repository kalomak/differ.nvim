-- the 3-way merge renderer (§8.5): a MergeModel becomes one column per visible side
-- plus the result spine. pure (no nvim API), so the column assembly + slab location are
-- unit-tested. unlike the diff renderers each merge column is a real single-source file
-- (a stage, or the worktree result), so the session highlights it natively and only
-- needs the per-region line ranges this returns
--
-- input columns show the full stage files; a region's slab is located by an ordered
-- forward search (slabs appear in file order), so a unique run highlights and a
-- not-found run simply doesn't — no highlight beats a wrong highlight (§6.3)

local to_lines = require("dipher.util.text").to_lines

---@class dipher.merge.ColumnRegion
---@field index integer  -- the source region's 1-based index
---@field first integer  -- 1-based buffer line, inclusive
---@field last integer   -- inclusive

---@class dipher.merge.RenderColumn
---@field side "ours"|"base"|"theirs"|"result"
---@field lines string[]
---@field regions dipher.merge.ColumnRegion[]

---@class dipher.merge.RenderResult
---@field columns dipher.merge.RenderColumn[]
---@field result_index integer -- index into columns of the editable result spine

local M = {}

-- first 1-based start at or after `from` where `slab` matches `lines` run-for-run, or nil
---@param lines string[]
---@param slab string[]
---@param from integer
---@return integer|nil
local function find_run(lines, slab, from)
    for start = from, #lines - #slab + 1 do
        local hit = true
        for k = 1, #slab do
            if lines[start + k - 1] ~= slab[k] then
                hit = false
                break
            end
        end
        if hit then
            return start
        end
    end
    return nil
end

-- locate each region's `key` slab (ours/base/theirs) inside a stage file's lines, in
-- order; an empty or unlocated slab contributes no region (so it stays unhighlighted)
---@param lines string[]
---@param regions dipher.merge.Region[]
---@param key "ours"|"base"|"theirs"
---@return dipher.merge.ColumnRegion[]
local function locate_regions(lines, regions, key)
    local out, from = {}, 1
    for _, r in ipairs(regions) do
        local slab = r[key]
        if slab and #slab > 0 then
            local s = find_run(lines, slab, from)
            if s then
                out[#out + 1] = { index = r.index, first = s, last = s + #slab - 1 }
                from = s + #slab
            end
        end
    end
    return out
end

-- build the merge columns. base is shown only under the diff3_mixed layout (it's read
-- + carried regardless, so the toggle costs nothing); the result column is always last
---@param model dipher.MergeModel
---@param opts { layout?: "default"|"diff3_mixed" }|nil
---@return dipher.merge.RenderResult
function M.render(model, opts)
    opts = opts or {}
    local show_base = opts.layout == "diff3_mixed"

    local ours = to_lines(model.ours_text)
    local theirs = to_lines(model.theirs_text)
    local result = to_lines(model.result_text)

    local columns = {
        { side = "ours", lines = ours, regions = locate_regions(ours, model.regions, "ours") },
    }
    if show_base then
        local base = to_lines(model.base_text)
        columns[#columns + 1] =
            { side = "base", lines = base, regions = locate_regions(base, model.regions, "base") }
    end
    columns[#columns + 1] = {
        side = "theirs",
        lines = theirs,
        regions = locate_regions(theirs, model.regions, "theirs"),
    }

    -- the result regions are exact: each marker block's line span (markers included)
    local result_regions = {}
    for _, r in ipairs(model.regions) do
        result_regions[#result_regions + 1] =
            { index = r.index, first = r.result_start, last = r.result_end }
    end
    columns[#columns + 1] = { side = "result", lines = result, regions = result_regions }

    return { columns = columns, result_index = #columns }
end

return M
