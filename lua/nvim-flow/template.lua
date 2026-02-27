local M = {}

function M.expand(cmd, vars)
  if type(cmd) ~= "string" then
    return cmd
  end

  return (cmd:gsub("{{%s*([%w_]+)%s*}}", function(name)
    local value = vars and vars[name]
    if value == nil then
      return "{{" .. name .. "}}"
    end
    return tostring(value)
  end))
end

return M
