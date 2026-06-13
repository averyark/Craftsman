--!nonstrict
--[[
    FileName    > PlayerData.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 13/06/2026
--]]

const Players = game:GetService("Players")

local Craftsman = require("@game/ReplicatedStorage/Packages/Craftsman")

local PlayerData = Craftsman.Store.CreatePlayerProducer({
	Coins = 0,
})({
	AddCoins = function(player_state, amount: number)
		return {
			Coins = (player_state.Coins or 0) + amount,
		}
	end,
	SetCoins = function(player_state, amount: number)
		return {
			Coins = amount,
		}
	end,
})
return PlayerData
