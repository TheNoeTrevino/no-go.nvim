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

--- Parse and return the Treesitter query for Go error handling patterns
--- @return vim.treesitter.Query|nil The parsed query or nil if parsing fails
function M.get_query()
	local has_parser = pcall(vim.treesitter.language.inspect, "go")

	local ok, query = pcall(vim.treesitter.query.parse, "go", M.query_string)
	if not ok then
		if not has_parser then
			vim.notify("no-go.nvim: Go parser not found. Install it with :TSInstall go", vim.log.levels.ERROR)
		else
			vim.notify(
				"no-go.nvim: Failed to parse query. Try updating the parser with :TSUpdate go",
				vim.log.levels.ERROR
			)
		end
		return nil
	end
	return query
end

--- Clear all extmarks in the specified buffer
--- @param bufnr number The buffer number
function M.clear_extmarks(bufnr)
	vim.api.nvim_buf_clear_namespace(bufnr, M.namespace, 0, -1)
end

--- Apply virtual text and concealment to collapse an error handling block
--- @param bufnr number The buffer number
--- @param if_node TSNode The if statement node
--- @param _ TSNode The block node to collapse
--- @param return_content string|nil The identifier from the return statement (e.g., "err"), or nil
--- @param config table The plugin configuration
function M.apply_collapse(bufnr, if_node, _, return_content, config)
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

--- Process buffer and apply collapses to error handling blocks
--- @param bufnr number|nil The buffer number (defaults to current buffer)
--- @param config table The plugin configuration
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
end

return M
