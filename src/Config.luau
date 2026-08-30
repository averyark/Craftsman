--!nonstrict
--[[
    FileName    > Config.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 20/05/2026
--]]

const TableUtil = require("./Utilities/TableUtil")
const PrintUtil = require("./Utilities/PrintUtil")

local Config = {
	DATA = {
		ENABLED = true,
		STORE_NAME = "CraftsmanData",
		TEMPLATE = {
			Receipts = {},
		},
		SCHEMA = nil,
		BRIDGE_FOLDER_NAME = "CraftsmanDataBridge",
		AUTO_CREATE_BRIDGE = true,
		AUTO_START_SERVER = true,
		AUTO_START_CLIENT = true,
		LOAD_EXISTING_PLAYERS = true,
		LOAD_ON_PLAYER_ADDED = true,
		SAVE_ON_PLAYER_REMOVING = true,
		LOCK_SESSIONS = true,
		BIND_TO_CLOSE = true,
		OPEN_ATTEMPTS = 2,
	},
	MARKET = {
		ENABLED = true,
		AUTO_START_SERVER = true,
		AUTO_START_CLIENT = true,
		RECEIPTS_FIELD = "Receipts",
		KEYS = {},
		PRODUCTS = {},
		GAMEPASSES = {},
	},
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
	MODULE_LOAD_ORDER = {},
}

const ReplicatedStorage = game:GetService("ReplicatedStorage")

--
export type PlayerState = typeof(require(ReplicatedStorage.CraftsmanConfig).DATA.SCHEMA:type())

export type ConfigEditType = {
	DATA: {
		ENABLED: boolean?,
		STORE_NAME: string?,
		TEMPLATE: PlayerState?,
		SCHEMA: any?,
		BRIDGE_FOLDER_NAME: string?,
		AUTO_CREATE_BRIDGE: boolean?,
		AUTO_START_SERVER: boolean?,
		AUTO_START_CLIENT: boolean?,
		LOAD_EXISTING_PLAYERS: boolean?,
		LOAD_ON_PLAYER_ADDED: boolean?,
		SAVE_ON_PLAYER_REMOVING: boolean?,
		LOCK_SESSIONS: boolean?,
		BIND_TO_CLOSE: boolean?,
		OPEN_ATTEMPTS: number?,
	}?,
	MARKET: {
		ENABLED: boolean?,
		AUTO_START_SERVER: boolean?,
		AUTO_START_CLIENT: boolean?,
		RECEIPTS_FIELD: string?,
		KEYS: { [string]: number }?,
		PRODUCTS: { [any]: any }?,
		GAMEPASSES: { [any]: any }?,
	}?,
	STATE_MACHINE: {
		ENABLED: boolean?,
		AUTO_START_SERVER: boolean?,
		AUTO_START_CLIENT: boolean?,
		SYNC_CLIENT: boolean?,
	}?,
	INTERFACE: {
		REFERENCE: Vector2?,
		MODE: string?,
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
	MODULE_LOAD_ORDER: { [any]: any }?,
}

export type ConfigModule = {
	DATA: {
		ENABLED: boolean,
		STORE_NAME: string,
		TEMPLATE: PlayerState,
		SCHEMA: any?,
		BRIDGE_FOLDER_NAME: string,
		AUTO_CREATE_BRIDGE: boolean,
		AUTO_START_SERVER: boolean,
		AUTO_START_CLIENT: boolean,
		LOAD_EXISTING_PLAYERS: boolean,
		LOAD_ON_PLAYER_ADDED: boolean,
		SAVE_ON_PLAYER_REMOVING: boolean,
		LOCK_SESSIONS: boolean,
		BIND_TO_CLOSE: boolean,
		OPEN_ATTEMPTS: number,
	},
	MARKET: {
		ENABLED: boolean,
		AUTO_START_SERVER: boolean,
		AUTO_START_CLIENT: boolean,
		RECEIPTS_FIELD: string,
		KEYS: { [string]: number },
		PRODUCTS: { [any]: any },
		GAMEPASSES: { [any]: any },
	},
	STATE_MACHINE: {
		ENABLED: boolean,
		AUTO_START_SERVER: boolean,
		AUTO_START_CLIENT: boolean,
		SYNC_CLIENT: boolean,
	},
	INTERFACE: {
		REFERENCE: Vector2,
		MODE: string,
		MIN_SCALE: number,
		MAX_SCALE: number,
		DAMPING: number,
		TEN_FOOT_BOOST: number,
	},
	TOUCH: {
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
	},
	MODULE_LOAD_ORDER: { [any]: any },
	Configure: (edit: ConfigEditType) -> (),
}

local DEFAULTS = TableUtil.DeepClone(Config)

--
local function assign_in_place(target: { [any]: any }, source: { [any]: any })
	for key, value in source do
		local existing = target[key]
		if
			type(value) == "table"
			and getmetatable(value :: any) == nil
			and type(existing) == "table"
			and getmetatable(existing :: any) == nil
		then
			assign_in_place(existing, value)
		else
			target[key] = value
		end
	end
end

--[=[
	Applies a consumer configuration over Craftsman's defaults.

	Merges from the pristine defaults rather than from the current state, so calling this
	twice replaces the previous configuration instead of compounding with it -- an omitted
	field returns to its default rather than keeping the earlier call's value.

	One limit: a field with no default (`DATA.SCHEMA` is the only one) cannot be *cleared*
	by a later call, only overwritten. There is nothing to reset it to, and removing keys
	absent from the merge would take `Configure` itself with them.

	@param edit ConfigEditType -- The configuration to apply. Omitted fields keep their default.
]=]
--
local function warn_if_schema_missing()
	if not Config.DATA.ENABLED or Config.DATA.SCHEMA ~= nil then
		return
	end

	PrintUtil:Warn(
		"DATA.ENABLED is true but DATA.SCHEMA is not set. Define a GreenTea schema so Data and Market can type PlayerState; without one it degrades to any."
	)
end

function Config.Configure(edit: ConfigEditType)
	assign_in_place(Config, TableUtil.DeepMerge(DEFAULTS, edit :: any))
	warn_if_schema_missing()
end

--
local consumer_config = ReplicatedStorage:FindFirstChild("CraftsmanConfig")
if consumer_config then
	Config.Configure(require(consumer_config))
else
	warn_if_schema_missing()
end

return (Config :: any) :: ConfigModule
