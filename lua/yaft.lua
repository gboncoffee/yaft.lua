v = vim.api

local M = {}

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

-- }}}

-- low level plugin {{{

M._setup_buffer_keys = function() -- {{{
    for key,func in pairs(M._keys) do
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

M._open_yaft_window = function(side, width) -- {{{
    -- returns true if we open it, false if it was already opened

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

M._create_buffer_lines = function(pad, line, subtree) -- {{{
    -- recursive because I like recursive things

    local padstr = ""
    for i = 0,pad do
        padstr = padstr .. "| "
    end

    -- we use it to add an empty line if the dir is opened but have no children
    -- (so making easy to see that it's actually opened)
    local actually_has_children = false
    for _, entry in ipairs(subtree) do
        actually_has_children = true

        vim.fn.appendbufline(M._tree_buffer, line, padstr .. entry.name)
        line = line + 1

        if entry.class == "dir" then
            v.nvim_buf_add_highlight(M._tree_buffer, -1, "YaftDir", line - 1, (pad + 1) * 2, -1)
            if entry.opened then
                line = M._create_buffer_lines(pad + 1, line, entry.children)
            end
        elseif entry.class == "exe" then
            v.nvim_buf_add_highlight(M._tree_buffer, -1, "YaftExe", line - 1, (pad + 1) * 2, -1)
        elseif entry.class == "link" then
            v.nvim_buf_add_highlight(M._tree_buffer, -1, "YaftLnk", line - 1, (pad + 1) * 2, -1)
        end
    end

    if not actually_has_children then
        vim.fn.appendbufline(M._tree_buffer, line, padstr)
        line = line + 1
    end

    return line
end -- }}}

M._update_buffer = function() -- {{{
    M._ensure_buf_exists()

    -- empty buffer
    v.nvim_buf_set_option(M._tree_buffer, "modifiable", true)
    v.nvim_buf_set_lines(M._tree_buffer, 0, -1, false, {})

    -- add root name
    vim.fn.appendbufline(M._tree_buffer, 0, M._tree.name)
    v.nvim_buf_add_highlight(M._tree_buffer, -1, "YaftRoot", 0, 0, -1)

    -- add other entries
    M._create_buffer_lines(0, 1, M._tree.tree)

    -- remove the trailing last line
    v.nvim_buf_set_lines(M._tree_buffer, -2, -1, false, {})

    v.nvim_buf_set_option(M._tree_buffer, "modifiable", false)
end -- }}}

M._create_subtree_from_dir = function(dir) -- {{{
    -- -F == append file indicator (*/=>@|)
    -- -A == all without . and ..
    -- -1 because for ocult forces the command was thinking that it was running
    -- interactively
    local ls = io.popen("ls --group-directories-first -F -A -1 " .. dir)
    local subtree = {}

    for entry in ls:lines() do
        local class = "file"
        local sufix = string.sub(entry, entry:len())
        if sufix == "/" then
            class = "dir"
        elseif sufix == "*" then
            class = "exe"
        elseif sufix == "@" then
            class = "link"
        end
        table.insert(subtree, new_entry(entry, class))
    end

    return subtree
end -- }}}

M._iterate_to_n_entry = function(cur, exp, subtree, fullpath) -- {{{

    for _, entry in pairs(subtree) do
        if cur == exp then
            return cur, entry, fullpath .. entry.name
        end

        cur = cur + 1
        if entry.class == "dir" and entry.opened then
            cur, entry, fullpath = M._iterate_to_n_entry(cur, exp, entry.children, fullpath .. entry.name)
            if entry then
                return cur, entry, fullpath
            end
        end
    end

    return cur, nil, nil
end -- }}}

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

-- }}}

-- api {{{

M.get_current_entry = function() -- {{{
    local curpos = vim.fn.getpos('.')[2] - 1
    if curpos == 0 then
        return nil, nil
    end

    local cur, entry, fullpath = M._iterate_to_n_entry(1, curpos, M._tree.tree, M._tree.name .. "/")
    return entry, fullpath
end -- }}}

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
    }
end -- }}}

M.setup_keys = function(keys) -- {{{
    if not M._keys then M._keys = {} end
    for key, func in pairs(keys) do
        M._keys[key] = func
    end
end -- }}}

M.open = function() -- {{{
    local entry, fullpath = M.get_current_entry()

    if entry.class == "dir" then
        if entry.opened then
            entry.opened = false
            local curpos = vim.fn.getpos('.')[2]
            M._update_buffer()
            vim.cmd("normal " .. curpos .. "G")
            return
        end

        entry.opened = true
        if #entry.children == 0 then
            entry.children = M._create_subtree_from_dir(fullpath)
        end
        local curpos = vim.fn.getpos('.')[2]
        M._update_buffer()
        vim.cmd("normal " .. curpos .. "G")
        return
    end

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

M.new_file = function()
    print "TODO! Not implemented yet"
end

M.new_dir = function()
    print "TODO! Not implemented yet"
end

-- }}}

return M
