-- File panel (§8.6): the persistent sidebar listing a change set. Source-agnostic
-- by design — it renders FileEntry sections, owns fold/listing state and the
-- window, and calls `on_select(entry)` when a file is chosen. The local frontend
-- feeds it git changes (phase 2); the PR frontend reuses it verbatim (phase 4),
-- only swapping the model source. It owns *which file*; the View owns *how it
-- renders*, so selecting a file re-sources the existing View (separation of
-- concerns, §8.6). Pure tree/line logic lives in panel/tree.lua + panel/render.lua.

local tree = require("dipher.panel.tree")
local render = require("dipher.panel.render")

local ns = vim.api.nvim_create_namespace("dipher.panel")

---@type dipher.Panel|nil -- the live panel, for runtime API (Panel.current())
local current = nil

---@type table<string, string>
local STATUS_HL = {
    A = "dipherPanelAdd",
    M = "dipherPanelModify",
    D = "dipherPanelDelete",
    R = "dipherPanelRename",
    C = "dipherPanelRename",
    U = "dipherPanelUnmerged",
    ["?"] = "dipherPanelUntracked",
}

---@class dipher.panel.Section
---@field title string|nil
---@field entries dipher.FileEntry[]

---@class dipher.Panel
---@field bufnr integer
---@field winid integer|nil
---@field origin_win integer|nil
---@field sections dipher.panel.Section[]
---@field listing "tree"|"flat"
---@field collapsed table<string, boolean>
---@field on_select fun(entry: dipher.FileEntry)
---@field position string
---@field height integer
---@field width integer
---@field lines string[]
---@field meta dipher.panel.LineMeta[]
local Panel = {}
Panel.__index = Panel

---@class dipher.panel.Opts
---@field sections dipher.panel.Section[]
---@field on_select fun(entry: dipher.FileEntry)
---@field listing? "tree"|"flat"
---@field position? "bottom"|"top"|"left"|"right"
---@field height? integer
---@field width? integer

-- Build a panel (buffer only; the window is created on :open, so it's headless-
-- constructible for tests).
---@param opts dipher.panel.Opts
---@return dipher.Panel
function Panel.new(opts)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[bufnr].buftype = "nofile"
    -- "hide", not "wipe": set_position closes + reopens the window, and the panel
    -- owns the buffer's lifecycle explicitly via :close().
    vim.bo[bufnr].bufhidden = "hide"
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].filetype = "dipherpanel"
    vim.bo[bufnr].modifiable = false
    return setmetatable({
        bufnr = bufnr,
        sections = opts.sections,
        on_select = opts.on_select,
        listing = opts.listing or "tree",
        position = opts.position or "bottom",
        height = opts.height or 10,
        width = opts.width or 35,
        collapsed = {},
        lines = {},
        meta = {},
    }, Panel)
end

-- 1-based line of the first file row, or 1 if there are none.
---@return integer
function Panel:_first_file_line()
    for i, m in ipairs(self.meta) do
        if m.kind == "file" then
            return i
        end
    end
    return 1
end

-- Re-flatten the sections (honouring listing + fold state) and repaint the
-- buffer. Cursor line is preserved across re-renders (clamped).
function Panel:render()
    local blocks = {}
    for _, sec in ipairs(self.sections) do
        local root = tree.build(sec.entries)
        blocks[#blocks + 1] =
            { title = sec.title, rows = tree.rows(root, self.listing, self.collapsed) }
    end
    local out = render.lines(blocks)
    self.lines, self.meta = out.lines, out.meta

    vim.bo[self.bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, out.lines)
    vim.bo[self.bufnr].modifiable = false
    self:_highlight()
end

-- Paint section/dir/status highlights from the line metadata.
function Panel:_highlight()
    vim.api.nvim_buf_clear_namespace(self.bufnr, ns, 0, -1)
    for i, m in ipairs(self.meta) do
        local row = i - 1
        local eol = #self.lines[i]
        if m.kind == "header" then
            vim.api.nvim_buf_set_extmark(
                self.bufnr,
                ns,
                row,
                0,
                { end_col = eol, hl_group = "dipherPanelHeader" }
            )
        elseif m.kind == "dir" then
            vim.api.nvim_buf_set_extmark(
                self.bufnr,
                ns,
                row,
                m.name_col,
                { end_col = eol, hl_group = "dipherPanelDir" }
            )
        elseif m.kind == "file" then
            local hl = STATUS_HL[m.status]
            if hl then
                vim.api.nvim_buf_set_extmark(
                    self.bufnr,
                    ns,
                    row,
                    m.status_col,
                    { end_col = m.status_col + #m.status, hl_group = hl }
                )
            end
        end
    end
end

-- Replace the file-list model and repaint (used on refresh / source change).
---@param sections dipher.panel.Section[]
function Panel:set_sections(sections)
    self.sections = sections
    self:render()
end

-- Toggle the fold state of a directory path and repaint, keeping the cursor put.
---@param path string
function Panel:toggle_fold(path)
    self.collapsed[path] = not self.collapsed[path]
    local lnum = self.winid and vim.api.nvim_win_get_cursor(self.winid)[1] or 1
    self:render()
    if self.winid and vim.api.nvim_win_is_valid(self.winid) then
        vim.api.nvim_win_set_cursor(self.winid, { math.min(lnum, math.max(#self.lines, 1)), 0 })
    end
end

-- A non-panel window to open diffs in: the origin window if still valid, else any
-- other window, else a fresh split carved off the panel.
---@return integer
function Panel:_ensure_origin()
    if
        self.origin_win
        and self.origin_win ~= self.winid
        and vim.api.nvim_win_is_valid(self.origin_win)
    then
        return self.origin_win
    end
    for _, w in ipairs(vim.api.nvim_list_wins()) do
        if w ~= self.winid then
            self.origin_win = w
            return w
        end
    end
    vim.api.nvim_set_current_win(self.winid)
    vim.cmd("aboveleft split")
    self.origin_win = vim.api.nvim_get_current_win()
    return self.origin_win
end

-- Open `entry`'s diff in the main window, then return focus to the panel so file
-- browsing keeps flowing.
---@param entry dipher.FileEntry
function Panel:_open(entry)
    vim.api.nvim_set_current_win(self:_ensure_origin())
    self.on_select(entry)
    if self.winid and vim.api.nvim_win_is_valid(self.winid) then
        vim.api.nvim_set_current_win(self.winid)
    end
end

-- <CR>/o: open a file, or toggle a directory's fold.
function Panel:select()
    local m = self.meta[vim.api.nvim_win_get_cursor(self.winid)[1]]
    if not m then
        return
    end
    if m.kind == "dir" then
        self:toggle_fold(m.path)
    elseif m.kind == "file" then
        self:_open(m.entry)
    end
end

-- ]f / [f: move to the next/prev file row and open it (lockstep file stepping).
---@param direction "next"|"prev"
function Panel:goto_file(direction)
    local lnum = vim.api.nvim_win_get_cursor(self.winid)[1]
    local from, to, step = lnum + 1, #self.meta, 1
    if direction == "prev" then
        from, to, step = lnum - 1, 1, -1
    end
    for i = from, to, step do
        local m = self.meta[i]
        if m and m.kind == "file" then
            vim.api.nvim_win_set_cursor(self.winid, { i, 0 })
            self:_open(m.entry)
            return
        end
    end
end

-- Window appearance + buffer-local keymaps.
function Panel:_setup_window()
    local win = self.winid
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = "no"
    vim.wo[win].foldcolumn = "0"
    vim.wo[win].wrap = false
    vim.wo[win].cursorline = true
    if self.position == "left" or self.position == "right" then
        vim.wo[win].winfixwidth = true
    else
        vim.wo[win].winfixheight = true
    end

    local function map(lhs, fn, desc)
        vim.keymap.set(
            "n",
            lhs,
            fn,
            { buffer = self.bufnr, desc = "dipher panel: " .. desc, nowait = true }
        )
    end
    map("<CR>", function()
        self:select()
    end, "open / toggle fold")
    map("o", function()
        self:select()
    end, "open / toggle fold")
    map("]f", function()
        self:goto_file("next")
    end, "next file")
    map("[f", function()
        self:goto_file("prev")
    end, "previous file")
    map("za", function()
        local m = self.meta[vim.api.nvim_win_get_cursor(self.winid)[1]]
        if m and m.kind == "dir" then
            self:toggle_fold(m.path)
        end
    end, "toggle fold")
    map("q", function()
        self:close()
    end, "close panel")
end

-- Create the split in the configured position, bind the buffer, set window opts.
function Panel:_open_window()
    if self.position == "top" then
        vim.cmd(("topleft %dsplit"):format(self.height))
    elseif self.position == "left" then
        vim.cmd(("topleft %dvsplit"):format(self.width))
    elseif self.position == "right" then
        vim.cmd(("botright %dvsplit"):format(self.width))
    else -- bottom (default)
        vim.cmd(("botright %dsplit"):format(self.height))
    end
    self.winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(self.winid, self.bufnr)
    self:_setup_window()
end

-- Close the panel window but keep the buffer + state (for re-positioning).
function Panel:_close_window()
    if self:is_open() then
        pcall(vim.api.nvim_win_close, self.winid, true)
    end
    self.winid = nil
end

-- Open the panel in its position and focus it.
---@return dipher.Panel
function Panel:open()
    self.origin_win = vim.api.nvim_get_current_win()
    self:_open_window()
    self:render()
    vim.api.nvim_win_set_cursor(self.winid, { self:_first_file_line(), 0 })
    current = self
    return self
end

---@return boolean
function Panel:is_open()
    return self.winid ~= nil and vim.api.nvim_win_is_valid(self.winid)
end

-- Restore the cursor line after a re-render/reposition (clamped to the content).
---@param lnum integer
function Panel:_restore_cursor(lnum)
    if self:is_open() then
        pcall(
            vim.api.nvim_win_set_cursor,
            self.winid,
            { math.min(lnum, math.max(#self.lines, 1)), 0 }
        )
    end
end

-- Runtime API (§8.3-style per-view control, not setup config) ----------------

-- Switch tree <-> flat listing live.
---@param listing "tree"|"flat"
function Panel:set_listing(listing)
    self.listing = listing
    if self:is_open() then
        local lnum = vim.api.nvim_win_get_cursor(self.winid)[1]
        self:render()
        self:_restore_cursor(lnum)
    end
end

function Panel:toggle_listing()
    self:set_listing(self.listing == "tree" and "flat" or "tree")
end

-- Move the panel to a new position live, preserving the buffer, fold state, and
-- the main (origin) window.
---@param position "bottom"|"top"|"left"|"right"
function Panel:set_position(position)
    self.position = position
    if not self:is_open() then
        return
    end
    local lnum = vim.api.nvim_win_get_cursor(self.winid)[1]
    local origin = self.origin_win
    self:_close_window()
    if origin and vim.api.nvim_win_is_valid(origin) then
        vim.api.nvim_set_current_win(origin)
    end
    self:_open_window()
    self.origin_win = origin
    self:render()
    self:_restore_cursor(lnum)
end

-- Close the panel window and wipe its buffer.
function Panel:close()
    self:_close_window()
    if vim.api.nvim_buf_is_valid(self.bufnr) then
        vim.api.nvim_buf_delete(self.bufnr, { force = true })
    end
    if current == self then
        current = nil
    end
end

-- The live panel, if one is open — the entry point for the runtime API.
---@return dipher.Panel|nil
function Panel.current()
    return current
end

return Panel
