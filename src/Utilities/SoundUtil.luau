--!nonstrict
--[[
    FileName    > SoundUtil.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 20/05/2026
--]]

const RunService = game:GetService("RunService")
const SoundService = game:GetService("SoundService")

const Keeper = require("../../../../Keeper")
const Promise = require("../../../../Promise")
const Signal = require("../../../../Signal")

--[[
	@class SoundUtilModule
	The entry point module for SoundUtil, exposing methods to get, add, or configure Roblox SoundGroups, as well as instantiate new SoundUtil managers.
]]--
local SoundUtilModule = {}

--[[
	@class SoundUtil
	An object-oriented instance that manages loading, caching, playback, spatialization, and stopping of sounds under a specific target Instance.
]]--
local SoundUtil = {}
SoundUtil.__index = SoundUtil

type SoundMap = { [string]: string }
type SoundProperties = { [string]: any }
type SoundUtilOptions = {
	NoCache: boolean?,
}
type PromiseLike = typeof(Promise.new(function() end))

local SoundUtilCache = {}
local SoundGroupCache = {}

--[[
	Retrieves an existing SoundGroup from SoundService by name.
	@param name string -- The name of the SoundGroup.
	@return SoundGroup? -- The SoundGroup instance if found, otherwise `nil`.
]]--
function SoundUtilModule.GetSoundGroup(name: string): SoundGroup?
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

--[[
	Retrieves or creates a SoundGroup under SoundService.
	@param sound_group_or_name string | SoundGroup -- The SoundGroup name or an existing SoundGroup instance.
	@return SoundGroup -- The retrieved or created SoundGroup.
]]--
function SoundUtilModule.AddSoundGroup(sound_group_or_name: string | SoundGroup): SoundGroup
	if typeof(sound_group_or_name) == "string" then
		local name = sound_group_or_name
		local cached = SoundGroupCache[name]
		if cached then
			return cached
		end

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
	elseif typeof(sound_group_or_name) == "Instance" and sound_group_or_name:IsA("SoundGroup") then
		local sound_group = sound_group_or_name
		local name = sound_group.Name
		SoundGroupCache[name] = sound_group

		if sound_group.Parent ~= SoundService then
			sound_group.Parent = SoundService
		end

		return sound_group
	else
		error("Invalid argument to AddSoundGroup. Expected string or SoundGroup instance.", 2)
	end
end

--[[
	Retrieves or creates a SoundGroup, and applies a dictionary of properties to it.
	@param sound_group_or_name string | SoundGroup -- The SoundGroup name or an existing SoundGroup instance.
	@param properties { [string]: any } -- Dictionary of properties to configure on the SoundGroup.
	@return SoundGroup -- The configured SoundGroup.
]]--
function SoundUtilModule.ConfigureSoundGroup(
	sound_group_or_name: string | SoundGroup,
	properties: { [string]: any }
): SoundGroup
	local sound_group = SoundUtilModule.AddSoundGroup(sound_group_or_name)
	for key, value in properties do
		sound_group[key] = value
	end
	return sound_group
end

--[[
	Instantiates or retrieves a cached SoundUtil manager associated with a specific Roblox Instance.
	@param target_instance Instance -- The Instance under which playing sound instances will be parented.
	@param sound_map SoundMap? -- Optional mapping dictionary of sound names to AssetIds.
	@param options_or_force_new (SoundUtilOptions | boolean)? -- Optional configurations or boolean forcing a new instance.
	@return SoundUtil -- The SoundUtil manager instance.
]]--
function SoundUtilModule.new(
	target_instance: Instance,
	sound_map: SoundMap?,
	options_or_force_new: (SoundUtilOptions | boolean)?
)
	local force_new = false
	if typeof(options_or_force_new) == "boolean" then
		force_new = options_or_force_new
	elseif typeof(options_or_force_new) == "table" then
		force_new = not not options_or_force_new.NoCache
	end

	if not force_new then
		local cached_sound_util = SoundUtilCache[target_instance]
		if cached_sound_util then
			return cached_sound_util
		end
	end

	local self = setmetatable({}, SoundUtil)
	self.Keeper = Keeper.new()
	self.Keeper:AttachToInstance(target_instance)
	self.Keeper:Add(function()
		SoundUtilCache[target_instance] = nil
	end)

	self.TargetInstance = target_instance
	self.SoundMap = sound_map or {}
	self.Sounds = {}
	self.SoundKeepers = {}
	self.SoundGroups = {}
	self.ActivePromises = {} :: { [string]: PromiseLike }

	self.OnPlay = self.Keeper:Construct(Signal)
	self.OnStop = self.Keeper:Construct(Signal)

	if not force_new then
		SoundUtilCache[target_instance] = self
	end

	return self
end

--[[
	Alias for new. Retrieves or instantiates a SoundUtil manager.
	@param target_instance Instance -- The target parent Instance.
	@param sound_map SoundMap? -- Optional sound mapping.
	@param options_or_force_new (SoundUtilOptions | boolean)? -- Optional configurations.
	@return SoundUtil -- The SoundUtil manager.
]]--
SoundUtilModule.Get = SoundUtilModule.new

export type SoundUtil = typeof(SoundUtilModule.new(...))

local function apply_properties(sound: Sound, properties: SoundProperties?)
	if not properties then
		return
	end
	for key, value in properties do
		if key == "SoundGroup" and typeof(value) == "string" then
			sound.SoundGroup = SoundUtilModule.AddSoundGroup(value)
		else
			sound[key] = value
		end
	end
end

--[[
	Sets or updates the SoundGroup associated with a specific named sound.
	@param name string -- The registered sound name.
	@param sound_group string | SoundGroup -- The SoundGroup name or instance.
]]--
function SoundUtil.SetSoundGroup(self: SoundUtil, name: string, sound_group: string | SoundGroup)
	self.SoundGroups[name] = sound_group
	local sound = self.Sounds[name]
	if sound then
		if typeof(sound_group) == "string" then
			sound.SoundGroup = SoundUtilModule.AddSoundGroup(sound_group)
		else
			sound.SoundGroup = sound_group
		end
	end
end

--[[
	Registers a sound name mapping to an AssetId and optionally registers its SoundGroup.
	@param name string -- The sound name key.
	@param sound_id string -- The asset ID (e.g. `rbxassetid://...`).
	@param sound_group (string | SoundGroup)? -- Optional SoundGroup name or instance.
]]--
function SoundUtil.AddSound(self: SoundUtil, name: string, sound_id: string, sound_group: (string | SoundGroup)?)
	self.SoundMap[name] = sound_id
	if sound_group then
		self:SetSoundGroup(name, sound_group)
	end
end

--[[
	Alias for AddSound. Registers a sound name mapping.
	@param name string -- The sound name key.
	@param sound_id string -- The asset ID.
	@param sound_group (string | SoundGroup)? -- Optional SoundGroup.
]]--
function SoundUtil.AddSoundId(self: SoundUtil, name: string, sound_id: string, sound_group: (string | SoundGroup)?)
	self:AddSound(name, sound_id, sound_group)
end

function SoundUtil._StopLoadedSound(self: SoundUtil, name: string)
	local sound = self.Sounds[name]
	if not sound then
		return
	end

	if self.ActivePromises[name] then
		self.ActivePromises[name]:cancel()
		return
	end

	sound:Stop()
	self.OnStop:Fire(name, sound)
end

function SoundUtil._RemoveLoadedSound(self: SoundUtil, name: string)
	local sound = self.Sounds[name]
	if sound then
		self:_StopLoadedSound(name)

		local sound_keeper = self.SoundKeepers[name]
		if sound_keeper then
			sound_keeper:Remove(sound)
		else
			pcall(function()
				sound:Destroy()
			end)
		end

		self.Sounds[name] = nil
		self.SoundKeepers[name] = nil
	end

	self.ActivePromises[name] = nil
	self.SoundMap[name] = nil
	self.SoundGroups[name] = nil
end

--[[
	Stops, destroys, and unregisters a loaded sound track by name.
	@param name string -- The registered sound name.
]]--
function SoundUtil.RemoveSound(self: SoundUtil, name: string)
	self:_RemoveLoadedSound(name)
end

--[[
	Stops, destroys, and unregisters all matching registered sounds by AssetId.
	@param sound_id string -- The asset ID to search and remove.
]]--
function SoundUtil.RemoveSoundId(self: SoundUtil, sound_id: string)
	local names_to_remove = {}

	for name, registered_sound_id in self.SoundMap do
		if registered_sound_id == sound_id then
			table.insert(names_to_remove, name)
		end
	end

	for index = 1, #names_to_remove do
		local name = names_to_remove[index]
		self:_RemoveLoadedSound(name)
	end
end

--[[
	Cleans up, destroys, and deletes the SoundUtil manager instance, removing it from cache.
]]--
function SoundUtil.Destroy(self: SoundUtil)
	SoundUtilCache[self.TargetInstance] = nil
	self.Keeper:Destroy()
	self.Sounds = nil
	self.SoundKeepers = nil
	self.SoundGroups = nil
	self.ActivePromises = nil
	self.SoundMap = nil
end

--[[
	Instantiates and loads a raw Sound instance under the target instance.
	@param name string -- The registered sound name to load.
	@return Sound -- The loaded playable Sound instance.
]]--
function SoundUtil.Load(self: SoundUtil, name: string): Sound
	local sound_instance = Instance.new("Sound")
	sound_instance.SoundId = self.SoundMap[name]
	sound_instance.Name = name
	sound_instance.Parent = self.TargetInstance

	local sound_group = self.SoundGroups[name]
	if sound_group then
		if typeof(sound_group) == "string" then
			sound_instance.SoundGroup = SoundUtilModule.AddSoundGroup(sound_group)
		else
			sound_instance.SoundGroup = sound_group
		end
	end

	-- Create a per-sound Keeper so that when the sound instance is
	-- destroyed, all connections, promises and other resources tied
	-- to this sound are cleaned up automatically.
	local sound_keeper = self.Keeper:Extend(name)

	-- Track the instance on the sub-keeper and attach to the instance
	-- so the keeper will clean itself when the instance is destroyed.
	sound_keeper:Add(sound_instance)
	sound_keeper:AttachToInstance(sound_instance)

	self.Sounds[name] = sound_instance
	self.SoundKeepers[name] = sound_keeper

	return sound_instance
end

--[[
	Ensures a sound is loaded, returning the cached Sound instance or loading it if missing.
	@param name string -- The registered sound name.
	@return Sound -- The Sound instance.
]]--
function SoundUtil.EnsureLoaded(self: SoundUtil, name: string): Sound
	if self.Sounds[name] then
		return self.Sounds[name]
	end

	return self:Load(name)
end

--[[
	Plays a registered sound track and applies optional properties.
	@param name string -- The registered sound name.
	@param properties SoundProperties? -- Optional properties to set before playing (e.g., Pitch, Volume, SoundGroup).
]]--
function SoundUtil.Play(self: SoundUtil, name: string, properties: SoundProperties?)
	local sound = self:EnsureLoaded(name)

	apply_properties(sound, properties)

	sound:Play()
	self.OnPlay:Fire(name, sound)
end

--[[
	Plays a registered sound and returns a Promise that resolves when the sound completes playing.
	Cancels any existing active promise on the same sound if already playing.
	@param name string -- The registered sound name.
	@param properties SoundProperties? -- Optional properties.
	@return Promise -- A promise that resolves when the sound ends or is stopped.
]]--
function SoundUtil.PlayAsync(self: SoundUtil, name: string, properties: SoundProperties?): PromiseLike
	local sound = self:EnsureLoaded(name)
	local sound_keeper = self.SoundKeepers[name]

	if self.ActivePromises[name] then
		self.ActivePromises[name]:cancel()
	end

	apply_properties(sound, properties)

	sound:Play()
	self.OnPlay:Fire(name, sound)

	local play_promise = Promise.new(function(resolve, _, on_cancel)
		-- Use the per-sound keeper to register the Ended connection so
		-- it will automatically be cleaned when the sound is destroyed.
		local connection = nil
		if sound_keeper then
			connection = sound_keeper:Once(sound.Ended, function()
				self.OnStop:Fire(name, sound)
				self.ActivePromises[name] = nil
				resolve(true)
			end)
		else
			connection = sound.Ended:Once(function()
				self.OnStop:Fire(name, sound)
				self.ActivePromises[name] = nil
				resolve(true)
			end)
		end

		on_cancel(function()
			if connection then
				if sound_keeper then
					sound_keeper:Remove(connection)
				else
					pcall(function()
						connection:Disconnect()
					end)
				end
			end

			pcall(function()
				sound:Stop()
			end)
			self.OnStop:Fire(name, sound)
			self.ActivePromises[name] = nil
		end)
	end)

	self.ActivePromises[name] = play_promise
	if sound_keeper then
		sound_keeper:AddPromise(play_promise)
	end

	return play_promise
end

--[[
	Stops a playing sound track by name.
	@param name string -- The registered sound name.
]]--
function SoundUtil.Stop(self: SoundUtil, name: string)
	local sound = self.Sounds[name]
	if not sound then
		return
	end

	if self.ActivePromises[name] then
		self.ActivePromises[name]:cancel()
	else
		sound:Stop()
		self.OnStop:Fire(name, sound)
	end
end

--[[
	Stops all active sound tracks managed by this manager.
]]--
function SoundUtil.StopAll(self: SoundUtil)
	for name in self.Sounds do
		self:Stop(name)
	end
end

--[[
	Creates a Promise that resolves when the sound playback reaches or exceeds a specified timeline position.
	@param name string -- The registered sound name.
	@param target_time number -- The target playback timeline position in seconds.
	@return Promise -- A promise that resolves with the actual timeline position reached.
]]--
function SoundUtil.TimePositionAsync(self: SoundUtil, name: string, target_time: number): PromiseLike
	local sound = self:EnsureLoaded(name)
	local sound_keeper = self.SoundKeepers[name]

	return Promise.new(function(resolve, _, on_cancel)
		local connection
		if sound_keeper then
			connection = sound_keeper:Connect(RunService.Heartbeat, function()
				if sound.TimePosition >= target_time then
					sound_keeper:Remove(connection)
					resolve(sound.TimePosition)
				end
			end)
		else
			connection = RunService.Heartbeat:Connect(function()
				if sound.TimePosition >= target_time then
					connection:Disconnect()
					resolve(sound.TimePosition)
				end
			end)
		end

		on_cancel(function()
			if connection then
				if sound_keeper then
					sound_keeper:Remove(connection)
				else
					pcall(function()
						connection:Disconnect()
					end)
				end
			end
		end)
	end)
end

--[[
	Spatializes and plays a temporary one-off sound parented under a specific Roblox Part.
	Automatically cleans up and destroys the Sound instance when it completes playback.
	@param part Instance -- The Roblox Part instance.
	@param name string -- The registered sound name.
	@param properties SoundProperties? -- Optional sound properties.
	@return Sound -- The instantiated spatial Sound instance.
]]--
function SoundUtil.PlayPart(self: SoundUtil, part: Instance, name: string, properties: SoundProperties?): Sound
	local sound = self.Keeper:Add(Instance.new("Sound"))
	sound.SoundId = self.SoundMap[name]
	sound.Name = name

	local sound_group = self.SoundGroups[name]
	if sound_group then
		if typeof(sound_group) == "string" then
			sound.SoundGroup = SoundUtilModule.AddSoundGroup(sound_group)
		else
			sound.SoundGroup = sound_group
		end
	end

	apply_properties(sound, properties)

	sound.Parent = part

	local conn
	conn = self.Keeper:Add(sound.Ended:Once(function()
		self.OnStop:Fire(name, sound)
		if conn then
			self.Keeper:Remove(conn)
		end
		self.Keeper:Remove(sound)
	end))

	sound:Play()
	self.OnPlay:Fire(name, sound)

	return sound
end

--[[
	Spatializes and plays a temporary one-off sound at a specific CFrame coordinate position.
	Instantiates a transparent, anchored part in the Workspace to parent the sound, automatically cleaning both up on finish.
	@param cframe CFrame -- The CFrame coordinate position.
	@param name string -- The registered sound name.
	@param properties SoundProperties? -- Optional sound properties.
	@return Sound -- The instantiated spatial Sound instance.
]]--
function SoundUtil.PlayCFrame(self: SoundUtil, cframe: CFrame, name: string, properties: SoundProperties?): Sound
	local part = self.Keeper:Add(Instance.new("Part"))
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.CFrame = cframe
	part.Name = name .. "_sound"
	part.Parent = workspace

	local sound = self.Keeper:Add(Instance.new("Sound"))
	sound.SoundId = self.SoundMap[name]
	sound.Name = name

	local sound_group = self.SoundGroups[name]
	if sound_group then
		if typeof(sound_group) == "string" then
			sound.SoundGroup = SoundUtilModule.AddSoundGroup(sound_group)
		else
			sound.SoundGroup = sound_group
		end
	end

	apply_properties(sound, properties)

	sound.Parent = part

	local conn
	conn = self.Keeper:Add(sound.Ended:Once(function()
		self.OnStop:Fire(name, sound)
		if conn then
			self.Keeper:Remove(conn)
		end
		self.Keeper:Remove(part)
	end))

	sound:Play()
	self.OnPlay:Fire(name, sound)

	return sound
end

--[[
	Plays a non-spatialized local client audio track parented to the CurrentCamera.
	Must be called from a Client script environment.
	@param player Player -- The local Player instance.
	@param name string -- The registered sound name.
	@param properties SoundProperties? -- Optional sound properties.
	@return Sound -- The instantiated local client Sound instance.
]]--
function SoundUtil.PlayLocal(self: SoundUtil, player: Player, name: string, properties: SoundProperties?): Sound
	if not RunService:IsClient() then
		error("PlayLocal must be called from the client", 2)
	end

	local sound = self.Keeper:Add(Instance.new("Sound"))
	sound.SoundId = self.SoundMap[name]
	sound.Name = name

	local sound_group = self.SoundGroups[name]
	if sound_group then
		if typeof(sound_group) == "string" then
			sound.SoundGroup = SoundUtilModule.AddSoundGroup(sound_group)
		else
			sound.SoundGroup = sound_group
		end
	end

	apply_properties(sound, properties)

	-- Parent to the current camera so the sound is local to this client
	local camera = workspace.CurrentCamera
	sound.Parent = camera

	local conn
	conn = self.Keeper:Add(sound.Ended:Once(function()
		self.OnStop:Fire(name, sound)
		if conn then
			self.Keeper:Remove(conn)
		end
		self.Keeper:Remove(sound)
	end))

	sound:Play()
	self.OnPlay:Fire(name, sound)

	return sound
end

return SoundUtilModule
