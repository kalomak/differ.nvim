-- Local git source: the runtime half of the diff source layer (§8.1). Resolves a
-- repo, turns a rev spec (rev.lua) into concrete old/new content, and opens a
-- View. Local diffs are fast and offline, so reads run synchronously here — the
-- latency discipline (§7.5) is about the PR sidecar hot path, not local git.
-- Pure parsing/grammar lives in git/rev.lua; this module only does I/O + wiring.

local rev = require("dipher.git.rev")

local M = {}

---@param msg string
---@param level integer|nil
local function notify(msg, level)
    vim.notify("dipher: " .. msg, level or vim.log.levels.INFO)
end

-- Run git in `cwd`. Returns stdout on success, or nil + stderr on failure.
---@param args string[]
---@param cwd string
---@return string|nil stdout, string|nil stderr
local function git(args, cwd)
    local cmd = { "git" }
    vim.list_extend(cmd, args)
    local res = vim.system(cmd, { cwd = cwd, text = true }):wait()
    if res.code ~= 0 then
        return nil, res.stderr
    end
    return res.stdout
end

local function chomp(s)
    return (s:gsub("%s+$", ""))
end

-- Repo root containing `path` (a file or directory), or nil if not in a repo.
---@param path string
---@return string|nil
function M.root(path)
    local dir = vim.fn.isdirectory(path) == 1 and path or vim.fs.dirname(path)
    local out = git({ "rev-parse", "--show-toplevel" }, dir)
    return out and chomp(out) or nil
end

-- Resolve an unresolved merge_base ref to a concrete rev; other refs pass through.
-- Returns nil on failure (e.g. unrelated histories), with a notification.
---@param ref dipher.git.Ref
---@param root string
---@return dipher.git.Ref|nil
local function resolve_ref(ref, root)
    if ref.kind ~= "merge_base" then
        return ref
    end
    local out = git({ "merge-base", ref.base, ref.head }, root)
    if not out then
        notify(("no merge-base between %s and %s"):format(ref.base, ref.head), vim.log.levels.ERROR)
        return nil
    end
    return { kind = "rev", rev = chomp(out), label = ref.label }
end

-- Read a side's content for `relpath` (repo-root-relative). Returns the content
-- (possibly ""), or nil when the file is absent on that side (added/deleted) —
-- callers treat nil as an empty file so the diff renders an add/delete.
---@param ref dipher.git.Ref
---@param root string
---@param relpath string
---@return string|nil
function M.read(ref, root, relpath)
    if ref.kind == "worktree" then
        local abs = root .. "/" .. relpath
        if vim.fn.filereadable(abs) == 0 then
            return nil
        end
        local fd = io.open(abs, "rb")
        if not fd then
            return nil
        end
        local data = fd:read("*a")
        fd:close()
        return data
    end
    -- index (stage 0) is `:path`; a rev is `<rev>:path`
    local spec = (ref.kind == "index" and ":" or (ref.rev .. ":")) .. relpath
    return git({ "show", spec }, root) -- nil if the path is absent in that tree
end

-- List changed files for a resolved source (used by the picker/panel, §8.6).
---@param source dipher.git.Source
---@param root string
---@return dipher.git.ChangedFile[]
function M.changed_files(source, root)
    local args = { "diff", "--name-status", "-z" }
    vim.list_extend(args, rev.diff_args(source))
    local out = git(args, root)
    if not out then
        return {}
    end
    return rev.parse_name_status(out)
end

-- Resolve a source's refs to concrete revs (merge_base -> rev). Returns nil if a
-- merge-base can't be found. Do this once per source, then open each file against
-- the result; the picker and panel both share it.
---@param source dipher.git.Source
---@param root string
---@return dipher.git.Source|nil
function M.resolve(source, root)
    local old = resolve_ref(source.old, root)
    local new = resolve_ref(source.new, root)
    if not (old and new) then
        return nil
    end
    return { old = old, new = new }
end

-- Open the diff for one changed file under an already-resolved source. Renames
-- read the old side from `previous_path`; an added/deleted side reads as empty.
---@param source dipher.git.Source -- resolved (no merge_base refs)
---@param root string
---@param file dipher.git.ChangedFile
---@return dipher.View
function M.open_file(source, root, file)
    local old_path = file.previous_path or file.path
    return require("dipher").diff({
        path = file.path,
        old_rev = source.old.label,
        new_rev = source.new.label,
        old_text = M.read(source.old, root, old_path) or "",
        new_text = M.read(source.new, root, file.path) or "",
    })
end

-- The repo to operate on: the current file's repo if it's a real file, else cwd.
---@return string|nil
local function repo_root()
    local file = vim.api.nvim_buf_get_name(0)
    local anchor = (file ~= "" and vim.fn.filereadable(file) == 1) and file or vim.fn.getcwd()
    return M.root(anchor)
end

-- A changed-file's display line for the picker: status, with rename arrow.
---@param file dipher.git.ChangedFile
---@return string
local function format_item(file)
    local name = file.previous_path and (file.previous_path .. " → " .. file.path) or file.path
    return ("%s  %s"):format(file.status, name)
end

-- :Dipher [revspec] — the MVP changed-file picker (§8.1). Resolve the source, list
-- its changed files, and on selection open that file's diff. The persistent file
-- panel (§8.6) supersedes this as the primary surface but coexists with it.
---@param fargs string[]
function M.open(fargs)
    local root = repo_root()
    if not root then
        return notify("not inside a git repository", vim.log.levels.WARN)
    end
    local source = M.resolve(rev.source(fargs), root)
    if not source then
        return
    end
    local files = M.changed_files(source, root)
    if #files == 0 then
        return notify("no changes for this source")
    end
    vim.ui.select(files, {
        prompt = "Dipher — changed files",
        format_item = format_item,
    }, function(choice)
        if choice then
            M.open_file(source, root, choice)
        end
    end)
end

return M
