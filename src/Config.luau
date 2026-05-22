--!nonstrict
--[[
    FileName    > Config.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 20/05/2026
--]]

local KEYS = {
	-- Products
	Add100Coins = 3596765117,
	Add1000Coins = 3596766189,

	-- Gamepasses
	Multiply10Coins = 1853669482,
	Multiply2Coins = 1854485439,
}

local Config = {
	DATA = {
		ENABLED = true,
		STORE_NAME = "CraftsmanData",
		TEMPLATE = {
			Receipts = {},
			Permissions = {},
			Coins = 0,
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
		KEYS = KEYS,
		PRODUCTS = {
			[KEYS.Add100Coins] = "Add100Coins",
			[KEYS.Add1000Coins] = "Add1000Coins",
		},
		GAMEPASSES = {
			[KEYS.Multiply10Coins] = "Multiply10Coins",
			[KEYS.Multiply2Coins] = "Multiply2Coins",
		},
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

export type ConfigEditType = {
	DATA: {
		ENABLED: boolean?,
		STORE_NAME: string?,
		TEMPLATE: typeof(Config.DATA.TEMPLATE)?,
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
		TEMPLATE: typeof(Config.DATA.TEMPLATE),
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
		KEYS: typeof(KEYS),
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
