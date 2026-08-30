--!nonstrict
--[[
    FileName    > Pathfind.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 12/06/2026
--]]

const PathfindingService = game:GetService("PathfindingService")
const RunService = game:GetService("RunService")

const Keeper = require("@game/ReplicatedStorage/Packages/Keeper")
const Promise = require("../../../Promise")
const Signal = require("../../../Signal")
const PrintUtil = require("./Utilities/PrintUtil")
const TableUtil = require("./Utilities/TableUtil")

--
const FALLBACK_CONFIG = {
	RECALCULATE_THROTTLE = 0.2,
	RECALCULATE_DISTANCE_THRESHOLD = 4,

	AGENT_RADIUS = 2,
	AGENT_HEIGHT = 5,
	AGENT_CAN_JUMP = true,

	AGENT_COSTS = {},

	WAYPOINT_SPACING = 4,
	WAYPOINT_ARRIVAL_RADIUS = 1.5,
	WAYPOINT_ADVANCE_RADIUS = 2.8,
	STUCK_TIMEOUT = 2,
	STALL_TIMEOUT = 2,
	PARTIAL_PATH = true,

	VISUALISE = false,
}
--

--
local PathVisualisationFolder = workspace:FindFirstChild("PathVisualisation") or Instance.new("Folder")
PathVisualisationFolder.Name = "PathVisualisation"
PathVisualisationFolder.Parent = workspace

local VisualisationBallPart = Instance.new("Part")
VisualisationBallPart.Name = "CFVisualisationBall"
VisualisationBallPart.Shape = Enum.PartType.Ball
VisualisationBallPart.Size = Vector3.new(0.35, 0.35, 0.35)
VisualisationBallPart.Material = Enum.Material.Neon
VisualisationBallPart.Anchored = true
VisualisationBallPart.CanCollide = false
VisualisationBallPart.CanTouch = false
VisualisationBallPart.CanQuery = false
VisualisationBallPart.CastShadow = false

local VisualisationBillboard = Instance.new("BillboardGui")
VisualisationBillboard.Name = "CFVisualisationBillboard"
VisualisationBillboard.Size = UDim2.new(0, 180, 0, 50)
VisualisationBillboard.StudsOffset = Vector3.new(0, 0.6, 0)
VisualisationBillboard.AlwaysOnTop = true
VisualisationBillboard.ResetOnSpawn = false

local VisualisationLabel = Instance.new("TextLabel")
VisualisationLabel.Size = UDim2.new(1, 0, 1, 0)
VisualisationLabel.BackgroundTransparency = 1
VisualisationLabel.Font = Enum.Font.GothamBold
VisualisationLabel.TextSize = 13
VisualisationLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
VisualisationLabel.TextStrokeTransparency = 0.4
VisualisationLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
VisualisationLabel.Parent = VisualisationBillboard

local VisualisationLine = Instance.new("Part")
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

local PathfindModule = {}

PathfindModule.Movers = {
	Humanoid = function(humanoid: Humanoid)
		if not humanoid or not humanoid:IsA("Humanoid") then
			PrintUtil:Error("Invalid humanoid provided to PathfindModule.Movers.Humanoid")
		end

		return function(destination: Vector3)
			humanoid:MoveTo(destination)
		end
	end,
}

local Pathfind = {}
Pathfind.__index = Pathfind

local function new(param: {
	Entity: Model | BasePart,
	Humanoid: Humanoid?,

	Mover: (Vector3) -> (),

	Config: typeof(FALLBACK_CONFIG)?,
})
	local self = setmetatable({}, Pathfind)

	--
	self.Entity = param.Entity
	self.Humanoid = param.Humanoid

	self.Mover = param.Mover

	if self.Humanoid then
		self.Mover = self.Mover or PathfindModule.Movers.Humanoid(self.Humanoid)
	end
	--

	--
	local normalised_config = {} :: typeof(FALLBACK_CONFIG)

	if param.Config then
		for key, value in TableUtil.DeepClone(FALLBACK_CONFIG) do
			local override = param.Config[key]
			normalised_config[key] = if override ~= nil then override else value
		end
	else
		normalised_config = TableUtil.DeepClone(FALLBACK_CONFIG)
	end

	self.Config = normalised_config
	--

	--
	self.Keeper = Keeper.new()
	self.Keeper:AttachToInstance(self.Entity)
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
	self.CurrentWaypointIndex = 1
	self.ChaseTarget = nil :: (BasePart | Model)?
	self.LastChasePosition = nil :: Vector3?

	self.IsMoving = false
	self.Destroyed = false

	self.VisualisationNodes = {}
	self.StaleVisualisationNodes = {}
	self.VisitedNodePositions = {}

	if RunService:IsServer() then
		local root = self:GetRoot()
		if root and root:IsA("BasePart") and not root.Anchored then
			pcall(root.SetNetworkOwner, root, nil)
		end

		for _, part in self.Entity:GetDescendants() do
			if part:IsA("BasePart") and not part.Anchored then
				pcall(part.SetNetworkOwner, part, nil)
			end
		end

		if self.Entity:IsA("BasePart") and not self.Entity.Anchored then
			pcall(self.Entity.SetNetworkOwner, self.Entity, nil)
		end
	end
	--

	if self.Config.VISUALISE then
		--
		self.EntityVisualisationBillboard = self.Keeper:Add(VisualisationBillboard:Clone())
		self.EntityVisualisationLabel = self.EntityVisualisationBillboard:FindFirstChildOfClass("TextLabel")
		self.EntityVisualisationBillboard.Adornee = self.Entity
		self.EntityVisualisationBillboard.Parent = PathVisualisationFolder
		--

		--
		self.Keeper:Connect(RunService.Heartbeat, function()
			local target_name = self.ChaseTarget and self.ChaseTarget.Name or "None"
			local target_x = math.round(self.TargetPosition.X * 100) / 100
			local target_y = math.round(self.TargetPosition.Y * 100) / 100
			local target_z = math.round(self.TargetPosition.Z * 100) / 100

			self.EntityVisualisationLabel.Text = `ChaseTarget: {target_name}\n`
				.. `CurrentWayPointIndex: {self.CurrentWaypointIndex}\n`
				.. `TargetPosition: {target_x}, {target_y}, {target_z}\n`
				.. `IsMoving: {self.IsMoving}`
		end, "VisualisationLogic")
		--
	end

	--
	self.OnPathCalculated = self.Keeper:Construct(Signal.new)
	self.OnPathEnded = self.Keeper:Construct(Signal.new)
	--

	--
	self:ConnectPathLogic()
	--

	return self
end

export type Pathfind = typeof(new(...))

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

function Pathfind.GetRoot(self: Pathfind)
	if not self.IsModel then
		return self.Entity
	end

	return self.Entity.PrimaryPart or self.Entity:FindFirstChild("HumanoidRootPart")
end

function Pathfind.GetCurrentPosition(self: Pathfind)
	if not self.IsModel then
		return self.Entity.Position
	end

	return self.Entity.PrimaryPart and self.Entity.PrimaryPart.CFrame.Position or self.Entity:GetPivot().Position
end

--
local function position_key(position: Vector3): string
	local x = math.round(position.X * 10) / 10
	local y = math.round(position.Y * 10) / 10
	local z = math.round(position.Z * 10) / 10

	return `{x},{y},{z}`
end
--

function Pathfind._ExecuteWaypoint(self: Pathfind)
	--
	if self.Config.VISUALISE then
		local just_reached = self.Waypoints[self.CurrentWaypointIndex - 1]
		if just_reached then
			self.VisitedNodePositions[position_key(just_reached.Position)] = true
		end
	end

	--
	local waypoint = self.Waypoints[self.CurrentWaypointIndex]

	if not waypoint then
		self.IsMoving = false
		self.OnPathEnded:Fire()
		return false
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

--
local PathLogiCleanupKey = "PathLogic"

function Pathfind.ConnectPathLogic(self: Pathfind)
	--
	self.Keeper:Remove(PathLogiCleanupKey)
	--

	self.Keeper:Connect(self.Path.Blocked, function(blocked_waypoint_index)
		--
		if not self.IsMoving then
			return
		end
		--

		--
		if blocked_waypoint_index < self.CurrentWaypointIndex - 1 then
			return
		end
		--

		--

		self:RecalculatePath()
	end, PathLogiCleanupKey)

	self.Keeper:Connect(RunService.Heartbeat, function()
		--
		if self.PendingRecalculate then
			self:RecalculatePath()
		end
		--

		--
		if not self.IsMoving then
			return
		end
		--

		--
		local current_position = self:GetCurrentPosition()
		local waypoint = self.Waypoints[self.CurrentWaypointIndex - 1]

		if not waypoint then
			self:_ExecuteWaypoint()
			return
		end
		--

		--
		local diff = waypoint.Position - current_position
		local dist = Vector3.new(diff.X, 0, diff.Z).Magnitude
		local is_final_waypoint = (self.Waypoints[self.CurrentWaypointIndex] == nil)
		local arrival_threshold = if is_final_waypoint
			then self.Config.WAYPOINT_ARRIVAL_RADIUS
			else math.min(self.Config.WAYPOINT_ADVANCE_RADIUS or 2.8, self.Config.WAYPOINT_SPACING * 0.75)

		if dist < arrival_threshold and math.abs(diff.Y) <= self.Config.AGENT_HEIGHT then
			self:_ExecuteWaypoint()
			return
		end
		--

		--
		local root_part = self:GetRoot()
		local velocity = root_part and root_part.AssemblyLinearVelocity or Vector3.zero
		local vel_normalised = Vector3.new(velocity.X, 0, velocity.Z)
		local speed = vel_normalised.Magnitude
		local dist_moved = (current_position - (self.LastRecordedPosition or current_position)).Magnitude

		if speed > 1 or dist_moved > 0.1 then
			self.LastMovingTime = os.clock()
			self.LastRecordedPosition = current_position
		end

		local stuck_timeout = self.Config.STUCK_TIMEOUT or self.Config.STALL_TIMEOUT or 2

		--
		if os.clock() - self.LastMovingTime > stuck_timeout then
			self.LastMovingTime = os.clock()
			self.LastAdvanceTime = os.clock()
			self.LastRecordedPosition = current_position
			self:RecalculatePath()
			return
		end
		--

		if not root_part or diff.Magnitude <= 0 then
			return
		end
		--

		if vel_normalised.Magnitude <= 1 then
			return
		end
		--

		--
		if dist <= arrival_threshold * 1.5 and math.abs(diff.Y) <= self.Config.AGENT_HEIGHT then
			local dirc_to_wp = Vector3.new(diff.X, 0, diff.Z).Unit
			local move_dirc = vel_normalised.Unit

			if dirc_to_wp:Dot(move_dirc) < 0 then
				self:_ExecuteWaypoint()
			end
		end
		--
	end, PathLogiCleanupKey)

	if self.Humanoid then
		self.Keeper:Connect(self.Humanoid.MoveToFinished, function(reached)
			if not self.IsMoving then
				return
			end

			if reached then
				--
				self:_ExecuteWaypoint()
			end
		end, PathLogiCleanupKey)
	end

	self.OnPathCalculated:Connect(function(waypoints)
		self.IsMoving = true
		self:_ExecuteWaypoint()
	end, PathLogiCleanupKey)

	self.OnPathEnded:Connect(function()
		self:_ClearVisualisationNodes()
	end, PathLogiCleanupKey)
end
--

function Pathfind.ComputePathToAsync(self: Pathfind, target_position: Vector3)
	--
	return Promise.new(function(resolve)
		local current_position = self:GetCurrentPosition()

		--
		self.Path:ComputeAsync(current_position, target_position)
		--

		resolve({ Status = self.Path.Status, Waypoints = self.Path:GetWaypoints() })
	end)
	--
end

function Pathfind._UpdateVisualisation(self: Pathfind)
	if not self.Config.VISUALISE then
		return
	end

	local new_nodes = {}

	local function was_visited(node: Part): boolean
		return self.VisitedNodePositions[position_key(node.Position)] == true
	end

	local function apply_blocked_color(node: Part)
		if was_visited(node) then
			return
		end

		node.Color = Color3.fromRGB(255, 0, 0)

		--
		local line = node:FindFirstChild("PathLine")

		if not line then
			return
		end
		--

		line.Color = Color3.fromRGB(255, 0, 0)
	end

	for i, wp in self.Waypoints do
		--
		local old_node = self.VisualisationNodes[i]
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
		local new_node = VisualisationBallPart:Clone()
		new_node.Position = wp.Position
		new_node.Parent = PathVisualisationFolder
		new_nodes[i] = new_node
		--

		--
		if i <= 1 then
			continue
		end
		--

		--
		local prev_wp = self.Waypoints[i - 1]
		local p1 = prev_wp.Position
		local p2 = wp.Position
		local dist = (p2 - p1).Magnitude

		local line = VisualisationLine:Clone()
		line.Size = Vector3.new(dist, 0.1, 0.1)
		line.CFrame = CFrame.lookAt(p1, p2) * CFrame.new(0, 0, -dist / 2) * CFrame.Angles(0, math.pi / 2, 0)
		line.Parent = new_node
		--
	end

	for _, old_node in self.VisualisationNodes do
		apply_blocked_color(old_node)
		table.insert(self.StaleVisualisationNodes, old_node)
	end

	self.VisualisationNodes = new_nodes
end

function Pathfind.RecalculatePath(self: Pathfind)
	--
	if self.Destroyed then
		return
	end
	--

	--
	local clock = os.clock()

	if clock - self.LastPathComputeTime < self.Config.RECALCULATE_THROTTLE then
		self.PendingRecalculate = true
		return
	end

	self.PendingRecalculate = false
	self.LastPathComputeTime = clock
	--

	self.PathComputeToken = (self.PathComputeToken or 0) + 1
	local current_token = self.PathComputeToken

	--
	self:ComputePathToAsync(self.TargetPosition):andThen(function(result)
		if self.Destroyed or self.PathComputeToken ~= current_token then
			return
		end

		if
			result.Status ~= Enum.PathStatus.Success
			and not (result.Status == Enum.PathStatus.NoPath and self.Config.PARTIAL_PATH)
		then
			PrintUtil:Warn("Failed to recalculate path. Status: " .. tostring(result.Status))
			return
		end

		local current_pos = self:GetCurrentPosition()
		local threshold = math.max(self.Config.WAYPOINT_ARRIVAL_RADIUS, self.Config.AGENT_RADIUS)

		self.Waypoints = result.Waypoints
		self.CurrentWaypointIndex = 1
		self.LastAdvanceTime = os.clock()
		self.LastMovingTime = os.clock()
		self.LastRecordedPosition = current_pos

		--

		while self.CurrentWaypointIndex < #self.Waypoints do
			--
			local wp = self.Waypoints[self.CurrentWaypointIndex]

			local dist = Vector3.new(wp.Position.X - current_pos.X, 0, wp.Position.Z - current_pos.Z).Magnitude
			if dist > threshold then
				break
			end
			--

			self.CurrentWaypointIndex += 1
		end
		--

		self.OnPathCalculated:Fire(self.Waypoints)

		self:_UpdateVisualisation()
	end)
	--
end

function Pathfind.Goto(self: Pathfind, target_position: Vector3)
	--
	self.ChaseTarget = nil
	self.LastChasePosition = nil
	--

	--
	self.TargetPosition = target_position
	--

	self:RecalculatePath()
end

--
local ChaseCleanupKey = "ChaseLogic"

function Pathfind.Chase(self: Pathfind, target: BasePart | Model, stopping_distance: number?)
	--
	self.ChaseTarget = target
	self.LastChasePosition = nil
	--

	--
	self.Keeper:Remove(ChaseCleanupKey)
	--

	local time_since_last_compute = 0

	--
	self.Keeper:Connect(RunService.Heartbeat, function(dt)
		if not self.ChaseTarget then
			self.Keeper:Remove(ChaseCleanupKey)
			return
		end

		--
		time_since_last_compute += dt

		if time_since_last_compute < self.Config.RECALCULATE_THROTTLE then
			return
		end

		time_since_last_compute = 0
		--

		--
		local target_pos

		if self.ChaseTarget:IsA("Model") then
			if not self.ChaseTarget.PrimaryPart then
				target_pos = self.ChaseTarget:GetPivot().Position
			else
				target_pos = self.ChaseTarget.PrimaryPart.CFrame.Position
			end
		else
			target_pos = self.ChaseTarget.CFrame.Position
		end
		--

		--
		local current_position = self:GetCurrentPosition()

		if stopping_distance and (target_pos - current_position).Magnitude <= stopping_distance then
			if not self.IsMoving then
				return
			end

			self.IsMoving = false
			self.Waypoints = {}
			self.CurrentWaypointIndex = 1
			self.PendingRecalculate = false
			self.PathComputeToken = (self.PathComputeToken or 0) + 1

			self.Mover(current_position)

			return
		end
		--

		--
		local needs_recalc = false

		if not self.LastChasePosition then
			needs_recalc = true
		elseif (target_pos - self.LastChasePosition).Magnitude > self.Config.RECALCULATE_DISTANCE_THRESHOLD then
			needs_recalc = true
		elseif not self.IsMoving then
			needs_recalc = true
		end

		if not needs_recalc then
			return
		end
		--

		self.LastChasePosition = target_pos
		self.TargetPosition = target_pos

		self:RecalculatePath()
	end, ChaseCleanupKey)
	--
end
--

function Pathfind.Stop(self: Pathfind)
	--
	self.IsMoving = false
	self.Waypoints = {}
	self.CurrentWaypointIndex = 1
	self.PendingRecalculate = false
	self.LastAdvanceTime = os.clock()
	self.LastMovingTime = os.clock()
	self.LastRecordedPosition = self:GetCurrentPosition()
	self.PathComputeToken = (self.PathComputeToken or 0) + 1
	--

	--
	self.ChaseTarget = nil
	self.LastChasePosition = nil
	self.Keeper:Remove(ChaseCleanupKey)
	--

	--
	self.OnPathEnded:Fire()

	self.Mover(self:GetCurrentPosition())
	--
end

function Pathfind.Destroy(self: Pathfind)
	self.Destroyed = true
	self.PendingRecalculate = false
	self.Keeper:Destroy()
end

PathfindModule.new = new

return PathfindModule
