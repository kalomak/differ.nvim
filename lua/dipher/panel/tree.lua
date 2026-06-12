-- file-tree model for the panel (§8.6): turn a flat FileEntry list into a folded
-- directory tree, and flatten it to display rows (tree or flat). pure lua, no
-- nvim API; the structural logic is unit-testable; rendering/highlighting and
-- the window live in panel/init.lua

local M = {}

---@class dipher.FileEntry
---@field path string
---@field status "A"|"M"|"D"|"R"|"C"|"U"|"?"
---@field additions integer
---@field deletions integer
---@field staged boolean|nil       -- which local section it belongs to
---@field previous_path string|nil -- renames/copies
---@Field viewed boolean|nil       -- PR only (§8.2)

---@class dipher.panel.Node
---@field kind "dir"|"file"
---@field name string                       -- display segment (folded path for dirs)
---@field path string                        -- full path; collapse key (dir) / entry key (file)
---@field children dipher.panel.Node[]|nil   -- dirs only
---@field entry dipher.FileEntry|nil         -- files only

---@class dipher.panel.Row
---@field depth integer
---@field kind "dir"|"file"
---@field name string
---@field path string
---@field collapsed boolean|nil   -- dir rows
---@field entry dipher.FileEntry|nil

---@param p string
---@return string[]
local function split_path(p)
    local parts, start = {}, 1
    while true do
        local s = p:find("/", start, true)
        if not s then
            parts[#parts + 1] = p:sub(start)
            break
        end
        parts[#parts + 1] = p:sub(start, s - 1)
        start = s + 1
    end
    return parts
end

-- sort each dir's children: directories first, then files, alphabetical within
---@param node dipher.panel.Node
local function sort_tree(node)
    if node.kind ~= "dir" then
        return
    end
    table.sort(node.children, function(a, b)
        if a.kind ~= b.kind then
            return a.kind == "dir"
        end
        return a.name < b.name
    end)
    for _, c in ipairs(node.children) do
        sort_tree(c)
    end
end

-- collapse single-child directory chains into one node (common-prefix folding,
-- gitHub/diffview-style): a dir whose only child is a dir becomes "parent/child".
-- recurses children first so chains fold maximally. the root is never folded
---@param node dipher.panel.Node
---@return dipher.panel.Node
local function fold(node)
    if node.kind == "file" then
        return node
    end
    for i, c in ipairs(node.children) do
        node.children[i] = fold(c)
    end
    while #node.children == 1 and node.children[1].kind == "dir" do
        local only = node.children[1]
        node.name = node.name == "" and only.name or (node.name .. "/" .. only.name)
        node.path = only.path
        node.children = only.children
    end
    return node
end

-- build a folded directory tree from a flat entry list
---@param entries dipher.FileEntry[]
---@return dipher.panel.Node root
function M.build(entries)
    local root = { kind = "dir", name = "", path = "", children = {} }
    local dirs = { [""] = root } -- dir path -> node, so siblings share a parent
    for _, e in ipairs(entries) do
        local parts = split_path(e.path)
        local parent, acc = root, ""
        for i = 1, #parts - 1 do
            acc = acc == "" and parts[i] or (acc .. "/" .. parts[i])
            local dir = dirs[acc]
            if not dir then
                dir = { kind = "dir", name = parts[i], path = acc, children = {} }
                dirs[acc] = dir
                parent.children[#parent.children + 1] = dir
            end
            parent = dir
        end
        parent.children[#parent.children + 1] =
            { kind = "file", name = parts[#parts], path = e.path, entry = e }
    end
    sort_tree(root)
    for i, c in ipairs(root.children) do
        root.children[i] = fold(c)
    end
    return root
end

-- flatten the tree to display rows. `listing` is "tree" (nested, honouring the
-- `collapsed` set of dir paths) or "flat" (leaves only, full paths)
---@param root dipher.panel.Node
---@param listing "tree"|"flat"
---@param collapsed table<string, boolean>|nil
---@return dipher.panel.Row[]
function M.rows(root, listing, collapsed)
    collapsed = collapsed or {}
    local out = {}
    if listing == "flat" then
        local function leaves(node)
            for _, c in ipairs(node.children or {}) do
                if c.kind == "file" then
                    out[#out + 1] = {
                        depth = 0,
                        kind = "file",
                        name = c.entry.path,
                        path = c.path,
                        entry = c.entry,
                    }
                else
                    leaves(c)
                end
            end
        end
        leaves(root)
        return out
    end
    local function walk(node, depth)
        for _, c in ipairs(node.children or {}) do
            if c.kind == "dir" then
                local is_collapsed = collapsed[c.path] == true
                out[#out + 1] = {
                    depth = depth,
                    kind = "dir",
                    name = c.name,
                    path = c.path,
                    collapsed = is_collapsed,
                }
                if not is_collapsed then
                    walk(c, depth + 1)
                end
            else
                out[#out + 1] =
                    { depth = depth, kind = "file", name = c.name, path = c.path, entry = c.entry }
            end
        end
    end
    walk(root, 0)
    return out
end

return M
