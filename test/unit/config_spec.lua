local config = require("differ.config")

describe("config.resolve_keymaps", function()
    it("applies the shared defaults to every surface", function()
        local km = config.resolve_keymaps(nil)
        for _, surface in ipairs({ "diff", "panel", "history" }) do
            assert.are.equal("]c", km[surface].next_hunk)
            assert.are.equal("f", km[surface].scroll_down)
            assert.are.same({ "<CR>", "o" }, km[surface].select)
        end
    end)

    it("lets a top-level override reach all surfaces", function()
        local km = config.resolve_keymaps({ next_hunk = "gh" })
        assert.are.equal("gh", km.diff.next_hunk)
        assert.are.equal("gh", km.panel.next_hunk)
        assert.are.equal("gh", km.history.next_hunk)
    end)

    it("scopes a per-surface override to that surface only", function()
        local km = config.resolve_keymaps({ panel = { stage = "ga" } })
        assert.are.equal("ga", km.panel.stage)
        assert.are.equal("s", km.diff.stage) -- diff keeps the default
        assert.are.equal("s", km.history.stage)
    end)

    it("disables an action with false", function()
        local km = config.resolve_keymaps({ scroll_down = false, panel = { discard = false } })
        assert.is_false(km.diff.scroll_down)
        assert.is_false(km.panel.scroll_down) -- top-level reaches the panel too
        assert.is_false(km.panel.discard)
        assert.is_false(km.history.scroll_down)
    end)

    it("replaces a multi-lhs list wholesale (no index merge)", function()
        local km = config.resolve_keymaps({ select = { "x" } })
        assert.are.same({ "x" }, km.panel.select) -- not { "x", "o" }
    end)

    it("a per-surface override wins over a top-level one", function()
        local km = config.resolve_keymaps({ next_hunk = "gh", diff = { next_hunk = "gn" } })
        assert.are.equal("gn", km.diff.next_hunk)
        assert.are.equal("gh", km.panel.next_hunk)
    end)
end)
