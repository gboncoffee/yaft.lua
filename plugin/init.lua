g = vim.g
v = vim.api
command = v.nvim_create_user_command

if g.autoloaded_yaft then
    return
end

g.autoloaded_yaft = true

require "yaft.config".init()

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
