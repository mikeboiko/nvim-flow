local M = {}

-- ESC[ ... m pattern (SGR sequences)
local ESC_PATTERN = "\27%[([%d;]*)m"

-- Resolve ANSI color index to the user's actual terminal palette color.
-- Falls back to basic named colors if terminal_color_N is not set.
local fallback_fg = {
	[0] = "Black",
	[1] = "Red",
	[2] = "Green",
	[3] = "Yellow",
	[4] = "Blue",
	[5] = "Magenta",
	[6] = "Cyan",
	[7] = "White",
	[8] = "DarkGrey",
	[9] = "LightRed",
	[10] = "LightGreen",
	[11] = "LightYellow",
	[12] = "LightBlue",
	[13] = "LightMagenta",
	[14] = "LightCyan",
	[15] = "White",
}

local function terminal_color(index)
	return vim.g["terminal_color_" .. index] or fallback_fg[index]
end

-- Map ANSI SGR foreground codes to terminal palette indices
local fg_to_palette = {
	[30] = 0,
	[31] = 1,
	[32] = 2,
	[33] = 3,
	[34] = 4,
	[35] = 5,
	[36] = 6,
	[37] = 7,
	[90] = 8,
	[91] = 9,
	[92] = 10,
	[93] = 11,
	[94] = 12,
	[95] = 13,
	[96] = 14,
	[97] = 15,
}

local bg_to_palette = {
	[40] = 0,
	[41] = 1,
	[42] = 2,
	[43] = 3,
	[44] = 4,
	[45] = 5,
	[46] = 6,
	[47] = 7,
	[100] = 8,
	[101] = 9,
	[102] = 10,
	[103] = 11,
	[104] = 12,
	[105] = 13,
	[106] = 14,
	[107] = 15,
}

local ns = vim.api.nvim_create_namespace("nvim_flow_ansi")
local hl_cache = {}

local function get_hl_group(attrs)
	local key = (attrs.bold and "B" or "")
		.. (attrs.underline and "U" or "")
		.. tostring(attrs.fg_idx or "")
		.. "/"
		.. tostring(attrs.bg_idx or "")
	if hl_cache[key] then
		return hl_cache[key]
	end
	if key == "/" then
		return nil
	end

	local group_name = "NvimFlowAnsi_" .. key:gsub("/", "_"):gsub("%s+", "")
	local hl_def = {}
	if attrs.fg_idx then
		hl_def.fg = terminal_color(attrs.fg_idx)
	end
	if attrs.bg_idx then
		hl_def.bg = terminal_color(attrs.bg_idx)
	end
	if attrs.bold then
		hl_def.bold = true
	end
	if attrs.underline then
		hl_def.underline = true
	end

	vim.api.nvim_set_hl(0, group_name, hl_def)
	hl_cache[key] = group_name
	return group_name
end

local function parse_sgr(params_str)
	local codes = {}
	if params_str == "" then
		table.insert(codes, 0)
	else
		for num in params_str:gmatch("%d+") do
			table.insert(codes, tonumber(num))
		end
	end
	return codes
end

--- Strip ANSI escape sequences from a string.
function M.strip(text)
	return (text:gsub("\27%[[%d;]*m", ""))
end

--- Strip ANSI sequences from a list of lines (in-place).
function M.strip_lines(lines)
	for i, line in ipairs(lines) do
		lines[i] = M.strip(line)
	end
	return lines
end

--- Apply ANSI color highlights to a buffer.
--- Lines should be the raw (un-stripped) content; the buffer should already
--- contain the stripped version at the corresponding line offsets.
---@param buf number Buffer handle
---@param raw_lines string[] Lines with ANSI codes
---@param line_offset number 0-based line offset in buffer
function M.highlight_buffer(buf, raw_lines, line_offset)
	local attrs = { bold = false, underline = false, fg_idx = nil, bg_idx = nil }

	for i, raw in ipairs(raw_lines) do
		local lnum = line_offset + i - 1
		local col = 0
		local last_pos = 1

		for seq_start, params_str, seq_end in raw:gmatch("()\27%[([%d;]*)m()") do
			-- Text before this escape sequence
			local text_before = raw:sub(last_pos, seq_start - 1)
			local text_len = #text_before

			if text_len > 0 then
				local hl_group = get_hl_group(attrs)
				if hl_group then
					pcall(vim.api.nvim_buf_set_extmark, buf, ns, lnum, col, {
						end_col = col + text_len,
						hl_group = hl_group,
					})
				end
				col = col + text_len
			end

			-- Process the SGR codes
			local codes = parse_sgr(params_str)
			for _, code in ipairs(codes) do
				if code == 0 then
					attrs = { bold = false, underline = false, fg_idx = nil, bg_idx = nil }
				elseif code == 1 then
					attrs.bold = true
				elseif code == 4 then
					attrs.underline = true
				elseif fg_to_palette[code] then
					attrs.fg_idx = fg_to_palette[code]
				elseif bg_to_palette[code] then
					attrs.bg_idx = bg_to_palette[code]
				end
			end

			last_pos = seq_end
		end

		-- Remaining text after last escape
		local remaining = raw:sub(last_pos)
		if #remaining > 0 then
			local hl_group = get_hl_group(attrs)
			if hl_group then
				pcall(vim.api.nvim_buf_set_extmark, buf, ns, lnum, col, {
					end_col = col + #remaining,
					hl_group = hl_group,
				})
			end
		end
	end
end

function M.clear_buffer(buf, line_start, line_end)
	vim.api.nvim_buf_clear_namespace(buf, ns, line_start or 0, line_end or -1)
end

return M
