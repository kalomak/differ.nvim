-- the MergeModel builder over a stubbed git layer: the parse path is real (pure
-- conflict.parse + to_lines), only the I/O reads are faked, so the assembly + the
-- no-conflict / missing-file guards are checked without a git repo or nvim runtime

local model = require("dipher.merge.model")

-- a default-style conflicted worktree file
local RESULT = table.concat({
    "keep me",
    "<<<<<<< HEAD",
    "ours",
    "=======",
    "theirs",
    ">>>>>>> branch",
}, "\n") .. "\n"

local function fake_git(opts)
    opts = opts or {}
    return {
        read = function()
            if opts.worktree == nil then
                return RESULT
            end
            return opts.worktree -- false/nil-able via an explicit field
        end,
        read_stage = function(_, _, stage)
            return (opts.stages or { [1] = "base\n", [2] = "ours\n", [3] = "theirs\n" })[stage]
                or ""
        end,
    }
end

describe("merge.model.build", function()
    after_each(function()
        package.loaded["dipher.git"] = nil
    end)

    it("assembles the model from the worktree result and the three stages", function()
        package.loaded["dipher.git"] = fake_git()
        local m, err = model.build("/repo", "a.txt", "main")
        assert.is_nil(err)
        assert.are.equal("a.txt", m.path)
        assert.are.equal("/repo", m.root)
        assert.are.equal("main", m.head)
        assert.are.equal(RESULT, m.result_text)
        assert.are.equal("ours\n", m.ours_text)
        assert.are.equal("base\n", m.base_text)
        assert.are.equal("theirs\n", m.theirs_text)
        assert.are.equal(1, #m.regions)
        assert.are.equal(2, m.regions[1].result_start)
    end)

    it("returns nil + reason when the file has no conflict markers", function()
        package.loaded["dipher.git"] = fake_git({ worktree = "clean file\n" })
        local m, err = model.build("/repo", "a.txt", nil)
        assert.is_nil(m)
        assert.is_string(err)
    end)

    it("returns nil + reason when the file is not in the working tree", function()
        package.loaded["dipher.git"] = fake_git({ worktree = false })
        local m, err = model.build("/repo", "gone.txt", nil)
        assert.is_nil(m)
        assert.is_string(err)
    end)

    it("reads an absent stage as empty (modify/delete conflict)", function()
        package.loaded["dipher.git"] = fake_git({ stages = { [2] = "ours\n" } })
        local m = model.build("/repo", "a.txt", nil)
        assert.are.equal("ours\n", m.ours_text)
        assert.are.equal("", m.base_text)
        assert.are.equal("", m.theirs_text)
    end)
end)
