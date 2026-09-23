--!strict
--[[
    FileName    > Inspect.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 23/09/2026
    Credits     > Ozzypig (repr v1.2)
--]]

--
export type Settings = {
	Pretty: boolean?,
	Indent: string?,
	Semicolons: boolean?,
	SortKeys: boolean?,
	MaxDepth: number?,
	MaxItems: number?,
	Precision: number?,
	FullName: boolean?,
	ProperFullName: boolean?,
	ClassName: boolean?,
	Metamethods: boolean?,
}

type Options = {
	Pretty: boolean,
	Indent: string,
	Separator: string,
	SortKeys: boolean,
	MaxDepth: number,
	MaxItems: number,
	Precision: number,
	FullName: boolean,
	ProperFullName: boolean,
	ClassName: boolean,
	Metamethods: boolean,
	Indents: { [number]: string },
}

type Context = {
	Options: Options,
	Parts: { string },
	Seen: { [any]: boolean },
}

type Formatter = (value: any, options: Options) -> string
--

--
const KEYWORDS: { [string]: boolean } = {
	["and"] = true,
	["break"] = true,
	["do"] = true,
	["else"] = true,
	["elseif"] = true,
	["end"] = true,
	["false"] = true,
	["for"] = true,
	["function"] = true,
	["if"] = true,
	["in"] = true,
	["local"] = true,
	["nil"] = true,
	["not"] = true,
	["or"] = true,
	["repeat"] = true,
	["return"] = true,
	["then"] = true,
	["true"] = true,
	["until"] = true,
	["while"] = true,
}

const KEY_RANKS: { [string]: number } = {
	number = 1,
	string = 2,
	boolean = 3,
}

const AXIS_NAMES = { "X", "Y", "Z" }
const FACE_NAMES = { "Right", "Top", "Back", "Left", "Bottom", "Front" }
--

--
const ESCAPES: { [string]: string } = {
	["\""] = "\\\"",
	["\\"] = "\\\\",
	["\n"] = "\\n",
	["\r"] = "\\r",
	["\t"] = "\\t",
	["\127"] = "\\127",
}

for code = 0, 31 do
	const char = string.char(code)

	if ESCAPES[char] then
		continue
	end

	ESCAPES[char] = `\\{string.rep("0", 3 - #tostring(code))}{code}`
end
--

--
const DEFAULT_PRECISION = 7
const DEFAULT_INDENT = "\t"
--

local function is_identifier(key: unknown): boolean
	return type(key) == "string" and string.match(key, "^[%a_][%w_]*$") ~= nil and not KEYWORDS[key]
end

local function quote_string(value: string): string
	--
	if not string.find(value, "[%c\"\\]") then
		return `"{value}"`
	end
	--

	--
	const escaped = string.gsub(value, "[%c\"\\]", ESCAPES)
	--

	return `"{escaped}"`
end

local function format_number(value: number): string
	--
	if value ~= value then
		return "0/0"
	end

	if value == math.huge then
		return "math.huge"
	end

	if value == -math.huge then
		return "-math.huge"
	end
	--

	return tostring(value)
end

local function round_significant(value: number, digits: number): number
	--
	if value == 0 or value ~= value or math.abs(value) == math.huge then
		return value
	end
	--

	--
	const shift = digits - math.floor(math.log10(math.abs(value))) - 1

	if math.abs(shift) > 22 then
		return value
	end

	if shift >= 0 then
		const scale = 10 ^ shift
		return math.round(value * scale) / scale
	end
	--

	--
	const scale = 10 ^ -shift
	--

	return math.round(value / scale) * scale
end

local function format_float(value: number, options: Options): string
	return format_number(round_significant(value, options.Precision))
end

local function format_unit(value: number, options: Options): string
	--
	const scale = 10 ^ options.Precision
	--

	return format_number(math.round(value * scale) / scale + 0)
end

local function join<T>(values: { T }, formatter: (T, Options) -> string, options: Options): string
	--
	const parts = table.create(#values)

	for _, value in values do
		table.insert(parts, formatter(value, options))
	end
	--

	return table.concat(parts, ", ")
end

local function to_byte(channel: number): number?
	--
	const scaled = channel * 255
	const rounded = math.round(scaled)

	if rounded < 0 or rounded > 255 or math.abs(scaled - rounded) > 1e-3 then
		return nil
	end
	--

	return rounded
end

local function format_flags(value: any, names: { string }, prefix: string): string
	--
	const enabled = {}

	for _, name in names do
		if not value[name] then
			continue
		end

		table.insert(enabled, `{prefix}.{name}`)
	end
	--

	return table.concat(enabled, ", ")
end

local function proper_full_name(instance: Instance): string
	--
	local path = ""
	local current: Instance? = instance

	while current and current ~= game do
		const name = current.Name
		path = if is_identifier(name) then `.{name}{path}` else `[{quote_string(name)}]{path}`
		current = current.Parent
	end
	--

	--
	if path == "" then
		return instance.Name
	end

	if string.sub(path, 1, 1) ~= "." then
		return path
	end
	--

	return string.sub(path, 2)
end

local function format_instance(value: Instance, options: Options): string
	--
	const name = if not options.FullName
		then value.Name
		elseif options.ProperFullName then proper_full_name(value)
		else value:GetFullName()

	if not options.ClassName then
		return name
	end
	--

	return `{name} ({value.ClassName})`
end

local function format_function(value: (...any) -> ...any, _options: Options): string
	--
	const source, line, name = debug.info(value, "sln")
	const label = if name == nil or name == "" then "anonymous" else name

	if source == "[C]" or line == nil or line < 0 then
		return `<function {label}>`
	end
	--

	--
	const path = string.gsub(source, "^[@=]", "")
	--

	return `<function {label} @ {path}:{line}>`
end

local function format_enum_item(value: EnumItem, _options: Options): string
	return tostring(value)
end

local function format_vector3(value: Vector3, options: Options): string
	--
	if value == Vector3.zero then
		return "Vector3.zero"
	end

	if value == Vector3.one then
		return "Vector3.one"
	end
	--

	return `Vector3.new({join({ value.X, value.Y, value.Z }, format_float, options)})`
end

local function format_vector2(value: Vector2, options: Options): string
	--
	if value == Vector2.zero then
		return "Vector2.zero"
	end

	if value == Vector2.one then
		return "Vector2.one"
	end
	--

	return `Vector2.new({format_float(value.X, options)}, {format_float(value.Y, options)})`
end

local function format_vector3int16(value: Vector3int16, _options: Options): string
	return `Vector3int16.new({value.X}, {value.Y}, {value.Z})`
end

local function format_color3(value: Color3, options: Options): string
	--
	const r, g, b = to_byte(value.R), to_byte(value.G), to_byte(value.B)

	if r == nil or g == nil or b == nil then
		return `Color3.new({join({ value.R, value.G, value.B }, format_float, options)})`
	end
	--

	return `Color3.fromRGB({r}, {g}, {b})`
end

local function format_color_keypoint(value: ColorSequenceKeypoint, options: Options): string
	return `ColorSequenceKeypoint.new({format_float(value.Time, options)}, {format_color3(value.Value, options)})`
end

local function format_number_keypoint(value: NumberSequenceKeypoint, options: Options): string
	--
	const time = format_float(value.Time, options)
	const number = format_float(value.Value, options)

	if value.Envelope == 0 then
		return `NumberSequenceKeypoint.new({time}, {number})`
	end
	--

	return `NumberSequenceKeypoint.new({time}, {number}, {format_float(value.Envelope, options)})`
end

local function format_cframe(value: CFrame, options: Options): string
	--
	if value == CFrame.identity then
		return "CFrame.identity"
	end

	if value.Rotation == CFrame.identity then
		return `CFrame.new({join({ value.X, value.Y, value.Z }, format_float, options)})`
	end
	--

	--
	const x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = value:GetComponents()
	const position = join({ x, y, z }, format_float, options)
	const rotation = join({ r00, r01, r02, r10, r11, r12, r20, r21, r22 }, format_unit, options)
	--

	return `CFrame.new({position}, {rotation})`
end

local function format_udim2(value: UDim2, options: Options): string
	--
	const x, y = value.X, value.Y

	if x.Offset == 0 and y.Offset == 0 then
		return `UDim2.fromScale({format_float(x.Scale, options)}, {format_float(y.Scale, options)})`
	end

	if x.Scale == 0 and y.Scale == 0 then
		return `UDim2.fromOffset({x.Offset}, {y.Offset})`
	end
	--

	return `UDim2.new({format_float(x.Scale, options)}, {x.Offset}, {format_float(y.Scale, options)}, {y.Offset})`
end

local function format_color_sequence(value: ColorSequence, options: Options): string
	--
	const keypoints = value.Keypoints
	const head, tail = keypoints[1], keypoints[#keypoints]

	if #keypoints > 2 then
		return `ColorSequence.new(\{{join(keypoints, format_color_keypoint, options)}})`
	end

	if head.Value == tail.Value then
		return `ColorSequence.new({format_color3(head.Value, options)})`
	end
	--

	return `ColorSequence.new({format_color3(head.Value, options)}, {format_color3(tail.Value, options)})`
end

local function format_number_sequence(value: NumberSequence, options: Options): string
	--
	const keypoints = value.Keypoints
	const head, tail = keypoints[1], keypoints[#keypoints]

	if #keypoints > 2 or head.Envelope ~= 0 or tail.Envelope ~= 0 then
		return `NumberSequence.new(\{{join(keypoints, format_number_keypoint, options)}})`
	end

	if head.Value == tail.Value then
		return `NumberSequence.new({format_float(head.Value, options)})`
	end
	--

	return `NumberSequence.new({format_float(head.Value, options)}, {format_float(tail.Value, options)})`
end

local function format_raycast_result(value: RaycastResult, options: Options): string
	--
	const target = if value.Instance then format_instance(value.Instance, options) else "nil"
	const position = format_vector3(value.Position, options)
	const normal = format_vector3(value.Normal, options)
	const distance = format_float(value.Distance, options)
	--

	return `<RaycastResult Instance = {target}, Position = {position}, Normal = {normal}, Material = {value.Material}, Distance = {distance}>`
end

const FORMATTERS: { [string]: Formatter } = {
	--
	["nil"] = function(_value: nil, _options: Options): string
		return "nil"
	end,

	boolean = function(value: boolean, _options: Options): string
		return if value then "true" else "false"
	end,

	number = function(value: number, _options: Options): string
		return format_number(value)
	end,

	string = function(value: string, _options: Options): string
		return quote_string(value)
	end,

	["function"] = format_function,

	thread = function(value: thread, _options: Options): string
		return `<thread {coroutine.status(value)}>`
	end,

	buffer = function(value: buffer, _options: Options): string
		return `<buffer {buffer.len(value)} bytes>`
	end,
	--

	--
	Instance = format_instance,

	RBXScriptConnection = function(value: RBXScriptConnection, _options: Options): string
		return if value.Connected then "<RBXScriptConnection connected>" else "<RBXScriptConnection disconnected>"
	end,

	RBXScriptSignal = function(value: RBXScriptSignal, _options: Options): string
		return `<{tostring(value)}>`
	end,

	RaycastResult = format_raycast_result,
	--

	--
	Enums = function(_value: any, _options: Options): string
		return "Enum"
	end,

	Enum = function(value: Enum, _options: Options): string
		return `Enum.{tostring(value)}`
	end,

	EnumItem = format_enum_item,

	Axes = function(value: Axes, _options: Options): string
		return `Axes.new({format_flags(value, AXIS_NAMES, "Enum.Axis")})`
	end,

	Faces = function(value: Faces, _options: Options): string
		return `Faces.new({format_flags(value, FACE_NAMES, "Enum.NormalId")})`
	end,
	--

	--
	Vector2 = format_vector2,
	Vector3 = format_vector3,
	Vector3int16 = format_vector3int16,
	CFrame = format_cframe,

	Vector2int16 = function(value: Vector2int16, _options: Options): string
		return `Vector2int16.new({value.X}, {value.Y})`
	end,

	Ray = function(value: Ray, options: Options): string
		return `Ray.new({format_vector3(value.Origin, options)}, {format_vector3(value.Direction, options)})`
	end,

	Region3 = function(value: Region3, options: Options): string
		--
		const center = value.CFrame.Position
		const extents = value.Size / 2
		--

		return `Region3.new({format_vector3(center - extents, options)}, {format_vector3(center + extents, options)})`
	end,

	Region3int16 = function(value: Region3int16, options: Options): string
		return `Region3int16.new({format_vector3int16(value.Min, options)}, {format_vector3int16(value.Max, options)})`
	end,

	Rect = function(value: Rect, options: Options): string
		return `Rect.new({join({ value.Min.X, value.Min.Y, value.Max.X, value.Max.Y }, format_float, options)})`
	end,

	PathWaypoint = function(value: PathWaypoint, options: Options): string
		--
		const position = format_vector3(value.Position, options)
		const action = format_enum_item(value.Action, options)

		if value.Label == "" then
			return `PathWaypoint.new({position}, {action})`
		end
		--

		return `PathWaypoint.new({position}, {action}, {quote_string(value.Label)})`
	end,
	--

	--
	UDim2 = format_udim2,

	UDim = function(value: UDim, options: Options): string
		return `UDim.new({format_float(value.Scale, options)}, {value.Offset})`
	end,

	Font = function(value: Font, _options: Options): string
		return `Font.new({quote_string(value.Family)}, {value.Weight}, {value.Style})`
	end,
	--

	--
	Color3 = format_color3,
	ColorSequence = format_color_sequence,
	ColorSequenceKeypoint = format_color_keypoint,
	NumberSequence = format_number_sequence,
	NumberSequenceKeypoint = format_number_keypoint,

	BrickColor = function(value: BrickColor, _options: Options): string
		return `BrickColor.new({quote_string(value.Name)})`
	end,

	NumberRange = function(value: NumberRange, options: Options): string
		--
		if value.Min == value.Max then
			return `NumberRange.new({format_float(value.Min, options)})`
		end
		--

		return `NumberRange.new({format_float(value.Min, options)}, {format_float(value.Max, options)})`
	end,
	--

	--
	TweenInfo = function(value: TweenInfo, options: Options): string
		--
		const time = format_float(value.Time, options)
		const delay = format_float(value.DelayTime, options)
		--

		return `TweenInfo.new({time}, {value.EasingStyle}, {value.EasingDirection}, {value.RepeatCount}, {value.Reverses}, {delay})`
	end,

	PhysicalProperties = function(value: PhysicalProperties, options: Options): string
		--
		const components = {
			value.Density,
			value.Friction,
			value.Elasticity,
			value.FrictionWeight,
			value.ElasticityWeight,
		}
		--

		return `PhysicalProperties.new({join(components, format_float, options)})`
	end,

	DateTime = function(value: DateTime, _options: Options): string
		return `DateTime.fromIsoDate("{value:ToIsoDate()}")`
	end,

	Random = function(_value: Random, _options: Options): string
		return "<Random>"
	end,

	DockWidgetPluginGuiInfo = function(value: any, _options: Options): string
		return `DockWidgetPluginGuiInfo.new({value.InitialDockState}, {value.InitialEnabled}, {value.InitialEnabledShouldOverrideRestore}, {value.FloatingXSize}, {value.FloatingYSize}, {value.MinWidth}, {value.MinHeight})`
	end,
	--
}

local function format_leaf(value: unknown, options: Options): string
	--
	const kind = typeof(value)
	const formatter = FORMATTERS[kind]

	if formatter == nil then
		return `<{kind}>`
	end
	--

	return formatter(value, options)
end

local function call_tostring(tbl: { [any]: any }): string?
	--
	const metatable: unknown = getmetatable(tbl)

	if type(metatable) ~= "table" then
		return nil
	end

	const method: unknown = rawget(metatable :: { [any]: any }, "__tostring")

	if type(method) ~= "function" then
		return nil
	end
	--

	--
	const ok, result = pcall(method :: (any) -> any, tbl)

	if not ok then
		return nil
	end
	--

	return tostring(result)
end

local function compare_keys(a: any, b: any): boolean
	--
	const type_a, type_b = type(a), type(b)

	if type_a ~= type_b then
		return (KEY_RANKS[type_a] or 4) < (KEY_RANKS[type_b] or 4)
	end
	--

	--
	if type_a == "number" or type_a == "string" then
		return a < b
	end

	if type_a == "boolean" then
		return not a and b
	end
	--

	return false
end

local function split_keys(tbl: { [any]: any }): (number, { any })
	--
	const length = rawlen(tbl)
	const keys = {}
	local counted = 0
	--

	--
	for key in next, tbl do
		if type(key) == "number" and key >= 1 and key <= length and key % 1 == 0 then
			counted += 1
			continue
		end

		table.insert(keys, key)
	end
	--

	--
	if counted == length then
		return length, keys
	end
	--

	--
	for index = 1, length do
		if rawget(tbl, index) == nil then
			continue
		end

		table.insert(keys, index)
	end
	--

	return 0, keys
end

local function get_indent(options: Options, depth: number): string
	--
	const cached = options.Indents[depth]

	if cached then
		return cached
	end
	--

	--
	const indent = `\n{string.rep(options.Indent, depth)}`
	options.Indents[depth] = indent
	--

	return indent
end

local function write(ctx: Context, value: unknown, depth: number)
	--
	if type(value) ~= "table" then
		table.insert(ctx.Parts, format_leaf(value, ctx.Options))
		return
	end
	--

	--
	const tbl = value :: { [any]: any }
	const options = ctx.Options
	const parts = ctx.Parts
	const custom = if options.Metamethods then call_tostring(tbl) else nil

	if custom then
		table.insert(parts, custom)
		return
	end

	if ctx.Seen[tbl] then
		table.insert(parts, "<cycle>")
		return
	end

	if depth >= options.MaxDepth then
		table.insert(parts, "{...}")
		return
	end
	--

	--
	const length, keys = split_keys(tbl)
	const total = length + #keys

	if total == 0 then
		table.insert(parts, "{}")
		return
	end
	--

	--
	if options.SortKeys then
		table.sort(keys, compare_keys)
	end

	const first = if options.Pretty then get_indent(options, depth + 1) else ""
	const rest = `{options.Separator}{if options.Pretty then first else " "}`
	const shown = math.min(total, options.MaxItems)
	local lead = first

	ctx.Seen[tbl] = true
	table.insert(parts, "{")
	--

	--
	for index = 1, math.min(length, shown) do
		table.insert(parts, lead)
		write(ctx, rawget(tbl, index), depth + 1)
		lead = rest
	end
	--

	--
	for position, key in keys do
		if length + position > shown then
			break
		end

		const bare = is_identifier(key)

		table.insert(parts, lead)
		table.insert(parts, if bare then key else "[")

		if not bare then
			write(ctx, key, depth + 1)
			table.insert(parts, "]")
		end

		table.insert(parts, " = ")
		write(ctx, rawget(tbl, key), depth + 1)
		lead = rest
	end
	--

	--
	if shown < total then
		table.insert(parts, lead)
		table.insert(parts, `<{total - shown} more>`)
	end

	ctx.Seen[tbl] = nil
	table.insert(parts, if options.Pretty then get_indent(options, depth) else "")
	table.insert(parts, "}")
	--
end

local function resolve_options(settings: Settings): Options
	return {
		Pretty = settings.Pretty == true,
		Indent = settings.Indent or DEFAULT_INDENT,
		Separator = if settings.Semicolons then ";" else ",",
		SortKeys = settings.SortKeys ~= false,
		MaxDepth = settings.MaxDepth or math.huge,
		MaxItems = settings.MaxItems or math.huge,
		Precision = settings.Precision or DEFAULT_PRECISION,
		FullName = settings.FullName == true,
		ProperFullName = settings.ProperFullName ~= false,
		ClassName = settings.ClassName ~= false,
		Metamethods = settings.Metamethods ~= false,
		Indents = {},
	}
end

const DEFAULT_OPTIONS = resolve_options({})

local function Inspect(value: unknown, settings: Settings?): string
	--
	const options = if settings then resolve_options(settings) else DEFAULT_OPTIONS

	if type(value) ~= "table" then
		return format_leaf(value, options)
	end
	--

	--
	const ctx: Context = {
		Options = options,
		Parts = {},
		Seen = {},
	}

	write(ctx, value, 0)
	--

	return table.concat(ctx.Parts)
end

return Inspect
