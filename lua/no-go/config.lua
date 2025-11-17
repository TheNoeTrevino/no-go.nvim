local M = {}

M.defaults = {
	-- enable the plugin by default
	enabled = true,

	-- identifiers to match in if statements (e.g., "if err != nil", "if error != nil")
	identifiers = { "err" },

	-- virtual text structure for a collapsed error handling block
	-- format: prefix + [content + content_separator] + return_character + suffix
	virtual_text = {
		prefix = " ", -- What comes before the content
		content_separator = " ", -- Space between content and return character (only used if content exists)
		return_character = "󱞿 ", -- The icon/character showing it's a return
		suffix = "", -- What comes at the end
	},

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

	-- key mappings to skip over concealed lines. can be a string or a table of strings
	keymaps = {
		move_down = "j",
		move_up = "k",
	},

	-- reveal concealed lines when cursor is on the if err != nil line,
	-- allows you to inspect the error handling by hovering over the collapsed line
	reveal_on_cursor = true,
}

-- current configuration (will be merged with user config)
M.options = {}

function M.setup(user_config)
	M.options = vim.tbl_deep_extend("force", M.defaults, user_config or {})
	M.setup_highlight()

	return M.options
end

function M.setup_highlight()
	local hl = M.options.highlight
	local hl_def = {}

	if hl.bg then
		hl_def.bg = hl.bg
	end

	if hl.fg then
		hl_def.fg = hl.fg
	end

	-- only set if not already defined by user's colorscheme
	vim.api.nvim_set_hl(0, M.options.highlight_group, hl_def)
end

return M
