--!nonstrict
--[[
    FileName    > AnimationUtil.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 20/05/2026
--]]

const Keeper = require("../../../../Keeper")
const Promise = require("../../../../Promise")
const Signal = require("../../../../Signal")

local AnimationUtilModule = {}

local AnimationUtil = {}
AnimationUtil.__index = AnimationUtil

type AnimationMap = { [string]: string }
type PromiseLike = typeof(Promise.new(function() end))

function AnimationUtilModule.new(animator: Animator, animation_map: AnimationMap?)
	local self = setmetatable({}, AnimationUtil)
	self.Keeper = Keeper.new()

	self.Animator = animator
	self.AnimationMap = animation_map or {}
	self.AnimationInstances = {}
	self.Tracks = {}
	self.ActivePromises = {} :: { [string]: PromiseLike }

	-- Keeper:Construct automatically cleans up the signals when the component dies
	self.OnPlay = self.Keeper:Construct(Signal)
	self.OnStop = self.Keeper:Construct(Signal)

	return self
end

export type AnimationUtil = typeof(AnimationUtilModule.new(...))

function AnimationUtil.AddAnimationId(self: AnimationUtil, name: string, animation_id: string)
	self.AnimationMap[name] = animation_id
end

function AnimationUtil._StopLoadedAnimation(self: AnimationUtil, name: string, fade_time: number?)
	local track = self.Tracks[name]
	if not track then
		return
	end

	if self.ActivePromises[name] then
		self.ActivePromises[name]:cancel()
		return
	end

	track:Stop(fade_time)
	self.OnStop:Fire(name, track)
end

function AnimationUtil._RemoveLoadedAnimation(self: AnimationUtil, name: string, fade_time: number?)
	local track = self.Tracks[name]
	if track then
		self:_StopLoadedAnimation(name, fade_time)
		self.Keeper:Remove(track)
		self.Tracks[name] = nil
	end

	local animation_instance = self.AnimationInstances[name]
	if animation_instance then
		self.Keeper:Remove(animation_instance)
		self.AnimationInstances[name] = nil
	end

	self.AnimationMap[name] = nil
end

function AnimationUtil.RemoveAnimation(self: AnimationUtil, name: string, fade_time: number?)
	self:_RemoveLoadedAnimation(name, fade_time)
end

function AnimationUtil.RemoveAnimationId(self: AnimationUtil, animation_id: string, fade_time: number?)
	local names_to_remove = {}

	for name, registered_animation_id in self.AnimationMap do
		if registered_animation_id == animation_id then
			names_to_remove[#names_to_remove + 1] = name
		end
	end

	for index = 1, #names_to_remove do
		local name = names_to_remove[index]
		self:_RemoveLoadedAnimation(name, fade_time)
	end
end

function AnimationUtil.Load(self: AnimationUtil, name: string): AnimationTrack
	local animation_instance = Instance.new("Animation")
	animation_instance.AnimationId = self.AnimationMap[name]
	animation_instance.Name = name

	self.Keeper:Add(animation_instance)
	self.AnimationInstances[name] = animation_instance

	local track = self.Animator:LoadAnimation(animation_instance)
	track.Name = name

	self.Keeper:Add(track)
	self.Tracks[name] = track

	return track
end

function AnimationUtil.EnsureLoaded(self: AnimationUtil, name: string): AnimationTrack
	if self.Tracks[name] then
		return self.Tracks[name]
	end

	return self:Load(name)
end

function AnimationUtil.Play(self: AnimationUtil, name: string, fade_time: number?, weight: number?, speed: number?)
	local track = self:EnsureLoaded(name)

	track:Play(fade_time, weight, speed)
	self.OnPlay:Fire(name, track)
end

function AnimationUtil.PlayAsync(
	self: AnimationUtil,
	name: string,
	fade_time: number?,
	weight: number?,
	speed: number?
): PromiseLike
	local track = self:EnsureLoaded(name)

	-- Cancel the existing promise if this animation is already playing
	if self.ActivePromises[name] then
		self.ActivePromises[name]:cancel()
	end

	track:Play(fade_time, weight, speed)
	self.OnPlay:Fire(name, track)

	local play_promise = Promise.new(function(resolve, _, on_cancel)
		local connection = track.Ended:Once(function()
			self.OnStop:Fire(name, track)
			self.ActivePromises[name] = nil
			resolve(true)
		end)

		-- If the promise is cancelled (e.g. stopped early), clean up the thread
		on_cancel(function()
			connection:Disconnect()
			track:Stop(fade_time)
			self.OnStop:Fire(name, track)
			self.ActivePromises[name] = nil
		end)
	end)

	self.ActivePromises[name] = play_promise
	return play_promise
end

function AnimationUtil.Stop(self: AnimationUtil, name: string, fade_time: number?)
	local track = self.Tracks[name]
	if not track then
		return
	end

	if self.ActivePromises[name] then
		self.ActivePromises[name]:cancel()
	else
		track:Stop(fade_time)
		self.OnStop:Fire(name, track)
	end
end

function AnimationUtil.StopAll(self: AnimationUtil, fade_time: number?)
	for name in self.Tracks do
		self:Stop(name, fade_time)
	end
end

function AnimationUtil.OnMarker(self: AnimationUtil, name: string, marker_name: string, callback: () -> ())
	local track = self:EnsureLoaded(name)

	local connection = track:GetMarkerReachedSignal(marker_name):Connect(callback)
	self.Keeper:Add(connection)

	return connection
end

function AnimationUtil.MarkerAsync(self: AnimationUtil, name: string, marker_name: string): PromiseLike
	local track = self:EnsureLoaded(name)

	-- Creates a promise that resolves exactly when the event fires
	return Promise.fromEvent(track:GetMarkerReachedSignal(marker_name))
end

return AnimationUtilModule
