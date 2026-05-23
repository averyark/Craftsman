--!nonstrict
--[[
    FileName    > Data.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 20/05/2026
--]]

const Players = game:GetService("Players")
const DataStoreService = game:GetService("DataStoreService")
const ReplicatedStorage = game:GetService("ReplicatedStorage")
const RunService = game:GetService("RunService")

const DocumentService = require("../../../../DocumentService")
const Promise = require("../../../../Promise")
const Reflex = require("../../../../Reflex")
local Signal = require("../Signal")

const Config = require(".././Config") -- Your default data dictionary
const Network = require("./Network")
const PrintUtil = require("../Utilities/PrintUtil")

export type PlayerState = Config.PlayerState

local Data = {}

local DataConfig = Config.DATA or {}
local BRIDGE_FOLDER_NAME = DataConfig.BRIDGE_FOLDER_NAME or "CraftsmanDataBridge"
local STATE_EVENT_NAME = DataConfig.STATE_EVENT_NAME or "StateUpdated"
local REQUEST_FUNCTION_NAME = DataConfig.REQUEST_FUNCTION_NAME or "RequestState"

local DefaultState: PlayerState = nil :: any
local DocumentStore = (nil :: any) :: typeof(DocumentService.DocumentStore.new(...))
local BridgeFolder = nil

local function deep_clone(value)
	if type(value) ~= "table" then
		return value
	end

	local clone = {}

	for key, child in next, value do
		clone[deep_clone(key)] = deep_clone(child)
	end

	return clone
end

local function normalize_state(value)
	if type(value) ~= "table" then
		return value
	end

	return table.freeze(deep_clone(value))
end

local function validate_template(template, value)
	if type(template) ~= "table" then
		return typeof(value) == typeof(template)
	end

	if type(value) ~= "table" then
		return false
	end

	for key, template_value in next, template do
		local candidate_value = value[key]

		if candidate_value == nil then
			value[key] = deep_clone(template_value)
			candidate_value = value[key]
		end

		if type(template_value) == "table" then
			if not validate_template(template_value, candidate_value) then
				return false
			end
		elseif typeof(candidate_value) ~= typeof(template_value) then
			return false
		end
	end

	return true
end

local function create_bridge()
	if not RunService:IsServer() or DataConfig.AUTO_CREATE_BRIDGE == false then
		return
	end

	local bridge_folder = ReplicatedStorage:FindFirstChild(BRIDGE_FOLDER_NAME)
	if not bridge_folder then
		bridge_folder = Instance.new("Folder")
		bridge_folder.Name = BRIDGE_FOLDER_NAME
		bridge_folder.Parent = ReplicatedStorage
	end

	BridgeFolder = bridge_folder
end

local function clone_template()
	return normalize_state(DefaultState)
end

local function make_producer(initial_state)
	return Reflex.createProducer(initial_state, {
		SetState = function(state, next_state)
			if next_state == state then
				return state
			end

			if type(next_state) ~= "table" then
				return state
			end

			return normalize_state(next_state)
		end,
		UpdateState = function(state, updater)
			local next_state = updater(state)

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
end

export type Record = {
	Player: Player,
	Document: typeof(DocumentStore),
	Producer: typeof(make_producer(clone_template())),
	Loaded: boolean,
	LoadPromise: typeof(Promise.new(...))?,
}

local PlayerRecords = {} :: {
	[Player]: Record,
}

local function get_record(player: Player): Record
	local record = PlayerRecords[player]
	if record then
		return record
	end

	local document = DocumentStore:GetDocument(tostring(player.UserId))
	local producer = make_producer(clone_template())

	record = {
		Player = player,
		Document = document,
		Producer = producer,
		Loaded = false,
		LoadPromise = nil,
	}

	PlayerRecords[player] = record

	return record
end

local function sync_client(player, state)
	if player.Parent then
		Network.packets.StateUpdated.sendTo(state, player)
	end
end

local function settle_loaded_state(player, record, state)
	local normalized_state = normalize_state(state)
	record.Producer.SetState(normalized_state)
	record.Document:SetCache(normalized_state)
	record.Loaded = true
	Data.Loaded:Fire(player, normalized_state)
	sync_client(player, normalized_state)

	return normalized_state
end

local function finish_saved_state(player, record, result)
	if not result.success then
		return nil, result.reason
	end

	local saved_state = if result.data then normalize_state(result.data) else record.Producer:getState()
	record.Producer.SetState(saved_state)
	Data.Saved:Fire(player, saved_state)
	sync_client(player, saved_state)

	return saved_state
end

local function create_save_promise(player, record, should_close)
	return Promise.new(function(resolve, reject)
		task.spawn(function()
			if not record.Document:IsOpen() then
				local current_state = record.Producer:getState()
				resolve(current_state)
				return
			end

			local result = if should_close then record.Document:Close() else record.Document:Save()
			local saved_state, reason = finish_saved_state(player, record, result)

			if not saved_state then
				reject(reason)
				return
			end

			if should_close then
				PlayerRecords[player] = nil
				record.Loaded = false
			end

			resolve(saved_state)
		end)
	end)
end

DefaultState = normalize_state(DataConfig.TEMPLATE)

local RealLoadedSignal = Signal.new()
Data.Loaded = {
	Connect = function(self, fn)
		local conn = RealLoadedSignal:Connect(fn)

		for player, record in next, PlayerRecords do
			if record.Loaded then
				task.spawn(fn, player, record.Producer:getState())
			end
		end

		return conn
	end,
	Once = function(self, fn)
		for player, record in next, PlayerRecords do
			if record.Loaded then
				task.spawn(fn, player, record.Producer:getState())
				return {
					Disconnect = function() end,
					Destroy = function() end,
					Connected = false,
				}
			end
		end

		return RealLoadedSignal:Once(fn)
	end,
	Wait = function(self)
		return RealLoadedSignal:Wait()
	end,
	Fire = function(self, ...)
		RealLoadedSignal:Fire(...)
	end,
} :: any

Data.Saved = Signal.new() :: Signal.Signal<Player, PlayerState>

function Data:Init()
	if DocumentStore then
		return
	end

	if DataConfig.ENABLED == false then
		Data.DocumentStore = nil
		Data.BridgeFolder = nil
		Data.StateEvent = nil
		Data.RequestFunction = nil
		Data.DefaultState = clone_template()
		return
	end

	create_bridge()

	local data_store = DataStoreService:GetDataStore(DataConfig.STORE_NAME)
	DocumentStore = DocumentService.DocumentStore.new({
		dataStore = data_store,
		check = function(value)
			local mutable_value = deep_clone(value)
			if not validate_template(DataConfig.TEMPLATE, mutable_value) then
				return false, DefaultState
			end

			return true, mutable_value
		end,
		default = clone_template(),
		migrations = {},
		lockSessions = DataConfig.LOCK_SESSIONS ~= false,
		bindToClose = DataConfig.BIND_TO_CLOSE ~= false,
	})

	Data.DocumentStore = DocumentStore
	Data.BridgeFolder = BridgeFolder
	Data.StateEvent = nil
	Data.RequestFunction = nil
	Data.DefaultState = DefaultState
end

function Data:GetPlayerRecord(player: Player)
	return get_record(player)
end

function Data:GetProducer(player: Player)
	return get_record(player).Producer
end

function Data:GetState(player: Player)
	local record = get_record(player)
	if not record.Loaded and record.LoadPromise then
		pcall(function()
			record.LoadPromise:await()
		end)
	end
	return normalize_state(record.Producer:getState())
end

function Data:SetState(player: Player, next_state)
	local record = get_record(player)
	local normalized_state = record.Producer.SetState(next_state)

	if record.Document:IsOpen() then
		record.Document:SetCache(normalized_state)
	end

	sync_client(player, normalized_state)
	return normalized_state
end

function Data:UpdateState(player: Player, updater)
	local record = get_record(player)
	local next_state = record.Producer.UpdateState(updater)

	if record.Document:IsOpen() then
		record.Document:SetCache(next_state)
	end

	sync_client(player, next_state)
	return next_state
end

function Data:ResetState(player: Player)
	return self:SetState(player, clone_template())
end

function Data:LoadPlayer(player: Player)
	local record = get_record(player)

	if record.LoadPromise then
		return record.LoadPromise
	end

	record.LoadPromise = Promise.new(function(resolve, reject)
		task.spawn(function()
			local attempt = 1
			local max_attempts = DataConfig.OPEN_ATTEMPTS or 2
			while attempt <= max_attempts do
				local result = record.Document:Open()

				if result.success then
					record.LoadPromise = nil
					record.Loaded = true
					resolve(settle_loaded_state(player, record, result.data))
					return
				end

				if result.reason == "SessionLockedError" and attempt == 1 then
					record.Document:Steal()
					attempt += 1
					continue
				end

				record.LoadPromise = nil
				reject(result.reason)
				return
			end
		end)
	end)

	return record.LoadPromise
end

function Data:SavePlayer(player: Player)
	local record = PlayerRecords[player]
	if not record then
		return Promise.new(function(resolve)
			resolve(nil)
		end)
	end

	if record.LoadPromise then
		return record.LoadPromise:andThen(function()
			return self:SavePlayer(player)
		end)
	end

	return create_save_promise(player, record, false)
end

function Data:ClosePlayer(player: Player)
	local record = PlayerRecords[player]
	if not record then
		return Promise.new(function(resolve)
			resolve(nil)
		end)
	end

	if not record.Document:IsOpen() then
		PlayerRecords[player] = nil
		record.Loaded = false
		return Promise.new(function(resolve)
			resolve(nil)
		end)
	end

	if record.LoadPromise then
		return record.LoadPromise:andThen(function()
			return self:ClosePlayer(player)
		end)
	end

	return create_save_promise(player, record, true)
end

function Data:RemovePlayer(player: Player)
	return self:ClosePlayer(player)
end

function Data:Shutdown()
	if DataConfig.ENABLED == false then
		return
	end

	local players = {}
	for player in next, PlayerRecords do
		players[#players + 1] = player
	end

	for index = 1, #players do
		local player = players[index]
		local record = PlayerRecords[player]

		if not record then
			continue
		end

		if not record.Document:IsOpen() then
			PlayerRecords[player] = nil
			continue
		end

		local result = record.Document:Close()
		if result.success then
			finish_saved_state(player, record, result)
		end

		PlayerRecords[player] = nil
		record.Loaded = false
	end
end

function Data:Start()
	if not RunService:IsServer() or DataConfig.ENABLED == false or DataConfig.AUTO_START_SERVER == false then
		return
	end

	self:Init()

	if DataConfig.LOAD_EXISTING_PLAYERS ~= false then
		local players = Players:GetPlayers()
		for index = 1, #players do
			local player = players[index]
			task.spawn(function()
				self:LoadPlayer(player):catch(function(err)
					PrintUtil:Warn(`Data load failed for {player.Name}: {err}`)
				end)
			end)
		end
	end

	if DataConfig.LOAD_ON_PLAYER_ADDED ~= false then
		Players.PlayerAdded:Connect(function(player)
			task.spawn(function()
				self:LoadPlayer(player):catch(function(err)
					PrintUtil:Warn(`Data load failed for {player.Name}: {err}`)
				end)
			end)
		end)
	end

	if DataConfig.SAVE_ON_PLAYER_REMOVING ~= false then
		Players.PlayerRemoving:Connect(function(player)
			task.spawn(function()
				self:ClosePlayer(player):catch(function(err)
					PrintUtil:Warn(`Data close failed for {player.Name}: {err}`)
				end)
			end)
		end)
	end

	if DataConfig.BIND_TO_CLOSE ~= false then
		game:BindToClose(function()
			self:Shutdown()
		end)
	end

	if DataConfig.SYNC_CLIENT ~= false then
		Network.queries.RequestState.listen(function(_data, player)
			return self:GetState(player)
		end)
	end
end

export type DataModule = {
	Loaded: Signal.Signal<Player, PlayerState>,
	Saved: Signal.Signal<Player, PlayerState>,

	Init: (self: DataModule) -> (),
	GetPlayerRecord: (self: DataModule, player: Player) -> any,
	GetProducer: (self: DataModule, player: Player) -> any,
	GetState: (self: DataModule, player: Player) -> PlayerState,
	SetState: (self: DataModule, player: Player, next_state: PlayerState) -> PlayerState,
	UpdateState: (self: DataModule, player: Player, updater: (PlayerState) -> PlayerState) -> PlayerState,
	ResetState: (self: DataModule, player: Player) -> PlayerState,
	LoadPlayer: (self: DataModule, player: Player) -> any,
	SavePlayer: (self: DataModule, player: Player) -> any,
	ClosePlayer: (self: DataModule, player: Player) -> any,
	RemovePlayer: (self: DataModule, player: Player) -> any,
	Shutdown: (self: DataModule) -> (),
	Start: (self: DataModule) -> (),
}

return (Data :: any) :: DataModule
