local M = {}

local config = require("no-go.config")
local fold = require("no-go.fold")

-- Track plugin initialization
M.initialized = false

-- Autocmd group
M.augroup = nil

-- Global enabled state (controls whether folding happens at all)
M.is_globally_enabled = true

-- Track buffers where the plugin is explicitly disabled
M.disabled_buffers = {}

-- Track buffers where the plugin is explicitly enabled (overrides global disabled state)
M.enabled_buffers = {}

--- Setup the plugin with user configuration
--- @param user_config table|nil Optional user configuration to override defaults
function M.setup(user_config)
	-- Setup configuration
	local opts = config.setup(user_config)

	-- Set global enabled state from config
	M.is_globally_enabled = opts.enabled

	-- Create autocmd group
	M.augroup = vim.api.nvim_create_augroup("NoGo", { clear = true })

	-- Setup autocmds for auto-updating
	vim.api.nvim_create_autocmd(opts.update_events, {
		group = M.augroup,
		pattern = "*.go",
		callback = function(args)
			if M.disabled_buffers[args.buf] then
				return
			end

			-- Skip if globally disabled AND buffer is not explicitly enabled
			if not M.is_globally_enabled and not M.enabled_buffers[args.buf] then
				return
			end

			-- Debounce updates slightly to avoid excessive processing
			vim.defer_fn(function()
				if vim.api.nvim_buf_is_valid(args.buf) and not M.disabled_buffers[args.buf] then
					-- Process if globally enabled OR buffer is explicitly enabled
					if M.is_globally_enabled or M.enabled_buffers[args.buf] then
						fold.process_buffer(args.buf, opts)
					end
				end
			end, 10)
		end,
	})

	-- Setup CursorMoved autocmd for reveal_on_cursor feature
	if opts.reveal_on_cursor then
		vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
			group = M.augroup,
			pattern = "*.go",
			callback = function(args)
				-- Skip if buffer is explicitly disabled
				if M.disabled_buffers[args.buf] then
					return
				end

				-- Skip if globally disabled AND buffer is not explicitly enabled
				if not M.is_globally_enabled and not M.enabled_buffers[args.buf] then
					return
				end

				-- Debounce cursor movements to avoid excessive processing
				vim.defer_fn(function()
					if vim.api.nvim_buf_is_valid(args.buf) and not M.disabled_buffers[args.buf] then
						-- Process if globally enabled OR buffer is explicitly enabled
						if M.is_globally_enabled or M.enabled_buffers[args.buf] then
							fold.process_buffer(args.buf, opts)
						end
					end
				end, 10)
			end,
		})
	end

	-- Process current buffer if it's a Go file and globally enabled
	if M.is_globally_enabled then
		local current_buf = vim.api.nvim_get_current_buf()
		local ft = vim.api.nvim_get_option_value("filetype", { buf = current_buf })
		if ft == "go" then
			fold.process_buffer(current_buf, opts)
		end
	end

	M.initialized = true
end

--- Manually refresh the current buffer
function M.refresh()
	if not M.initialized then
		vim.notify("no-go.nvim: Plugin not initialized. Call setup() first.", vim.log.levels.WARN)
		return
	end

	local bufnr = vim.api.nvim_get_current_buf()
	fold.process_buffer(bufnr, config.options)
end

-- GLOBAL COMMANDS (affect all buffers)

--- Disable the plugin globally (all Go buffers)
function M.disable()
	if not M.initialized then
		return
	end

	-- Set global state to disabled
	M.is_globally_enabled = false

	-- Clear explicitly enabled buffers (global disable overrides all)
	M.enabled_buffers = {}

	-- Clear extmarks from all Go buffers
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
			if ft == "go" then
				fold.clear_extmarks(bufnr)
			end
		end
	end
end

--- Enable the plugin globally (all Go buffers)
function M.enable()
	if not M.initialized then
		vim.notify("no-go.nvim: Plugin not initialized. Call setup() first.", vim.log.levels.WARN)
		return
	end

	-- Set global state to enabled
	M.is_globally_enabled = true

	-- Refresh all visible Go buffers (excluding per-buffer disabled ones)
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
			local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
			if ft == "go" and not M.disabled_buffers[bufnr] then
				fold.process_buffer(bufnr, config.options)
			end
		end
	end
end

--- Toggle the plugin globally (all Go buffers)
function M.toggle()
	if not M.initialized then
		vim.notify("no-go.nvim: Plugin not initialized. Call setup() first.", vim.log.levels.WARN)
		return
	end

	-- Toggle global state
	if M.is_globally_enabled then
		M.disable()
	else
		M.enable()
	end
end

-- BUFFER-SPECIFIC COMMANDS (affect only current buffer)

--- Disable the plugin for current buffer only
function M.disable_buffer()
	if not M.initialized then
		return
	end

	local bufnr = vim.api.nvim_get_current_buf()

	-- Mark buffer as disabled
	M.disabled_buffers[bufnr] = true

	-- Remove from explicitly enabled buffers
	M.enabled_buffers[bufnr] = nil

	-- Clear extmarks for this buffer
	fold.clear_extmarks(bufnr)
end

--- Enable the plugin for current buffer only
function M.enable_buffer()
	if not M.initialized then
		vim.notify("no-go.nvim: Plugin not initialized. Call setup() first.", vim.log.levels.WARN)
		return
	end

	local bufnr = vim.api.nvim_get_current_buf()

	-- Remove buffer from disabled list
	M.disabled_buffers[bufnr] = nil

	-- If globally disabled, add to explicitly enabled buffers
	if not M.is_globally_enabled then
		M.enabled_buffers[bufnr] = true
	end

	fold.process_buffer(bufnr, config.options)
end

--- Toggle the plugin for current buffer only
function M.toggle_buffer()
	if not M.initialized then
		vim.notify("no-go.nvim: Plugin not initialized. Call setup() first.", vim.log.levels.WARN)
		return
	end

	local bufnr = vim.api.nvim_get_current_buf()
	-- Check if buffer is currently disabled
	if M.disabled_buffers[bufnr] then
		M.enable_buffer()
	else
		M.disable_buffer()
	end
end

return M
