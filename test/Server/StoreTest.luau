--!nonstrict
--[[
    FileName    > StoreTest.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 13/06/2026
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

const Craftsman = require("@game/ReplicatedStorage/Packages/Craftsman")

local StoreTest = {}

local Producer = Craftsman.Store.CreateProducer({
	Coins = 1,
})({
	AddCoins = function(state, amount: number)
		return {
			Coins = state.Coins + amount,
		}
	end,
})

-- Example of usage:
-- Producer.AddCoins(5)
-- print(Producer:getState().Coins) -- 6

return StoreTest
