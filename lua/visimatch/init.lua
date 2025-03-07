local M = {}

-- Combined configuration
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

-- Setup function
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
		block_hl_group = { config.block_hl_group, "string" },
		block_max_width = { config.block_max_width, "number" },
	})
end

-- Utility function
local function get_wins(how)
	local current_win = vim.api.nvim_get_current_win()
	local current_buf = vim.api.nvim_win_get_buf(current_win)
	local current_ft = vim.api.nvim_buf_get_option(current_buf, "filetype")

	if how == "current" then
		return { current_win }
	elseif how == "all" then
		return vim.api.nvim_list_wins()
	elseif how == "filetype" then
		local wins = {}
		for _, win in ipairs(vim.api.nvim_list_wins()) do
			local buf = vim.api.nvim_win_get_buf(win)
			local ft = vim.api.nvim_buf_get_option(buf, "filetype")
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

-- Namespaces and augroup
local match_ns = vim.api.nvim_create_namespace("visimatch")
local block_match_ns = vim.api.nvim_create_namespace("visimatch-block")
local main_selection_ns = vim.api.nvim_create_namespace("visimatch_main_selection")
local augroup = vim.api.nvim_create_augroup("visimatch", { clear = true })

-- Blinking variables
local main_selection = nil
local blink_timer = nil
local blink_state = false

-- Blinking highlight function
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

-- Block selection processing
local function process_block_selection()
	local start_pos = vim.fn.getpos("v")
	local end_pos = vim.fn.getpos(".")
	local buf = vim.api.nvim_get_current_buf()
	-- Normalize block coordinates
	local start_line = math.min(start_pos[2], end_pos[2])
	local end_line = math.max(start_pos[2], end_pos[2])
	local start_col = math.min(start_pos[3], end_pos[3])
	local end_col = math.max(start_pos[3], end_pos[3])
	-- Validate block width
	if (end_col - start_col) > config.block_max_width then
		return
	end
	-- Extract block text pattern
	local block_pattern = {}
	for lnum = start_line, end_line do
		local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, true)[1] or ""
		table.insert(block_pattern, vim.trim(line:sub(start_col, end_col)))
	end
	-- Find matches in target buffers
	for _, win in ipairs(get_wins("filetype")) do
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
							block_match_ns,
							config.block_hl_group,
							lnum + i - 2, -- 0-based
							col - 1, -- 0-based
							col + (end_col - start_col) - 1
						)
					end
				end
			end
		end
	end
end

-- Clear all highlights
local function clear_highlights()
	-- Clear match highlights
	local wins = get_wins(config.buffers)
	for _, win in pairs(wins) do
		local buf = vim.api.nvim_win_get_buf(win)
		vim.api.nvim_buf_clear_namespace(buf, match_ns, 0, -1)
	end
	-- Clear block highlights
	local block_wins = get_wins("filetype")
	for _, win in pairs(block_wins) do
		local buf = vim.api.nvim_win_get_buf(win)
		vim.api.nvim_buf_clear_namespace(buf, block_match_ns, 0, -1)
	end
	-- Clear main selection and stop timer
	local current_buf = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_clear_namespace(current_buf, main_selection_ns, 0, -1)
	if blink_timer then
		blink_timer:stop()
		blink_timer:close()
		blink_timer = nil
	end
	main_selection = nil
end

-- Unified autocommand
vim.api.nvim_create_autocmd({ "CursorMoved", "ModeChanged" }, {
	group = augroup,
	callback = function()
		clear_highlights()
		local mode = vim.fn.mode()
		if mode == "v" or mode == "V" then
			local selection_start, selection_stop = vim.fn.getpos("v"), vim.fn.getpos(".")
			local selection = vim.fn.getregion(selection_start, selection_stop, { type = mode })
			local selection_collapsed = vim.trim(table.concat(selection, "\n"))
			local selection_buf = vim.api.nvim_get_current_buf()
			if #selection > config.lines_upper_limit or #selection_collapsed < config.chars_lower_limit then
				return
			end
			-- Placeholder for original match highlighting logic
			-- Add your matching logic here, e.g.:
			-- local pattern = ... (construct based on config.strict_spacing, case_insensitive)
			-- for _, win in ipairs(get_wins(config.buffers)) do
			--     local buf = vim.api.nvim_win_get_buf(win)
			--     -- Highlight matches using match_ns and config.hl_group
			-- end
			main_selection = {
				buf = selection_buf,
				mode = mode,
				start_line = selection_start[2],
				end_line = selection_stop[2],
				start_col = selection_start[3],
				end_col = selection_stop[3],
			}
			if config.blink_enabled then
				apply_blink_highlight(main_selection)
				-- Add blinking logic if needed
			end
		elseif mode == "" then
			process_block_selection()
		end
	end,
})

return M
