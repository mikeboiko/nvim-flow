local M = {}

local uv = vim.uv or vim.loop
local ansi = require("nvim-flow.ansi")

M.last_output_lines = {}
M.last_command = nil
M.last_cmd_def = nil
M.last_terminal_buf = nil
M.last_terminal_win = nil

local current_buffer_job = nil

local function trim(value)
	return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function split_lines(text)
	local lines = {}
	text = (text or ""):gsub("\r\n", "\n")
	if text:sub(-1) ~= "\n" then
		text = text .. "\n"
	end
	for line in text:gmatch("(.-)\n") do
		table.insert(lines, line)
	end
	return lines
end

local function max_line_width(lines)
	local max_width = 1
	for _, line in ipairs(lines) do
		max_width = math.max(max_width, vim.fn.strdisplaywidth(line))
	end
	return max_width
end

local function normalize_output_line(line)
	line = (line or ""):gsub("\r+$", "")
	if line:find("\r", 1, true) then
		line = line:gsub(".*\r", "")
	end
	return line
end

function M.display_command(cmd)
	local lines = split_lines(cmd)
	local start_idx = 1
	if lines[1] and lines[1]:match("^#!") then
		start_idx = 2
	end

	local display_lines = {}
	for i = start_idx, #lines do
		table.insert(display_lines, lines[i])
	end
	return table.concat(display_lines, "\n")
end

local function build_script(cmd, show_command)
	local lines = split_lines(cmd)
	local hashbang = "#!/usr/bin/env bash"
	local start_idx = 1

	if lines[1] and lines[1]:match("^#!") then
		hashbang = lines[1]
		start_idx = 2
	end

	local clean_lines = {}
	for i = start_idx, #lines do
		if trim(lines[i]) ~= "clear" then
			table.insert(clean_lines, lines[i])
		end
	end

	local script_path = vim.fn.tempname()
	local fh, open_err = io.open(script_path, "w")
	if not fh then
		return nil, open_err
	end

	fh:write(hashbang .. "\n")
	if show_command then
		local display_cmd = M.display_command(cmd)
		fh:write("cat <<'NVIM_FLOW_CONTENT_EOF'\n")
		fh:write(display_cmd)
		if display_cmd:sub(-1) ~= "\n" then
			fh:write("\n")
		end
		fh:write("NVIM_FLOW_CONTENT_EOF\n")
		fh:write(("__nvim_flow_sep_len=%d\n"):format(max_line_width(split_lines(display_cmd))))
		fh:write('__nvim_flow_cols=$(tput cols 2>/dev/null || printf "%s" "$__nvim_flow_sep_len")\n')
		fh:write('case "$__nvim_flow_cols" in ""|*[!0-9]*) __nvim_flow_cols="$__nvim_flow_sep_len" ;; esac\n')
		fh:write(
			'if [ "$__nvim_flow_cols" -lt "$__nvim_flow_sep_len" ]; then __nvim_flow_sep_len="$__nvim_flow_cols"; fi\n'
		)
		fh:write('if [ "$__nvim_flow_sep_len" -lt 1 ]; then __nvim_flow_sep_len=1; fi\n')
		fh:write("printf '%*s\\n' \"$__nvim_flow_sep_len\" '' | tr ' ' '-'\n")
	end

	fh:write(table.concat(clean_lines, "\n"))
	fh:write("\n")
	fh:close()

	if uv and uv.fs_chmod then
		uv.fs_chmod(script_path, 493)
	else
		vim.fn.system({ "chmod", "+x", script_path })
	end

	return script_path
end

function M._build_script_for_test(cmd, show_command)
	return build_script(cmd, show_command)
end

function M._cleanup_script_for_test(script_path)
	if uv and uv.fs_unlink then
		uv.fs_unlink(script_path)
	else
		os.remove(script_path)
	end
end

function M.get_last_output()
	if M.last_terminal_buf and vim.api.nvim_buf_is_valid(M.last_terminal_buf) then
		M.last_output_lines = vim.api.nvim_buf_get_lines(M.last_terminal_buf, 0, -1, false)
	end
	return vim.deepcopy(M.last_output_lines)
end

local function build_buffer_header(cmd)
	local display_cmd = M.display_command(cmd)
	local display_lines = split_lines(display_cmd)
	local sep_width = max_line_width(display_lines)
	if sep_width < 1 then
		sep_width = 1
	end
	local header = {}
	for _, line in ipairs(display_lines) do
		table.insert(header, line)
	end
	table.insert(header, string.rep("-", sep_width))
	return header
end

local function build_buffer_name(cmd_def, exit_code)
	local source_key = cmd_def.source_key or "run"
	if exit_code and exit_code ~= 0 then
		return ("flow://%s (%d)"):format(source_key, exit_code)
	end
	return "flow://" .. source_key
end

local function run_buffer(cmd_def, opts)
	local show_command = opts.show_command ~= false
	local terminal_height = tonumber(opts.terminal_height) or 15
	local terminal_position = opts.terminal_position == "bottom" and "bottom" or "top"
	local source_win = vim.api.nvim_get_current_win()
	local source_buf = vim.api.nvim_get_current_buf()

	local script_path, script_err = build_script(cmd_def.cmd, false)
	if not script_path then
		return false, script_err
	end

	M.last_output_lines = {}
	M.last_command = cmd_def.cmd
	M.last_cmd_def = vim.deepcopy(cmd_def)

	local buf = vim.api.nvim_create_buf(false, true)
	vim.b[buf].nvim_flow_terminal = 1
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	local buf_name = build_buffer_name(cmd_def)
	pcall(vim.api.nvim_buf_set_name, buf, buf_name)

	local buf_win
	local opened, open_result = pcall(vim.api.nvim_open_win, buf, true, {
		split = terminal_position == "top" and "above" or "below",
		win = source_win,
		height = terminal_height,
	})
	if opened then
		buf_win = open_result
	else
		if terminal_position == "top" then
			vim.cmd(("topleft %dsplit"):format(terminal_height))
		else
			vim.cmd(("botright %dsplit"):format(terminal_height))
		end
		buf_win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(buf_win, buf)
	end

	vim.wo[buf_win].wrap = true
	vim.wo[buf_win].linebreak = true
	vim.wo[buf_win].number = false
	vim.wo[buf_win].relativenumber = false
	vim.wo[buf_win].signcolumn = "no"

	M.last_terminal_buf = buf
	M.last_terminal_win = buf_win

	local header_lines = {}
	if show_command then
		header_lines = build_buffer_header(cmd_def.cmd)
	end

	vim.bo[buf].modifiable = true
	if #header_lines > 0 then
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, header_lines)
	end
	vim.bo[buf].modifiable = false

	local function restore_source_window()
		local target_win = source_win
		if not vim.api.nvim_win_is_valid(target_win) then
			target_win = nil
		end

		if target_win and vim.api.nvim_win_get_buf(target_win) ~= source_buf then
			for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
				if vim.api.nvim_win_get_buf(win) == source_buf then
					target_win = win
					break
				end
			end
		end

		if not target_win then
			target_win = vim.api.nvim_tabpage_list_wins(0)[1]
			if target_win and vim.api.nvim_buf_is_valid(source_buf) then
				vim.api.nvim_win_set_buf(target_win, source_buf)
			end
		end

		if target_win and vim.api.nvim_win_is_valid(target_win) then
			if vim.api.nvim_buf_is_valid(source_buf) and vim.api.nvim_win_get_buf(target_win) ~= source_buf then
				vim.api.nvim_win_set_buf(target_win, source_buf)
			end
			vim.api.nvim_set_current_win(target_win)
		end
	end

	local function cleanup_script()
		if uv and uv.fs_unlink then
			uv.fs_unlink(script_path)
		else
			os.remove(script_path)
		end
	end

	local collected = { "" }

	local function output_lines_snapshot()
		local lines = vim.deepcopy(collected)

		if #lines > 0 and lines[#lines] == "" then
			table.remove(lines)
		end

		for i, line in ipairs(lines) do
			lines[i] = normalize_output_line(line)
		end

		local filtered = {}
		for _, line in ipairs(lines) do
			if not line:match("^stty:.*Inappropriate ioctl") then
				table.insert(filtered, line)
			end
		end

		return filtered
	end

	local function render_output(exit_code)
		local lines = output_lines_snapshot()
		local all_lines = {}
		for _, hl in ipairs(header_lines) do
			table.insert(all_lines, hl)
		end
		for _, ol in ipairs(lines) do
			table.insert(all_lines, ol)
		end

		M.last_output_lines = ansi.strip_lines(vim.deepcopy(all_lines))

		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end

		local should_follow = false
		if vim.api.nvim_win_is_valid(buf_win) and vim.api.nvim_win_get_buf(buf_win) == buf then
			local cursor_line = vim.api.nvim_win_get_cursor(buf_win)[1]
			local buffer_line_count = vim.api.nvim_buf_line_count(buf)
			should_follow = cursor_line >= buffer_line_count
		end

		if exit_code ~= nil then
			pcall(vim.api.nvim_buf_set_name, buf, build_buffer_name(cmd_def, exit_code))
		end

		local display_lines = ansi.strip_lines(vim.deepcopy(lines))
		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, #header_lines, -1, false, display_lines)
		ansi.clear_buffer(buf, #header_lines, -1)
		ansi.highlight_buffer(buf, lines, #header_lines)
		vim.bo[buf].modifiable = false

		if should_follow and vim.api.nvim_win_is_valid(buf_win) and vim.api.nvim_win_get_buf(buf_win) == buf then
			local line_count = math.max(vim.api.nvim_buf_line_count(buf), 1)
			vim.api.nvim_win_set_cursor(buf_win, { line_count, 0 })
		end
	end

	local function on_output(job_id, data, _)
		if current_buffer_job and job_id ~= current_buffer_job then
			return
		end

		if not data or #data == 0 then
			return
		end
		collected[#collected] = collected[#collected] .. (data[1] or "")
		for i = 2, #data do
			table.insert(collected, data[i])
		end

		render_output()
	end

	local function on_exit(job_id, exit_code)
		-- Ignore stale callbacks from superseded runs
		if job_id ~= current_buffer_job then
			cleanup_script()
			return
		end
		current_buffer_job = nil

		render_output(exit_code)

		cleanup_script()
	end

	-- Run under a PTY so terminal-aware programs (including code that
	-- calls `stty size`) see a real terminal size, while we still render
	-- the captured output into a normal buffer.
	local env = vim.fn.environ()
	env.COLUMNS = tostring(vim.api.nvim_win_get_width(buf_win))
	env.LINES = tostring(vim.api.nvim_win_get_height(buf_win))

	local job = vim.fn.jobstart(script_path, {
		env = env,
		pty = true,
		width = vim.api.nvim_win_get_width(buf_win),
		height = vim.api.nvim_win_get_height(buf_win),
		on_stdout = on_output,
		on_exit = on_exit,
	})

	if job <= 0 then
		cleanup_script()
		restore_source_window()
		return false, "failed to start job"
	end

	current_buffer_job = job
	restore_source_window()
	return true
end

function M.run(cmd_def, opts)
	opts = opts or {}

	if opts.output_mode == "buffer" then
		return run_buffer(cmd_def, opts)
	end

	local show_command = opts.show_command ~= false
	local terminal_height = tonumber(opts.terminal_height) or 15
	local terminal_position = opts.terminal_position == "bottom" and "bottom" or "top"
	local source_win = vim.api.nvim_get_current_win()
	local source_buf = vim.api.nvim_get_current_buf()

	local script_path, script_err = build_script(cmd_def.cmd, show_command)
	if not script_path then
		return false, script_err
	end

	M.last_output_lines = {}
	M.last_command = cmd_def.cmd
	M.last_cmd_def = vim.deepcopy(cmd_def)
	local term_buf = vim.api.nvim_create_buf(true, false)
	vim.b[term_buf].nvim_flow_terminal = 1
	local term_win

	local opened, open_result = pcall(vim.api.nvim_open_win, term_buf, true, {
		split = terminal_position == "top" and "above" or "below",
		win = source_win,
		height = terminal_height,
	})
	if opened then
		term_win = open_result
	else
		if terminal_position == "top" then
			vim.cmd(("topleft %dsplit"):format(terminal_height))
		else
			vim.cmd(("botright %dsplit"):format(terminal_height))
		end
		term_win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(term_win, term_buf)
	end
	M.last_terminal_buf = term_buf
	M.last_terminal_win = term_win

	local function restore_source_window()
		local target_win = source_win
		if not vim.api.nvim_win_is_valid(target_win) then
			target_win = nil
		end

		if target_win and vim.api.nvim_win_get_buf(target_win) ~= source_buf then
			for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
				if vim.api.nvim_win_get_buf(win) == source_buf then
					target_win = win
					break
				end
			end
		end

		if not target_win then
			target_win = vim.api.nvim_tabpage_list_wins(0)[1]
			if target_win and vim.api.nvim_buf_is_valid(source_buf) then
				vim.api.nvim_win_set_buf(target_win, source_buf)
			end
		end

		if target_win and vim.api.nvim_win_is_valid(target_win) then
			if vim.api.nvim_buf_is_valid(source_buf) and vim.api.nvim_win_get_buf(target_win) ~= source_buf then
				vim.api.nvim_win_set_buf(target_win, source_buf)
			end
			vim.api.nvim_set_current_win(target_win)
		end
	end

	local function capture_terminal_output()
		if term_buf and vim.api.nvim_buf_is_valid(term_buf) then
			M.last_output_lines = vim.api.nvim_buf_get_lines(term_buf, 0, -1, false)
		end
	end

	local function cleanup_script()
		if uv and uv.fs_unlink then
			uv.fs_unlink(script_path)
		else
			os.remove(script_path)
		end
	end

	vim.api.nvim_set_current_win(term_win)
	local job = vim.fn.termopen(script_path, {
		on_exit = function()
			vim.schedule(function()
				-- Only capture if this terminal is still the active one
				if M.last_terminal_buf == term_buf then
					capture_terminal_output()
				end
				cleanup_script()
			end)
		end,
	})

	if job <= 0 then
		cleanup_script()
		restore_source_window()
		return false, "failed to start terminal job"
	end

	vim.cmd("normal! G")
	restore_source_window()

	return true
end

function M._build_buffer_header_for_test(cmd)
	return build_buffer_header(cmd)
end

return M
