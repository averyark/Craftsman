--!strict
--[[
    FileName    > AnimationUtil.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 20/05/2026
--]]

const ContentProvider = game:GetService("ContentProvider")
const Players = game:GetService("Players")
const RunService = game:GetService("RunService")

const Promise = require("../../packages/roblox/Promise")
const TableUtil = require("./TableUtil")

--[=[
	@class AnimationUtil
	@ignore
	The constructor and entry point module for initiating character Animator utility managers.
]=]
local AnimationUtil = {}

--
type AnimationProperties = {
	FadeTime: number?,
	Weight: number?,
	Speed: number?,
	Priority: Enum.AnimationPriority?,
	Looped: boolean?,
}
--

--
const GlobalAnimate = setmetatable({}, { __mode = "k" }) :: { [Model | Humanoid | Animator | AnimationController]: Animate }
const GlobalAnimationRegistry = {} :: { [string]: Animation }
--

function AnimationUtil.QuickPlay(
	animator: Animator,
	animation_name: string,
	properties: AnimationProperties?
): AnimationTrack
	--
	const safe_props: AnimationProperties = properties or {}
	--

	--
	local animation = GlobalAnimationRegistry[animation_name]

	if not animation then
		error("Animation not found in global animation cache for QuickPlay.")
	end

	animation = animation:Clone()
	--

	--
	const track = animator:LoadAnimation(animation)

	track:Play(safe_props.FadeTime, safe_props.Weight, safe_props.Speed)
	--

	--
	if safe_props.Priority ~= nil then
		track.Priority = safe_props.Priority
	end

	if safe_props.Looped then
		warn("AnimationUtil.QuickPlay does not support looped animations; ignoring Looped.")
	end

	track.Looped = false
	--

	--
	track.Ended:Once(function()
		track:Destroy()
		animation:Destroy()
	end)
	--

	return track
end

function AnimationUtil.Register(animation_name: string, animation_id: string, should_preload: boolean?): Animation
	--
	const animation = Instance.new("Animation")
	animation.Name = animation_name
	animation.AnimationId = animation_id
	--

	--
	GlobalAnimationRegistry[animation_name] = animation
	--

	--
	if should_preload and RunService:IsClient() then
		Promise.try(function()
			ContentProvider:PreloadAsync({ animation })
		end):catch(function(err)
			warn(`Failed to preload animation '{animation_name}': {err}`)
		end)
	end
	--

	return animation
end

function AnimationUtil.BulkRegister(
	animations: { [string]: { AnimationId: string } & AnimationProperties },
	should_preload: boolean?
): { [string]: Animation }
	--
	const registered_animations: { [string]: Animation } = {}

	for animation_name, data in animations do
		registered_animations[animation_name] = AnimationUtil.Register(animation_name, data.AnimationId, false)
	end
	--

	--
	if should_preload and RunService:IsClient() then
		Promise.try(function()
			ContentProvider:PreloadAsync(TableUtil.Values(registered_animations))
		end):catch(function(err)
			warn(`Failed to preload animations: {err}`)
		end)
	end
	--

	return registered_animations
end

function AnimationUtil.Unregister(animation_name: string): boolean
	--
	const animation = GlobalAnimationRegistry[animation_name]

	if not animation then
		error(`AnimationUtil.Unregister: No animation found in registry with name '{animation_name}'.`)
	end
	--

	--
	animation:Destroy()
	GlobalAnimationRegistry[animation_name] = nil
	--

	return true
end

--
local Animate = {}
Animate.__index = Animate
--

local function new(container: Animator | Humanoid | Model | AnimationController)
	--
	const self = setmetatable({}, Animate)

	self.Container = container

	self.AnimationCache = {} :: { [string]: Animation }
	self.Tracks = {} :: { [string]: AnimationTrack }
	--

	return self
end

--
export type Animate = typeof(new(...))
--

local function register_track(
	self: Animate,
	track_name: string,
	animation: Animation,
	should_preload: boolean?
): AnimationTrack
	--
	const track: AnimationTrack = (self.Container :: any):LoadAnimation(animation)
	--

	--
	if self.Tracks[track_name] then
		self.Tracks[track_name]:Stop()
		self.Tracks[track_name]:Destroy()
	end

	if self.AnimationCache[track_name] then
		self.AnimationCache[track_name]:Destroy()
	end

	self.AnimationCache[track_name] = animation
	self.Tracks[track_name] = track
	--

	--
	if should_preload and RunService:IsClient() then
		Promise.try(function()
			ContentProvider:PreloadAsync({ animation })
		end):catch(function(err)
			warn(`Failed to preload animation '{track_name}': {err}`)
		end)
	end
	--

	return track
end

local function load_from_id(
	self: Animate,
	animation_name: string?,
	animation_id: string?,
	should_preload: boolean?
): AnimationTrack
	--
	if not animation_id or not animation_name then
		return error("Animate.Load: Expected both AnimationId and AnimationName in param.", 2)
	end
	--

	--
	const animation = Instance.new("Animation")
	animation.Name = animation_name or "UnnamedAnimation"
	animation.AnimationId = animation_id
	--

	return register_track(self, animation_name, animation, should_preload)
end

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
	if not param.FromRegistry then
		return load_from_id(self, param.AnimationName, param.AnimationId, param.ShouldPreload)
	end
	--

	--
	local clone = GlobalAnimationRegistry[param.FromRegistry]

	if not clone then
		error(`Animate.Load: No animation found in registry with name '{param.FromRegistry}'.`, 2)
	end

	clone = clone:Clone()
	clone.Name = param.AnimationName or param.FromRegistry
	--

	return register_track(self, param.AnimationName or param.FromRegistry, clone, param.ShouldPreload)
end

function Animate.Unload(self: Animate, animation_name: string): boolean
	--
	const animation = self.AnimationCache[animation_name]

	if not animation then
		error(`Animate.Unload: No animation found in cache with name '{animation_name}'.`, 2)
	end
	--

	--
	animation:Destroy()

	if self.Tracks[animation_name] then
		self.Tracks[animation_name]:Stop()
		self.Tracks[animation_name]:Destroy()
	end
	--

	--
	self.AnimationCache[animation_name] = nil
	self.Tracks[animation_name] = nil
	--

	return true
end

function Animate.Play(self: Animate, animation_name: string, properties: AnimationProperties?)
	--
	const track = self.Tracks[animation_name]

	if not track then
		error(`Animate.Play: No track found for animation with name '{animation_name}'.`, 2)
	end
	--

	--
	const safe_properties: AnimationProperties = properties or {}

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
	const track = self.Tracks[animation_name]

	if not track then
		error(`Animate.Stop: No track found for animation with name '{animation_name}'.`, 2)
	end
	--

	track:Stop(fade_time)
end

function Animate.StopAll(self: Animate, fade_time: number?)
	--
	for _, track in self.Tracks do
		track:Stop(fade_time)
	end
	--
end

function Animate.UnloadAll(self: Animate)
	--
	for animation_name in self.AnimationCache do
		self:Unload(animation_name)
	end
	--
end

function Animate.Destroy(self: Animate)
	--
	self:UnloadAll()
	self.Container = nil :: any
	--
end

function AnimationUtil.GetSharedAnimate(container: Animator | Humanoid | Model | AnimationController): Animate
	--
	if GlobalAnimate[container] then
		return GlobalAnimate[container]
	end
	--

	--
	const animate = new(container)
	GlobalAnimate[container] = animate

	container.Destroying:Once(function()
		GlobalAnimate[container] = nil
	end)
	--

	return animate
end

function AnimationUtil.GetLocalAnimate(): Animate?
	--
	const player = Players.LocalPlayer

	if not player then
		error("AnimationUtil.GetLocalAnimate: No local player found.")
	end

	const character = player.Character

	if not character then
		return nil
	end

	const humanoid = character:FindFirstChildOfClass("Humanoid")

	if not humanoid then
		return nil
	end

	const animator = humanoid:FindFirstChildOfClass("Animator")

	if not animator then
		return nil
	end
	--

	return AnimationUtil.GetSharedAnimate(animator)
end

--
AnimationUtil.new = new
--

return AnimationUtil
