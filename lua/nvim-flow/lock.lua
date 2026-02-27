local M = {}

local locked_filepath = nil

local function normalize(path)
  if not path or path == "" then
    return nil
  end

  if path:sub(1, 1) ~= "/" then
    path = vim.fn.fnamemodify(path, ":p")
  end

  if vim and vim.fs and vim.fs.normalize then
    return vim.fs.normalize(path)
  end
  return path
end

function M.get()
  return locked_filepath
end

function M.set(filepath)
  local normalized = normalize(filepath)
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
