local tree = require("dipher.panel.tree")
local render = require("dipher.panel.render")

local function entry(path, status, add, del)
    return { path = path, status = status or "M", additions = add or 0, deletions = del or 0 }
end

describe("panel.render.lines", function()
    it("prefixes a header (root path + Help + blank) when given one", function()
        local root = tree.build({ entry("a.lua") })
        local out = render.lines(
            { { title = "Changes", rows = tree.rows(root, "tree", {}) } },
            { path = "~/repo", help = "g?" }
        )
        assert.are.same({ "~/repo", "Help: g?", "", "Changes (1)", "M a.lua" }, out.lines)
        assert.are.equal("root", out.meta[1].kind)
        assert.are.equal("help", out.meta[2].kind)
        assert.are.equal("blank", out.meta[3].kind)
        assert.are.equal("header", out.meta[4].kind)
    end)

    it("appends a 'Showing changes for:' footer when given a rev", function()
        local root = tree.build({ entry("a.lua") })
        local out = render.lines({ { rows = tree.rows(root, "tree", {}) } }, nil, nil, "main...")
        assert.are.same({ "M a.lua", "", "Showing changes for:", "main..." }, out.lines)
        assert.are.equal("blank", out.meta[2].kind)
        assert.are.equal("foothead", out.meta[3].kind)
        assert.are.equal("footrev", out.meta[4].kind)
    end)

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

    it("appends +/- counts only when nonzero, with byte cols for each", function()
        local root = tree.build({ entry("a.lua", "M", 3, 1) })
        local out = render.lines({ { rows = tree.rows(root, "tree", {}) } })
        assert.are.equal("M a.lua  +3 -1", out.lines[1])
        local m = out.meta[1]
        -- "M a.lua  +3 -1": "+3" at cols 9..11, "-1" at cols 12..14
        assert.are.equal("+3", out.lines[1]:sub(m.add_col + 1, m.add_end))
        assert.are.equal("-1", out.lines[1]:sub(m.del_col + 1, m.del_end))
    end)

    it("leaves count cols nil when there are no changes", function()
        local root = tree.build({ entry("a.lua", "M", 0, 0) })
        local out = render.lines({ { rows = tree.rows(root, "tree", {}) } })
        assert.is_nil(out.meta[1].add_col)
    end)

    it("paints a devicon between the status letter and the name", function()
        local root = tree.build({ entry("a.lua", "M", 3, 1) })
        local icon_for = function()
            return ">", "DevIconLua"
        end
        local out = render.lines({ { rows = tree.rows(root, "tree", {}) } }, nil, icon_for)
        assert.are.equal("M > a.lua  +3 -1", out.lines[1])
        local m = out.meta[1]
        assert.are.equal("DevIconLua", m.icon_hl)
        assert.are.equal(">", out.lines[1]:sub(m.icon_col + 1, m.icon_end))
        assert.are.equal("a.lua", out.lines[1]:sub(m.name_col + 1, m.name_col + 5))
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
