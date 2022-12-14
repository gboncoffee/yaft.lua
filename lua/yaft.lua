v = vim.api

local M = {}

-- utils {{{
-- entry creator {{{
-- (funny history: I could use metatables and stuff to emulate oop, but for
-- some reason the table entries were messy, so I couldn't do that. but simply
-- using a helper function like I would do in C)
M._new_entry = function(name, class)
    return {
        name     = name,
        class    = class, -- file, dir, exe, link
        children = {},
        opened   = false,
        checked  = false,
    }
end -- }}}

local printerr = function(msg)
    v.nvim_echo({ { msg, "Error" } }, true, {})
end
-- }}}

-- low level plugin {{{

M._setup_buffer_keys = function() -- {{{
    for key, func in pairs(M._config.keys) do
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

--@param side (string) "left" or "right".
--@returns (boolean) true if just opened it, false if it was already opened.
M._open_yaft_window = function() -- {{{

    if M._yaft_window and v.nvim_win_is_valid(M._yaft_window) then
        return false
    end

    M._ensure_buf_exists()

    local col = 0
    if M._config.side == "right" then
        col = math.ceil(vim.o.columns - M._config.width)
    end

    M._old_window  = v.nvim_get_current_win()
    M._yaft_window = v.nvim_open_win(M._tree_buffer, true, {
        relative = "editor",
        col      = col,
        row      = 0,
        width    = M._config.width,
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
        v.nvim_buf_add_highlight(M._tree_buffer, -1, "YaftIndent", line - 1, 0, (pad + 1) * 2)

        if entry.opened then
            line = M._create_buffer_lines(pad + 1, line, entry.children)
        end
    end

    if not actually_has_children then
        vim.fn.appendbufline(M._tree_buffer, line, padstr)
        v.nvim_buf_add_highlight(M._tree_buffer, -1, "YaftIndent", line, 0, (pad + 1) * 2)
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
--@param old (table) old subtree. If exists, will get already opened dirs and
-- substitute then.
--@returns (table) subtree created.
M._create_subtree_from_dir = function(dir, old) -- {{{
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

        table.insert(subtree, M._new_entry(realname, class))
    end

    if old then
        for _, old_entry in ipairs(old) do
            if old_entry.opened then
                for idx, new_entry in ipairs(subtree) do
                    if new_entry.name == old_entry.name then
                        subtree[idx] = old_entry
                        subtree[idx].children = M._create_subtree_from_dir(
                                                dir .. "/" .. subtree[idx].name,
                                                subtree[idx].children)
                    end
                end
            end
        end
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

    for _, entry in ipairs(subtree) do
        cur = cur + 1
        if cur == n then
            return cur, entry, fullpath .. "/" .. entry.name
        elseif entry.opened then
            if #entry.children == 0 then
                cur = cur + 1
                if cur == n then
                    return cur, nil, fullpath .. "/" .. entry.name .."/.."
                end
            else
                cur, new_entry, new_fullpath = M._iterate_to_n_entry(cur,
                                                                     n,
                                                                     entry.children,
                                                                     fullpath .. "/" .. entry.name)
                if cur == n then
                    return cur, new_entry, new_fullpath
                end
            end
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

-- Gets full parent directory path of another.
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

-- Get parent entry from a full path.
--
--@param fullpath (string) full path, relatively to the subtree.
--@param subtree (table) subtree to search.
--@returns (table) parent entry, nil if path is children of the subtree.
M._get_parent_entry_from_fullpath = function(fullpath, subtree) -- {{{
    local dirs = {}
    local last = 1
    while true do
        local idx = string.find(fullpath, "/")
        if not idx then
            break
        end
        table.insert(dirs, string.sub(fullpath, 1, idx - 1))
        fullpath = string.sub(fullpath, idx + 1)
    end

    local entry   = nil
    for _, dir in ipairs(dirs) do
        for _, inentry in ipairs(subtree) do
            if inentry.name == dir then
                if not inentry.children then inentry.children = {} end
                subtree = inentry.children
                entry   = inentry
                break
            end
        end
    end

    return entry
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

-- Gets base entry name from a full path.
--
--@param fullpath (string) self-explanatory.
--@returns (string) self-explanatory.
M._get_base_name_from_fullpath = function(fullpath) -- {{{
    while true do
        local idx = string.find(fullpath, "/")
        if idx then
            fullpath = string.sub(fullpath, idx + 1, -1)
        else
            return fullpath
        end
    end
end -- }}}

-- }}}

-- api {{{.

-- Gets selected entry.
--
--@returns (table, string) entry and entry full path.
M.get_current_entry = function() -- {{{
    local curpos = vim.fn.getpos('.')[2] - 1
    if curpos == 0 then
        return nil, M._tree.name .. "/.." -- used as dummy name because it's impossible
    end

    local cur, entry, fullpath = M._iterate_to_n_entry(0, curpos, M._tree.tree, M._tree.name)

    return entry, fullpath
end -- }}}

-- Completely reloads the tree
M.reload_yaft = function() -- {{{

    -- recreates the root, adding name and then creating the tree itself
    M._tree.name = vim.fn.getcwd()
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
M.toggle_yaft = function() -- {{{

    if M._open_yaft_window("right", M._config.width) then
        if M._tree.name ~= vim.fn.getcwd() then
            M.reload_yaft()
        else
            M._update_buffer()
        end
    else
        v.nvim_win_close(M._yaft_window, false)
    end
end -- }}}

M.setup = function(config) -- {{{
    if not M._config then M._config = { keys = {} } end
    if not M._config.keys then M._config.keys = {} end
    for key, value in pairs(config) do
        if key == "keys" then
            for kei, func in key do
                M._config.keys[kei] = func
            end
            goto continue
        end
        M._config[key] = value
    end
    ::continue::
end -- }}}

-- Opens the current entry.
M.open = function(entry, fullpath) -- {{{
    if not entry then
        entry, fullpath = M.get_current_entry()
    end
    if not entry then
        printerr "No valid entry selected!"
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
        M._config.yaft_exe_opener(entry, fullpath)
        return
    end

    M._open_file_in_editor(fullpath)
end -- }}}

-- Deletes the current entry
M.delete_entry = function() -- {{{

    local entry, fullpath = M.get_current_entry()
    if not entry then
        printerr "No valid entry selected!"
        return
    end

    local prettypath = string.gsub(fullpath, M._tree.name .. "/", "")
    local sure = "Y"

    -- files {{{
    if entry.class ~= "dir" then

        -- confirmation
        vim.fn.inputsave()
        sure = vim.fn.input({
            prompt = "Delete file " .. prettypath .. "? [Y/n] ",
            cancelreturn = "N"
        })
        vim.fn.inputrestore()

        if string.upper(string.sub(sure, 1, 1)) ~= "N" then
            if os.execute(M._config.file_delete_cmd .. " " .. fullpath) ~= 0 then
                printerr("Unable to delete" .. prettypath .. "!")
                return
            end

            print("Deleted " .. prettypath)

            local relative_path = string.sub(string.gsub(fullpath, M._tree.name, ""), 2)
            local entry = M._get_parent_entry_from_fullpath(relative_path, M._tree.tree)
            local dirpath = M._get_dir_path_from_fullpath(fullpath)
            if entry then
                entry.children = M._create_subtree_from_dir(dirpath, entry.children)
            else
                M._tree.tree = M._create_subtree_from_dir(M._tree.name, M._tree.tree)
            end
            M._update_buffer()
        else
            print("Cancelling deletion of " .. prettypath)
        end
    else -- }}}
        -- dirs {{{
        -- check if dir is .git or a git repo
        local is_git_repo = false
        local is_git_dir  = false
        if entry.name == ".git" then
            is_git_dir = true
        else
            local io_stream = io.open(fullpath .. "/.git", "r")
            if io_stream ~= nil then
                is_git_repo = true
                io_stream:close()
            end
        end

        -- confirmation
        local prompt = "Delete "
        if is_git_dir      then prompt = prompt .. "Git directory "
        elseif is_git_repo then prompt = prompt .. "Git repo "
        else                    prompt = prompt .. "directory "
        end

        vim.fn.inputsave()
        sure = vim.fn.input({
            prompt = prompt .. prettypath .. "? [Y/n] ",
            cancelreturn = "N"
        })
        vim.fn.inputrestore()

        -- finally delete
        if string.upper(string.sub(sure, 1, 1)) ~= "N" then
            local cmd = M._config.dir_delete_cmd
            if is_git_dir or is_git_repo then cmd = M._config.git_delete_cmd end
            if os.execute(cmd .. " " .. fullpath) ~= 0 then
                printerr("Cannot delete " .. prettypath .. "!")
                return
            end

            local relative_path = string.sub(string.gsub(fullpath, M._tree.name, ""), 2)
            local entry = M._get_parent_entry_from_fullpath(relative_path, M._tree.tree)
            local dirpath = M._get_dir_path_from_fullpath(fullpath)
            if entry then
                entry.children = M._create_subtree_from_dir(dirpath, entry.children)
            else
                M._tree.tree = M._create_subtree_from_dir(M._tree.name, M._tree.tree)
            end
            print("Deleted " .. prettypath)
            M._update_buffer()
        else
            print("Cancelling deletion of " .. prettypath)
        end
    end -- }}}
end -- }}}

M.chroot_or_open = function() -- {{{
    local entry, fullpath = M.get_current_entry()

    if entry.class ~= "dir" then
        M.open(entry, fullpath)
        return
    end

    local old_dir = vim.fn.chdir(fullpath)
    if old_dir == "" then
        local prettypath = string.gsub(fullpath, M._tree.name, "")
        printerr("Unable to change directory to " .. prettypath .. "!")
        return
    end

    M._tree.name = fullpath
    if #entry.children == 0 then
        M._tree.tree = M._create_subtree_from_dir(fullpath)
    else
        M._tree.tree = entry.children
    end
    M._update_buffer()
    vim.cmd("normal gg")
end -- }}}

M.chroot_backwards = function() -- {{{
    local old_dir = vim.fn.chdir("..")
    if old_dir == "" then
        printerr("Unable to change directory to ..!")
        return
    end

    local old_subtree = M._tree.tree
    local old_name = M._get_base_name_from_fullpath(M._tree.name)
    -- from reload yaft
    M._tree.name = vim.fn.getcwd()
    M._tree.tree = M._create_subtree_from_dir(M._tree.name)

    for idx, entry in ipairs(M._tree.tree) do
        if entry.name == old_name then
            M._tree.tree[idx].children = old_subtree
            M._tree.tree[idx].opened = true
        end
    end

    M._update_buffer()
    -- this gambiarra places the cursor on the last root
    vim.cmd("normal gg")
    vim.cmd("/| " .. old_name .. "/")
    vim.cmd("nohl")
end -- }}}

-- Creates a new directory or file entry, both in plugin and in filesystem.
-- Edits a newly created file entry.
M.new_entry = function(class) -- {{{

    if not class then class = "file" end

    -- get entry, fullpath and dirpath
    local entry, fullpath = M.get_current_entry()
    local dirpath = fullpath
    if fullpath ~= M._tree.name then
        dirpath = M._get_dir_path_from_fullpath(fullpath)
    end

    -- prompt for a new name
    local prompt = "New file: "
    if class == "dir" then
        prompt = "New dir: "
    end

    vim.fn.inputsave()
    local new_path = vim.fn.input(prompt .. string.gsub(dirpath, os.getenv("HOME"), "~") .. "/",
                                  "",
                                  "file")
    vim.fn.inputrestore()

    -- error handling
    if new_path == "" then
        return
    elseif string.find(new_path, "/") then
        printerr "Linux files can't contain slashes!"
        return
    end

    new_path = dirpath .. "/" .. new_path

    local io_stream = io.open(new_path, "r")
    if io_stream ~= nil then
        printerr "File/dir already exists!"
        io_stream:close()
        return
    end

    -- get parent entry
    local relative_path = string.sub(string.gsub(new_path, M._tree.name, ""), 2)
    local entry = M._get_parent_entry_from_fullpath(relative_path, M._tree.tree)

    -- finally create the entry in the fs and reload it's dir
    if class == "dir" then
        if os.execute("mkdir " .. new_path) ~= 0 then
            printerr("Unable to create directory " .. new_path .. "!")
            return
        end
    else
        if os.execute("touch " .. new_path) ~= 0 then
            printerr("Unable to create file " .. new_path .. "!")
            return
        end
        M._open_file_in_editor(new_path)
    end

    if entry then
        entry.children = M._create_subtree_from_dir(dirpath, entry.children)
    else
        M._tree.tree = M._create_subtree_from_dir(M._tree.name, M._tree.tree)
    end
    M._update_buffer()
end -- }}}

-- Runs a shell command inside the selected directory, non-interactively.
-- Reloads the directory then.
M.shell = function(cmd) -- {{{
    local entry, fullpath = M.get_current_entry()
    local dirpath = M._get_dir_path_from_fullpath(fullpath)

    if (not cmd) or cmd == "" then
        local prettydirpath = string.gsub(dirpath, M._tree.name, "")
        vim.fn.inputsave()
        if string.len(prettydirpath) > 0 then
            cmd = vim.fn.input(prettydirpath .. " $ ")
        else
            cmd = vim.fn.input("$ ")
        end
        vim.fn.inputrestore()
    end

    if cmd == "" then
        return
    end

    local savepath = vim.fn.getcwd()
    vim.cmd("cd " .. dirpath)
    vim.cmd("!" .. cmd)
    vim.cmd("cd " .. savepath)

    local relative_path = string.sub(string.gsub(fullpath, M._tree.name, ""), 2)
    local entry = M._get_parent_entry_from_fullpath(relative_path, M._tree.tree)

    if entry then
        entry.children = M._create_subtree_from_dir(dirpath, entry.children)
    else
        M._tree.tree = M._create_subtree_from_dir(M._tree.name, M._tree.tree)
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

-- init plugin {{{

M.default_keys = function() -- {{{
    return {
        ["<BS>"]    = M.delete_entry,
        ["<CR>"]    = M.open,
        ["<Space>"] = M.open,
        ["l"]       = M.chroot_or_open,
        ["h"]       = M.chroot_backwards,
        ["m"]       = M.new_file,
        ["M"]       = M.new_dir,
        ["$"]       = M.shell,
        ["q"]       = M.toggle_yaft,
        ["<C-r>"]   = M.reload_yaft,
        ["<C-p>"]   = function() 
            local _, fullpath = M.get_current_entry()
            print(fullpath)
        end,
    }
end -- }}}

M._tree = {}
M._keys = {}
M._config = {
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
    keys = M.default_keys(),
    width = 25,
    side = "right"
}

-- }}}

return M
