local M = {}

---@class VisimatchBlockConfig
---
---Highlight group for block matches; defaults to `Visual`.
---@field block_hl_group? string
---
---Maximum width for block matching; defaults to 50.
---@field block_max_width? number

---@type VisimatchBlockConfig
local config = {
	block_hl_group = "Visual",
	block_max_width = 50,
}

---@param opts? VisimatchBlockConfig
M.setup = function(opts)
	config = vim.tbl_extend("force", config, opts or {})
	vim.validate({
		block_hl_group = { config.block_hl_group, "string" },
		block_max_width = { config.block_max_width, "number" },
	})
end

local match_ns = vim.api.nvim_create_namespace("visimatch-block")
local augroup = vim.api.nvim_create_augroup("visimatch-block", { clear = true })

local function get_wins(how)
	-- Same implementation as in visimatch.lua
end

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

		-- Check each possible column position
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
					-- Highlight vertical block match
					for i = 1, #block_pattern do
						vim.api.nvim_buf_add_highlight(
							tbuf,
							match_ns,
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

vim.api.nvim_create_autocmd({ "CursorMoved", "ModeChanged" }, {
	group = augroup,
	callback = function()
		local mode = vim.fn.mode()
		if mode == "" then -- Visual block mode
			process_block_selection()
		end
	end,
})

return M
