local debug_runner = require("nvim-flow.debug_runner")

describe("nvim-flow debug runner", function()
	local original_dap = nil

	before_each(function()
		original_dap = package.loaded.dap
		package.loaded.dap = {
			configurations = {},
			continue = function() end,
		}
	end)

	after_each(function()
		package.loaded.dap = original_dap
	end)

	it("builds python program launch config from flow command", function()
		local ok = debug_runner.run({
			cmd = "#!/usr/bin/env bash\npython /tmp/example.py --name value",
			filepath = "/tmp/example.py",
		})

		assert.is_true(ok)
		local cfg = package.loaded.dap.configurations[vim.bo.filetype][1]
		assert.are.equal("python", cfg.type)
		assert.are.equal("/tmp/example.py", cfg.program)
		assert.are.same({ "--name", "value" }, cfg.args)
	end)

	it("builds python module launch config for uv run -m", function()
		local ok = debug_runner.run({
			cmd = "#!/usr/bin/env bash\nuv run -m app.main --foo bar",
			filepath = "/tmp/example.py",
		})

		assert.is_true(ok)
		local cfg = package.loaded.dap.configurations[vim.bo.filetype][1]
		assert.are.equal("python", cfg.type)
		assert.are.equal("app.main", cfg.module)
		assert.are.same({ "--foo", "bar" }, cfg.args)
	end)
end)
