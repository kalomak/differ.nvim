-- side-by-side renderer from the same hunk model and map contract as stacked.
-- pure function over the hunk model (no nvim API).
--
-- real code lines must stay yankable/searchable, so side-by-side is two columns
-- (two buffers), not one buffer of "old | new" cells. this renderer emits two
-- index-aligned line sequences plus a LineMap per side (each conforming to the
-- frozen contract verbatim). filler cells (hunk padding) are kind=="meta" rows
-- with empty text so both columns stay row-aligned; unchanged regions are emitted
-- in full and collapsed by native folds, not dropped

local LineMap = require("dipher.render.linemap")
local text_util = require("dipher.util.text")
local spans = require("dipher.worddiff.spans")
local walk = require("dipher.render.walk")

local M = {}

-- render a model into two index-aligned columns ("old" left, "new" right). both
-- columns share the same fold ranges since their rows are aligned
---@param model dipher.DiffModel
---@param opts { context: integer, deep_diff?: table }
---@return dipher.RenderResult
function M.render(model, opts)
    local old_map, new_map = LineMap.new(), LineMap.new()
    local old_lines, new_lines = {}, {}
    local folds = {}
    local fold_start = nil

    -- push one aligned row, keeping both columns the same length
    ---@param ltext string|nil
    ---@param lrail dipher.RailLine
    ---@param rtext string|nil
    ---@param rrail dipher.RailLine
    local function push_row(ltext, lrail, rtext, rrail)
        old_lines[#old_lines + 1] = ltext or ""
        new_lines[#new_lines + 1] = rtext or ""
        old_map:push(lrail)
        new_map:push(rrail)
    end

    -- extend/close the running fold run over the aligned rows
    local function mark(foldable)
        if foldable then
            fold_start = fold_start or #old_lines
        elseif fold_start then
            folds[#folds + 1] = { first = fold_start, last = #old_lines - 1 }
            fold_start = nil
        end
    end

    local function result()
        return {
            columns = {
                { lines = old_lines, map = old_map, side = "old", folds = folds },
                { lines = new_lines, map = new_map, side = "new", folds = folds },
            },
            rows = #old_lines,
        }
    end

    if #model.hunks == 0 then
        return result()
    end

    local context = opts.context or 3
    local deep = opts.deep_diff or {}
    local deep_on = deep.enabled ~= false
    local mode = deep.granularity or "word"

    -- context lines are identical on both sides, so old_all supplies their text
    local old_all = text_util.to_lines(model.old_text)

    walk.walk(model, context, #old_all, {
        context = function(o, n, foldable)
            push_row(
                old_all[o],
                { kind = "context", old = o, new = n },
                old_all[o],
                { kind = "context", old = o, new = n }
            )
            mark(foldable)
        end,
        -- side-by-side aligns old[i] with new[i] positionally and pads the shorter
        -- side with filler. word spans are computed per positionally-paired row;
        -- similarity-based pairing is a deferred refinement (spec §6.3 / §11)
        hunk = function(h, hi)
            local rows = math.max(h.old_count, h.new_count)
            for i = 1, rows do
                local has_old = i <= h.old_count
                local has_new = i <= h.new_count
                local lspan, rspan
                if deep_on and has_old and has_new then
                    local s = spans.emit(h.old_lines[i], h.new_lines[i], mode)
                    lspan, rspan = s.old, s.new
                end
                local lrail = has_old
                        and { kind = "old", old = h.old_start + i - 1, hunk = hi, spans = lspan }
                    or { kind = "meta" }
                local rrail = has_new
                        and { kind = "new", new = h.new_start + i - 1, hunk = hi, spans = rspan }
                    or { kind = "meta" }
                push_row(
                    has_old and h.old_lines[i] or nil,
                    lrail,
                    has_new and h.new_lines[i] or nil,
                    rrail
                )
                mark(false)
            end
        end,
    })
    if fold_start then
        folds[#folds + 1] = { first = fold_start, last = #old_lines }
    end

    return result()
end

return M
