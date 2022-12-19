local M = {}

-- Gets file extension from a filename.
--
--@param filename (string) filename to get extension.
M.get_extension = function(filename)
    local ext = filename
    local i = nil
    while true do
        i = string.find(ext, ".", 1, true)
        if not i then break end
        ext = string.sub(ext, i + 1)
    end
    if ext ~= filename then
        return ext
    end
    return ""
end

-- Gets full parent directory path of another.
--
--@param fullpath (string) path to return directory of.
M.get_dir_path_from_fullpath = function(fullpath)
    local lastslash = 1

    for c = 1, (string.len(fullpath) - 1) do
        if string.sub(fullpath, c, c) == "/" then
            lastslash = c
        end
    end

    return string.sub(fullpath, 1, lastslash - 1)
end

-- Gets base entry name from a full path.
--
--@param fullpath (string) self-explanatory.
--@returns (string) self-explanatory.
M.get_base_name_from_fullpath = function(fullpath)
    while true do
        local idx = string.find(fullpath, "/")
        if idx then
            fullpath = string.sub(fullpath, idx + 1, -1)
        else
            return fullpath
        end
    end
end

return M
