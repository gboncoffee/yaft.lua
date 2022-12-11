g = vim.g
v = vim.api
command = v.nvim_create_user_command

if g.autoloaded_yaft then
    return
end

g.autoloaded_yaft = true

command("YaftToggle", function(args)
    require "yaft".toggle_yaft(args.args)
end, {
    complete = "file",
    nargs = "*",
})
command("YaftReload", function(args)
    require "yaft".reload_yaft(args.args)
end, {
    complete = "file",
    nargs = "*",
})
