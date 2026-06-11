--!nonstrict
--[[
	FileName    > TweenUtilTest.luau
	Author      > AveryArk
	Contact     > Twitter: https://twitter.com/averyark_
	Created     > 31/05/2026
--]]

const Craftsman = require("@game/ReplicatedStorage/Packages/Craftsman")

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
	Craftsman.PrintUtil:Print("TweenUtil Template & Spring test started")

	local results = {}

	-- Register test templates
	Craftsman.TweenUtil.new("PartFade", Enum.EasingStyle.Linear, {
		Transparency = 1,
	}, 0.05, Enum.EasingDirection.Out)

	Craftsman.TweenUtil.new("PartFadeSpring", "Spring", {
		Transparency = 0.5,
	}, 1.0, 10.0)

	Craftsman.TweenUtil.new("PartGrow", Enum.EasingStyle.Quad, {
		Size = Vector3.new(5, 5, 5),
	}, 0.05, Enum.EasingDirection.Out)

	run_case(results, "TweenUtil template registration stores templates correctly", function()
		local template = Craftsman.TweenUtil.new("TempCheck", Enum.EasingStyle.Quad, { Transparency = 0.5 })
		assert(template ~= nil, "Template registration should return the created config")
		assert(template.Type == "Tween", "Default type should be Tween")
		assert(template.Duration == 0.3, "Default duration should be 0.3")
	end)

	run_case(results, "Tween template playback and value transition works", function()
		local part = Instance.new("Part")
		part.Transparency = 0
		part.Parent = workspace

		local tween = Craftsman.TweenUtil.Play("PartFade", part)
		assert(tween ~= nil, "Play on a tween template should return a Tween object")
		task.wait(0.1)

		assert(part.Transparency == 1, "Transparency should successfully animate to 1")
		part:Destroy()
	end)

	run_case(results, "Tween PlayFrom snaps properties and animates correctly", function()
		local part = Instance.new("Part")
		part.Transparency = 0
		part.Parent = workspace

		local tween = Craftsman.TweenUtil.PlayFrom("PartFade", part, { Transparency = 0.25 })
		assert(part.Transparency == 0.25, "Should immediately snap to starting value")
		task.wait(0.1)

		assert(
			part.Transparency == 1,
			"Should successfully complete animation to 1. Actual: " .. tostring(part.Transparency)
		)
		part:Destroy()
	end)

	run_case(results, "Spring template playback executes successfully", function()
		local part = Instance.new("Part")
		part.Transparency = 0
		part.Parent = workspace

		local tween = Craftsman.TweenUtil.Play("PartFadeSpring", part)
		assert(tween == nil, "Spring animation does not return a standard Tween object")
		task.wait(0.1)

		assert(part.Transparency > 0.4 and part.Transparency < 0.6, "Spring should pull transparency to target ~0.5")
		part:Destroy()
	end)

	run_case(results, "Promise PlayAsync resolves for standard Tweens", function()
		local part = Instance.new("Part")
		part.Transparency = 0
		part.Parent = workspace

		local resolved = false
		Craftsman.TweenUtil
			.PlayAsync("PartFade", part)
			:andThen(function()
				resolved = true
			end)
			:await()

		assert(resolved == true, "Promise should resolve when Tween completes")
		assert(part.Transparency == 1, "Transparency should be 1")
		part:Destroy()
	end)

	run_case(results, "Promise PlayAsync resolves for Springs when settled", function()
		local part = Instance.new("Part")
		part.Transparency = 0
		part.Parent = workspace

		local resolved = false
		Craftsman.TweenUtil
			.PlayAsync("PartFadeSpring", part)
			:andThen(function()
				resolved = true
			end)
			:await()

		assert(resolved == true, "Promise should resolve when Spring settles")
		assert(part.Transparency > 0.4 and part.Transparency < 0.6, "Spring should settle near target 0.5")
		part:Destroy()
	end)

	run_case(results, "Unified Deduplication: standard Tween cancels conflicting properties", function()
		local part = Instance.new("Part")
		part.Transparency = 0
		part.Parent = workspace

		-- Start a long tween
		Craftsman.TweenUtil.new("LongFade", Enum.EasingStyle.Linear, { Transparency = 1 }, 1.0)
		local tween1 = Craftsman.TweenUtil.Play("LongFade", part)

		-- Play a new overlapping tween
		local tween2 = Craftsman.TweenUtil.Play("PartFade", part)

		assert(
			tween1.PlaybackState == Enum.PlaybackState.Cancelled,
			"First tween should be cancelled by overlapping property"
		)
		task.wait(0.1)
		assert(part.Transparency == 1, "Second tween should complete successfully")
		part:Destroy()
	end)

	run_case(results, "Unified Deduplication: playing a Tween stops conflicting Springs", function()
		local part = Instance.new("Part")
		part.Transparency = 0
		part.Parent = workspace

		-- Start Spring animation
		Craftsman.TweenUtil.Play("PartFadeSpring", part)

		-- Immediately play a standard Tween on same property
		local tween = Craftsman.TweenUtil.Play("PartFade", part)
		assert(tween ~= nil, "Should return valid Tween object")
		task.wait(0.1)

		assert(part.Transparency == 1, "Tween should take over and successfully drive transparency to 1")
		part:Destroy()
	end)

	run_case(results, "Tween nested children recursively works", function()
		local parent = Instance.new("Frame")
		local shadow = Instance.new("Frame")
		shadow.Name = "Shadow"
		shadow.Parent = parent
		local uiScale = Instance.new("UIScale")
		uiScale.Name = "UIScale"
		uiScale.Parent = shadow

		parent.BackgroundTransparency = 0
		shadow.BackgroundTransparency = 0
		uiScale.Scale = 1.0

		Craftsman.TweenUtil.new("NestedChildrenTest", Enum.EasingStyle.Linear, {
			BackgroundTransparency = 1,
			Shadow = {
				BackgroundTransparency = 1,
				UIScale = {
					Scale = 1.5,
				},
			},
		}, 0.05)

		local tween = Craftsman.TweenUtil.Play("NestedChildrenTest", parent)
		assert(tween ~= nil, "Should return a valid Tween / tween group object")
		task.wait(0.1)

		assert(parent.BackgroundTransparency == 1, "Parent background transparency should be 1")
		assert(shadow.BackgroundTransparency == 1, "Shadow background transparency should be 1")
		assert(uiScale.Scale == 1.5, "UIScale scale should be 1.5")
		parent:Destroy()
	end)

	run_case(results, "PlayFrom snaps nested properties recursively", function()
		local parent = Instance.new("Frame")
		local shadow = Instance.new("Frame")
		shadow.Name = "Shadow"
		shadow.Parent = parent
		local uiScale = Instance.new("UIScale")
		uiScale.Name = "UIScale"
		uiScale.Parent = shadow

		parent.BackgroundTransparency = 0
		shadow.BackgroundTransparency = 0
		uiScale.Scale = 1.0

		local tween = Craftsman.TweenUtil.PlayFrom("NestedChildrenTest", parent, {
			BackgroundTransparency = 0.5,
			Shadow = {
				BackgroundTransparency = 0.5,
				UIScale = {
					Scale = 1.2,
				},
			},
		})
		assert(parent.BackgroundTransparency == 0.5, "Parent should immediately snap to 0.5")
		assert(shadow.BackgroundTransparency == 0.5, "Shadow should immediately snap to 0.5")
		assert(uiScale.Scale == 1.2, "UIScale should immediately snap to 1.2")

		task.wait(0.1)
		assert(parent.BackgroundTransparency == 1, "Parent should animate to 1")
		assert(shadow.BackgroundTransparency == 1, "Shadow should animate to 1")
		assert(uiScale.Scale == 1.5, "UIScale should animate to 1.5")
		parent:Destroy()
	end)

	run_case(results, "TweenUtil.Stop cancels nested children tweens recursively", function()
		local parent = Instance.new("Frame")
		local shadow = Instance.new("Frame")
		shadow.Name = "Shadow"
		shadow.Parent = parent
		local uiScale = Instance.new("UIScale")
		uiScale.Name = "UIScale"
		uiScale.Parent = shadow

		parent.BackgroundTransparency = 0
		shadow.BackgroundTransparency = 0
		uiScale.Scale = 1.0

		Craftsman.TweenUtil.new("LongNestedTest", Enum.EasingStyle.Linear, {
			BackgroundTransparency = 1,
			Shadow = {
				BackgroundTransparency = 1,
				UIScale = {
					Scale = 1.5,
				},
			},
		}, 1.0)

		local tween = Craftsman.TweenUtil.Play("LongNestedTest", parent)
		task.wait(0.1)

		Craftsman.TweenUtil.Stop(parent)

		local val_parent = parent.BackgroundTransparency
		local val_shadow = shadow.BackgroundTransparency
		local val_scale = uiScale.Scale

		task.wait(0.1)
		assert(parent.BackgroundTransparency == val_parent, "Parent should be stopped")
		assert(shadow.BackgroundTransparency == val_shadow, "Shadow should be stopped")
		assert(uiScale.Scale == val_scale, "UIScale should be stopped")
		parent:Destroy()
	end)

	run_case(results, "QuickPlay plays animation immediately with dynamic parameter sorting", function()
		local part = Instance.new("Part")
		part.Transparency = 0
		part.Parent = workspace

		local tween1 = Craftsman.TweenUtil.QuickPlay(
			part,
			{ Transparency = 0.5 },
			0.05,
			Enum.EasingStyle.Linear,
			Enum.EasingDirection.Out
		)
		assert(tween1 ~= nil, "QuickPlay should return a valid Tween object")
		task.wait(0.08)
		assert(part.Transparency == 0.5, "Part transparency should animate to 0.5")

		local tween2 = Craftsman.TweenUtil.QuickPlay(
			part,
			0.05,
			Enum.EasingStyle.Linear,
			Enum.EasingDirection.Out,
			{ Transparency = 1.0 }
		)
		assert(tween2 ~= nil, "QuickPlay should return a valid Tween object")
		task.wait(0.08)
		assert(part.Transparency == 1.0, "Part transparency should animate to 1.0")

		part:Destroy()
	end)

	run_case(results, "tween_group completed event Once and Wait works", function()
		local parent = Instance.new("Frame")
		local shadow = Instance.new("Frame")
		shadow.Name = "Shadow"
		shadow.Parent = parent
		local uiScale = Instance.new("UIScale")
		uiScale.Name = "UIScale"
		uiScale.Parent = shadow

		parent.BackgroundTransparency = 0
		shadow.BackgroundTransparency = 0
		uiScale.Scale = 1.0

		local tween = Craftsman.TweenUtil.Play("NestedChildrenTest", parent)
		assert(tween ~= nil, "Should return a valid tween group object")

		local once_fired = false
		tween.Completed:Once(function(state)
			once_fired = true
		end)

		local state = tween.Completed:Wait()
		assert(state == Enum.PlaybackState.Completed, "Wait should return the playback state")
		assert(once_fired == true, "Once connection should have fired")

		parent:Destroy()
	end)

	Craftsman.PrintUtil:ListPrint("TweenUtil Template & Spring Test Results", { "Case", "Status", "Message" }, results)
end

return test
