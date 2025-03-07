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
---Enable blinking effect for the main selection
---@field blink_enabled? boolean
---
---Interval for blinking effect in milliseconds
---@field blink_time? number
---
---Highlight group for the blinking effect
---@field blink_hl_group? string
---
---Highlight group for block mode matches
---@field block_hl_group? string
---
---Maximum width for block mode highlights
---@field block_max_width? number

---@type VisimatchConfig
local config = {
    hl_group = "Search",              -- Highlight group for matches
    chars_lower_limit = 6,            -- Min characters to trigger highlighting
    lines_upper_limit = 30,           -- Max lines to highlight
    strict_spacing = false,           -- Whether spacing must match exactly
    buffers = "filetype",             -- Where to apply highlights: "current", "all", "filetype", or function
    case_insensitive = { "markdown", "text", "help" }, -- Filetypes or boolean for case-insensitive matching
    blink_enabled = true,             -- Enable blinking for main selection
    blink_time = 500,                 -- Blink interval in milliseconds
    blink_hl_group = "IncSearch",     -- Highlight group for blinking
    block_hl_group = "Visual",        -- Highlight group for block mode matches
    block_max_width = 50,             -- Max width for block mode highlights
}

---@param opts? VisimatchConfig
M.setup = function(opts)
    config = vim.tbl_extend("force", config, opts or {})
    vim.validate({
        hl_group          = { config.hl_group,          "string" },
        chars_lower_limit = { config.chars_lower_limit, "number" },
        lines_upper_limit = { config.lines_upper_limit, "number" },
        strict_spacing    = { config.strict_spacing,    "boolean" },
        buffers           = { config.buffers,           { "string", "function" } },
        case_insensitive  = { config.case_insensitive,  { "boolean", "table" } },
        blink_enabled     = { config.blink_enabled,     "boolean", true },
        blink_time        = { config.blink_time,        "number", true },
        blink_hl_group    = { config.blink_hl_group,    "string", true },
        block_hl_group    = { config.block_hl_group,    "string" },
        block_max_width   = { config.block_max_width,   "number" },
    })
end

local function get_wins(how)
    local current_win = vim.api.nvim_get_current_win()
    local current_buf = vim.api.nvim_win_get_buf(current_win)
    local current_ft = vim.api.nvim_buf_get_option(current_buf, 'filetype')

    if how == "current" then
        return { current_win }
    elseif how == "all" then
        return vim.api.nvim_list_wins()
    elseif how == "filetype" then
        local wins = {}
        for _, win in ipairs(vim.api.nvim_list_wins()) do
            local buf = vim.api.nvim_win_get_buf(win)
            local ft = vim.api.nvim_buf_get_option(buf, 'filetype')
            if ft == current_ft then
                table.insert(wins, win)
            end
        end
        return wins
    elseif type(how) == "function" then
        local wins = {}
        for _, win in ipairs(vim.api.nvim_list_wins()) do
            local buf = vim.api.nvim_win_get_buf(win)
            if how(buf) then
                table.insert(wins, win)
            end
        end
        return wins
    else
        error("Invalid 'buffers' option: " .. tostring(how))
    end
end

local match_ns = vim.api.nvim_create_namespace("visimatch")
local block_match_ns = vim.api.nvim_create_namespace("visimatch-block")
local main_selection_ns = vim.api.nvim_create_namespace("visimatch_main_selection")
local augroup = vim.api.nvim_create_augroup("visimatch", { clear = true })

local main_selection = nil
local blink_timer = nil
local blink_state = false

local function apply_blink_highlight(selection)
    local buf = selection.buf
    vim.api.nvim_buf_clear_namespace(buf, main_selection_ns, 0, -1)
    
    if selection.mode == 'v' then
        local start_line = selection.start_line
        local end_line = selection.end_line
        for line = start_line, end_line do
            local start_col = (line == start_line) and (selection.start_col - 1) or 0
            local end_col = (line == end_line) and (selection.end_col) or -1
            vim.api.nvim_buf_add_highlight(
                buf, main_selection_ns, config.blink_hl_group,
                line - 1, start_col, end_col
            )
        end
    elseif selection.mode == '\22' then
        local start_line = selection.start_line
        local end_line = selection.end_line
        
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        for lnum = start_line, end_line do
            local line = lines[lnum] or ""
            if selection.matching_pattern and line then
                local s, e = string.find(line, selection.matching_pattern, 1, true)
                if s then
                    vim.api.nvim_buf_add_highlight(
                        buf, main_selection_ns, config.blink_hl_group,
                        lnum - 1, s - 1, e
                    )
                end
            end
        end
    end
end

local function toggle_blink()
    if not main_selection or main_selection.mode == 'V' then return end
    blink_state = not blink_state
    if blink_state then
        apply_blink_highlight(main_selection)
    else
        vim.api.nvim_buf_clear_namespace(main_selection.buf, main_selection_ns, 0, -1)
    end
end

local function process_block_selection()
    local start_pos = vim.fn.getpos("v")
    local end_pos = vim.fn.getpos(".")
    local buf = vim.api.nvim_get_current_buf()
    
    local start_line = math.min(start_pos[2], end_pos[2])
    local end_line = math.max(start_pos[2], end_pos[2])
    local start_col = math.min(start_pos[3], end_pos[3])
    local end_col = math.max(start_pos[3], end_pos[3])
    
    if (end_col - start_col) > config.block_max_width then
        return
    end
    
    local block_pattern = {}
    for lnum = start_line, end_line do
        local line = vim.api.nvim_buf_get_lines(buf, lnum-1, lnum, true)[1] or ""
        local substring = line:sub(start_col, end_col)
        table.insert(block_pattern, substring)
    end
    
    local current_ft = vim.api.nvim_buf_get_option(buf, 'filetype')
    local case_insensitive = type(config.case_insensitive) == "boolean" and config.case_insensitive
        or vim.tbl_contains(config.case_insensitive, current_ft)
    
    if case_insensitive then
        for i, str in ipairs(block_pattern) do
            block_pattern[i] = string.lower(str)
        end
    end
    
    local matching_pattern = block_pattern[1]
    if case_insensitive then
        matching_pattern = string.lower(matching_pattern)
    end
    
    main_selection = {
        buf = buf,
        mode = '\22',
        start_line = start_line,
        end_line = end_line,
        start_col = start_col,
        end_col = end_col,
        matching_pattern = matching_pattern,
    }
    
    for _, win in ipairs(get_wins("filetype")) do
        local tbuf = vim.api.nvim_win_get_buf(win)
        local lines = vim.api.nvim_buf_get_lines(tbuf, 0, -1, false)
        for lnum, line in ipairs(lines) do
            local start_col = 1
            while true do
                local s, e = string.find(line, matching_pattern, start_col, true)
                if not s then break end
                vim.api.nvim_buf_add_highlight(tbuf, block_match_ns, config.hl_group, lnum - 1, s - 1, e)
                start_col = e + 1
            end
        end
    end
end

local function clear_highlights()
    local wins = get_wins(config.buffers)
    for _, win in pairs(wins) do
        local buf = vim.api.nvim_win_get_buf(win)
        vim.api.nvim_buf_clear_namespace(buf, match_ns, 0, -1)
    end
    
    local block_wins = get_wins("filetype")
    for _, win in pairs(block_wins) do
        local buf = vim.api.nvim_win_get_buf(win)
        vim.api.nvim_buf_clear_namespace(buf, block_match_ns, 0, -1)
    end
    
    local current_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_clear_namespace(current_buf, main_selection_ns, 0, -1)
    if blink_timer then
        blink_timer:stop()  
        blink_timer:close() 
        blink_timer = nil   
    end
    main_selection = nil
end

vim.api.nvim_create_autocmd({ "CursorMoved", "ModeChanged" }, {
    group = augroup,
    callback = function()
        clear_highlights()
        local mode = vim.fn.mode()
        if mode == "v" or mode == "V" or mode == "\22" then
        local selection_start, selection_stop = vim.fn.getpos("v"), vim.fn.getpos(".")
        local selection = vim.fn.getregion(selection_start, selection_stop, { type = mode })
        local selection_buf = vim.api.nvim_get_current_buf()

           
            local total_chars = 0
            for _, str in ipairs(selection) do
                total_chars = total_chars + #str
            end
            
            if #selection > config.lines_upper_limit or total_chars < config.chars_lower_limit then
                return
            end
            
            -- Normalize start and end positions
            local start_line = math.min(selection_start[2], selection_stop[2])
            local end_line = math.max(selection_start[2], selection_stop[2])
            local start_col = mode == "\22" and math.min(selection_start[3], selection_stop[3]) or selection_start[3]
            local end_col = mode == "\22" and math.max(selection_start[3], selection_stop[3]) or selection_stop[3]
            
           
            if mode == "\22" then
                
                main_selection = {
                    buf = selection_buf,
                    mode = mode,
                    start_line = start_line,
                    end_line = end_line,
                    start_col = start_col,
                    end_col = end_col,
                    matching_pattern = nil,  
                }
            else
                main_selection = {
                    buf = selection_buf,
                    mode = mode,
                    start_line = start_line,
                    end_line = end_line,
                    start_col = start_col,
                    end_col = end_col,
                }
            end
            
            if config.blink_enabled and mode ~= "V" then
                apply_blink_highlight(main_selection)
                blink_timer = vim.loop.new_timer()
                blink_timer:start(config.blink_time, config.blink_time, vim.schedule_wrap(toggle_blink))
            end
            
            if mode == "v" then
                local selected_text = table.concat(selection, "\n")
                for _, win in ipairs(get_wins(config.buffers)) do
                    local buf = vim.api.nvim_win_get_buf(win)
                    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
                    for lnum, line in ipairs(lines) do
                        local start_col = 1
                        while true do
                            local s, e = string.find(line, selected_text, start_col, true)
                            if not s then break end
                            vim.api.nvim_buf_add_highlight(buf, match_ns, config.hl_group, lnum-1, s-1, e)
                            start_col = e + 1
                        end
                    end
                end
            elseif mode == "V" then
                local selected_lines = {}
                for _, line in ipairs(selection) do
                    selected_lines[line] = true
                end
                for _, win in ipairs(get_wins(config.buffers)) do
                    local buf = vim.api.nvim_win_get_buf(win)
                    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
                    for lnum, line in ipairs(lines) do
                        if selected_lines[line] then
                            vim.api.nvim_buf_add_highlight(buf, match_ns, config.hl_group, lnum-1, 0, -1)
                        end
                    end
                end
            elseif mode == "\22" then
                process_block_selection()
            end
        end
    end,
})

vim.api.nvim_create_autocmd("ModeChanged", {
    group = augroup,
    callback = function()
        if vim.fn.mode() ~= "v" and vim.fn.mode() ~= "V" and vim.fn.mode() ~= "\22" then
            clear_highlights()
        end
    end,
})

return M