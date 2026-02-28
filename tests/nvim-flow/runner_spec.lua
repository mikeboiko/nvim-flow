local runner = require("nvim-flow.runner")

describe("nvim-flow runner", function()
	local root = nil
	local target = nil

	before_each(function()
		root = vim.fn.tempname()
		vim.fn.mkdir(root, "p")
		target = root .. "/example.py"
		local fh = assert(io.open(target, "w"))
		fh:write("print('hello')\n")
		fh:close()
	end)

	after_each(function()
		vim.cmd("only")
		if root then
			vim.fn.delete(root, "rf")
		end
	end)

	it("opens terminal split without replacing the source buffer", function()
		vim.cmd("edit " .. vim.fn.fnameescape(target))
		local source_buf = vim.api.nvim_get_current_buf()

		local ok, err = runner.run({
			cmd = "#!/usr/bin/env bash\necho runner-test",
			filepath = target,
			runner = "terminal",
		}, {
			terminal_height = 5,
			show_command = false,
		})

		assert.is_true(ok, err)
		assert.are.equal(source_buf, vim.api.nvim_get_current_buf())
		assert.are.equal(1, vim.b[runner.last_terminal_buf].nvim_flow_terminal)
	end)

	it("opens terminal above source by default and below when configured", function()
		vim.cmd("edit " .. vim.fn.fnameescape(target))
		local source_win = vim.api.nvim_get_current_win()

		local ok_top = runner.run({
			cmd = "#!/usr/bin/env bash\necho top",
			filepath = target,
			runner = "terminal",
		}, {
			terminal_height = 5,
			show_command = false,
		})
		assert.is_true(ok_top)

		local top_row = vim.fn.win_screenpos(runner.last_terminal_win)[1]
		local source_row = vim.fn.win_screenpos(source_win)[1]
		assert.is_true(top_row < source_row)

		vim.cmd("only")
		vim.cmd("edit " .. vim.fn.fnameescape(target))
		source_win = vim.api.nvim_get_current_win()

		local ok_bottom = runner.run({
			cmd = "#!/usr/bin/env bash\necho bottom",
			filepath = target,
			runner = "terminal",
		}, {
			terminal_height = 5,
			terminal_position = "bottom",
			show_command = false,
		})
		assert.is_true(ok_bottom)

		local bottom_row = vim.fn.win_screenpos(runner.last_terminal_win)[1]
		source_row = vim.fn.win_screenpos(source_win)[1]
		assert.is_true(bottom_row > source_row)
	end)

	it("builds separator width from command width when showing command", function()
		local cmd = "#!/usr/bin/env bash\npython /home/mike/temp/test.py"
		local script = assert(runner._build_script_for_test(cmd, true))
		local fh = assert(io.open(script, "r"))
		local text = fh:read("*a")
		fh:close()
		runner._cleanup_script_for_test(script)

		local width = text:match("__nvim_flow_sep_len=(%d+)")
		assert.are.equal(tostring(#"python /home/mike/temp/test.py"), width)
		assert.is_truthy(text:find("tput cols", 1, true))
		assert.is_false(text:find("NVIM_FLOW_CONTENT_EOF\n#!/usr/bin/env bash", 1, true) ~= nil)
	end)

	it("strips shebang from display command", function()
		local shown = runner.display_command('#!/usr/bin/env bash\nbash "/tmp/run.sh"')
		assert.are.equal('bash "/tmp/run.sh"', shown)
	end)
end)
