v = vim.api
local l = require "yaft.low_level"
local p = require "yaft.path"
local y = require "yaft.api"
local config   = require "yaft.utils".get_config_key
local printerr = require "yaft.utils".printerr

local M = {}

-- Tries to get an usable window with l.get_first_usable_window. If nil,
-- creates a window by splitting the first one. Uses the choosen window to edit
-- the file.
--
--@param fullpath (string) path to the file to edit.
M.open_file_in_editor = function(fullpath)
    local win = nil
    local cmd = "edit"
    if v.nvim_win_is_valid(l.old_window) then
        win = l.old_window
    else
        win = y.get_first_usable_window()
        if win == nil then
            win = v.nvim_list_wins()[1]
            cmd = "split"
        end
    end

    v.nvim_win_call(win, function()
        vim.cmd(cmd .. " " .. fullpath)
    end)
end

-- Completely reloads the tree
M.reload_yaft = function()

    -- recreates the root, adding name and then creating the tree itself
    l.tree.name = vim.fn.getcwd()
    l.tree.tree = l.create_subtree_from_dir(l.tree.name, l.tree.tree)
    l.update_buffer()

    -- make sure we update what the user see too, and go to the first line
    local cur_win = v.nvim_get_current_win()
    if cur_win == l.yaft_window then
        vim.cmd("normal gg")
    else
        v.nvim_set_current_win(l.yaft_window)
        vim.cmd("normal gg")
        v.nvim_set_current_win(cur_win)
    end
end

-- Opens or closes the plugin window.
--
--@param root (string) path to base the tree on.
M.toggle_yaft = function()

    if l.open_yaft_window() then
        if l.tree.name ~= vim.fn.getcwd() then
            M.reload_yaft()
        else
            l.update_buffer()
        end
    else
        v.nvim_win_close(l.yaft_window, false)
    end
end

M.setup = function(config)
    local c = require "yaft.config"
    c.init()
    
    for key, value in pairs(config) do
        if key == "keys" then
            for kei, func in key do
                c.config.keys[kei] = func
            end
            goto continue
        end
        c.config[key] = value
    end
    ::continue::
end

-- Opens the current entry.
M.open = function(entry, fullpath)
    if not entry then
        entry, fullpath = y.get_current_entry()
    end
    if not entry then
        printerr "No valid entry selected!"
        return
    end

    if entry.class == "dir" then
        if entry.opened then
            entry.opened = false
            l.update_buffer()
            return
        end

        entry.opened = true
        if not entry.checked then
            y.check_dir(entry, fullpath)
        end
        l.update_buffer()
        return
    elseif entry.class == "exe" then
        config("yaft_exe_opener")(entry, fullpath)
        return
    end

    M.open_file_in_editor(fullpath)
end

-- Tries to open the current entry in editor (silently fails in case of dir
-- selected or nil entry).
M.edit = function()
    local entry, fullpath = y.get_current_entry()
    if entry and entry.class ~= "dir" then
        M.open_file_in_editor(fullpath)
    end
end

-- Deletes the current entry
M.delete_entry = function()

    local entry, fullpath = y.get_current_entry()
    if not entry then
        printerr "No valid entry selected!"
        return
    end

    local prettypath = string.gsub(fullpath, l.tree.name .. "/", "")
    local sure = "Y"

    -- files
    if entry.class ~= "dir" then

        -- confirmation
        vim.fn.inputsave()
        sure = vim.fn.input({
            prompt = "Delete file " .. prettypath .. "? [Y/n] ",
            cancelreturn = "N"
        })
        vim.fn.inputrestore()

        if string.upper(string.sub(sure, 1, 1)) ~= "N" then
            if os.execute(config("file_delete_cmd") .. " " .. fullpath .. " 2> /dev/null") ~= 0 then
                printerr("Unable to delete" .. prettypath .. "!")
                return
            end

            print("Deleted " .. prettypath)

            local relative_path = string.sub(string.gsub(fullpath, l.tree.name, ""), 2)
            local entry = l.get_parent_entry_from_fullpath(relative_path, l.tree.tree)
            local dirpath = p.get_dir_path_from_fullpath(fullpath)
            if entry then
                entry.children = l.create_subtree_from_dir(dirpath, entry.children)
            else
                l.tree.tree = l.create_subtree_from_dir(l.tree.name, l.tree.tree)
            end
            l.update_buffer()
        else
            print("Cancelling deletion of " .. prettypath)
        end
    else
        -- dirs
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
            local cmd = config("dir_delete_cmd")
            if is_git_dir or is_git_repo then cmd = config("git_delete_cmd") end
            if os.execute(cmd .. " " .. fullpath .. " 2> /dev/null") ~= 0 then
                printerr("Cannot delete " .. prettypath .. "!")
                return
            end

            local relative_path = string.sub(string.gsub(fullpath, l.tree.name, ""), 2)
            local entry = l.get_parent_entry_from_fullpath(relative_path, l.tree.tree)
            local dirpath = p.get_dir_path_from_fullpath(fullpath)
            if entry then
                entry.children = l._create_subtree_from_dir(dirpath, entry.children)
            else
                l.tree.tree = l.create_subtree_from_dir(l.tree.name, l.tree.tree)
            end
            print("Deleted " .. prettypath)
            l.update_buffer()
        else
            print("Cancelling deletion of " .. prettypath)
        end
    end
end

M.chroot_or_open = function()
    local entry, fullpath = y.get_current_entry()

    if entry.class ~= "dir" then
        M.open(entry, fullpath)
        return
    end

    local old_dir = vim.fn.chdir(fullpath)
    if old_dir == "" then
        local prettypath = string.gsub(fullpath, l.tree.name, "")
        printerr("Unable to change directory to " .. prettypath .. "!")
        return
    end

    l.tree.name = fullpath
    if #entry.children == 0 then
        l.tree.tree = l.create_subtree_from_dir(fullpath)
    else
        l.tree.tree = entry.children
    end
    l.update_buffer()
    vim.cmd("normal gg")
end

M.chroot_backwards = function()
    local old_dir = vim.fn.chdir("..")
    if old_dir == "" then
        printerr("Unable to change directory to ..!")
        return
    end

    local old_subtree = l.tree.tree
    local old_name = p.get_base_name_from_fullpath(l.tree.name)
    -- from reload yaft
    l.tree.name = vim.fn.getcwd()
    l.tree.tree = l.create_subtree_from_dir(l.tree.name)

    for idx, entry in ipairs(l.tree.tree) do
        if entry.name == old_name then
            l.tree.tree[idx].children = old_subtree
            l.tree.tree[idx].opened = true
        end
    end

    l.update_buffer()
    -- this gambiarra places the cursor on the last root
    local has_icons = pcall(require, "nvim-web-devicons")
    local icon = ""
    if has_icons then
        icon = " "
    end
    vim.cmd("normal gg")
    vim.cmd("/| " .. icon .. old_name .. "/")
    vim.cmd("nohl")
end

-- Creates a new directory or file entry, both in plugin and in filesystem.
-- Edits a newly created file entry.
M.new_entry = function(class)

    if not class then class = "file" end

    -- get entry, fullpath and dirpath
    local entry, fullpath = y.get_current_entry()
    local dirpath = fullpath
    if fullpath ~= l.tree.name then
        dirpath = p.get_dir_path_from_fullpath(fullpath)
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
    local relative_path = string.sub(string.gsub(new_path, l.tree.name, ""), 2)
    local entry = l.get_parent_entry_from_fullpath(relative_path, l.tree.tree)

    -- finally create the entry in the fs and reload it's dir
    if class == "dir" then
        if os.execute("mkdir " .. new_path .. " 2> /dev/null") ~= 0 then
            printerr("Unable to create directory " .. new_path .. "!")
            return
        end
    else
        if os.execute("touch " .. new_path .. " 2> /dev/null") ~= 0 then
            printerr("Unable to create file " .. new_path .. "!")
            return
        end
        M.open_file_in_editor(new_path)
    end

    if entry then
        entry.children = l.create_subtree_from_dir(dirpath, entry.children)
    else
        l.tree.tree = l.create_subtree_from_dir(l.tree.name, l.tree.tree)
    end
    l.update_buffer()
end

-- Runs a shell command inside the selected directory, non-interactively.
-- Reloads the directory then.
M.shell = function(cmd)
    local entry, fullpath = y.get_current_entry()
    local dirpath = p.get_dir_path_from_fullpath(fullpath)

    if (not cmd) or cmd == "" then
        local prettydirpath = string.gsub(dirpath, l.tree.name, "")
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

    local relative_path = string.sub(string.gsub(fullpath, l.tree.name, ""), 2)
    local entry = l.get_parent_entry_from_fullpath(relative_path, l.tree.tree)

    if entry then
        entry.children = l.create_subtree_from_dir(dirpath, entry.children)
    else
        l.tree.tree = l.create_subtree_from_dir(l.tree.name, l.tree.tree)
    end
    l.update_buffer()
end

-- Move entries inside the tree with mv
M.move = function()
    local entry, fullpath = y.get_current_entry()

    if not entry then
        printerr "No valid entry selected!"
        return
    end

    local path_without_root = string.gsub(fullpath, l.tree.name .. "/", "")

    vim.fn.inputsave()
    local new_rel_path = vim.fn.input(
                         "New path: " .. string.gsub(l.tree.name, os.getenv("HOME"), "~") .. "/",
                         path_without_root,
                         "file")
    vim.fn.inputrestore()

    local new_path = l.tree.name .. "/" .. new_rel_path
    if os.execute("mv " .. fullpath .. " " .. new_path .. " 2> /dev/null") ~= 0 then
        printerr("Unable to move " .. path_without_root .. " to " .. new_rel_path .. "!")
    end

    print("Moved " .. path_without_root .. " to " .. new_rel_path)

    -- we're going to reload the whole tree because most of the time it would be
    -- faster then if we tried to find the possible two directories to reload
    l.tree.tree = l.create_subtree_from_dir(l.tree.name, l.tree.tree)
    l.update_buffer()
end

-- Copy entries inside the tree
M.copy = function()
    local entry, fullpath = y.get_current_entry()

    if not entry then
        printerr "No valid entry selected!"
        return
    end

    local path_without_root = string.gsub(fullpath, l.tree.name .. "/", "")

    vim.fn.inputsave()
    local copy_rel_path = vim.fn.input(
                         "Path to copy to: " .. string.gsub(l.tree.name, os.getenv("HOME"), "~") .. "/",
                         path_without_root,
                         "file")
    vim.fn.inputrestore()

    local copy_path = l.tree.name .. "/" .. copy_rel_path
    if os.execute("cp " .. fullpath .. " " .. copy_path .. " 2> /dev/null") ~= 0 then
        printerr("Unable to copy " .. path_without_root .. " to " .. copy_rel_path .. "!")
    end

    print("Moved " .. path_without_root .. " to " .. copy_rel_path)

    -- we're going to reload the whole tree because most of the time it would be
    -- faster then if we tried to find the possible two directories to reload
    l.tree.tree = l.create_subtree_from_dir(l.tree.name, l.tree.tree)
    l.update_buffer()
end

-- Toggle hidden entries
M.toggle_hidden = function()
    local c = require "yaft.config"
    if config("show_hidden") then
        c.config.show_hidden = false
    else
        c.config.show_hidden = true
    end
    l.update_buffer()
end

M.new_file = function()
    M.new_entry("file")
end

M.new_dir = function()
    M.new_entry("dir")
end

M.default_exe_opener = function(entry, fullpath)
    local has_run, run = pcall(require, "run")
    if has_run then
        run.run(fullpath)
        return
    end
    v.nvim_win_call(require "yaft.low_level".get_first_usable_window(), function()
        vim.cmd("split | term " .. fullpath)
    end)
end

M.default_keys = function()
    return {
        ["<BS>"]    = M.delete_entry,
        ["<CR>"]    = M.open,
        ["<Space>"] = M.open,
        ["e"]       = M.edit,
        ["l"]       = M.chroot_or_open,
        ["h"]       = M.chroot_backwards,
        ["m"]       = M.new_file,
        ["M"]       = M.new_dir,
        ["r"]       = M.move,
        ["c"]       = M.copy,
        ["a"]       = M.toggle_hidden,
        ["$"]       = M.shell,
        ["q"]       = M.toggle_yaft,
        ["<C-r>"]   = M.reload_yaft,
        ["<C-p>"]   = function() 
            local _, fullpath = y.get_current_entry()
            print(fullpath)
        end,
    }
end

return M
