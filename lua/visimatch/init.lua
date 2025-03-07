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
---Enable blinking effect for main visual selection; defaults to `true`.
---@field blink_enabled? boolean
---
---Blink interval in milliseconds; defaults to 500.
---@field blink_time? number
---
---Highlight group for blinking selection; defaults to `IncSearch`.
---@field blink_hl_group? string

---@type VisimatchConfig
local config = {
	hl_group = "Search",
	chars_lower_limit = 6,
	lines_upper_limit = 30,
	strict_spacing = false,
	buffers = "filetype",
	case_insensitive = { "markdown", "text", "help" },
	blink_enabled = true,
	blink_time = 500,
	blink_hl_group = "IncSearch",
}

---@param opts? VisimatchConfig
M.setup = function(opts)
	config = vim.tbl_extend("force", config, opts or {})
	vim.validate({
		hl_group = { config.hl_group, "string" },
		chars_lower_limit = { config.chars_lower_limit, "number" },
		lines_upper_limit = { config.lines_upper_limit, "number" },
		strict_spacing = { config.strict_spacing, "boolean" },
		buffers = { config.buffers, { "string", "function" } },
		case_insensitive = { config.case_insensitive, { "boolean", "table" } },
		blink_enabled = { config.blink_enabled, "boolean", true },
		blink_time = { config.blink_time, "number", true },
		blink_hl_group = { config.blink_hl_group, "string", true },
	})
end

-- [Previous utility functions: find2, gfind, get_wins, is_case_insensitive]

local match_ns = vim.api.nvim_create_namespace("visimatch")
local main_selection_ns = vim.api.nvim_create_namespace("visimatch_main_selection")
local augroup = vim.api.nvim_create_augroup("visimatch", { clear = true })

local main_selection = nil
local blink_timer = nil
local blink_state = false

local function apply_blink_highlight(selection)
	local buf = selection.buf
	vim.api.nvim_buf_clear_namespace(buf, main_selection_ns, 0, -1)

	if selection.mode == "V" then
		for line = selection.start_line, selection.end_line do
			vim.api.nvim_buf_add_highlight(buf, main_selection_ns, config.blink_hl_group, line - 1, 0, -1)
		end
	else
		local start_line = selection.start_line
		local end_line = selection.end_line
		for line = start_line, end_line do
			local start_col = (line == start_line) and (selection.start_col - 1) or 0
			local end_col = (line == end_line) and selection.end_col or -1
			vim.api.nvim_buf_add_highlight(buf, main_selection_ns, config.blink_hl_group, line - 1, start_col, end_col)
		end
	end
end

vim.api.nvim_create_autocmd({ "CursorMoved", "ModeChanged" }, {
	group = augroup,
	callback = function()
		-- Clear existing highlights
		local wins = get_wins(config.buffers)
		for _, win in pairs(wins) do
			vim.api.nvim_buf_clear_namespace(vim.api.nvim_win_get_buf(win), match_ns, 0, -1)
		end

		-- Original match highlighting logic
		local mode = vim.fn.mode()
		if mode ~= "v" and mode ~= "V" then
			if blink_timer then
				blink_timer:stop()
				blink_timer:close()
				blink_timer = nil
			end
			main_selection = nil
			return
		end

		local selection_start, selection_stop = vim.fn.getpos("v"), vim.fn.getpos(".")
		local selection = vim.fn.getregion(selection_start, selection_stop, { type = mode })
		local selection_collapsed = vim.trim(table.concat(selection, "\n"))
		local selection_buf = vim.api.nvim_get_current_buf()

		-- Crucial fix for timer cleanup
		if #selection > config.lines_upper_limit or #selection_collapsed < config.chars_lower_limit then
			if blink_timer then
				blink_timer:stop()
				blink_timer:close()
				blink_timer = nil
			end
			main_selection = nil
			vim.api.nvim_buf_clear_namespace(selection_buf, main_selection_ns, 0, -1)
			return
		end

		-- [Rest of the original implementation...]
	end,
})

return M
