--!strict
--[[
    FileName    > Bootstrap.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 21/05/2026
--]]

const Players = game:GetService("Players")
const RunService = game:GetService("RunService")

const Craftsman = require("@game/ReplicatedStorage/Packages/Craftsman")
const Lifecycle = require("@game/ReplicatedStorage/Packages/packages/roblox/Lifecycle")

require("../Packages/packages/roblox/ByteNet")

-- Apply user configuration before any services start
require("@game/ReplicatedStorage/CraftsmanConfig")

local Bootstrap = {}

--
local function add_player(player: Player)
	--
	player.CharacterAdded:Connect(function(character)
		Craftsman.Entity.new(character, player)
	end)
	--

	if not player.Character then
		return
	end

	Craftsman.Entity.new(player.Character, player)
end
--

--
local function start_services()
	--
	if RunService:IsServer() then
		Craftsman.StateMachineServer:Start()
		return
	end
	--

	Craftsman.StateMachineClient:Start()
end
--

--
function Bootstrap:Start(modules: Instance?)
	--
	start_services()

	if modules then
		Lifecycle:LoadModulesAsync(modules):await()
	end
	--

	--
	Players.PlayerAdded:Connect(add_player)

	for _, player in Players:GetPlayers() do
		add_player(player)
	end
	--
end
--

return Bootstrap
