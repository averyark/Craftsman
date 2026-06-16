--!nonstrict
--[[
    FileName    > CraftsmanConfig.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 23/05/2026
--]]

const gt = require(game.ReplicatedStorage.Packages.gt)

local KEYS = {
	-- Products

	-- Gamepasses
}

local PRODUCTS = {
}

local GAMEPASSES = {
}

local TEMPLATE = {

}

local SCHEMA = gt.build(gt.table({

}))

return {
	MARKET = {
		KEYS = KEYS,
		PRODUCTS = PRODUCTS,
		GAMEPASSES = GAMEPASSES,
	},
	DATA = {
		TEMPLATE = TEMPLATE,
		SCHEMA = SCHEMA,
	},
}
