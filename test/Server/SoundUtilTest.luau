--!nonstrict
--[[
	FileName    > SoundUtilTest.luau
	Author      > AveryArk
	Contact     > Twitter: https://twitter.com/averyark_
	Created     > 30/05/2026
--]]

const Craftsman = require("@game/ReplicatedStorage/Packages/Craftsman")
const SoundService = game:GetService("SoundService")

local test = Craftsman.Component.new({})

local function run_case(results: { { string } }, case_name: string, callback: () -> ())
	local ok, err = pcall(callback)
	table.insert(results, {
		case_name,
		if ok then "success" else "fail",
		if ok then "" else tostring(err),
	})
end

function test:Start()
	Craftsman.PrintUtil:Print("SoundUtil SoundGroup test started")

	local results = {}

	run_case(results, "AddSoundGroup by string creates and parents to SoundService", function()
		local group_name = "TestGroupString_" .. tostring(math.random(1000, 9999))
		local group = Craftsman.SoundUtil.AddSoundGroup(group_name)

		assert(group ~= nil, "Group should not be nil")
		assert(group:IsA("SoundGroup"), "Group should be a SoundGroup instance")
		assert(group.Name == group_name, "Group name should match")
		assert(group.Parent == SoundService, "Group should be parented to SoundService")

		-- Verify it caches and retrieves from cache/SoundService
		local retrieved = Craftsman.SoundUtil.GetSoundGroup(group_name)
		assert(retrieved == group, "Should retrieve the same group from cache")
	end)

	run_case(results, "AddSoundGroup by instance caches and parents to SoundService", function()
		local group_name = "TestGroupInstance_" .. tostring(math.random(1000, 9999))
		local group = Instance.new("SoundGroup")
		group.Name = group_name

		local added = Craftsman.SoundUtil.AddSoundGroup(group)
		assert(added == group, "Should return the same instance")
		assert(group.Parent == SoundService, "Should parent to SoundService")

		local retrieved = Craftsman.SoundUtil.GetSoundGroup(group_name)
		assert(retrieved == group, "Should cache by name")
	end)

	run_case(results, "ConfigureSoundGroup configures properties of SoundGroup", function()
		local group_name = "TestGroupConfigure_" .. tostring(math.random(1000, 9999))
		local group = Craftsman.SoundUtil.ConfigureSoundGroup(group_name, {
			Volume = 0.75,
		})

		assert(group.Volume == 0.75, "Volume property should be set to 0.75")
	end)

	run_case(results, "Client deduplication: reuse existing SoundGroup in SoundService", function()
		local group_name = "TestDeduplication_" .. tostring(math.random(1000, 9999))

		-- Pre-create in SoundService to simulate server-side replication
		local pre_created = Instance.new("SoundGroup")
		pre_created.Name = group_name
		pre_created.Parent = SoundService

		-- AddSoundGroup should find and reuse it
		local group = Craftsman.SoundUtil.AddSoundGroup(group_name)
		assert(group == pre_created, "Should reuse pre-existing SoundGroup and not create a new one")

		-- Clean up the pre-created one
		pre_created:Destroy()
	end)

	run_case(results, "Binding SoundGroup via AddSound specifies group for sound", function()
		local group_name = "TestSoundGroup_" .. tostring(math.random(1000, 9999))
		local folder = Instance.new("Folder")
		folder.Parent = workspace
		local sound_util = Craftsman.SoundUtil.new(folder)

		sound_util:AddSound("Boom", "rbxassetid://13750192967", group_name)

		-- Load sound and verify SoundGroup is assigned
		local sound = sound_util:Load("Boom")
		assert(sound.SoundGroup ~= nil, "Loaded sound should have a SoundGroup")
		assert(sound.SoundGroup.Name == group_name, "Loaded sound should have the correct SoundGroup name")

		folder:Destroy()
	end)

	run_case(results, "SetSoundGroup separately configures/updates sound group", function()
		local group_name = "OriginalGroup_" .. tostring(math.random(1000, 9999))
		local new_group_name = "UpdatedGroup_" .. tostring(math.random(1000, 9999))
		local folder = Instance.new("Folder")
		folder.Parent = workspace
		local sound_util = Craftsman.SoundUtil.new(folder)

		sound_util:AddSound("Boom", "rbxassetid://13750192967", group_name)

		-- Set new group separately before load
		sound_util:SetSoundGroup("Boom", new_group_name)

		local sound = sound_util:Load("Boom")
		assert(sound.SoundGroup.Name == new_group_name, "Should use updated sound group")

		-- Update separately after load
		local custom_group = Instance.new("SoundGroup")
		custom_group.Name = "CustomGroup"
		sound_util:SetSoundGroup("Explosion", custom_group)

		assert(sound.SoundGroup == custom_group, "Should immediately update loaded sound instance")

		folder:Destroy()
		custom_group:Destroy()
	end)

	run_case(results, "SoundUtil.Get alias exists and behaves identically to new", function()
		assert(Craftsman.SoundUtil.Get == Craftsman.SoundUtil.new, "Get should be a direct alias of new")
	end)

	run_case(results, "SoundUtil instance caching works by default", function()
		local folder = Instance.new("Folder")
		folder.Parent = workspace
		local s1 = Craftsman.SoundUtil.new(folder)
		local s2 = Craftsman.SoundUtil.Get(folder)

		assert(s1 == s2, "Subsequent calls to new/Get with same instance should return cached utility")

		folder:Destroy()
	end)

	run_case(results, "SoundUtil force_new parameter bypasses caching", function()
		local folder = Instance.new("Folder")
		folder.Parent = workspace
		local s1 = Craftsman.SoundUtil.new(folder)
		local s2 = Craftsman.SoundUtil.new(folder, nil, true)

		assert(s1 ~= s2, "Passing force_new = true should bypass cache and create new instance")

		-- The cached instance should still be s1
		local s3 = Craftsman.SoundUtil.Get(folder)
		assert(s3 == s1, "Caching for the original should remain unaffected by force_new")

		folder:Destroy()
	end)

	run_case(results, "SoundUtil.Destroy cleans up cache and internal states", function()
		local folder = Instance.new("Folder")
		folder.Parent = workspace
		local s1 = Craftsman.SoundUtil.new(folder)

		s1:Destroy()

		-- Verify cache is cleared
		local s2 = Craftsman.SoundUtil.Get(folder)
		assert(s2 ~= s1, "Get should return a new instance after the previous one was destroyed")

		folder:Destroy()
	end)

	run_case(results, "AddSound immediately instantiates Sound in target_instance", function()
		local folder = Instance.new("Folder")
		folder.Parent = workspace
		local sound_util = Craftsman.SoundUtil.new(folder)

		sound_util:AddSound("Boom", "rbxassetid://13750192967")

		local sound = folder:FindFirstChild("Boom")
		assert(sound ~= nil, "Sound should be immediately instantiated in the folder")
		assert(sound:IsA("Sound"), "Instantiated child should be a Sound")
		assert(sound.SoundId == "rbxassetid://13750192967", "SoundId should match")

		folder:Destroy()
	end)

	run_case(results, "AddSound deduplication: multiple calls do not create duplicates", function()
		local folder = Instance.new("Folder")
		folder.Parent = workspace
		local sound_util = Craftsman.SoundUtil.new(folder)

		sound_util:AddSound("Boom", "rbxassetid://13750192967")
		sound_util:AddSound("Boom", "rbxassetid://9876543210")

		local sounds = {}
		for _, child in folder:GetChildren() do
			if child.Name == "Boom" and child:IsA("Sound") then
				table.insert(sounds, child)
			end
		end

		assert(#sounds == 1, "There should be exactly one Sound instance in target_instance, no duplicates")
		assert(sounds[1].SoundId == "rbxassetid://9876543210", "SoundId should be updated to the new one")

		folder:Destroy()
	end)

	run_case(results, "AddSound deduplication: reuses pre-existing Sound child in target_instance", function()
		local folder = Instance.new("Folder")
		folder.Parent = workspace

		-- Pre-create Sound instance in folder
		local pre_existing = Instance.new("Sound")
		pre_existing.Name = "Boom"
		pre_existing.SoundId = "rbxassetid://11111111"
		pre_existing.Parent = folder

		local sound_util = Craftsman.SoundUtil.new(folder)
		sound_util:AddSound("Boom", "rbxassetid://22222222")

		local sounds = {}
		for _, child in folder:GetChildren() do
			if child.Name == "Boom" and child:IsA("Sound") then
				table.insert(sounds, child)
			end
		end

		assert(#sounds == 1, "Should reuse pre-existing Sound and not create a duplicate")
		assert(sounds[1] == pre_existing, "Should be the exact pre-existing sound instance")
		assert(pre_existing.SoundId == "rbxassetid://22222222", "SoundId should be updated to the new one")

		folder:Destroy()
	end)

	run_case(results, "Play with PlayDuplicate = true clones and plays duplicate sound", function()
		local folder = Instance.new("Folder")
		folder.Parent = workspace
		local sound_util = Craftsman.SoundUtil.new(folder)
		sound_util:AddSound("Boom", "rbxassetid://13750192967")

		local original_sound = folder:FindFirstChild("Boom")
		assert(original_sound ~= nil, "Original sound should exist")

		local on_play_fired = false
		local played_sound = nil
		local conn = sound_util.OnPlay:Connect(function(name, sound)
			if name == "Boom" then
				on_play_fired = true
				played_sound = sound
			end
		end)

		sound_util:Play("Boom", { PlayDuplicate = true, Volume = 0.8 })

		assert(on_play_fired == true, "OnPlay should have fired")
		assert(played_sound ~= nil, "Should have passed the played sound")
		assert(played_sound ~= original_sound, "Played sound should be a clone, not the original")
		assert(played_sound.Volume == 0.8, "Should apply properties to the cloned sound")
		assert(played_sound.Parent == folder, "Cloned sound should be parented to the same parent as original")

		conn:Disconnect()
		folder:Destroy()
	end)

	run_case(results, "PlayAsync with PlayDuplicate = true cancellation cleans up clone", function()
		local folder = Instance.new("Folder")
		folder.Parent = workspace
		local sound_util = Craftsman.SoundUtil.new(folder)
		sound_util:AddSound("Boom", "rbxassetid://13750192967")

		local played_sound = nil
		local conn = sound_util.OnPlay:Connect(function(name, sound)
			if name == "Boom" then
				played_sound = sound
			end
		end)

		local p = sound_util:PlayAsync("Boom", { PlayDuplicate = true })
		assert(played_sound ~= nil, "Should have played duplicate")
		assert(played_sound ~= folder:FindFirstChild("Boom"), "Should be a duplicate instance, not the original")

		p:cancel()

		assert(played_sound.Parent == nil, "Duplicate should be destroyed and unparented upon cancellation")

		conn:Disconnect()
		folder:Destroy()
	end)

	Craftsman.PrintUtil:ListPrint("SoundUtil SoundGroup Test Results", { "Case", "Status", "Message" }, results)
end

return test
