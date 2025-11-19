local M = {}

-- deafults that will be merged by the user config (user priority duh)
M.defaults = {
	-- enable the plugin by default
	enabled = true,

	-- identifiers to match in if statements (e.g., "if err != nil", "if error != nil")
	identifiers = { "err" },

	-- virtual text structure for a collapsed error handling block
	-- formatted will be: prefix + content + content_separator + return_character + suffix
	virtual_text = {
		prefix = ": ",
		content_separator = " ",
		return_character = "󱞿 ",
		suffix = "",
	},

	-- virtual text for collapsed import blocks
	import_virtual_text = {
		prefix = " ",
		suffix = "  ",
	},

	-- enable import folding
	fold_imports = true,

	highlight_group = "NoGoZone",

	highlight = {
		bg = "#2A2A37",
	},

	-- auto-update on these events
	update_events = {
		"BufEnter",
		"BufWritePost",
		"TextChanged",
		"TextChangedI",
		"InsertLeave",
	},

	-- reveal concealed lines when cursor is on the if err != nil line,
	-- allows you to inspect the error handling by hovering over the collapsed line
	reveal_on_cursor = true,
}

-- current configuration (will be merged with user config)
M.options = {}

--- Setup configuration by merging user config with defaults
--- @param user_config table|nil Optional user configuration to override defaults
--- @return table The merged configuration options
function M.setup(user_config)
	M.options = vim.tbl_deep_extend("force", M.defaults, user_config or {})
	M.setup_highlight()

	return M.options
end

--- Setup the NoGoZone highlight group
function M.setup_highlight()
	-- dont override users highlight group
	if M.options.highlight_group ~= "NoGoZone" then
		return
	end

	local hl = M.options.highlight
	local hl_def = {}

	if hl.bg then
		hl_def.bg = hl.bg
	end

	if hl.fg then
		hl_def.fg = hl.fg
	end

	vim.api.nvim_set_hl(0, M.options.highlight_group, hl_def)
end

return M
