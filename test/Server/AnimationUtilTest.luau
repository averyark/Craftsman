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
		local folder = Instance.new("Folder")
		folder.Parent = workspace
		local animator = Instance.new("Animator")
		animator.Parent = folder

		local a1 = Craftsman.AnimationUtil.new(animator)
		local a2 = Craftsman.AnimationUtil.Get(animator)

		assert(a1 == a2, "Subsequent calls to new/Get with same animator should return cached utility")

		folder:Destroy()
	end)

	run_case(results, "AnimationUtil force_new parameter bypasses caching", function()
		local folder = Instance.new("Folder")
		folder.Parent = workspace
		local animator = Instance.new("Animator")
		animator.Parent = folder

		local a1 = Craftsman.AnimationUtil.new(animator)
		local a2 = Craftsman.AnimationUtil.new(animator, nil, true)

		assert(a1 ~= a2, "Passing force_new = true should bypass cache and create new instance")

		-- The cached instance should still be a1
		local a3 = Craftsman.AnimationUtil.Get(animator)
		assert(a3 == a1, "Caching for the original should remain unaffected by force_new")

		folder:Destroy()
	end)

	run_case(results, "AnimationUtil.Destroy cleans up cache and internal states", function()
		local folder = Instance.new("Folder")
		folder.Parent = workspace
		local animator = Instance.new("Animator")
		animator.Parent = folder

		local a1 = Craftsman.AnimationUtil.new(animator)

		a1:Destroy()

		-- Verify cache is cleared
		local a2 = Craftsman.AnimationUtil.new(animator, nil, true)
		local a3 = Craftsman.AnimationUtil.Get(animator)
		assert(a2 == a3, "Get should return the newly created instance after Destroy cleared the cache")

		folder:Destroy()
	end)

	run_case(results, "Reference cleanup upon removing an animation", function()
		local folder = Instance.new("Folder")
		folder.Parent = workspace
		local animator = Instance.new("Animator")
		animator.Parent = folder

		local a1 = Craftsman.AnimationUtil.new(animator)

		a1:AddAnimationId("Run", "rbxassetid://12345")
		assert(a1.AnimationMap["Run"] == "rbxassetid://12345", "AnimationId should be mapped")

		a1:RemoveAnimation("Run")
		assert(a1.AnimationMap["Run"] == nil, "AnimationMap entry should be nil after removal")
		assert(a1.ActivePromises["Run"] == nil, "ActivePromises entry should be nil after removal")

		folder:Destroy()
	end)

	Craftsman.PrintUtil:ListPrint("AnimationUtil Test Results", { "Case", "Status", "Message" }, results)
end

return test
