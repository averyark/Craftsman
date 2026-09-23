--!strict
--[[
    FileName    > PrintUtil.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 20/05/2026
--]]

const Inspect = require("../Inspect")

--[=[
	@class PrintUtil
	A printing utility for rich formatting and structured table output.
]=]
local PrintUtil = {}

local function format_two_decimals(value: number): string
	--
	const sign = value < 0 and "-" or ""
	const scaled = math.floor(math.abs(value) * 100 + 0.5)
	const integer_part = math.floor(scaled / 100)
	const fraction_text = tostring(scaled - integer_part * 100)
	const padding = string.rep("0", 2 - #fraction_text)
	--

	return `{sign}{integer_part}.{padding}{fraction_text}`
end

local function flush_line(lines: { string }, current_line: string)
	--
	if #current_line == 0 then
		return
	end
	--

	table.insert(lines, current_line)
end

local function push_word_chunks(lines: { string }, word: string, max_len: number): string
	--
	local temp = word

	while #temp > max_len do
		table.insert(lines, string.sub(temp, 1, max_len))
		temp = string.sub(temp, max_len + 1)
	end
	--

	return temp
end

local function wrap_text(str: string, max_len: number): { string }
	--
	const lines: { string } = {}
	const raw_lines = string.split(str, "\n")
	--

	for _, line in raw_lines do
		--
		if #line <= max_len then
			table.insert(lines, line)
			continue
		end
		--

		--
		local current_line = ""

		for word in string.gmatch(line, "%S+") do
			if #word > max_len then
				flush_line(lines, current_line)
				current_line = push_word_chunks(lines, word, max_len)
				continue
			end

			const space = #current_line > 0 and " " or ""

			if #current_line + #space + #word > max_len then
				table.insert(lines, current_line)
				current_line = word
				continue
			end

			current_line = `{current_line}{space}{word}`
		end
		--

		--
		flush_line(lines, current_line)
		--
	end

	--
	if #lines == 0 then
		table.insert(lines, "")
	end
	--

	return lines
end

local function is_array(t: any): boolean
	return type(t) == "table" and #t > 0
end

local function is_row_object(value: any, headers: { string }): boolean
	--
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return false
	end
	--

	--
	for j = 2, #headers do
		if value[headers[j]] == nil then
			continue
		end

		return true
	end
	--

	return false
end

local function build_row(key: any, value: any, headers: { string }): { any }
	--
	const row = {}
	row[1] = key

	for j = 2, #headers do
		const h = headers[j]
		row[j] = value[h]
	end
	--

	return row
end

local function collect_rows(rows: { [any]: any }, headers: { string }): { any }
	--
	const row_list = {}
	--

	--
	if is_array(rows) then
		for _, r in rows do
			row_list[#row_list + 1] = r
		end

		return row_list
	end
	--

	--
	for k, v in rows do
		if not is_row_object(v, headers) then
			row_list[#row_list + 1] = { k, v }
			continue
		end

		row_list[#row_list + 1] = build_row(k, v, headers)
	end
	--

	return row_list
end

local function format_cell(value: any): string
	--
	if value == nil then
		return ""
	end

	if type(value) == "number" and value % 1 == 0 then
		return tostring(value)
	end

	if type(value) == "number" then
		return format_two_decimals(value)
	end

	if type(value) == "table" then
		return Inspect(value)
	end
	--

	return tostring(value)
end

local function build_title_lines(title: string, widths: { number }, col_count: number): { string }
	--
	if title == "" then
		return { "" }
	end
	--

	--
	const title_str = tostring(title)
	const title_display = `  {title_str}`

	local sum_widths = 0

	for i = 1, col_count do
		sum_widths = sum_widths + (widths[i] or 0)
	end
	--

	--
	const table_len = sum_widths + 3 * col_count + 3
	const desired_len = math.max(table_len, #title_display)
	const equals_line = `  {string.rep("=", math.max(0, desired_len - 2))}`
	--

	return { "\n", equals_line, title_display, equals_line }
end

--[=[
	Prints a beautifully formatted ASCII table representing row and column data with dynamic wrapping and borders.
	@param title string -- The title header of the table.
	@param columns { string | { name: string } } -- The headers or definitions for each column.
	@param rows { { any } | { [string]: any } } -- The row data elements (can be arrays of values or dictionaries of fields).
	@param max_width number? -- The maximum character width of each cell column before word wrapping occurs (defaults to 45).
]=]
function PrintUtil:ListPrint(title: string?, columns: { any }?, rows: { [any]: any }?, max_width: number?)
	--
	const title = title or ""
	const columns = columns or {}
	const rows = rows or {}
	const max_width = max_width or 45
	--

	--
	local print_count = 0

	local function print_line(s)
		print_count = print_count + 1
		print(`{s}{string.rep(utf8.char(0x200B), print_count % 3)}`)
	end
	--

	--
	const headers: { string } = {}

	for i, col in columns do
		if type(col) ~= "table" then
			headers[i] = tostring(col)
			continue
		end

		headers[i] = tostring(col.name or col.header or col[1] or "")
	end
	--

	--
	const row_list = collect_rows(rows, headers)
	--

	--
	local col_count = #headers

	if col_count == 0 then
		for _, r in row_list do
			col_count = math.max(col_count, #r)
		end

		for i = 1, col_count do
			headers[i] = headers[i] or `Column {i}`
		end
	end
	--

	--
	const widths = {}

	for i = 1, col_count do
		widths[i] = #tostring(headers[i])
	end
	--

	--
	const formatted = {}

	for ri, r in row_list do
		formatted[ri] = {}

		for ci = 1, col_count do
			const cell_lines = wrap_text(format_cell(r[ci]), max_width)
			formatted[ri][ci] = cell_lines

			for _, cell_line in cell_lines do
				const len = #cell_line

				if len <= widths[ci] then
					continue
				end

				widths[ci] = len
			end
		end
	end
	--

	--
	for _, title_line in build_title_lines(title, widths, col_count) do
		print_line(title_line)
	end
	--

	--
	local function build_border(left, mid, right)
		local out = `  {left}`

		for i = 1, col_count do
			out = `{out}{string.rep("─", widths[i] + 2)}`
			out = `{out}{if i < col_count then mid else right}`
		end

		return out
	end
	--

	--
	print_line(build_border("┌", "┬", "┐"))

	local header_line = "  │"

	for i = 1, col_count do
		const h = headers[i] or ""
		header_line = `{header_line} {h}{string.rep(" ", widths[i] - #h)} │`
	end

	print_line(header_line)
	print_line(build_border("├", "┼", "┤"))
	--

	for ri, formatted_row in formatted do
		--
		local max_lines = 1

		for ci = 1, col_count do
			max_lines = math.max(max_lines, #formatted_row[ci])
		end
		--

		--
		for li = 1, max_lines do
			local row_line = "  │"

			for ci = 1, col_count do
				const cell_lines = formatted_row[ci]
				const cell = cell_lines[li] or ""
				const orig = row_list[ri] and row_list[ri][ci]
				const padding = string.rep(" ", widths[ci] - #cell)

				if type(orig) == "number" then
					row_line = `{row_line} {padding}{cell} │`
					continue
				end

				row_line = `{row_line} {cell}{padding} │`
			end

			print_line(row_line)
		end
		--
	end

	print_line(build_border("└", "┴", "┘"))
end

--[=[
	Formats and lists the fields and values of a non-functional table/object into an ASCII grid layout.
	@param object { [any]: any } -- The target table/object.
]=]
function PrintUtil:PrintObject(object: { [any]: any })
	--
	const title = object.Name or object.ClassName or "Component"
	const columns = { "Field", "Value" }
	const rows: { { any } } = {}
	--

	--
	for k, v in object do
		if type(v) == "function" then
			continue
		end

		table.insert(rows, { k, v })
	end

	table.sort(rows, function(a, b)
		return tostring(a[1]) < tostring(b[1])
	end)
	--

	PrintUtil:ListPrint(title, columns, rows)
end

return PrintUtil
