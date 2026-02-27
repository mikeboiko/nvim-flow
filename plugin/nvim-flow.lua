if vim.g.nvim_flow_loaded then
	return
end
vim.g.nvim_flow_loaded = true

local flow = require("nvim-flow")

vim.api.nvim_create_user_command("FlowRun", function()
	flow.run()
end, {})

vim.api.nvim_create_user_command("FlowDebug", function()
	flow.debug()
end, {})

vim.api.nvim_create_user_command("FlowToggleLock", function(opts)
	flow.toggle_lock(opts.args)
end, { nargs = "?" })

vim.api.nvim_create_user_command("FlowSet", function(opts)
	flow.toggle_lock(opts.args)
end, { nargs = 1, complete = "file" })

vim.api.nvim_create_user_command("FlowPreview", function()
	flow.preview()
end, {})

vim.api.nvim_create_user_command("FlowQuickfix", function()
	flow.quickfix()
end, {})
