--!strict
--[[
    FileName    > SoundUtil.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 20/05/2026
--]]

const ContentProvider = game:GetService("ContentProvider")
const RunService = game:GetService("RunService")
const SoundService = game:GetService("SoundService")

const Promise = require("../../packages/roblox/Promise")
const TableUtil = require("./TableUtil")

--[=[
	@class SoundUtil
	A comprehensive utility for managing, preloading, and playing Sound and SoundGroup instances.
]=]
local SoundUtil = {}

--
type SoundProperties = {
	SoundGroup: string | SoundGroup?,
	Volume: number?,
	Looped: boolean?,
	RollOffMode: Enum.RollOffMode?,
	RollOffMaxDistance: number?,
	RollOffMinDistance: number?,
	TimePosition: number?,
	PlaybackSpeed: number?,
}

type QuickPlayParams = {
	SoundName: string,
	SoundId: string?,
	SoundGroup: (string | SoundGroup)?,
	Properties: SoundProperties?,

	Part: Instance?,
	CFrame: CFrame?,
	Position: Vector3?,
}

type LoadParams = {
	SoundName: string?,
	SoundId: string?,
	FromRegistry: string?,
	ShouldPreload: boolean?,
} & SoundProperties
--

--
const SoundGroupCache = {} :: { [string]: SoundGroup }
const GlobalSoundRegistry = {} :: { [string]: Sound }
const SharedSoundPlayers = setmetatable({}, { __mode = "k" }) :: { [Instance]: SoundPlayer }
--

--[=[
	Retrieves an existing SoundGroup from SoundService by name.
	@within SoundUtil
	@param name string -- The name of the SoundGroup.
	@return SoundGroup? -- The SoundGroup instance if found, otherwise `nil`.
]=]
function SoundUtil.GetSoundGroup(name: string): SoundGroup?
	--
	const cached = SoundGroupCache[name]

	if cached then
		return cached
	end

	const existing = SoundService:FindFirstChild(name)

	if not existing or not existing:IsA("SoundGroup") then
		return nil
	end
	--

	--
	SoundGroupCache[name] = existing
	--

	return existing :: SoundGroup
end

local function adopt_sound_group(sound_group: SoundGroup): SoundGroup
	--
	if not sound_group:IsA("SoundGroup") then
		error("SoundUtilModule.AddSoundGroup: Provided instance is not a SoundGroup.", 3)
	end
	--

	--
	const name = sound_group.Name
	SoundGroupCache[name] = sound_group
	--

	--
	if sound_group.Parent ~= SoundService then
		sound_group.Parent = SoundService
	end
	--

	return sound_group
end

--[=[
	Retrieves or creates a SoundGroup under SoundService.
	@within SoundUtil
	@param sound_group_or_name string | SoundGroup -- The SoundGroup name or an existing SoundGroup instance.
	@return SoundGroup -- The retrieved or created SoundGroup.
]=]
function SoundUtil.AddSoundGroup(sound_group_or_name: string | SoundGroup): SoundGroup
	--
	if typeof(sound_group_or_name) == "Instance" then
		return adopt_sound_group(sound_group_or_name)
	end
	--

	--
	const name = sound_group_or_name
	const cached = SoundGroupCache[name]

	if cached then
		return cached
	end

	const existing = SoundService:FindFirstChild(name)

	if existing and existing:IsA("SoundGroup") then
		SoundGroupCache[name] = existing
		return existing :: SoundGroup
	end
	--

	--
	const sound_group = Instance.new("SoundGroup")
	sound_group.Name = name
	sound_group.Parent = SoundService

	SoundGroupCache[name] = sound_group
	--

	return sound_group
end

function SoundUtil.RemoveSoundGroup(name: string): boolean
	--
	const cached = SoundGroupCache[name]

	if not cached then
		error(`SoundUtilModule.RemoveSoundGroup: No SoundGroup found with name '{name}'.`, 2)
		return false
	end
	--

	--
	cached:Destroy()
	SoundGroupCache[name] = nil
	--

	return true
end

--[=[
	Retrieves or creates a SoundGroup, and applies a dictionary of properties to it.
	@within SoundUtil
	@param sound_group_or_name string | SoundGroup -- The SoundGroup name or an existing SoundGroup instance.
	@param properties { [string]: any } -- Dictionary of properties to configure on the SoundGroup.
	@return SoundGroup -- The configured SoundGroup.
]=]
function SoundUtil.ConfigureSoundGroup(
	sound_group_or_name: string | SoundGroup,
	properties: { [string]: any }
): SoundGroup
	--
	const sound_group = SoundUtil.AddSoundGroup(sound_group_or_name)

	for key, value in properties do
		(sound_group :: any)[key] = value
	end
	--

	return sound_group
end

local function apply_properties(sound: Sound, properties: SoundProperties?)
	--
	if not properties then
		return
	end
	--

	--
	if properties.Volume ~= nil then
		sound.Volume = properties.Volume :: number
	end

	if properties.PlaybackSpeed ~= nil then
		sound.PlaybackSpeed = properties.PlaybackSpeed :: number
	end

	if properties.Looped ~= nil then
		sound.Looped = properties.Looped :: boolean
	end

	if properties.RollOffMode ~= nil then
		sound.RollOffMode = properties.RollOffMode :: Enum.RollOffMode
	end

	if properties.RollOffMaxDistance ~= nil then
		sound.RollOffMaxDistance = properties.RollOffMaxDistance :: number
	end

	if properties.RollOffMinDistance ~= nil then
		sound.RollOffMinDistance = properties.RollOffMinDistance :: number
	end

	if properties.TimePosition ~= nil then
		sound.TimePosition = properties.TimePosition :: number
	end
	--

	--
	if properties.SoundGroup == nil then
		return
	end

	if typeof(properties.SoundGroup) == "string" then
		sound.SoundGroup = SoundUtil.AddSoundGroup(properties.SoundGroup :: string)
		return
	end
	--

	--
	sound.SoundGroup = properties.SoundGroup :: SoundGroup
	--
end

local function resolve_quickplay_sound(param: QuickPlayParams): Sound
	--
	const cached_sound = GlobalSoundRegistry[param.SoundName]

	if cached_sound then
		return cached_sound:Clone()
	end
	--

	--
	const sound = Instance.new("Sound")
	sound.SoundId = param.SoundId or ""
	sound.Name = param.SoundName
	--

	return sound
end

local function destroy_when_finished(sound: Sound, anchor: Instance?)
	--
	local finished = false
	--

	local function finish()
		--
		if finished then
			return
		end

		finished = true
		--

		--
		sound:Destroy()

		if anchor then
			anchor:Destroy()
		end
		--
	end

	--
	sound.Ended:Once(finish)
	sound.Stopped:Once(finish)
	sound.Destroying:Once(finish)
	--
end

local function mount_quickplay_sound(sound: Sound, param: QuickPlayParams)
	--
	if param.Part then
		sound.Parent = param.Part
		destroy_when_finished(sound)
		return
	end

	if not param.CFrame and not param.Position then
		sound.Parent = SoundService
		destroy_when_finished(sound)
		return
	end
	--

	--
	const part = Instance.new("Part")
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CFrame = param.CFrame or CFrame.new(param.Position :: Vector3)
	part.Transparency = 1
	part.Name = `{param.SoundName}_quickplay`
	part.Shape = Enum.PartType.Ball
	part.Parent = workspace

	sound.Parent = part
	--

	destroy_when_finished(sound, part)
end

function SoundUtil.QuickPlay(param: QuickPlayParams): Sound
	--
	const sound = resolve_quickplay_sound(param)
	--

	--
	const sound_group = if typeof(param.SoundGroup) == "string"
		then SoundUtil.GetSoundGroup(param.SoundGroup)
		else param.SoundGroup

	if sound_group then
		sound.SoundGroup = sound_group
	end

	apply_properties(sound, param.Properties)
	--

	--
	if sound.Looped then
		warn("SoundUtil.QuickPlay does not support looped sounds; forcing Looped = false.")
		sound.Looped = false
	end
	--

	--
	mount_quickplay_sound(sound, param)
	sound:Play()
	--

	return sound
end

function SoundUtil.Register(
	sound_name: string,
	sound_id: string,
	properties: SoundProperties?,
	should_preload: boolean?
): Sound
	--
	const sound = Instance.new("Sound")
	sound.Name = sound_name
	sound.SoundId = sound_id
	sound.Parent = SoundService

	apply_properties(sound, properties)
	--

	--
	const existing = GlobalSoundRegistry[sound_name]

	if existing then
		existing:Destroy()
	end

	GlobalSoundRegistry[sound_name] = sound
	--

	--
	if should_preload and RunService:IsClient() then
		Promise.try(function()
			ContentProvider:PreloadAsync({ sound })
		end):catch(function(err)
			warn(`Failed to preload sound '{sound_name}': {err}`)
		end)
	end
	--

	return sound
end

function SoundUtil.BulkRegister(
	sounds: { [string]: { SoundId: string } & SoundProperties },
	should_preload: boolean?
): { [string]: Sound }
	--
	const registered_sounds: { [string]: Sound } = {}

	for sound_name, data in sounds do
		registered_sounds[sound_name] = SoundUtil.Register(sound_name, data.SoundId, data, false)
	end
	--

	--
	if should_preload and RunService:IsClient() then
		Promise.try(function()
			ContentProvider:PreloadAsync(TableUtil.Values(registered_sounds))
		end):catch(function(err)
			warn(`Failed to preload sounds: {err}`)
		end)
	end
	--

	return registered_sounds
end

function SoundUtil.Unregister(sound_name: string): boolean
	--
	const sound = GlobalSoundRegistry[sound_name]

	if not sound then
		error(`SoundUtilModule.Unregister: No sound found in registry with name '{sound_name}'.`, 2)
	end
	--

	--
	sound:Destroy()
	GlobalSoundRegistry[sound_name] = nil
	--

	return true
end

--
local SoundPlayer = {}
SoundPlayer.__index = SoundPlayer
--

local function new(container: Instance)
	--
	const self = setmetatable({}, SoundPlayer)

	self.Container = container
	self.SoundCache = {} :: { [string]: Sound }
	--

	return self
end

--
export type SoundPlayer = typeof(new(...))
--

local function load_from_registry(self: SoundPlayer, param: LoadParams, registry_name: string): Sound
	--
	local clone = GlobalSoundRegistry[registry_name]

	if not clone then
		error(`SoundPlayer.Load: No sound found in registry with name '{registry_name}'.`, 2)
	end

	clone = clone:Clone()
	--

	--
	clone.Name = param.SoundName or registry_name
	clone.Parent = self.Container
	--

	--
	const existing = self.SoundCache[param.SoundName or registry_name]

	if existing then
		existing:Destroy()
	end

	self.SoundCache[param.SoundName or registry_name] = clone
	--

	--
	apply_properties(clone, param)
	--

	--
	if param.ShouldPreload and RunService:IsClient() then
		Promise.try(function()
			ContentProvider:PreloadAsync({ clone })
		end):catch(function(err)
			warn(`Failed to preload sound '{param.SoundName or registry_name}': {err}`)
		end)
	end
	--

	return clone
end

function SoundPlayer.Load(self: SoundPlayer, param: LoadParams): Sound
	--
	if param.FromRegistry then
		return load_from_registry(self, param, param.FromRegistry)
	end

	if not param.SoundId or not param.SoundName then
		return error("SoundPlayer.Load: Expected both SoundId and SoundName in param.")
	end
	--

	--
	const sound = Instance.new("Sound")
	sound.Name = param.SoundName or "UnnamedSound"
	sound.SoundId = param.SoundId
	sound.Parent = self.Container

	apply_properties(sound, param)
	--

	--
	const existing = self.SoundCache[param.SoundName]

	if existing then
		existing:Destroy()
	end

	self.SoundCache[param.SoundName] = sound
	--

	--
	if param.ShouldPreload and RunService:IsClient() then
		Promise.try(function()
			ContentProvider:PreloadAsync({ sound })
		end):catch(function(err)
			warn(`Failed to preload sound '{param.SoundName or param.FromRegistry}': {err}`)
		end)
	end
	--

	return sound
end

function SoundPlayer.Unload(self: SoundPlayer, sound_name: string): boolean
	--
	if not self.SoundCache[sound_name] then
		error(`SoundPlayer.Unload: Sound '{sound_name}' has not been loaded.`, 2)
	end
	--

	--
	const sound = self.SoundCache[sound_name]
	sound:Destroy()
	self.SoundCache[sound_name] = nil
	--

	return true
end

function SoundPlayer.Play(
	self: SoundPlayer,
	sound_name: string,
	param: ({
		PlayDuplicate: boolean?,
	} & SoundProperties)?
): Sound
	--
	if not self.SoundCache[sound_name] or sound_name == nil then
		error(`SoundPlayer.Play: Sound '{sound_name}' has not been loaded. Please load the sound before playing.`)
	end
	--

	--
	local sound = self.SoundCache[sound_name]

	if param and param.PlayDuplicate then
		sound = sound:Clone()
		sound.Parent = self.Container

		apply_properties(sound, param)

		sound.Looped = false

		sound.Ended:Once(function()
			sound:Destroy()
		end)
	end
	--

	--
	sound:Play()
	--

	return sound
end

function SoundPlayer.Stop(self: SoundPlayer, sound_name: string): Sound
	--
	if not self.SoundCache[sound_name] then
		error(`SoundPlayer.Stop: Sound '{sound_name}' has not been loaded. Please load the sound before stopping.`, 2)
	end
	--

	--
	const sound = self.SoundCache[sound_name]
	sound:Stop()
	--

	return sound
end

function SoundPlayer.Pause(self: SoundPlayer, sound_name: string): Sound
	--
	if not self.SoundCache[sound_name] then
		error(`SoundPlayer.Pause: Sound '{sound_name}' has not been loaded. Please load the sound before pausing.`, 2)
	end
	--

	--
	const sound = self.SoundCache[sound_name]
	sound:Pause()
	--

	return sound
end

function SoundPlayer.Resume(self: SoundPlayer, sound_name: string): Sound
	--
	if not self.SoundCache[sound_name] then
		error(`SoundPlayer.Resume: Sound '{sound_name}' has not been loaded. Please load the sound before resuming.`, 2)
	end
	--

	--
	const sound = self.SoundCache[sound_name]
	sound:Resume()
	--

	return sound
end

function SoundPlayer.StopAll(self: SoundPlayer): boolean
	--
	for _, sound in self.SoundCache do
		sound:Stop()
	end
	--

	return true
end

function SoundPlayer.PauseAll(self: SoundPlayer): boolean
	--
	for _, sound in self.SoundCache do
		sound:Pause()
	end
	--

	return true
end

function SoundPlayer.ResumeAll(self: SoundPlayer): boolean
	--
	for _, sound in self.SoundCache do
		sound:Resume()
	end
	--

	return true
end

function SoundPlayer.UnloadAll(self: SoundPlayer): boolean
	--
	for sound_name, sound in self.SoundCache do
		sound:Destroy()
		self.SoundCache[sound_name] = nil
	end
	--

	return true
end

function SoundPlayer.Destroy(self: SoundPlayer)
	--
	if SharedSoundPlayers[self.Container] == self then
		SharedSoundPlayers[self.Container] = nil
	end
	--

	--
	self:UnloadAll()
	self.Container = nil :: any
	--
end

function SoundUtil.GetSharedSoundPlayer(container: Instance): SoundPlayer
	--
	if SharedSoundPlayers[container] then
		return SharedSoundPlayers[container]
	end
	--

	--
	const sound_player = new(container)
	SharedSoundPlayers[container] = sound_player
	--

	--
	container.Destroying:Once(function()
		SharedSoundPlayers[container] = nil
	end)
	--

	return sound_player
end

function SoundUtil.GetLocalSoundPlayer(): SoundPlayer
	return SoundUtil.GetSharedSoundPlayer(SoundService)
end

--
SoundUtil.new = new
--

return SoundUtil
