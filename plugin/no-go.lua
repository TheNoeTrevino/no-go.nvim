if vim.g.loaded_no_go then
	return
end
vim.g.loaded_no_go = true

vim.api.nvim_create_user_command("NoGoRefresh", function()
	require("no-go").refresh()
end, { desc = "Refresh no-go error collapsing" })

vim.api.nvim_create_user_command("NoGoToggle", function()
	require("no-go").toggle_buffer()
end, { desc = "Toggle no-go error collapsing for current buffer" })

vim.api.nvim_create_user_command("NoGoEnable", function()
	require("no-go").enable_buffer()
end, { desc = "Enable no-go error collapsing for current buffer" })

vim.api.nvim_create_user_command("NoGoDisable", function()
	require("no-go").disable_buffer()
end, { desc = "Disable no-go error collapsing for current buffer" })
