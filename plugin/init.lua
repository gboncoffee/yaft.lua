g = vim.g
v = vim.api
command = v.nvim_create_user_command

if g.autoloaded_yaft then
    return
end

g.autoloaded_yaft = true

vim.cmd [[
hi link YaftDir Directory
hi link YaftExe Character
hi link YaftLink Question
hi link YaftRoot Todo
]]

-- defaults
g._yaft_config = {
    yaft_exe_opener = function(entry, fullpath)
        local has_run, run = pcall(require, "run")
        if has_run then
            run.run(fullpath)
            return
        end
        v.nvim_win_call(require "yaft"._get_first_usable_window(), function()
            vim.cmd("split | term " .. fullpath)
        end)
    end,
    file_delete_cmd = "rm",
    dir_delete_cmd  = "rm -r",
    git_delete_cmd  = "rm -rf",
    keys = require "yaft".default_keys()
}

command("YaftToggle", function()
    require "yaft".toggle_yaft()
end, {})
