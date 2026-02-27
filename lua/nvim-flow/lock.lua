local M = {}
local path = require("nvim-flow.path")

local locked_filepath = nil

function M.get()
	return locked_filepath
end

function M.set(filepath)
	local normalized = path.normalize(filepath)
	if not normalized then
		return nil
	end
	locked_filepath = normalized
	return locked_filepath
end

function M.clear()
	locked_filepath = nil
end

return M
