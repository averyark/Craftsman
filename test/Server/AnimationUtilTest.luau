--!nonstrict
--[[
	FileName    > AnimationUtilTest.luau
	Author      > AveryArk
	Contact     > Twitter: https://twitter.com/averyark_
	Created     > 30/05/2026
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
	Craftsman.PrintUtil:Print("AnimationUtil caching and lifecycle test started")

	local results = {}

	run_case(results, "AnimationUtil.Get alias exists and behaves identically to new", function()
		assert(Craftsman.AnimationUtil.Get == Craftsman.AnimationUtil.new, "Get should be a direct alias of new")
	end)

	run_case(results, "AnimationUtil instance caching works by default", function()
		local model = Instance.new("Model")
		model.Parent = workspace
		local controller = Instance.new("AnimationController")
		controller.Parent = model
		local animator = Instance.new("Animator")
		animator.Parent = controller

		local a1 = Craftsman.AnimationUtil.new(animator)
		local a2 = Craftsman.AnimationUtil.Get(animator)

		assert(a1 == a2, "Subsequent calls to new/Get with same animator should return cached utility")

		model:Destroy()
	end)

	run_case(results, "AnimationUtil force_new parameter bypasses caching", function()
		local model = Instance.new("Model")
		model.Parent = workspace
		local controller = Instance.new("AnimationController")
		controller.Parent = model
		local animator = Instance.new("Animator")
		animator.Parent = controller

		local a1 = Craftsman.AnimationUtil.new(animator)
		local a2 = Craftsman.AnimationUtil.new(animator, nil, true)

		assert(a1 ~= a2, "Passing force_new = true should bypass cache and create new instance")

		-- The cached instance should still be a1
		local a3 = Craftsman.AnimationUtil.Get(animator)
		assert(a3 == a1, "Caching for the original should remain unaffected by force_new")

		model:Destroy()
	end)

	run_case(results, "AnimationUtil.Destroy cleans up cache and internal states", function()
		local model = Instance.new("Model")
		model.Parent = workspace
		local controller = Instance.new("AnimationController")
		controller.Parent = model
		local animator = Instance.new("Animator")
		animator.Parent = controller

		local a1 = Craftsman.AnimationUtil.new(animator)

		a1:Destroy()

		-- Verify cache is cleared
		local a2 = Craftsman.AnimationUtil.Get(animator)
		assert(a2 ~= a1, "Get should return a new instance after the previous one was destroyed")

		model:Destroy()
	end)

	run_case(results, "Reference cleanup upon removing an animation", function()
		local model = Instance.new("Model")
		model.Parent = workspace
		local controller = Instance.new("AnimationController")
		controller.Parent = model
		local animator = Instance.new("Animator")
		animator.Parent = controller

		local a1 = Craftsman.AnimationUtil.new(animator)

		a1:AddAnimationId("Run", "rbxassetid://91539600632847")
		assert(a1.AnimationMap["Run"] == "rbxassetid://91539600632847", "AnimationId should be mapped")

		a1:RemoveAnimation("Run")
		assert(a1.AnimationMap["Run"] == nil, "AnimationMap entry should be nil after removal")
		assert(a1.ActivePromises["Run"] == nil, "ActivePromises entry should be nil after removal")

		model:Destroy()
	end)

	Craftsman.PrintUtil:ListPrint("AnimationUtil Test Results", { "Case", "Status", "Message" }, results)
end

return test
