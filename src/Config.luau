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
	MODULE_LOAD_ORDER = {},
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[
	The consumer's state type, read from its GreenTea schema. Defining DATA.SCHEMA is the
	supported way to type player data: it is what gives Data and Market their real
	PlayerState instead of `any`.

	This is a *type-only* reach-through. `typeof(...)` is erased, so despite naming a module
	in the consumer's ReplicatedStorage it executes no require and does not stop Craftsman
	loading in a place that has no CraftsmanConfig -- which the runtime require below it used
	to do. A place without that module still runs; it just does not typecheck this line.
]]
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
	MODULE_LOAD_ORDER: { [any]: any },
	Configure: (edit: ConfigEditType) -> (),
}

local DEFAULTS = TableUtil.DeepClone(Config)

--[[
	Copies `source` over `target` without replacing any table it can merge into instead.

	Identity matters here: modules capture `Config` and its sub-tables when they require
	this module (`const StateMachineConfig = Config.STATE_MACHINE`). Assigning a fresh
	sub-table would leave every one of those holding a stale reference, so merge in place.
]]
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
--[[
	DATA.SCHEMA is how player data gets typed: PlayerState reads it, and Data and Market
	are typed off PlayerState. Without one it silently degrades to `any` -- silently
	because it fails in a type position under --!nonstrict, which is exactly how it went
	unnoticed. Only worth saying when DATA is actually on.
]]
local function warn_if_schema_missing()
	if Config.DATA.ENABLED and Config.DATA.SCHEMA == nil then
		PrintUtil:Warn(
			"DATA.ENABLED is true but DATA.SCHEMA is not set. Define a GreenTea schema so Data and Market can type PlayerState; without one it degrades to any."
		)
	end
end

function Config.Configure(edit: ConfigEditType)
	assign_in_place(Config, TableUtil.DeepMerge(DEFAULTS, edit :: any))
	warn_if_schema_missing()
end

--[[
	Craftsman used to hard-require ReplicatedStorage.CraftsmanConfig at module scope, so it
	could not load at all in a place that did not define that exact module at that exact
	path -- no defaults, no minimal consumer, no headless test.

	It is now optional: picked up when present, defaults when not. Existing consumers are
	unaffected, and Configure is available for anyone who would rather be explicit.
]]
local consumer_config = ReplicatedStorage:FindFirstChild("CraftsmanConfig")
if consumer_config then
	Config.Configure(require(consumer_config))
else
	warn_if_schema_missing()
end

return (Config :: any) :: ConfigModule
