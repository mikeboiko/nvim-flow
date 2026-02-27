local M = {}
local uv = vim.uv or vim.loop

function M.normalize(path)
	if not path or path == "" then
		return nil
	end

	if path:sub(1, 1) ~= "/" then
		path = vim.fn.fnamemodify(path, ":p")
	end

	return vim.fs.normalize(path)
end

function M.to_absolute(path)
	return M.normalize(path)
end

function M.split_filename(basename)
	local filename, ext = basename:match("^(.*)%.([^%.]+)$")
	if not filename then
		return basename, "", ""
	end
	return filename, ext, "." .. ext
end

function M.detect_repo_name(filepath)
	local start = vim.fs.dirname(filepath)
	local root = nil
	if vim.fs.root then
		root = vim.fs.root(start, { ".git" })
	else
		local dir = start
		while dir and dir ~= "" do
			if uv.fs_stat(dir .. "/.git") then
				root = dir
				break
			end
			local parent = vim.fs.dirname(dir)
			if not parent or parent == dir then
				break
			end
			dir = parent
		end
	end
	if root then
		return vim.fs.basename(root)
	end
	return ""
end

function M.build_context(filepath)
	local absolute = M.to_absolute(filepath)
	local dir = vim.fs.dirname(absolute)
	local basename = vim.fs.basename(absolute)
	local filename, ext, dotext = M.split_filename(basename)
	return {
		filepath = absolute,
		dir = dir,
		basename = basename,
		filename = filename,
		ext = ext,
		dotext = dotext,
		folder = vim.fs.basename(dir),
		repo = M.detect_repo_name(absolute),
	}
end

return M
