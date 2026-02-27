local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":p:h:h")

vim.opt.runtimepath:prepend(root)

local plenary_path = os.getenv("PLENARY_PATH") or (vim.fn.stdpath("data") .. "/lazy/plenary.nvim")
if (vim.uv or vim.loop).fs_stat(plenary_path) then
  vim.opt.runtimepath:prepend(plenary_path)
end

vim.opt.swapfile = false
