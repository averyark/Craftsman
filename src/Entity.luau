--!nonstrict
--[[
    FileName    > Entity.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 21/05/2026
--]]

const Players = game:GetService("Players")

const Keeper = require("../../../Keeper")
local Signal = require("./Signal")

const Player = require("./Player")
const AnimationUtil = require("./Utilities/AnimationUtil")
const SoundUtil = require("./Utilities/SoundUtil")

local function is_airborne_state(state: Enum.HumanoidStateType)
	return state == Enum.HumanoidStateType.Jumping
		or state == Enum.HumanoidStateType.Freefall
		or state == Enum.HumanoidStateType.FallingDown
		or state == Enum.HumanoidStateType.Flying
end

local Entity = {
	Spawned = Signal.new() :: Signal.Signal<Entity>,
	StateChanged = Signal.new() :: Signal.Signal<Entity, Enum.HumanoidStateType, Enum.HumanoidStateType>,
	Removing = Signal.new() :: Signal.Signal<Entity>,
	Jumping = Signal.new() :: Signal.Signal<Entity, Enum.HumanoidStateType, Enum.HumanoidStateType>,
	Landing = Signal.new() :: Signal.Signal<Entity, Enum.HumanoidStateType, Enum.HumanoidStateType>,
	Died = Signal.new() :: Signal.Signal<Entity>,
	Destroyed = Signal.new() :: Signal.Signal<Entity>,
	HealthChanged = Signal.new() :: Signal.Signal<Entity, number>,
}
local EntityObjects = {}

local EntityClass = {}
EntityClass.__index = EntityClass

function Entity.new(instance: Instance, player: Player?)
	local self = setmetatable({}, EntityClass)

	self.Keeper = Keeper.new()
	self.Keeper:AttachToInstance(instance)

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

function EntityClass.IsAlive(self: Entity)
	return not self._Destroyed and self.Instance.Parent ~= nil and self.Humanoid.Health > 0
end

function EntityClass.GetPosition(self: Entity)
	return self.HumanoidRootPart.Position
end

function EntityClass.GetRootCFrame(self: Entity)
	return self.HumanoidRootPart.CFrame
end

function EntityClass.GetHealth(self: Entity)
	return self.Humanoid.Health
end

function EntityClass.PlayAnimation(self: Entity, name, fade_time, weight, speed)
	return self.AnimationUtil:Play(name, fade_time, weight, speed)
end

function EntityClass.PlayAnimationAsync(self: Entity, name, fade_time, weight, speed)
	return self.AnimationUtil:PlayAsync(name, fade_time, weight, speed)
end

function EntityClass.StopAnimation(self: Entity, name, fade_time)
	return self.AnimationUtil:Stop(name, fade_time)
end

function EntityClass.StopAllAnimations(self: Entity, fade_time)
	return self.AnimationUtil:StopAll(fade_time)
end

function EntityClass.PlaySound(self: Entity, name, properties)
	return self.SoundUtil:Play(name, properties)
end

function EntityClass.PlaySoundAsync(self: Entity, name, properties)
	return self.SoundUtil:PlayAsync(name, properties)
end

function EntityClass.StopSound(self: Entity, name)
	return self.SoundUtil:Stop(name)
end

function EntityClass.StopAllSounds(self: Entity)
	return self.SoundUtil:StopAll()
end

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
