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
local Signal = require("./Signal")

const PrintUtil = require("./Utilities/PrintUtil")
local DataServer = nil

if RunService:IsServer() then
	DataServer = require("./Data/Server")
end

local Player = {}
Player.__index = Player

Player.Added = Signal.new()
Player.Removing = Signal.new()
Player.Loaded = Signal.new()
Player.Unloading = Signal.new()
Player.PermissionsChanged = Signal.new()
Player.DataSaved = Signal.new()

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

	for key, value in next, left do
		if right[key] ~= value then
			return false
		end
	end

	for key, value in next, right do
		if left[key] ~= value then
			return false
		end
	end

	return true
end

function Player.new(instance: Player)
	local self = setmetatable({}, Player)

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

	Player.Loaded:Fire(self)

	return self
end

function Player:_ApplyState(state)
	local previous_permissions = self.Permissions
	self.Data = state
	self.Permissions = clone_permissions(type(state) == "table" and state.Permissions or nil)

	if not permissions_equal(previous_permissions, self.Permissions) then
		Player.PermissionsChanged:Fire(self, previous_permissions, self.Permissions)
	end

	return state
end

function Player:_SyncState(state)
	self.Data = state
	self.Permissions = clone_permissions(type(state) == "table" and state.Permissions or nil)
	return state
end

function Player:GetUserId()
	return self.Instance.UserId
end

function Player:GetName()
	return self.Instance.Name
end

function Player:GetDisplayName()
	return self.Instance.DisplayName
end

function Player:BindCharacter(character: Model, entity)
	self.Character = character
	self.Entity = entity
	return character
end

function Player:UnbindCharacter(character)
	if character == nil or self.Character == character then
		self.Character = nil
		self.Entity = nil
	end
end

function Player:GetData()
	if RunService:IsServer() then
		return self:_SyncState(DataServer:GetState(self.Instance))
	end

	if self.Instance ~= Players.LocalPlayer then
		return nil
	end

	return self:_SyncState(DataClient:GetState())
end

function Player:SetData(next_state)
	if not RunService:IsServer() then
		PrintUtil:Error("Cannot call ResetData from the client")
		return
	end

	local state = DataServer:SetState(self.Instance, next_state)
	self:_ApplyState(state)
	Player.DataSaved:Fire(self, state)
	return state
end

function Player:UpdateData(updater)
	if not RunService:IsServer() then
		PrintUtil:Error("Cannot call ResetData from the client")
		return
	end

	local state = DataServer:UpdateState(self.Instance, updater)
	self:_ApplyState(state)
	Player.DataSaved:Fire(self, state)
	return state
end

function Player:Load()
	if not RunService:IsServer() then
		return Promise.resolve("Cannot call Load from the client")
	end

	return DataServer:LoadPlayer(self.Instance):andThen(function(state)
		return state
	end)
end

function Player:Save()
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

function Player:ResetData()
	if not RunService:IsServer() then
		PrintUtil:Error("Cannot call ResetData from the client")
		return nil
	end

	local state = DataServer:ResetState(self.Instance)
	self:_ApplyState(state)
	Player.DataSaved:Fire(self, state)
	return state
end

function Player:HasPermission(permission)
	return self.Permissions[permission] == true
end

function Player:SetPermission(permission, allowed)
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

function Player:GrantPermission(permission)
	return self:SetPermission(permission, true)
end

function Player:RevokePermission(permission)
	return self:SetPermission(permission, false)
end

function Player:Destroy()
	if self._Destroyed then
		return
	end

	self._Destroyed = true
	Player.Unloading:Fire(self)
	self.Character = nil
	self.Entity = nil
	self.Data = nil
	self.Permissions = {}
	self.Keeper:Destroy()
end

Players.PlayerAdded:Connect(function(player)
	Player.Added:Fire(player)
end)

Players.PlayerRemoving:Connect(function(player)
	Player.Removing:Fire(player)
end)

export type PermissionMap = { [string]: boolean }
export type PlayerState = typeof(Config.DATA.TEMPLATE)

export type PlayerObject = {
	Keeper: any,
	Instance: Player,
	Character: Model?,
	Entity: any,
	Data: PlayerState,
	Permissions: PermissionMap,
	_Destroyed: boolean,

	GetUserId: (self: PlayerObject) -> number,
	GetName: (self: PlayerObject) -> string,
	GetDisplayName: (self: PlayerObject) -> string,
	BindCharacter: (self: PlayerObject, character: Model, entity: any) -> Model,
	UnbindCharacter: (self: PlayerObject, character: Model?) -> (),
	GetData: (self: PlayerObject) -> PlayerState,
	SetData: (self: PlayerObject, next_state: PlayerState) -> PlayerState,
	UpdateData: (self: PlayerObject, updater: (PlayerState) -> PlayerState) -> PlayerState,
	Load: (self: PlayerObject) -> any,
	Save: (self: PlayerObject) -> any,
	ResetData: (self: PlayerObject) -> PlayerState,
	HasPermission: (self: PlayerObject, permission: string) -> boolean,
	SetPermission: (self: PlayerObject, permission: string, allowed: boolean) -> any,
	GrantPermission: (self: PlayerObject, permission: string) -> any,
	RevokePermission: (self: PlayerObject, permission: string) -> any,
	Destroy: (self: PlayerObject) -> (),
}

type PlayerModule = {
	new: (instance: Player) -> PlayerObject,
	Added: Signal.Signal<Player>,
	Removing: Signal.Signal<Player>,
	Loaded: Signal.Signal<PlayerObject>,
	Unloading: Signal.Signal<PlayerObject>,
	PermissionsChanged: Signal.Signal<PlayerObject, PermissionMap, PermissionMap>,
	DataSaved: Signal.Signal<PlayerObject, PlayerState>,
}

return (Player :: any) :: PlayerModule
