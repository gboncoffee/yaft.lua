local M = {}

local p = require "yaft.path"
local config = require "yaft.utils".get_config_key

-- lower level API for Yaft

-- entry creator
-- (funny history: I could use metatables and stuff to emulate oop, but for
-- some reason the table entries were messy, so I couldn't do that. but simply
-- using a helper function like I would do in C)
M.new_entry = function(name, class)
    return {
        name     = name,
        class    = class, -- file, dir, exe, link
        children = {},
        opened   = false,
        checked  = false,
    }
end

M.setup_buffer_keys = function()
    for key, func in pairs(config("keys")) do
        vim.keymap.set("n", key, func, { buffer = M.tree_buffer })
    end
end

M.ensure_buf_exists = function()
    if not M.tree_buffer or not v.nvim_buf_is_valid(M.tree_buffer) then
        M.tree_buffer = v.nvim_create_buf(false, true)
        M.setup_buffer_keys()
        v.nvim_buf_set_option(M.tree_buffer, "modifiable", false)
    end
end

--@param side (string) "left" or "right".
--@returns (boolean) true if just opened it, false if it was already opened.
M.open_yaft_window = function()

    if M.yaft_window and v.nvim_win_is_valid(M.yaft_window) then
        return false
    end

    M.ensure_buf_exists()

    local col = 0
    local border = { "", "", "│", "│", "╯", "─", "", "" }
    if config("side") == "right" then
        col = math.ceil(vim.o.columns - config("width"))
        border = { "│", "", "", "", "", "─", "╰", "│" }
    end

    M.old_window  = v.nvim_get_current_win()
    M.yaft_window = v.nvim_open_win(M.tree_buffer, true, {
        relative = "editor",
        col      = col,
        row      = 0,
        width    = config("width"),
        height   = vim.o.lines,
        border   = border
    })

    return true
end

-- Writes the lines (i.e. the entries from a subtree) to the plugin buffer.
-- Recursive.
--
--@param pad (number) indentation, i.e., how deep in the subtree it is.
--@param line (number) next line in the buffer (0-indexed).
--@param subtree (table) the tree of entries it'll be basing those lines in.
--@returns (number) next line in the buffer (0-indexed).
M.create_buffer_lines = function(pad, line, subtree)

    local has_icons, icons = pcall(require, "nvim-web-devicons")

    local padstr = ""
    for i = 0,pad do
        padstr = padstr .. "| "
    end

    -- we use it to add an empty line if the dir is opened but have no children
    -- (so making easy to see that it's actually opened)
    local actually_has_children = false
    for _, entry in ipairs(subtree) do

        if (not config("show_hidden")) and string.sub(entry.name, 1, 1) == "." then
            goto continue
        end

        actually_has_children = true

        local highlight = ""
        local sufix     = ""
        local icon      = ""
        if has_icons then
            icon = icons.get_icon(entry.name, p.get_extension(entry.name), { default = true }) .. " "
        end

        if entry.class == "dir" then
            highlight = "YaftDir"
            sufix     = "/"
            if has_icons then
                -- hardcoded because I cannot find how to get a directory icon
                -- with devicons
                icon = " "
            end
        elseif entry.class == "exe" then
            highlight = "YaftExe"
            sufix     = "*"
        elseif entry.class == "link" then
            highlight = "YaftLink"
            sufix     = "@"
        end

        v.nvim_buf_set_lines(M.tree_buffer, line, line + 1, false, { padstr .. icon .. entry.name .. sufix })
        line = line + 1

        v.nvim_buf_add_highlight(M.tree_buffer, -1, highlight, line - 1, (pad + 1) * 2, -1)
        v.nvim_buf_add_highlight(M.tree_buffer, -1, "YaftIndent", line - 1, 0, (pad + 1) * 2)

        if entry.opened then
            line = M.create_buffer_lines(pad + 1, line, entry.children)
        end

        ::continue::
    end

    if not actually_has_children then
        vim.fn.appendbufline(M.tree_buffer, line, padstr)
        v.nvim_buf_add_highlight(M.tree_buffer, -1, "YaftIndent", line, 0, (pad + 1) * 2)
        line = line + 1
    end

    return line
end

-- Updates the entire buffer. Don't mind cursor jumping, it'll not.
M.update_buffer = function()
    M.ensure_buf_exists()

    v.nvim_buf_set_option(M.tree_buffer, "modifiable", true)

    -- add root name
    local rootname = M.tree.name
    rootname = string.gsub(rootname, os.getenv("HOME"), "~")
    v.nvim_buf_set_lines(M.tree_buffer, 0, 1, false, { rootname })
    v.nvim_buf_add_highlight(M.tree_buffer, -1, "YaftRoot", 0, 0, -1)

    -- add other entries
    local last_line = M.create_buffer_lines(0, 1, M.tree.tree)
    v.nvim_buf_set_lines(M.tree_buffer, last_line, -1, false, {})

    v.nvim_buf_set_option(M.tree_buffer, "modifiable", false)
end

-- Creates a tree of entries from a directory.
--
--@param dir (string) directory to base the subtree in.
--@param old (table) old subtree. If exists, will get already opened dirs and
-- substitute then.
--@returns (table) subtree created.
M.create_subtree_from_dir = function(dir, old)
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

        table.insert(subtree, M.new_entry(realname, class))
    end

    if old then
        for _, old_entry in ipairs(old) do
            if old_entry.opened then
                for idx, new_entry in ipairs(subtree) do
                    if new_entry.name == old_entry.name then
                        subtree[idx] = old_entry
                        subtree[idx].children = M.create_subtree_from_dir(
                                                dir .. "/" .. subtree[idx].name,
                                                subtree[idx].children)
                    end
                end
            end
        end
    end

    return subtree
end

-- Gets number of children of a subtree visible (#subtree if
-- M._config.show_hidden).
--
--@param subtree (table) subtree to count.
--@returns (number) number of visible children.
M.get_number_of_visible_children = function(subtree)
    if not subtree then
        return 0
    end
    local n_children = #subtree
    if not config("show_hidden") then
        for _, entry in ipairs(subtree) do
            if string.sub(entry.name, 1, 1) == "." then
                n_children = n_children - 1
            end
        end
    end
    return n_children
end

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
M.iterate_to_n_entry = function(cur, n, subtree, fullpath)

    for _, entry in ipairs(subtree) do
        if (not config("show_hidden")) and string.sub(entry.name, 1, 1) == "." then
            goto continue
        end

        cur = cur + 1

        if cur == n then
            return cur, entry, fullpath .. "/" .. entry.name
        elseif entry.opened then
            if M.get_number_of_visible_children(entry.children) == 0 then
                cur = cur + 1
                if cur == n then
                    return cur, nil, fullpath .. "/" .. entry.name .."/.."
                end
            else
                cur, new_entry, new_fullpath = M.iterate_to_n_entry(cur,
                                                                    n,
                                                                    entry.children,
                                                                    fullpath .. "/" .. entry.name)
                if cur == n then
                    return cur, new_entry, new_fullpath
                end
            end
        end
        ::continue::
    end

    return cur, nil, fullpath
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

-- Get parent entry from a full path.
--
--@param fullpath (string) full path, relatively to the subtree.
--@param subtree (table) subtree to search.
--@returns (table) parent entry, nil if path is children of the subtree.
M.get_parent_entry_from_fullpath = function(fullpath, subtree)
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
end

M.init = function()
    M.tree = {}
    M.keys = {}
end

return M
