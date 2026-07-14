local flow = require("nvim-flow")
local runner = require("nvim-flow.runner")

describe("nvim-flow run_here integration", function()
	local root = nil

	before_each(function()
		root = vim.fn.tempname()
		vim.fn.mkdir(root, "p")
		runner.last_cmd_def = nil
		runner.last_command = nil
		flow.setup({ output_mode = "buffer", show_command = false, terminal_height = 5 })
	end)

	after_each(function()
		vim.cmd("silent! only")
		vim.cmd("silent! %bwipeout!")
		if root then
			vim.fn.delete(root, "rf")
		end
	end)

	it("runs the entry under the cursor from a .flow.yml buffer", function()
		local flow_file = root .. "/proj/.flow.yml"
		vim.fn.mkdir(root .. "/proj", "p")
		local fh = assert(io.open(flow_file, "w"))
		fh:write("first:\n  cmd: echo one\n\nsecond:\n  cmd: echo two\n")
		fh:close()

		vim.cmd("edit " .. vim.fn.fnameescape(flow_file))
		vim.api.nvim_win_set_cursor(0, { 5, 0 }) -- inside `second`

		flow.run_here()

		assert.is_not_nil(runner.last_cmd_def)
		assert.are.equal("second", runner.last_cmd_def.source_key)
		assert.is_true(runner.last_command:find("echo two", 1, true) ~= nil)
	end)

	it("does not run when the buffer is not a flow config file", function()
		local other = root .. "/notes.txt"
		local fh = assert(io.open(other, "w"))
		fh:write("hello\n")
		fh:close()
		vim.cmd("edit " .. vim.fn.fnameescape(other))

		flow.run_here()
		assert.is_nil(runner.last_cmd_def)
	end)
end)
