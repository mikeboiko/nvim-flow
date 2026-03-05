local config = require("nvim-flow.config")

local function write_file(path, contents)
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	local fh = assert(io.open(path, "w"))
	fh:write(contents)
	fh:close()
end

local function contains(value, needle)
	return value:find(needle, 1, true) ~= nil
end

describe("nvim-flow config resolution", function()
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

	it("merges configs from file dir to home with closer files winning", function()
		local home = root .. "/home"
		local repo = home .. "/repo"
		local src = repo .. "/src"
		local target = src .. "/main.py"

		write_file(
			home .. "/.flow.yml",
			[[
default:
  cmd: echo home-default
py:
  cmd: echo home-py {{filename}}
]]
		)

		write_file(
			repo .. "/.flow.yml",
			[[
py:
  cmd: echo repo-py {{filename}}
]]
		)

		write_file(target, "print('hello')\n")

		local cmd_def = assert(config.resolve(target, {
			config_file = ".flow.yml",
			stop_at_home = true,
			home = home,
		}))

		assert.is_true(contains(cmd_def.cmd, "echo repo-py main"))
	end)

	it("keeps legacy key matching and supports optional match arrays", function()
		local home = root .. "/home"
		local repo = home .. "/repo"
		local src = repo .. "/src"
		local py_target = src .. "/worker.py"
		local lua_target = src .. "/plugin.lua"

		write_file(
			home .. "/.flow.yml",
			[[
python-group:
  match: [py, pyw]
  cmd: echo from-match {{ext}}
lua:
  cmd: echo from-legacy {{ext}}
]]
		)

		write_file(py_target, "print('hello')\n")
		write_file(lua_target, "print('hello')\n")

		local py_cmd = assert(config.resolve(py_target, {
			config_file = ".flow.yml",
			stop_at_home = true,
			home = home,
		}))
		local lua_cmd = assert(config.resolve(lua_target, {
			config_file = ".flow.yml",
			stop_at_home = true,
			home = home,
		}))

		assert.is_true(contains(py_cmd.cmd, "echo from-match py"))
		assert.is_true(contains(lua_cmd.cmd, "echo from-legacy lua"))
	end)

	it("uses basename before match entries", function()
		local home = root .. "/home"
		local repo = home .. "/repo"
		local src = repo .. "/src"
		local target = src .. "/special.py"

		write_file(
			home .. "/.flow.yml",
			[[
python-group:
  match: [py]
  cmd: echo from-match
special.py:
  cmd: echo from-basename
]]
		)

		write_file(target, "print('hello')\n")

		local cmd_def = assert(config.resolve(target, {
			config_file = ".flow.yml",
			stop_at_home = true,
			home = home,
		}))

		assert.is_true(contains(cmd_def.cmd, "echo from-basename"))
	end)

	it("uses deterministic match order and prefers closer files", function()
		local home = root .. "/home"
		local repo = home .. "/repo"
		local src = repo .. "/src"
		local target = src .. "/worker.py"

		write_file(
			home .. "/.flow.yml",
			[[
match-first:
  match: [py]
  cmd: echo from-home-first
match-second:
  match: [py]
  cmd: echo from-home-second
]]
		)

		write_file(
			repo .. "/.flow.yml",
			[[
repo-match:
  match: [py]
  cmd: echo from-repo
]]
		)

		write_file(target, "print('hello')\n")

		local cmd_def = assert(config.resolve(target, {
			config_file = ".flow.yml",
			stop_at_home = true,
			home = home,
		}))

		assert.is_true(contains(cmd_def.cmd, "echo from-repo"))
	end)

	it("does not match filename without extension", function()
		local home = root .. "/home"
		local repo = home .. "/repo"
		local src = repo .. "/src"
		local target = src .. "/worker.py"

		write_file(
			home .. "/.flow.yml",
			[[
worker:
  cmd: echo from-filename
py:
  cmd: echo from-extension
]]
		)

		write_file(target, "print('hello')\n")

		local cmd_def = assert(config.resolve(target, {
			config_file = ".flow.yml",
			stop_at_home = true,
			home = home,
		}))

		assert.is_true(contains(cmd_def.cmd, "echo from-extension"))
		assert.is_false(contains(cmd_def.cmd, "echo from-filename"))
	end)

	it("parses plain multiline cmd blocks with URLs", function()
		local home = root .. "/home"
		local repo = home .. "/repo"
		local src = repo .. "/src"
		local target = src .. "/payload.json"

		write_file(
			home .. "/.flow.yml",
			[[
json:
  cmd:
    curl -k -i -X POST "https://localhost:7125/api/test" \
      -H "Content-Type: application/json" \
      --data-binary @{{filepath}}
]]
		)

		write_file(target, "{}\n")

		local cmd_def = assert(config.resolve(target, {
			config_file = ".flow.yml",
			stop_at_home = true,
			home = home,
		}))

		assert.is_true(contains(cmd_def.cmd, 'curl -k -i -X POST "https://localhost:7125/api/test"'))
		assert.is_true(contains(cmd_def.cmd, "--data-binary @" .. target))
	end)

	it("handles inline multiline scalar continuations without truncating later keys", function()
		local home = root .. "/home"
		local repo = home .. "/repo"
		local src = repo .. "/src"
		local target = src .. "/sVar.py"

		write_file(
			home .. "/.flow.yml",
			[[
ioCombine.py:
  cmd: python {{filepath}} -c /tmp/iGet.xlsx
    -p /tmp/sVar.xlsx
    -o /tmp/IO.xlsx

sVar.py:
  cmd: bash ~/git/Yokogawa/Common/scripts/run_svar.sh

py:
  cmd: python {{filepath}}
]]
		)

		write_file(target, "print('hello')\n")

		local cmd_def = assert(config.resolve(target, {
			config_file = ".flow.yml",
			stop_at_home = true,
			home = home,
		}))

		assert.are.equal("sVar.py", cmd_def.source_key)
		assert.is_true(contains(cmd_def.cmd, "run_svar.sh"))
	end)

	it("parses keys with inline comments (YAML fold markers)", function()
		local home = root .. "/home"
		local repo = home .. "/repo"
		local src = repo .. "/src"
		local target = src .. "/tag_generator.py"

		write_file(
			home .. "/.flow.yml",
			[[
py:
  cmd: echo from-extension

tag_generator.py: # {{{2
  cmd: echo from-basename-with-comment
]]
		)

		write_file(target, "print('hello')\n")

		local cmd_def = assert(config.resolve(target, {
			config_file = ".flow.yml",
			stop_at_home = true,
			home = home,
		}))

		assert.is_true(contains(cmd_def.cmd, "echo from-basename-with-comment"))
		assert.are.equal("tag_generator.py", cmd_def.source_key)
	end)

	it("preserves hash inside quoted scalar values", function()
		local home = root .. "/home"
		local repo = home .. "/repo"
		local src = repo .. "/src"
		local target = src .. "/run.sh"

		write_file(
			home .. "/.flow.yml",
			[[
sh:
  cmd: echo "hello # world"
]]
		)

		write_file(target, "#!/bin/bash\n")

		local cmd_def = assert(config.resolve(target, {
			config_file = ".flow.yml",
			stop_at_home = true,
			home = home,
		}))

		assert.is_true(contains(cmd_def.cmd, 'echo "hello # world"'))
	end)

	it("keeps URL fragments while stripping trailing inline comments", function()
		local home = root .. "/home"
		local repo = home .. "/repo"
		local src = repo .. "/src"
		local target = src .. "/worker.py"

		write_file(
			home .. "/.flow.yml",
			[[
py:
  cmd: curl https://example.com/#frag --name value # this is a comment
]]
		)

		write_file(target, "print('hello')\n")

		local cmd_def = assert(config.resolve(target, {
			config_file = ".flow.yml",
			stop_at_home = true,
			home = home,
		}))

		assert.is_true(contains(cmd_def.cmd, "https://example.com/#frag"))
		assert.is_false(contains(cmd_def.cmd, "this is a comment"))
	end)

	it("parses match arrays with commas inside quoted elements", function()
		local home = root .. "/home"
		local repo = home .. "/repo"
		local src = repo .. "/src"
		local target = src .. "/worker.py"

		write_file(
			home .. "/.flow.yml",
			[[
python-group:
  match: ["foo,bar", py]
  cmd: echo from-match
default:
  cmd: echo default
]]
		)

		write_file(target, "print('hello')\n")

		local cmd_def = assert(config.resolve(target, {
			config_file = ".flow.yml",
			stop_at_home = true,
			home = home,
		}))

		assert.are.equal("python-group", cmd_def.source_key)
		assert.is_true(contains(cmd_def.cmd, "echo from-match"))
	end)

	it("handles top-level comments after inline continuation and still parses later keys", function()
		local home = root .. "/home"
		local repo = home .. "/repo"
		local src = repo .. "/src"
		local target = src .. "/sVar.py"

		write_file(
			home .. "/.flow.yml",
			[[
ioCombine.py:
  cmd: python {{filepath}} -c /tmp/iGet.xlsx
    -p /tmp/sVar.xlsx
    -o /tmp/IO.xlsx
# comment between entries
sVar.py:
  cmd: bash /tmp/run_svar.sh
py:
  cmd: python {{filepath}}
]]
		)

		write_file(target, "print('hello')\n")

		local cmd_def = assert(config.resolve(target, {
			config_file = ".flow.yml",
			stop_at_home = true,
			home = home,
		}))

		assert.are.equal("sVar.py", cmd_def.source_key)
		assert.is_true(contains(cmd_def.cmd, "run_svar.sh"))
	end)

	it("finds source flow file and line for resolved key", function()
		local home = root .. "/home"
		local repo = home .. "/repo"
		local src = repo .. "/tasks"
		local target = src .. "/sync.yaml"

		write_file(
			home .. "/.flow.yml",
			[[
default:
  cmd: echo home-default
]]
		)

		write_file(
			repo .. "/.flow.yml",
			[[
# repo-specific tasks

sync.yaml:
  cmd: bash ./ansible-run.sh --tags "sync"
]]
		)

		write_file(target, "hosts: []\n")

		local cmd_def = assert(config.resolve(target, {
			config_file = ".flow.yml",
			stop_at_home = true,
			home = home,
		}))
		assert.are.equal("sync.yaml", cmd_def.source_key)

		local location = assert(config.find_source_location(cmd_def.source_key, cmd_def.source_files))
		assert.are.equal(repo .. "/.flow.yml", location.file)
		assert.are.equal(4, location.line)
	end)

	it("finds source location in nearest file and jumps to cmd when cmd is not first field", function()
		local home = root .. "/home"
		local repo = home .. "/repo"
		local src = repo .. "/tasks"
		local target = src .. "/sync.yaml"

		write_file(
			home .. "/.flow.yml",
			[[
sync.yaml:
  cmd: echo home-sync
]]
		)

		write_file(
			repo .. "/.flow.yml",
			[[
# repo-specific tasks
sync.yaml:
  runner: terminal
  cmd: echo repo-sync
]]
		)

		write_file(target, "hosts: []\n")

		local cmd_def = assert(config.resolve(target, {
			config_file = ".flow.yml",
			stop_at_home = true,
			home = home,
		}))
		assert.are.equal("sync.yaml", cmd_def.source_key)
		assert.is_true(contains(cmd_def.cmd, "echo repo-sync"))

		local location = assert(config.find_source_location(cmd_def.source_key, cmd_def.source_files))
		assert.are.equal(repo .. "/.flow.yml", location.file)
		assert.are.equal(4, location.line)
	end)
end)
