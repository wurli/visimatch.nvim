# visimatch.nvim

A tiny plugin which highlights any text in the current buffer which matches
the text you currently have selected in visual mode.

![visimatch](https://github.com/user-attachments/assets/c9547434-950c-4205-945d-097481baf85e)

## Installation

Using Lazy:

``` lua
{
    "wurli/visimatch.nvim",
    opts = {}
}
```

## Configuration
Here's the default configuration:

``` lua
-- Pass this to require("visimatch").setup() or use it as the `opts` field
-- in the Lazy.nvim plugin spec above
opts = {
    -- The highlight group to apply to matched text
    hl_group = "Search",
    -- The minimum number of selected characters required to trigger highlighting
    chars_lower_limit = 6,
    -- The maximum number of selected lines to trigger highlighting for
    lines_upper_limit = 30,
    -- By default, visimatch will highlight text even if it doesn't have exactly
    -- the same spacing as the selected region. You can set this to `true` if
    -- you're not a fan of this behaviour :)
    strict_spacing = false,
    -- Visible buffers which should be highlighted. Valid options:
    -- * `"filetype"` (the default): highlight buffers with the same filetype
    -- * `"current"`: highlight matches in the current buffer only
    -- * `"all"`: highlight matches in all visible buffers
    buffers = "filetype"
    -- Case-(in)nsitivity for matches. Valid options:
    -- * `true`: matches will never be case-sensitive
    -- * `false`/`{}`: matches will always be case-sensitive
    -- * a table of filetypes to use use case-insensitive matching for.
    case_insensitive = { "markdown", "text", "help" },
}
```

## Limitations

Note that visimatch won't trigger in situations where the cursor doesn't move.
In particular, this means that entering `viw` when the cursor is already at the
end of the word won't trigger visimatch. In such situations, just move the
cursor and highlights will trigger 💫 NB, this is a limitation of Neovim which I
don't think is worth adding a workaround for yet. Hopefully this will be
[addressed](https://github.com/neovim/neovim/issues/19708) on the vim/Neovim
side eventually.

