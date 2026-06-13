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
const Signal = require("@game/ReplicatedStorage/Shared/Signal")
const Promise = require("./Packages/Promise")
const Craftsman = require("./Packages/Craftsman")

--
const FALLBACK_CONFIG = {
	RECALCULATE_THROTTLE = 0.2, -- seconds
	RECALCULATE_DISTANCE_THRESHOLD = 4, -- studs

	AGENT_RADIUS = 2,
	AGENT_HEIGHT = 5,
	AGENT_CAN_JUMP = true,

	AGENT_COSTS = {},

	WAYPOINT_SPACING = 4,
	PARTIAL_PATH = true,
}
--

local PathfindModule = {}

PathfindModule.Movers = {
	Humanoid = function(humanoid: Humanoid)
		if not humanoid or not humanoid:IsA("Humanoid") then
			Craftsman.PrintUtil:Error("Invalid humanoid provided to PathfindModule.Movers.Humanoid")
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
		for key, value in Craftsman.TableUtil.DeepClone(FALLBACK_CONFIG) do
			normalised_config[key] = param.Config and param.Config[key] or value
		end
	else
		normalised_config = Craftsman.TableUtil.DeepClone(FALLBACK_CONFIG)
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
	self.Waypoints = {} :: typeof(self.Path:GetWaypoints())
	self.TargetPosition = self:GetCurrentPosition()
	self.LastPathComputeTime = 0
	self.CurrentWaypointIndex = 1
	self.ChaseTarget = nil :: (BasePart | Model)?
	self.LastChasePosition = nil :: Vector3?

	self.IsModel = self.Entity:IsA("Model")

	self.IsMoving = false
	self.Destroyed = false
	--

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

function Pathfind.GetCurrentPosition(self: Pathfind)
	if self.IsModel then
		return self.Entity.PrimaryPart and self.Entity.PrimaryPart.CFrame.Position or self.Entity:GetPivot().Position
	else
		return self.Entity.Position
	end
end

function Pathfind._ExecuteWaypoint(self: Pathfind)
	-- Check
	local waypoint = self.Waypoints[self.CurrentWaypointIndex]

	if not waypoint then
		self.IsMoving = false
		self.OnPathEnded:Fire()
		return false
	end
	--

	-- We only execute jump when the agent CanJump is valid, and the path requires jump, while also having a humanoid
	if waypoint.Action == Enum.PathWaypointAction.Jump and self.Humanoid then
		self.Humanoid.Jump = true
	end
	--

	-- Move to the waypoint and increment the index
	self.Mover(waypoint.Position)
	self.CurrentWaypointIndex += 1
	--

	return true
end

--
local PathLogiCleanupKey = "PathLogic"

function Pathfind.ConnectPathLogic(self: Pathfind)
	-- Remove previous connections if they exist
	self.Keeper:Remove(PathLogiCleanupKey)
	--

	self.Keeper:Connect(self.Path.Blocked, function(blocked_waypoint_index)
		--
		if not self.IsMoving then
			return
		end
		--

		-- We only need to recalculate if the blocked waypoint is ahead of us
		if blocked_waypoint_index < self.CurrentWaypointIndex then
			return
		end
		--

		self:RecalculatePath()
	end, PathLogiCleanupKey)

	if self.Humanoid then
		self.Keeper:Connect(self.Humanoid.MoveToFinished, function(reached)
			--
			if not self.IsMoving then
				return
			end
			--

			-- Agent is probably stuck
			if not reached then
				self:RecalculatePath()
				return
			end
			--

			self:_ExecuteWaypoint()
		end, PathLogiCleanupKey)
	else
		-- If we don't have a humanoid, we can use a simple heartbeat loop to check when to move to the next waypoint
		self.Keeper:Connect(RunService.Heartbeat, function()
			--
			if not self.IsMoving then
				return
			end
			--

			local current_position = self:GetCurrentPosition()
			local waypoint = self.Waypoints[self.CurrentWaypointIndex - 1]

			local diff = waypoint.Position - current_position
			local dist = diff.Magnitude

			if not waypoint or dist > self.Config.AGENT_RADIUS then
				return
			end

			self:_ExecuteWaypoint()
		end, PathLogiCleanupKey)
	end

	self.OnPathCalculated:Connect(function(waypoints)
		self.IsMoving = true

		self:_ExecuteWaypoint()
	end, PathLogiCleanupKey)
end
--

function Pathfind.ComputePathToAsync(self: Pathfind, target_position: Vector3)
	-- Async returns a Promise
	return Promise.new(function(resolve)
		local current_position = self:GetCurrentPosition()

		--
		self.Path:ComputeAsync(current_position, target_position)
		--

		resolve({ Status = self.Path.Status, Waypoints = self.Path:GetWaypoints() })
	end)
	--
end

function Pathfind.RecalculatePath(self: Pathfind)
	--
	local clock = os.clock()

	if clock - self.LastPathComputeTime < self.Config.RECALCULATE_THROTTLE then
		return
	end

	self.LastPathComputeTime = clock
	--

	--
	self:ComputePathToAsync(self.TargetPosition):andThen(function(result)
		if
			result.Status == Enum.PathStatus.Success
			or (result.Status == Enum.PathStatus.NoPath and self.Config.PARTIAL_PATH)
		then
			self.Waypoints = result.Waypoints
			self.CurrentWaypointIndex = 1

			self.OnPathCalculated:Fire(self.Waypoints)
		else
			Craftsman.PrintUtil:Warn("Failed to recalculate path. Status: " .. tostring(result.Status))
		end
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

function Pathfind.Chase(self: Pathfind, target: BasePart | Model)
	--
	self.ChaseTarget = target
	self.LastChasePosition = nil
	--

	-- Remove existing chase logic
	self.Keeper:Remove(ChaseCleanupKey)
	--

	local time_since_last_compute = 0

	--
	self.Keeper:Connect(RunService.Heartbeat, function(dt)
		if not self.ChaseTarget then
			self.Keeper:Remove(ChaseCleanupKey)
			return
		end

		-- Throttle
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
	--

	-- Chase logic
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
	self.Keeper:Destroy()
	self.Destroyed = true
end

PathfindModule.new = new

return PathfindModule
