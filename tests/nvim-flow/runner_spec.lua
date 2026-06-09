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

	-- buffer output_mode tests

	it("buffer mode opens a split without replacing the source buffer", function()
		vim.cmd("edit " .. vim.fn.fnameescape(target))
		local source_buf = vim.api.nvim_get_current_buf()

		local ok, err = runner.run({
			cmd = "#!/usr/bin/env bash\necho buffer-test",
			filepath = target,
			runner = "terminal",
		}, {
			output_mode = "buffer",
			terminal_height = 5,
			show_command = false,
		})

		assert.is_true(ok, err)
		assert.are.equal(source_buf, vim.api.nvim_get_current_buf())
		assert.are.equal(1, vim.b[runner.last_terminal_buf].nvim_flow_terminal)
	end)

	it("buffer mode respects terminal_position top and bottom", function()
		vim.cmd("edit " .. vim.fn.fnameescape(target))
		local source_win = vim.api.nvim_get_current_win()

		local ok_top = runner.run({
			cmd = "#!/usr/bin/env bash\necho top",
			filepath = target,
			runner = "terminal",
		}, {
			output_mode = "buffer",
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
			output_mode = "buffer",
			terminal_height = 5,
			terminal_position = "bottom",
			show_command = false,
		})
		assert.is_true(ok_bottom)

		local bottom_row = vim.fn.win_screenpos(runner.last_terminal_win)[1]
		source_row = vim.fn.win_screenpos(source_win)[1]
		assert.is_true(bottom_row > source_row)
	end)

	it("buffer mode sets wrapped scratch-buffer options", function()
		vim.cmd("edit " .. vim.fn.fnameescape(target))

		local ok = runner.run({
			cmd = "#!/usr/bin/env bash\necho opts-test",
			filepath = target,
			runner = "terminal",
		}, {
			output_mode = "buffer",
			terminal_height = 5,
			show_command = false,
		})
		assert.is_true(ok)

		local buf = runner.last_terminal_buf
		local win = runner.last_terminal_win
		assert.are.equal("nofile", vim.bo[buf].buftype)
		assert.are.equal(false, vim.bo[buf].swapfile)
		assert.are.equal(true, vim.wo[win].wrap)
		assert.are.equal(true, vim.wo[win].linebreak)
		assert.are.equal(false, vim.wo[win].number)
		assert.are.equal(false, vim.wo[win].relativenumber)
		assert.are.equal("no", vim.wo[win].signcolumn)
	end)

	it("buffer mode stores output in runner.last_output_lines", function()
		vim.cmd("edit " .. vim.fn.fnameescape(target))

		local ok = runner.run({
			cmd = "#!/usr/bin/env bash\necho hello-flow",
			filepath = target,
			runner = "terminal",
		}, {
			output_mode = "buffer",
			terminal_height = 5,
			show_command = false,
		})
		assert.is_true(ok)

		-- Wait for the async job to finish
		vim.wait(5000, function()
			return #runner.last_output_lines > 0
		end, 50)

		local found = false
		for _, line in ipairs(runner.last_output_lines) do
			if line:find("hello-flow", 1, true) then
				found = true
				break
			end
			assert.is_falsy(line:find("%[Process exited %d+%]"))
		end
		assert.is_true(found, "expected 'hello-flow' in output lines")
		assert.are.equal("flow://run", vim.api.nvim_buf_get_name(runner.last_terminal_buf))
	end)

	it("buffer mode streams output before the job exits", function()
		vim.cmd("edit " .. vim.fn.fnameescape(target))

		local ok = runner.run({
			cmd = "#!/usr/bin/env bash\nprintf 'first\\n'; sleep 1; printf 'second\\n'",
			filepath = target,
			runner = "terminal",
		}, {
			output_mode = "buffer",
			terminal_height = 5,
			show_command = false,
		})
		assert.is_true(ok)

		local saw_first = vim.wait(1500, function()
			return #runner.last_output_lines == 1 and runner.last_output_lines[1] == "first"
		end, 20)
		assert.is_true(saw_first, "expected first line before process exit")

		local saw_second = vim.wait(5000, function()
			return #runner.last_output_lines >= 2 and runner.last_output_lines[2] == "second"
		end, 20)
		assert.is_true(saw_second, "expected second line after streaming completes")
	end)

	it("buffer mode ctrl+c interrupts the running job", function()
		vim.cmd("edit " .. vim.fn.fnameescape(target))

		local ok = runner.run({
			cmd = "#!/usr/bin/env bash\nprintf 'first\\n'; sleep 5; printf 'second\\n'",
			filepath = target,
			runner = "terminal",
		}, {
			output_mode = "buffer",
			terminal_height = 5,
			show_command = false,
		})
		assert.is_true(ok)

		local saw_first = vim.wait(1500, function()
			return #runner.last_output_lines == 1 and runner.last_output_lines[1] == "first"
		end, 20)
		assert.is_true(saw_first, "expected first line before interrupt")

		local keymaps = vim.api.nvim_buf_get_keymap(runner.last_terminal_buf, "n")
		local has_interrupt_map = false
		for _, keymap in ipairs(keymaps) do
			if keymap.lhs == "<C-C>" or keymap.lhs == "<C-c>" then
				has_interrupt_map = true
				break
			end
		end
		assert.is_true(has_interrupt_map, "expected buffer-local <C-c> mapping")
		assert.is_true(runner.interrupt_buffer_job(runner.last_terminal_buf))

		local interrupted = vim.wait(5000, function()
			local name = vim.api.nvim_buf_get_name(runner.last_terminal_buf)
			return name:match("^flow://run %(%d+%)$") ~= nil
		end, 20)
		assert.is_true(interrupted, "expected interrupt to stop the running job")

		local lines = runner.get_last_output()
		assert.are.equal("first", lines[1])
		for _, line in ipairs(lines) do
			assert.is_not.equal("second", line)
		end
		assert.is_false(runner.interrupt_buffer_job(runner.last_terminal_buf))
	end)

	it("show_command in buffer mode strips shebang and adds Lua-generated separator", function()
		local header = runner._build_buffer_header_for_test("#!/usr/bin/env bash\npython /tmp/test.py --verbose")
		assert.are.equal("python /tmp/test.py --verbose", header[1])
		-- separator should be dashes matching command width
		local expected_width = vim.fn.strdisplaywidth("python /tmp/test.py --verbose")
		assert.are.equal(string.rep("-", expected_width), header[2])
		-- should NOT contain shebang
		for _, line in ipairs(header) do
			assert.is_falsy(line:find("^#!"))
		end
	end)

	it("buffer mode nonzero exit renames the buffer and keeps output visible", function()
		vim.cmd("edit " .. vim.fn.fnameescape(target))

		local ok = runner.run({
			cmd = "#!/usr/bin/env bash\necho failing && exit 42",
			filepath = target,
			runner = "terminal",
			source_key = "sh",
		}, {
			output_mode = "buffer",
			terminal_height = 5,
			show_command = false,
		})
		assert.is_true(ok)

		vim.wait(5000, function()
			return vim.api.nvim_buf_get_name(runner.last_terminal_buf) == "flow://sh (42)"
		end, 50)

		assert.are.equal("failing", runner.last_output_lines[#runner.last_output_lines])
		for _, line in ipairs(runner.last_output_lines) do
			assert.is_falsy(line:find("%[Process exited %d+%]"))
		end
		assert.are.equal("flow://sh (42)", vim.api.nvim_buf_get_name(runner.last_terminal_buf))

		-- Buffer should still be valid and visible
		assert.is_true(vim.api.nvim_buf_is_valid(runner.last_terminal_buf))
		assert.is_true(vim.api.nvim_win_is_valid(runner.last_terminal_win))
	end)

	it("buffer mode strips carriage returns from PTY output", function()
		vim.cmd("edit " .. vim.fn.fnameescape(target))

		local ok = runner.run({
			cmd = "#!/usr/bin/env bash\nprintf 'alpha\\r\\nbeta\\r\\n'",
			filepath = target,
			runner = "terminal",
		}, {
			output_mode = "buffer",
			terminal_height = 5,
			show_command = false,
		})
		assert.is_true(ok)

		vim.wait(5000, function()
			return #runner.last_output_lines > 0
		end, 50)

		assert.are.equal("alpha", runner.last_output_lines[1])
		assert.are.equal("beta", runner.last_output_lines[2])
		assert.is_falsy(runner.last_output_lines[1]:find("\r", 1, true))
		assert.is_falsy(runner.last_output_lines[2]:find("\r", 1, true))
	end)

	it("buffer mode strips cursor-control sequences from progress-style output", function()
		vim.cmd("edit " .. vim.fn.fnameescape(target))

		local ok = runner.run({
			cmd = "#!/usr/bin/env bash\nprintf '\\033[2Kbuilding\\n\\033[2K\\033[1A\\033[32mbuilt\\033[0m\\n'",
			filepath = target,
			runner = "terminal",
		}, {
			output_mode = "buffer",
			terminal_height = 5,
			show_command = false,
		})
		assert.is_true(ok)

		vim.wait(5000, function()
			return #runner.last_output_lines >= 2
		end, 50)

		assert.are.equal("building", runner.last_output_lines[1])
		assert.are.equal("built", runner.last_output_lines[2])
		for _, line in ipairs(runner.last_output_lines) do
			assert.is_falsy(line:find("[2K", 1, true))
			assert.is_falsy(line:find("[1A", 1, true))
		end
	end)
end)
