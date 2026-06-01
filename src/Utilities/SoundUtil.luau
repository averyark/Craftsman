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
const PrintUtil = require("./PrintUtil")

--[[
	@class SoundUtilModule
	The entry point module for SoundUtil, exposing methods to get, add, or configure Roblox SoundGroups, as well as instantiate new SoundUtil managers.
]]
--
local SoundUtilModule = {}

--[[
	@class SoundUtil
	An object-oriented instance that manages loading, caching, playback, spatialization, and stopping of sounds under a specific target Instance.
]]
--
local SoundUtil = {}
SoundUtil.__index = SoundUtil

type SoundMap = { [string]: string }
type SoundProperties = {
	PlayDuplicate: boolean?,
	SoundGroup: string | SoundGroup?,
	Volume: number?,
	Looped: boolean?,
	RollOffMode: Enum.RollOffMode?,
	RollOffMaxDistance: number?,
	RollOffMinDistance: number?,
	TimePosition: number?,
	PlaybackSpeed: number?,
}

type SoundUtilOptions = {
	NoCache: boolean?,
}
type PromiseLike = typeof(Promise.new(function() end))

local SoundUtilCache = {}
local SoundGroupCache = {}
local GlobalSoundRegistry = {}

--[[
	Retrieves an existing SoundGroup from SoundService by name.
	@param name string -- The name of the SoundGroup.
	@return SoundGroup? -- The SoundGroup instance if found, otherwise `nil`.
]]
--
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
]]
--
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
]]
--
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
	Registers a sound name or dictionary of name-to-AssetId mappings globally.
	Any SoundUtil instance will fallback to this registry when loading/playing sounds by name.
	@param name_or_map string | { [string]: string } -- The sound name or a mapping dictionary.
	@param sound_id string? -- The sound AssetId (required if first argument is a name).
]]
--
function SoundUtilModule.Register(name_or_map: string | { [string]: string }, sound_id: string?)
	if typeof(name_or_map) == "table" then
		for key, value in name_or_map do
			GlobalSoundRegistry[key] = value
		end
	else
		GlobalSoundRegistry[name_or_map] = sound_id
	end
end

--[[
	Instantiates or retrieves a cached SoundUtil manager associated with a specific Roblox Instance.
	@param target_instance Instance -- The Instance under which playing sound instances will be parented.
	@param sound_map SoundMap? -- Optional mapping dictionary of sound names to AssetIds.
	@param options_or_force_new (SoundUtilOptions | boolean)? -- Optional configurations or boolean forcing a new instance.
	@return SoundUtil -- The SoundUtil manager instance.
]]
--
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
	self.SoundMap = setmetatable(sound_map or {}, { __index = GlobalSoundRegistry })
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
]]
--
SoundUtilModule.Get = SoundUtilModule.new

export type SoundUtil = typeof(SoundUtilModule.new(...))

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
			sound.SoundGroup = SoundUtilModule.AddSoundGroup(properties.SoundGroup :: string)
		else
			sound.SoundGroup = properties.SoundGroup :: SoundGroup
		end
	end
end

--[[
	Sets or updates the SoundGroup associated with a specific named sound.
	@param name string -- The registered sound name.
	@param sound_group string | SoundGroup -- The SoundGroup name or instance.
]]
--
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
	If sound_id is not specified, it will be derived from the global cache.
	@param name string -- The sound name key.
	@param sound_id string? -- The asset ID (e.g. `rbxassetid://...`). If omitted, derives from the global cache.
	@param sound_group (string | SoundGroup)? -- Optional SoundGroup name or instance.
]]
--
function SoundUtil.AddSound(self: SoundUtil, name: string, sound_id: string?, sound_group: (string | SoundGroup)?)
	local resolved_id = sound_id or self.SoundMap[name]
	if not resolved_id then
		error("SoundId not specified and name '" .. name .. "' not found in global sound cache.", 2)
	end

	self.SoundMap[name] = resolved_id
	if sound_group then
		self:SetSoundGroup(name, sound_group)
	end

	-- Immediately create/ensure the sound instance exists in the target instance without duplicates
	local sound = self:EnsureLoaded(name)

	-- Sync sound properties
	sound.SoundId = resolved_id
	if sound_group then
		if typeof(sound_group) == "string" then
			sound.SoundGroup = SoundUtilModule.AddSoundGroup(sound_group)
		else
			sound.SoundGroup = sound_group
		end
	end
end

--[[
	Alias for AddSound. Registers a sound name mapping.
	@param name string -- The sound name key.
	@param sound_id string? -- The asset ID. If omitted, derives from the global cache.
	@param sound_group (string | SoundGroup)? -- Optional SoundGroup.
]]
--
function SoundUtil.AddSoundId(self: SoundUtil, name: string, sound_id: string?, sound_group: (string | SoundGroup)?)
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
]]
--
function SoundUtil.RemoveSound(self: SoundUtil, name: string)
	self:_RemoveLoadedSound(name)
end

--[[
	Stops, destroys, and unregisters all matching registered sounds by AssetId.
	@param sound_id string -- The asset ID to search and remove.
]]
--
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
]]
--
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
]]
--
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
]]
--
function SoundUtil.EnsureLoaded(self: SoundUtil, name: string): Sound
	if self.Sounds[name] then
		return self.Sounds[name]
	end

	-- Check if a Sound with this name already exists in target_instance (deduplication)
	local existing = self.TargetInstance:FindFirstChild(name)
	if existing and existing:IsA("Sound") then
		local sound_keeper = self.Keeper:Extend(name)
		sound_keeper:Add(existing)
		sound_keeper:AttachToInstance(existing)
		self.Sounds[name] = existing
		self.SoundKeepers[name] = sound_keeper

		-- Sync properties if registered
		if self.SoundMap[name] then
			existing.SoundId = self.SoundMap[name]
		end

		local sound_group = self.SoundGroups[name]
		if sound_group then
			if typeof(sound_group) == "string" then
				existing.SoundGroup = SoundUtilModule.AddSoundGroup(sound_group)
			else
				existing.SoundGroup = sound_group
			end
		end

		return existing
	end

	return self:Load(name)
end

--[[
	Plays a registered sound track and applies optional properties.
	@param name string -- The registered sound name.
	@param properties SoundProperties? -- Optional properties to set before playing (e.g., Pitch, Volume, SoundGroup).
]]
--
function SoundUtil.Play(self: SoundUtil, name: string, properties: SoundProperties?)
	local sound = self:EnsureLoaded(name)

	local is_duplicate = properties and properties.PlayDuplicate == true
	local target_sound = sound
	if is_duplicate then
		target_sound = sound:Clone()
		target_sound.Parent = sound.Parent
		target_sound.Ended:Once(function()
			self.OnStop:Fire(name, target_sound)
			target_sound:Destroy()
		end)
		-- Apply properties after parenting so Roblox Sound properties
		-- (e.g. Volume) are reliably set on a live instance.
		apply_properties(target_sound, properties)
	else
		apply_properties(target_sound, properties)
	end

	target_sound:Play()
	self.OnPlay:Fire(name, target_sound)
end

--[[
	Plays a registered sound and returns a Promise that resolves when the sound completes playing.
	Cancels any existing active promise on the same sound if already playing.
	@param name string -- The registered sound name.
	@param properties SoundProperties? -- Optional properties.
	@return Promise -- A promise that resolves when the sound ends or is stopped.
]]
--
function SoundUtil.PlayAsync(self: SoundUtil, name: string, properties: SoundProperties?): PromiseLike
	local sound = self:EnsureLoaded(name)
	local sound_keeper = self.SoundKeepers[name]

	local is_duplicate = properties and properties.PlayDuplicate == true

	if not is_duplicate and self.ActivePromises[name] then
		self.ActivePromises[name]:cancel()
	end

	local target_sound = sound
	if is_duplicate then
		target_sound = sound:Clone()
		target_sound.Parent = sound.Parent
	end

	apply_properties(target_sound, properties)

	target_sound:Play()
	self.OnPlay:Fire(name, target_sound)

	local play_promise = Promise.new(function(resolve, _, on_cancel)
		-- Use the per-sound keeper to register the Ended connection so
		-- it will automatically be cleaned when the sound is destroyed.
		local connection = nil
		if not is_duplicate and sound_keeper then
			connection = sound_keeper:Once(target_sound.Ended, function()
				self.OnStop:Fire(name, target_sound)
				self.ActivePromises[name] = nil
				resolve(true)
			end)
		else
			connection = target_sound.Ended:Once(function()
				self.OnStop:Fire(name, target_sound)
				if is_duplicate then
					pcall(function()
						target_sound:Destroy()
					end)
				else
					self.ActivePromises[name] = nil
				end
				resolve(true)
			end)
		end

		on_cancel(function()
			if connection then
				if not is_duplicate and sound_keeper then
					sound_keeper:Remove(connection)
				else
					pcall(function()
						connection:Disconnect()
					end)
				end
			end

			pcall(function()
				target_sound:Stop()
			end)
			self.OnStop:Fire(name, target_sound)

			if is_duplicate then
				pcall(function()
					target_sound:Destroy()
				end)
			else
				self.ActivePromises[name] = nil
			end
		end)
	end)

	if not is_duplicate then
		self.ActivePromises[name] = play_promise
		if sound_keeper then
			sound_keeper:AddPromise(play_promise)
		end
	end

	return play_promise
end

--[[
	Stops a playing sound track by name.
	@param name string -- The registered sound name.
]]
--
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
]]
--
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
]]
--
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
]]
--
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
]]
--
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
]]
--
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

--[[
	Plays a sound instantly on the manager's target instance using a dictionary of options or a sound name.
	Automatically manages creating, playing, and destroying the temporary Sound instance.
	@param sound_name string -- The registered sound name or asset ID to play.
	@param properties SoundProperties -- Dictionary of properties for the sound:
		- Volume: number? -- The volume of the sound.
		- PlaybackSpeed: number? -- The speed of the playback.
		- Looped: boolean? -- Whether the sound should loop.
		- SoundGroup: (string | SoundGroup)? -- SoundGroup name or instance.
		- RollOffMode: Enum.RollOffMode? -- Attenuation roll-off mode.
		- RollOffMaxDistance: number? -- Maximum audible distance.
		- RollOffMinDistance: number? -- Minimum distance before volume begins to drop.
		- TimePosition: number? -- Starting position in seconds.
		- PlayDuplicate: boolean? -- Whether to clone and play as a separate one-off duplicate.
	@return Sound -- The created Sound instance.
]]
--
function SoundUtilModule.QuickPlay(self: any, arg1: any, arg2: any): Sound
	local sound_util: SoundUtil
	local second_arg = arg1
	local third_arg = arg2

	if typeof(self) == "Instance" then
		sound_util = SoundUtilModule.Get(self)
	elseif typeof(self) == "table" and self.TargetInstance then
		sound_util = self
	else
		error("QuickPlay must be called on a SoundUtil instance or a Roblox Instance", 2)
	end

	local sound_name_or_id: string? = nil
	local properties: { [string]: any }? = nil

	if typeof(second_arg) == "string" then
		sound_name_or_id = second_arg
		properties = third_arg
	elseif typeof(second_arg) == "table" then
		properties = second_arg
		sound_name_or_id = second_arg.Name or second_arg.SoundId
	end

	local resolved_id = sound_name_or_id and (sound_util.SoundMap[sound_name_or_id] or sound_name_or_id)
	if not resolved_id and properties then
		resolved_id = properties.SoundId or (properties.Name and sound_util.SoundMap[properties.Name])
	end

	if not resolved_id then
		PrintUtil:Error(
			`Sound not found: {tostring(sound_name_or_id or (properties and (properties.Name or properties.SoundId)))}`
		)
		error("SoundId/Name could not be resolved for QuickPlay", 2)
	end

	local play_local = properties and (properties.PlayLocal or properties.Local)
	local play_part = properties and (properties.PlayPart or properties.Part)
	local play_cframe = properties and (properties.PlayCFrame or properties.CFrame)

	local sound = sound_util.Keeper:Add(Instance.new("Sound"))
	sound.SoundId = resolved_id
	sound.Name = sound_name_or_id or "QuickPlaySound"

	local name_for_events = sound_name_or_id or resolved_id

	-- Set SoundGroup if specified in registry/properties
	local sound_group = properties and properties.SoundGroup
		or (sound_name_or_id and sound_util.SoundGroups[sound_name_or_id])
	if sound_group then
		if typeof(sound_group) == "string" then
			sound.SoundGroup = SoundUtilModule.AddSoundGroup(sound_group)
		else
			sound.SoundGroup = sound_group
		end
	end

	local cleanup_part = nil

	if play_local then
		if not RunService:IsClient() then
			error("PlayLocal must be called from the client", 2)
		end
		local player = typeof(play_local) == "Instance" and play_local:IsA("Player") and play_local
			or game:GetService("Players").LocalPlayer
		if not player then
			error("Local player not found for PlayLocal", 2)
		end
		sound.Parent = workspace.CurrentCamera
	elseif play_part then
		if typeof(play_part) ~= "Instance" then
			error("PlayPart option must be a Roblox Instance", 2)
		end
		sound.Parent = play_part
	elseif play_cframe then
		if typeof(play_cframe) ~= "CFrame" then
			error("PlayCFrame option must be a CFrame", 2)
		end
		local part = sound_util.Keeper:Add(Instance.new("Part"))
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		part.Anchored = true
		part.CanCollide = false
		part.Transparency = 1
		part.CFrame = play_cframe
		part.Name = (sound_name_or_id or "QuickPlaySound") .. "_sound"
		part.Parent = workspace

		sound.Parent = part
		cleanup_part = part
	else
		sound.Parent = sound_util.TargetInstance
	end

	-- Apply properties after parenting so Roblox Sound properties
	-- (e.g. Volume, RollOffMode) are reliably set on a live instance.
	apply_properties(sound, properties)

	local connection
	connection = sound_util.Keeper:Add(sound.Ended:Once(function()
		sound_util.OnStop:Fire(name_for_events, sound)
		if connection then
			sound_util.Keeper:Remove(connection)
		end
		sound_util.Keeper:Remove(sound)
		if cleanup_part then
			sound_util.Keeper:Remove(cleanup_part)
		end
	end))

	sound:Play()
	sound_util.OnPlay:Fire(name_for_events, sound)

	return sound
end

SoundUtil.QuickPlay = SoundUtilModule.QuickPlay

return SoundUtilModule
