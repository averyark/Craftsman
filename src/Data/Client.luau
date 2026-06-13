--!nonstrict
--[[
    FileName    > Client.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 21/05/2026
--]]

const RunService = game:GetService("RunService")
const Players = game:GetService("Players")

const Config = require(".././Config")
local Signal = require("../Signal")

export type PlayerState = Config.PlayerState

--[=[
	@class DataClient
	The client-side Data module for Craftsman. It acts as a lightweight observer
	for the player's loaded state using the global Store.
]=]
local Client = {}

local DataConfig = Config.DATA or {}

local IsLoaded = false

local RealLoadedSignal = Signal.new()

--[=[
	@prop Loaded Signal<Player, PlayerState>
	@within DataClient
	A signal that fires when the client player's state is loaded and normalized.
	Supports standard Signal connection APIs (Connect, Once, Wait).
]=]
Client.Loaded = {
	Connect = function(self, fn)
		local conn = RealLoadedSignal:Connect(fn)
		if IsLoaded then
			task.spawn(fn, Players.LocalPlayer, Client:GetPlayerState())
		end
		return conn
	end,
	Once = function(self, fn)
		if IsLoaded then
			task.spawn(fn, Players.LocalPlayer, Client:GetPlayerState())
			return {
				Disconnect = function() end,
				Destroy = function() end,
				Connected = false,
			}
		end
		return RealLoadedSignal:Once(fn)
	end,
	Wait = function(self)
		if IsLoaded then
			return Players.LocalPlayer, Client:GetPlayerState()
		end
		return RealLoadedSignal:Wait()
	end,
	Fire = function(self, ...)
		RealLoadedSignal:Fire(...)
	end,
} :: Signal.Signal<Player, PlayerState>

--[=[
	@method Init
	@within DataClient
	@param config { Producer: any }? -- The global producer configuration
	Initializes the client-side data store. Hooks into the global Reflex producer
	to observe when the player's data arrives from the server.
]=]
function Client:Init(config: { Producer: any }?)
	if Client.Producer then
		return
	end

	if config and config.Producer then
		Client.Producer = config.Producer
	end

	if not RunService:IsClient() or DataConfig.ENABLED == false or DataConfig.AUTO_START_CLIENT == false then
		return
	end

	if not Client.Producer then
		return
	end

	local unsubscribe
	unsubscribe = Client.Producer:subscribe(function(state)
		if not Players.LocalPlayer then
			return
		end

		local local_user_id = tostring(Players.LocalPlayer.UserId)
		local player_state = state[local_user_id]

		if not player_state or IsLoaded then
			return
		end

		IsLoaded = true
		Client.Loaded:Fire(Players.LocalPlayer, player_state)

		if unsubscribe then
			task.defer(unsubscribe)
		end
	end)
end

--[=[
	@method Start
	@within DataClient
	Starts the client-side data service. Calls `Init()`.
]=]
function Client:Start()
	if not RunService:IsClient() or DataConfig.ENABLED == false or DataConfig.AUTO_START_CLIENT == false then
		return
	end

	self:Init()
end

--[=[
	@method GetPlayerState
	@within DataClient
	@param selector ((PlayerState) -> any)? -- Optional selector function
	@return any -- The current player state, or selected portion
	Queries the current player state from the global Reflex producer.
]=]
function Client:GetPlayerState(selector: ((PlayerState) -> any)?): any
	if not Client.Producer then
		return nil
	end

	if not Players.LocalPlayer then
		return nil
	end

	return Client.Producer:getPlayerState(Players.LocalPlayer, selector)
end

export type ClientModule = {
	Loaded: Signal.Signal<Player, PlayerState>,

	Init: (self: ClientModule, config: { Producer: any }?) -> (),
	Start: (self: ClientModule) -> (),
	GetPlayerState: ((self: ClientModule) -> PlayerState)
		& (<U>(self: ClientModule, selector: (PlayerState) -> U) -> U),
}

return (Client :: any) :: ClientModule
