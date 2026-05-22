--!nonstrict
--[[
    FileName    > Config.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 20/05/2026
--]]

local Config = {
	DATA = {
		ENABLED = true,
		STORE_NAME = "CraftsmanData",
		TEMPLATE = {
			Receipts = {},
			Permissions = {},
		},
		BRIDGE_FOLDER_NAME = "CraftsmanDataBridge",
		STATE_EVENT_NAME = "StateUpdated",
		REQUEST_FUNCTION_NAME = "RequestState",
		AUTO_CREATE_BRIDGE = true,
		AUTO_START_SERVER = true,
		AUTO_START_CLIENT = true,
		LOAD_EXISTING_PLAYERS = true,
		LOAD_ON_PLAYER_ADDED = true,
		SAVE_ON_PLAYER_REMOVING = true,
		SYNC_CLIENT = true,
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
	MODULE_LOAD_ORDER = {},
}

local function merge_tables(target, source)
	for k, v in next, source do
		if type(v) == "table" and type(target[k]) == "table" then
			merge_tables(target[k], v)
		else
			target[k] = v
		end
	end
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
export type PlayerState = typeof(require(ReplicatedStorage.CraftsmanConfig).TEMPLATE)

export type ConfigEditType = {
	DATA: {
		ENABLED: boolean?,
		STORE_NAME: string?,
		TEMPLATE: PlayerState?,
		BRIDGE_FOLDER_NAME: string?,
		STATE_EVENT_NAME: string?,
		REQUEST_FUNCTION_NAME: string?,
		AUTO_CREATE_BRIDGE: boolean?,
		AUTO_START_SERVER: boolean?,
		AUTO_START_CLIENT: boolean?,
		LOAD_EXISTING_PLAYERS: boolean?,
		LOAD_ON_PLAYER_ADDED: boolean?,
		SAVE_ON_PLAYER_REMOVING: boolean?,
		SYNC_CLIENT: boolean?,
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
	MODULE_LOAD_ORDER: { [any]: any }?,
}

export type ConfigModule = {
	DATA: {
		ENABLED: boolean,
		STORE_NAME: string,
		TEMPLATE: PlayerState,
		BRIDGE_FOLDER_NAME: string,
		STATE_EVENT_NAME: string,
		REQUEST_FUNCTION_NAME: string,
		AUTO_CREATE_BRIDGE: boolean,
		AUTO_START_SERVER: boolean,
		AUTO_START_CLIENT: boolean,
		LOAD_EXISTING_PLAYERS: boolean,
		LOAD_ON_PLAYER_ADDED: boolean,
		SAVE_ON_PLAYER_REMOVING: boolean,
		SYNC_CLIENT: boolean,
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
	MODULE_LOAD_ORDER: { [any]: any },
	Edit: (self: ConfigModule, changes: ConfigEditType) -> (),
}

function Config:Edit(changes: ConfigEditType)
	merge_tables(Config, changes)
end

return (Config :: any) :: ConfigModule
