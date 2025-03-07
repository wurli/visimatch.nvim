local M = {}

---@class VisimatchConfig
---
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
---
---Visible buffers which should be highlighted. Valid options:
---* `"filetype"` (the default): highlight buffers with the same filetype
---* `"current"`: highlight matches in the current buffer only
---* `"all"`: highlight matches in all visible buffers
---* A function. This will be passed a buffer number and should return
---  `true`/`false` to indicate whether the buffer should be highlighted.
---@field buffers? "filetype" | "all" | "current" | fun(buf): boolean
---
---Case-(in)sensitivity for matches. Valid options:
---* `true`: matches will never be case-sensitive
---* `false`/`{}`: matches will always be case-sensitive
---* a table of filetypes to use use case-insensitive matching for
---@field case_insensitive? boolean | string[]
---
---Enable blinking for the main selection
---@field blink_enabled? boolean
---
---Blink interval in milliseconds
---@field blink_interval? number
---
---Highlight group for the blinking selection; defaults to `Visual`
---@field blink_hl_group? string

---@type VisimatchConfig
local config = {
    hl_group = "Search",
    chars_lower_limit = 4,
    lines_upper_limit = 45,
    strict_spacing = false,
    buffers = "filetype",
    case_insensitive = { "markdown", "text", "help" , "oil" },
    blink_enabled = true,
    blink_interval = 500,
    blink_hl_group = "Visual",
}

-- Store the blink timer
local blink_timer = nil
local blink_state = false

local function clear_blink_timer()
    if blink_timer then
        blink_timer:stop()
        blink_timer:close()
        blink_timer = nil
    end
end

local function toggle_selection_highlight(buf, start_pos, end_pos, visible)
    if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
    
    -- Convert from 1-based to 0-based line numbers for API calls
    local start_line = start_pos[2] - 1
    local end_line = end_pos[2] - 1
    
    -- Clear existing highlights
    vim.api.nvim_buf_clear_namespace(buf, match_ns, start_line, end_line + 1)
    
    -- Add highlight if visible is true
    if visible then
        for line = start_line, end_line do
            local col_start = (line == start_line) and start_pos[3] - 1 or 0
            local col_end = (line == end_line) and end_pos[3] or -1
            vim.api.nvim_buf_add_highlight(
                buf,
                match_ns,
                config.blink_hl_group,
                line,
                col_start,
                col_end
            )
        end
    end
end

---@param opts? VisimatchConfig
M.setup = function(opts)
    clear_blink_timer()
    
    config = vim.tbl_extend("force", config, opts or {})
    vim.validate({
        hl_group          = { config.hl_group,          "string" },
        chars_lower_limit = { config.chars_lower_limit, "number" },
        lines_upper_limit = { config.lines_upper_limit, "number" },
        strict_spacing    = { config.strict_spacing,    "boolean" },
        buffers           = { config.buffers,           { "string", "function" } },
        case_insensitive  = { config.case_insensitive,  { "boolean", "table" } },
        blink_enabled     = { config.blink_enabled,     "boolean" },
        blink_interval    = { config.blink_interval,    "number" },
        blink_hl_group    = { config.blink_hl_group,    "string" },
    })
end

-- string.find() seems to have a bug/issue where you get a `pattern too
-- complex` error if the pattern used is too long _and_ matches the text in
-- question. NB, to see this in action you just need to use a regular
-- string.find() in the algorithm and try selecting a tonne of repeated text.
-- This is a workaround for this bug, which tries a normal `find()` call, and
-- if it fails, tries again by splitting the pattern up into ~100 character
-- chunks and checking them in sequence. This function isn't smart enough
-- to handle arbitrary patterns - but it is smart enough to handle the patterns
-- used in this plugin.
local find2 = function(s, pattern, init, plain)
    local ok, start, stop = pcall(string.find, s, pattern, init, plain)
    if ok then
        return start, stop
    end

    local needle_length = 100
    local needle_start, any_matches = 1, false
    local match_start
    local match_stop = init and (init - 1) or nil

    local i = 0
    while needle_start < pattern:len() do
        i = i + 1
        local needle_end = needle_start + needle_length

        -- If the end of the new pattern intersects either `%<anything>` or
        -- `%s+`, we need to extend the pattern by a few chars.
        local _, extra1 = pattern:find("^.?%%s%+", needle_end - 1)
        local _, extra2 = pattern:find("^[^%%]%%.", needle_end - 1)
        needle_end = extra1 or extra2 or needle_end

        local small_match_start, small_match_stop = s:find(
            pattern:sub(needle_start, needle_end),
            (match_stop or 0) + 1
        )

        if small_match_start then
            match_start = match_start or small_match_start
            match_stop = small_match_stop
            any_matches = true
        elseif any_matches then
            return nil, nil
        end

        needle_start = needle_end + 1
    end

    return match_start, match_stop
end

---@alias TextPoint { line: number, col: number }
---@alias TextRegion { start: TextPoint, stop: TextPoint }

---@param x string[] A table of strings; each string represents a line
---@param pattern string The pattern to match against
---@param plain boolean If `true`, special characters in `pattern` are ignored
---@return TextRegion[]
local gfind = function(x, pattern, plain)
    local x_collapsed, matches, init = table.concat(x, "\n"), {}, 0

    while true do
        local start, stop = find2(x_collapsed, pattern, init, plain)
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

---@param how "all" | "current" | "filetype" | fun(buf): boolean
local get_wins = function(how)
    if how == "current" then
        return { vim.api.nvim_get_current_win() }
    elseif how == "all" then
        return vim.api.nvim_tabpage_list_wins(0)
    elseif how == "filetype" then
        return vim.tbl_filter(
            function(w) return vim.bo[vim.api.nvim_win_get_buf(w)].ft == vim.bo.ft end,
            vim.api.nvim_tabpage_list_wins(0)
        )
    elseif type(how) == "function" then
        return vim.tbl_filter(
            function(w)
                return how(vim.api.nvim_win_get_buf(w)) and true or false
            end,
            vim.api.nvim_tabpage_list_wins(0)
        )
    end
    error(("Invalid input for `how`: `%s`"):format(vim.inspect(how)))
end

local is_case_insensitive = function(ft1, ft2)
    if type(config.case_insensitive) == "boolean" then return config.case_insensitive end
    if type(config.case_insensitive) == "table" then
        ---@diagnostic disable-next-line: param-type-mismatch
        for _, special_ft in ipairs(config.case_insensitive) do
            if ft1 == special_ft or ft2 == special_ft then return true end
        end
    end
    return false
end


local match_ns = vim.api.nvim_create_namespace("visimatch")
local augroup = vim.api.nvim_create_augroup("visimatch", { clear = true })

vim.api.nvim_create_autocmd({ "CursorMoved", "ModeChanged" }, {
    group = augroup,
    callback = function()
        -- clean existing blink timer
        clear_blink_timer()
        
        local wins = get_wins(config.buffers)
        for _, win in pairs(wins) do
            vim.api.nvim_buf_clear_namespace(vim.api.nvim_win_get_buf(win), match_ns, 0, -1)
        end

        local mode = vim.fn.mode()
        if mode ~= "v" and mode ~= "V" then return end

        local selection_start, selection_stop = vim.fn.getpos("v"), vim.fn.getpos(".")
        local selection = vim.fn.getregion(selection_start, selection_stop, { type = mode })
        local selection_collapsed = vim.trim(table.concat(selection, "\n"))
        local selection_buf = vim.api.nvim_get_current_buf()

        if #selection > config.lines_upper_limit           then return end
        if #selection_collapsed < config.chars_lower_limit then return end

        if config.blink_enabled then
            blink_state = true
            blink_timer = vim.loop.new_timer()
            blink_timer:start(0, config.blink_interval, vim.schedule_wrap(function()
                blink_state = not blink_state
                toggle_selection_highlight(selection_buf, selection_start, selection_stop, blink_state)
            end))
        end

        local pattern = selection_collapsed:gsub("(%p)", "%%%0")
        if not config.strict_spacing then pattern = pattern:gsub("%s+", "%%s+") end
        local pattern_lower

        for _, win in pairs(wins) do
            local first_line       = math.max(0, vim.fn.line("w0", win) - #selection)
            local last_line        = vim.fn.line("w$", win) + #selection
            local buf              = vim.api.nvim_win_get_buf(win)
            local visible_text     = vim.api.nvim_buf_get_lines(buf, first_line, last_line, false)
            local case_insensitive = is_case_insensitive(vim.bo[buf].ft, vim.bo.ft)

            if case_insensitive and not pattern_lower then pattern_lower = pattern:lower() end

            local needle           = case_insensitive and pattern_lower or pattern
            local haystack         = case_insensitive and vim.tbl_map(string.lower, visible_text) or visible_text
            local matches          = gfind(haystack, needle, false)

            for _, m in pairs(matches) do
                m.start.line, m.stop.line = m.start.line + first_line, m.stop.line + first_line

                local m_starts_after_selection = m.start.line > selection_stop[2]  or (m.start.line == selection_stop[2]  and m.start.col > selection_stop[3])
                local m_ends_before_selection  = m.stop.line  < selection_start[2] or (m.stop.line  == selection_start[2] and m.stop.col  < selection_start[3])

                if buf ~= selection_buf or m_starts_after_selection or m_ends_before_selection then
                    for line = m.start.line, m.stop.line do
                        vim.api.nvim_buf_add_highlight(
                            buf, match_ns, config.hl_group, line - 1,
                            line == m.start.line and m.start.col - 1 or 0,
                            line == m.stop.line and m.stop.col or -1
                        )
                    end
                end
            end
        end
    end
})


vim.api.nvim_create_autocmd("VimLeavePre", {
    group = augroup,
    callback = function()
        clear_blink_timer()
    end,
})

return M

