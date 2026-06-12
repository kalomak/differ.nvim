-- Stacked dual-rail renderer: old/new interleaved per hunk on one scroll surface.
-- Pure function over the hunk model (no Neovim API) so it stays golden-testable.
-- Buffer lines are raw code (search/yank/motions work); +/- styling and line
-- numbers are painted later from the map, never baked into the text.

local LineMap = require("dipher.render.linemap")
local text_util = require("dipher.util.text")
local spans = require("dipher.worddiff.spans")

local M = {}

-- Buffer text for a collapsed-context separator. No line numbers (kind=="meta").
---@param hidden integer
---@return string
local function meta_text(hidden)
    return ("\u{22ef} %d unchanged line%s"):format(hidden, hidden == 1 and "" or "s")
end

-- Render a model into interleaved buffer lines plus a populated line map.
---@param model dipher.DiffModel
---@param opts { context: integer, deep_diff?: table }
---@return dipher.RenderResult
function M.render(model, opts)
    local map = LineMap.new()
    local lines = {}

    -- Identical content produces no hunks; nothing to show.
    if #model.hunks == 0 then
        return { lines = lines, map = map }
    end

    local context = opts.context or 3
    local deep = opts.deep_diff or {}
    local deep_on = deep.enabled ~= false
    local threshold = deep.similarity_threshold or 0.5
    local mode = deep.granularity or "word"

    -- Context lines are identical on both sides, so old_all supplies their text.
    local old_all = text_util.to_lines(model.old_text)

    -- Emit one context line present on both sides.
    ---@param o integer
    ---@param n integer
    local function push_context(o, n)
        lines[#lines + 1] = old_all[o]
        map:push({ kind = "context", old = o, new = n })
    end

    -- Emit an unchanged region [old_from, new_from) of length L, collapsing its
    -- middle to a separator when it exceeds the surrounding context windows.
    -- lead/tail are the context lines to keep at each end (0 at a file boundary).
    ---@param old_from integer
    ---@param new_from integer
    ---@param len integer
    ---@param has_prev boolean
    ---@param has_next boolean
    local function emit_gap(old_from, new_from, len, has_prev, has_next)
        if len <= 0 then
            return
        end
        local lead = math.min(has_prev and context or 0, len)
        local tail = math.min(has_next and context or 0, len)
        if lead + tail >= len then
            for k = 0, len - 1 do
                push_context(old_from + k, new_from + k)
            end
            return
        end
        for k = 0, lead - 1 do
            push_context(old_from + k, new_from + k)
        end
        lines[#lines + 1] = meta_text(len - lead - tail)
        map:push({ kind = "meta" })
        for k = len - tail, len - 1 do
            push_context(old_from + k, new_from + k)
        end
    end

    -- Emit a hunk: old (deleted) lines as a block, then new (added) lines.
    ---@param h dipher.Hunk
    ---@param hi integer
    local function emit_hunk(h, hi)
        local old_spans, new_spans = {}, {}
        if deep_on then
            old_spans, new_spans = spans.for_hunk(h, threshold, mode)
        end
        for k = 1, h.old_count do
            lines[#lines + 1] = h.old_lines[k]
            map:push({ kind = "old", old = h.old_start + k - 1, hunk = hi, spans = old_spans[k] })
        end
        for k = 1, h.new_count do
            lines[#lines + 1] = h.new_lines[k]
            map:push({ kind = "new", new = h.new_start + k - 1, hunk = hi, spans = new_spans[k] })
        end
    end

    local cursor_old, cursor_new = 1, 1
    for hi, h in ipairs(model.hunks) do
        -- vim.text.diff reports pure insertions as old_count==0 with old_start at
        -- the preceding old line (deletions mirror it on the new side), so derive
        -- the last unchanged line before the hunk from the count, not the start.
        local gap_old_end = h.old_count > 0 and (h.old_start - 1) or h.old_start
        emit_gap(cursor_old, cursor_new, gap_old_end - cursor_old + 1, hi > 1, true)
        emit_hunk(h, hi)
        cursor_old = h.old_count > 0 and (h.old_start + h.old_count) or (h.old_start + 1)
        cursor_new = h.new_count > 0 and (h.new_start + h.new_count) or (h.new_start + 1)
    end
    emit_gap(cursor_old, cursor_new, #old_all - cursor_old + 1, true, false)

    return { lines = lines, map = map }
end

return M
