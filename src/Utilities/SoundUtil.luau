--!nonstrict
--[[
    FileName    > SoundUtil.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 20/05/2026
--]]

const SoundService = game:GetService("SoundService")

const PrintUtil = require("./PrintUtil")

local SoundUtil = {}

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

local SoundGroupCache = {} :: { [string]: SoundGroup }
local GlobalSoundRegistry = {} :: { [string]: Sound }
local SharedSoundPlayers = {} :: { [Instance]: SoundPlayer }

--[=[
	Retrieves an existing SoundGroup from SoundService by name.
	@within SoundUtil
	@param name string -- The name of the SoundGroup.
	@return SoundGroup? -- The SoundGroup instance if found, otherwise `nil`.
]=]
--
function SoundUtil.GetSoundGroup(name: string): SoundGroup?
	local cached = SoundGroupCache[name]
	if cached then
		return cached
	end

	local existing = SoundService:FindFirstChild(name)
	if existing and existing:IsA("SoundGroup") then
		SoundGroupCache[name] = existing
		return existing :: SoundGroup
	end

	return nil
end

--[=[
	Retrieves or creates a SoundGroup under SoundService.
	@within SoundUtil
	@param sound_group_or_name string | SoundGroup -- The SoundGroup name or an existing SoundGroup instance.
	@return SoundGroup -- The retrieved or created SoundGroup.
]=]
--
function SoundUtil.AddSoundGroup(sound_group_or_name: string | SoundGroup): SoundGroup
	if typeof(sound_group_or_name) == "Instance" then
		if not sound_group_or_name:IsA("SoundGroup") then
			PrintUtil:Error("SoundUtilModule.AddSoundGroup: Provided instance is not a SoundGroup.", 2)
		end

		local sound_group = sound_group_or_name
		local name = sound_group.Name
		SoundGroupCache[name] = sound_group

		if sound_group.Parent ~= SoundService then
			sound_group.Parent = SoundService
		end

		return sound_group
	end

	local name = sound_group_or_name
	local cached = SoundGroupCache[name]
	if cached then return cached end

	local existing = SoundService:FindFirstChild(name)
	if existing and existing:IsA("SoundGroup") then
		SoundGroupCache[name] = existing
		return existing :: SoundGroup
	end

	local sound_group = Instance.new("SoundGroup")
	sound_group.Name = name
	sound_group.Parent = SoundService
	SoundGroupCache[name] = sound_group
	return sound_group
end

function SoundUtil.RemoveSoundGroup(name: string)
	local cached = SoundGroupCache[name]
	if cached then
		cached:Destroy()
		SoundGroupCache[name] = nil
		return true
	end

	PrintUtil:Error("SoundUtilModule.RemoveSoundGroup: No SoundGroup found with name '" .. name .. "'.", 2)
	return false
end

--[=[
	Retrieves or creates a SoundGroup, and applies a dictionary of properties to it.
	@within SoundUtil
	@param sound_group_or_name string | SoundGroup -- The SoundGroup name or an existing SoundGroup instance.
	@param properties { [string]: any } -- Dictionary of properties to configure on the SoundGroup.
	@return SoundGroup -- The configured SoundGroup.
]=]
--
function SoundUtil.ConfigureSoundGroup(
	sound_group_or_name: string | SoundGroup,
	properties: { [string]: any }
): SoundGroup
	local sound_group = SoundUtil.AddSoundGroup(sound_group_or_name)
	for key, value in properties do
		sound_group[key] = value
	end
	return sound_group
end

local function apply_properties(sound: Sound, properties: SoundProperties?)
	if not properties then
		return
	end
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
	if properties.SoundGroup ~= nil then
		if typeof(properties.SoundGroup) == "string" then
			sound.SoundGroup = SoundUtil.AddSoundGroup(properties.SoundGroup :: string)
		else
			sound.SoundGroup = properties.SoundGroup :: SoundGroup
		end
	end
end

function SoundUtil.QuickPlay(param: {
	Target: Instance?,
	SoundName: string,
	SoundId: string?,
	SoundGroup: (string | SoundGroup)?,
	Properties: SoundProperties?,

	Part: Instance?,
	CFrame: CFrame?,
	Position: Vector3?,
})
	local sound = Instance.new("Sound")
	sound.SoundId = GlobalSoundRegistry[param.SoundName] or param.SoundId
	sound.Name = param.SoundName

	local sound_group = if typeof(param.SoundGroup) == "string" then SoundUtil.GetSoundGroup(param.SoundGroup) else param.SoundGroup

	if sound_group then
		sound.SoundGroup = sound_group
	end

	apply_properties(sound, param.Properties)

	if param.Part then
		sound.Parent = param.Part

		sound.Ended:Once(function()
			sound:Destroy()
		end)
	elseif param.CFrame or param.Position then
		local part = Instance.new("Part")
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		part.Anchored = true
		part.CanCollide = false
		part.CFrame = param.CFrame or CFrame.new(param.Position :: Vector3)
		part.Transparency = 1
		part.Name = param.SoundName .. "_quickplay"
		part.Shape = Enum.PartType.Ball
		part.Parent = workspace
		sound.Parent = part

		sound.Ended:Once(function()
			part:Destroy()
			sound:Destroy()
		end)
	else
		sound.Parent = SoundService

		sound.Ended:Once(function()
			sound:Destroy()
		end)
	end

	sound:Play()

	return sound
end

function SoundUtil.Register(sound_name: string, sound_id: string, properties: SoundProperties?)
	local sound = Instance.new("Sound")
	sound.Name = sound_name
	sound.SoundId = sound_id
	sound.Parent = SoundService

	apply_properties(sound, properties)

	GlobalSoundRegistry[sound_name] = sound
	return sound
end

function SoundUtil.BulkRegister(sounds: { [string]: { SoundId: string } & SoundProperties })
	local registered_sounds = {}
	for sound_name, data in sounds do
		registered_sounds[sound_name] = SoundUtil.Register(sound_name, data.SoundId, data)
	end
	return registered_sounds
end

function SoundUtil.Unregister(sound_name: string)
	local sound = GlobalSoundRegistry[sound_name]
	if not sound then
		PrintUtil:Error("SoundUtilModule.Unregister: No sound found in registry with name '" .. sound_name .. "'.", 2)
	end

	sound:Destroy()
	GlobalSoundRegistry[sound_name] = nil
	return true
end

local SoundPlayer = {}
SoundPlayer.__index = SoundPlayer

local function new(
	container: Instance
)
	local self = setmetatable({}, SoundPlayer)

	self.Container = container
	self.SoundCache = {}

	return self
end

export type SoundPlayer = typeof(new(...))

function SoundPlayer.Load(
	self: SoundPlayer,
	param: {
		SoundName: string,
		SoundId: string?,
		FromRegistry: string?
	} & SoundProperties
)
	--
	if param.FromRegistry then
		--
		local clone = GlobalSoundRegistry[param.FromRegistry]
		if not clone then
			PrintUtil:Error("SoundPlayer.Load: No sound found in registry with name '" .. param.FromRegistry .. "'.")
		end

		clone = clone:Clone()
		--

		clone.Parent = self.Container
		self.SoundCache[param.SoundName] = clone

		apply_properties(clone, param)
		return clone
	end
	--

	--
	local sound = Instance.new("Sound")
	sound.Name = param.SoundName
	sound.SoundId = param.SoundId
	sound.Parent = self.Container
	--

	apply_properties(sound, param)

	self.SoundCache[param.SoundName] = sound
	return sound
end

function SoundPlayer.Unload(self: SoundPlayer, sound_name: string)
	if not self.SoundCache[sound_name] then
		PrintUtil:Error("SoundPlayer.Unload: Sound '" .. sound_name .. "' has not been loaded.", 2)
	end

	local sound = self.SoundCache[sound_name]
	sound:Destroy()
	self.SoundCache[sound_name] = nil
	return true
end

function SoundPlayer.Play(
	self: SoundPlayer,
	param: {
		SoundName: string,
		SoundId: string?,

		PlayDuplicate: boolean?,
	} & SoundProperties
)
	if not self.SoundCache[param.SoundName] then
		PrintUtil:Error("SoundPlayer.Play: Sound '" .. param.SoundName .. "' has not been loaded. Please load the sound before playing.", 2)
	end

	local sound = self.SoundCache[param.SoundName]

	if param.PlayDuplicate then
		sound = sound:Clone()
		sound.Parent = self.Container

		sound.Ended:Once(function()
			sound:Destroy()
		end)
	end

	apply_properties(sound, param)
	sound:Play()
	return sound
end

function SoundPlayer.Stop(self: SoundPlayer, sound_name: string)
	if not self.SoundCache[sound_name] then
		PrintUtil:Error("SoundPlayer.Stop: Sound '" .. sound_name .. "' has not been loaded. Please load the sound before stopping.", 2)
	end

	local sound = self.SoundCache[sound_name]
	sound:Stop()
	return sound
end

function SoundPlayer.Pause(self: SoundPlayer, sound_name: string)
	if not self.SoundCache[sound_name] then
		PrintUtil:Error("SoundPlayer.Pause: Sound '" .. sound_name .. "' has not been loaded. Please load the sound before pausing.", 2)
	end

	local sound = self.SoundCache[sound_name]
	sound:Pause()
	return sound
end

function SoundPlayer.Resume(self: SoundPlayer, sound_name: string)
	if not self.SoundCache[sound_name] then
		PrintUtil:Error("SoundPlayer.Resume: Sound '" .. sound_name .. "' has not been loaded. Please load the sound before resuming.", 2)
	end

	local sound = self.SoundCache[sound_name]
	sound:Resume()
	return sound
end

function SoundPlayer.StopAll(self: SoundPlayer)
	for _, sound in self.SoundCache do
		sound:Stop()
	end
	return true
end

function SoundPlayer.PauseAll(self: SoundPlayer)
	for _, sound in self.SoundCache do
		sound:Pause()
	end
	return true
end

function SoundPlayer.ResumeAll(self: SoundPlayer)
	for _, sound in self.SoundCache do
		sound:Resume()
	end
	return true
end

function SoundPlayer.UnloadAll(self: SoundPlayer)
	for sound_name, sound in self.SoundCache do
		sound:Destroy()
		self.SoundCache[sound_name] = nil
	end
	return true
end

function SoundPlayer.Destroy(self: SoundPlayer)
	if SharedSoundPlayers[self.Container] == self then
		SharedSoundPlayers[self.Container] = nil
	end

	self:UnloadAll()
	self.Container = nil
end

function SoundUtil.GetSharedSoundPlayer(container: Instance): SoundPlayer
	if SharedSoundPlayers[container] then
		return SharedSoundPlayers[container]
	end

	local sound_player = new(container)
	SharedSoundPlayers[container] = sound_player

	container.Destroying:Once(function()
		SharedSoundPlayers[container] = nil
	end)

	return sound_player
end

function SoundUtil.GetLocalSoundPlayer(): SoundPlayer
	return SoundUtil.GetSharedSoundPlayer(SoundService)
end

SoundUtil.new = new

return SoundUtil
