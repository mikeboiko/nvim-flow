local path = require("nvim-flow.path")

describe("nvim-flow path helpers", function()
	local root = nil

	before_each(function()
		root = vim.fn.tempname()
		vim.fn.mkdir(root, "p")
	end)

	after_each(function()
		if root then
			vim.fn.delete(root, "rf")
		end
	end)

	it("detects repo root even when vim.fs.root is unavailable", function()
		local repo = root .. "/my-repo"
		local src = repo .. "/src"
		local file = src .. "/main.py"
		vim.fn.mkdir(repo .. "/.git", "p")
		vim.fn.mkdir(src, "p")
		local fh = assert(io.open(file, "w"))
		fh:write("print('x')\n")
		fh:close()

		local original_root = vim.fs.root
		vim.fs.root = nil
		local ok, detected = pcall(path.detect_repo_name, file)
		vim.fs.root = original_root

		assert.is_true(ok)
		assert.are.equal("my-repo", detected)
	end)
end)
