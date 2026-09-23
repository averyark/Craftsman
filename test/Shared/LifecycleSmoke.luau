--!strict
--[[
    FileName    > LifecycleSmoke.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 17/07/2026

    Smoke test for the 0.8.0 changes that only Roblox can answer, and the companion to
    BarrelSmoke (which covers the lazy barrel, P1.2).

    Everything here was verified under lune first, but lune stubs `require`, `game`,
    `task` and `Keeper` -- so it proves the logic and not the integration. This runs the
    real loader over real ModuleScripts in a real boot.

    Covers: the Component alias to Lifecycle (0.10.0), P1.1 config inversion,
    P2.1 radian helpers, P2.2 Entity rig accessors. The loader itself is tested in
    averyark/craftsman-lifecycle.
--]]

const Craftsman = require("@game/ReplicatedStorage/Packages/Craftsman")

local LifecycleSmoke = {}

function LifecycleSmoke.Run(context: "server" | "client"): number
	local failures = 0
	local checks = 0

	local function check(name: string, ok: boolean, detail: string?)
		checks += 1
		if not ok then
			failures += 1
			warn(`[LifecycleSmoke/{context}] FAIL  {name}` .. (if detail then `  -- {detail}` else ""))
		end
	end

	-- 0.10.0 ---------------------------------------------------------------------
	-- The loader moved to averyark/craftsman-lifecycle, which tests it. Here it only
	-- has to be the same module Craftsman.Component forwards to.
	local Lifecycle = require("@game/ReplicatedStorage/Packages/packages/roblox/Lifecycle")
	check("Craftsman.Component forwards to Lifecycle", rawequal(Craftsman.Component, Lifecycle))
	check("the forwarded loader can load", type(Craftsman.Component.LoadModulesAsync) == "function")

	-- P1.1 ------------------------------------------------------------------------
	-- The consumer's CraftsmanConfig is now optional rather than hard-required. This
	-- place defines one, so it must still be picked up exactly as before.
	check("Config resolves", Craftsman.Config ~= nil)
	check(
		"defaults present",
		Craftsman.Config.INTERFACE.MIN_SCALE == 0.5,
		tostring(Craftsman.Config.INTERFACE.MIN_SCALE)
	)
	check(
		"consumer config applied",
		Craftsman.Config.INTERFACE.TEN_FOOT_BOOST == 1.5,
		"CraftsmanConfig's INTERFACE.TEN_FOOT_BOOST did not reach Config"
	)
	check("Configure is exposed", type(Craftsman.Config.Configure) == "function")

	-- P2.1 ------------------------------------------------------------------------
	local approached = Craftsman.MathUtil.ApproachAngle(6.2, 0.1, 1)
	check("ApproachAngle wraps the short way", approached > 6.2, tostring(approached))
	check(
		"ShortestAngleRad stays within [-pi, pi]",
		math.abs(Craftsman.MathUtil.ShortestAngleRad(0.1, 6.2)) <= math.pi + 1e-6
	)

	-- P2.2 ------------------------------------------------------------------------
	local rig = Instance.new("Model")
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = rig
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = rig
	rig.PrimaryPart = root
	rig.Parent = workspace

	local entity_ok, entity = pcall(Craftsman.Entity.new, rig, nil)
	check("Entity.new accepts a complete rig", entity_ok, tostring(entity))

	if entity_ok then
		check("GetHumanoid finds the Humanoid", entity:GetHumanoid() == humanoid)
		check("GetRoot finds the HumanoidRootPart", entity:GetRoot() == root)

		-- The accessors read the rig as it is now, unlike the fields captured at construction.
		humanoid:Destroy()
		check("GetHumanoid returns nil once the Humanoid is gone", entity:GetHumanoid() == nil)
		check("GetRoot still resolves", entity:GetRoot() == root)
	end

	rig:Destroy()

	--
	if context == "client" then
		local gui = Instance.new("ScreenGui")
		gui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

		local unbind = Craftsman.InterfaceUtil:AutoScale(gui)
		local scale = gui:FindFirstChildWhichIsA("UIScale")

		check("AutoScale created a UIScale", scale ~= nil)
		check("it scaled to something sane", scale ~= nil and scale.Scale > 0)
		check(
			"the applied scale matches ComputeScale",
			scale ~= nil
				and math.abs(
						scale.Scale - Craftsman.InterfaceUtil.ComputeScale(workspace.CurrentCamera.ViewportSize)
					)
					< 1e-4,
			tostring(scale and scale.Scale)
		)

		local rebind = Craftsman.InterfaceUtil:AutoScale(gui)
		local scales = 0
		for _, child in gui:GetChildren() do
			if child:IsA("UIScale") then
				scales += 1
			end
		end
		check("rebinding does not stack a second UIScale", scales == 1, `{scales} UIScales`)

		rebind()
		check("unbind destroyed the UIScale it created", gui:FindFirstChildWhichIsA("UIScale") == nil)

		unbind()
		gui:Destroy()
	else
		local ok = pcall(function()
			Craftsman.InterfaceUtil:AutoScale(Instance.new("ScreenGui"))
		end)
		check("AutoScale refuses to run on the server", not ok)
	end
	--

	if failures == 0 then
		print(`[LifecycleSmoke/{context}] all {checks} checks passed`)
	else
		warn(`[LifecycleSmoke/{context}] {failures} of {checks} checks FAILED`)
	end

	return failures
end

return LifecycleSmoke
