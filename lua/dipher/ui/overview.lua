-- pure builder for the PR overview page (§8.2). data in -> { lines, highlights } out,
-- no vim state, so it's unit-tested like ui/thread.lua. the timeline merges comments +
-- review verdicts and sorts by created_at; relative time is injected (opts.reltime) to
-- keep the builder deterministic. §3 scope guard: comments + review verdicts only — no
-- reactions, labels, assignees, or events

local M = {}

local RULE = string.rep("─", 60)

-- review state -> the verdict label + highlight group
---@type table<string, { label: string, hl: string }>
local VERDICT = {
    APPROVED = { label = "approved", hl = "dipherOverviewApproved" },
    CHANGES_REQUESTED = { label = "requested changes", hl = "dipherOverviewChanges" },
    COMMENTED = { label = "commented", hl = "dipherOverviewMeta" },
    DISMISSED = { label = "review dismissed", hl = "dipherOverviewMeta" },
}

-- the PR state word -> its highlight group (no dedicated state groups in §10, so the
-- open/merged states ride the approved green and a closed PR the changes orange)
---@type table<string, string>
local STATE_HL = {
    OPEN = "dipherOverviewApproved",
    MERGED = "dipherOverviewApproved",
    CLOSED = "dipherOverviewChanges",
}

-- split on newlines, dropping a single trailing newline so a github-style "body\n"
-- doesn't add a blank row. vim-free (the builder runs under busted, no nvim runtime)
---@param s string
---@return string[]
local function split_lines(s)
    local out = {}
    for line in ((s or ""):gsub("\n$", "") .. "\n"):gmatch("([^\n]*)\n") do
        out[#out + 1] = line
    end
    return out
end

-- merge comments + reviews into one chronological list of { kind, author, body, ts,
-- state? }, sorted ascending by created_at (lexical sort is correct for ISO-8601 UTC)
---@param tl { comments: table[], reviews: table[] }
---@return table[]
local function timeline(tl)
    local items = {}
    for _, c in ipairs(tl.comments or {}) do
        items[#items + 1] =
            { kind = "comment", author = c.author, body = c.body, ts = c.created_at }
    end
    for _, r in ipairs(tl.reviews or {}) do
        items[#items + 1] = {
            kind = "review",
            author = r.author,
            body = r.body,
            ts = r.created_at,
            state = r.state,
        }
    end
    table.sort(items, function(a, b)
        return (a.ts or "") < (b.ts or "")
    end)
    return items
end

M.timeline = timeline

-- an item's verdict label + highlight: a review maps through VERDICT (an unknown state
-- falls back to its lowercased word in meta), a conversation comment reads "commented"
---@param item table
---@return { label: string, hl: string }
local function verdict_of(item)
    if item.kind == "review" then
        return VERDICT[item.state or ""]
            or { label = (item.state or "reviewed"):lower(), hl = "dipherOverviewMeta" }
    end
    return { label = "commented", hl = "dipherOverviewMeta" }
end

-- build the overview buffer content.
---@param data { meta: table, checks: table|nil, unresolved: integer, total_threads: integer, timeline: table }
---@param opts { reltime?: fun(ts: string): string }|nil
---@return { lines: string[], highlights: table[] }  -- highlight: { row, col_start, col_end, hl } (0-based row)
function M.build(data, opts)
    opts = opts or {}
    local reltime = opts.reltime or function(ts)
        return ts or ""
    end
    local meta = data.meta or {}

    local lines, highlights = {}, {}

    -- emit one line from { text, hl } chunks, pushing a span per chunk that carries a
    -- highlight and real text (hl may be nil for plain separators)
    ---@param chunks table[]
    local function push(chunks)
        local col, parts = 0, {}
        for _, c in ipairs(chunks) do
            local text = c[1] or ""
            parts[#parts + 1] = text
            local bytes = #text
            if c[2] and bytes > 0 then
                highlights[#highlights + 1] =
                    { row = #lines, col_start = col, col_end = col + bytes, hl = c[2] }
            end
            col = col + bytes
        end
        lines[#lines + 1] = table.concat(parts)
    end

    -- header: title, the state/author/mergeable meta line, the checks + threads line
    local number = meta.number and ("#" .. meta.number .. " ") or ""
    push({ { number .. (meta.title or "untitled"), "dipherOverviewTitle" } })

    local state_word = meta.draft and "draft" or (meta.state or "open"):lower()
    local state_hl = meta.draft and "dipherOverviewMeta"
        or (STATE_HL[(meta.state or ""):upper()] or "dipherOverviewMeta")
    local mergeable = (meta.mergeable or ""):lower()
    local meta_line = {
        { state_word, state_hl },
        { " · ", "dipherOverviewMeta" },
        { "@" .. (meta.author or "?"), "dipherOverviewAuthor" },
    }
    if mergeable ~= "" then
        meta_line[#meta_line + 1] = { " · ", "dipherOverviewMeta" }
        meta_line[#meta_line + 1] = { mergeable, "dipherOverviewMeta" }
    end
    push(meta_line)

    local rollup = data.checks and data.checks.rollup
    local rollup_word = (rollup ~= nil and rollup ~= "") and tostring(rollup):lower() or "n/a"
    push({
        {
            ("checks: %s · threads: %d unresolved / %d"):format(
                rollup_word,
                data.unresolved or 0,
                data.total_threads or 0
            ),
            "dipherOverviewMeta",
        },
    })

    push({ { RULE, "dipherOverviewMeta" } })

    -- body: one buffer line per source line (markdown buffer renders it), empty body
    -- emits no rows so the page doesn't carry a blank block
    if meta.body and meta.body ~= "" then
        for _, line in ipairs(split_lines(meta.body)) do
            push({ { line, "dipherOverviewBody" } })
        end
    end

    push({ { RULE, "dipherOverviewMeta" } })

    -- timeline: one section per item, a blank row between sections
    for i, item in ipairs(timeline(data.timeline or {})) do
        if i > 1 then
            push({ { "", "dipherOverviewBody" } })
        end
        local v = verdict_of(item)
        push({
            { "── ", "dipherOverviewMeta" },
            { "@" .. (item.author or "?"), "dipherOverviewAuthor" },
            { " ", "dipherOverviewMeta" },
            { v.label, v.hl },
            { " · " .. reltime(item.ts or "") .. " ──", "dipherOverviewMeta" },
        })
        if item.body and item.body ~= "" then
            for _, line in ipairs(split_lines(item.body)) do
                push({ { line, "dipherOverviewBody" } })
            end
        end
    end

    return { lines = lines, highlights = highlights }
end

return M
