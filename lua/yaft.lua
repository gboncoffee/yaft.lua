v = vim.api

local M = {}

-- TODO: 
-- - Entry deletion
-- - Confirmation when deleting non-empty dirs with -r and git repos with -rf

-- init plugin {{{

-- entry creator {{{
-- (funny history: I could use metatables and stuff to emulate oop, but for
-- some reason the table entries were messy, so I couldn't do that. but simply
-- using a helper function like I would do in C)
local new_entry = function(name, class)
    return {
        name     = name,
        class    = class, -- file, dir, exe, link
        children = {},
        opened   = false,
        checked  = false,
    }
end -- }}}

M._tree = {}
M._keys = {}

-- }}}

-- low level plugin {{{

M._setup_buffer_keys = function() -- {{{
    for key, func in pairs(vim.g._yaft_config.keys) do
        vim.keymap.set("n", key, func, { buffer = M._tree_buffer })
    end
end -- }}}

M._ensure_buf_exists = function() -- {{{
    if not M._tree_buffer or not v.nvim_buf_is_valid(M._tree_buffer) then
        M._tree_buffer = v.nvim_create_buf(false, true)
        M._setup_buffer_keys()
        v.nvim_buf_set_option(M._tree_buffer, "modifiable", false)
    end
end -- }}}

--@param side (string) "left" or "right"
--@param width (number) number of columns (yet not implemented, changes nothing)
--@returns (boolean) true if just opened it, false if it was already opened
M._open_yaft_window = function(side, width) -- {{{

    if M._yaft_window and v.nvim_win_is_valid(M._yaft_window) then
        return false
    end

    M._ensure_buf_exists()

    local col = 0
    if side == "right" then
        col = math.ceil(vim.o.columns - 20)
    end

    M._old_window  = v.nvim_get_current_win()
    M._yaft_window = v.nvim_open_win(M._tree_buffer, true, {
        relative = "editor",
        col      = col,
        row      = 0,
        width    = width,
        height   = vim.o.lines,
    })

    return true
end -- }}}

-- Writes the lines (i.e. the entries from a subtree) to the plugin buffer.
-- Recursive.
--
--@param pad (number) indentation, i.e., how deep in the subtree it is.
--@param line (number) next line in the buffer (0-indexed).
--@param subtree (table) the tree of entries it'll be basing those lines in.
--@returns (number) next line in the buffer (0-indexed).
M._create_buffer_lines = function(pad, line, subtree) -- {{{

    local padstr = ""
    for i = 0,pad do
        padstr = padstr .. "| "
    end

    -- we use it to add an empty line if the dir is opened but have no children
    -- (so making easy to see that it's actually opened)
    local actually_has_children = false
    for _, entry in ipairs(subtree) do
        actually_has_children = true

        local highlight = ""
        local sufix     = ""

        if entry.class == "dir" then
            highlight = "YaftDir"
            sufix     = "/"
        elseif entry.class == "exe" then
            highlight = "YaftExe"
            sufix     = "*"
        elseif entry.class == "link" then
            highlight = "YaftLink"
            sufix     = "@"
        end

        v.nvim_buf_set_lines(M._tree_buffer, line, line + 1, false, { padstr .. entry.name .. sufix })
        line = line + 1

        v.nvim_buf_add_highlight(M._tree_buffer, -1, highlight, line - 1, (pad + 1) * 2, -1)

        if entry.opened then
            line = M._create_buffer_lines(pad + 1, line, entry.children)
        end
    end

    if not actually_has_children then
        vim.fn.appendbufline(M._tree_buffer, line, padstr)
        line = line + 1
    end

    return line
end -- }}}

-- Updates the entire buffer. Don't mind cursor jumping, it'll not.
M._update_buffer = function() -- {{{
    M._ensure_buf_exists()

    -- empty buffer
    v.nvim_buf_set_option(M._tree_buffer, "modifiable", true)

    -- add root name
    local rootname = M._tree.name
    rootname = string.gsub(rootname, os.getenv("HOME"), "~")
    v.nvim_buf_set_lines(M._tree_buffer, 0, 1, false, { rootname })
    v.nvim_buf_add_highlight(M._tree_buffer, -1, "YaftRoot", 0, 0, -1)

    -- add other entries
    local last_line = M._create_buffer_lines(0, 1, M._tree.tree)
    v.nvim_buf_set_lines(M._tree_buffer, last_line, -1, false, {})

    v.nvim_buf_set_option(M._tree_buffer, "modifiable", false)
end -- }}}

-- Creates a tree of entries from a directory.
--
--@param dir (string) directory to base the subtree in.
--@returns (table) subtree created.
M._create_subtree_from_dir = function(dir) -- {{{
    -- -F == append file indicator (*/=>@|)
    -- -A == all without . and ..
    -- -1 because for ocult forces the command was thinking that it was running
    -- interactively
    local ls = io.popen("ls --group-directories-first -F -A -1 '" .. dir .. "'")
    local subtree = {}

    for entry in ls:lines() do
        local class    = "file"
        local realname = entry
        local sufix    = string.sub(realname, -1)
        if sufix == "/" then
            class = "dir"
        elseif sufix == "*" then
            class = "exe"
        elseif sufix == "@" then
            class = "link"
        end

        if string.find("*/=>@|", sufix) then
            realname = string.sub(realname, 1, -2)
        end

        table.insert(subtree, new_entry(realname, class))
    end

    return subtree
end -- }}}

-- The most important function of the module. Traverses a subtree of entries,
-- counting until it reaches the n entry listed. Recursive.
--
--@param cur (number) current entry. When this equals n, it reached the desired
-- entry.
--@param n (number) desired entry index.
--@param subtree (table) tree of entries to traverse.
--@param fullpath (string) path in which it appends each directory entry path,
-- to create a full desired entry path.
--@returns (number, table, string) next entry number, desired entry and desired
-- entry full path.
M._iterate_to_n_entry = function(cur, n, subtree, fullpath) -- {{{

    for _, entry in pairs(subtree) do
        if cur == n then
            return cur, entry, fullpath .. "/" .. entry.name
        end

        cur = cur + 1
        if entry.class == "dir" and entry.opened then
            if #entry.children == 0 then
                if cur == n then
                    -- .. is a dummy name we'll be using as "the current entry
                    -- is inside a empty dir"
                    return cur, nil, fullpath .. "/" .. entry.name .. "/" .. ".."
                end
                cur = cur + 1
                goto continue
            end
            cur, entry, new_full_path = M._iterate_to_n_entry(cur, 
                                                              n, 
                                                              entry.children, 
                                                              fullpath .. "/" .. entry.name)
            if entry then
                return cur, entry, new_full_path
            end
            ::continue::
        end
    end

    return cur, nil, fullpath
end -- }}}

-- Seeks for a window in which to place a buffer.
--
--@returns (number) choosen window handler.
M._get_first_usable_window = function() -- {{{
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
end -- }}}

-- Gets full parent directory path of an entry.
--
--@param fullpath (string) path to return directory of.
M._get_dir_path_from_fullpath = function(fullpath) -- {{{
    local lastslash = 1

    for c = 1, (string.len(fullpath) - 1) do
        if string.sub(fullpath, c, c) == "/" then
            lastslash = c
        end
    end

    return string.sub(fullpath, 1, lastslash - 1)
end -- }}}

-- Tries to get an usable window with M._get_first_usable_window. If nil,
-- creates a window by splitting the first one. Uses the choosen window to edit
-- the file.
--
--@param fullpath (string) path to the file to edit.
M._open_file_in_editor = function(fullpath) -- {{{
    local win = nil
    local cmd = "edit"
    if v.nvim_win_is_valid(M._old_window) then
        win = M._old_window
    else
        win = M._get_first_usable_window()
        if win == nil then
            win = v.nvim_list_wins()[1]
            cmd = "split"
        end
    end

    v.nvim_win_call(win, function()
        vim.cmd(cmd .. " " .. fullpath)
    end)
end -- }}}

-- }}}

-- api {{{

-- Gets selected entry.
--
--@returns (table, string) entry and entry full path.
M.get_current_entry = function() -- {{{
    local curpos = vim.fn.getpos('.')[2] - 1
    if curpos == 0 then
        return nil, M._tree.name
    end

    local cur, entry, fullpath = M._iterate_to_n_entry(1, curpos, M._tree.tree, M._tree.name)

    return entry, fullpath
end -- }}}

-- Completely reloads the tree
--
--@param root (string) path to base the tree on.
M.reload_yaft = function(root) -- {{{
    if (not root)
    or root == ""
    or root == "."
    then
        root = vim.fn.getcwd()
    end

    -- recreates the root, adding name and then creating the tree itself
    M._tree.name = root
    M._tree.tree = M._create_subtree_from_dir(M._tree.name)
    M._update_buffer()

    -- make sure we update what the user see too, and go to the first line
    local cur_win = v.nvim_get_current_win()
    if cur_win == M._yaft_window then
        vim.cmd("normal gg")
    else
        v.nvim_set_current_win(M._yaft_window)
        vim.cmd("normal gg")
        v.nvim_set_current_win(cur_win)
    end
end -- }}}

-- Opens or closes the plugin window.
--
--@param root (string) path to base the tree on.
M.toggle_yaft = function(root) -- {{{
    if M._open_yaft_window("right", 20) then
        M.reload_yaft(root)
    else
        v.nvim_win_close(M._yaft_window, false)
    end
end -- }}}

M.default_keys = function() -- {{{
    return {
        ["<BS>"]    = M.delete_entry,
        ["<CR>"]    = M.open,
        ["<Space>"] = M.open,
        ["l"]       = M.chroot_or_open,
        ["h"]       = M.chroot_backwards,
        ["m"]       = M.new_file,
        ["M"]       = M.new_dir,
        ["q"]       = M.toggle_yaft,
        ["<C-r>"]   = M.reload_yaft,
        ["<C-p>"]   = function() 
            local _, fullpath = M.get_current_entry()
            print(fullpath)
        end,
    }
end -- }}}

M.setup = function(config) -- {{{
    for key, value in config do
        if key == "keys" then
            for kei, func in key do
                key[kei] = func
            end
            return
        end
        vim.g._yaft_config[key] = value
    end
end -- }}}

-- Opens the current entry.
M.open = function() -- {{{
    local entry, fullpath = M.get_current_entry()
    if not entry then
        v.nvim_echo({ { "No valid entry selected!", "Error" } }, true, {})
        return
    end

    if entry.class == "dir" then
        if entry.opened then
            entry.opened = false
            M._update_buffer()
            return
        end

        entry.opened = true
        if #entry.children == 0 then
            entry.children = M._create_subtree_from_dir(fullpath)
        end
        M._update_buffer()
        return
    elseif entry.class == "exe" then
        g._yaft_config.yaft_exe_opener(entry, fullpath)
        return
    end

    M._open_file_in_editor(fullpath)
end -- }}}

M.delete_entry = function()
    local entry = M.get_current_entry()
    print "TODO! Not implemented yet"
end

M.chroot_or_open = function()
    local entry = M.get_current_entry()
    print "TODO! Not implemented yet"
end

M.chroot_backwards = function()
    local entry = M.get_current_entry()
    print "TODO! Not implemented yet"
end

-- Creates a new directory or file entry, both in plugin and in filesystem.
-- Edits a newly created file entry.
M.new_entry = function(class) -- {{{

    if not class then class = "file" end

    local entry, fullpath = M.get_current_entry()
    local dirpath = fullpath
    if fullpath ~= M._tree.name then
        dirpath = M._get_dir_path_from_fullpath(fullpath)
    end

    local prompt = "New file: "
    if class == "dir" then
        prompt = "New dir: "
    end

    vim.fn.inputsave()
    local new_file = vim.fn.input(prompt .. string.gsub(dirpath, os.getenv("HOME"), "~") .. "/",
                                  "",
                                  "file")
    vim.fn.inputrestore()

    if new_file == "" then
        return
    elseif string.find(new_file, "/") then
        v.nvim_echo({ { "Linux files can't contain slashes!", "Error" } }, true, {})
        return
    end

    -- find where, relatively from root, we should add the entry

    new_file = dirpath .. "/" .. new_file

    if io.open(new_file, "r") ~= nil then
        v.nvim_echo({ { "File/dir already exists!", "Error" } }, true, {})
        return
    end

    local new_path = new_file -- will be used to open the file
    new_file = string.sub(string.gsub(new_file, M._tree.name, ""), 2)

    local dirs = {}
    local last = 1
    while true do
        local idx = string.find(new_file, "/")
        if not idx then
            break
        end
        table.insert(dirs, string.sub(new_file, 1, idx - 1))
        new_file = string.sub(new_file, idx + 1)
    end

    -- get the entry relatively to that
    local subtree = M._tree.tree
    local entry   = nil
    for _, dir in ipairs(dirs) do
        for _, inentry in ipairs(subtree) do
            if inentry.name == dir then
                subtree = inentry.children
                entry   = inentry
                break
            end
        end
    end

    -- finally create the entry in the fs and reload it's dir
    if class == "dir" then
        os.execute("mkdir " .. new_path)
    else
        os.execute("touch " .. new_path)
        M._open_file_in_editor(new_path)
    end

    if entry then
        entry.children = M._create_subtree_from_dir(dirpath)
    else
        M._tree.tree = M._create_subtree_from_dir(dirpath)
    end
    M._update_buffer()
end -- }}}

M.new_file = function()
    M.new_entry("file")
end

M.new_dir = function()
    M.new_entry("dir")
end

-- }}}

return M
