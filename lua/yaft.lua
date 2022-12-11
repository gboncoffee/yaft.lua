v = vim.api

local M = {}

-- TODO: remove this from here
vim.cmd [[
hi! link YaftDir Directory
hi! link YaftExe Character
hi! link YaftLnk Question
hi! link YaftRoot Todo
]]

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

M._ensure_buf_exists = function() -- {{{
    if not M._tree_buffer or not v.nvim_buf_is_valid(M._tree_buffer) then
        M._tree_buffer = v.nvim_create_buf(false, false)
        v.nvim_buf_set_option(M._tree_buffer, "modifiable", false)
    end
end -- }}}

M._open_yaft_window = function(side, width) -- {{{

    if M._yaft_window and v.nvim_win_is_valid(M._yaft_window) then
        return false
    end

    M._ensure_buf_exists()

    local col = 0
    if side == "right" then
        col = math.ceil(vim.o.columns - 20)
    end
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
    local padstr = ""
    for i = 0,pad do
        padstr = padstr .. "| "
    end

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

    v.nvim_buf_set_option(M._tree_buffer, "modifiable", true)
    v.nvim_buf_set_lines(M._tree_buffer, 0, -1, false, {})

    -- add root name
    -- TODO: create highlight groups
    vim.fn.appendbufline(M._tree_buffer, 0, M._tree.name)
    v.nvim_buf_add_highlight(M._tree_buffer, -1, "YaftRoot", 0, 0, -1)

    M._create_buffer_lines(0, 1, M._tree.tree)

    v.nvim_buf_set_lines(M._tree_buffer, -2, -1, false, {})

    v.nvim_buf_set_option(M._tree_buffer, "modifiable", false)
end -- }}}

M._create_subtree_from_dir = function(dir) -- {{{
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

M.reload_yaft = function(root) -- {{{
    if not root then root = vim.fn.getcwd() end
    M._tree.name = root
    print(vim.inspect(M._tree.name))
    M._tree.tree = M._create_subtree_from_dir(M._tree.name)
    M._update_buffer()
end -- }}}

M.toggle_yaft = function() -- {{{
    if M._open_yaft_window("right", 20) then
        M.reload_yaft()
        vim.cmd("normal gg")
    else
        v.nvim_win_close(M._yaft_window, false)
    end
end -- }}}

return M
