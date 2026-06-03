--!nonstrict
--[[
    FileName    > Player.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 21/05/2026
--]]

const Players = game:GetService("Players")
const RunService = game:GetService("RunService")

const Promise = require("../../../Promise")
const Keeper = require("../../../Keeper")
const DataClient = require("./Data/Client")
const Config = require("./Config")
const Signal = require("./Signal")
const StateMachine = require("./StateMachine")

const PrintUtil = require("./Utilities/PrintUtil")
local DataServer = nil

if RunService:IsServer() then
	DataServer = require("./Data/Server")
end

--[=[
	@class PlayerObject
	A wrapper class representing a Roblox player's session.
	Handles player-specific state machines, permission/authorization management, and profile data loading/saving.

	:::note
	Every `PlayerObject` has an associated `Keeper` bound to the lifecycle of the Roblox Player. Cleanup runs automatically on player departure.
	:::
]=]
local PlayerModule = {}
local PlayerObjects = {}

local PlayerClass = {}
PlayerClass.__index = PlayerClass

--[=[
	@prop Added Signal<Player>
	@within PlayerObject
	A global signal that fires when a raw Roblox Player joins the game.
]=]
PlayerModule.Added = Signal.new()

--[=[
	@prop Removing Signal<Player>
	@within PlayerObject
	A global signal that fires when a raw Roblox Player is leaving the game.
]=]
PlayerModule.Removing = Signal.new()

--[=[
	@prop Loaded Signal<PlayerObject>
	@within PlayerObject
	A global signal that fires when a player session wrapper is created and loaded.
]=]
PlayerModule.Loaded = Signal.new()

--[=[
	@prop Unloading Signal<PlayerObject>
	@within PlayerObject
	A global signal that fires when a player session wrapper is unloading/destroying.
]=]
PlayerModule.Unloading = Signal.new()

--[=[
	@prop PermissionsChanged Signal<PlayerObject, PermissionMap, PermissionMap>
	@within PlayerObject
	A global signal that fires when a player's permission set changes.
]=]
PlayerModule.PermissionsChanged = Signal.new()

--[=[
	@prop DataSaved Signal<PlayerObject, PlayerState>
	@within PlayerObject
	A global signal that fires when a player's state is saved or modified on the server.
]=]
PlayerModule.DataSaved = Signal.new()

local function clone_permissions(permissions)
	local clone = {}

	if type(permissions) ~= "table" then
		return clone
	end

	for permission, allowed in permissions do
		clone[permission] = not not allowed
	end

	return clone
end

local function permissions_equal(left, right)
	if left == right then
		return true
	end

	if type(left) ~= "table" or type(right) ~= "table" then
		return false
	end

	for key, value in left do
		if right[key] ~= value then
			return false
		end
	end

	for key, value in right do
		if left[key] ~= value then
			return false
		end
	end

	return true
end

--[=[
	@function new
	@within PlayerObject
	@param instance Player -- The raw Roblox Player instance to wrap.
	@return PlayerObject -- The initialized Player session wrapper.
	@tag constructor
	Creates a new `PlayerObject` wrapper. Attaches a `Keeper` to clean up connections on disconnect.
]=]
function PlayerModule.new(instance: Player)
	local self = setmetatable({}, PlayerClass)

	self.Keeper = Keeper.new()
	self.Keeper:AttachToInstance(instance)

	self.Instance = instance
	self.Character = instance.Character
	self.Entity = nil
	self.Data = nil
	self.Permissions = {}
	self._Destroyed = false
	PlayerObjects[instance] = self

	self.EntityId = `Player-{tostring(instance.UserId)}`
	self.Machines = {} :: { [string]: typeof(StateMachine.Machine.new("")) }

	local state_machine = self.Keeper:Construct(StateMachine.Machine.new, self.EntityId)
	self.State = state_machine
	self.Machines.State = state_machine

	self.Keeper:Connect(instance.CharacterAdded, function(character)
		self.Character = character
	end)

	self.Keeper:Connect(instance.CharacterRemoving, function(character)
		if self.Character == character then
			self.Character = nil
		end

		self.Entity = nil
	end)

	self.Keeper:Connect(self.Instance.AncestryChanged, function()
		if self.Instance:IsDescendantOf(game) then
			return
		end
		self:Destroy()
	end)

	PlayerModule.Loaded:Fire(self)

	return self
end

export type PlayerObject = typeof(PlayerModule.new(...))

--[=[
	@method Get
	@within PlayerObject
	@param instance Player -- The raw Roblox Player instance.
	@return PlayerObject? -- The cached player session wrapper if found.
	Retrieves the cached player session wrapper associated with a Roblox Player.
]=]
function PlayerModule.Get(instance: Player): PlayerObject?
	return PlayerObjects[instance]
end

--[=[
	@method _ApplyState
	@private
	@ignore
	@within PlayerObject
]=]
function PlayerClass._ApplyState(self: PlayerObject, state)
	local previous_permissions = self.Permissions
	self.Data = state
	self.Permissions = clone_permissions(type(state) == "table" and state.Permissions or nil)

	if not permissions_equal(previous_permissions, self.Permissions) then
		PlayerModule.PermissionsChanged:Fire(self, previous_permissions, self.Permissions)
	end

	return state
end

--[=[
	@method _SyncState
	@private
	@ignore
	@within PlayerObject
]=]
function PlayerClass._SyncState(self: PlayerObject, state)
	self.Data = state
	self.Permissions = clone_permissions(type(state) == "table" and state.Permissions or nil)
	return state
end

--[=[
	@method GetUserId
	@within PlayerObject
	@return number -- The player's UserId.
	Returns the player's Roblox UserId.
]=]
function PlayerClass.GetUserId(self: PlayerObject)
	return self.Instance.UserId
end

--[=[
	@method Machine
	@within PlayerObject
	@param id string -- The ID of the state machine
	@return Machine -- The state machine instance
	Gets or creates a hierarchical state machine for this player session.
]=]
function PlayerClass.Machine(self: PlayerObject, id: string)
	if self.Machines[id] then
		return self.Machines[id]
	end

	local machine = self.Keeper:Construct(StateMachine.Machine.new, `{self.EntityId}-{id}`)
	self.Machines[id] = machine

	return machine
end

--[=[
	@method RemoveMachine
	@within PlayerObject
	@param id string -- The ID of the state machine to remove
	Destroys and removes the specified state machine from the player session.
]=]
function PlayerClass.RemoveMachine(self: PlayerObject, id: string)
	local machine = self.Machines[id]
	if machine then
		self.Keeper:Remove(machine)
		self.Machines[id] = nil
	end
end

--[=[
	@method GetName
	@within PlayerObject
	@return string -- The player's username.
	Returns the player's Roblox Name.
]=]
function PlayerClass.GetName(self: PlayerObject)
	return self.Instance.Name
end

--[=[
	@method GetDisplayName
	@within PlayerObject
	@return string -- The player's display name.
	Returns the player's Roblox DisplayName.
]=]
function PlayerClass.GetDisplayName(self: PlayerObject)
	return self.Instance.DisplayName
end

--[=[
	@method BindCharacter
	@within PlayerObject
	@param character Model -- The character Model
	@param entity Entity -- The character Entity wrapper
	@return Model
	Binds the player session to a character Model and its Entity wrapper.
]=]
function PlayerClass.BindCharacter(self: PlayerObject, character: Model, entity)
	self.Character = character
	self.Entity = entity
	return character
end

--[=[
	@method UnbindCharacter
	@within PlayerObject
	@param character Model? -- The character Model to unbind (or current character if nil)
	Unbinds the player session from their character.
]=]
function PlayerClass.UnbindCharacter(self: PlayerObject, character)
	if character == nil or self.Character == character then
		self.Character = nil
		self.Entity = nil
	end
end

--[=[
	@method GetData
	@within PlayerObject
	@return PlayerState? -- The current player state
	Retrieves the player's current data state.

	:::caution
	On the client, this returns the local player's data state. Attempting to call this for other players on the client will return `nil`.
	:::
]=]
function PlayerClass.GetData(self: PlayerObject)
	if RunService:IsServer() then
		return self:_SyncState(DataServer:GetState(self.Instance))
	end

	if self.Instance ~= Players.LocalPlayer then
		return nil
	end

	return self:_SyncState(DataClient:GetState())
end

--[=[
	@method SetData
	@within PlayerObject
	@param next_state PlayerState -- The new state to apply.
	@return PlayerState -- The updated state.
	Overwrites the player's state. Replicates changes to the client and triggers saves.

	:::warning
	This method is **server-only**. Calling it on the client will print an error and do nothing.
	:::
]=]
function PlayerClass.SetData(self: PlayerObject, next_state)
	if not RunService:IsServer() then
		PrintUtil:Error("Cannot call ResetData from the client")
		return
	end

	local state = DataServer:SetState(self.Instance, next_state)
	self:_ApplyState(state)
	PlayerModule.DataSaved:Fire(self, state)
	return state
end

--[=[
	@method UpdateData
	@within PlayerObject
	@param updater (state: PlayerState) -> PlayerState -- Callback function that mutates state.
	@return PlayerState -- The updated state.
	Updates the player's state using a mutation callback function.

	:::warning
	This method is **server-only**. Calling it on the client will print an error and do nothing.
	:::
]=]
function PlayerClass.UpdateData(self: PlayerObject, updater)
	if not RunService:IsServer() then
		PrintUtil:Error("Cannot call ResetData from the client")
		return
	end

	local state = DataServer:UpdateState(self.Instance, updater)
	self:_ApplyState(state)
	PlayerModule.DataSaved:Fire(self, state)
	return state
end

--[=[
	@method Load
	@within PlayerObject
	@return Promise<PlayerState> -- Resolves when data loading completes.
	Initiates data loading from the datastore (server-only).

	:::warning
	This method is **server-only**. Calling it on the client resolves with a warning and does nothing.
	:::
]=]
function PlayerClass.Load(self: PlayerObject)
	if not RunService:IsServer() then
		return Promise.resolve("Cannot call Load from the client")
	end

	return DataServer:LoadPlayer(self.Instance):andThen(function(state)
		return state
	end)
end

--[=[
	@method Save
	@within PlayerObject
	@return Promise<PlayerState?> -- Resolves when data save completes.
	Saves the current state cache to the datastore (server-only).

	:::warning
	This method is **server-only**. Calling it on the client rejects the promise.
	:::
]=]
function PlayerClass.Save(self: PlayerObject)
	if not RunService:IsServer() then
		return Promise.reject("Cannot call Save from the client")
	end

	return DataServer:SavePlayer(self.Instance):andThen(function(state)
		if state ~= nil then
			return state
		end

		return state
	end)
end

--[=[
	@method ResetData
	@within PlayerObject
	@return PlayerState -- The reset state.
	Resets the player's data state back to the default config template (server-only).

	:::warning
	This method is **server-only**. Calling it on the client will print an error.
	:::
]=]
function PlayerClass.ResetData(self: PlayerObject)
	if not RunService:IsServer() then
		PrintUtil:Error("Cannot call ResetData from the client")
		return nil
	end

	local state = DataServer:ResetState(self.Instance)
	self:_ApplyState(state)
	PlayerModule.DataSaved:Fire(self, state)
	return state
end

--[=[
	@method HasPermission
	@within PlayerObject
	@param permission string -- The permission key to check
	@return boolean -- True if the player has the permission
	Checks if the player has the specified permission configuration.
]=]
function PlayerClass.HasPermission(self: PlayerObject, permission)
	return self.Permissions[permission] == true
end

--[=[
	@method SetPermission
	@within PlayerObject
	@param permission string -- The permission key
	@param allowed boolean -- Whether to allow or block the permission
	@return PlayerState -- The updated player state.
	Configures a permission for this player session (server-only).

	:::warning
	This method is **server-only**. Calling it on the client will print an error.
	:::
]=]
function PlayerClass.SetPermission(self: PlayerObject, permission, allowed)
	if not RunService:IsServer() then
		PrintUtil:Error("Cannot call SetPermission from the client")
		return
	end

	return self:UpdateData(function(state)
		state = type(state) == "table" and state or {}
		state.Permissions = type(state.Permissions) == "table" and state.Permissions or {}
		state.Permissions[permission] = not not allowed
		return state
	end)
end

--[=[
	@method GrantPermission
	@within PlayerObject
	@param permission string -- The permission key to grant
	@return PlayerState -- The updated player state.
	Grants the specified permission to the player (server-only).
]=]
function PlayerClass.GrantPermission(self: PlayerObject, permission)
	return self:SetPermission(permission, true)
end

--[=[
	@method RevokePermission
	@within PlayerObject
	@param permission string -- The permission key to revoke
	@return PlayerState -- The updated player state.
	Revokes the specified permission from the player (server-only).
]=]
function PlayerClass.RevokePermission(self: PlayerObject, permission)
	return self:SetPermission(permission, false)
end

--[=[
	@method Destroy
	@within PlayerObject
	Destroys the player session wrapper, cleaning up the internal `Keeper`.
]=]
function PlayerClass.Destroy(self: PlayerObject)
	if self._Destroyed then
		return
	end

	self._Destroyed = true
	PlayerModule.Unloading:Fire(self)
	self.Character = nil
	self.Entity = nil
	self.Data = nil
	self.Permissions = {}
	PlayerObjects[self.Instance] = nil
	self.Keeper:Destroy()
end

Players.PlayerAdded:Connect(function(player)
	PlayerModule.Added:Fire(player)
end)

Players.PlayerRemoving:Connect(function(player)
	PlayerModule.Removing:Fire(player)
end)

export type PermissionMap = { [string]: boolean }
export type PlayerState = Config.PlayerState

return PlayerModule
