-- Highlight group definitions for diff lines, word-level spans, and threads

local M = {}

---@type table<string, vim.api.keyset.highlight>
local GROUPS = {
    dipherLineDelete = { link = "DiffDelete" },
    dipherLineAdd = { link = "DiffAdd" },
    dipherWordDelete = { link = "DiffText", bold = true },
    dipherWordAdd = { link = "DiffText", bold = true },
    dipherThreadRange = { link = "Visual" },
    -- File panel (§8.6)
    dipherPanelHeader = { link = "Title" },
    dipherPanelDir = { link = "Directory" },
    dipherPanelAdd = { link = "Added" },
    dipherPanelModify = { link = "Changed" },
    dipherPanelDelete = { link = "Removed" },
    dipherPanelRename = { link = "Changed" },
    dipherPanelUnmerged = { link = "DiffText" },
    dipherPanelUntracked = { link = "Comment" },
}

-- Define all default highlight groups (default = true so users can override)
function M.setup()
    for name, val in pairs(GROUPS) do
        vim.api.nvim_set_hl(0, name, vim.tbl_extend("keep", { default = true }, val))
    end
end

return M
