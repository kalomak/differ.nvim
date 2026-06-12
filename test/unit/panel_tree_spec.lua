local tree = require("dipher.panel.tree")

local function entry(path, status)
    return { path = path, status = status or "M", additions = 0, deletions = 0 }
end

describe("panel.tree.build", function()
    it("folds single-child directory chains", function()
        local root = tree.build({ entry("lua/dipher/git/init.lua") })
        -- the whole chain collapses to one dir node "lua/dipher/git"
        assert.are.equal(1, #root.children)
        local dir = root.children[1]
        assert.are.equal("dir", dir.kind)
        assert.are.equal("lua/dipher/git", dir.name)
        assert.are.equal("lua/dipher/git", dir.path)
        assert.are.equal("init.lua", dir.children[1].name)
    end)

    it("stops folding where a directory branches", function()
        local root = tree.build({ entry("src/a.lua"), entry("src/sub/b.lua") })
        assert.are.equal(1, #root.children)
        local src = root.children[1]
        assert.are.equal("src", src.name) -- can't fold: two children
        -- dirs sort before files: sub/ then a.lua
        assert.are.equal("sub", src.children[1].name)
        assert.are.equal("a.lua", src.children[2].name)
    end)
end)

describe("panel.tree.rows", function()
    it("emits dirs before files, nested by depth, in tree mode", function()
        local root = tree.build({ entry("src/a.lua"), entry("src/sub/b.lua") })
        local rows = tree.rows(root, "tree", {})
        -- src/ (d0); sub/ before a.lua (dirs first); b.lua nested under sub
        local got = {}
        for _, r in ipairs(rows) do
            got[#got + 1] = ("%s:%s:%d"):format(r.kind, r.path, r.depth)
        end
        assert.are.same(
            { "dir:src:0", "dir:src/sub:1", "file:src/sub/b.lua:2", "file:src/a.lua:1" },
            got
        )
    end)

    it("hides children of a collapsed directory", function()
        local root = tree.build({ entry("src/a.lua"), entry("src/b.lua") })
        local all = tree.rows(root, "tree", {})
        assert.are.equal(3, #all) -- src, a.lua, b.lua
        local collapsed = tree.rows(root, "tree", { ["src"] = true })
        assert.are.equal(1, #collapsed) -- just src, children hidden
        assert.is_true(collapsed[1].collapsed)
    end)

    it("flat mode lists leaves with full paths and no depth", function()
        local root = tree.build({ entry("src/sub/b.lua"), entry("src/a.lua") })
        local rows = tree.rows(root, "flat", {})
        assert.are.equal(2, #rows)
        for _, r in ipairs(rows) do
            assert.are.equal("file", r.kind)
            assert.are.equal(0, r.depth)
            assert.are.equal(r.entry.path, r.name) -- full path as the label
        end
    end)
end)
