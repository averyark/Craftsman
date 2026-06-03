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
const GreenTea = require("../../../../gt")
local Signal = require("../Signal")

const Config = require(".././Config") -- Your default data dictionary
const Network = require("./Network")
const PrintUtil = require("../Utilities/PrintUtil")

export type PlayerState = Config.PlayerState

--[=[
	@class DataServer
	The server-side Data module for Craftsman. It handles player session loading/saving,
	reconciliation against schemas (via GreenTea), session locking, client replication,
	and provides state producers for server-side state modification.
]=]
local Data = {}

local DataConfig = Config.DATA or {}
local BRIDGE_FOLDER_NAME = DataConfig.BRIDGE_FOLDER_NAME or "CraftsmanDataBridge"
local _STATE_EVENT_NAME = DataConfig.STATE_EVENT_NAME or "StateUpdated"
local _REQUEST_FUNCTION_NAME = DataConfig.REQUEST_FUNCTION_NAME or "RequestState"

local DefaultState: PlayerState = nil :: any
local DocumentStore = (nil :: any) :: typeof(DocumentService.DocumentStore.new(...))
local BridgeFolder = nil
local Schema = nil

local function deep_clone<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end

	local clone = {}

	for key, child in value do
		clone[deep_clone(key)] = deep_clone(child)
	end

	return clone :: any
end

local function normalize_state(value): PlayerState
	if type(value) ~= "table" then
		return value
	end

	return table.freeze(deep_clone(value))
end

local function validate_template(template: PlayerState, value: PlayerState): boolean
	if type(template) ~= "table" then
		return typeof(value) == typeof(template)
	end

	if type(value) ~= "table" then
		return false
	end

	for key, template_value in template do
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

local function validate_state(value: PlayerState): (PlayerState?, string?)
	if Schema then
		local ok, cause = Schema:matches(value)
		if not ok then
			return nil, tostring(cause)
		end
		-- :assert() casts the value to the schema's declared type.
		return Schema:assert(value) :: PlayerState
	end

	-- Fallback: structural template-diff check.
	if not validate_template(DataConfig.TEMPLATE, value) then
		return nil, "value does not match data template"
	end

	return value
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

local function clone_template(): PlayerState
	return normalize_state(DefaultState)
end

local function reconcile_state(state: PlayerState): PlayerState
	local mutable_state = deep_clone(state)
	local validated, err = validate_state(mutable_state)

	if not validated then
		PrintUtil:Warn(`Data reconcile failed, resetting to default. Reason: {err}`)
		return clone_template()
	end

	return normalize_state(validated)
end

local function make_producer(initial_state: PlayerState)
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
	local normalized_state = reconcile_state(state)
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

--[=[
	@prop Loaded Signal<Player, PlayerState>
	@within DataServer
	A signal that fires when a player's data is loaded and reconciled.
	Supports standard Signal connection APIs (Connect, Once, Wait).
]=]
Data.Loaded = {
	Connect = function(self, fn)
		local conn = RealLoadedSignal:Connect(fn)

		for player, record in PlayerRecords do
			if record.Loaded then
				task.spawn(fn, player, record.Producer:getState())
			end
		end

		return conn
	end,
	Once = function(self, fn)
		for player, record in PlayerRecords do
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
} :: Signal.Signal<Player, PlayerState>

--[=[
	@prop Saved Signal<Player, PlayerState>
	@within DataServer
	A signal that fires when a player's data is successfully saved to the DataStore.
]=]
Data.Saved = Signal.new() :: Signal.Signal<Player, PlayerState>

--[=[
	@method Init
	@within DataServer
	Initializes the server-side data store. Sets up the GreenTea validation schema
	and constructs the DocumentStore object.
]=]
function Data:Init()
	if DocumentStore then
		return
	end

	DefaultState = normalize_state(DataConfig.TEMPLATE)

	if DataConfig.SCHEMA ~= nil then
		if GreenTea.isGtType(DataConfig.SCHEMA) then
			Schema = DataConfig.SCHEMA
		else
			Schema = GreenTea.build(DataConfig.SCHEMA)
		end
	else
		Schema = nil
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
			local validated, err = validate_state(mutable_value)

			if not validated then
				PrintUtil:Warn(`Data document check failed: {err}`)
				return false, DefaultState
			end

			return true, validated
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

--[=[
	@method GetPlayerRecord
	@within DataServer
	@param player Player -- The player instance
	@return Record -- The internal record representing the player session status
	Returns the internal record containing the Player's Document, Reflex Producer, and load status.
]=]
function Data:GetPlayerRecord(player: Player)
	return get_record(player)
end

--[=[
	@method GetProducer
	@within DataServer
	@param player Player -- The player instance
	@return Producer -- The Reflex producer for this player
	Gets the Reflex producer associated with the player.
]=]
function Data:GetProducer(player: Player)
	return get_record(player).Producer
end

--[=[
	@method GetState
	@within DataServer
	@param player Player -- The player instance
	@return PlayerState -- The current player state, deep-cloned and frozen
	Queries the current state of a player. Yields if the player's data is still loading.
]=]
function Data:GetState(player: Player)
	local record = get_record(player)
	if not record.Loaded and record.LoadPromise then
		pcall(function()
			record.LoadPromise:await()
		end)
	end
	return normalize_state(record.Producer:getState())
end

--[=[
	@method SetState
	@within DataServer
	@param player Player -- The player instance
	@param next_state PlayerState -- The new state to set
	@return PlayerState -- The updated state
	Overwrites a player's state. Replicates changes to the client and caches them for saving.
]=]
function Data:SetState(player: Player, next_state)
	local record = get_record(player)
	local normalized_state = record.Producer.SetState(next_state)

	if record.Document:IsOpen() then
		record.Document:SetCache(normalized_state)
	end

	sync_client(player, normalized_state)
	return normalized_state
end

--[=[
	@method UpdateState
	@within DataServer
	@param player Player -- The player instance
	@param updater (state: PlayerState) -> PlayerState -- Function that transforms state
	@return PlayerState -- The updated state
	Updates a player's state using an updater function. Replicates changes to the client.
]=]
function Data:UpdateState(player: Player, updater)
	local record = get_record(player)
	local next_state = record.Producer.UpdateState(updater)

	if record.Document:IsOpen() then
		record.Document:SetCache(next_state)
	end

	sync_client(player, next_state)
	return next_state
end

--[=[
	@method ResetState
	@within DataServer
	@param player Player -- The player instance
	@return PlayerState -- The reset state
	Resets the player's state back to the default template state.
]=]
function Data:ResetState(player: Player)
	return self:SetState(player, clone_template())
end

--[=[
	@method LoadPlayer
	@within DataServer
	@param player Player -- The player instance
	@return Promise<PlayerState> -- A promise resolving with the loaded state
	Loads a player's document from the datastore, steals locks if needed, and syncs to the client.
]=]
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

--[=[
	@method SavePlayer
	@within DataServer
	@param player Player -- The player instance
	@return Promise<PlayerState?> -- A promise resolving with the saved state
	Saves the player's current cached state to the datastore without closing the session.
]=]
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

--[=[
	@method ClosePlayer
	@within DataServer
	@param player Player -- The player instance
	@return Promise<nil> -- A promise resolving when closed
	Closes the player's session, releases session locks, and saves current state.
]=]
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

--[=[
	@method RemovePlayer
	@within DataServer
	@param player Player -- The player instance
	@return Promise<nil>
	Alias for ClosePlayer.
]=]
function Data:RemovePlayer(player: Player)
	return self:ClosePlayer(player)
end

--[=[
	@method Shutdown
	@within DataServer
	Closes all active player sessions during a game shutdown. Runs synchronously.
]=]
function Data:Shutdown()
	if DataConfig.ENABLED == false then
		return
	end

	local players = {}
	for player in PlayerRecords do
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

--[=[
	@method Start
	@within DataServer
	Starts the server-side Data service, hooking up PlayerAdded/PlayerRemoving connections
	and BindToClose callbacks.
]=]
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

return Data
