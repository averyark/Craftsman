--!nonstrict
--[[
    FileName    > PrintUtil.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 20/05/2026
--]]

const Repr = require("../Repr")

--[[
	@class PrintUtil
	A specialized printing and logging utility module designed for rich formatting, structured table output, and debugging assertions.
]]--
local PrintUtil = {}

local DEFAULT_INTERNAL_PREFIX = "Craftsman"
local DEFAULT_INTERNAL_SUFFIX = ""

local function get_calling_module_name()
	local info = debug.info(3, "s")
	return info:match("([^%.]+)$")
end

local function get_formatted_prefix_and_suffix(...)
	local module_name = get_calling_module_name()
	if module_name then
		return `[{module_name}] {...} {DEFAULT_INTERNAL_SUFFIX}`
	else
		return `{DEFAULT_INTERNAL_PREFIX} {...} {DEFAULT_INTERNAL_SUFFIX}`
	end
end

local function wrap_text(str: string, max_len: number): { string }
	local lines = {}
	local raw_lines = string.split(str, "\n")

	for i = 1, #raw_lines do
		local line = raw_lines[i]
		if #line <= max_len then
			table.insert(lines, line)
			continue
		end

		local current_line = ""
		for word in string.gmatch(line, "%S+") do
			if #word > max_len then
				if #current_line > 0 then
					table.insert(lines, current_line)
					current_line = ""
				end
				local temp = word
				while #temp > max_len do
					table.insert(lines, string.sub(temp, 1, max_len))
					temp = string.sub(temp, max_len + 1)
				end
				current_line = temp
			else
				local space = #current_line > 0 and " " or ""
				if #current_line + #space + #word > max_len then
					table.insert(lines, current_line)
					current_line = word
				else
					current_line = current_line .. space .. word
				end
			end
		end
		if #current_line > 0 then
			table.insert(lines, current_line)
		end
	end

	if #lines == 0 then
		table.insert(lines, "")
	end

	return lines
end

--[[
	Outputs standard log messages prefixed by the caller module name.
	@param ... any -- The arguments to print.
]]--
function PrintUtil:Print(...)
	local args = { ... }
	local formatted_args = {}
	for i, arg in args do
		formatted_args[i] = tostring(arg)
	end
	local message = table.concat(formatted_args, " ")
	print(get_formatted_prefix_and_suffix(message))
end

--[[
	Outputs warnings prefixed by the caller module name, along with a stack traceback.
	@param ... any -- The arguments to warn.
]]--
function PrintUtil:Warn(...)
	local args = { ... }
	local formatted_args = {}
	for i, arg in args do
		formatted_args[i] = tostring(arg)
	end
	local message = table.concat(formatted_args, " ")
	warn(get_formatted_prefix_and_suffix(message), debug.traceback("\n\n", 2))
end

--[[
	Throws an error prefixed by the caller module name.
	@param ... any -- The error message parameters.
]]--
function PrintUtil:Error(...)
	local args = { ... }
	local formatted_args = {}
	for i, arg in args do
		formatted_args[i] = tostring(arg)
	end
	local message = table.concat(formatted_args, " ")
	error(get_formatted_prefix_and_suffix(message))
end

--[[
	Asserts that a condition is true, otherwise throws a formatted error prefixed by the calling module name.
	@param condition any -- The condition expression to assert.
	@param ... any -- The error message parameters.
]]--
function PrintUtil:Assert(condition, ...)
	if not condition then
		local args = { ... }
		local formatted_args = {}
		for i, arg in args do
			formatted_args[i] = tostring(arg)
		end
		local message = table.concat(formatted_args, " ")
		error(get_formatted_prefix_and_suffix(message))
	end
end

--[[
	Prints a beautifully formatted ASCII table representing row and column data with dynamic wrapping and borders.
	@param title string -- The title header of the table.
	@param columns { string | { name: string } } -- The headers or definitions for each column.
	@param rows { { any } | { [string]: any } } -- The row data elements (can be arrays of values or dictionaries of fields).
	@param max_width number? -- The maximum character width of each cell column before word wrapping occurs (defaults to 45).
]]--
function PrintUtil:ListPrint(title, columns, rows, max_width)
	local title = title or ""
	local columns = columns or {}
	local rows = rows or {}
	local max_width = max_width or 45

	local print_count = 0
	local function print_line(s)
		print_count = print_count + 1
		print(tostring(s) .. string.rep(utf8.char(0x200B), print_count % 3))
	end

	local headers = {}
	for i, col in columns do
		if type(col) == "table" then
			headers[i] = tostring(col.name or col.header or col[1] or "")
		else
			headers[i] = tostring(col)
		end
	end

	-- Normalize rows into an array of row-tables (numeric indexed)
	local row_list = {}
	local function is_array(t)
		return type(t) == "table" and #t > 0
	end

	if is_array(rows) then
		for _, r in rows do
			row_list[#row_list + 1] = r
		end
	else
		for k, v in rows do
			local is_row_obj = false
			if type(v) == "table" and getmetatable(v) == nil then
				for j = 2, #headers do
					if v[headers[j]] ~= nil then
						is_row_obj = true
						break
					end
				end
			end

			if is_row_obj then
				local row = {}
				row[1] = k
				for j = 2, #headers do
					local h = headers[j]
					row[j] = v[h]
				end
				row_list[#row_list + 1] = row
			else
				row_list[#row_list + 1] = { k, v }
			end
		end
	end

	-- Ensure we have headers when none are provided
	local col_count = #headers
	if col_count == 0 then
		for _, r in row_list do
			col_count = math.max(col_count, #r)
		end
		for i = 1, col_count do
			headers[i] = headers[i] or ("Column " .. tostring(i))
		end
	end

	-- Build string representations and compute widths
	local widths = {}
	for i = 1, col_count do
		widths[i] = #tostring(headers[i])
	end

	local formatted = {}
	for ri = 1, #row_list do
		local r = row_list[ri]
		formatted[ri] = {}
		for ci = 1, col_count do
			local v = r[ci]
			local s
			if v == nil then
				s = ""
			elseif type(v) == "number" then
				if v % 1 == 0 then
					s = tostring(v)
				else
					s = string.format("%.2f", v)
				end
			elseif type(v) == "table" then
				s = Repr(v)
			else
				s = tostring(v)
			end

			local cell_lines = wrap_text(s, max_width)
			formatted[ri][ci] = cell_lines

			for li = 1, #cell_lines do
				local len = #cell_lines[li]
				if len > widths[ci] then
					widths[ci] = len
				end
			end
		end
	end

	-- Print title decoration (dynamic width)
	if title ~= "" then
		local title_str = tostring(title)
		local title_display = "  " .. title_str

		local sum_widths = 0
		for i = 1, col_count do
			sum_widths = sum_widths + (widths[i] or 0)
		end

		local table_len = sum_widths + 3 * col_count + 3
		local desired_len = math.max(table_len, #title_display)
		local equals_line = "  " .. string.rep("=", math.max(0, desired_len - 2))

		print_line("\n")
		print_line(equals_line)
		print_line(title_display)
		print_line(equals_line)
	else
		print_line("")
	end

	-- Helper to build borders
	local function build_border(left, mid, right)
		local out = "  " .. left
		for i = 1, col_count do
			out = out .. string.rep("─", widths[i] + 2)
			out = out .. (i < col_count and mid or right)
		end
		return out
	end

	print_line(build_border("┌", "┬", "┐"))

	-- Header row
	local headerLine = "  │"
	for i = 1, col_count do
		local h = headers[i] or ""
		headerLine = headerLine .. " " .. h .. string.rep(" ", widths[i] - #h) .. " │"
	end
	print_line(headerLine)

	print_line(build_border("├", "┼", "┤"))

	-- Data rows
	for ri = 1, #formatted do
		local max_lines = 1
		for ci = 1, col_count do
			max_lines = math.max(max_lines, #formatted[ri][ci])
		end

		for li = 1, max_lines do
			local rowLine = "  │"
			for ci = 1, col_count do
				local cell_lines = formatted[ri][ci]
				local cell = cell_lines[li] or ""
				local orig = row_list[ri] and row_list[ri][ci]
				local alignRight = type(orig) == "number"
				if alignRight then
					rowLine = rowLine .. " " .. string.rep(" ", widths[ci] - #cell) .. cell .. " │"
				else
					rowLine = rowLine .. " " .. cell .. string.rep(" ", widths[ci] - #cell) .. " │"
				end
			end
			print_line(rowLine)
		end
	end

	print_line(build_border("└", "┴", "┘"))
end

--[[
	Formats and lists the fields and values of a non-functional table/object into an ASCII grid layout.
	@param object { [any]: any } -- The target table/object.
]]--
function PrintUtil:PrintObject(object)
	local title = object.Name or object.ClassName or "Component"
	local columns = { "Field", "Value" }
	local rows = {}

	for k, v in object do
		if type(v) ~= "function" then
			table.insert(rows, { k, v })
		end
	end

	table.sort(rows, function(a, b)
		return tostring(a[1]) < tostring(b[1])
	end)

	PrintUtil:ListPrint(title, columns, rows)
end

return PrintUtil
