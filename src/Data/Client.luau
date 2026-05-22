--!nonstrict
--[[
    FileName    > Client.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 21/05/2026
--]]

const ReplicatedStorage = game:GetService("ReplicatedStorage")
const RunService = game:GetService("RunService")
const Players = game:GetService("Players")

const Reflex = require("../../../../Reflex")
const Config = require(".././Config")
const TableUtil = require("../Utilities/TableUtil")
local Signal = require("../Signal")

export type PlayerState = typeof(Config.DATA.TEMPLATE)

local Client = {}

local DataConfig = Config.DATA or {}
local BRIDGE_FOLDER_NAME = DataConfig.BRIDGE_FOLDER_NAME or "CraftsmanDataBridge"
local STATE_EVENT_NAME = DataConfig.STATE_EVENT_NAME or "StateUpdated"
local REQUEST_FUNCTION_NAME = DataConfig.REQUEST_FUNCTION_NAME or "RequestState"

local DefaultState: PlayerState = nil :: any
local BridgeFolder = nil
local StateEvent = nil
local RequestFunction = nil
local StateProducer = nil

local function normalize_state(value)
	if type(value) ~= "table" then
		return value
	end

	return table.freeze(TableUtil.DeepClone(value))
end

local function clone_template()
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

local function ensure_bridge()
	if BridgeFolder then
		return BridgeFolder
	end

	BridgeFolder = ReplicatedStorage:WaitForChild(BRIDGE_FOLDER_NAME)
	StateEvent = BridgeFolder:WaitForChild(STATE_EVENT_NAME) :: RemoteEvent
	RequestFunction = BridgeFolder:WaitForChild(REQUEST_FUNCTION_NAME) :: RemoteFunction

	return BridgeFolder
end

local function sync_state(next_state)
	local producer = ensure_producer()
	producer.SetState(normalize_state(next_state))
	return producer:getState()
end

DefaultState = normalize_state(DataConfig.TEMPLATE)

Client.Loaded = Signal.new() :: Signal.Signal<Player, PlayerState>
Client.Saved = Signal.new() :: Signal.Signal<Player, PlayerState>

function Client:Init()
	if StateProducer then
		return
	end

	ensure_producer()

	if not RunService:IsClient() or DataConfig.ENABLED == false or DataConfig.AUTO_START_CLIENT == false then
		return
	end

	ensure_bridge()

	StateEvent.OnClientEvent:Connect(function(next_state)
		sync_state(next_state)
	end)
end

function Client:Start()
	if not RunService:IsClient() or DataConfig.ENABLED == false or DataConfig.AUTO_START_CLIENT == false then
		return
	end

	self:Init()

	task.spawn(function()
		local ok, initial_state = pcall(function()
			return RequestFunction:InvokeServer()
		end)

		if not ok then
			return
		end

		if type(initial_state) == "table" then
			sync_state(initial_state)
			Client.Loaded:Fire(Players.LocalPlayer, initial_state)
		end
	end)
end

function Client:GetState(selector)
	local state = ensure_producer():getState(selector)

	if type(state) == "table" then
		return normalize_state(state)
	end

	return state
end

function Client:Connect(listener)
	return ensure_producer():Connect(listener)
end

function Client:Once(listener)
	return ensure_producer():Once(listener)
end

function Client:Wait()
	return ensure_producer():Wait()
end

function Client:Subscribe(...)
	return ensure_producer():subscribe(...)
end

function Client:Observe(...)
	return ensure_producer():observe(...)
end

function Client:ObserveWhile(...)
	return ensure_producer():observeWhile(...)
end

function Client:WaitForBridge()
	return ensure_bridge()
end

function Client:GetBridge()
	return ensure_bridge()
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
	WaitForBridge: (self: ClientModule) -> Folder,
	GetBridge: (self: ClientModule) -> Folder,
}

return (Client :: any) :: ClientModule
