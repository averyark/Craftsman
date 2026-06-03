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

--[=[
	@class AnimationUtilModule
	@ignore
	The constructor and entry point module for initiating character Animator utility managers.
]=]
--
local AnimationUtilModule = {}

--[=[
	@class AnimationUtil
	An object-oriented instance that manages loading, caching, playback, stopping, promise waits, and event markers for a single Roblox Animator.
]=]
--
local AnimationUtil = {}
AnimationUtil.__index = AnimationUtil

type AnimationProperties = {
	FadeTime: number?,
	Weight: number?,
	Speed: number?,
	Priority: Enum.AnimationPriority?,
	Looped: boolean?,
}
type AnimationMap = { [string]: string }
type PromiseLike = typeof(Promise.new(function() end))

local AnimationUtilCache = {} :: { [Animator]: AnimationUtil }
local GlobalAnimationRegistry = {}

--[=[
	Registers an animation name or dictionary of name-to-AssetId mappings globally.
	Any AnimationUtil instance will fallback to this registry when loading/playing animations by name.
	@within AnimationUtil
	@param name_or_map string | { [string]: string } -- The animation name or a mapping dictionary.
	@param animation_id string? -- The animation AssetId (required if first argument is a name).
]=]
--
function AnimationUtilModule.Register(name_or_map: string | { [string]: string }, animation_id: string?)
	if typeof(name_or_map) == "table" then
		for key, value in name_or_map do
			GlobalAnimationRegistry[key] = value
		end
	else
		GlobalAnimationRegistry[name_or_map] = animation_id
	end
end

--[=[
	Creates or retrieves a cached AnimationUtil instance for the specified Roblox Animator.
	@within AnimationUtil
	@param animator Animator -- The target Animator instance.
	@param animation_map AnimationMap? -- Optional mapping dictionary of animation names to AssetIds.
	@param force_new boolean? -- Set to `true` to bypass cache retrieval and force create a new instance.
	@return AnimationUtil -- The AnimationUtil instance.
	@tag constructor
]=]
--
function AnimationUtilModule.new(animator: Animator, animation_map: AnimationMap?, force_new: boolean?)
	if not force_new then
		local cached_anim_util = AnimationUtilCache[animator]
		if cached_anim_util then
			return cached_anim_util
		end
	end

	local self = setmetatable({}, AnimationUtil)
	self.Keeper = Keeper.new()
	self.Keeper:AttachToInstance(animator)
	self.Keeper:Add(function()
		AnimationUtilCache[animator] = nil
	end)

	self.Animator = animator
	self.AnimationMap = setmetatable(animation_map or {}, { __index = GlobalAnimationRegistry })
	self.AnimationInstances = {}
	self.Tracks = {}
	self.ActivePromises = {} :: { [string]: PromiseLike }

	-- Keeper:Construct automatically cleans up the signals when the component dies
	self.OnPlay = self.Keeper:Construct(Signal)
	self.OnStop = self.Keeper:Construct(Signal)

	if not force_new then
		AnimationUtilCache[animator] = self
	end

	return self
end

--[=[
	@function Get
	@within AnimationUtil
	Alias for new. Retrieves or instantiates an AnimationUtil manager.
	@param animator Animator -- The target Animator.
	@param animation_map AnimationMap? -- Optional animation mapping.
	@param force_new boolean? -- Bypasses cache check.
	@return AnimationUtil -- The AnimationUtil instance.
]=]
--
AnimationUtilModule.Get = AnimationUtilModule.new

export type AnimationUtil = typeof(AnimationUtilModule.new(...))

--[=[
	Registers an animation name to an AssetId mapping for this manager.
	If animation_id is not specified, it will be derived from the global cache.
	@param name string -- The name key.
	@param animation_id string? -- The asset ID (e.g. `rbxassetid://...`). If omitted, derives from the global cache.
]=]
--
function AnimationUtil.AddAnimationId(self: AnimationUtil, name: string, animation_id: string?)
	local resolved_id = animation_id or self.AnimationMap[name]
	if not resolved_id then
		error("AnimationId not specified and name '" .. name .. "' not found in global animation cache.", 2)
	end

	self.AnimationMap[name] = resolved_id
end

--[=[
	Alias for AddAnimationId. Registers an animation name.
	@param name string -- The name key.
	@param animation_id string? -- The asset ID. If omitted, derives from the global cache.
]=]
--
function AnimationUtil.AddAnimation(self: AnimationUtil, name: string, animation_id: string?)
	self:AddAnimationId(name, animation_id)
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

	self.ActivePromises[name] = nil
	self.AnimationMap[name] = nil
end

--[=[
	Stops, destroys, and unregisters a loaded animation track and instance by name.
	@param name string -- The registered animation name.
	@param fade_time number? -- The fade transition duration.
]=]
--
function AnimationUtil.RemoveAnimation(self: AnimationUtil, name: string, fade_time: number?)
	self:_RemoveLoadedAnimation(name, fade_time)
end

--[=[
	Stops, destroys, and unregisters all matching loaded animations by AssetId.
	@param animation_id string -- The asset ID.
	@param fade_time number? -- The fade transition duration.
]=]
--
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

--[[
	Cleans up, disconnects, and destroys the AnimationUtil instance, removing it from cache.
]]
--
function AnimationUtil.Destroy(self: AnimationUtil)
	AnimationUtilCache[self.Animator] = nil
	self.Keeper:Destroy()
	self.AnimationInstances = nil
	self.Tracks = nil
	self.ActivePromises = nil
	self.AnimationMap = nil
end

--[=[
	Instantiates and loads a raw AnimationInstance onto the Animator.
	@param name string -- The registered name key to load.
	@return AnimationTrack -- The loaded playable AnimationTrack.
]=]
--
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

--[=[
	Ensures an animation is loaded, retrieving the cached AnimationTrack or loading it if missing.
	@param name string -- The registered name key.
	@return AnimationTrack -- The loaded AnimationTrack.
]=]
--
function AnimationUtil.EnsureLoaded(self: AnimationUtil, name: string): AnimationTrack
	if self.Tracks[name] then
		return self.Tracks[name]
	end

	return self:Load(name)
end

--[=[
	Plays a registered animation track on the Animator.
	@param name string -- The registered animation name.
	@param fade_time number? -- The fade transition duration.
	@param weight number? -- The track weight multiplier.
	@param speed number? -- The playback speed multiplier.
]=]
--
function AnimationUtil.Play(self: AnimationUtil, name: string, fade_time: number?, weight: number?, speed: number?)
	local track = self:EnsureLoaded(name)

	track:Play(fade_time, weight, speed)
	self.OnPlay:Fire(name, track)
end

--[=[
	Plays a registered animation track and returns a Promise that resolves when the animation finishes playing.
	Cancels any existing active promise on the same track if already playing.
	@param name string -- The registered animation name.
	@param fade_time number? -- The fade transition duration.
	@param weight number? -- The track weight multiplier.
	@param speed number? -- The playback speed multiplier.
	@return Promise -- A promise that resolves when the track completes.
]=]
--
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

--[=[
	Stops a playing animation track by name.
	@param name string -- The animation name.
	@param fade_time number? -- The fade out transition duration.
]=]
--
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

--[=[
	Stops all active animation tracks managed by this instance.
	@param fade_time number? -- The fade out duration.
]=]
--
function AnimationUtil.StopAll(self: AnimationUtil, fade_time: number?)
	for name in self.Tracks do
		self:Stop(name, fade_time)
	end
end

--[=[
	Connects a callback function to trigger when a specific named animation marker event is reached.
	@param name string -- The animation name.
	@param marker_name string -- The animation marker event name.
	@param callback () -> () -- The callback to trigger.
	@return RBXScriptConnection -- The connection instance (automatically managed by the instance's Keeper).
]=]
--
function AnimationUtil.OnMarker(self: AnimationUtil, name: string, marker_name: string, callback: () -> ())
	local track = self:EnsureLoaded(name)

	local connection = track:GetMarkerReachedSignal(marker_name):Connect(callback)
	self.Keeper:Add(connection)

	return connection
end

--[=[
	Creates a Promise that resolves when a specific named animation marker event is reached.
	@param name string -- The animation name.
	@param marker_name string -- The animation marker event name.
	@return Promise -- A promise that resolves when the marker signal fires.
]=]
--
function AnimationUtil.MarkerAsync(self: AnimationUtil, name: string, marker_name: string): PromiseLike
	local track = self:EnsureLoaded(name)

	-- Creates a promise that resolves exactly when the event fires
	return Promise.fromEvent(track:GetMarkerReachedSignal(marker_name))
end

--[=[
	Plays an animation instantly on a target Animator using a dictionary of options or an animation name.
	Automatically manages creating, playing, and stopping/destroying the track when finished.
	@within AnimationUtil
	@param animator Animator -- The target Animator.
	@param animation_name string -- The registered animation name or asset ID.
	@param properties AnimationProperties -- Dictionary of properties for the animation:
		- FadeTime: number? -- The fade transition duration.
		- Weight: number? -- The weight of the animation track.
		- Speed: number? -- The playback speed.
		- Priority: Enum.AnimationPriority? -- The priority of the animation.
		- Looped: boolean? -- Whether the animation loops.
	@return AnimationTrack -- The created AnimationTrack.
]=]
--
function AnimationUtilModule.QuickPlay(
	animator: Animator,
	animation_name: string,
	properties: AnimationProperties?
): AnimationTrack
	local safe_props = properties or {}

	local animation_id = GlobalAnimationRegistry[animation_name]
	if not animation_id then
		error("AnimationId not specified and Name not found in global animation cache for QuickPlay.", 2)
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = animation_id

	local track = animator:LoadAnimation(animation)
	animation:Destroy()

	if safe_props.Priority ~= nil then
		track.Priority = safe_props.Priority
	end

	if safe_props.Looped ~= nil then
		track.Looped = safe_props.Looped
	end

	track:Play(safe_props.FadeTime, safe_props.Weight, safe_props.Speed)

	track.Ended:Once(function()
		track:Stop(safe_props.FadeTime)
		track:Destroy()
	end)

	return track
end

return AnimationUtilModule
