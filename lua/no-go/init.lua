local M = {}

local config = require("no-go.config")
local fold = require("no-go.fold")

-- Track plugin initialization
M.initialized = false

-- Autocmd group
M.augroup = nil

-- Track buffers where the plugin is disabled
M.disabled_buffers = {}

-- Setup the plugin
function M.setup(user_config)
	-- merge default and user config
	local opts = config.setup(user_config)

	-- TODO: this is a placeholder. We need to initialize, but disable through hierarchy
	if not opts.enabled then
		return
	end

	M.augroup = vim.api.nvim_create_augroup("NoGo", { clear = true })

	vim.api.nvim_create_autocmd(opts.update_events, {
		group = M.augroup,
		pattern = "*.go",
		callback = function(args)
			if M.disabled_buffers[args.buf] then
				return
			end

			-- dont spam too much
			vim.defer_fn(function()
				if vim.api.nvim_buf_is_valid(args.buf) and not M.disabled_buffers[args.buf] then
					fold.process_buffer(args.buf, opts)
				end
			end, 20)
		end,
	})

	-- CursorMoved autocmd for reveal_on_cursor feature
	if opts.reveal_on_cursor then
		vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
			group = M.augroup,
			pattern = "*.go",
			callback = function(args)
				-- Skip if buffer is disabled
				if M.disabled_buffers[args.buf] then
					return
				end

				-- dont spam too much
				vim.defer_fn(function()
					if vim.api.nvim_buf_is_valid(args.buf) and not M.disabled_buffers[args.buf] then
						fold.process_buffer(args.buf, opts)
					end
				end, 20)
			end,
		})
	end

	-- Process current buffer if .go
	local current_buf = vim.api.nvim_get_current_buf()
	local ft = vim.api.nvim_get_option_value("filetype", { buf = current_buf })
	if ft == "go" then
		fold.process_buffer(current_buf, opts)
	end

	M.initialized = true
end

-- Manually refresh the current buffer
function M.refresh()
	if not M.initialized then
		-- TODO: change when the hierarchy is implemented
		vim.notify("no-go.nvim: Plugin not initialized. Call setup() first.", vim.log.levels.WARN)
		return
	end

	local bufnr = vim.api.nvim_get_current_buf()
	fold.process_buffer(bufnr, config.options)
end

-- Disable the plugin for current buffer
function M.disable_buffer()
	local bufnr = vim.api.nvim_get_current_buf()

	M.disabled_buffers[bufnr] = true

	fold.clear_extmarks(bufnr)
end

-- Enable the plugin for current buffer
function M.enable_buffer()
	if not M.initialized then
		-- TODO: change when the hierarchy is implemented
		vim.notify("no-go.nvim: Plugin not initialized. Call setup() first.", vim.log.levels.WARN)
		return
	end

	local bufnr = vim.api.nvim_get_current_buf()

	-- Remove from disabled buffers
	M.disabled_buffers[bufnr] = nil

	M.refresh()
end

-- Toggle the plugin for current buffer
function M.toggle_buffer()
	if not M.initialized then
		-- TODO: change when the hierarchy is implemented
		vim.notify("no-go.nvim: Plugin not initialized. Call setup() first.", vim.log.levels.WARN)
		return
	end

	local bufnr = vim.api.nvim_get_current_buf()

	if M.disabled_buffers[bufnr] then
		M.enable_buffer()
	else
		M.disable_buffer()
	end
end

return M
