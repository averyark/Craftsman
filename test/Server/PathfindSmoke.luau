--!strict
--[[
    FileName    > PathfindSmoke.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 23/09/2026
--]]

const Players = game:GetService("Players")
const RunService = game:GetService("RunService")

const Config = require("@game/ReplicatedStorage/Packages/Craftsman/Config")
const Pathfind = require("@game/ReplicatedStorage/Packages/Craftsman/Pathfind")

local PathfindSmoke = {}

--
type Agent = {
	Rig: Model,
	Pathfind: Pathfind.Pathfind,
	Arrived: number,
	Stuck: number,
	Failed: { string },
	WaypointCounts: { number },
	JumpWaypoints: number,
}
--

--
const FLOOR_SIZE = Vector3.new(100, 1, 60)

const VIEWER_WAIT = 20
const ARENA_OFFSET = Vector3.new(0, 30, 100)
const VIEWPOINT_OFFSET = Vector3.new(0, 25, -75)
const LANE_LINGER = 2
const NAVMESH_SETTLE = 1

const PIT_WIDTH = 16
const JUMP_GAP_WIDTH = 5

const FLOOR_COLOR = Color3.fromRGB(200, 200, 205)
const OBSTACLE_COLOR = Color3.fromRGB(220, 70, 60)
const TARGET_COLOR = Color3.fromRGB(250, 200, 40)
const BRIDGE_COLOR = Color3.fromRGB(90, 160, 230)

const PATROL_LAPS = 3
const SWEEP_AMPLITUDE = 18
const SWEEP_PERIOD = 8
--

--
local Failures = 0
local Checks = 0
local ArenaOrigin = Vector3.zero
--

local function check(name: string, ok: boolean, detail: string?)
	--
	Checks += 1

	if ok then
		return
	end
	--

	--
	Failures += 1
	warn(`[PathfindSmoke] FAIL  {name}{if detail then `  -- {detail}` else ""}`)
	--
end

local function wait_until(predicate: () -> boolean, timeout: number): boolean
	--
	const deadline = os.clock() + timeout

	while os.clock() < deadline do
		if predicate() then
			return true
		end

		task.wait(0.1)
	end
	--

	return predicate()
end

local function await_outcome(promise: any, timeout: number): string
	--
	local outcome = "Pending"

	promise:andThen(function()
		outcome = "Resolved"
	end, function(reason)
		outcome = tostring(reason)
	end)
	--

	--
	wait_until(function()
		return promise:getStatus() ~= "Started"
	end, timeout)

	if promise:getStatus() == "Cancelled" then
		return "Cancelled"
	end

	if promise:getStatus() == "Started" then
		return "Timeout"
	end
	--

	return outcome
end

local function make_part(parent: Instance, size: Vector3, position: Vector3, color: Color3?): Part
	--
	const part = Instance.new("Part")
	part.Anchored = true
	part.Size = size
	part.Position = position
	part.Color = color or FLOOR_COLOR
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	--

	return part
end

local function get_character_root(): BasePart?
	--
	for _, player in Players:GetPlayers() do
		const character = player.Character

		if not character then
			continue
		end

		const root = character:FindFirstChild("HumanoidRootPart")

		if not root or not root:IsA("BasePart") then
			continue
		end

		return root
	end
	--

	return nil
end

local function prepare_viewpoint()
	--
	local root: BasePart? = nil

	wait_until(function()
		root = get_character_root()
		return root ~= nil
	end, VIEWER_WAIT)
	--

	--
	const spawn_location = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	const anchor = if root then root.Position elseif spawn_location then spawn_location.Position else Vector3.zero

	ArenaOrigin = anchor + ARENA_OFFSET
	--

	--
	const viewpoint = ArenaOrigin + VIEWPOINT_OFFSET
	const platform = make_part(workspace, Vector3.new(12, 1, 12), viewpoint, BRIDGE_COLOR)
	platform.Name = "PathfindSmokeViewpoint"
	platform.Transparency = 0.5

	if not root then
		return
	end
	--

	--
	const character = root.Parent :: Model
	const eye = viewpoint + Vector3.new(0, 4, 0)
	const focus = Vector3.new(ArenaOrigin.X, eye.Y, ArenaOrigin.Z)

	root.AssemblyLinearVelocity = Vector3.zero
	character:PivotTo(CFrame.lookAt(eye, focus))
	--
end

local function create_lane(title: string): (Folder, Vector3)
	--
	const folder = Instance.new("Folder")
	folder.Name = `PathfindSmoke {title}`
	folder.Parent = workspace
	--

	--
	const marker = make_part(folder, Vector3.one, ArenaOrigin + Vector3.new(0, 16, 0))
	marker.Transparency = 1
	marker.CanCollide = false
	marker.CanQuery = false

	const billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(420, 60)
	billboard.AlwaysOnTop = true
	billboard.Parent = marker

	const label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Text = title
	label.Parent = billboard
	--

	print(`[PathfindSmoke] running: {title}`)

	return folder, ArenaOrigin
end

local function close_lane(folder: Folder)
	--
	task.wait(LANE_LINGER)
	folder:Destroy()
	--

	task.wait(NAVMESH_SETTLE)
end

local function spawn_agent(folder: Folder, position: Vector3): Agent?
	--
	const ok, rig = pcall(function()
		return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	end)

	if not ok then
		check("rig spawns", false, tostring(rig))
		return nil
	end
	--

	--
	rig:PivotTo(CFrame.new(position + Vector3.new(0, 4, 0)))
	rig.Parent = folder

	const humanoid = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
	const pathfind = Pathfind.new({ Entity = rig, Humanoid = humanoid, Config = { VISUALISE = true } :: any })
	--

	--
	const agent: Agent = {
		Rig = rig,
		Pathfind = pathfind,
		Arrived = 0,
		Stuck = 0,
		Failed = {},
		WaypointCounts = {},
		JumpWaypoints = 0,
	}

	pathfind.OnArrived:Connect(function()
		agent.Arrived += 1
	end)

	pathfind.OnStuck:Connect(function()
		agent.Stuck += 1
	end)

	pathfind.OnPathFailed:Connect(function(reason)
		table.insert(agent.Failed, reason)
	end)

	pathfind.OnPathCalculated:Connect(function(waypoints)
		table.insert(agent.WaypointCounts, #waypoints)

		for _, waypoint in waypoints do
			if waypoint.Action ~= Enum.PathWaypointAction.Jump then
				continue
			end

			agent.JumpWaypoints += 1
		end
	end)
	--

	task.wait(0.5)

	return agent
end

local function run_direct_path()
	--
	const folder, origin = create_lane("Direct path")
	make_part(folder, FLOOR_SIZE, origin)

	const agent = spawn_agent(folder, origin + Vector3.new(-20, 0, 0))

	if not agent then
		folder:Destroy()
		return
	end
	--

	--
	const outcome = await_outcome(agent.Pathfind:GotoAsync(origin + Vector3.new(20, 0.5, 0)), 10)
	--

	--
	check("direct: GotoAsync resolves on arrival", outcome == "Resolved", outcome)
	check("direct: OnArrived fires", agent.Arrived == 1, `arrived = {agent.Arrived}`)
	check("direct: skips PathfindingService", agent.WaypointCounts[1] == 1, `waypoints = {agent.WaypointCounts[1]}`)

	close_lane(folder)
	--
end

local function run_detour()
	--
	const folder, origin = create_lane("Detour around a wall")
	make_part(folder, FLOOR_SIZE, origin)
	make_part(folder, Vector3.new(2, 12, 40), origin + Vector3.new(0, 6.5, 0), OBSTACLE_COLOR)

	const agent = spawn_agent(folder, origin + Vector3.new(-20, 0, 0))

	if not agent then
		folder:Destroy()
		return
	end
	--

	--
	agent.Pathfind:Goto(origin + Vector3.new(20, 0.5, 0))

	const arrived = wait_until(function()
		return agent.Arrived > 0
	end, 20)
	--

	--
	check("detour: arrives around a wall", arrived, `failed = {table.concat(agent.Failed, ", ")}`)
	check("detour: uses a computed path", (agent.WaypointCounts[1] or 0) > 1, `waypoints = {agent.WaypointCounts[1]}`)

	close_lane(folder)
	--
end

local function track_lowest_point(rig: Model): () -> number
	--
	local lowest = math.huge

	const connection = RunService.Heartbeat:Connect(function()
		lowest = math.min(lowest, rig:GetPivot().Position.Y)
	end)
	--

	return function()
		connection:Disconnect()
		return lowest
	end
end

local function build_split_floor(folder: Folder, origin: Vector3, gap: number)
	--
	const half_width = (FLOOR_SIZE.X - gap) / 2
	const half_size = Vector3.new(half_width, FLOOR_SIZE.Y, FLOOR_SIZE.Z)
	const offset = gap / 2 + half_width / 2
	--

	--
	make_part(folder, half_size, origin + Vector3.new(-offset, 0, 0))
	make_part(folder, half_size, origin + Vector3.new(offset, 0, 0))
	--
end

local function run_pit()
	--
	const folder, origin = create_lane("Pit with a bridge")
	build_split_floor(folder, origin, PIT_WIDTH)
	make_part(folder, Vector3.new(PIT_WIDTH + 4, 1, 8), origin + Vector3.new(0, 0, 25), BRIDGE_COLOR)

	const agent = spawn_agent(folder, origin + Vector3.new(-14, 0, 0))

	if not agent then
		folder:Destroy()
		return
	end
	--

	--
	const stop_tracking = track_lowest_point(agent.Rig)
	const outcome = await_outcome(agent.Pathfind:GotoAsync(origin + Vector3.new(14, 0.5, 0)), 20)
	const lowest = stop_tracking()
	--

	--
	check("pit: arrives over the bridge", outcome == "Resolved", outcome)
	check(
		"pit: direct path refuses the gap",
		(agent.WaypointCounts[1] or 0) > 1,
		`waypoints = {agent.WaypointCounts[1]}`
	)
	check("pit: the agent never falls in", lowest > origin.Y, `lowest = {math.round(lowest - origin.Y)} studs`)

	close_lane(folder)
	--
end

local function run_jump_gap()
	--
	const folder, origin = create_lane("Jump across a gap")
	build_split_floor(folder, origin, JUMP_GAP_WIDTH)

	const agent = spawn_agent(folder, origin + Vector3.new(-14, 0, 0))

	if not agent then
		folder:Destroy()
		return
	end
	--

	--
	const stop_tracking = track_lowest_point(agent.Rig)
	const outcome = await_outcome(agent.Pathfind:GotoAsync(origin + Vector3.new(14, 0.5, 0)), 20)
	const lowest = stop_tracking()
	--

	--
	check("jump: arrives across the gap", outcome == "Resolved", outcome)
	check("jump: the path contains a jump", agent.JumpWaypoints > 0, `jumps = {agent.JumpWaypoints}`)
	check("jump: the agent never falls in", lowest > origin.Y, `lowest = {math.round(lowest - origin.Y)} studs`)

	close_lane(folder)
	--
end

local function run_stop()
	--
	const folder, origin = create_lane("Stop mid-path")
	make_part(folder, FLOOR_SIZE, origin)

	const agent = spawn_agent(folder, origin + Vector3.new(-40, 0, 0))

	if not agent then
		folder:Destroy()
		return
	end
	--

	--
	const request = agent.Pathfind:GotoAsync(origin + Vector3.new(40, 0.5, 0))
	task.wait(1)
	agent.Pathfind:Stop()

	const stopped_at = agent.Rig:GetPivot().Position
	task.wait(1.5)
	const drift = (agent.Rig:GetPivot().Position - stopped_at).Magnitude
	--

	--
	check("stop: GotoAsync is cancelled, not rejected", await_outcome(request, 1) == "Cancelled")
	check("stop: IsMoving is false", not agent.Pathfind.IsMoving)
	check("stop: rig stays put", drift < 4, `drifted {math.round(drift * 10) / 10} studs`)
	check("stop: no arrival reported", agent.Arrived == 0)

	close_lane(folder)
	--
end

local function run_chase_target_destroyed()
	--
	const folder, origin = create_lane("Chase a destroyed target")
	make_part(folder, FLOOR_SIZE, origin)

	const target = make_part(folder, Vector3.new(2, 2, 2), origin + Vector3.new(20, 1.5, 0), TARGET_COLOR)
	target.CanCollide = false

	const agent = spawn_agent(folder, origin + Vector3.new(-20, 0, 0))

	if not agent then
		folder:Destroy()
		return
	end
	--

	--
	const mover = RunService.Heartbeat:Connect(function()
		if not target.Parent then
			return
		end

		target.Position = origin + Vector3.new(20, 1.5, math.sin(os.clock()) * 15)
	end)

	agent.Pathfind:Chase(target, 3)
	task.wait(2)
	target:Destroy()

	const released = wait_until(function()
		return agent.Pathfind.ChaseTarget == nil and not agent.Pathfind.IsMoving
	end, 2)

	mover:Disconnect()
	--

	--
	check("chase: stops when the target is destroyed", released)

	close_lane(folder)
	--
end

local function run_stuck()
	--
	const folder, origin = create_lane("Stuck behind a pass-through wall")
	make_part(folder, FLOOR_SIZE, origin)

	const wall = make_part(folder, Vector3.new(2, 14, 60), origin + Vector3.new(0, 7.5, 0), OBSTACLE_COLOR)
	const modifier = Instance.new("PathfindingModifier")
	modifier.PassThrough = true
	modifier.Parent = wall

	const agent = spawn_agent(folder, origin + Vector3.new(-15, 0, 0))

	if not agent then
		folder:Destroy()
		return
	end
	--

	--
	const outcome = await_outcome(agent.Pathfind:GotoAsync(origin + Vector3.new(15, 0.5, 0)), 15)
	--

	--
	check("stuck: GotoAsync rejects with Stuck", outcome == "Stuck", outcome)
	check("stuck: OnStuck fires behind a pass-through wall", agent.Stuck == 1, `stuck = {agent.Stuck}`)
	check("stuck: agent halts after giving up", not agent.Pathfind.IsMoving)

	close_lane(folder)
	--
end

local function run_supersede_and_cancel()
	--
	const folder, origin = create_lane("Supersede and cancel")
	make_part(folder, FLOOR_SIZE, origin)

	const agent = spawn_agent(folder, origin + Vector3.new(-40, 0, 0))

	if not agent then
		folder:Destroy()
		return
	end
	--

	--
	const first = agent.Pathfind:GotoAsync(origin + Vector3.new(40, 0.5, 0))
	const second = agent.Pathfind:GotoAsync(origin + Vector3.new(40, 0.5, 20))
	task.wait(1)
	second:cancel()
	task.wait(0.5)
	--

	--
	check("supersede: the first request is cancelled", await_outcome(first, 1) == "Cancelled")
	check("cancel: cancelling GotoAsync stops the agent", not agent.Pathfind.IsMoving)
	check("cancel: no arrival reported", agent.Arrived == 0)

	close_lane(folder)
	--
end

local function run_link_handler()
	--
	const folder, origin = create_lane("PathfindingLink teleport")
	const platform_size = Vector3.new(30, 1, 30)
	const start_platform = make_part(folder, platform_size, origin + Vector3.new(-25, 0, 0))
	const end_platform = make_part(folder, platform_size, origin + Vector3.new(25, 0, 0))

	const start_attachment = Instance.new("Attachment")
	start_attachment.Position = Vector3.new(13, 0.5, 0)
	start_attachment.Parent = start_platform

	const end_attachment = Instance.new("Attachment")
	end_attachment.Position = Vector3.new(-13, 0.5, 0)
	end_attachment.Parent = end_platform

	const link = Instance.new("PathfindingLink")
	link.Attachment0 = start_attachment
	link.Attachment1 = end_attachment
	link.Label = "Teleport"
	link.Parent = folder

	const agent = spawn_agent(folder, origin + Vector3.new(-30, 0, 0))

	if not agent then
		folder:Destroy()
		return
	end
	--

	--
	local traversals = 0

	agent.Pathfind:SetLinkHandler("Teleport", function(_pathfind, _from, to)
		traversals += 1
		agent.Rig:PivotTo(CFrame.new(to.Position + Vector3.new(0, 4, 0)))
		task.wait(0.2)
	end)

	const outcome = await_outcome(agent.Pathfind:GotoAsync(origin + Vector3.new(30, 0.5, 0)), 20)
	--

	--
	check("link: GotoAsync resolves across a PathfindingLink", outcome == "Resolved", outcome)
	check("link: the Teleport handler runs once", traversals == 1, `traversals = {traversals}`)

	close_lane(folder)
	--
end

local function run_moving_obstacle()
	--
	const folder, origin = create_lane("Moving obstacle patrol")
	make_part(folder, FLOOR_SIZE, origin)

	const wall = make_part(folder, Vector3.new(4, 10, 20), origin + Vector3.new(0, 5.5, 0), OBSTACLE_COLOR)

	const agent = spawn_agent(folder, origin + Vector3.new(-30, 0, 0))

	if not agent then
		folder:Destroy()
		return
	end
	--

	--
	const sweeper = RunService.Heartbeat:Connect(function()
		const phase = os.clock() * 2 * math.pi / SWEEP_PERIOD
		wall.Position = origin + Vector3.new(0, 5.5, math.sin(phase) * SWEEP_AMPLITUDE)
	end)

	const outcomes: { string } = {}
	local completed = 0

	for _ = 1, PATROL_LAPS do
		for _, x in { 30, -30 } do
			const outcome = await_outcome(agent.Pathfind:GotoAsync(origin + Vector3.new(x, 0.5, 0)), 20)
			table.insert(outcomes, outcome)

			if outcome ~= "Resolved" then
				continue
			end

			completed += 1
		end
	end

	sweeper:Disconnect()
	--

	--
	const legs = PATROL_LAPS * 2

	check(
		"moving obstacle: every patrol leg arrives",
		completed == legs,
		`{completed}/{legs} legs, outcomes = {table.concat(outcomes, ", ")}`
	)
	check("moving obstacle: the agent never gives up", agent.Stuck == 0, `stuck = {agent.Stuck}`)

	print(`[PathfindSmoke] moving obstacle: {#agent.WaypointCounts} paths planned over {legs} legs`)

	close_lane(folder)
	--
end

local function run_compute_budget()
	--
	const folder, origin = create_lane("Compute budget (8 agents)")
	make_part(folder, Vector3.new(100, 1, 110), origin)
	make_part(folder, Vector3.new(2, 12, 90), origin + Vector3.new(0, 6.5, 0), OBSTACLE_COLOR)

	Config.Configure({ PATHFIND = { MAX_COMPUTES_PER_FRAME = 1, MAX_CONCURRENT_COMPUTES = 2 } })

	const agents: { Agent } = {}

	for index = 1, 8 do
		const agent = spawn_agent(folder, origin + Vector3.new(-25, 0, index * 8 - 36))

		if not agent then
			continue
		end

		table.insert(agents, agent)
	end
	--

	--
	local peak_in_flight = 0

	const sampler = RunService.Heartbeat:Connect(function()
		peak_in_flight = math.max(peak_in_flight, Pathfind.GetStats().InFlight)
	end)

	for index, agent in agents do
		agent.Pathfind:Goto(origin + Vector3.new(25, 0.5, index * 8 - 36))
	end

	const all_arrived = wait_until(function()
		for _, agent in agents do
			if agent.Arrived == 0 then
				return false
			end
		end

		return true
	end, 40)

	sampler:Disconnect()
	Config.Configure({})
	--

	--
	check("budget: all agents spawned", #agents == 8, `spawned {#agents}`)
	check("budget: in-flight computes stay within the cap", peak_in_flight <= 2, `peak {peak_in_flight}`)
	check("budget: every agent arrives", all_arrived)

	close_lane(folder)
	--
end

function PathfindSmoke.Start()
	--
	if not RunService:IsServer() then
		return
	end
	--

	--
	prepare_viewpoint()
	--

	--
	run_direct_path()
	run_detour()
	run_pit()
	run_jump_gap()
	run_stop()
	run_chase_target_destroyed()
	run_stuck()
	run_supersede_and_cancel()
	run_link_handler()
	run_moving_obstacle()
	run_compute_budget()
	--

	--
	if Failures > 0 then
		warn(`[PathfindSmoke] {Failures} of {Checks} checks FAILED`)
		return
	end
	--

	print(`[PathfindSmoke] all {Checks} checks passed`)
end

return PathfindSmoke
