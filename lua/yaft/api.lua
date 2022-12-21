local l = require "yaft.low_level"

local M = {}

-- Creates a subtree in an entry. Keeps opened directories already opened and
-- recursively creates their subtrees.
--
--@param entry (table) entry to create subtree.
--@param fullpath (string) fullpath of the entry to create subtree.
M.check_dir = function(entry, fullpath)
    entry.checked = true
    entry.children = l.create_subtree_from_dir(fullpath, entry.children)
end

-- Same as M.check_dir() but for the root.
M.reload_root = function()
    l.tree.tree = l.create_subtree_from_dir(l.tree.name, l.tree.tree)
end

M.check_dir_or_reload_root = function(entry, fullpath)
end

-- Seeks for a window in which to place a buffer.
--
--@returns (number) choosen window handler.
M.get_first_usable_window = function()
    -- basically stolen and converted to Lua from the NERDTree ;)

    for _, win in ipairs(v.nvim_list_wins()) do
        local buf = v.nvim_win_get_buf(win)
        if v.nvim_buf_get_option(buf, "buftype") == ""
            and (not v.nvim_win_get_option(win, "previewwindow"))
            and (not (v.nvim_buf_get_option(buf, "modified") and v.nvim_get_option("hidden")))
            then
            return win
        end
    end

    return nil
end

-- Gets selected entry. Returned entry is nil if no "valid" entry selected
-- (e.g., cursor is in the tree name, or in a trailing line of empty opened
-- dirs). Returns dummy fullpath (ends with ..) on the second case.
--
--@returns (table, string) entry and entry full path.
M.get_current_entry = function()
    local curpos = vim.fn.getpos('.')[2] - 1
    if curpos == 0 then
        return nil, l.tree.name .. "/.." -- used as dummy name because it's impossible
    -- if tree don't have any children
    elseif curpos == 1 and l.get_number_of_visible_children(l.tree.tree) == 0 then
        return nil, l.tree.name .. "/.."
    end

    local cur, entry, fullpath = l.iterate_to_n_entry(0, curpos, l.tree.tree, l.tree.name)

    return entry, fullpath
end

-- Gets parent entry from a fullpath.
--
--@param fullpath (string) fullpath of the entry to search.
--@returns (table) parent entry.
M.get_parent_entry = function(fullpath)
    return l.get_parent_entry_from_fullpath(fullpath, l.tree.tree)
end

return M
