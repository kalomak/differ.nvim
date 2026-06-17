local overview = require("dipher.ui.overview")

-- inject a deterministic reltime so the golden lines don't depend on the clock
local function build(data)
    return overview.build(data, {
        reltime = function(ts)
            return ts
        end,
    })
end

-- the built line at `idx` (1-based), for layout assertions
local function line(built, idx)
    return built.lines[idx]
end

-- find the 1-based row index of the first line equal to `text`, or nil
local function row_of(built, text)
    for i, l in ipairs(built.lines) do
        if l == text then
            return i
        end
    end
end

-- shallow-merge `over` onto a copy of `base` (pure Lua; no vim runtime under busted)
local function extend(base, over)
    local out = {}
    for k, v in pairs(base) do
        out[k] = v
    end
    for k, v in pairs(over) do
        out[k] = v
    end
    return out
end

local BASE_META = {
    number = 42,
    title = "add the overview",
    author = "alice",
    state = "OPEN",
    draft = false,
    mergeable = "MERGEABLE",
    body = "",
}

describe("ui.overview.timeline (merge + sort)", function()
    it("merges comments + reviews and sorts ascending by ISO timestamp", function()
        local items = overview.timeline({
            comments = {
                { author = "a", body = "later", created_at = "2026-01-03T00:00:00Z" },
                { author = "b", body = "first", created_at = "2026-01-01T00:00:00Z" },
            },
            reviews = {
                {
                    author = "c",
                    state = "APPROVED",
                    body = "lgtm",
                    created_at = "2026-01-02T00:00:00Z",
                },
            },
        })
        assert.are.equal(3, #items)
        assert.are.equal("b", items[1].author) -- 01-01
        assert.are.equal("c", items[2].author) -- 01-02 (the review, interleaved)
        assert.are.equal("a", items[3].author) -- 01-03
        assert.are.equal("review", items[2].kind)
        assert.are.equal("comment", items[1].kind)
    end)
end)

describe("ui.overview.build (shapes that must not error)", function()
    it("builds a comment-only PR", function()
        local built = build({
            meta = BASE_META,
            unresolved = 0,
            total_threads = 0,
            timeline = {
                comments = { { author = "a", body = "hi", created_at = "2026-01-01T00:00:00Z" } },
                reviews = {},
            },
        })
        assert.is_truthy(row_of(built, "── @a commented · 2026-01-01T00:00:00Z ──"))
    end)

    it("builds a review-only PR", function()
        local built = build({
            meta = BASE_META,
            unresolved = 0,
            total_threads = 0,
            timeline = {
                comments = {},
                reviews = {
                    {
                        author = "r",
                        state = "APPROVED",
                        body = "",
                        created_at = "2026-01-01T00:00:00Z",
                    },
                },
            },
        })
        assert.is_truthy(row_of(built, "── @r approved · 2026-01-01T00:00:00Z ──"))
    end)

    it("builds an empty PR (no timeline) without error", function()
        local built = build({
            meta = BASE_META,
            unresolved = 0,
            total_threads = 0,
            timeline = { comments = {}, reviews = {} },
        })
        assert.is_truthy(#built.lines >= 1)
        assert.are.equal("#42 add the overview", line(built, 1))
    end)
end)

describe("ui.overview.build (verdict mapping)", function()
    local CASES = {
        { state = "APPROVED", label = "approved", hl = "dipherOverviewApproved" },
        { state = "CHANGES_REQUESTED", label = "requested changes", hl = "dipherOverviewChanges" },
        { state = "COMMENTED", label = "commented", hl = "dipherOverviewMeta" },
        { state = "DISMISSED", label = "review dismissed", hl = "dipherOverviewMeta" },
    }
    for _, c in ipairs(CASES) do
        it("maps " .. c.state .. " to its label + highlight", function()
            local built = build({
                meta = BASE_META,
                unresolved = 0,
                total_threads = 0,
                timeline = {
                    comments = {},
                    reviews = {
                        {
                            author = "x",
                            state = c.state,
                            body = "note",
                            created_at = "2026-01-01T00:00:00Z",
                        },
                    },
                },
            })
            local want = ("── @x %s · 2026-01-01T00:00:00Z ──"):format(c.label)
            local row = row_of(built, want)
            assert.is_truthy(row)
            -- the verdict label rides its highlight group; find the span covering it
            local col = built.lines[row]:find(c.label, 1, true) - 1
            local found = false
            for _, h in ipairs(built.highlights) do
                if h.row == row - 1 and h.col_start == col and h.hl == c.hl then
                    found = true
                end
            end
            assert.is_true(found)
        end)
    end
end)

describe("ui.overview.build (body rendering)", function()
    it("emits one line per source line for a multi-line body", function()
        local built = build({
            meta = extend(BASE_META, { body = "line one\nline two" }),
            unresolved = 0,
            total_threads = 0,
            timeline = { comments = {}, reviews = {} },
        })
        assert.is_truthy(row_of(built, "line one"))
        assert.is_truthy(row_of(built, "line two"))
    end)

    it("emits no body rows for an empty body", function()
        local built = build({
            meta = BASE_META, -- body == ""
            unresolved = 0,
            total_threads = 0,
            timeline = { comments = {}, reviews = {} },
        })
        -- the two rules are adjacent when there's no body between them
        local rule = string.rep("─", 60)
        local first = row_of(built, rule)
        assert.is_truthy(first)
        assert.are.equal(rule, line(built, first + 1))
    end)
end)

describe("ui.overview.build (header counts + rollup)", function()
    it("reports the unresolved/total thread count and the checks rollup", function()
        local built = build({
            meta = BASE_META,
            checks = { rollup = "SUCCESS" },
            unresolved = 2,
            total_threads = 5,
            timeline = { comments = {}, reviews = {} },
        })
        assert.is_truthy(row_of(built, "checks: success · threads: 2 unresolved / 5"))
    end)

    it("degrades to n/a when checks are absent", function()
        local built = build({
            meta = BASE_META,
            checks = nil,
            unresolved = 0,
            total_threads = 0,
            timeline = { comments = {}, reviews = {} },
        })
        assert.is_truthy(row_of(built, "checks: n/a · threads: 0 unresolved / 0"))
    end)
end)

describe("ui.overview.build (highlight spans align)", function()
    it("title span covers the whole title line", function()
        local built = build({
            meta = BASE_META,
            unresolved = 0,
            total_threads = 0,
            timeline = { comments = {}, reviews = {} },
        })
        local title = "#42 add the overview"
        local span
        for _, h in ipairs(built.highlights) do
            if h.row == 0 and h.hl == "dipherOverviewTitle" then
                span = h
            end
        end
        assert.is_truthy(span)
        assert.are.equal(0, span.col_start)
        assert.are.equal(#title, span.col_end)
    end)
end)
