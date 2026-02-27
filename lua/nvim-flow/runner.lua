local M = {}

local uv = vim.uv or vim.loop

M.last_output_lines = {}
M.last_command = nil
M.last_cmd_def = nil
M.last_terminal_buf = nil

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
    fh:write('echo "--------------------------------------------------------------------------------"\n')
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
  local previous_win = vim.api.nvim_get_current_win()

  local script_path, script_err = build_script(cmd_def.cmd, show_command)
  if not script_path then
    return false, script_err
  end

  M.last_output_lines = {}
  M.last_command = cmd_def.cmd
  M.last_cmd_def = vim.deepcopy(cmd_def)

  vim.cmd(("%dsplit"):format(terminal_height))
  M.last_terminal_buf = vim.api.nvim_get_current_buf()

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
    if vim.api.nvim_win_is_valid(previous_win) then
      vim.api.nvim_set_current_win(previous_win)
    end
    return false, "failed to start terminal job"
  end

  vim.cmd("normal! G")
  if vim.api.nvim_win_is_valid(previous_win) then
    vim.api.nvim_set_current_win(previous_win)
  end

  return true
end

return M
