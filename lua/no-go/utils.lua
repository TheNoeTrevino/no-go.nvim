local M = {}

--- Check if a node represents a configured identifier (e.g., "err", "error")
--- @param node TSNode|nil The treesitter node to check
--- @param bufnr number The buffer number
--- @param config table The plugin configuration
--- @return boolean True if the node matches a configured identifier
function M.is_configured_identifier(node, bufnr, config)
	if not node then
		return false
	end

	local text = vim.treesitter.get_node_text(node, bufnr)

	for _, identifier in ipairs(config.identifiers) do
		if text == identifier then
			return true
		end
	end

	return false
end

--- Find the position of the opening brace on the if line
--- @param bufnr number The buffer number
--- @param if_start_row number The row number of the if statement
--- @param char string The character to detect (e.g., "{", "(")
--- @return number|nil The column position of the opening brace (0-indexed), or nil if not found
function M.find_opening_pair(bufnr, if_start_row, char)
	local line = vim.api.nvim_buf_get_lines(bufnr, if_start_row, if_start_row + 1, false)[1]
	if not line then
		return nil
	end

	local brace_col = line:find(char, 1, true)
	if brace_col then
		return brace_col - 1
	end
	return nil
end

--- Find the position of the closing brace
--- @param bufnr number The buffer number
--- @param if_end_row number The row number of the closing brace
--- @param char string The character to detect (e.g., "}", ")")
--- @return number|nil The column position of the closing brace (0-indexed), or nil if not found
function M.find_closing_pair(bufnr, if_end_row, char)
	local line = vim.api.nvim_buf_get_lines(bufnr, if_end_row, if_end_row + 1, false)[1]
	if not line then
		return nil
	end

	local brace_col = nil
	for i = #line, 1, -1 do
		if line:sub(i, i) == char then
			brace_col = i - 1 -- Convert to 0-indexed
			break
		end
	end

	return brace_col
end

--- Build virtual text string based on return content and config
--- Format: prefix + [content + content_separator] + return_character + suffix
--- @param content string|nil The identifier from the return statement (e.g., "err"), or nil
--- @param config table The plugin configuration
--- @return string The formatted virtual text string
function M.build_virtual_text(content, config)
	local vtext = config.virtual_text
	local result = vtext.prefix or " "

	if content and content ~= "" then
		result = result .. content
		result = result .. (vtext.content_separator or " ")
	end

	result = result .. (vtext.return_character or "󱞿 ")

	result = result .. (vtext.suffix or "")

	return result
end

--- Check if a line is concealed by an extmark
--- @param bufnr number The buffer number
--- @param row number The row number to check (0-indexed)
--- @param namespace number The namespace ID
--- @return boolean True if the line is concealed
function M.is_line_concealed(bufnr, row, namespace)
	-- get all extmarks in the buffer with our namespace
	local marks = vim.api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, { details = true })

	for _, mark in ipairs(marks) do
		local start_row = mark[2]
		local details = mark[4]

		if details and details.conceal_lines and details.end_row then
			local end_row = details.end_row

			-- Check if the current row is in the concealed range
			if row >= start_row and row <= end_row then
				return true
			end
		end
	end

	return false
end

--- get concealed block range containing the row param
--- @param bufnr number The buffer number
--- @param row number The row number to check (0-indexed)
--- @param namespace number The namespace ID
--- @return table|nil Table with start_row and end_row (0-indexed), or nil if not concealed
function M.get_concealed_range(bufnr, row, namespace)
	local marks = vim.api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, { details = true })

	for _, mark in ipairs(marks) do
		local start_row = mark[2]
		local details = mark[4]

		if details and details.conceal_lines and details.end_row then
			local end_row = details.end_row

			if row >= start_row and row <= end_row then
				return { start_row = start_row, end_row = end_row }
			end
		end
	end

	return nil
end

--- lines to skip for smart downward motion
--- @param count number The motion count (vim.v.count1)
--- @param namespace number The namespace ID
--- @return number The number of buffer lines to move
function M.smart_down_lines(count, namespace)
	local bufnr = vim.api.nvim_get_current_buf()
	local current_line = vim.fn.line(".")
	local max_line = vim.fn.line("$")

	local target_line = math.min(current_line + count, max_line)

	-- check if target line lands inside a concealed block
	local range = M.get_concealed_range(bufnr, target_line - 1, namespace) -- -1 for 0-indexed
	if range then
		target_line = math.min(range.end_row + 2, max_line) -- +2: end_row is 0-indexed, +1 for 1-indexed, +1 for line after
	end

	return target_line - current_line
end

--- lines to skip for smart upward motion
--- @param count number The motion count (vim.v.count1)
--- @param namespace number The namespace ID
--- @return number The number of buffer lines to move (positive value)
function M.smart_up_lines(count, namespace)
	local bufnr = vim.api.nvim_get_current_buf()
	local current_line = vim.fn.line(".")
	local target_line = math.max(current_line - count, 1)

	-- check if target line lands inside a concealed block
	local range = M.get_concealed_range(bufnr, target_line - 1, namespace) -- -1 for 0-indexed
	if range then
		-- jump to the line before the concealed block (start_row is 0-indexed, lol)
		target_line = math.max(range.start_row, 1) -- start_row in 0-indexed = line before block in 1-indexed
	end

	return current_line - target_line
end

return M
