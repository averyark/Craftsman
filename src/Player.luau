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

const PrintUtil = require("./Utilities/PrintUtil")
local DataServer = nil

if RunService:IsServer() then
	DataServer = require("./Data/Server")
end

local PlayerModule = {}

local PlayerClass = {}
PlayerClass.__index = PlayerClass

PlayerModule.Added = Signal.new()
PlayerModule.Removing = Signal.new()
PlayerModule.Loaded = Signal.new()
PlayerModule.Unloading = Signal.new()
PlayerModule.PermissionsChanged = Signal.new()
PlayerModule.DataSaved = Signal.new()

local function clone_permissions(permissions)
	local clone = {}

	if type(permissions) ~= "table" then
		return clone
	end

	for permission, allowed in  permissions do
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

	for key, value in  left do
		if right[key] ~= value then
			return false
		end
	end

	for key, value in  right do
		if left[key] ~= value then
			return false
		end
	end

	return true
end

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

function PlayerClass._ApplyState(self: PlayerObject, state)
	local previous_permissions = self.Permissions
	self.Data = state
	self.Permissions = clone_permissions(type(state) == "table" and state.Permissions or nil)

	if not permissions_equal(previous_permissions, self.Permissions) then
		PlayerModule.PermissionsChanged:Fire(self, previous_permissions, self.Permissions)
	end

	return state
end

function PlayerClass._SyncState(self: PlayerObject, state)
	self.Data = state
	self.Permissions = clone_permissions(type(state) == "table" and state.Permissions or nil)
	return state
end

function PlayerClass.GetUserId(self: PlayerObject)
	return self.Instance.UserId
end

function PlayerClass.GetName(self: PlayerObject)
	return self.Instance.Name
end

function PlayerClass.GetDisplayName(self: PlayerObject)
	return self.Instance.DisplayName
end

function PlayerClass.BindCharacter(self: PlayerObject, character: Model, entity)
	self.Character = character
	self.Entity = entity
	return character
end

function PlayerClass.UnbindCharacter(self: PlayerObject, character)
	if character == nil or self.Character == character then
		self.Character = nil
		self.Entity = nil
	end
end

function PlayerClass.GetData(self: PlayerObject)
	if RunService:IsServer() then
		return self:_SyncState(DataServer:GetState(self.Instance))
	end

	if self.Instance ~= Players.LocalPlayer then
		return nil
	end

	return self:_SyncState(DataClient:GetState())
end

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

function PlayerClass.Load(self: PlayerObject)
	if not RunService:IsServer() then
		return Promise.resolve("Cannot call Load from the client")
	end

	return DataServer:LoadPlayer(self.Instance):andThen(function(state)
		return state
	end)
end

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

function PlayerClass.HasPermission(self: PlayerObject, permission)
	return self.Permissions[permission] == true
end

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

function PlayerClass.GrantPermission(self: PlayerObject, permission)
	return self:SetPermission(permission, true)
end

function PlayerClass.RevokePermission(self: PlayerObject, permission)
	return self:SetPermission(permission, false)
end

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
