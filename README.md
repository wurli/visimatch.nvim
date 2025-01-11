# visimatch.nvim

A tiny plugin which highlights any text in the current buffer which matches
the text you currently have selected in visual mode.

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
opts {
    -- The highlight group to apply to matched text
    hl_group = "Search",
    -- The minimum number of selected characters required to trigger highlighting
    chars_lower_limit = 6,
    -- The maximum number of selected lines to trigger highlighting for
    lines_upper_limit = 30,
    -- By default, visimatch will highlight text even if it doesn't have exactly
    -- the same spacing as the selected region. You can set this to `true` if
    -- you're not a fan of this behaviour :)
    strict_spacing = false
}
```

## Limitations

Note that visimatch won't trigger in situations where the cursor doesn't move.
In particular, this means that entering `viw` when the cursor is already at the
end of the word won't trigger visimatch. In such situations, just move the
cursor and highlights will trigger 💫 NB, this is a limiation of Neovim which I
don't think is worth adding a workaround for yet. Hopefully this will be
[addressed](https://github.com/neovim/neovim/issues/19708) on the vim/Neovim
side eventually.

