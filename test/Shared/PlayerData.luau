--!nonstrict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Craftsman = require(ReplicatedStorage.Packages.Craftsman)

local Config = require(ReplicatedStorage.CraftsmanConfig)

local PlayerData = Craftsman.Store.CreatePlayerProducer(Config.DATA.TEMPLATE)({
	DispatchTestAction = function(state, value)
		return { TestField = value }
	end
})

return PlayerData
