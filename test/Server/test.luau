--!nonstrict
--[[
    FileName    > test.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 22/05/2026
--]]

const Craftsman = require("@game/ReplicatedStorage/Packages/Craftsman")
const CraftsmanConfig = require("@game/ReplicatedStorage/CraftsmanConfig")

local test = Craftsman.Component.new({})

local LoadedPlayers = {}

test.Start = function()
	Craftsman.PrintUtil:Print("Test component started!")

	-- Register Developer Product purchase handlers
	Craftsman.MarketServer:RegisterHandler("Add100Coins", function(player, state, definition, context)
		local new_state = Craftsman.TableUtil.DeepClone(state)
		new_state.Coins = (new_state.Coins or 0) + 100

		return new_state
	end)

	Craftsman.MarketServer:RegisterHandler("Add1000Coins", function(player, state, definition, context)
		local new_state = Craftsman.TableUtil.DeepClone(state)
		new_state.Coins = (new_state.Coins or 0) + 1000
		return new_state
	end)

	-- Register Gamepass purchase handlers (Global ownership handled by Roblox)
	Craftsman.MarketServer:RegisterHandler("Multiply10Coins", function(player, state, definition, context)
		return true
	end)

	Craftsman.MarketServer:RegisterHandler("Multiply2Coins", function(player, state, definition, context)
		return true
	end)

	-- Periodic coin awarding task
	task.spawn(function()
		while true do
			task.wait(10)

			for player in next, LoadedPlayers do
				local base_coins = math.random(1, 10)

				-- Apply active multipliers from the gamepass cache natively
				local multiplier = 1
				local keys = CraftsmanConfig.KEYS
				if Craftsman.MarketServer:UserOwnsGamePass(player, keys.Multiply10Coins) then
					multiplier *= 10
				end
				if Craftsman.MarketServer:UserOwnsGamePass(player, keys.Multiply2Coins) then
					multiplier *= 2
				end

				local amount_to_add = base_coins * multiplier

				Craftsman.PrintUtil:Print(
					string.format(
						"[test] Awarding %d coins to player %s (base: %d, multiplier: %d)",
						amount_to_add,
						player.Name,
						base_coins,
						multiplier
					)
				)

				Craftsman.DataServer:UpdateState(player, function(state)
					local new_state = Craftsman.TableUtil.DeepClone(state)
					new_state.Coins = (new_state.Coins or 0) + amount_to_add
					return new_state
				end)
			end
		end
	end)
end

Craftsman.DataServer.Loaded:Connect(function(player, data)
	LoadedPlayers[player] = true
	Craftsman.PrintUtil:Print("Data loaded for player " .. player.Name)
	Craftsman.PrintUtil:PrintObject(data)
end)

Craftsman.DataServer.Saved:Connect(function(player, data)
	Craftsman.PrintUtil:Print("Data saved for player " .. player.Name)
	Craftsman.PrintUtil:PrintObject(data)
end)

Craftsman.Player.Loaded:Connect(function(player)
	Craftsman.PrintUtil:PrintObject(player)
end)

Craftsman.Entity.Spawned:Connect(function(entity)
	Craftsman.PrintUtil:PrintObject(entity)
end)

Craftsman.Player.Removing:Connect(function(player)
	LoadedPlayers[player] = nil
end)

return test
