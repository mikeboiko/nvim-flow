local ansi = require("nvim-flow.ansi")

describe("nvim-flow ansi", function()
	it("strips basic SGR sequences", function()
		local input = "\27[31mhello\27[0m world"
		assert.are.equal("hello world", ansi.strip(input))
	end)

	it("strips multiple codes in one sequence", function()
		local input = "\27[1;4;34mtext\27[0m"
		assert.are.equal("text", ansi.strip(input))
	end)

	it("strip_lines modifies table in place", function()
		local lines = { "\27[32mgreen\27[0m", "plain", "\27[91mred\27[0m" }
		ansi.strip_lines(lines)
		assert.are.equal("green", lines[1])
		assert.are.equal("plain", lines[2])
		assert.are.equal("red", lines[3])
	end)

	it("sanitizes non-SGR terminal control sequences while preserving colors", function()
		local input = "\27[2K\27[1A\27[31mhello\27[0m"
		assert.are.equal("\27[31mhello\27[0m", ansi.sanitize(input))
		assert.are.equal("hello", ansi.strip(input))
	end)

	it("strips OSC sequences from displayed text", function()
		local input = "\27]8;;https://example.com\7link\27]8;;\7"
		assert.are.equal("link", ansi.strip(input))
	end)

	it("highlight_buffer applies extmarks for colored output", function()
		local buf = vim.api.nvim_create_buf(false, true)
		local raw_lines = { "\27[2K\27[1A\27[31mERROR\27[0m: something failed" }
		local stripped = { "ERROR: something failed" }
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, stripped)

		ansi.highlight_buffer(buf, raw_lines, 0)

		local ns = vim.api.nvim_create_namespace("nvim_flow_ansi")
		local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
		assert.is_true(#marks > 0, "expected at least one extmark")

		-- First mark should cover "ERROR" (5 chars at col 0)
		local first = marks[1]
		assert.are.equal(0, first[2]) -- row
		assert.are.equal(0, first[3]) -- col
		assert.are.equal(5, first[4].end_col)

		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("handles reset mid-line correctly", function()
		local input = "\27[32mOK\27[0m then \27[31mFAIL\27[0m"
		assert.are.equal("OK then FAIL", ansi.strip(input))
	end)
end)
