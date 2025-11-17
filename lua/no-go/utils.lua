local M = {}

-- Check if a node is an identifier (from config)
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

-- Find the pos of opening brace on the if line
function M.find_opening_brace(bufnr, if_start_row)
	local line = vim.api.nvim_buf_get_lines(bufnr, if_start_row, if_start_row + 1, false)[1]
	if not line then
		return nil
	end

	local brace_col = line:find("{")
	if brace_col then
		return brace_col - 1
	end
	return nil
end

-- Find the pos of closing brace
function M.find_closing_brace(bufnr, if_end_row)
	local line = vim.api.nvim_buf_get_lines(bufnr, if_end_row, if_end_row + 1, false)[1]
	if not line then
		return nil
	end

	local brace_col = nil
	for i = #line, 1, -1 do
		if line:sub(i, i) == "}" then
			brace_col = i - 1 -- Convert to 0-indexed
			break
		end
	end

	return brace_col
end

-- Based on return contnet and config
-- Format: prefix + [content + content_separator] + return_character + suffix
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

return M
