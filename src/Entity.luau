--!nonstrict
--[[
    FileName    > Entity.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 21/05/2026
--]]

const Players = game:GetService("Players")
const HttpService = game:GetService("HttpService")
const RunService = game:GetService("RunService")

const Keeper = require("../../../Keeper")
local Signal = require("./Signal")

const Player = require("./Player")
const StateMachine = require("./StateMachine")
const AnimationUtil = require("./Utilities/AnimationUtil")
const SoundUtil = require("./Utilities/SoundUtil")

local function is_airborne_state(state: Enum.HumanoidStateType)
	return state == Enum.HumanoidStateType.Jumping
		or state == Enum.HumanoidStateType.Freefall
		or state == Enum.HumanoidStateType.FallingDown
		or state == Enum.HumanoidStateType.Flying
end

local function resolve_entity_id(instance: Instance): string
	local entity_id = instance:GetAttribute("EntityId")
	if type(entity_id) == "string" and entity_id ~= "" then
		return entity_id
	end

	if RunService:IsServer() then
		entity_id = HttpService:GenerateGUID(false)
		instance:SetAttribute("EntityId", entity_id)
		return entity_id
	end

	return tostring(entity_id or instance.Name)
end

--[=[
	@class Entity
	A wrapper class representing a physical character model (NPC or Player Character) in the game.
	Provides quick access to its Humanoid, HumanoidRootPart, Animator, and helper wrappers for playing animations and sounds.

	:::note
	Every `Entity` has an associated `Keeper` that is bound to the lifespan of the Character Model. If the Model is destroyed in the workspace, the Entity will automatically clean itself up.
	:::
]=]
local Entity = {
	--[=[
		@prop Spawned Signal<Entity>
		@within Entity
		A global signal that fires whenever a new `Entity` is spawned/initialized.
	]=]
	Spawned = Signal.new() :: Signal.Signal<Entity>,

	--[CNET]
	--[=[
		@prop StateChanged Signal<Entity, Enum.HumanoidStateType, Enum.HumanoidStateType>
		@within Entity
		A global signal that fires when an entity's Humanoid state changes.
	]=]
	StateChanged = Signal.new() :: Signal.Signal<Entity, Enum.HumanoidStateType, Enum.HumanoidStateType>,

	--[CNET]
	--[=[
		@prop Removing Signal<Entity>
		@within Entity
		A global signal that fires when an entity is being removed (e.g. Model is being destroyed).
	]=]
	Removing = Signal.new() :: Signal.Signal<Entity>,

	--[CNET]
	--[=[
		@prop Jumping Signal<Entity, Enum.HumanoidStateType, Enum.HumanoidStateType>
		@within Entity
		A global signal that fires when the entity performs a jump state transition.
	]=]
	Jumping = Signal.new() :: Signal.Signal<Entity, Enum.HumanoidStateType, Enum.HumanoidStateType>,

	--[CNET]
	--[=[
		@prop Landing Signal<Entity, Enum.HumanoidStateType, Enum.HumanoidStateType>
		@within Entity
		A global signal that fires when the entity lands back on the ground after being airborne.
	]=]
	Landing = Signal.new() :: Signal.Signal<Entity, Enum.HumanoidStateType, Enum.HumanoidStateType>,

	--[CNET]
	--[=[
		@prop Died Signal<Entity>
		@within Entity
		A global signal that fires when the entity's Humanoid health reaches 0.
	]=]
	Died = Signal.new() :: Signal.Signal<Entity>,

	--[CNET]
	--[=[
		@prop Destroyed Signal<Entity>
		@within Entity
		A global signal that fires when the entity wrapper is completely destroyed.
	]=]
	Destroyed = Signal.new() :: Signal.Signal<Entity>,

	--[CNET]
	--[=[
		@prop HealthChanged Signal<Entity, number>
		@within Entity
		A global signal that fires when the entity's Humanoid health changes.
	]=]
	HealthChanged = Signal.new() :: Signal.Signal<Entity, number>,
}
local EntityObjects = {}

local EntityClass = {}
EntityClass.__index = EntityClass

--[=[
	@function new
	@within Entity
	@param instance Instance -- The character Model instance.
	@param player Player? -- Optional Player reference if the Character belongs to a player.
	@return Entity -- The initialized Entity wrapper.
	@tag constructor
	Creates a new `Entity` instance wrapping the character Model.

	:::info
	The constructor attaches a `Keeper` object to the model instance. Cleanup will run automatically when the Model's Destroying event fires.
	:::
]=]
function Entity.new(instance: Instance, player: Player?)
	local self = setmetatable({}, EntityClass)

	self.Keeper = Keeper.new()
	self.Keeper:AttachToInstance(instance)

	self.EntityId = resolve_entity_id(instance)
	self.Machines = {} :: { [string]: typeof(StateMachine.Machine.new("")) }

	local state_machine = self.Keeper:Construct(StateMachine.Machine.new, self.EntityId)
	self.State = state_machine
	self.Machines.State = state_machine

	self.Instance = instance
	local resolved_player = player or Players:GetPlayerFromCharacter(instance)
	self.PlayerObject = if resolved_player then Player.Get(resolved_player) else nil
	self.Player = resolved_player
	EntityObjects[instance] = self

	if self.PlayerObject and type((self.PlayerObject :: any).BindCharacter) == "function" then
		(self.PlayerObject :: any):BindCharacter(instance, self)
	end

	self.HumanoidRootPart = instance:WaitForChild("HumanoidRootPart") :: BasePart
	self.Humanoid = instance:WaitForChild("Humanoid") :: Humanoid
	self.Animator = self.Humanoid:WaitForChild("Animator") :: Animator
	self.Head = instance:WaitForChild("Head") :: BasePart

	self.Name = instance.Name
	self.RigType = self.Humanoid.RigType

	self.AnimationUtil = AnimationUtil.new(self.Animator)
	self.SoundUtil = SoundUtil.new(self.HumanoidRootPart)

	self.Keeper:Connect(self.Humanoid.Died, function()
		Entity.Died:Fire(self)
	end)
	self.Keeper:Connect(self.Humanoid.HealthChanged, function(health)
		Entity.HealthChanged:Fire(self, health)
	end)
	self.Keeper:Connect(self.Humanoid.StateChanged, function(old_state, new_state)
		Entity.StateChanged:Fire(self, old_state, new_state)

		if new_state == Enum.HumanoidStateType.Jumping then
			Entity.Jumping:Fire(self, old_state, new_state)
		end

		if is_airborne_state(old_state) and not is_airborne_state(new_state) then
			Entity.Landing:Fire(self, old_state, new_state)
		end
	end)
	self.Keeper:Connect(self.Instance.Destroying, function()
		Entity.Removing:Fire(self)
	end)
	self.Keeper:Connect(Player.Removing, function(player)
		if player == self.Player then
			Entity.Removing:Fire(self)
		end
	end)

	self._Destroyed = false
	Entity.Spawned:Fire(self)

	return self
end

export type Entity = typeof(Entity.new(...))

--[=[
	@method Get
	@within Entity
	@param instance Instance -- The Player or character Model.
	@return Entity? -- The cached Entity wrapper if it exists.
	Retrieves the cached Entity wrapper for a player or a character Model.
]=]
function Entity.Get(instance: Instance): Entity?
	if instance:IsA("Player") then
		local character = (instance :: Player).Character
		if character == nil then
			return nil
		end

		return EntityObjects[character]
	end

	return EntityObjects[instance]
end

--[=[
	@method Machine
	@within Entity
	@param id string -- The ID of the state machine
	@return CraftsmanMachine -- The state machine instance
	Gets or creates a hierarchical state machine for this entity.
]=]
function EntityClass.Machine(self: Entity, id: string)
	if self.Machines[id] then
		return self.Machines[id]
	end

	local machine = self.Keeper:Construct(StateMachine.Machine.new, `{self.EntityId}-{id}`)
	self.Machines[id] = machine

	return machine
end

--[=[
	@method RemoveMachine
	@within Entity
	@param id string -- The ID of the state machine to remove
	Destroys and removes the specified state machine from the entity.
]=]
function EntityClass.RemoveMachine(self: Entity, id: string)
	local machine = self.Machines[id]
	if machine then
		self.Keeper:Remove(machine)
		self.Machines[id] = nil
	end
end

--[=[
	@method IsAlive
	@within Entity
	@return boolean -- True if the entity is alive
	Returns whether the entity wrapper is not destroyed, has its Model parented in workspace, and has a Humanoid health greater than 0.
]=]
function EntityClass.IsAlive(self: Entity)
	return not self._Destroyed and self.Instance.Parent ~= nil and self.Humanoid.Health > 0
end

--[=[
	@method GetPosition
	@within Entity
	@return Vector3 -- The current 3D position
	Returns the 3D position of the entity's HumanoidRootPart.
]=]
function EntityClass.GetPosition(self: Entity)
	return self.HumanoidRootPart.Position
end

--[=[
	@method GetRootCFrame
	@within Entity
	@return CFrame -- The current CFrame matrix
	Returns the CFrame of the entity's HumanoidRootPart.
]=]
function EntityClass.GetRootCFrame(self: Entity)
	return self.HumanoidRootPart.CFrame
end

--[=[
	@method GetHealth
	@within Entity
	@return number -- Current health value
	Returns the current health of the entity's Humanoid.
]=]
function EntityClass.GetHealth(self: Entity)
	return self.Humanoid.Health
end

--[=[
	@method PlayAnimation
	@within Entity
	@param name string -- The animation name
	@param fade_time number? -- Optional fade duration
	@param weight number? -- Optional weight multiplier
	@param speed number? -- Optional speed multiplier
	Plays a named character animation on the entity.
]=]
function EntityClass.PlayAnimation(self: Entity, name, fade_time, weight, speed)
	return self.AnimationUtil:Play(name, fade_time, weight, speed)
end

--[=[
	@method PlayAnimationAsync
	@within Entity
	@param name string -- The animation name
	@param fade_time number? -- Optional fade duration
	@param weight number? -- Optional weight multiplier
	@param speed number? -- Optional speed multiplier
	@return Promise -- A promise that resolves when the animation track completes.
	Plays a named character animation and waits for it to complete.
]=]
function EntityClass.PlayAnimationAsync(self: Entity, name, fade_time, weight, speed)
	return self.AnimationUtil:PlayAsync(name, fade_time, weight, speed)
end

--[=[
	@method StopAnimation
	@within Entity
	@param name string -- The animation name
	@param fade_time number? -- Optional fade duration
	Stops the specified named animation.
]=]
function EntityClass.StopAnimation(self: Entity, name, fade_time)
	return self.AnimationUtil:Stop(name, fade_time)
end

--[=[
	@method StopAllAnimations
	@within Entity
	@param fade_time number? -- Optional fade duration
	Stops all active animations on the entity.
]=]
function EntityClass.StopAllAnimations(self: Entity, fade_time)
	return self.AnimationUtil:StopAll(fade_time)
end

--[=[
	@method PlaySound
	@within Entity
	@param name string -- The registered sound name
	@param properties SoundProperties? -- Optional sound properties
	Plays a named sound at the entity's position.
]=]
function EntityClass.PlaySound(self: Entity, name, properties)
	return self.SoundUtil:Play(name, properties)
end

--[=[
	@method PlaySoundAsync
	@within Entity
	@param name string -- The registered sound name
	@param properties SoundProperties? -- Optional sound properties
	@return Promise -- A promise that resolves when the sound completes playing.
	Plays a named sound and yields/waits until it ends.
]=]
function EntityClass.PlaySoundAsync(self: Entity, name, properties)
	return self.SoundUtil:PlayAsync(name, properties)
end

--[=[
	@method StopSound
	@within Entity
	@param name string -- The sound name
	Stops playing the specified named sound.
]=]
function EntityClass.StopSound(self: Entity, name)
	return self.SoundUtil:Stop(name)
end

--[=[
	@method StopAllSounds
	@within Entity
	Stops all active sounds on the entity.
]=]
function EntityClass.StopAllSounds(self: Entity)
	return self.SoundUtil:StopAll()
end

--[=[
	@method Destroy
	@within Entity
	Destroys the entity wrapper, releasing the character references and triggering cleanup on the internal `Keeper`.
]=]
function EntityClass.Destroy(self: Entity)
	if self._Destroyed then
		return
	end

	self._Destroyed = true
	Entity.Destroyed:Fire(self)
	EntityObjects[self.Instance] = nil

	if self.PlayerObject and type((self.PlayerObject :: any).UnbindCharacter) == "function" then
		(self.PlayerObject :: any):UnbindCharacter(self.Instance)
	end

	self.Keeper:Destroy()
end

return Entity
