-- Runs under headless nvim against a throwaway git repo: exercises the local git
-- source end-to-end — content reads, changed-file listing, rename handling,
-- merge-base resolution, and the :Dipher picker building a correct DiffModel.
local git_src = require("dipher.git")
local rev = require("dipher.git.rev")

-- Run git in `cwd`, asserting success. Identity is pinned inline so commits work
-- in CI without a global gitconfig.
local function git(cwd, ...)
    local args =
        { "git", "-c", "user.email=t@t", "-c", "user.name=t", "-c", "init.defaultBranch=main" }
    vim.list_extend(args, { ... })
    local res = vim.system(args, { cwd = cwd, text = true }):wait()
    assert(
        res.code == 0,
        "git failed: " .. table.concat({ ... }, " ") .. "\n" .. (res.stderr or "")
    )
    return res.stdout
end

local function write(path, content)
    local fd = assert(io.open(path, "wb"))
    fd:write(content)
    fd:close()
end

-- A fresh repo with one committed file (a.lua = V1) on `main`.
local V1 = "local x = 1\nreturn x\n"
local function fresh_repo()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    git(root, "init", "-q")
    write(root .. "/a.lua", V1)
    git(root, "add", "a.lua")
    git(root, "commit", "-q", "-m", "init")
    return root
end

describe("git.read / changed_files", function()
    it("reads the committed version and the worktree version", function()
        local root = fresh_repo()
        write(root .. "/a.lua", "local x = 2\nreturn x\n") -- uncommitted edit

        local head = { kind = "rev", rev = "HEAD", label = "HEAD" }
        local wt = { kind = "worktree", label = "WORKTREE" }
        assert.are.equal(V1, git_src.read(head, root, "a.lua"))
        assert.are.equal("local x = 2\nreturn x\n", git_src.read(wt, root, "a.lua"))
    end)

    it("returns nil for a path absent on a side (add/delete)", function()
        local root = fresh_repo()
        local head = { kind = "rev", rev = "HEAD", label = "HEAD" }
        assert.is_nil(git_src.read(head, root, "never.lua"))
    end)

    it("lists changed files for the default uncommitted source", function()
        local root = fresh_repo()
        write(root .. "/a.lua", "local x = 2\nreturn x\n")
        local files = git_src.changed_files(rev.source({}), root)
        assert.are.same({ { status = "M", path = "a.lua" } }, files)
    end)
end)

describe("git.open_file", function()
    it("reads the rename's old side from previous_path", function()
        local root = fresh_repo()
        git(root, "mv", "a.lua", "b.lua")
        write(root .. "/b.lua", "local x = 2\nreturn x\n")
        git(root, "commit", "-q", "-am", "rename + edit")

        local source = assert(git_src.resolve(rev.source({ "HEAD~1", "HEAD" }), root))
        local v = git_src.open_file(
            source,
            root,
            { status = "R", path = "b.lua", previous_path = "a.lua" }
        )
        assert.are.equal("b.lua", v.model.path)
        assert.are.equal(V1, v.model.old_text) -- a.lua @ HEAD~1
        assert.are.equal("local x = 2\nreturn x\n", v.model.new_text) -- b.lua @ HEAD
        v:close()
    end)
end)

describe(":Dipher panel", function()
    local Panel = require("dipher.panel")

    it("opens a panel listing the change set and toggles closed", function()
        local root = fresh_repo()
        write(root .. "/a.lua", "local x = 2\nreturn x\n")
        vim.cmd.edit(root .. "/a.lua")

        git_src.panel({})
        local p = Panel.current()
        assert.is_not_nil(p)
        assert.is_true(p:is_open())
        assert.are.same({ "M a.lua" }, vim.api.nvim_buf_get_lines(p.bufnr, 0, -1, false))

        git_src.panel({}) -- toggle
        assert.is_nil(Panel.current())
    end)

    it("re-sources one View in place as files are selected", function()
        local root = fresh_repo()
        write(root .. "/a.lua", "local x = 2\nreturn x\n")
        write(root .. "/z.lua", "local z = 9\n")
        git(root, "add", "z.lua") -- z is a new (added) file in the change set
        vim.cmd.edit(root .. "/a.lua")

        git_src.panel({})
        local p = Panel.current()
        -- a.lua then z.lua (sorted); pick the first, then the second
        vim.api.nvim_win_set_cursor(p.winid, { 1, 0 })
        p:select()
        local diff_buf = vim.api.nvim_win_get_buf(p.origin_win)
        vim.api.nvim_win_set_cursor(p.winid, { 2, 0 })
        p:select()
        -- same window + buffer: the View was re-sourced, not recreated
        assert.are.equal(diff_buf, vim.api.nvim_win_get_buf(p.origin_win))
        p:close()
    end)
end)

describe(":Dipher picker", function()
    -- Drive vim.ui.select deterministically: pick the entry matching `path`.
    local function with_pick(path, fn)
        local orig = vim.ui.select
        vim.ui.select = function(items, _, on_choice)
            for _, it in ipairs(items) do
                if it.path == path then
                    return on_choice(it)
                end
            end
            return on_choice(nil)
        end
        local ok, err = pcall(fn)
        vim.ui.select = orig
        assert(ok, err)
    end

    it("opens the picked file's diff: HEAD vs worktree by default", function()
        local root = fresh_repo()
        write(root .. "/a.lua", "local x = 2\nreturn x\n")
        vim.cmd.edit(root .. "/a.lua")

        with_pick("a.lua", function()
            git_src.open({})
        end)
        local v = require("dipher.view").current()
        assert.is_not_nil(v)
        assert.are.equal("a.lua", v.model.path)
        assert.are.equal(V1, v.model.old_text)
        assert.are.equal("local x = 2\nreturn x\n", v.model.new_text)
        v:close()
    end)

    it("resolves a merge-base (three-dot) against the working tree", function()
        local root = fresh_repo()
        -- diverge: branch off main, commit a change on the branch, then edit further
        git(root, "checkout", "-q", "-b", "feature")
        write(root .. "/a.lua", "local x = 2\nreturn x\n")
        git(root, "commit", "-q", "-am", "feature change")
        write(root .. "/a.lua", "local x = 3\nreturn x\n") -- uncommitted on top
        vim.cmd.edit(root .. "/a.lua")

        -- main... => merge-base(main, HEAD) [the init commit, V1] vs worktree [V3]
        with_pick("a.lua", function()
            git_src.open({ "main..." })
        end)
        local v = require("dipher.view").current()
        assert.is_not_nil(v)
        assert.are.equal(V1, v.model.old_text)
        assert.are.equal("local x = 3\nreturn x\n", v.model.new_text)
        assert.are.equal("main...", v.model.old_rev)
        v:close()
    end)
end)
