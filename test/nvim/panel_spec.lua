-- Runs under headless nvim: drives the Panel component through a real window —
-- rendering, selection callback, fold, and the runtime listing/position API.
-- Fed plain FileEntry lists (no git), since the panel is source-agnostic.
local Panel = require("dipher.panel")

local function fe(path, status)
    return { path = path, status = status or "M", additions = 0, deletions = 0 }
end

local function lines(p)
    return vim.api.nvim_buf_get_lines(p.bufnr, 0, -1, false)
end

local function panel(entries, opts)
    vim.cmd("silent! only")
    local picked = {}
    local p = Panel.new(vim.tbl_extend("force", {
        sections = { { entries = entries } },
        on_select = function(e)
            picked[#picked + 1] = e
        end,
    }, opts or {}))
    return p, picked
end

describe("panel rendering", function()
    it("renders a folded tree, dirs before files, cursor on first file", function()
        local p = panel({ fe("a.lua"), fe("src/b.lua") })
        p:open()
        assert.are.same({ "▾ src/", "  M b.lua", "M a.lua" }, lines(p))
        assert.are.equal(2, vim.api.nvim_win_get_cursor(p.winid)[1]) -- first file row
        p:close()
    end)

    it("toggle_listing flattens to full paths", function()
        local p = panel({ fe("a.lua"), fe("src/b.lua") })
        p:open()
        p:toggle_listing()
        assert.are.same({ "M src/b.lua", "M a.lua" }, lines(p))
        p:close()
    end)
end)

describe("panel navigation", function()
    it("opens the file under the cursor via on_select", function()
        local p, picked = panel({ fe("a.lua"), fe("b.lua") })
        p:open()
        vim.api.nvim_win_set_cursor(p.winid, { 1, 0 }) -- a.lua
        p:select()
        assert.are.equal("a.lua", picked[1].path)
        p:close()
    end)

    it("]f steps to the next file and opens it", function()
        local p, picked = panel({ fe("a.lua"), fe("b.lua") })
        p:open()
        vim.api.nvim_win_set_cursor(p.winid, { 1, 0 })
        p:goto_file("next")
        assert.are.equal(2, vim.api.nvim_win_get_cursor(p.winid)[1])
        assert.are.equal("b.lua", picked[#picked].path)
        p:close()
    end)

    it("toggles a directory fold from its row, hiding children", function()
        local p = panel({ fe("src/a.lua"), fe("src/b.lua") })
        p:open()
        vim.api.nvim_win_set_cursor(p.winid, { 1, 0 }) -- src/
        p:select() -- dir row => toggle fold
        assert.are.same({ "▸ src/" }, lines(p))
        p:close()
    end)
end)

describe("panel runtime position", function()
    it("re-positions live, keeping the panel open and its buffer", function()
        local p = panel({ fe("a.lua") })
        p:open()
        local buf, win = p.bufnr, p.winid
        p:set_position("left")
        assert.is_true(p:is_open())
        assert.are.equal(buf, p.bufnr) -- same buffer, just re-windowed
        assert.is_false(win == p.winid) -- new window
        p:close()
    end)

    it("current() tracks the open panel and clears on close", function()
        local p = panel({ fe("a.lua") })
        p:open()
        assert.are.equal(p, Panel.current())
        p:close()
        assert.is_nil(Panel.current())
    end)
end)
