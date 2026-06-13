-- runs under headless nvim against a throwaway git repo: exercises the local git
-- source end-to-end (content reads, changed-file listing, rename handling,
-- merge-base resolution, and the :Dipher picker building a correct DiffModel)
local git_src = require("dipher.git")
local rev = require("dipher.git.rev")

-- run git in `cwd`, asserting success. identity is pinned inline so commits work
-- in CI without a global gitconfig
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

-- a fresh repo with one committed file (a.lua = V1) on `main`
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

    -- 1-based line of the file row for `path` (optionally pinned to a staged/unstaged
    -- section), located via the panel's meta so tests don't hardcode header offsets
    local function file_line(p, path, staged)
        for i, m in ipairs(p.meta) do
            if
                m.kind == "file"
                and m.entry.path == path
                and (staged == nil or m.entry.staged == staged)
            then
                return i
            end
        end
    end

    -- the section content only: strip the 3-line header (root/help/blank) and the
    -- 3-line footer (blank/"Showing changes for:"/rev) so assertions don't depend on
    -- the temp-dir path or the HEAD sha
    local function body(p)
        assert.are.equal("Help: g?", p.lines[2]) -- header present
        assert.are.equal("Showing changes for:", p.lines[#p.lines - 1]) -- footer present
        return vim.list_slice(p.lines, 4, #p.lines - 3)
    end

    it("opens the default panel as a single Unstaged section and toggles closed", function()
        local root = fresh_repo()
        write(root .. "/a.lua", "local x = 2\nreturn x\n") -- modified, not staged
        vim.cmd.edit(root .. "/a.lua")

        git_src.panel({})
        local p = Panel.current()
        assert.is_not_nil(p)
        assert.is_true(p:is_open())
        -- empty Staged/Untracked sections are dropped, leaving one Unstaged section
        assert.are.same({ "Unstaged (1)", "M a.lua  +1 -1" }, body(p))

        git_src.panel({}) -- toggle
        assert.is_nil(Panel.current())
    end)

    it("binds f/b quarter-scroll in the panel window too", function()
        local root = fresh_repo()
        write(root .. "/a.lua", "local x = 2\nreturn x\n")
        vim.cmd.edit(root .. "/a.lua")

        git_src.panel({})
        local p = Panel.current()
        local lhs = {}
        for _, m in ipairs(vim.api.nvim_buf_get_keymap(p.bufnr, "n")) do
            lhs[m.lhs] = true
        end
        assert.is_true(lhs["f"])
        assert.is_true(lhs["b"])
        -- invoking must not error (regression: the method was shadowed by the field)
        p:scroll("down")
        p:scroll("up")
        p:close()
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
        }, body(p))
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
        vim.api.nvim_win_set_cursor(p.winid, { file_line(p, "z.lua"), 0 }) -- staged: HEAD vs index
        p:select()
        local diff_buf = vim.api.nvim_win_get_buf(p.origin_win)
        vim.api.nvim_win_set_cursor(p.winid, { file_line(p, "a.lua"), 0 }) -- unstaged: index vs worktree
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
        -- window's buffer (View.current keys off the focused buffer)
        local function view_in_origin()
            vim.api.nvim_set_current_win(p.origin_win)
            return require("dipher.view").current()
        end
        -- a.lua is "MM": it appears in both the Staged and Unstaged sections
        vim.api.nvim_win_set_cursor(p.winid, { file_line(p, "a.lua", true), 0 })
        p:select()
        local v = view_in_origin()
        assert.are.equal(V1, v.model.old_text) -- HEAD
        assert.are.equal("local x = 2\nreturn x\n", v.model.new_text) -- index

        vim.api.nvim_win_set_cursor(p.winid, { file_line(p, "a.lua", false), 0 })
        p:select()
        v = view_in_origin()
        assert.are.equal("local x = 2\nreturn x\n", v.model.old_text) -- index
        assert.are.equal("local x = 3\nreturn x\n", v.model.new_text) -- worktree
        p:close()
    end)
end)

describe(":Dipher panel staging (§8.6 slice C)", function()
    local Panel = require("dipher.panel")

    -- the FileEntry for `path`, optionally pinned to staged/unstaged, via the panel
    -- meta (which is rebuilt by refresh after each op)
    local function entry_of(p, path, staged)
        for _, m in ipairs(p.meta) do
            if
                m.kind == "file"
                and m.entry.path == path
                and (staged == nil or m.entry.staged == staged)
            then
                return m.entry
            end
        end
    end
    local function file_line(p, path, staged)
        for i, m in ipairs(p.meta) do
            if
                m.kind == "file"
                and m.entry.path == path
                and (staged == nil or m.entry.staged == staged)
            then
                return i
            end
        end
    end
    local function keymaps(p)
        local lhs = {}
        for _, m in ipairs(vim.api.nvim_buf_get_keymap(p.bufnr, "n")) do
            lhs[m.lhs] = true
        end
        return lhs
    end

    it("stages and unstages the file under the cursor", function()
        local root = fresh_repo()
        write(root .. "/a.lua", "local x = 2\nreturn x\n") -- unstaged modify
        vim.cmd.edit(root .. "/a.lua")
        git_src.panel({})
        local p = Panel.current()
        assert.is_not_nil(entry_of(p, "a.lua", false)) -- starts unstaged

        vim.api.nvim_win_set_cursor(p.winid, { file_line(p, "a.lua", false), 0 })
        p:stage_op("stage")
        assert.is_not_nil(entry_of(p, "a.lua", true)) -- now staged
        assert.is_nil(entry_of(p, "a.lua", false))

        vim.api.nvim_win_set_cursor(p.winid, { file_line(p, "a.lua", true), 0 })
        p:stage_op("unstage")
        assert.is_not_nil(entry_of(p, "a.lua", false)) -- back to unstaged
        p:close()
    end)

    it("stages and unstages all", function()
        local root = fresh_repo()
        write(root .. "/a.lua", "local x = 2\nreturn x\n") -- modified
        write(root .. "/b.lua", "new\n") -- untracked
        vim.cmd.edit(root .. "/a.lua")
        git_src.panel({})
        local p = Panel.current()

        p:stage_op("stage_all")
        assert.is_not_nil(entry_of(p, "a.lua", true))
        assert.is_not_nil(entry_of(p, "b.lua", true)) -- untracked got added too

        p:stage_op("unstage_all")
        assert.is_nil(entry_of(p, "a.lua", true))
        p:close()
    end)

    it("discards a tracked file back to HEAD (after confirm)", function()
        local root = fresh_repo()
        write(root .. "/a.lua", "local x = 2\nreturn x\n")
        vim.cmd.edit(root .. "/a.lua")
        git_src.panel({})
        local p = Panel.current()
        vim.api.nvim_win_set_cursor(p.winid, { file_line(p, "a.lua"), 0 })

        local orig = vim.fn.confirm
        vim.fn.confirm = function()
            return 1
        end
        p:discard()
        vim.fn.confirm = orig

        assert.is_nil(entry_of(p, "a.lua")) -- no longer a change
        assert.are.equal(V1, table.concat(vim.fn.readfile(root .. "/a.lua"), "\n") .. "\n")
        p:close()
    end)

    it("discards an untracked file by deleting it", function()
        local root = fresh_repo()
        write(root .. "/u.lua", "untracked\n")
        vim.cmd.edit(root .. "/a.lua")
        git_src.panel({})
        local p = Panel.current()
        vim.api.nvim_win_set_cursor(p.winid, { file_line(p, "u.lua"), 0 })

        local orig = vim.fn.confirm
        vim.fn.confirm = function()
            return 1
        end
        p:discard()
        vim.fn.confirm = orig

        assert.are.equal(0, vim.fn.filereadable(root .. "/u.lua"))
        p:close()
    end)

    it("binds staging keys for the worktree source", function()
        local root = fresh_repo()
        write(root .. "/a.lua", "local x = 2\nreturn x\n")
        vim.cmd.edit(root .. "/a.lua")
        git_src.panel({})
        local p = Panel.current()
        local lhs = keymaps(p)
        for _, k in ipairs({ "s", "u", "S", "U", "X", "R" }) do
            assert.is_true(lhs[k])
        end
        p:close()
    end)

    it("does not bind staging keys for a rev-pair source", function()
        local root = fresh_repo()
        write(root .. "/a.lua", "local x = 2\nreturn x\n")
        git(root, "commit", "-q", "-am", "edit")
        vim.cmd.edit(root .. "/a.lua")
        git_src.panel({ rev = "HEAD~1..HEAD" })
        local p = Panel.current()
        local lhs = keymaps(p)
        assert.is_nil(lhs["s"])
        assert.is_nil(lhs["X"])
        p:close()
    end)
end)

describe(":Dipher (open_first)", function()
    local Panel = require("dipher.panel")

    -- p:select returns focus to the panel, so the View lives in the origin window
    local function view_in_origin(p)
        vim.api.nvim_set_current_win(p.origin_win)
        return require("dipher.view").current()
    end

    it("opens the panel and the first file's diff (DiffviewOpen-style)", function()
        local root = fresh_repo()
        write(root .. "/a.lua", "local x = 2\nreturn x\n")
        vim.cmd.edit(root .. "/a.lua")

        git_src.panel({ rev = {}, open_first = true })
        local p = Panel.current()
        assert.is_not_nil(p)
        local v = view_in_origin(p)
        assert.is_not_nil(v)
        assert.are.equal("a.lua", v.model.path)
        assert.are.equal(V1, v.model.old_text) -- index (nothing staged) == HEAD
        assert.are.equal("local x = 2\nreturn x\n", v.model.new_text) -- worktree
        -- the default footer is the HEAD commit (a 40-char hex sha)
        assert.are.equal("Showing changes for:", p.lines[#p.lines - 1])
        local sha = p.lines[#p.lines]
        assert.are.equal(40, #sha)
        assert.is_truthy(sha:match("^%x+$"))
        p:close()
    end)

    it("populates gitsigns status vars on the diff buffer for the statusline", function()
        local root = fresh_repo()
        write(root .. "/a.lua", "local x = 2\nreturn x\n") -- one changed line
        vim.cmd.edit(root .. "/a.lua")

        git_src.panel({ rev = {}, open_first = true })
        local p = Panel.current()
        local buf = vim.api.nvim_win_get_buf(p.origin_win)
        local dict = vim.b[buf].gitsigns_status_dict
        assert.is_not_nil(dict)
        assert.are.equal(1, dict.changed) -- "1" -> "2" is a single changed line
        assert.are.equal(0, dict.added)
        assert.are.equal(0, dict.removed)
        assert.are.equal("main", vim.b[buf].gitsigns_head)
        p:close()
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
        git_src.panel({ rev = "main...", open_first = true })
        local p = Panel.current()
        local v = view_in_origin(p)
        assert.is_not_nil(v)
        assert.are.equal(V1, v.model.old_text)
        assert.are.equal("local x = 3\nreturn x\n", v.model.new_text)
        assert.are.equal("main...", v.model.old_rev)
        p:close()
    end)

    it("]f from the diff window steps the panel selection, keeping focus in the diff", function()
        local root = fresh_repo()
        write(root .. "/a.lua", "local x = 2\nreturn x\n") -- unstaged
        write(root .. "/z.lua", "local z = 9\n")
        git(root, "add", "z.lua") -- staged -> two files in the set
        vim.cmd.edit(root .. "/a.lua")

        git_src.panel({ rev = {}, open_first = true })
        local p = Panel.current()
        vim.api.nvim_set_current_win(p.origin_win) -- emulate cursor in the diff window
        local v = require("dipher.view").current()
        local first = v.model.path

        v:step_file("next")
        -- focus stayed in the diff window (not bounced to the panel)
        assert.are.equal(p.origin_win, vim.api.nvim_get_current_win())
        -- and the one view re-sourced to a different file
        assert.are_not.equal(first, require("dipher.view").current().model.path)
        p:close()
    end)

    it("git.close tears down the panel and the diff view it drives", function()
        local root = fresh_repo()
        write(root .. "/a.lua", "local x = 2\nreturn x\n")
        vim.cmd.edit(root .. "/a.lua")

        git_src.panel({ rev = {}, open_first = true })
        local p = Panel.current()
        local v = view_in_origin(p)
        assert.is_true(p:is_open())
        assert.is_true(v:is_open())

        git_src.close()
        assert.is_nil(Panel.current()) -- panel gone
        assert.is_false(v:is_open()) -- on_close closed the driven view
    end)
end)
