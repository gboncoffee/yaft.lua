g = vim.g
v = vim.api
command = v.nvim_create_user_command

if g.autoloaded_yaft then
    return
end

g.autoloaded_yaft = true

g._yaft_config = {
    yaft_exe_opener = require "yaft".default_exe_opener,
    file_delete_cmd = "rm",
    dir_delete_cmd  = "rm -r",
    git_delete_cmd  = "rm -rf",
    keys            = require "yaft".default_keys(),
    width           = 25,
    side            = "right",
    show_hidden     = true,
}

vim.cmd [[
hi link YaftDir Directory
hi link YaftExe Character
hi link YaftLink Question
hi link YaftRoot Todo
hi link YaftIndent Comment
]]

command("YaftToggle", function()
    require "yaft".toggle_yaft()
end, {})

require "yaft.low_level".init()
