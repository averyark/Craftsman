--!nonstrict
--[[
    FileName    > AnimationUtil.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 20/05/2026
--]]

const ContentProvider = game:GetService("ContentProvider")
const Players = game:GetService("Players")
const RunService = game:GetService("RunService")

const Promise = require("../../../../Promise")
const PrintUtil = require("./PrintUtil")
const TableUtil = require("./TableUtil")

--[=[
	@class AnimationUtil
	@ignore
	The constructor and entry point module for initiating character Animator utility managers.
]=]
--
local AnimationUtil = {}

type AnimationProperties = {
	FadeTime: number?,
	Weight: number?,
	Speed: number?,
	Priority: Enum.AnimationPriority?,
	Looped: boolean?,
}

local GlobalAnimate = {} :: { [Model | Humanoid | Animator | AnimationController]: Animate }
local GlobalAnimationRegistry = {} :: { [string]: Animation }

function AnimationUtil.QuickPlay(
	animator: Animator,
	animation_name: string,
	properties: AnimationProperties?
): AnimationTrack
	local safe_props = properties or {}

	local animation = GlobalAnimationRegistry[animation_name]
	if not animation then
		error("Animation not found in global animation cache for QuickPlay.", 2)
	end

	animation = animation:Clone()

	--
	local track = animator:LoadAnimation(animation)

	track:Play(safe_props.FadeTime, safe_props.Weight, safe_props.Speed)
	--

	--
	if safe_props.Priority ~= nil then
		track.Priority = safe_props.Priority
	end

	if safe_props.Looped ~= nil then
		track.Looped = safe_props.Looped
	end
	--

	track.Ended:Once(function()
		track:Stop(safe_props.FadeTime)
		track:Destroy()
		animation:Destroy()
	end)

	return track
end

function AnimationUtil.Register(
	animation_name: string,
	animation_id: string,
	properties: AnimationProperties?,
	should_preload: boolean?
)
	--
	local animation = Instance.new("Animation")
	animation.Name = animation_name
	animation.AnimationId = animation_id
	--

	GlobalAnimationRegistry[animation_name] = animation

	--
	if should_preload and RunService:IsClient() then
		Promise.try(function()
			ContentProvider:PreloadAsync({ animation })
		end):catch(function(err)
			PrintUtil:Warn("Failed to preload animation '" .. animation_name .. "': " .. tostring(err), 2)
		end)
	end
	--

	return animation
end

function AnimationUtil.BulkRegister(
	animations: { [string]: { AnimationId: string } & AnimationProperties },
	should_preload: boolean?
)
	local registered_animations = {}
	for animation_name, data in animations do
		registered_animations[animation_name] = AnimationUtil.Register(animation_name, data.AnimationId, data)
	end

	if should_preload and RunService:IsClient() then
		Promise.try(function()
			ContentProvider:PreloadAsync(TableUtil.Values(registered_animations))
		end):catch(function(err)
			PrintUtil:Warn("Failed to preload animations: " .. tostring(err), 2)
		end)
	end

	return registered_animations
end

function AnimationUtil.Unregister(animation_name: string)
	local animation_id = GlobalAnimationRegistry[animation_name]
	if not animation_id then
		PrintUtil:Error(
			"AnimationUtil.Unregister: No animation found in registry with name '" .. animation_name .. "'.",
			2
		)
	end

	GlobalAnimationRegistry[animation_name] = nil
	return true
end

local Animate = {}
Animate.__index = Animate

local function new(container: Animator | Humanoid | Model | AnimationController)
	local self = setmetatable({}, Animate)

	self.Container = container

	self.AnimationCache = {} :: { [string]: Animation }
	self.Tracks = {} :: { [string]: AnimationTrack }

	return self
end

export type Animate = typeof(new(...))

function Animate.Load(
	self: Animate,
	param: {
		AnimationName: string?,
		AnimationId: string?,
		FromRegistry: string?,
		ShouldPreload: boolean?,
	} & AnimationProperties
): AnimationTrack
	--
	if param.FromRegistry then
		--
		local clone = GlobalAnimationRegistry[param.FromRegistry]
		if not clone then
			PrintUtil:Error("Animate.Load: No animation found in registry with name '" .. param.FromRegistry .. "'.", 2)
		end

		clone = clone:Clone()
		--

		clone.Name = param.AnimationName or param.FromRegistry

		local track = self.Container:LoadAnimation(clone)

		self.AnimationCache[param.AnimationName or param.FromRegistry] = clone
		self.Tracks[param.AnimationName or param.FromRegistry] = track

		--
		if param.ShouldPreload and RunService:IsClient() then
			Promise.try(function()
				ContentProvider:PreloadAsync({ clone })
			end):catch(function(err)
				PrintUtil:Warn(
					"Failed to preload animation '"
						.. (param.AnimationName or param.FromRegistry)
						.. "': "
						.. tostring(err),
					2
				)
			end)
		end
		--

		return track
	end
	--

	assert(param.AnimationId and param.AnimationName, "Expected AnimationId and AnimationName")

	--
	local animation = Instance.new("Animation")
	animation.Name = param.AnimationName or "UnnamedAnimation"
	animation.AnimationId = param.AnimationId
	--

	--
	local track = self.Container:LoadAnimation(animation)

	self.AnimationCache[param.AnimationName] = animation
	self.Tracks[param.AnimationName] = track
	--

	--
	if param.ShouldPreload and RunService:IsClient() then
		Promise.try(function()
			ContentProvider:PreloadAsync({ animation })
		end):catch(function(err)
			PrintUtil:Warn(
				"Failed to preload animation '" .. (param.AnimationName or param.FromRegistry) .. "': " .. tostring(err),
				2
			)
		end)
	end
	--

	return track
end

function Animate.Unload(self: Animate, animation_name: string)
	--
	local animation = self.AnimationCache[animation_name]
	if not animation then
		PrintUtil:Error("Animate.Unload: No animation found in cache with name '" .. animation_name .. "'.", 2)
	end
	--
	animation:Destroy()

	if self.Tracks[animation_name] then
		self.Tracks[animation_name]:Stop()
		self.Tracks[animation_name]:Destroy()
	end

	--
	self.AnimationCache[animation_name] = nil
	self.Tracks[animation_name] = nil
	--
	return true
end

function Animate.Play(self: Animate, animation_name: string, properties: AnimationProperties?)
	--
	local track = self.Tracks[animation_name]
	if not track then
		PrintUtil:Error("Animate.Play: No track found for animation with name '" .. animation_name .. "'.", 2)
	end
	--

	local safe_properties = properties or {}

	--
	track:Play(safe_properties.FadeTime, safe_properties.Weight, safe_properties.Speed)
	--

	--
	if safe_properties.Priority ~= nil then
		track.Priority = safe_properties.Priority
	end

	if safe_properties.Looped ~= nil then
		track.Looped = safe_properties.Looped
	end
	--
end

function Animate.Stop(self: Animate, animation_name: string, fade_time: number?)
	--
	local track = self.Tracks[animation_name]
	if not track then
		PrintUtil:Error("Animate.Stop: No track found for animation with name '" .. animation_name .. "'.", 2)
	end
	--

	track:Stop(fade_time)
end

function Animate.StopAll(self: Animate, fade_time: number?)
	for _, track in self.Tracks do
		track:Stop(fade_time)
	end
end

function Animate.UnloadAll(self: Animate)
	for animation_name in self.AnimationCache do
		self:Unload(animation_name)
	end
end

function Animate.Destroy(self: Animate)
	self:UnloadAll()
	self.Container = nil
end

function Animate.GetSharedAnimate(container: Animator | Humanoid | Model | AnimationController): Animate
	--
	if GlobalAnimate[container] then
		return GlobalAnimate[container]
	end
	--

	--
	local animate = new(container)
	GlobalAnimate[container] = animate

	container.Destroying:Once(function()
		GlobalAnimate[container] = nil
	end)
	--

	return animate
end

function Animate.GetLocalAnimate()
	--
	local player = Players.LocalPlayer
	if not player then
		PrintUtil:Error("Animate.GetLocalAnimate: No local player found.", 2)
	end

	local character = player.Character
	if not character then
		return
	end
	--

	return Animate.GetSharedAnimate(character)
end

AnimationUtil.new = new

return AnimationUtil
