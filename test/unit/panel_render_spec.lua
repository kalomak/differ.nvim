local tree = require("dipher.panel.tree")
local render = require("dipher.panel.render")

local function entry(path, status, add, del)
    return { path = path, status = status or "M", additions = add or 0, deletions = del or 0 }
end

describe("panel.render.lines", function()
    it("renders a section header with the file count", function()
        local root = tree.build({ entry("a.lua"), entry("b.lua") })
        local out = render.lines({ { title = "Unstaged", rows = tree.rows(root, "tree", {}) } })
        assert.are.equal("Unstaged (2)", out.lines[1])
        assert.are.equal("header", out.meta[1].kind)
    end)

    it("renders a file row with status letter and points cols at it", function()
        local root = tree.build({ entry("a.lua", "M") })
        local out = render.lines({ { title = nil, rows = tree.rows(root, "tree", {}) } })
        assert.are.equal("M a.lua", out.lines[1])
        local m = out.meta[1]
        assert.are.equal("file", m.kind)
        assert.are.equal("M", m.status)
        assert.are.equal(0, m.status_col) -- "M" at col 0
        assert.are.equal(2, m.name_col) -- name after "M "
    end)

    it("appends +/- counts only when nonzero", function()
        local root = tree.build({ entry("a.lua", "M", 3, 1) })
        local out = render.lines({ { rows = tree.rows(root, "tree", {}) } })
        assert.are.equal("M a.lua  +3 -1", out.lines[1])
    end)

    it("renders a collapsed dir with a closed fold arrow and trailing slash", function()
        local root = tree.build({ entry("src/a.lua"), entry("src/b.lua") })
        local out = render.lines({ { rows = tree.rows(root, "tree", { ["src"] = true }) } })
        assert.are.equal("▸ src/", out.lines[1])
        assert.are.equal("dir", out.meta[1].kind)
        assert.is_true(out.meta[1].collapsed)
    end)

    it("indents nested rows by depth", function()
        local root = tree.build({ entry("src/a.lua"), entry("src/b.lua") })
        local out = render.lines({ { rows = tree.rows(root, "tree", {}) } })
        assert.are.equal("▾ src/", out.lines[1])
        assert.are.equal("  M a.lua", out.lines[2]) -- depth 1 => two-space indent
    end)
end)
