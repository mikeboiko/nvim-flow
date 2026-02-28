local yaml = require("nvim-flow.yaml")
local template = require("nvim-flow.template")
local path = require("nvim-flow.path")

local M = {}

local uv = vim.uv or vim.loop

local function trim(value)
	return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function is_list(tbl)
	if type(tbl) ~= "table" then
		return false
	end

	local count = 0
	for key, _ in pairs(tbl) do
		if type(key) ~= "number" then
			return false
		end
		count = count + 1
	end

	for i = 1, count do
		if tbl[i] == nil then
			return false
		end
	end

	return true
end

local function is_meta_key(key)
	return type(key) == "string" and key:sub(1, 2) == "__"
end

local function ordered_entry_keys(tbl)
	if type(tbl) ~= "table" then
		return {}
	end

	local keys = {}
	local seen = {}
	local order = rawget(tbl, "__order")
	if type(order) == "table" then
		for _, key in ipairs(order) do
			if tbl[key] ~= nil and not is_meta_key(key) and not seen[key] then
				table.insert(keys, key)
				seen[key] = true
			end
		end
	end

	local extras = {}
	for key, _ in pairs(tbl) do
		if not is_meta_key(key) and not seen[key] then
			table.insert(extras, key)
		end
	end
	table.sort(extras, function(a, b)
		return tostring(a) < tostring(b)
	end)

	for _, key in ipairs(extras) do
		table.insert(keys, key)
	end

	return keys
end

local function remove_order_key(order, key)
	for idx, existing in ipairs(order) do
		if existing == key then
			table.remove(order, idx)
			return
		end
	end
end

local function merge_orders(base_order, override_order)
	local out = vim.deepcopy(base_order)
	for i = #override_order, 1, -1 do
		local key = override_order[i]
		remove_order_key(out, key)
		table.insert(out, 1, key)
	end
	return out
end

local function deep_merge(base, override)
	local out = vim.deepcopy(base)
	local base_order = ordered_entry_keys(base)
	local override_order = ordered_entry_keys(override)

	for _, key in ipairs(override_order) do
		local value = override[key]
		if type(out[key]) == "table" and type(value) == "table" and not is_list(out[key]) and not is_list(value) then
			out[key] = deep_merge(out[key], value)
		else
			out[key] = vim.deepcopy(value)
		end
	end

	rawset(out, "__order", merge_orders(base_order, override_order))
	return out
end

local function file_exists(filepath)
	return uv.fs_stat(filepath) ~= nil
end

function M.find_config_files(filepath, opts)
	opts = opts or {}

	local config_file = opts.config_file or ".flow.yml"
	local stop_at_home = opts.stop_at_home ~= false
	local home = path.normalize(opts.home or uv.os_homedir())
	local dir = vim.fs.dirname(path.to_absolute(filepath))

	local files = {}
	while dir and dir ~= "" do
		local candidate = dir .. "/" .. config_file
		if file_exists(candidate) then
			table.insert(files, candidate)
		end

		if stop_at_home and dir == home then
			break
		end

		local parent = vim.fs.dirname(dir)
		if not parent or parent == dir then
			break
		end
		dir = parent
	end

	return files
end

function M.load_file(filepath)
	local parsed, err = yaml.decode_file(filepath)
	if not parsed then
		return nil, ("Failed parsing %s: %s"):format(filepath, err)
	end
	if type(parsed) ~= "table" then
		return {}
	end
	return parsed
end

function M.load_merged(filepath, opts)
	opts = opts or {}

	local files = M.find_config_files(filepath, opts)
	local config_file = opts.config_file or ".flow.yml"
	if #files == 0 then
		return nil, nil, ("No `%s` found while walking up from %s"):format(config_file, filepath)
	end

	local merged = {}
	for i = #files, 1, -1 do
		local parsed, parse_err = M.load_file(files[i])
		if not parsed then
			return nil, nil, parse_err
		end
		merged = deep_merge(merged, parsed)
	end
	return merged, files
end

local function has_glob(pattern)
	return pattern:find("[%*%?%[]") ~= nil
end

local function glob_match(pattern, value)
	local regpat = vim.fn.glob2regpat(pattern)
	return vim.fn.match(value, regpat) ~= -1
end

local function pattern_matches(pattern, ctx)
	pattern = trim(tostring(pattern or ""))
	if pattern == "" then
		return false
	end

	local exact_candidates = {
		ctx.basename,
		ctx.folder,
		ctx.repo,
		ctx.ext,
		ctx.dotext,
	}
	for _, candidate in ipairs(exact_candidates) do
		if pattern == candidate then
			return true
		end
	end

	if pattern:sub(-1) == "/" then
		if ctx.filepath:find("/" .. pattern, 1, true) or ctx.filepath:sub(-#pattern) == pattern then
			return true
		end
	end

	if has_glob(pattern) then
		local glob_candidates = {
			ctx.basename,
			ctx.folder,
			ctx.repo,
			ctx.ext,
			ctx.dotext,
			ctx.filepath,
			ctx.dir,
		}
		for _, candidate in ipairs(glob_candidates) do
			if glob_match(pattern, candidate) then
				return true
			end
		end
	end

	if ctx.filepath:find("/" .. pattern .. "/", 1, true) then
		return true
	end

	return false
end

function M.find_match(flow_defs, ctx)
	local basename_match = flow_defs[ctx.basename]
	if type(basename_match) == "table" then
		return ctx.basename, basename_match
	end

	for _, key in ipairs(ordered_entry_keys(flow_defs)) do
		local entry = flow_defs[key]
		if type(entry) == "table" then
			local patterns = entry.match
			if patterns ~= nil then
				if type(patterns) == "string" then
					patterns = { patterns }
				end
				if is_list(patterns) then
					for _, pattern in ipairs(patterns) do
						if pattern_matches(pattern, ctx) then
							return key, entry
						end
					end
				end
			end
		end
	end

	local folder_match = flow_defs[ctx.folder]
	if type(folder_match) == "table" then
		return ctx.folder, folder_match
	end

	local repo_match = flow_defs[ctx.repo]
	if type(repo_match) == "table" then
		return ctx.repo, repo_match
	end

	local dotext_match = flow_defs[ctx.dotext]
	if type(dotext_match) == "table" then
		return ctx.dotext, dotext_match
	end

	local ext_match = flow_defs[ctx.ext]
	if type(ext_match) == "table" then
		return ctx.ext, ext_match
	end

	local default_match = flow_defs.default
	if type(default_match) == "table" then
		return "default", default_match
	end

	return nil
end

local function normalize_runner(runner)
	if runner == nil or runner == "" then
		return "terminal"
	end

	runner = tostring(runner):gsub("_", "-")
	if runner == "vim" or runner == "terminal" then
		return "terminal"
	end
	if runner == "debug" then
		return "debug"
	end
	return nil
end

function M.normalize_cmd_def(key, entry, ctx)
	if type(entry) ~= "table" then
		return nil, ("invalid entry for key `%s`"):format(key)
	end

	if type(entry.cmd) ~= "string" then
		return nil, ("entry `%s` must define a string `cmd`"):format(key)
	end

	local cmd_def = vim.deepcopy(entry)
	cmd_def.runner = normalize_runner(cmd_def.runner)
	if not cmd_def.runner then
		return nil, ("invalid runner for `%s`; expected one of: vim, terminal, debug"):format(key)
	end

	cmd_def.cmd = template.expand(cmd_def.cmd, {
		filepath = ctx.filepath,
		dir = ctx.dir,
		filename = ctx.filename,
		ext = ctx.ext,
		repo = ctx.repo,
		folder = ctx.folder,
	})

	if not cmd_def.cmd:match("^#!") then
		cmd_def.cmd = "#!/usr/bin/env bash\n" .. cmd_def.cmd
	end

	cmd_def.source_key = key
	return cmd_def
end

function M.resolve(filepath, opts)
	opts = opts or {}
	local ctx = path.build_context(filepath)

	local flow_defs, source_files, load_err = M.load_merged(ctx.filepath, opts)
	if not flow_defs then
		return nil, load_err
	end

	local key, entry = M.find_match(flow_defs, ctx)
	if not entry then
		return nil, ("No matching flow definition found in `%s`"):format(opts.config_file or ".flow.yml")
	end

	local cmd_def, normalize_err = M.normalize_cmd_def(key, entry, ctx)
	if not cmd_def then
		return nil, normalize_err
	end

	cmd_def.filepath = ctx.filepath
	cmd_def.source_files = source_files
	return cmd_def
end

return M
