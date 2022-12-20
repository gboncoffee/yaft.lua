local M = {}
local c = require "yaft.config"

M.printerr = function(msg)
    v.nvim_echo({ { msg, "Error" } }, true, {})
end

M.get_config_key = function(key)
    if not key then
        return c.config
    else
        return c.config[key]
    end
end

return M
