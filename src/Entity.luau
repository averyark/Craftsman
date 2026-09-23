--!strict
--[[
    FileName    > Entity.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 04/06/2026
--]]

const Players = game:GetService("Players")

const Keeper = require("../packages/roblox/Keeper")
const Signal = require("../packages/roblox/Signal")

local EntityModule = {}

--
EntityModule.Entities = {} :: { [Instance]: Entity }
--

--
local Entity = {}
Entity.__index = Entity
--

--
type EntityFields = {
	Instance: Model,
	Player: Player?,
	Humanoid: Humanoid,
	HumanoidRootPart: BasePart,
	Keeper: Keeper.Keeper,
}

export type Entity = typeof(setmetatable({} :: EntityFields, Entity))
--

--
const RIG_WAIT_TIMEOUT = 5
--

--
EntityModule.Spawned = Signal.new() :: Signal.Signal<Entity>
EntityModule.Died = Signal.new() :: Signal.Signal<Entity>
EntityModule.Removing = Signal.new() :: Signal.Signal<Entity>
--

local function new(entity: Instance, player: Player?): Entity
	--
	assert(entity:IsA("Model"), "Invalid entity.")

	if EntityModule.Entities[entity] then
		return EntityModule.Entities[entity]
	end
	--

	--
	const self = setmetatable({} :: EntityFields, Entity)

	self.Instance = entity :: Model
	self.Player = player or Players:GetPlayerFromCharacter(self.Instance)
	self.Humanoid = entity:WaitForChild("Humanoid", RIG_WAIT_TIMEOUT) :: Humanoid
	self.HumanoidRootPart = entity:WaitForChild("HumanoidRootPart", RIG_WAIT_TIMEOUT) :: BasePart
	--

	--
	if not self.Humanoid then
		error(`Entity.new: {entity:GetFullName()} has no Humanoid after {RIG_WAIT_TIMEOUT}s.`, 2)
	end

	if not self.HumanoidRootPart then
		error(`Entity.new: {entity:GetFullName()} has no HumanoidRootPart after {RIG_WAIT_TIMEOUT}s.`, 2)
	end
	--

	--
	self.Keeper = Keeper.new()

	EntityModule.Entities[entity] = self
	self.Keeper:Add(function()
		EntityModule.Entities[entity] = nil
	end)
	--

	--
	self.Keeper:Add(entity.AncestryChanged:Connect(function()
		if entity:IsDescendantOf(game) then
			return
		end

		EntityModule.Died:Fire(self)
		self.Keeper:Destroy()
	end))
	--

	--
	EntityModule.Spawned:Fire(self)
	--

	--
	self.Keeper:Add(self.Humanoid.Died:Connect(function()
		EntityModule.Died:Fire(self)
		self.Keeper:Destroy()
	end))
	--

	return self
end

--[=[
	Returns the entity's Humanoid, or nil if the rig has none.

	Never yields, unlike the `.Humanoid` field's `WaitForChild` in the constructor, and
	reads the rig as it is now rather than as it was at construction -- so it stays correct
	across a rig whose Humanoid is replaced or destroyed.

	@return Humanoid? -- The Humanoid, or nil.
]=]
function Entity.GetHumanoid(self: Entity): Humanoid?
	return self.Instance:FindFirstChildWhichIsA("Humanoid")
end

--[=[
	Returns the entity's root part, or nil if the rig has none.

	Prefers HumanoidRootPart and falls back to the model's PrimaryPart. Never yields.

	@return BasePart? -- The root part, or nil.
]=]
function Entity.GetRoot(self: Entity): BasePart?
	--
	const root = self.Instance:FindFirstChild("HumanoidRootPart")

	if root and root:IsA("BasePart") then
		return root
	end
	--

	return self.Instance.PrimaryPart
end

function Entity.Destroy(self: Entity)
	--
	EntityModule.Removing:Fire(self)
	--

	--
	self.Instance:Destroy()
	EntityModule.Entities[self.Instance] = nil
	--
end

function EntityModule.Get(character: Instance): Entity?
	return EntityModule.Entities[character] or new(character)
end

--
EntityModule.new = new
--

return EntityModule
