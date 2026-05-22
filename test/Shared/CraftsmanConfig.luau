--!nonstrict
--[[
    FileName    > CraftsmanConfig.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 23/05/2026
--]]

const Craftsman = require("@game/ReplicatedStorage/Packages/Craftsman")

local KEYS = {
	-- Products
	Add100Coins = 3596765117,
	Add1000Coins = 3596766189,

	-- Gamepasses
	Multiply10Coins = 1853669482,
	Multiply2Coins = 1854485439,
}

local PRODUCTS = {
	[KEYS.Add100Coins] = "Add100Coins",
	[KEYS.Add1000Coins] = "Add1000Coins",
}

local GAMEPASSES = {
	[KEYS.Multiply10Coins] = "Multiply10Coins",
	[KEYS.Multiply2Coins] = "Multiply2Coins",
}

local TEMPLATE = {
	Receipts = {},
	Permissions = {},
	Coins = 0,
}

Craftsman.Config:Edit({
	DATA = {
		TEMPLATE = TEMPLATE,
	},
	MARKET = {
		KEYS = KEYS,
		PRODUCTS = PRODUCTS,
		GAMEPASSES = GAMEPASSES,
	},
})

return {
	KEYS = KEYS,
	PRODUCTS = PRODUCTS,
	GAMEPASSES = GAMEPASSES,
	TEMPLATE = TEMPLATE,
}
