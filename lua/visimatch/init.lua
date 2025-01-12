local M = {}

---@class VisimatchConfig
---The highlight group to apply to matched text; defaults to `Search`.
---@field hl_group? string
---
---The minimum number of selected characters required to trigger highlighting;
---defaults to 6.
---@field chars_lower_limit? number
---
---The maximum number of selected lines to trigger highlighting for; defaults
---to 30.
---@field lines_upper_limit? number
---
---If `false` (the default) text will be highlighted even if the spacing is not
---exactly the same as the text you have selected.
---@field strict_spacing? boolean

---@type VisimatchConfig
local config = {
    hl_group = "Search",
    chars_lower_limit = 6,
    lines_upper_limit = 30,
    strict_spacing = false
}

---@param opts? VisimatchConfig
M.setup = function(opts)
    config = vim.tbl_extend("force", config, opts or {})
end

---@alias TextPoint { line: number, col: number }
---@alias TextRegion { start: TextPoint, end: TextPoint }

---@param x string[] A table of strings; each string represents a line
---@param pattern string The pattern to match against
---@param plain boolean If `true`, special characters in `pattern` are ignored
---@return TextRegion[]
local gfind = function(x, pattern, plain)
    local x_collapsed, matches, init = table.concat(x, "\n"), {}, 0

    while true do
        local start, stop = x_collapsed:find(pattern, init, plain)
        if start == nil then break end
        table.insert(matches, { start = start, stop = stop })
        init = stop + 1
    end

    local match_line, match_col = 1, 0

    for _, m in pairs(matches) do
        for _, type in ipairs({ "start", "stop" }) do
            local line_end = match_col + #x[match_line]
            while m[type] > line_end do
                match_col  = match_col + #x[match_line] + 1
                match_line = match_line + 1
                line_end   = match_col + #x[match_line]
            end
            m[type] = { line = match_line, col = m[type] - match_col }
        end
    end

    return matches
end

local match_ns = vim.api.nvim_create_namespace("visual-matches")

vim.api.nvim_create_autocmd({ "CursorMoved", "ModeChanged" }, {
    callback = function()
        vim.api.nvim_buf_clear_namespace(0, match_ns, 0, -1)

        local mode = vim.fn.mode()
        if mode ~= "v" and mode ~= "V" then return end

        local selection_start, selection_stop = vim.fn.getpos("v"), vim.fn.getpos(".")
        local selection_text = vim.fn.getregion(selection_start, selection_stop, { type = mode })

        if #selection_text > config.lines_upper_limit then return end

        local selection_collapsed = vim.trim(table.concat(selection_text, "\n"))

        if #selection_collapsed < config.chars_lower_limit then return end

        local selection_pattern = selection_collapsed:gsub("(%p)", "%%%0")
        selection_pattern       = config.strict_spacing and selection_pattern or selection_pattern:gsub("%s+", "%%s+")
        local first_line        = math.max(0, vim.fn.line("w0", vim.api.nvim_get_current_win()) - #selection_text)
        local last_line         = vim.fn.line("w$", vim.api.nvim_get_current_win()) + #selection_text
        local visible_text      = vim.api.nvim_buf_get_lines(0, first_line, last_line, false)
        local matches           = gfind(visible_text, selection_pattern, false)

        for _, m in pairs(matches) do
            m.start.line, m.stop.line = m.start.line + first_line, m.stop.line + first_line

            local m_starts_after_selection = m.start.line > selection_stop[2]  or (m.start.line == selection_stop[2]  and m.start.col > selection_stop[3])
            local m_ends_before_selection  = m.stop.line  < selection_start[2] or (m.stop.line  == selection_start[2] and m.stop.col  < selection_start[3])

            if m_starts_after_selection or m_ends_before_selection then
                for line = m.start.line, m.stop.line do
                    vim.api.nvim_buf_add_highlight(
                        0, match_ns, config.hl_group, line - 1,
                        line == m.start.line and m.start.col - 1 or 0,
                        line == m.stop.line and m.stop.col or -1
                    )
                end
            end
        end
    end
})

return M
