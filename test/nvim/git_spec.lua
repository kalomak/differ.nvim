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

    it("opens the default panel as a single Unstaged section and toggles closed", function()
        local root = fresh_repo()
        write(root .. "/a.lua", "local x = 2\nreturn x\n") -- modified, not staged
        vim.cmd.edit(root .. "/a.lua")

        git_src.panel({})
        local p = Panel.current()
        assert.is_not_nil(p)
        assert.is_true(p:is_open())
        -- header + the one file row; the empty Staged/Untracked sections are dropped
        assert.are.same(
            { "Unstaged (1)", "M a.lua  +1 -1" },
            vim.api.nvim_buf_get_lines(p.bufnr, 0, -1, false)
        )

        git_src.panel({}) -- toggle
        assert.is_nil(Panel.current())
    end)

    it("groups staged / unstaged / untracked into sections with counts", function()
        local root = fresh_repo()
        write(root .. "/a.lua", "local x = 2\nreturn x\n") -- unstaged modify of a.lua
        write(root .. "/z.lua", "local z = 9\n")
        git(root, "add", "z.lua") -- staged add
        write(root .. "/u.lua", "untracked\n") -- untracked
        vim.cmd.edit(root .. "/a.lua")

        git_src.panel({})
        local p = Panel.current()
        assert.are.same({
            "Staged (1)",
            "A z.lua  +1 -0",
            "Unstaged (1)",
            "M a.lua  +1 -1",
            "Untracked (1)",
            "? u.lua",
        }, vim.api.nvim_buf_get_lines(p.bufnr, 0, -1, false))
        p:close()
    end)

    it("re-sources one View in place as files are selected", function()
        local root = fresh_repo()
        write(root .. "/a.lua", "local x = 2\nreturn x\n") -- unstaged modify (Unstaged)
        write(root .. "/z.lua", "local z = 9\n")
        git(root, "add", "z.lua") -- staged add (Staged)
        vim.cmd.edit(root .. "/a.lua")

        git_src.panel({})
        local p = Panel.current()
        -- buffer is: Staged header, z.lua, Unstaged header, a.lua — pick both files
        vim.api.nvim_win_set_cursor(p.winid, { 2, 0 }) -- z.lua (staged: HEAD vs index)
        p:select()
        local diff_buf = vim.api.nvim_win_get_buf(p.origin_win)
        vim.api.nvim_win_set_cursor(p.winid, { 4, 0 }) -- a.lua (unstaged: index vs worktree)
        p:select()
        -- same window + buffer: the View was re-sourced, not recreated
        assert.are.equal(diff_buf, vim.api.nvim_win_get_buf(p.origin_win))
        p:close()
    end)

    it("diffs a staged entry HEAD↔index and an unstaged entry index↔worktree", function()
        local root = fresh_repo()
        -- stage one version of a.lua, then edit further in the worktree
        write(root .. "/a.lua", "local x = 2\nreturn x\n")
        git(root, "add", "a.lua")
        write(root .. "/a.lua", "local x = 3\nreturn x\n")
        vim.cmd.edit(root .. "/a.lua")

        git_src.panel({})
        local p = Panel.current()
        -- p:select returns focus to the panel, so look the View up via the origin
        -- window's buffer (View.current keys off the focused buffer).
        local function view_in_origin()
            vim.api.nvim_set_current_win(p.origin_win)
            return require("dipher.view").current()
        end
        -- a.lua is "MM": staged (line 2) and unstaged (line 4)
        vim.api.nvim_win_set_cursor(p.winid, { 2, 0 })
        p:select()
        local v = view_in_origin()
        assert.are.equal(V1, v.model.old_text) -- HEAD
        assert.are.equal("local x = 2\nreturn x\n", v.model.new_text) -- index

        vim.api.nvim_win_set_cursor(p.winid, { 4, 0 })
        p:select()
        v = view_in_origin()
        assert.are.equal("local x = 2\nreturn x\n", v.model.old_text) -- index
        assert.are.equal("local x = 3\nreturn x\n", v.model.new_text) -- worktree
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
