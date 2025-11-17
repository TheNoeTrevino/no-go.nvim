if vim.g.loaded_no_go then
	return
end
vim.g.loaded_no_go = true

vim.api.nvim_create_user_command("NoGoEnable", function()
	require("no-go").enable()
end, { desc = "Enable no-go globally (all buffers)" })

vim.api.nvim_create_user_command("NoGoDisable", function()
	require("no-go").disable()
end, { desc = "Disable no-go globally (all buffers)" })

vim.api.nvim_create_user_command("NoGoToggle", function()
	require("no-go").toggle()
end, { desc = "Toggle no-go globally (all buffers)" })

-- Buffer-specific commands (affect only current buffer)
vim.api.nvim_create_user_command("NoGoBufEnable", function()
	require("no-go").enable_buffer()
end, { desc = "Enable no-go for current buffer only" })

vim.api.nvim_create_user_command("NoGoBufDisable", function()
	require("no-go").disable_buffer()
end, { desc = "Disable no-go for current buffer only" })

vim.api.nvim_create_user_command("NoGoBufToggle", function()
	require("no-go").toggle_buffer()
end, { desc = "Toggle no-go for current buffer only" })

vim.api.nvim_create_user_command("NoGoRefresh", function()
	require("no-go").refresh()
end, { desc = "Refresh no-go error collapsing for current buffer" })
