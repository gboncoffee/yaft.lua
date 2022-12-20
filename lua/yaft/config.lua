local M = {}

M.init = function()
    if not M.config then
        M.config = {
            yaft_exe_opener = require "yaft".default_exe_opener,
            file_delete_cmd = "rm",
            dir_delete_cmd  = "rm -r",
            git_delete_cmd  = "rm -rf",
            keys            = require "yaft".default_keys(),
            width           = 25,
            side            = "right",
            show_hidden     = true,
        }
    end
end

return M
