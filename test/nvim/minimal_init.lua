-- busted helper for the headless-nvim suite (wired via .busted `nvim.helper`)
-- captures notifications into `_G.notifs` so they don't leak into the progress
-- output; specs can inspect the table if they ever need to assert on a message
_G.notifs = {}
vim.notify = function(msg, level)
    _G.notifs[#_G.notifs + 1] = { msg = msg, level = level }
end
