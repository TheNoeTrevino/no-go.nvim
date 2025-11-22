local M = {}

local config = require("no-go.config")
local fold = require("no-go.fold")
local utils = require("no-go.utils")

-- Track plugin initialization
M.initialized = false

-- Autocmd group
M.augroup = nil

-- Global enabled state (controls whether folding happens at all)
M.is_globally_enabled = true

-- these vars are for tracking per buffer enabled and disabled states
M.disabled_buffers = {}

M.enabled_buffers = {}

M.keymap_buffers = {}

--- these keymaps skip over concealed lines using direct cursor movement
--- only set up when reveal_on_cursor is false!
--- @param bufnr number The buffer number
--- @param opts table The plugin configuration
local function setup_keymaps(bufnr, opts)
	if M.keymap_buffers[bufnr] then
		return
	end

	-- only set smart keymaps when reveal_on_cursor is disabled
	if opts.reveal_on_cursor then
		return
	end

	-- if user puts in false, for some reason
	if not opts.keys then
		return
	end

	local namespace = fold.namespace

	if opts.keys.down then
		vim.keymap.set({ "n", "x", "o" }, opts.keys.down, function()
			local lines = utils.smart_down_lines(vim.v.count1, namespace)
			if lines > 0 then
				local cursor = vim.api.nvim_win_get_cursor(0)
				local max_line = vim.api.nvim_buf_line_count(0)
				local new_line = math.min(cursor[1] + lines, max_line)
				vim.api.nvim_win_set_cursor(0, { new_line, cursor[2] })
			end
		end, { buffer = bufnr, desc = "Smart down (skip concealed)" })
	end

	if opts.keys.up then
		vim.keymap.set({ "n", "x", "o" }, opts.keys.up, function()
			local lines = utils.smart_up_lines(vim.v.count1, namespace)
			if lines > 0 then
				local cursor = vim.api.nvim_win_get_cursor(0)
				local new_line = math.max(cursor[1] - lines, 1)
				vim.api.nvim_win_set_cursor(0, { new_line, cursor[2] })
			end
		end, { buffer = bufnr, desc = "Smart up (skip concealed)" })
	end

	M.keymap_buffers[bufnr] = true
end

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
			setup_keymaps(args.buf, opts)

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
			setup_keymaps(current_buf, opts)
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
