local M = {}

local uv = vim.uv or vim.loop

M.last_output_lines = {}
M.last_command = nil
M.last_cmd_def = nil
M.last_terminal_buf = nil
M.last_terminal_win = nil

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
		fh:write("cat <<'NVIM_FLOW_CONTENT_EOF'\n")
		fh:write(cmd)
		if cmd:sub(-1) ~= "\n" then
			fh:write("\n")
		end
		fh:write("NVIM_FLOW_CONTENT_EOF\n")
		fh:write(("__nvim_flow_sep_len=%d\n"):format(max_line_width(lines)))
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

function M.run(cmd_def, opts)
	opts = opts or {}
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
		if M.last_terminal_buf and vim.api.nvim_buf_is_valid(M.last_terminal_buf) then
			M.last_output_lines = vim.api.nvim_buf_get_lines(M.last_terminal_buf, 0, -1, false)
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
				capture_terminal_output()
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

return M
