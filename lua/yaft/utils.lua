local M = {}

M.printerr = function(msg)
    v.nvim_echo({ { msg, "Error" } }, true, {})
end

M.get_config_key = function(key)
    if not key then
        return vim.g._yaft_config
    else
        return vim.g._yaft_config[key]
    end
end

return M
