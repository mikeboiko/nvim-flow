local config = require("nvim-flow.config")
local lock = require("nvim-flow.lock")
local runner = require("nvim-flow.runner")
local debug_runner = require("nvim-flow.debug_runner")
local preview = require("nvim-flow.preview")
local quickfix = require("nvim-flow.quickfix")

local M = {}

local defaults = {
	config_file = ".flow.yml",
	terminal_height = 15,
	terminal_position = "top",
	stop_at_home = true,
	show_command = true,
	keymaps = {
		run = nil,
		debug = nil,
		toggle_lock = nil,
		preview = nil,
		quickfix = nil,
	},
}

local state = {
	opts = vim.deepcopy(defaults),
}

local function notify(message, level)
	vim.notify("nvim-flow: " .. message, level or vim.log.levels.INFO)
end

local function current_filepath()
	local filepath = vim.api.nvim_buf_get_name(0)
	if filepath == "" then
		return nil
	end
	return vim.fs.normalize(filepath)
end

local function resolve_cmd_def()
	local filepath = lock.get() or current_filepath()
	if not filepath then
		notify("current buffer has no file path", vim.log.levels.WARN)
		return nil
	end

	local cmd_def, err = config.resolve(filepath, state.opts)
	if not cmd_def then
		notify(err, vim.log.levels.ERROR)
		return nil
	end
	return cmd_def
end

local function setup_keymaps()
	local keymaps = state.opts.keymaps or {}
	local group = vim.api.nvim_create_augroup("NvimFlowKeymaps", { clear = true })

	local function pre_flow_action()
		vim.cmd("wa")
		if vim.fn.exists("*CloseAll") == 1 then
			pcall(vim.cmd, "call CloseAll()")
		end
	end

	local function set_run_mapping(bufnr)
		if not vim.api.nvim_buf_is_valid(bufnr) then
			return
		end
		if vim.bo[bufnr].buftype ~= "" then
			return
		end

		vim.keymap.set("n", keymaps.run, function()
			pre_flow_action()
			require("nvim-flow").run()
		end, { buffer = bufnr, silent = true, desc = "Flow run" })
	end

	if keymaps.run then
		for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_loaded(bufnr) then
				set_run_mapping(bufnr)
			end
		end

		vim.api.nvim_create_autocmd("FileType", {
			group = group,
			pattern = "*",
			callback = function(event)
				set_run_mapping(event.buf)
			end,
		})
	end

	if keymaps.debug then
		vim.keymap.set("n", keymaps.debug, function()
			pre_flow_action()
			require("nvim-flow").debug()
		end, { silent = true, desc = "Flow debug" })
	end

	if keymaps.toggle_lock then
		vim.keymap.set("n", keymaps.toggle_lock, function()
			require("nvim-flow").toggle_lock()
		end, { silent = true, desc = "Flow toggle lock" })
	end

	if keymaps.preview then
		vim.keymap.set("n", keymaps.preview, function()
			require("nvim-flow").preview()
		end, { silent = true, desc = "Flow preview" })
	end

	if keymaps.quickfix then
		vim.keymap.set("n", keymaps.quickfix, function()
			require("nvim-flow").quickfix()
		end, { silent = true, desc = "Flow quickfix" })
	end
end

function M.setup(opts)
	state.opts = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
	setup_keymaps()
end

function M.run()
	local cmd_def = resolve_cmd_def()
	if not cmd_def then
		return
	end

	if cmd_def.runner == "debug" then
		debug_runner.run(cmd_def)
		return
	end

	local ok, err = runner.run(cmd_def, state.opts)
	if not ok then
		notify(err, vim.log.levels.ERROR)
	end
end

function M.debug()
	local cmd_def = resolve_cmd_def()
	if not cmd_def then
		return
	end
	debug_runner.run(cmd_def)
end

function M.preview()
	local cmd_def = resolve_cmd_def()
	if not cmd_def then
		return
	end
	preview.open(runner.display_command(cmd_def.cmd), { title = "Flow Preview (" .. cmd_def.source_key .. ")" })
end

function M.quickfix()
	local lines = runner.get_last_output()
	if #lines == 0 then
		notify("no terminal output available from previous FlowRun", vim.log.levels.WARN)
		return
	end

	local ok, err = quickfix.populate_python(lines, "nvim-flow traceback")
	if not ok then
		notify(err, vim.log.levels.WARN)
		return
	end
	vim.cmd("copen")
end

function M.toggle_lock(filepath)
	if filepath and filepath ~= "" then
		lock.set(filepath)
		notify("file lock set: " .. filepath)
		return
	end

	local current = lock.get()
	if current then
		lock.clear()
		notify("file lock released")
		return
	end

	local active_file = current_filepath()
	if not active_file then
		notify("current buffer has no file path", vim.log.levels.WARN)
		return
	end
	lock.set(active_file)
	notify("file lock set: " .. active_file)
end

return M
