--!strict
--[[
    FileName    > Config.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 20/05/2026
--]]

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const TableUtil = require("./Utilities/TableUtil")

--
export type ScaleMode = "Fit" | "Height" | "Width" | "Diagonal"

export type StateMachineConfig = {
	ENABLED: boolean,
	AUTO_START_SERVER: boolean,
	AUTO_START_CLIENT: boolean,
	SYNC_CLIENT: boolean,
	CLIENT_UPDATE_MIN_INTERVAL: number?,
}

export type InterfaceConfig = {
	REFERENCE: Vector2,
	MODE: ScaleMode,
	MIN_SCALE: number,
	MAX_SCALE: number,
	DAMPING: number,
	TEN_FOOT_BOOST: number,
}

export type TouchConfig = {
	DEFAULT_ASSET: string,
	RECT_SIZE: Vector2,
	RECT_OFFSET_IDLE: Vector2,
	RECT_OFFSET_PRESSED: Vector2,
	LABEL_COLOR_IDLE: Color3,
	LABEL_COLOR_PRESSED: Color3,
	LABEL_TEXT_SIZE: number,
	OVERLAY_TRANSPARENCY: number,
	OVERLAY_PRESS_DELTA: number,
	OVERLAY_SCALE: number,
	OVERLAY_OFFSET: number,
	BASE_SIZE: number,
	DEFAULT_SIZE: number,
	MATCH_JUMP_SIZE: boolean,
	JUMP_BUTTON_EDITABLE: boolean,
	ZONE_PADDING: number,
	ZONE_MARGIN: number,
	DISPLAY_ORDER: number,
	DISABLED_TRANSPARENCY: number,
	AUTO_SCALE: boolean,
	MIN_SIZE: number,
	MAX_SIZE: number,
	EDIT_GRID: number,
	DRAG_THRESHOLD: number,
	EDIT_OUTLINE_COLOR: Color3,
	EDIT_OUTLINE_TRANSPARENCY: number,
	HANDLE_SIZE: number,
	HANDLE_ASSET: string,
	HANDLE_COLOR: Color3,
	LAYOUT_VERSION: number,
}

export type PathfindSchedulerConfig = {
	MAX_COMPUTES_PER_FRAME: number,
	MAX_CONCURRENT_COMPUTES: number,
}

export type Settings = {
	STATE_MACHINE: StateMachineConfig,
	INTERFACE: InterfaceConfig,
	TOUCH: TouchConfig,
	PATHFIND: PathfindSchedulerConfig,
	MODULE_LOAD_ORDER: { string },
}

export type ConfigEditType = {
	STATE_MACHINE: {
		ENABLED: boolean?,
		AUTO_START_SERVER: boolean?,
		AUTO_START_CLIENT: boolean?,
		SYNC_CLIENT: boolean?,
		CLIENT_UPDATE_MIN_INTERVAL: number?,
	}?,
	INTERFACE: {
		REFERENCE: Vector2?,
		MODE: ScaleMode?,
		MIN_SCALE: number?,
		MAX_SCALE: number?,
		DAMPING: number?,
		TEN_FOOT_BOOST: number?,
	}?,
	TOUCH: {
		DEFAULT_ASSET: string?,
		RECT_SIZE: Vector2?,
		RECT_OFFSET_IDLE: Vector2?,
		RECT_OFFSET_PRESSED: Vector2?,
		LABEL_COLOR_IDLE: Color3?,
		LABEL_COLOR_PRESSED: Color3?,
		LABEL_TEXT_SIZE: number?,
		OVERLAY_TRANSPARENCY: number?,
		OVERLAY_PRESS_DELTA: number?,
		OVERLAY_SCALE: number?,
		OVERLAY_OFFSET: number?,
		BASE_SIZE: number?,
		DEFAULT_SIZE: number?,
		MATCH_JUMP_SIZE: boolean?,
		JUMP_BUTTON_EDITABLE: boolean?,
		ZONE_PADDING: number?,
		ZONE_MARGIN: number?,
		DISPLAY_ORDER: number?,
		DISABLED_TRANSPARENCY: number?,
		AUTO_SCALE: boolean?,
		MIN_SIZE: number?,
		MAX_SIZE: number?,
		EDIT_GRID: number?,
		DRAG_THRESHOLD: number?,
		EDIT_OUTLINE_COLOR: Color3?,
		EDIT_OUTLINE_TRANSPARENCY: number?,
		HANDLE_SIZE: number?,
		HANDLE_ASSET: string?,
		HANDLE_COLOR: Color3?,
		LAYOUT_VERSION: number?,
	}?,
	PATHFIND: {
		MAX_COMPUTES_PER_FRAME: number?,
		MAX_CONCURRENT_COMPUTES: number?,
	}?,
	MODULE_LOAD_ORDER: { string }?,
}

export type ConfigModule = Settings & {
	Configure: (edit: ConfigEditType) -> (),
}
--

local function create_settings(): Settings
	return {
		STATE_MACHINE = {
			ENABLED = true,
			AUTO_START_SERVER = true,
			AUTO_START_CLIENT = true,
			SYNC_CLIENT = true,
		},
		INTERFACE = {
			REFERENCE = Vector2.new(1920, 1080),
			MODE = "Fit",
			MIN_SCALE = 0.5,
			MAX_SCALE = 2,
			DAMPING = 1,
			TEN_FOOT_BOOST = 1.25,
		},
		TOUCH = {
			DEFAULT_ASSET = "rbxassetid://16147465077",
			RECT_SIZE = Vector2.new(144, 144),
			RECT_OFFSET_IDLE = Vector2.new(1, 146),
			RECT_OFFSET_PRESSED = Vector2.new(146, 146),
			LABEL_COLOR_IDLE = Color3.fromRGB(200, 200, 200),
			LABEL_COLOR_PRESSED = Color3.fromRGB(55, 55, 55),
			LABEL_TEXT_SIZE = 14,
			OVERLAY_TRANSPARENCY = 0.3,
			OVERLAY_PRESS_DELTA = 0.2,
			OVERLAY_SCALE = 0,
			OVERLAY_OFFSET = 32,
			BASE_SIZE = 70,
			DEFAULT_SIZE = 70,
			MATCH_JUMP_SIZE = true,
			JUMP_BUTTON_EDITABLE = true,
			ZONE_PADDING = 8,
			ZONE_MARGIN = 16,
			DISPLAY_ORDER = -1,
			DISABLED_TRANSPARENCY = 0.6,
			AUTO_SCALE = false,
			MIN_SIZE = 40,
			MAX_SIZE = 160,
			EDIT_GRID = 0,
			DRAG_THRESHOLD = 6,
			EDIT_OUTLINE_COLOR = Color3.fromRGB(120, 200, 255),
			EDIT_OUTLINE_TRANSPARENCY = 0.2,
			HANDLE_SIZE = 16,
			HANDLE_ASSET = "rbxassetid://99822241004086",
			HANDLE_COLOR = Color3.fromRGB(120, 200, 255),
			LAYOUT_VERSION = 2,
		},
		PATHFIND = {
			MAX_COMPUTES_PER_FRAME = 4,
			MAX_CONCURRENT_COMPUTES = 12,
		},
		MODULE_LOAD_ORDER = {},
	}
end

--
const DEFAULTS = create_settings()
local Config = create_settings() :: ConfigModule
local Baseline: { [any]: any } = DEFAULTS :: any
--

local function is_plain_table(value: unknown): boolean
	return type(value) == "table" and getmetatable(value :: any) == nil
end

local function copy_value(value: any): any
	--
	if not is_plain_table(value) then
		return value
	end
	--

	return TableUtil.DeepClone(value)
end

local function merge_settings(base: { [any]: any }, edit: { [any]: any }): { [any]: any }
	--
	const merged = table.clone(base)
	--

	for key, value in edit do
		--
		const existing = base[key]

		if not is_plain_table(value) or not is_plain_table(existing) or #existing > 0 then
			merged[key] = copy_value(value)
			continue
		end
		--

		--
		merged[key] = merge_settings(existing, value)
		--
	end

	return merged
end

local function sync_table(target: { [any]: any }, source: { [any]: any }, prune: boolean)
	for key, value in source do
		--
		const existing = target[key]

		if not is_plain_table(value) or not is_plain_table(existing) then
			target[key] = copy_value(value)
			continue
		end
		--

		--
		sync_table(existing, value, true)
		--
	end

	--
	if not prune then
		return
	end
	--

	--
	for key in target do
		if source[key] ~= nil then
			continue
		end

		target[key] = nil
	end
	--
end

--[=[
	Applies a consumer configuration over Craftsman's baseline.

	The baseline is the built-in defaults with `ReplicatedStorage.CraftsmanConfig` applied on
	top. Each call merges from that baseline rather than from the current state, so calling
	this twice replaces the previous call instead of compounding with it, and an omitted field
	returns to its baseline value. `CraftsmanConfig` is never discarded. Arrays are replaced
	whole, never merged index by index.

	@param edit ConfigEditType -- The configuration to apply. Omitted fields keep their baseline value.
]=]
function Config.Configure(edit: ConfigEditType)
	sync_table(Config :: any, merge_settings(Baseline, edit :: any), false)
end

--
const consumer_config = ReplicatedStorage:FindFirstChild("CraftsmanConfig")

if consumer_config then
	Baseline = merge_settings(DEFAULTS :: any, require(consumer_config :: ModuleScript) :: any)
	Config.Configure({})
end
--

return Config
