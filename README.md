# Yet Another File Tree for Neovim

Yaft is a simpler take on a tree file explorer. Uses a floating window, so it
won't get in the way of your editor windows.

Yaft works on Linux and I'm 99% sure it'll work in other \*nix OSes like MacOS
and BSDs. Also, I'm 99.99% sure it doesn't work on Microsoft Windows.

Features:  
- [x] Tree-based file exploration.  
- [x] File/directory deletion and creation.  
- [x] Neovim's CWD changing.  
- [x] Extensibility: map any function inside the buffer and run shell commands
  inside a directory in the file tree.  
- [x] Automatic use icons if
  [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons) is
  installed.  
- [x] Automatic use [run.lua](https://github.com/gboncoffee/run.lua) to open
  executable files if it is installed.  

TODO:  
- [ ] Symlink resolving  
- [ ] Better API for custom functions  

If you want to contribute, adding features or solving bugs, please send a pull
request! If you find any bug, have any problem with the plugin or have an
feature request or suggestion, please fill an issue!

## Installing

Install it with your favorite Neovim package manager. Optionally install
[nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons) to have
icons in the plugin.

## Configuration/Usage

Toggle the tree with the command `YaftToggle`. The `setup` function support this
options:
```lua
local yaft = require "yaft"
yaft.setup {
    yaft_exe_opener = yaft.default_exe_opener, -- function(entry, fullpath) to
                                               -- open executables.
    file_delete_cmd = "rm",     -- any shell command. Yaft will require
    dir_delete_cmd  = "rm -r",  -- confirmation to run theese.
    git_delete_cmd  = "rm -rf", --
    keys            = {
        ["<BS>"]    = yaft.delete_entry,    -- any key support any Lua function.
        ["<CR>"]    = yaft.open,
        ["<Space>"] = yaft.open,
        ["l"]       = yaft.chroot_or_open,
        ["h"]       = yaft.chroot_backwards,
        ["m"]       = yaft.new_file,
        ["M"]       = yaft.new_dir,
        ["r"]       = yaft.move,
        ["a"]       = yaft.toggle_hidden,
        ["$"]       = yaft.shell,
        ["q"]       = yaft.toggle_yaft,
        ["<C-r>"]   = yaft.reload_yaft,
        ["<C-p>"]   = function()
            local _, fullpath = M.get_current_entry()
            print(fullpath)
        end,
    },
    width           = 25,      -- width of the plugin window.
    side            = "right", -- side to place the plugin.
    show_hidden     = true     -- show hidden files (toggable with keybind).
}
```
## Built-in functions

### yaft.open

If the selected entry is a file, opens it in the editor. If it's a directory,
opens it in the tree (shows its subtree). If it's a executable, uses the
`yaft_exe_opener` option to open it. The function must have a .

### yaft.default_exe_opener

If [run.lua](https://github.com/gboncoffee/run.lua) is installed, opens the
entry with it. If not, opens the entry in a split terminal.

### yaft.chroot_or_open

Uses `yaft.open` if the entry is not a directory. Else, changes the Neovim CWD
and the tree root to it.

### yaft.chroot_backwards

Changes the Neovim CWD and the tree root to the parent directory of the current.

### yaft.new_file

Creates a new file in the parent directory of the current selected entry.
Prompts for a file name.

### yaft.new_dir

Same, but for directories.

### yaft.delete_entry

Deletes the current selected entry. If it is a normal file, will use
`file_delete_cmd`. If it's a normal directory, will use `dir_delete_cmd`. If
it's a directory named `.git` or a directory with a `.git` inside, will use
`git_delete_cmd`.

### yaft.move

Moves the selected entry within the tree. Prompts for a new path.

### yaft.toggle_hidden

Toggles showing hidden entries.

### yaft.shell

Runs a shell command in the parent directory of the current selected entry.

### yaft.toggle_yaft

Toggles the tree.

### yaft.reload_yaft

Completely reloads the tree.

## Extending

Proper extensibility to map keys to custom Lua functions that requires
subdirectories from the tree to be reloaded needs a better API, but one could
look the implementation of the `move` or the `shell` functions to take insights
on creating new functions at the moment.

Most functions would require knowing the current entry and its full path. To do
that, use the function `get_current_entry()`, that returns a table `entry` and
a string `fullpath`.

Entry tables are build with this function:
```lua
M._new_entry = function(name, class)
    return {
        name     = name,
        class    = class, -- file, dir, exe, link
        children = {},
        opened   = false,
        checked  = false,
    }
end
```
Where `name` is the entry base name (i.e., without any /) and class is one of
the following: `"file"`, `"dir"`, `"exe"` and `"link"`. Without symlink
resolving support, current the `"link"` class only works to show the entry
differently in the tree.

If the entry is a directory, the following is present too: `children` is a tree
of entries, `opened` tells the plugin if it must show the entry childrens, and
`checked` tells the plugin whenever the entry children were loaded or not.
