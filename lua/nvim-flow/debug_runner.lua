local M = {}

function M.run(cmd_def)
  local ok, dap_functions = pcall(require, "config.dap.functions")
  if not ok or type(dap_functions.flow_debug) ~= "function" then
    vim.notify("nvim-flow: debug runner requires config.dap.functions.flow_debug()", vim.log.levels.ERROR)
    return false
  end

  dap_functions.flow_debug(cmd_def.cmd)
  return true
end

return M
