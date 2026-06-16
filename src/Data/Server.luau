--!nonstrict
--[[
    FileName    > Data.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 20/05/2026
--]]

const Players = game:GetService("Players")
const DataStoreService = game:GetService("DataStoreService")
const RunService = game:GetService("RunService")

const DocumentService = require("../../../../DocumentService")
const Promise = require("../../../../Promise")
const GreenTea = require("../../../../gt")
local Signal = require("../Signal")

const Config = require(".././Config") -- Your default data dictionary
const PrintUtil = require("../Utilities/PrintUtil")
const TableUtil = require("../Utilities/TableUtil")

export type PlayerState = Config.PlayerState

--[=[
	@class DataServer
	The server-side Data module for Craftsman. It handles player session loading/saving,
	reconciliation against schemas (via GreenTea), session locking, and hooks into the
	global Store.
]=]
local Data = {}

local DataConfig = Config.DATA or {}

local DefaultState: PlayerState = nil :: any
local DocumentStore = (nil :: any) :: typeof(DocumentService.DocumentStore.new(...))
local Schema: any? = nil

local function normalize_state(value): PlayerState
	if type(value) ~= "table" then
		return value
	end

	return table.freeze(TableUtil.DeepClone(value))
end

local function reconcile_template(template: PlayerState, value: PlayerState): boolean
	if type(template) ~= "table" then
		return typeof(value) == typeof(template)
	end

	if type(value) ~= "table" then
		return false
	end

	for key, template_value in template do
		local candidate_value = value[key]

		if candidate_value == nil then
			value[key] = TableUtil.DeepClone(template_value)
			candidate_value = value[key]
		end

		if type(template_value) == "table" then
			if not reconcile_template(template_value, candidate_value) then
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
		return Schema:assert(value) :: PlayerState
	end

	if not reconcile_template(DataConfig.TEMPLATE, value) then
		return nil, "value does not match data template"
	end

	return value
end

local function clone_template(): PlayerState
	return normalize_state(DefaultState)
end

local function reconcile_state(state: PlayerState): PlayerState
	local mutable_state = TableUtil.DeepClone(state)
	local validated, err = validate_state(mutable_state)

	if not validated then
		PrintUtil:Warn(`Data reconcile failed, resetting to default. Reason: {err}`)
		return clone_template()
	end

	return normalize_state(validated)
end

export type Record = {
	Player: Player,
	Document: typeof(DocumentStore:GetDocument(...)),
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

	record = {
		Player = player,
		Document = document,
		Loaded = false,
		LoadPromise = nil,
	}

	PlayerRecords[player] = record

	return record
end

local function settle_loaded_state(player, record, state)
	local normalized_state = reconcile_state(state)

	if Data.Producer and Data.Producer._LoadPlayer then
		Data.Producer._LoadPlayer(tostring(player.UserId), normalized_state)
	end

	record.Document:SetCache(normalized_state)
	record.Loaded = true
	Data.Loaded:Fire(player, normalized_state)

	return normalized_state
end

local function finish_saved_state(player, record, result)
	if not result.success then
		return nil, result.reason
	end

	local saved_state = if result.data then normalize_state(result.data) else Data:GetPlayerState(player)

	Data.Saved:Fire(player, saved_state)

	return saved_state
end

local function create_save_promise(player, record, should_close)
	return Promise.new(function(resolve, reject)
		if not record.Document:IsOpen() then
			resolve(Data:GetPlayerState(player))
			return
		end

		local current_state = Data:GetPlayerState(player)
		if current_state then
			record.Document:SetCache(current_state)
		end

		local result = if should_close then record.Document:Close() else record.Document:Save()
		local saved_state, reason = finish_saved_state(player, record, result)

		if not saved_state then
			reject(reason)
			return
		end

		if should_close then
			if Data.Producer and Data.Producer._UnloadPlayer then
				Data.Producer._UnloadPlayer(tostring(player.UserId))
			end
			PlayerRecords[player] = nil
			record.Loaded = false
		end

		resolve(saved_state)
	end)
end

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
			if not record.Loaded then
				continue
			end

			task.spawn(fn, player, Data:GetPlayerState(player))
		end

		return conn
	end,
	Once = function(self, fn)
		local fired = false
		local conn

		local function fire_once(player, state)
			if fired then
				return
			end
			fired = true
			if conn then
				conn:Disconnect()
			end
			fn(player, state)
		end

		-- Listen for the next load. Guarded by `fired` so a replayed already-loaded
		-- player and a future load can never both invoke the callback.
		conn = RealLoadedSignal:Connect(fire_once)

		for player, record in PlayerRecords do
			if not record.Loaded then
				continue
			end

			task.spawn(fire_once, player, Data:GetPlayerState(player))
			break
		end

		return conn
	end,
	Wait = function(self)
		for player, record in PlayerRecords do
			if record.Loaded then
				return player, Data:GetPlayerState(player)
			end
		end
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
	@param config { Producer: any }? -- The global producer configuration
	Initializes the server-side data store. Sets up the GreenTea validation schema
	and constructs the DocumentStore object.
]=]
function Data:Init(config: { Producer: any }?)
	if DocumentStore then
		return
	end

	if config and config.Producer then
		Data.Producer = config.Producer
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
		Data.DefaultState = clone_template()
		return
	end

	local data_store = DataStoreService:GetDataStore(DataConfig.STORE_NAME)
	DocumentStore = DocumentService.DocumentStore.new({
		dataStore = data_store,
		check = function(value)
			local mutable_value = TableUtil.DeepClone(value)
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
	Data.DefaultState = DefaultState
end

--[=[
	@method GetPlayerRecord
	@within DataServer
	@param player Player -- The player instance
	@return Record -- The internal record representing the player session status
	Returns the internal record containing the Player's Document and load status.
]=]
function Data:GetPlayerRecord(player: Player)
	return get_record(player)
end

--[=[
	@method GetPlayerState
	@within DataServer
	@param player Player -- The player instance
	@param selector ((PlayerState) -> any)? -- Optional selector function
	@return any -- The current player state, or selected portion
	Queries the current state of a player from the global producer.
]=]
function Data:GetPlayerState(player: Player, selector: ((PlayerState) -> any)?): any
	if not Data.Producer then
		return nil
	end
	return Data.Producer:getPlayerState(player, selector)
end

--[=[
	@method LoadPlayer
	@within DataServer
	@param player Player -- The player instance
	@return Promise<PlayerState> -- A promise resolving with the loaded state
	Loads a player's document from the datastore, steals locks if needed, and syncs to the global store.
]=]
function Data:LoadPlayer(player: Player)
	local record = get_record(player)

	if record.LoadPromise then
		return record.LoadPromise
	end

	record.LoadPromise = Promise.new(function(resolve, reject)
		local attempt = 1
		local max_attempts = DataConfig.OPEN_ATTEMPTS or 2

		while attempt <= max_attempts do
			local result = record.Document:Open()

			if result.success then
				local settled_state = settle_loaded_state(player, record, result.data)
				record.LoadPromise = nil
				resolve(settled_state)
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
	Closes the player's session, releases session locks, unloads from global store, and saves state.
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

	-- Do not change this to a pairs loop. This is to avoid issues with PlayerRecords being modified while iterating.
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

		local current_state = Data:GetPlayerState(player)
		if current_state then
			record.Document:SetCache(current_state)
		end

		local result = record.Document:Close()
		if result.success then
			finish_saved_state(player, record, result)
		end

		if Data.Producer and Data.Producer._UnloadPlayer then
			Data.Producer._UnloadPlayer(tostring(player.UserId))
		end

		PlayerRecords[player] = nil
		record.Loaded = false
	end
	--
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
		for _, player in Players:GetPlayers() do
			self:LoadPlayer(player):catch(function(err)
				PrintUtil:Warn(`Data load failed for {player.Name}: {err}`)
			end)
		end
	end

	if DataConfig.LOAD_ON_PLAYER_ADDED ~= false then
		Players.PlayerAdded:Connect(function(player)
			self:LoadPlayer(player):catch(function(err)
				PrintUtil:Warn(`Data load failed for {player.Name}: {err}`)
			end)
		end)
	end

	if DataConfig.SAVE_ON_PLAYER_REMOVING ~= false then
		Players.PlayerRemoving:Connect(function(player)
			self:ClosePlayer(player):catch(function(err)
				PrintUtil:Warn(`Data close failed for {player.Name}: {err}`)
			end)
		end)
	end

	if DataConfig.BIND_TO_CLOSE ~= false then
		game:BindToClose(function()
			self:Shutdown()
		end)
	end
end

export type ServerModule = {
	Loaded: Signal.Signal<Player, PlayerState>,
	Saved: Signal.Signal<Player, PlayerState>,
	Producer: any?,

	Init: (self: ServerModule, config: { Producer: any }?) -> (),
	Start: (self: ServerModule) -> (),
	GetPlayerRecord: (self: ServerModule, player: Player) -> any?,
	GetPlayerState: ((self: ServerModule, player: Player) -> PlayerState?)
		& (<U>(self: ServerModule, player: Player, selector: (PlayerState) -> U) -> U?),
	LoadPlayer: (self: ServerModule, player: Player) -> any,
	SavePlayer: (self: ServerModule, player: Player) -> any,
	ClosePlayer: (self: ServerModule, player: Player) -> any,
	RemovePlayer: (self: ServerModule, player: Player) -> typeof(Promise.new(...)),
	Shutdown: (self: ServerModule) -> (),
}

return (Data :: any) :: ServerModule
