--!nonstrict
--[[
    FileName    > Bootstrap.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 21/05/2026
--]]

const Players = game:GetService("Players")
const RunService = game:GetService("RunService")

const Craftsman = require("@game/ReplicatedStorage/Packages/Craftsman")

-- Apply user configuration before any services start
require("@game/ReplicatedStorage/CraftsmanConfig")

local Bootstrap = {}

function Bootstrap.AddPlayer(player)
	Craftsman.Player.new(player)

	player.CharacterAdded:Connect(function(character)
		Craftsman.Entity.new(character, player)
	end)

	if player.Character then
		Craftsman.Entity.new(player.Character, player)
	end
end

function Bootstrap:Start(modules: Instance?)
	if RunService:IsClient() then
		Craftsman.DataClient:Start()
		Craftsman.MarketClient:Start()
		Craftsman.StateMachineClient:Start()
	else
		Craftsman.DataServer:Start()
		Craftsman.MarketServer:Start()
		Craftsman.StateMachineServer:Start()
	end

	if modules then
		Craftsman.Component:LoadModulesAsync(modules):await()
	end

	Players.PlayerAdded:Connect(self.AddPlayer)

	for _, player in Players:GetPlayers() do
		pcall(self.AddPlayer, player)
	end
end

return Bootstrap
