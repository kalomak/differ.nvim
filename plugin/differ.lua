-- command registration; loaded once on startup

if vim.g.loaded_differ then
    return
end
vim.g.loaded_differ = true

vim.api.nvim_create_user_command("Differ", function(opts)
    require("differ.command").dispatch(opts.fargs)
end, {
    nargs = "*",
    desc = "differ diff viewer",
    complete = function(arglead, cmdline)
        return require("differ.command").complete(arglead, cmdline)
    end,
})
