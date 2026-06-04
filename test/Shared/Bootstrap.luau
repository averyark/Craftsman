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
end

return Bootstrap
