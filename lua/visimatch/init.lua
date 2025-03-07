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
---  `true`/`false` to indicate whether the buffer should be highlighted.
---@field buffers? "filetype" | "all" | "current" | fun(buf): boolean
---
---Case-(in)sensitivity for matches. Valid options:
---* `true`: matches will never be case-sensitive
---* `false`/`{}`: matches will always be case-sensitive
---* a table of filetypes to use use case-insensitive matching for
---@field case_insensitive? boolean | string[]
---
---Enable blinking for the main selection in visual mode. Defaults to `false`.
---@field blink_selection? boolean
---
---Blinking interval in milliseconds. Defaults to `500`.
---@field blink_interval? number

---@type VisimatchConfig
local config = {
    hl_group = "Search",
    chars_lower_limit = 6,
    lines_upper_limit = 30,
    strict_spacing = false,
    buffers = "filetype",
    case_insensitive = { "markdown", "text", "help" },
    blink_selection = false, -- New option
    blink_interval = 500,   -- New option
}

---@param opts? VisimatchConfig
M.setup = function(opts)
    config = vim.tbl_extend("force", config, opts or {})
    vim.validate({
        hl_group          = { config.hl_group,          "string" },
        chars_lower_limit = { config.chars_lower_limit, "number" },
        lines_upper_limit = { config.lines_upper_limit, "number" },
        strict_spacing    = { config.strict_spacing,    "boolean" },
        buffers           = { config.buffers,           { "string", "function" } },
        case_insensitive  = { config.case_insensitive,  { "boolean", "table" } },
        blink_selection   = { config.blink_selection,   "boolean" }, -- Validate new option
        blink_interval    = { config.blink_interval,    "number" },  -- Validate new option
    })
    if M.blink_timer then -- Stop existing timer if setup is called again
        M.blink_timer:stop()
        M.blink_timer:close()
        M.blink_timer = nil
    end
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
                match_col  = match_col + #x[match_line] + 1
                match_line = match_line + 1
                line_end   = match_col + #x[match_line]
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
        return false
end


local match_ns = vim.api.nvim_create_namespace("visimatch")
local selection_blink_ns = vim.api.nvim_create_namespace("visimatch_selection_blink") -- New namespace for selection blink
local augroup = vim.api.nvim_create_augroup("visimatch", { clear = true })

M.blink_timer = nil -- Timer variable to control blinking
M.blink_state = false -- State to track highlight on/off for blinking


local clear_selection_blink_highlight = function(bufnr)
    vim.api.nvim_buf_clear_namespace(bufnr, selection_blink_ns, 0, -1)
end

local set_selection_blink_highlight = function(bufnr, selection_start, selection_stop)
    if not M.blink_state then
        local mode = vim.fn.mode()
        local selection_region = vim.fn.getregion(selection_start, selection_stop, { type = mode })
        if #selection_region > 0 then
            local start_line = selection_start[2]
            local end_line = selection_stop[2]
            for line_num = start_line, end_line do
                local start_col = (line_num == start_line and selection_start[3] or 1) -1
                local end_col = (line_num == end_line and selection_stop[3] or -1) - (line_num == end_line and 1 or 0) -- -1 for till end, adjust end col
                vim.api.nvim_buf_add_highlight(bufnr, selection_blink_ns, config.hl_group, line_num - 1, start_col , end_col)
            end
        end
    end
    M.blink_state = not M.blink_state -- Toggle state for next blink
end


vim.api.nvim_create_autocmd({ "CursorMoved", "ModeChanged" }, {
    group = augroup,
    callback = function()
        local wins = get_wins(config.buffers)
        for _, win in pairs(wins) do
            vim.api.nvim_buf_clear_namespace(vim.api.nvim_win_get_buf(win), match_ns, 0, -1)
        end
        local mode = vim.fn.mode()

        -- Handle selection blinking timer
        if mode == "v" or mode == "V" then
            local selection_start, selection_stop = vim.fn.getpos("v"), vim.fn.getpos(".")
            local selection = vim.fn.getregion(selection_start, selection_stop, { type = mode })
            local selection_collapsed = vim.trim(table.concat(selection, "\n"))

            if config.blink_selection and #selection_collapsed >= config.chars_lower_limit and #selection <= config.lines_upper_limit then
                if not M.blink_timer then
                    M.blink_timer = vim.loop.new_timer()
                    M.blink_timer:start(0, config.blink_interval, vim.schedule_wrap(function()
                        set_selection_blink_highlight(vim.api.nvim_get_current_buf(), selection_start, selection_stop)
                    end))
                end
            else
                if M.blink_timer then
                    M.blink_timer:stop()
                    M.blink_timer:close()
                    M.blink_timer = nil
                    clear_selection_blink_highlight(vim.api.nvim_get_current_buf())
                    M.blink_state = false -- Reset blink state
                end
            end
        else -- Not in visual mode
            if M.blink_timer then
                M.blink_timer:stop()
                M.blink_timer:close()
                M.blink_timer = nil
                clear_selection_blink_highlight(vim.api.nvim_get_current_buf())
                M.blink_state = false -- Reset blink state
            end
        end


        if mode ~= "v" and mode ~= "V" then return end

        local selection_start, selection_stop = vim.fn.getpos("v"), vim.fn.getpos(".")
        local selection = vim.fn.getregion(selection_start, selection_stop, { type = mode })
        local selection_collapsed = vim.trim(table.concat(selection, "\n"))
        local selection_buf = vim.api.nvim_get_current_buf()

        if #selection > config.lines_upper_limit           then return end
        if #selection_collapsed < config.chars_lower_limit then return end

        local pattern = selection_collapsed:gsub("(%p)", "%%%0")
        if not config.strict_spacing then pattern = pattern:gsub("%s+", "%%s+") end
        local pattern_lower

        for _, win in pairs(wins) do
            local first_line       = math.max(0, vim.fn.line("w0", win) - #selection)
            local last_line        = vim.fn.line("w$", win) + #selection
            local buf              = vim.api.nvim_win_get_buf(win)
            local visible_text     = vim.api.nvim_buf_get_lines(buf, first_line, last_line, false)
            local case_insensitive = is_case_insensitive(vim.bo[buf].ft, vim.bo.ft)

            if case_insensitive and not pattern_lower then pattern_lower = pattern:lower() end

            local needle           = case_insensitive and pattern_lower or pattern
            local haystack         = case_insensitive and vim.tbl_map(string.lower, visible_text) or visible_text
            local matches          = gfind(haystack, needle, false)

            for _, m in pairs(matches) do
                m.start.line, m.stop.line = m.start.line + first_line, m.stop.line + first_line

                local m_starts_after_selection = m.start.line > selection_stop[2]  or (m.start.line == selection_stop[2]  and m.start.col > selection_stop[3])
                local m_ends_before_selection  = m.stop.line  < selection_start[2] or (m.stop.line  == selection_start[2] and m.stop.col  < selection_start[3])

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

return M