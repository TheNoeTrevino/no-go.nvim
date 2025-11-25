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

-- Track reveal_on_cursor state (separate from general enabled state)
M.reveal_on_cursor_globally_enabled = true
M.reveal_on_cursor_disabled_buffers = {}
M.reveal_on_cursor_enabled_buffers = {}
M.cursor_autocmd_id = nil

--- Determine if reveal_on_cursor should be active for a buffer
--- @param bufnr number The buffer number
--- @return boolean True if reveal_on_cursor should be active
local function is_reveal_on_cursor_active(bufnr)
	-- Buffer disable takes highest priority
	if M.reveal_on_cursor_disabled_buffers[bufnr] then
		return false
	end

	-- Global enabled state
	if M.reveal_on_cursor_globally_enabled then
		return true
	end

	-- Buffer explicitly enabled overrides global disable
	if M.reveal_on_cursor_enabled_buffers[bufnr] then
		return true
	end

	return false
end

--- Remove smart navigation keymaps from a buffer
--- @param bufnr number The buffer number
--- @param opts table The plugin configuration
local function teardown_keymaps(bufnr, opts)
	if not M.keymap_buffers[bufnr] then
		return
	end

	if opts.keys and opts.keys.down then
		pcall(vim.keymap.del, { "n", "x", "o" }, opts.keys.down, { buffer = bufnr })
	end

	if opts.keys and opts.keys.up then
		pcall(vim.keymap.del, { "n", "x", "o" }, opts.keys.up, { buffer = bufnr })
	end

	M.keymap_buffers[bufnr] = nil
end

--- these keymaps skip over concealed lines using direct cursor movement
--- only set up when reveal_on_cursor is false!
--- @param bufnr number The buffer number
--- @param opts table The plugin configuration
local function setup_keymaps(bufnr, opts)
	if M.keymap_buffers[bufnr] then
		return
	end

	-- only set smart keymaps when reveal_on_cursor is disabled
	if is_reveal_on_cursor_active(bufnr) then
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

--- Setup CursorMoved autocmds for reveal_on_cursor feature
--- @param opts table The plugin configuration
local function setup_cursor_autocmds(opts)
	-- Don't create if already exists
	if M.cursor_autocmd_id then
		return
	end

	M.cursor_autocmd_id = vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
		group = M.augroup,
		pattern = "*.go",
		callback = function(args)
			-- Skip if buffer has reveal_on_cursor disabled
			if not is_reveal_on_cursor_active(args.buf) then
				return
			end

			-- Skip if plugin is disabled for this buffer
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
					if M.is_globally_enabled or M.enabled_buffers[args.buf] then
						fold.process_buffer(args.buf, opts, is_reveal_on_cursor_active(args.buf))
					end
				end
			end, 10)
		end,
	})
end

--- Remove CursorMoved autocmds for reveal_on_cursor feature if no longer needed
local function teardown_cursor_autocmds_if_unused()
	-- Keep autocmds if globally enabled
	if M.reveal_on_cursor_globally_enabled then
		return
	end

	-- Keep autocmds if any buffer is explicitly enabled
	for _ in pairs(M.reveal_on_cursor_enabled_buffers) do
		return
	end

	-- No buffers need cursor autocmds, safe to remove
	if M.cursor_autocmd_id then
		vim.api.nvim_del_autocmd(M.cursor_autocmd_id)
		M.cursor_autocmd_id = nil
	end
end

--- Setup the plugin with user configuration
--- @param user_config table|nil Optional user configuration to override defaults
function M.setup(user_config)
	-- Setup configuration
	local opts = config.setup(user_config)

	-- Set global enabled state from config
	M.is_globally_enabled = opts.enabled

	-- Set reveal_on_cursor enabled state from config
	M.reveal_on_cursor_globally_enabled = opts.reveal_on_cursor

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
						fold.process_buffer(args.buf, opts, is_reveal_on_cursor_active(args.buf))
					end
				end
			end, 10)
		end,
	})

	-- Setup CursorMoved autocmd for reveal_on_cursor feature
	if opts.reveal_on_cursor then
		setup_cursor_autocmds(opts)
	end

	-- Cleanup tracking tables when buffers are deleted
	vim.api.nvim_create_autocmd("BufDelete", {
		group = M.augroup,
		callback = function(args)
			M.disabled_buffers[args.buf] = nil
			M.enabled_buffers[args.buf] = nil
			M.reveal_on_cursor_disabled_buffers[args.buf] = nil
			M.reveal_on_cursor_enabled_buffers[args.buf] = nil
			M.keymap_buffers[args.buf] = nil
		end,
	})

	-- Process current buffer if it's a Go file and globally enabled
	if M.is_globally_enabled then
		local current_buf = vim.api.nvim_get_current_buf()
		local ft = vim.api.nvim_get_option_value("filetype", { buf = current_buf })
		if ft == "go" then
			setup_keymaps(current_buf, opts)
			fold.process_buffer(current_buf, opts, is_reveal_on_cursor_active(current_buf))
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
	fold.process_buffer(bufnr, config.options, is_reveal_on_cursor_active(bufnr))
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
				fold.process_buffer(bufnr, config.options, is_reveal_on_cursor_active(bufnr))
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

-- REVEAL_ON_CURSOR GLOBAL COMMANDS (affect all buffers)

--- Disable reveal_on_cursor globally (all Go buffers)
function M.disable_reveal_on_cursor()
	if not M.initialized then
		return
	end

	-- Set global state to disabled
	M.reveal_on_cursor_globally_enabled = false

	-- Clear explicitly enabled buffers (global disable overrides all)
	M.reveal_on_cursor_enabled_buffers = {}

	-- Remove cursor autocmds if no longer needed
	teardown_cursor_autocmds_if_unused()

	vim.notify("no-go.nvim: reveal_on_cursor disabled globally", vim.log.levels.INFO)

	-- Set up smart keymaps for all Go buffers
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
			local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
			if ft == "go" then
				setup_keymaps(bufnr, config.options)
			end
		end
	end

	-- Refresh all visible Go buffers to reprocess with new state
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
			local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
			if ft == "go" and not M.disabled_buffers[bufnr] then
				if M.is_globally_enabled or M.enabled_buffers[bufnr] then
					fold.process_buffer(bufnr, config.options, is_reveal_on_cursor_active(bufnr))
				end
			end
		end
	end
end

--- Enable reveal_on_cursor globally (all Go buffers)
function M.enable_reveal_on_cursor()
	if not M.initialized then
		vim.notify("no-go.nvim: Plugin not initialized. Call setup() first.", vim.log.levels.WARN)
		return
	end

	-- Set global state to enabled
	M.reveal_on_cursor_globally_enabled = true

	-- Setup cursor autocmds
	setup_cursor_autocmds(config.options)

	vim.notify("no-go.nvim: reveal_on_cursor enabled globally", vim.log.levels.INFO)

	-- Teardown smart keymaps from all Go buffers
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
			local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
			if ft == "go" then
				teardown_keymaps(bufnr, config.options)
			end
		end
	end

	-- Refresh all visible Go buffers to reprocess with new state
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
			local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
			if ft == "go" and not M.disabled_buffers[bufnr] then
				if M.is_globally_enabled or M.enabled_buffers[bufnr] then
					fold.process_buffer(bufnr, config.options, is_reveal_on_cursor_active(bufnr))
				end
			end
		end
	end
end

--- Toggle reveal_on_cursor globally (all Go buffers)
function M.toggle_reveal_on_cursor()
	if not M.initialized then
		vim.notify("no-go.nvim: Plugin not initialized. Call setup() first.", vim.log.levels.WARN)
		return
	end

	-- Toggle global state
	if M.reveal_on_cursor_globally_enabled then
		M.disable_reveal_on_cursor()
	else
		M.enable_reveal_on_cursor()
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

	fold.process_buffer(bufnr, config.options, is_reveal_on_cursor_active(bufnr))
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

-- REVEAL_ON_CURSOR BUFFER-SPECIFIC COMMANDS (affect only current buffer)

--- Disable reveal_on_cursor for current buffer only
function M.disable_reveal_on_cursor_buffer()
	if not M.initialized then
		return
	end

	local bufnr = vim.api.nvim_get_current_buf()

	-- Mark buffer as having reveal_on_cursor disabled
	M.reveal_on_cursor_disabled_buffers[bufnr] = true

	-- Remove from explicitly enabled buffers
	M.reveal_on_cursor_enabled_buffers[bufnr] = nil

	-- Setup smart keymaps for this buffer
	setup_keymaps(bufnr, config.options)

	vim.notify("no-go.nvim: reveal_on_cursor disabled for current buffer", vim.log.levels.INFO)

	-- Refresh buffer to reprocess with new state
	if not M.disabled_buffers[bufnr] then
		if M.is_globally_enabled or M.enabled_buffers[bufnr] then
			fold.process_buffer(bufnr, config.options, is_reveal_on_cursor_active(bufnr))
		end
	end
end

--- Enable reveal_on_cursor for current buffer only
function M.enable_reveal_on_cursor_buffer()
	if not M.initialized then
		vim.notify("no-go.nvim: Plugin not initialized. Call setup() first.", vim.log.levels.WARN)
		return
	end

	local bufnr = vim.api.nvim_get_current_buf()

	-- Remove buffer from disabled list
	M.reveal_on_cursor_disabled_buffers[bufnr] = nil

	-- If globally disabled, add to explicitly enabled buffers
	if not M.reveal_on_cursor_globally_enabled then
		M.reveal_on_cursor_enabled_buffers[bufnr] = true

		-- Ensure cursor autocmds exist (needed if this is the first buffer to enable)
		setup_cursor_autocmds(config.options)
	end

	-- Teardown smart keymaps for this buffer
	teardown_keymaps(bufnr, config.options)

	vim.notify("no-go.nvim: reveal_on_cursor enabled for current buffer", vim.log.levels.INFO)

	-- Refresh buffer to reprocess with new state
	if not M.disabled_buffers[bufnr] then
		if M.is_globally_enabled or M.enabled_buffers[bufnr] then
			fold.process_buffer(bufnr, config.options, is_reveal_on_cursor_active(bufnr))
		end
	end
end

--- Toggle reveal_on_cursor for current buffer only
function M.toggle_reveal_on_cursor_buffer()
	if not M.initialized then
		vim.notify("no-go.nvim: Plugin not initialized. Call setup() first.", vim.log.levels.WARN)
		return
	end

	local bufnr = vim.api.nvim_get_current_buf()

	-- Check if buffer has reveal_on_cursor disabled
	if M.reveal_on_cursor_disabled_buffers[bufnr] then
		M.enable_reveal_on_cursor_buffer()
	else
		M.disable_reveal_on_cursor_buffer()
	end
end

return M
