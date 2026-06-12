-- Public entry point: setup() and the top-level API surface

local config = require("dipher.config")

local M = {}

---@type dipher.Config|nil
M.config = nil

-- Resolve options and register highlight groups; call once from user config
---@param opts table|nil
function M.setup(opts)
    M.config = config.resolve(opts)
    require("dipher.ui.highlights").setup()
end

-- Return the resolved config, defaulting if setup() was never called
---@return dipher.Config
function M.get_config()
    return M.config or config.defaults
end

---@class dipher.DiffSpec
---@field old_text string
---@field new_text string
---@field path string|nil
---@field old_rev string|nil
---@field new_rev string|nil
---@field layout dipher.Layout|nil
---@field context integer|nil

-- Open a View from an already-built DiffModel. The git frontend and panel use
-- this; `opts` overrides the layout/context defaults per-view.
---@param model dipher.DiffModel
---@param opts { layout?: dipher.Layout, context?: integer }|nil
---@return dipher.View
function M.diff_model(model, opts)
    require("dipher.ui.highlights").setup()
    local cfg = M.get_config()
    opts = opts or {}
    return require("dipher.view")
        .new(model, {
            layout = opts.layout or cfg.layout,
            context = opts.context or cfg.context,
            deep_diff = cfg.deep_diff,
        })
        :open()
end

-- Open a diff view for an old/new text pair. The frontends (local git, PR) build
-- their DiffModel from real sources; this is the shared, source-agnostic entry.
---@param spec dipher.DiffSpec
---@return dipher.View
function M.diff(spec)
    local model = require("dipher.model.diff").build({
        path = spec.path or "",
        old_rev = spec.old_rev or "OLD",
        new_rev = spec.new_rev or "NEW",
        old_text = spec.old_text,
        new_text = spec.new_text,
    })
    return M.diff_model(model, { layout = spec.layout, context = spec.context })
end

-- Open a local git diff for the current file from a rev spec (§8.1). The entry
-- point keymaps bind to this — e.g. `require("dipher").open("main...")` for the
-- branch-total diff. A string is one rev token; pass a table for multi-arg forms.
---@param spec string|string[]|nil
---@return dipher.View|nil
function M.open(spec)
    local args = {}
    if type(spec) == "table" then
        args = spec
    elseif type(spec) == "string" and spec ~= "" then
        args = { spec }
    end
    return require("dipher.git").open(args)
end

-- Open (or toggle) the file panel over a local git change set (§8.6). `opts` are
-- runtime, not setup config: `rev` (rev spec, string or args), `position`
-- ("bottom"|"top"|"left"|"right"), `listing` ("tree"|"flat"), `height`, `width`.
-- The live panel is reachable via `require("dipher.panel").current()` for runtime
-- tweaks, e.g. `:current():set_position("left")` / `:toggle_listing()`.
---@param opts table|nil
---@return dipher.Panel|nil
function M.panel(opts)
    return require("dipher.git").panel(opts or {})
end

return M
