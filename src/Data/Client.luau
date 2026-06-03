--!nonstrict
--[[
    FileName    > Client.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 21/05/2026
--]]

const RunService = game:GetService("RunService")
const Players = game:GetService("Players")

const Reflex = require("../../../../Reflex")
const Config = require(".././Config")
const Network = require("./Network")
const TableUtil = require("../Utilities/TableUtil")
local Signal = require("../Signal")

export type PlayerState = Config.PlayerState

--[=[
	@class DataClient
	The client-side Data module for Craftsman. It handles local state storage, replication,
	state selection, and state observation via Reflex.
]=]
local Client = {}

local DataConfig = Config.DATA or {}

local DefaultState: PlayerState = nil :: any
local StateProducer = nil

local IsLoaded = false
local LoadedState: PlayerState = nil :: any

local function normalize_state(value): PlayerState
	if type(value) ~= "table" then
		return value
	end

	return table.freeze(TableUtil.DeepClone(value))
end

local function clone_template(): PlayerState
	return normalize_state(DefaultState)
end

local function ensure_producer()
	if StateProducer then
		return StateProducer
	end

	StateProducer = Reflex.createProducer(clone_template(), {
		SetState = function(state, next_state)
			if next_state == state then
				return state
			end

			if type(next_state) ~= "table" then
				return state
			end

			return normalize_state(next_state)
		end,
		ResetState = function()
			return clone_template()
		end,
	})

	return StateProducer
end

local function sync_state(next_state)
	local producer = ensure_producer()
	producer.SetState(normalize_state(next_state))
	return producer:getState()
end

DefaultState = normalize_state(DataConfig.TEMPLATE)

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
			task.spawn(fn, Players.LocalPlayer, LoadedState)
		end
		return conn
	end,
	Once = function(self, fn)
		if IsLoaded then
			task.spawn(fn, Players.LocalPlayer, LoadedState)
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
			return Players.LocalPlayer, LoadedState
		end
		return RealLoadedSignal:Wait()
	end,
	Fire = function(self, ...)
		RealLoadedSignal:Fire(...)
	end,
} :: any

--[=[
	@prop Saved Signal<Player, PlayerState>
	@within DataClient
	A signal that fires when the client player's state is saved.
]=]
Client.Saved = Signal.new() :: Signal.Signal<Player, PlayerState>

--[=[
	@method Init
	@within DataClient
	Initializes the client-side data store. Sets up Reflex state producers and
	registers packet listeners for state updates from the server.
]=]
function Client:Init()
	if StateProducer then
		return
	end

	DefaultState = normalize_state(DataConfig.TEMPLATE)
	ensure_producer()

	if not RunService:IsClient() or DataConfig.ENABLED == false or DataConfig.AUTO_START_CLIENT == false then
		return
	end

	Network.packets.StateUpdated.listen(function(next_state)
		if type(next_state) == "table" then
			if not IsLoaded then
				IsLoaded = true
				LoadedState = next_state
				Client.Loaded:Fire(Players.LocalPlayer, next_state)
			end
			sync_state(next_state)
		end
	end)
end

--[=[
	@method Start
	@within DataClient
	Starts the client-side data service. Calls `Init()` and requests the initial
	state from the server.
]=]
function Client:Start()
	if not RunService:IsClient() or DataConfig.ENABLED == false or DataConfig.AUTO_START_CLIENT == false then
		return
	end

	self:Init()

	task.spawn(function()
		local ok, initial_state = pcall(function()
			return Network.queries.RequestState.invoke()
		end)

		if not ok then
			return
		end

		if type(initial_state) == "table" then
			if not IsLoaded then
				IsLoaded = true
				LoadedState = initial_state
				Client.Loaded:Fire(Players.LocalPlayer, initial_state)
				sync_state(initial_state)
			end
		end
	end)
end

--[=[
	@method GetState
	@within DataClient
	@param selector function? -- Optional selector function to query specific state properties
	@return PlayerState -- The current player state or selected sub-state, deep-cloned and frozen
	Queries the current player state from the Reflex producer.
]=]
function Client:GetState(selector): PlayerState
	local state = ensure_producer():getState(selector)

	if type(state) == "table" then
		return normalize_state(state)
	end

	return state
end

--[=[
	@method Connect
	@within DataClient
	@param listener function -- Callback to listen to state updates
	@return any -- Connection object
	Connects a listener to the state producer.
]=]
function Client:Connect(listener)
	return ensure_producer():Connect(listener)
end

--[=[
	@method Once
	@within DataClient
	@param listener function -- Callback to listen to the next state update
	@return any -- Connection object
	Connects a listener to the state producer that fires only once.
]=]
function Client:Once(listener)
	return ensure_producer():Once(listener)
end

--[=[
	@method Wait
	@within DataClient
	@return PlayerState -- The next state
	Yields the current thread until the state producer updates.
]=]
function Client:Wait()
	return ensure_producer():Wait()
end

--[=[
	@method Subscribe
	@within DataClient
	@param listener (state: PlayerState, oldState: PlayerState) -> () -- Callback for state changes
	@return any -- Connection object
	Subscribes a listener to the state producer. If data is already loaded, runs immediately.
]=]
function Client:Subscribe(listener)
	local conn = ensure_producer():subscribe(listener)
	if IsLoaded then
		task.spawn(listener, LoadedState, nil)
	end
	return conn
end

--[=[
	@method Observe
	@within DataClient
	@param selector (state: PlayerState) -> any -- Selector for state property
	@param listener (next: any, prev: any) -> () -- Callback function
	@return any -- Connection object
	Observes a specific selector for changes.
]=]
function Client:Observe(...)
	return ensure_producer():observe(...)
end

--[=[
	@method ObserveWhile
	@within DataClient
	@param selector (state: PlayerState) -> boolean -- Conditional selector
	@param listener (isActive: boolean) -> () -- Callback function
	@return any -- Connection object
	Observes a boolean selector for changes.
]=]
function Client:ObserveWhile(...)
	return ensure_producer():observeWhile(...)
end

export type ClientModule = {
	Loaded: Signal.Signal<Player, PlayerState>,
	Saved: Signal.Signal<Player, PlayerState>,

	Init: (self: ClientModule) -> (),
	Start: (self: ClientModule) -> (),
	GetState: ((self: ClientModule) -> PlayerState) & (<U>(self: ClientModule, selector: (PlayerState) -> U) -> U),
	Connect: (self: ClientModule, listener: (PlayerState) -> ()) -> any,
	Once: (self: ClientModule, listener: (PlayerState) -> ()) -> any,
	Wait: (self: ClientModule) -> PlayerState,
	Subscribe: (self: ClientModule, listener: (PlayerState, PlayerState) -> ()) -> any,
	Observe: (self: ClientModule, selector: (PlayerState) -> any, listener: (any, any) -> ()) -> any,
	ObserveWhile: (self: ClientModule, selector: (PlayerState) -> boolean, listener: (boolean) -> ()) -> any,
}

return (Client :: any) :: ClientModule
