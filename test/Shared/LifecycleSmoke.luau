--!nonstrict
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

    Covers: P1.3 dependency-ordered start, P1.4 Stop + Keeper, P1.1 config inversion,
    P0.1 PrintUtil:Error levels, P2.1 radian helpers, P2.2 Entity rig accessors.
--]]

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Craftsman = require("@game/ReplicatedStorage/Packages/Craftsman")
const SmokeRecord = require("@game/ReplicatedStorage/Shared/SmokeRecord")

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

	-- P1.3 / P1.4 -----------------------------------------------------------------
	-- Drive the fixtures through a scratch loader rather than the one that booted the
	-- game: StopModulesAsync would otherwise tear down the very modules running this.
	-- Its own Modules/LoadedModules are seeded so `self.Modules or {}` cannot reach
	-- through the metatable and share the real loader's tables.
	local loader = setmetatable({ Modules = {}, LoadedModules = {} }, { __index = Craftsman.Component })

	-- Not a dot-index: that hard-errors with nothing actionable, and on the client the
	-- folder has to replicate first. Adding Fixtures to test.project.json also needs a
	-- fresh sync -- rojo serve does not pick up a new top-level tree node on its own.
	local fixtures = ReplicatedStorage:FindFirstChild("Fixtures") or ReplicatedStorage:WaitForChild("Fixtures", 5)
	if not fixtures then
		check(
			"ReplicatedStorage.Fixtures exists",
			false,
			"missing -- rebuild the place (rojo build test.project.json) or restart rojo serve"
		)
		warn(`[LifecycleSmoke/{context}] {failures} of {checks} checks FAILED`)
		return failures
	end

	SmokeRecord.Reset()
	local loaded_ok, loaded_err = loader:LoadModulesAsync(fixtures):await()
	check("fixtures loaded", loaded_ok, tostring(loaded_err))

	local alpha_end = SmokeRecord.IndexOf("Alpha", "start_end")
	local beta_begin = SmokeRecord.IndexOf("Beta", "start_begin")
	local solo_begin = SmokeRecord.IndexOf("Solo", "start_begin")

	check("Alpha started", alpha_end ~= nil)
	check("Beta started", beta_begin ~= nil)
	check("Solo started", solo_begin ~= nil)

	if alpha_end and beta_begin then
		-- The declared edge: Beta must not begin until Alpha has *finished*.
		check("Beta waited for its declared dependency", beta_begin > alpha_end, "Beta started before Alpha finished")
	end

	if alpha_end and solo_begin then
		-- The absence of an edge: Solo must not be dragged behind Alpha's yield.
		check("Solo ran concurrently with Alpha's yield", solo_begin < alpha_end, "independent modules serialised")
	end

	-- Read before Stop: StopModulesAsync clears LoadedModules.
	local solo_module = loader.LoadedModules.Solo
	check("Solo was loaded", solo_module ~= nil)
	check("loader granted the module a Keeper", solo_module ~= nil and solo_module.Keeper ~= nil)
	check(
		"the scratch loader did not share the real loader's tables",
		loader.LoadedModules ~= Craftsman.Component.LoadedModules
	)

	local stopped_ok, stopped_err = loader:StopModulesAsync():await()
	check("fixtures stopped", stopped_ok ~= false, tostring(stopped_err))

	local beta_stop = SmokeRecord.IndexOf("Beta", "stop")
	local alpha_stop = SmokeRecord.IndexOf("Alpha", "stop")
	check("Beta stopped", beta_stop ~= nil)
	check("Alpha stopped", alpha_stop ~= nil)

	if beta_stop and alpha_stop then
		-- Teardown is the start graph reversed: the dependent goes first.
		check("dependent stopped before its dependency", beta_stop < alpha_stop, "a dependency was torn down first")
	end

	check("Keeper cleaned up on Stop", SmokeRecord.IndexOf("Solo", "keeper_cleaned") ~= nil)
	check("loader reports unloaded", loader.IsLoaded == false)

	-- P1.1 ------------------------------------------------------------------------
	-- The consumer's CraftsmanConfig is now optional rather than hard-required. This
	-- place defines one, so it must still be picked up exactly as before.
	check("Config resolves", Craftsman.Config ~= nil)
	check(
		"defaults present",
		Craftsman.Config.DATA.STORE_NAME == "CraftsmanData",
		tostring(Craftsman.Config.DATA.STORE_NAME)
	)
	check(
		"consumer config applied",
		Craftsman.Config.DATA.SCHEMA ~= nil,
		"CraftsmanConfig's SCHEMA did not reach Config"
	)
	check("Configure is exposed", type(Craftsman.Config.Configure) == "function")

	-- P0.1 ------------------------------------------------------------------------
	local ok, err = pcall(function()
		Craftsman.PrintUtil:Error("smoke_probe", 2)
	end)
	check("Error throws", not ok)
	check("level is not stringified into the message", not tostring(err):find("smoke_probe 2"), tostring(err))
	check("message survives", tostring(err):find("smoke_probe") ~= nil, tostring(err))

	-- Informational: which module the prefix names depends on whether Roblox inlines
	-- PrintUtil's local helpers, which is the open question in the proposal's Rejected
	-- section. Reported rather than asserted -- it is not this test's call to make.
	print(`[LifecycleSmoke/{context}] PrintUtil:Error prefix reads: {tostring(err)}`)

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

	local entity_ok, entity = pcall(Craftsman.Entity.new, rig)
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
