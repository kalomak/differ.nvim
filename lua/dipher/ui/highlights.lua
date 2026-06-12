-- highlight group definitions for diff lines, word-level spans, threads, and the
-- file panel. structural groups are plain links; the panel's status + count groups
-- carry a semantic palette (green add / yellow modify / blue rename / orange
-- conflict / red delete) derived from the active theme with hex fallbacks, mirroring
-- the user's diffview/octo colours. all are set with `default = true` so explicit
-- user overrides win, and re-applied on `ColorScheme` so theme switches propagate

local M = {}

-- static links: body diff layers and structural panel chrome
---@type table<string, vim.api.keyset.highlight>
local LINKS = {
    dipherLineDelete = { link = "DiffDelete" },
    dipherLineAdd = { link = "DiffAdd" },
    dipherWordDelete = { link = "DiffText", bold = true },
    dipherWordAdd = { link = "DiffText", bold = true },
    dipherThreadRange = { link = "Visual" },
    -- file panel chrome (§8.6)
    dipherPanelHeader = { link = "Title" },
    dipherPanelRoot = { link = "Directory" },
    dipherPanelHelp = { link = "Comment" },
    dipherPanelDir = { link = "Directory" },
}

-- the first defined fg among `groups`, else `fallback` (a 0xRRGGBB int). lets the
-- palette ride the theme (e.g. green from `Added`/`GitSignsAdd`) yet still render
-- on bare themes that define none of them
---@param groups string[]
---@param fallback integer
---@return integer
local function fg_of(groups, fallback)
    for _, name in ipairs(groups) do
        local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
        if ok and hl and hl.fg then
            return hl.fg
        end
    end
    return fallback
end

-- semantic status palette, resolved against the current theme. fallbacks are the
-- tokyo Night-ish hexes the user's diffview config lands on
---@return table<string, integer>
local function palette()
    return {
        green = fg_of({ "Added", "diffAdded", "GitSignsAdd", "String" }, 0x9ece6a),
        yellow = fg_of({ "Changed", "diffChanged", "GitSignsChange", "WarningMsg" }, 0xe0af68),
        blue = fg_of({ "Function", "Directory" }, 0x7aa2f7),
        orange = fg_of({ "Number", "Constant" }, 0xff9e64),
        red = fg_of({ "Removed", "diffRemoved", "GitSignsDelete", "ErrorMsg" }, 0xf7768e),
        grey = fg_of({ "Comment", "NonText" }, 0x6c7086),
    }
end

-- map the panel's status/count groups onto the palette (status letters, §8.6
-- "Status presentation", and the right-aligned +N -M counts)
---@param p table<string, integer>
---@return table<string, vim.api.keyset.highlight>
local function status_groups(p)
    return {
        dipherPanelAdd = { fg = p.green },
        dipherPanelModify = { fg = p.yellow },
        dipherPanelDelete = { fg = p.red },
        dipherPanelRename = { fg = p.blue },
        dipherPanelUnmerged = { fg = p.orange },
        dipherPanelUntracked = { fg = p.green },
        dipherPanelCountAdd = { fg = p.green },
        dipherPanelCountDelete = { fg = p.red },
    }
end

-- (re)define all default highlight groups. `default = true` keeps user overrides
-- authoritative; the ColorScheme autocmd (registered once by setup) re-resolves the
-- palette so it tracks theme changes
local function apply()
    local groups = vim.tbl_extend("error", {}, LINKS, status_groups(palette()))
    for name, val in pairs(groups) do
        vim.api.nvim_set_hl(0, name, vim.tbl_extend("keep", { default = true }, val))
    end
end

local registered = false

function M.setup()
    apply()
    if not registered then
        registered = true
        vim.api.nvim_create_autocmd("ColorScheme", {
            group = vim.api.nvim_create_augroup("dipher.highlights", { clear = true }),
            callback = apply,
        })
    end
end

return M
