# visimatch.nvim

A tiny plugin to highlight text matching the current selection in visual mode 💫
![250307_15h51m26s_screenshot](https://github.com/user-attachments/assets/4e1091a6-982d-4d92-a3d1-c19700f8ef8f)

![visimatch](https://github.com/user-attachments/assets/c9547434-950c-4205-945d-097481baf85e)

Highlights are updated whenever the visual selection changes, but visimatch
manages to do this without noticeable lag by only searching/applying highlights
to the *visible* regions of buffers. This means that visimatch will continue to
work smoothly even when editing very large files. It's magic!

## Installation

Using Lazy:

``` lua
{
    "wurli/visimatch.nvim",
    opts = {}
}
```

## Configuration / Features

Here's the default configuration:

``` lua
-- Pass this to require("visimatch").setup() or use it as the `opts` field
-- in the Lazy.nvim plugin spec above
opts = {
    -- The highlight group to apply to matched text
    hl_group = "Search",
    -- The minimum number of selected characters required to trigger highlighting
    chars_lower_limit = 5,
    -- The maximum number of selected lines to trigger highlighting for
    lines_upper_limit = 45,
    -- By default, visimatch will highlight text even if it doesn't have exactly
    -- the same spacing as the selected region. You can set this to `true` if
    -- you're not a fan of this behaviour :)
    strict_spacing = false,
    -- Visible buffers which should be highlighted. Valid options:
    -- * `"filetype"` (the default): highlight buffers with the same filetype
    -- * `"current"`: highlight matches in the current buffer only
    -- * `"all"`: highlight matches in all visible buffers
    -- * A function. This will be passed a buffer number and should return
    --   `true`/`false` to indicate whether the buffer should be highlighted.
    buffers = "filetype" ,
    -- Case-(in)nsitivity for matches. Valid options:
    -- * `true`: matches will never be case-sensitive
    -- * `false`/`{}`: matches will always be case-sensitive
    -- * a table of filetypes to use use case-insensitive matching for.
    case_insensitive = { "markdown", "text", "help" , "oil" },
    -- Enable blinking effect for the main selection
    -- This helps identify matches in large files by making the current selection blink
    blink_enabled = true,
    -- Interval for blinking effect in milliseconds
    blink_time = 500,
    -- Highlight group for the blinking effect
    blink_hl_group = "IncSearch",
    -- Highlight group for block mode matches
    block_hl_group = "Visual",
    -- Maximum width for block mode highlights
    block_max_width = 50,
}
```

## Features

- **Live Highlighting**: Matches are updated in real-time as you move your cursor in visual mode
- **Smart Buffer Handling**: Only searches visible regions of buffers for optimal performance
- **Multiple Visual Modes**: Supports character-wise (`v`), line-wise (`V`), and block (`^V`) visual modes
- **Blinking Indicator**: The current selection blinks to help you identify when matches are found, especially useful in large files
- **Configurable Matching**: Control case sensitivity, spacing requirements, and buffer scope
- **Performance Optimized**: Works smoothly even in large files by limiting search scope

## Limitations
Note that visimatch won't trigger in situations where the cursor doesn't move.
In particular, this means that entering `viw` when the cursor is already at the
end of the word won't trigger visimatch. In such situations, just move the
cursor and highlights will trigger 💫 NB, this is a limitation of Neovim which I
don't think is worth adding a workaround for yet. Hopefully this will eventually
be [addressed](https://github.com/neovim/neovim/issues/19708) on the vim/Neovim
side.

