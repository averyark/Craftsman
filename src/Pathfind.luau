--!strict
--[[
    FileName    > Pathfind.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 12/06/2026
--]]

const PathfindingService = game:GetService("PathfindingService")
const RunService = game:GetService("RunService")

const Keeper = require("../packages/roblox/Keeper")
const Promise = require("../packages/roblox/Promise")
const Signal = require("../packages/roblox/Signal")
const Config = require("./Config")
const TableUtil = require("./Utilities/TableUtil")

local PathfindModule = {}

--
export type PathfindConfig = {
	RECALCULATE_THROTTLE: number,
	RECALCULATE_DISTANCE_THRESHOLD: number,
	IDLE_RECALCULATE_INTERVAL: number?,

	AGENT_RADIUS: number,
	AGENT_HEIGHT: number,
	AGENT_CAN_JUMP: boolean,

	AGENT_COSTS: { [string]: number },

	WAYPOINT_SPACING: number,
	WAYPOINT_ARRIVAL_RADIUS: number,
	WAYPOINT_ADVANCE_RADIUS: number,
	STUCK_TIMEOUT: number,
	STUCK_RETRIES: number?,
	STALL_TIMEOUT: number,
	PARTIAL_PATH: boolean,

	DIRECT_PATH: boolean?,
	DIRECT_PATH_MAX_DISTANCE: number?,
	DIRECT_PATH_MAX_STEP: number?,

	VISUALISE: boolean,
}

export type PathResult = {
	Status: Enum.PathStatus,
	Waypoints: { PathWaypoint },
}

export type PathfindStats = {
	Agents: number,
	Queued: number,
	InFlight: number,
}

type ConfigMap = { [string]: any }

type ChaseRequest = "None" | "Direct" | "Full"

type PendingRequest = {
	Resolve: () -> (),
	Reject: (reason: string) -> (),
	Cancel: () -> (),
}

type LinkHandlerFunction = (pathfind: any, from: PathWaypoint, to: PathWaypoint) -> ()
--

--
const FALLBACK_CONFIG: PathfindConfig = {
	RECALCULATE_THROTTLE = 0.2,
	RECALCULATE_DISTANCE_THRESHOLD = 4,
	IDLE_RECALCULATE_INTERVAL = 1,

	AGENT_RADIUS = 2,
	AGENT_HEIGHT = 5,
	AGENT_CAN_JUMP = true,

	AGENT_COSTS = {},

	WAYPOINT_SPACING = 4,
	WAYPOINT_ARRIVAL_RADIUS = 1.5,
	WAYPOINT_ADVANCE_RADIUS = 2.8,
	STUCK_TIMEOUT = 2,
	STUCK_RETRIES = 2,
	STALL_TIMEOUT = 2,
	PARTIAL_PATH = true,

	DIRECT_PATH = true,
	DIRECT_PATH_MAX_DISTANCE = 40,
	DIRECT_PATH_MAX_STEP = 2,

	VISUALISE = false,
}
--

--
local VisualisationFolder: Instance? = nil

const VisualisationBallPart = Instance.new("Part")
VisualisationBallPart.Name = "CFVisualisationBall"
VisualisationBallPart.Shape = Enum.PartType.Ball
VisualisationBallPart.Size = Vector3.new(0.35, 0.35, 0.35)
VisualisationBallPart.Material = Enum.Material.Neon
VisualisationBallPart.Anchored = true
VisualisationBallPart.CanCollide = false
VisualisationBallPart.CanTouch = false
VisualisationBallPart.CanQuery = false
VisualisationBallPart.CastShadow = false

const VisualisationBillboard = Instance.new("BillboardGui")
VisualisationBillboard.Name = "CFVisualisationBillboard"
VisualisationBillboard.Size = UDim2.new(0, 180, 0, 50)
VisualisationBillboard.StudsOffset = Vector3.new(0, 0.6, 0)
VisualisationBillboard.AlwaysOnTop = true
VisualisationBillboard.ResetOnSpawn = false

const VisualisationLabel = Instance.new("TextLabel")
VisualisationLabel.Size = UDim2.new(1, 0, 1, 0)
VisualisationLabel.BackgroundTransparency = 1
VisualisationLabel.Font = Enum.Font.GothamBold
VisualisationLabel.TextSize = 13
VisualisationLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
VisualisationLabel.TextStrokeTransparency = 0.4
VisualisationLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
VisualisationLabel.Parent = VisualisationBillboard

const VisualisationLine = Instance.new("Part")
VisualisationLine.Name = "PathLine"
VisualisationLine.Shape = Enum.PartType.Cylinder
VisualisationLine.Material = Enum.Material.Neon
VisualisationLine.Color = Color3.fromRGB(255, 255, 255)
VisualisationLine.Anchored = true
VisualisationLine.CanCollide = false
VisualisationLine.CanTouch = false
VisualisationLine.CanQuery = false
VisualisationLine.CastShadow = false
--

--
PathfindModule.Movers = {
	Humanoid = function(humanoid: Humanoid)
		if not humanoid or not humanoid:IsA("Humanoid") then
			error("Invalid humanoid provided to PathfindModule.Movers.Humanoid")
		end

		return function(destination: Vector3)
			humanoid:MoveTo(destination)
		end
	end,
}
--

--
const Pathfind = {}
Pathfind.__index = Pathfind
--

--
type PathfindFields = {
	Entity: Model | BasePart,
	Humanoid: Humanoid?,
	Mover: (Vector3) -> (),
	Config: PathfindConfig,
	Keeper: Keeper.Keeper,
	PathLogicKeeper: Keeper.Keeper,
	Path: Path,
	RayParams: RaycastParams,

	IsModel: boolean,
	Waypoints: { PathWaypoint },
	TargetPosition: Vector3,
	LastPathComputeTime: number,
	LastAdvanceTime: number,
	LastMovingTime: number,
	LastRecordedPosition: Vector3,
	PendingRecalculate: boolean,
	Queued: boolean,
	Computing: boolean,
	PathComputeToken: number?,
	CurrentWaypointIndex: number,
	StuckCount: number,
	ChaseTarget: (BasePart | Model)?,
	LastChasePosition: Vector3?,
	StoppingDistance: number?,
	ChaseElapsed: number,
	ActiveRequest: PendingRequest?,
	LinkHandlers: { [string]: LinkHandlerFunction },

	IsMoving: boolean,
	Traversing: boolean,
	DirectPath: boolean,
	LastDirectCheck: number,
	Destroyed: boolean,

	VisualisationNodes: { [number]: Part },
	StaleVisualisationNodes: { Part },
	VisitedNodePositions: { [string]: boolean },
	EntityVisualisationBillboard: BillboardGui?,
	EntityVisualisationLabel: TextLabel?,

	OnPathCalculated: Signal.Signal<{ PathWaypoint }>,
	OnPathEnded: Signal.Signal<()>,
	OnArrived: Signal.Signal<()>,
	OnStuck: Signal.Signal<()>,
	OnPathFailed: Signal.Signal<string>,
}
--

--
const Agents: { [any]: boolean } = {}
const JoiningAgents: { any } = {}
const ComputeQueue: { any } = {}

local InFlightComputes = 0
local SchedulerConnection: RBXScriptConnection? = nil

const SharedLinkHandlers: { [string]: LinkHandlerFunction } = {}
--

local function normalise_config(config: PathfindConfig?): ConfigMap
	--
	const defaults = TableUtil.DeepClone(FALLBACK_CONFIG) :: ConfigMap

	if not config then
		return defaults
	end
	--

	--
	const normalised_config = {} :: ConfigMap

	for key, value in defaults do
		const override = (config :: ConfigMap)[key]
		normalised_config[key] = if override ~= nil then override else value
	end
	--

	return normalised_config
end

local function get_visualisation_folder(): Instance
	--
	if VisualisationFolder then
		return VisualisationFolder
	end
	--

	--
	const folder = workspace:FindFirstChild("PathVisualisation") or Instance.new("Folder")
	folder.Name = "PathVisualisation"
	folder.Parent = workspace

	VisualisationFolder = folder
	--

	return folder
end

local function release_network_owner(instance: Instance?)
	--
	if not instance or not instance:IsA("BasePart") or instance.Anchored then
		return
	end
	--

	pcall(instance.SetNetworkOwner, instance, nil)
end

local function release_entity_network_ownership(entity: Model | BasePart)
	--
	const released: { [BasePart]: boolean } = {}
	const parts = entity:GetDescendants()

	table.insert(parts, entity)
	--

	--
	for _, part in parts do
		if not part:IsA("BasePart") then
			continue
		end

		const assembly_root = part.AssemblyRootPart or part

		if released[assembly_root] then
			continue
		end

		released[assembly_root] = true
		release_network_owner(assembly_root)
	end
	--
end

local function create_ray_params(entity: Instance): RaycastParams
	--
	const params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { entity }
	params.RespectCanCollide = true
	params.IgnoreWater = true
	--

	return params
end

local function attach_visualisation(pathfind: PathfindFields)
	--
	if not pathfind.Config.VISUALISE then
		return
	end
	--

	--
	const billboard = pathfind.Keeper:Add(VisualisationBillboard:Clone())
	pathfind.EntityVisualisationBillboard = billboard
	pathfind.EntityVisualisationLabel = billboard:FindFirstChildOfClass("TextLabel")
	billboard.Adornee = pathfind.Entity
	billboard.Parent = get_visualisation_folder()
	--
end

local function take_request(agent: PathfindFields): PendingRequest?
	--
	const request = agent.ActiveRequest
	agent.ActiveRequest = nil
	--

	return request
end

local function resolve_request(agent: PathfindFields)
	--
	const request = take_request(agent)

	if not request then
		return
	end
	--

	request.Resolve()
end

local function reject_request(agent: PathfindFields, reason: string)
	--
	const request = take_request(agent)

	if not request then
		return
	end
	--

	request.Reject(reason)
end

local function cancel_request(agent: PathfindFields)
	--
	const request = take_request(agent)

	if not request then
		return
	end
	--

	request.Cancel()
end

local function unregister_agent(agent: PathfindFields)
	--
	agent.Destroyed = true
	agent.Queued = false
	agent.PendingRecalculate = false

	Agents[agent] = nil
	--

	cancel_request(agent)
end

local function new(param: {
	Entity: Model | BasePart,
	Humanoid: Humanoid?,

	Mover: ((Vector3) -> ())?,

	Config: PathfindConfig?,
})
	--
	const mover = param.Mover or if param.Humanoid then PathfindModule.Movers.Humanoid(param.Humanoid) else nil

	if not mover then
		error("Pathfind.new requires a Mover or a Humanoid", 2)
	end
	--

	--
	const self = setmetatable({} :: PathfindFields, Pathfind)

	self.Entity = param.Entity
	self.Humanoid = param.Humanoid
	self.Mover = mover
	--

	--
	self.Config = normalise_config(param.Config) :: PathfindConfig
	--

	--
	self.Keeper = Keeper.new()
	self.Keeper:AttachToInstance(self.Entity)

	self.PathLogicKeeper = self.Keeper:Extend()

	self.Keeper:Add(function()
		unregister_agent(self)
		self:_ClearVisualisationNodes()
	end)
	--

	--
	self.Path = PathfindingService:CreatePath({
		AgentRadius = self.Config.AGENT_RADIUS,
		AgentHeight = self.Config.AGENT_HEIGHT,
		AgentCanJump = self.Config.AGENT_CAN_JUMP,
		Costs = self.Config.AGENT_COSTS,

		WaypointSpacing = self.Config.WAYPOINT_SPACING,

		PathSettings = {
			SupportPartialPath = self.Config.PARTIAL_PATH,
		},
	})

	self.RayParams = create_ray_params(self.Entity)
	--

	--
	self.IsModel = self.Entity:IsA("Model")
	self.Waypoints = {} :: typeof(self.Path:GetWaypoints())
	self.TargetPosition = self:GetCurrentPosition()
	self.LastPathComputeTime = 0
	self.LastAdvanceTime = os.clock()
	self.LastMovingTime = os.clock()
	self.LastRecordedPosition = self.TargetPosition
	self.PendingRecalculate = false
	self.Queued = false
	self.Computing = false
	self.CurrentWaypointIndex = 1
	self.StuckCount = 0
	self.ChaseTarget = nil :: (BasePart | Model)?
	self.LastChasePosition = nil :: Vector3?
	self.StoppingDistance = nil :: number?
	self.ChaseElapsed = 0
	self.ActiveRequest = nil :: PendingRequest?
	self.LinkHandlers = {}

	self.IsMoving = false
	self.Traversing = false
	self.DirectPath = false
	self.LastDirectCheck = 0
	self.Destroyed = false

	self.VisualisationNodes = {}
	self.StaleVisualisationNodes = {}
	self.VisitedNodePositions = {}
	--

	--
	if RunService:IsServer() then
		release_entity_network_ownership(self.Entity)
	end
	--

	--
	attach_visualisation(self)
	--

	--
	self.OnPathCalculated = self.Keeper:Construct(Signal.new)
	self.OnPathEnded = self.Keeper:Construct(Signal.new)
	self.OnArrived = self.Keeper:Construct(Signal.new)
	self.OnStuck = self.Keeper:Construct(Signal.new)
	self.OnPathFailed = self.Keeper:Construct(Signal.new)
	--

	--
	self:ConnectPathLogic()
	--

	return self
end

--
export type Pathfind = typeof(new(...))

export type LinkHandler = (pathfind: Pathfind, from: PathWaypoint, to: PathWaypoint) -> ()
--

function Pathfind._ClearVisualisationNodes(self: Pathfind)
	--
	if not self.Config.VISUALISE then
		return
	end
	--

	--
	if self.VisualisationNodes then
		for _, node in self.VisualisationNodes do
			node:Destroy()
		end

		self.VisualisationNodes = {}
	end

	if self.StaleVisualisationNodes then
		for _, node in self.StaleVisualisationNodes do
			node:Destroy()
		end

		self.StaleVisualisationNodes = {}
	end
	--

	self.VisitedNodePositions = {}
end

function Pathfind.GetRoot(self: Pathfind): BasePart?
	--
	if not self.IsModel then
		return self.Entity :: BasePart
	end
	--

	return self.Entity.PrimaryPart or self.Entity:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function Pathfind.GetCurrentPosition(self: Pathfind): Vector3
	--
	if not self.IsModel then
		return self.Entity.Position
	end
	--

	return self.Entity.PrimaryPart and self.Entity.PrimaryPart.CFrame.Position or self.Entity:GetPivot().Position
end

local function position_key(position: Vector3): string
	--
	const x = math.round(position.X * 10) / 10
	const y = math.round(position.Y * 10) / 10
	const z = math.round(position.Z * 10) / 10
	--

	return `{x},{y},{z}`
end

local function mark_visited(visited_positions: { [string]: boolean }, waypoint: PathWaypoint?)
	--
	if not waypoint then
		return
	end
	--

	--
	visited_positions[position_key(waypoint.Position)] = true
	--
end

local function set_ray_filter(pathfind: Pathfind, target: Instance?)
	pathfind.RayParams.FilterDescendantsInstances = if target then { pathfind.Entity, target } else { pathfind.Entity }
end

local function get_arrival_threshold(pathfind: Pathfind): number
	return math.max(pathfind.Config.WAYPOINT_ARRIVAL_RADIUS, pathfind.Config.AGENT_RADIUS)
end

local function reaches_target(pathfind: Pathfind, position: Vector3): boolean
	--
	const offset = position - pathfind.TargetPosition
	--

	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= get_arrival_threshold(pathfind)
end

local function fail_request(pathfind: Pathfind, reason: string)
	--
	pathfind.OnPathFailed:Fire(reason)
	--

	--
	if pathfind.IsMoving then
		return
	end
	--

	reject_request(pathfind, reason)
end

local function finish_path(pathfind: Pathfind)
	--
	const final_waypoint = pathfind.Waypoints[#pathfind.Waypoints]
	pathfind.IsMoving = false
	--

	--
	pathfind.OnPathEnded:Fire()
	--

	--
	if not final_waypoint or not reaches_target(pathfind, final_waypoint.Position) then
		fail_request(pathfind, "Unreachable")
		return
	end
	--

	--
	pathfind.OnArrived:Fire()
	--

	resolve_request(pathfind)
end

local function halt(pathfind: Pathfind)
	--
	const current_position = pathfind:GetCurrentPosition()

	pathfind.IsMoving = false
	pathfind.DirectPath = false
	pathfind.Waypoints = {}
	pathfind.CurrentWaypointIndex = 1
	pathfind.PendingRecalculate = false
	pathfind.Queued = false
	pathfind.LastAdvanceTime = os.clock()
	pathfind.LastMovingTime = os.clock()
	pathfind.LastRecordedPosition = current_position
	pathfind.PathComputeToken = (pathfind.PathComputeToken or 0) + 1
	--

	--
	pathfind.OnPathEnded:Fire()

	pathfind.Mover(current_position)
	--
end

local function get_link_handler(pathfind: Pathfind, waypoint: PathWaypoint?): LinkHandlerFunction?
	--
	if not waypoint or waypoint.Action ~= Enum.PathWaypointAction.Custom then
		return nil
	end
	--

	return pathfind.LinkHandlers[waypoint.Label] or SharedLinkHandlers[waypoint.Label]
end

local function traverse_link(pathfind: Pathfind, handler: LinkHandlerFunction, from: PathWaypoint, to: PathWaypoint)
	--
	const token = pathfind.PathComputeToken
	pathfind.Traversing = true
	--

	task.spawn(function()
		--
		local failure: string? = nil

		xpcall(handler, function(err)
			failure = debug.traceback(tostring(err), 2)
		end, pathfind, from, to)

		pathfind.Traversing = false

		if pathfind.Destroyed or pathfind.PathComputeToken ~= token then
			return
		end
		--

		--
		if failure then
			task.spawn(error, failure, 0)
			halt(pathfind)
			fail_request(pathfind, `Link:{from.Label}`)
			return
		end
		--

		--
		pathfind.CurrentWaypointIndex += 1
		pathfind.StuckCount = 0
		pathfind.LastMovingTime = os.clock()
		pathfind.LastRecordedPosition = pathfind:GetCurrentPosition()
		--

		pathfind:_ExecuteWaypoint()
	end)
end

function Pathfind._ExecuteWaypoint(self: Pathfind): boolean
	--
	const reached = self.Waypoints[self.CurrentWaypointIndex - 1]

	if self.Config.VISUALISE then
		mark_visited(self.VisitedNodePositions, reached)
	end
	--

	--
	const waypoint = self.Waypoints[self.CurrentWaypointIndex]

	if not waypoint then
		finish_path(self)
		return false
	end
	--

	--
	const link_handler = get_link_handler(self, reached)

	if link_handler then
		traverse_link(self, link_handler, reached, waypoint)
		return true
	end
	--

	--
	if waypoint.Action == Enum.PathWaypointAction.Jump and self.Humanoid then
		self.Humanoid.Jump = true
	end
	--

	--
	self.LastAdvanceTime = os.clock()
	self.LastMovingTime = os.clock()
	self.LastRecordedPosition = self:GetCurrentPosition()
	self.Mover(waypoint.Position)
	self.CurrentWaypointIndex += 1
	--

	return true
end

local function advance(pathfind: Pathfind): boolean
	--
	pathfind.StuckCount = 0
	--

	return pathfind:_ExecuteWaypoint()
end

local function recover_from_stuck(pathfind: Pathfind, current_position: Vector3)
	--
	pathfind.StuckCount += 1
	pathfind.LastMovingTime = os.clock()
	pathfind.LastAdvanceTime = os.clock()
	pathfind.LastRecordedPosition = current_position
	--

	--
	if pathfind.StuckCount > (pathfind.Config.STUCK_RETRIES :: number) then
		pathfind.StuckCount = 0
		halt(pathfind)
		pathfind.OnStuck:Fire()
		reject_request(pathfind, "Stuck")
		return
	end
	--

	--
	if pathfind.Humanoid then
		pathfind.Humanoid.Jump = true
	end
	--

	pathfind:RecalculatePath()
end

function Pathfind.ComputePathToAsync(self: Pathfind, target_position: Vector3): Promise.TypedPromise<PathResult>
	return Promise.new(function(resolve)
		--
		const current_position = self:GetCurrentPosition()

		self.Path:ComputeAsync(current_position, target_position)
		--

		resolve({ Status = self.Path.Status, Waypoints = self.Path:GetWaypoints() })
	end)
end

function Pathfind._UpdateVisualisation(self: Pathfind)
	--
	if not self.Config.VISUALISE then
		return
	end
	--

	--
	const new_nodes: { [number]: Part } = {}
	const folder = get_visualisation_folder()

	local function was_visited(node: Part): boolean
		return self.VisitedNodePositions[position_key(node.Position)] == true
	end

	local function apply_blocked_color(node: Part)
		if was_visited(node) then
			return
		end

		node.Color = Color3.fromRGB(255, 0, 0)

		const line = node:FindFirstChild("PathLine") :: Part?

		if not line then
			return
		end

		line.Color = Color3.fromRGB(255, 0, 0)
	end
	--

	for i, wp in self.Waypoints do
		--
		const old_node = self.VisualisationNodes[i]
		local is_different = true

		if old_node and (old_node.Position - wp.Position).Magnitude < 0.1 then
			is_different = false
		end
		--

		--
		if old_node and is_different then
			apply_blocked_color(old_node)
			table.insert(self.StaleVisualisationNodes, old_node)
		end
		--

		--
		self.VisualisationNodes[i] = nil
		--

		--
		if old_node and not is_different then
			new_nodes[i] = old_node
			continue
		end
		--

		--
		const new_node = VisualisationBallPart:Clone()
		new_node.Position = wp.Position
		new_node.Parent = folder
		new_nodes[i] = new_node
		--

		--
		if i <= 1 then
			continue
		end
		--

		--
		const prev_wp = self.Waypoints[i - 1]
		const p1 = prev_wp.Position
		const p2 = wp.Position
		const dist = (p2 - p1).Magnitude

		const line = VisualisationLine:Clone()
		line.Size = Vector3.new(dist, 0.1, 0.1)
		line.CFrame = CFrame.lookAt(p1, p2) * CFrame.new(0, 0, -dist / 2) * CFrame.Angles(0, math.pi / 2, 0)
		line.Parent = new_node
		--
	end

	--
	for _, old_node in self.VisualisationNodes do
		apply_blocked_color(old_node)
		table.insert(self.StaleVisualisationNodes, old_node)
	end
	--

	self.VisualisationNodes = new_nodes
end

local function update_visualisation_label(pathfind: Pathfind)
	--
	const label = pathfind.EntityVisualisationLabel

	if not label then
		return
	end
	--

	--
	const target_name = pathfind.ChaseTarget and pathfind.ChaseTarget.Name or "None"
	const target_x = math.round(pathfind.TargetPosition.X * 100) / 100
	const target_y = math.round(pathfind.TargetPosition.Y * 100) / 100
	const target_z = math.round(pathfind.TargetPosition.Z * 100) / 100
	--

	label.Text =
		`ChaseTarget: {target_name}\nCurrentWayPointIndex: {pathfind.CurrentWaypointIndex}\nTargetPosition: {target_x}, {target_y}, {target_z}\nIsMoving: {pathfind.IsMoving}`
end

local function is_usable_result(pathfind: Pathfind, result: PathResult): boolean
	--
	if #result.Waypoints == 0 then
		return false
	end
	--

	return result.Status == Enum.PathStatus.Success or pathfind.Config.PARTIAL_PATH
end

local function apply_path_result(pathfind: Pathfind, result: PathResult, token: number, is_direct: boolean)
	--
	if pathfind.Destroyed or pathfind.PathComputeToken ~= token then
		return
	end

	if not is_usable_result(pathfind, result) then
		fail_request(pathfind, result.Status.Name)
		return
	end
	--

	--
	const current_pos = pathfind:GetCurrentPosition()
	const threshold = get_arrival_threshold(pathfind)

	pathfind.Waypoints = result.Waypoints
	pathfind.DirectPath = is_direct
	pathfind.LastDirectCheck = os.clock()
	pathfind.CurrentWaypointIndex = 1
	pathfind.LastAdvanceTime = os.clock()
	pathfind.LastMovingTime = os.clock()
	pathfind.LastRecordedPosition = current_pos
	--

	--
	while pathfind.CurrentWaypointIndex < #pathfind.Waypoints do
		const wp = pathfind.Waypoints[pathfind.CurrentWaypointIndex]
		const dist = Vector3.new(wp.Position.X - current_pos.X, 0, wp.Position.Z - current_pos.Z).Magnitude

		if dist > threshold then
			break
		end

		pathfind.CurrentWaypointIndex += 1
	end
	--

	--
	pathfind.OnPathCalculated:Fire(pathfind.Waypoints)

	pathfind:_UpdateVisualisation()
	--
end

local function probe_ground(pathfind: Pathfind, origin: Vector3, planar: Vector3): Vector3?
	--
	const config = pathfind.Config
	const distance = planar.Magnitude
	const direction = planar.Unit
	const spacing = math.max(config.AGENT_RADIUS, 1)
	const drop = Vector3.new(0, -config.AGENT_HEIGHT * 2, 0)
	const max_step = config.DIRECT_PATH_MAX_STEP :: number

	local previous_height: number? = nil
	local ground: Vector3? = nil
	--

	--
	for step = 0, math.ceil(distance / spacing) do
		const sample = origin + direction * math.min(step * spacing, distance)
		const hit = workspace:Raycast(sample, drop, pathfind.RayParams)

		if not hit then
			return nil
		end

		if previous_height and math.abs(hit.Position.Y - previous_height) > max_step then
			return nil
		end

		previous_height = hit.Position.Y
		ground = hit.Position
	end
	--

	return ground
end

local function is_line_blocked(pathfind: Pathfind, origin: Vector3, planar: Vector3): boolean
	return workspace:Spherecast(origin, pathfind.Config.AGENT_RADIUS * 0.75, planar, pathfind.RayParams) ~= nil
end

local function is_direct_line_blocked(pathfind: Pathfind): boolean
	--
	const clock = os.clock()

	if not pathfind.DirectPath or clock - pathfind.LastDirectCheck < pathfind.Config.RECALCULATE_THROTTLE then
		return false
	end

	pathfind.LastDirectCheck = clock
	--

	--
	const root = pathfind:GetRoot()
	const destination = pathfind.Waypoints[#pathfind.Waypoints]

	if not root or not destination then
		return false
	end
	--

	--
	const offset = destination.Position - root.Position
	const planar = Vector3.new(offset.X, 0, offset.Z)

	if planar.Magnitude <= pathfind.Config.AGENT_RADIUS then
		return false
	end
	--

	return is_line_blocked(pathfind, root.Position, planar)
end

local function try_direct_path(pathfind: Pathfind): PathResult?
	--
	const config = pathfind.Config

	if not config.DIRECT_PATH or next(config.AGENT_COSTS) ~= nil then
		return nil
	end

	const root = pathfind:GetRoot()

	if not root then
		return nil
	end
	--

	--
	const origin = root.Position
	const offset = pathfind.TargetPosition - origin
	const planar = Vector3.new(offset.X, 0, offset.Z)
	const distance = planar.Magnitude

	if distance < 0.1 or distance > (config.DIRECT_PATH_MAX_DISTANCE :: number) then
		return nil
	end

	if math.abs(offset.Y) > config.AGENT_HEIGHT then
		return nil
	end
	--

	--
	if is_line_blocked(pathfind, origin, planar) then
		return nil
	end

	const ground = probe_ground(pathfind, origin, planar)

	if not ground then
		return nil
	end
	--

	return {
		Status = Enum.PathStatus.Success,
		Waypoints = { PathWaypoint.new(ground, Enum.PathWaypointAction.Walk) },
	}
end

local function start_compute(pathfind: Pathfind)
	--
	pathfind.Queued = false
	pathfind.Computing = true
	pathfind.LastPathComputeTime = os.clock()
	pathfind.PathComputeToken = (pathfind.PathComputeToken or 0) + 1

	InFlightComputes += 1

	const token = pathfind.PathComputeToken :: number
	--

	pathfind
		:ComputePathToAsync(pathfind.TargetPosition)
		:andThen(function(result)
			apply_path_result(pathfind, result, token, false)
		end)
		:catch(function(err)
			--
			if pathfind.Destroyed or pathfind.PathComputeToken ~= token then
				return
			end
			--

			fail_request(pathfind, tostring(err))
		end)
		:finally(function()
			InFlightComputes -= 1
			pathfind.Computing = false
		end)
end

local function dispatch_computes()
	--
	const settings = Config.PATHFIND
	local budget = settings.MAX_COMPUTES_PER_FRAME
	--

	--
	while budget > 0 and InFlightComputes < settings.MAX_CONCURRENT_COMPUTES do
		const pathfind = table.remove(ComputeQueue, 1)

		if pathfind == nil then
			break
		end

		if pathfind.Destroyed or not pathfind.Queued then
			continue
		end

		budget -= 1
		start_compute(pathfind)
	end
	--
end

local function request_path(pathfind: Pathfind, direct_only: boolean)
	--
	if pathfind.Destroyed then
		return
	end

	if pathfind.Queued then
		pathfind.PendingRecalculate = false
		return
	end
	--

	--
	const clock = os.clock()
	const busy = pathfind.Computing or pathfind.Traversing

	if busy or clock - pathfind.LastPathComputeTime < pathfind.Config.RECALCULATE_THROTTLE then
		pathfind.PendingRecalculate = pathfind.PendingRecalculate or not direct_only
		return
	end
	--

	--
	const direct_result = try_direct_path(pathfind)

	if direct_result then
		pathfind.PendingRecalculate = false
		pathfind.LastPathComputeTime = clock
		pathfind.PathComputeToken = (pathfind.PathComputeToken or 0) + 1
		apply_path_result(pathfind, direct_result, pathfind.PathComputeToken :: number, true)
		return
	end

	if direct_only then
		return
	end
	--

	--
	pathfind.PendingRecalculate = false
	pathfind.Queued = true
	table.insert(ComputeQueue, pathfind)
	--
end

local function get_chase_request(pathfind: Pathfind, target_position: Vector3): ChaseRequest
	--
	if pathfind.Computing or pathfind.Queued or pathfind.Traversing then
		return "None"
	end

	if not pathfind.LastChasePosition then
		return "Full"
	end

	if (target_position - pathfind.LastChasePosition).Magnitude > pathfind.Config.RECALCULATE_DISTANCE_THRESHOLD then
		return "Full"
	end

	if pathfind.IsMoving then
		return "None"
	end

	if os.clock() - pathfind.LastPathComputeTime >= (pathfind.Config.IDLE_RECALCULATE_INTERVAL :: number) then
		return "Full"
	end
	--

	return "Direct"
end

local function resolve_target_position(target: BasePart | Model): Vector3
	--
	if not target:IsA("Model") then
		return target.CFrame.Position
	end
	--

	--
	if not target.PrimaryPart then
		return target:GetPivot().Position
	end
	--

	return target.PrimaryPart.CFrame.Position
end

local function is_target_alive(target: BasePart | Model): boolean
	--
	if not target.Parent then
		return false
	end

	if not target:IsA("Model") then
		return true
	end
	--

	--
	const humanoid = target:FindFirstChildOfClass("Humanoid")
	--

	return humanoid == nil or humanoid.Health > 0
end

local function step_chase(pathfind: Pathfind, dt: number)
	--
	const chase_target = pathfind.ChaseTarget

	if not chase_target then
		return
	end
	--

	--
	pathfind.ChaseElapsed += dt

	if pathfind.ChaseElapsed < pathfind.Config.RECALCULATE_THROTTLE then
		return
	end

	pathfind.ChaseElapsed = 0
	--

	--
	if not is_target_alive(chase_target) then
		pathfind:Stop()
		return
	end
	--

	--
	const target_pos = resolve_target_position(chase_target)
	const current_position = pathfind:GetCurrentPosition()
	const stopping_distance = pathfind.StoppingDistance
	const in_stopping_range = stopping_distance and (target_pos - current_position).Magnitude <= stopping_distance

	if in_stopping_range and not pathfind.IsMoving then
		return
	end
	--

	--
	if in_stopping_range then
		halt(pathfind)
		pathfind.OnArrived:Fire()
		return
	end
	--

	--
	const request = get_chase_request(pathfind, target_pos)

	if request == "None" then
		return
	end
	--

	--
	pathfind.LastChasePosition = target_pos
	pathfind.TargetPosition = target_pos
	--

	request_path(pathfind, request == "Direct")
end

local function is_airborne(pathfind: Pathfind): boolean
	--
	const humanoid = pathfind.Humanoid

	if not humanoid then
		return false
	end
	--

	return humanoid.FloorMaterial == Enum.Material.Air
end

local function needs_precise_arrival(pathfind: Pathfind): boolean
	--
	const next_waypoint = pathfind.Waypoints[pathfind.CurrentWaypointIndex]

	if not next_waypoint then
		return true
	end
	--

	return next_waypoint.Action == Enum.PathWaypointAction.Jump
end

local function step_movement(pathfind: Pathfind)
	--
	if pathfind.Traversing then
		return
	end

	if pathfind.PendingRecalculate then
		pathfind:RecalculatePath()
	end
	--

	--
	if not pathfind.IsMoving then
		return
	end
	--

	--
	const current_position = pathfind:GetCurrentPosition()
	const waypoint = pathfind.Waypoints[pathfind.CurrentWaypointIndex - 1]

	if not waypoint then
		pathfind:_ExecuteWaypoint()
		return
	end
	--

	--
	if is_airborne(pathfind) then
		pathfind.LastMovingTime = os.clock()
		pathfind.LastRecordedPosition = current_position
		return
	end

	if is_direct_line_blocked(pathfind) then
		request_path(pathfind, false)
		return
	end
	--

	--
	const config = pathfind.Config
	const diff = waypoint.Position - current_position
	const dist = Vector3.new(diff.X, 0, diff.Z).Magnitude
	const needs_precision = needs_precise_arrival(pathfind)
	const arrival_threshold = if needs_precision
		then config.WAYPOINT_ARRIVAL_RADIUS
		else math.min(config.WAYPOINT_ADVANCE_RADIUS or 2.8, config.WAYPOINT_SPACING * 0.75)

	if dist < arrival_threshold and math.abs(diff.Y) <= config.AGENT_HEIGHT then
		advance(pathfind)
		return
	end
	--

	--
	const root_part = pathfind:GetRoot()
	const velocity = root_part and root_part.AssemblyLinearVelocity or Vector3.zero
	const vel_normalised = Vector3.new(velocity.X, 0, velocity.Z)
	const speed = vel_normalised.Magnitude
	const dist_moved = (current_position - (pathfind.LastRecordedPosition or current_position)).Magnitude

	if speed > 1 or dist_moved > 0.1 then
		pathfind.LastMovingTime = os.clock()
		pathfind.LastRecordedPosition = current_position
	end
	--

	--
	const stuck_timeout = config.STUCK_TIMEOUT or config.STALL_TIMEOUT or 2

	if os.clock() - pathfind.LastMovingTime > stuck_timeout then
		recover_from_stuck(pathfind, current_position)
		return
	end
	--

	--
	if needs_precision or not root_part or diff.Magnitude <= 0 then
		return
	end

	if speed <= 1 then
		return
	end

	if not (dist <= arrival_threshold * 1.5 and math.abs(diff.Y) <= config.AGENT_HEIGHT) then
		return
	end
	--

	--
	const dirc_to_wp = Vector3.new(diff.X, 0, diff.Z).Unit
	const move_dirc = vel_normalised.Unit

	if not (dirc_to_wp:Dot(move_dirc) < 0) then
		return
	end
	--

	advance(pathfind)
end

local function step_agent(pathfind: Pathfind, dt: number)
	--
	if pathfind.Destroyed then
		Agents[pathfind] = nil
		return
	end
	--

	--
	step_chase(pathfind, dt)
	step_movement(pathfind)
	--

	--
	if pathfind.Config.VISUALISE then
		update_visualisation_label(pathfind)
	end
	--
end

local function report_step_error(err: any)
	task.spawn(error, debug.traceback(tostring(err), 2), 0)
end

local function stop_scheduler()
	--
	const connection = SchedulerConnection

	if not connection then
		return
	end
	--

	--
	connection:Disconnect()
	SchedulerConnection = nil
	--
end

local function step_scheduler(dt: number)
	--
	for _, pathfind in JoiningAgents do
		if pathfind.Destroyed then
			continue
		end

		Agents[pathfind] = true
	end

	table.clear(JoiningAgents)
	--

	--
	for pathfind in Agents do
		xpcall(step_agent, report_step_error, pathfind, dt)
	end
	--

	--
	dispatch_computes()
	--

	--
	if next(Agents) ~= nil or #JoiningAgents > 0 or #ComputeQueue > 0 then
		return
	end
	--

	stop_scheduler()
end

local function register_agent(pathfind: Pathfind)
	--
	table.insert(JoiningAgents, pathfind)
	--

	--
	if SchedulerConnection then
		return
	end
	--

	SchedulerConnection = RunService.Heartbeat:Connect(step_scheduler)
end

function Pathfind.ConnectPathLogic(self: Pathfind)
	--
	self.PathLogicKeeper:Clean()
	--

	--
	self.PathLogicKeeper:Connect(self.Path.Blocked, function(blocked_waypoint_index: number)
		if not self.IsMoving then
			return
		end

		if blocked_waypoint_index < self.CurrentWaypointIndex - 1 then
			return
		end

		self:RecalculatePath()
	end)

	if self.Humanoid then
		self.PathLogicKeeper:Connect(self.Humanoid.MoveToFinished, function(reached: boolean)
			if not self.IsMoving then
				return
			end

			if not reached then
				return
			end

			advance(self)
		end)
	end

	self.PathLogicKeeper:Connect(self.OnPathCalculated, function()
		self.IsMoving = true
		self:_ExecuteWaypoint()
	end)

	self.PathLogicKeeper:Connect(self.OnPathEnded, function()
		self:_ClearVisualisationNodes()
	end)
	--

	--
	if self.Destroyed then
		return
	end
	--

	register_agent(self)
end

function Pathfind.RecalculatePath(self: Pathfind)
	request_path(self, false)
end

local function set_destination(pathfind: Pathfind, target_position: Vector3)
	--
	pathfind.ChaseTarget = nil
	pathfind.LastChasePosition = nil
	pathfind.StoppingDistance = nil
	set_ray_filter(pathfind, nil)
	--

	--
	pathfind.TargetPosition = target_position
	pathfind.StuckCount = 0
	pathfind.PathComputeToken = (pathfind.PathComputeToken or 0) + 1
	--

	pathfind:RecalculatePath()
end

function Pathfind.Goto(self: Pathfind, target_position: Vector3)
	--
	cancel_request(self)
	--

	set_destination(self, target_position)
end

function Pathfind.GotoAsync(self: Pathfind, target_position: Vector3): Promise.TypedPromise<()>
	--
	const request = {} :: PendingRequest

	const promise = Promise.new(function(resolve, reject, on_cancel)
		request.Resolve = resolve
		request.Reject = reject

		on_cancel(function()
			if self.ActiveRequest ~= request then
				return
			end

			self.ActiveRequest = nil
			self:Stop()
		end)
	end)

	request.Cancel = function()
		promise:cancel()
	end
	--

	--
	cancel_request(self)
	self.ActiveRequest = request
	set_destination(self, target_position)
	--

	return promise
end

function Pathfind.Chase(self: Pathfind, target: BasePart | Model, stopping_distance: number?)
	--
	cancel_request(self)
	--

	--
	self.ChaseTarget = target
	self.LastChasePosition = nil
	self.StoppingDistance = stopping_distance
	self.ChaseElapsed = 0
	self.StuckCount = 0
	self.PathComputeToken = (self.PathComputeToken or 0) + 1
	set_ray_filter(self, target)
	--
end

function Pathfind.Stop(self: Pathfind)
	--
	self.ChaseTarget = nil
	self.LastChasePosition = nil
	self.StoppingDistance = nil
	set_ray_filter(self, nil)
	--

	--
	halt(self)
	--

	cancel_request(self)
end

function Pathfind.SetLinkHandler(self: Pathfind, label: string, handler: LinkHandler?)
	self.LinkHandlers[label] = handler
end

function Pathfind.Destroy(self: Pathfind)
	--
	unregister_agent(self)
	self.Keeper:Destroy()
	--
end

function PathfindModule.GetStats(): PathfindStats
	--
	local agent_count = #JoiningAgents

	for _ in Agents do
		agent_count += 1
	end
	--

	--
	const queued: { [any]: boolean } = {}
	local queued_count = 0

	for _, pathfind in ComputeQueue do
		if queued[pathfind] or pathfind.Destroyed or not pathfind.Queued then
			continue
		end

		queued[pathfind] = true
		queued_count += 1
	end
	--

	return {
		Agents = agent_count,
		Queued = queued_count,
		InFlight = InFlightComputes,
	}
end

function PathfindModule.SetLinkHandler(label: string, handler: LinkHandler?)
	SharedLinkHandlers[label] = handler
end

--
PathfindModule.new = new
--

return PathfindModule
