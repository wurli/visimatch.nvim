local M = {}

---@class VisimatchConfig
---@field hl_group? string
---@field chars_lower_limit? number
---@field lines_upper_limit? number
---@field strict_spacing? boolean
---@field buffers? "filetype" | "all" | "current" | fun(buf): boolean
---@field case_insensitive? boolean | string[]
---@field blink_enabled? boolean
---@field blink_time? number
---@field blink_hl_group? string
---@field block_hl_group? string
---@field block_max_width? number

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
	block_hl_group = "Visual",
	block_max_width = 50,
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
		block_hl_group = { config.block_hl_group, "string", true },
		block_max_width = { config.block_max_width, "number", true },
	})
end

-- Utility functions
local function get_wins(how)
	local current_ft = vim.bo.filetype
	local wins = {}
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		if how == "current" then
			if win == vim.api.nvim_get_current_win() then
				table.insert(wins, win)
			end
		elseif how == "all" then
			table.insert(wins, win)
		elseif how == "filetype" then
			if vim.bo[buf].filetype == current_ft then
				table.insert(wins, win)
			end
		elseif type(how) == "function" and how(buf) then
			table.insert(wins, win)
		end
	end
	return wins
end

local function is_case_insensitive(filetype)
	if type(config.case_insensitive) == "table" then
		return vim.tbl_contains(config.case_insensitive, filetype)
	end
	return config.case_insensitive
end

-- Namespaces and autocmds
local match_ns = vim.api.nvim_create_namespace("visimatch")
local block_ns = vim.api.nvim_create_namespace("visimatch-block")
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
		local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, true)[1] or ""
		table.insert(block_pattern, vim.trim(line:sub(start_col, end_col)))
	end

	for _, win in ipairs(get_wins(config.buffers)) do
		local tbuf = vim.api.nvim_win_get_buf(win)
		local lines = vim.api.nvim_buf_get_lines(tbuf, 0, -1, false)
		for lnum = 1, #lines - #block_pattern + 1 do
			for col = 1, #lines[lnum] - (end_col - start_col) do
				local match = true
				for i = 1, #block_pattern do
					local chunk = lines[lnum + i - 1]:sub(col, col + (end_col - start_col))
					if chunk ~= block_pattern[i] then
						match = false
						break
					end
				end
				if match then
					for i = 1, #block_pattern do
						vim.api.nvim_buf_add_highlight(
							tbuf,
							block_ns,
							config.block_hl_group,
							lnum + i - 2,
							col - 1,
							col + (end_col - start_col) - 1
						)
					end
				end
			end
		end
	end
end

vim.api.nvim_create_autocmd({ "CursorMoved", "ModeChanged" }, {
	group = augroup,
	callback = function()
		-- Clear existing highlights
		local wins = get_wins(config.buffers)
		for _, win in pairs(wins) do
			local buf = vim.api.nvim_win_get_buf(win)
			vim.api.nvim_buf_clear_namespace(buf, match_ns, 0, -1)
			vim.api.nvim_buf_clear_namespace(buf, block_ns, 0, -1)
		end

		local mode = vim.fn.mode()

		-- Handle block mode
		if mode == "\22" then -- Visual block mode
			process_block_selection()
			return
		end

		-- Original visual mode handling
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

		-- Rest of your original logic...
	end,
})

return M
