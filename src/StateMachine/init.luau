--!nonstrict
--[[
    FileName    > init.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 27/05/2026
--]]

const RunService = game:GetService("RunService")

local StateMachine = {
	State = require(script.State),
	Machine = require(script.Machine),
	Server = require(script.Server),
	Client = require(script.Client),
	Network = require(script.Network),
	Types = require(script.Types),
}

function StateMachine.Register(machine, targets: { any }?): boolean
	if not RunService:IsServer() then
		return StateMachine.Client:Register(machine)
	end

	return StateMachine.Server:Register(machine, targets)
end

function StateMachine.Unregister(machine): boolean
	if not RunService:IsServer() then
		return StateMachine.Client:Unregister(machine)
	end

	return StateMachine.Server:Unregister(machine)
end

return StateMachine
