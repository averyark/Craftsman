--!nonstrict
--[[
    FileName    > Entity.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 04/06/2026
--]]

const Players = game:GetService("Players")

const Keeper = require("../../../Keeper")
const Signal = require("./Signal")
const PrintUtil = require("./Utilities/PrintUtil")

local EntityModule = {}

EntityModule.Entities = {}

local Entity = {}
Entity.__index = Entity

EntityModule.Spawned = Signal.new()
EntityModule.Died = Signal.new()
EntityModule.Removing = Signal.new()

local function new(entity: Instance, player: Player?)
	PrintUtil:Assert(entity:IsA("Model"), "Invalid entity.")

	if EntityModule.Entities[entity] then
		return EntityModule.Entities[entity]
	end

	local self = setmetatable({}, Entity)

	self.Instance = entity
	self.Player = player or Players:GetPlayerFromCharacter(self.Instance)
	self.Humanoid = entity:WaitForChild("Humanoid")
	self.HumanoidRootPart = entity:WaitForChild("HumanoidRootPart")
	self.Keeper = Keeper.new()

	EntityModule.Entities[entity] = self
	self.Keeper:Add(function()
		EntityModule.Entities[entity] = nil
	end)

	entity.AncestryChanged:Connect(function()
		if entity:IsDescendantOf(game) then
			return
		end
		EntityModule.Died:Fire(self)
		self.Keeper:Destroy()
	end)

	EntityModule.Spawned:Fire(self)

	self.Humanoid.Died:Connect(function()
		EntityModule.Died:Fire(self)
		self.Keeper:Destroy()
	end)

	return self
end

function Entity:Destroy()
	EntityModule.Removing:Fire(self)

	self.Instance:Destroy()
	EntityModule.Entities[self.Instance] = nil
end

export type Entity = typeof(new(...))

function EntityModule.Get(character): Entity?
	return EntityModule.Entities[character] or new(character)
end

EntityModule.new = new

return EntityModule
