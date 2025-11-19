local M = {}
local utils = require("no-go.utils")
local queries = require("no-go.queries")

M.namespace = vim.api.nvim_create_namespace("no-go")

--- Parse and return the Treesitter query for Go error handling patterns
--- @return vim.treesitter.Query|nil query The parsed query or nil if parsing fails
function M.get_error_query()
	local has_parser = pcall(vim.treesitter.language.inspect, "go")

	local ok, query = pcall(vim.treesitter.query.parse, "go", queries.error_query)
	if not ok then
		if not has_parser then
			vim.notify("no-go.nvim: Go parser not found. Install it with :TSInstall go", vim.log.levels.ERROR)
		else
			vim.notify(
				"no-go.nvim: Failed to parse error query. Try updating the parser with :TSUpdate go",
				vim.log.levels.ERROR
			)
		end
		return nil
	end
	return query
end

--- Parse and return the Treesitter query for Go import blocks
--- @return vim.treesitter.Query|nil query The parsed query or nil if parsing fails
function M.get_import_query()
	local has_parser = pcall(vim.treesitter.language.inspect, "go")

	local ok, query = pcall(vim.treesitter.query.parse, "go", queries.import_query)
	if not ok then
		if not has_parser then
			vim.notify("no-go.nvim: Go parser not found. Install it with :TSInstall go", vim.log.levels.ERROR)
		else
			vim.notify(
				"no-go.nvim: Failed to parse import query. Try updating the parser with :TSUpdate go",
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

	local brace_start_col = utils.find_opening_pair(bufnr, if_start_row, "{")
	if not brace_start_col then
		return
	end

	local brace_end_col = utils.find_closing_pair(bufnr, if_end_row, "}")
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

--- Apply virtual text and concealment to collapse an import block
--- @param bufnr number The buffer number
--- @param import_node TSNode The import statement node
--- @param collapse_node TSNode The import_spec_list node to collapse
--- @param config table The plugin configuration
function M.apply_import_collapse(bufnr, import_node, collapse_node, config)
	local import_start_row, _, import_end_row, _ = import_node:range()

	-- check if cursor is inside this block and reveal_on_cursor is enabled
	if config.reveal_on_cursor then
		local wins = vim.fn.win_findbuf(bufnr)
		for _, win in ipairs(wins) do
			local cursor = vim.api.nvim_win_get_cursor(win)
			local cursor_row = cursor[1] - 1

			if cursor_row >= import_start_row and cursor_row <= import_end_row then
				return
			end
		end
	end

	local paren_start_col = utils.find_opening_pair(bufnr, import_start_row, "(")
	if not paren_start_col then
		return
	end

	local paren_end_col = utils.find_closing_pair(bufnr, import_end_row, ")")
	if not paren_end_col then
		return
	end

	-- Conceal from ( to end of the import line
	local import_line = vim.api.nvim_buf_get_lines(bufnr, import_start_row, import_start_row + 1, false)[1]
	if import_line then
		vim.api.nvim_buf_set_extmark(bufnr, M.namespace, import_start_row, paren_start_col, {
			end_row = import_start_row,
			end_col = #import_line,
			conceal = "",
		})
	end

	-- hide all intermediate lines
	if import_end_row > import_start_row then
		vim.api.nvim_buf_set_extmark(bufnr, M.namespace, import_start_row + 1, 0, {
			end_row = import_end_row,
			end_col = 0,
			conceal_lines = "",
		})
	end

	-- Count import packages
	local import_count = 0
	for child in collapse_node:iter_children() do
		if child:type() == "import_spec" then
			import_count = import_count + 1
		end
	end

	local virtual_text_string = config.import_virtual_text.prefix .. import_count .. config.import_virtual_text.suffix
	vim.api.nvim_buf_set_extmark(bufnr, M.namespace, import_start_row, paren_start_col, {
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

	local error_query = M.get_error_query()
	if not error_query then
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

	-- iterate err query matches
	for id, node, _ in error_query:iter_captures(root, bufnr, 0, -1) do
		local capture_name = error_query.captures[id]

		if capture_name == "if_statement" then -- checking capture group
			local err_identifier_node = nil
			local collapse_block_node = nil
			local return_identifier_node = nil

			-- gets the nodes we need to make the virtual text, and what we will collapse
			for child_id, child_node, _ in error_query:iter_captures(node, bufnr, 0, -1) do
				local child_capture_name = error_query.captures[child_id]

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

	-- iterate import query matches, if enabled
	if config.fold_imports then
		local import_query = M.get_import_query()
		if import_query then
			for id, node, _ in import_query:iter_captures(root, bufnr, 0, -1) do
				local capture_name = import_query.captures[id]

				if capture_name == "import_statement" then
					local collapse_block_node = nil

					for child_id, child_node, _ in import_query:iter_captures(node, bufnr, 0, -1) do
						local child_capture_name = import_query.captures[child_id]

						if child_capture_name == "collapse_block" then
							collapse_block_node = child_node
						end
					end

					if collapse_block_node then
						M.apply_import_collapse(bufnr, node, collapse_block_node, config)
					end
				end
			end
		end
	end
end

return M
