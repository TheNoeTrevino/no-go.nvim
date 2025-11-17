local M = {}
local utils = require("no-go.utils")

M.namespace = vim.api.nvim_create_namespace("no-go")

M.query_string = [[
(
  (if_statement
    condition: (binary_expression
      left: (identifier) @err_identifier)
    consequence: (block
      (statement_list
        (return_statement
          (expression_list
            (identifier) @return_identifier)?)))) @collapse_block) @if_statement
]]

function M.get_query()
	local ok, query = pcall(vim.treesitter.query.parse, "go", M.query_string)
	if not ok then
		vim.notify("no-go.nvim: Failed to parse Treesitter query", vim.log.levels.ERROR)
		return nil
	end
	return query
end

function M.clear_extmarks(bufnr)
	vim.api.nvim_buf_clear_namespace(bufnr, M.namespace, 0, -1)
end

-- Apply virtual text to replace the error handling block
-- return the identifier from the return statement (e.g., "err"), or nil if no identifier
function M.apply_collapse(bufnr, if_node, collapse_node, return_content, config)
	local if_start_row, _, if_end_row, _ = if_node:range()

	-- check if cursor is inside this block and reveal_on_cursor is enabled
	if config.reveal_on_cursor then
		-- get all windows showing this buffer
		local wins = vim.fn.win_findbuf(bufnr)
		for _, win in ipairs(wins) do
			local cursor = vim.api.nvim_win_get_cursor(win)
			local cursor_row = cursor[1] - 1 -- Convert to 0-indexed

			-- if cursor is on the if line OR inside the block, don't apply concealment!
			-- this allows the user to navigate inside the revealed error handling code
			if cursor_row >= if_start_row and cursor_row <= if_end_row then
				return
			end
		end
	end

	local brace_start_col = utils.find_opening_brace(bufnr, if_start_row)
	if not brace_start_col then
		return
	end

	local brace_end_col = utils.find_closing_brace(bufnr, if_end_row)
	if not brace_end_col then
		return
	end

	-- Conceal from { to end of the if line (hide the opening brace and anything after it)
	local if_line = vim.api.nvim_buf_get_lines(bufnr, if_start_row, if_start_row + 1, false)[1]
	if if_line then
		vim.api.nvim_buf_set_extmark(bufnr, M.namespace, if_start_row, brace_start_col, {
			end_row = if_start_row,
			end_col = #if_line, -- End of line
			conceal = "",
		})
	end

	-- hide all intermediate lines completely using conceal_lines, lines between braces
	-- includes the body of the if block AND the closing brace line (yes!)
	if if_end_row > if_start_row then
		vim.api.nvim_buf_set_extmark(bufnr, M.namespace, if_start_row + 1, 0, {
			end_row = if_end_row, -- end_row is inclusive, so this hides from if_start_row+1 to if_end_row
			end_col = 0,
			conceal_lines = "",
		})
	end

	local virtual_text_string = utils.build_virtual_text(return_content, config)
	vim.api.nvim_buf_set_extmark(bufnr, M.namespace, if_start_row, brace_start_col, {
		virt_text = { { virtual_text_string, config.highlight_group } },
		virt_text_pos = "inline",
	})
end

-- Smart cursor movement that skips concealed lines
function M.move_cursor_skip_concealed(direction)
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1 -- Convert to 0-indexed
	local col = cursor[2]
	local max_row = vim.api.nvim_buf_line_count(bufnr) - 1

	if direction == "down" then
		row = row + 1
	elseif direction == "up" then
		row = row - 1
	end

	-- keep moving until we find a non-concealed line
	local attempts = 0
	local max_attempts = 100 -- prevent loop

	while attempts < max_attempts and row >= 0 and row <= max_row do
		if not utils.is_line_concealed(bufnr, row, M.namespace) then
			-- Found a non-concealed line, move cursor there
			vim.api.nvim_win_set_cursor(0, { row + 1, col })
			return
		end

		-- continue moving in the same direction
		if direction == "down" then
			row = row + 1
		elseif direction == "up" then
			row = row - 1
		end

		attempts = attempts + 1
	end

	-- if we couldn't find a non-concealed line, just move normally
	if direction == "down" then
		vim.cmd("normal! j")
	elseif direction == "up" then
		vim.cmd("normal! k")
	end
end

-- Setup buffer mappings to skip concealed lines
function M.setup_keymaps(bufnr, config)
	if not config.keymaps or config.keymaps == false then
		return
	end

	local opts = { buffer = bufnr, silent = true, noremap = true }

	-- helper function to set up keymaps (handles both string and table)
	local function setup_key(keys, direction)
		if not keys then
			return
		end

		local key_list = type(keys) == "table" and keys or { keys }

		for _, key in ipairs(key_list) do
			vim.keymap.set("n", key, function()
				M.move_cursor_skip_concealed(direction)
			end, opts)
		end
	end

	setup_key(config.keymaps.move_down, "down")
	setup_key(config.keymaps.move_up, "up")
end

-- Process buffer and apply collapses
function M.process_buffer(bufnr, config)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	-- check if buffer is a go file early
	local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
	if filetype ~= "go" then
		return
	end

	M.clear_extmarks(bufnr)

	-- set conceallevel at the window level so concealing works
	vim.api.nvim_buf_call(bufnr, function()
		vim.wo.conceallevel = 2
		vim.wo.concealcursor = "nvic" -- conceal in all modes
	end)

	local query = M.get_query()
	if not query then
		return
	end

	local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "go")
	if not ok then
		return
	end

	local tree = parser:parse()[1]
	if not tree then
		return
	end

	local root = tree:root()

	-- iterate query matches
	for id, node, _ in query:iter_captures(root, bufnr, 0, -1) do
		local capture_name = query.captures[id]

		if capture_name == "if_statement" then -- checking capture group
			local err_identifier_node = nil
			local collapse_block_node = nil
			local return_identifier_node = nil

			-- gets the nodes we need to make the virtual text, and what we will collapse
			for child_id, child_node, _ in query:iter_captures(node, bufnr, 0, -1) do
				local child_capture_name = query.captures[child_id]

				if child_capture_name == "err_identifier" then
					err_identifier_node = child_node
				elseif child_capture_name == "collapse_block" then
					collapse_block_node = child_node
				elseif child_capture_name == "return_identifier" then
					return_identifier_node = child_node
				end
			end

			-- collapse if:
			---- identifier is in the configured identifiers list
			---- have a collapse block (statement_list with return)
			if
				err_identifier_node
				and utils.is_configured_identifier(err_identifier_node, bufnr, config)
				and collapse_block_node
			then
				-- get the returned var name, for err ^ text
				local return_content = nil
				if return_identifier_node then
					return_content = vim.treesitter.get_node_text(return_identifier_node, bufnr)
				end

				M.apply_collapse(bufnr, node, collapse_block_node, return_content, config)
			end
		end
	end

	M.setup_keymaps(bufnr, config)
end

return M
