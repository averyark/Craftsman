--!nonstrict
--[[
    FileName    > SoundUtil.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 20/05/2026
--]]

const RunService = game:GetService("RunService")

const Keeper = require("../../../../Keeper")
const Promise = require("../../../../Promise")
const Signal = require("../../../../Signal")

const SoundUtil = {}
SoundUtil.__index = SoundUtil

function SoundUtil.new(target_instance, sound_map)
	local self = setmetatable({}, SoundUtil)
	self.Keeper = Keeper.new()

	self.TargetInstance = target_instance
	self.SoundMap = sound_map or {}
	self.Sounds = {}
	self.SoundKeepers = {}
	self.ActivePromises = {}

	self.OnPlay = self.Keeper:Construct(Signal)
	self.OnStop = self.Keeper:Construct(Signal)

	return self
end

function SoundUtil:AddSound(name, sound_id)
	self.SoundMap[name] = sound_id
end

function SoundUtil:AddSoundId(name, sound_id)
	self:AddSound(name, sound_id)
end

function SoundUtil:_StopLoadedSound(name)
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

function SoundUtil:_RemoveLoadedSound(name)
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
end

function SoundUtil:RemoveSound(name)
	self:_RemoveLoadedSound(name)
end

function SoundUtil:RemoveSoundId(sound_id)
	local names_to_remove = {}

	for name, registered_sound_id in pairs(self.SoundMap) do
		if registered_sound_id == sound_id then
			table.insert(names_to_remove, name)
		end
	end

	for _, name in names_to_remove do
		self:_RemoveLoadedSound(name)
	end
end

function SoundUtil:Load(name)
	local sound_instance = Instance.new("Sound")
	sound_instance.SoundId = self.SoundMap[name]
	sound_instance.Name = name
	sound_instance.Parent = self.TargetInstance

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

function SoundUtil:EnsureLoaded(name)
	if self.Sounds[name] then
		return self.Sounds[name]
	end

	return self:Load(name)
end

function SoundUtil:Play(name, properties)
	local sound = self:EnsureLoaded(name)

	if properties then
		for key, value in properties do
			sound[key] = value
		end
	end

	sound:Play()
	self.OnPlay:Fire(name, sound)
end

function SoundUtil:PlayAsync(name, properties)
	local sound = self:EnsureLoaded(name)
	local sound_keeper = self.SoundKeepers[name]

	if self.ActivePromises[name] then
		self.ActivePromises[name]:cancel()
	end

	if properties then
		for key, value in properties do
			sound[key] = value
		end
	end

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

function SoundUtil:Stop(name)
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

function SoundUtil:StopAll()
	for name, _ in self.Sounds do
		self:Stop(name)
	end
end

function SoundUtil:TimePositionAsync(name, target_time)
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

function SoundUtil:PlayPart(part, name, properties)
	local sound = self.Keeper:Add(Instance.new("Sound"))
	sound.SoundId = self.SoundMap[name]
	sound.Name = name

	if properties then
		for key, value in properties do
			sound[key] = value
		end
	end

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

function SoundUtil:PlayCFrame(cframe, name, properties)
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

	if properties then
		for key, value in properties do
			sound[key] = value
		end
	end

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

function SoundUtil:PlayLocal(player, name, properties)
	if not RunService:IsClient() then
		error("PlayLocal must be called from the client", 2)
	end

	local sound = self.Keeper:Add(Instance.new("Sound"))
	sound.SoundId = self.SoundMap[name]
	sound.Name = name

	if properties then
		for key, value in properties do
			sound[key] = value
		end
	end

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

return SoundUtil
