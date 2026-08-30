--!nonstrict
--[[
    FileName    > WorldUtil.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 21/05/2026
--]]

const PrintUtil = require("./PrintUtil")

const Below = -Vector3.yAxis

type CastMode = "Raycast" | "Block" | "Sphere"

type CastOptions = {
	Mode: CastMode?,
	BlockSize: Vector3?,
	SphereRadius: number?,
}

local function get_cast_result(
	origin: Vector3,
	direction: Vector3,
	ray_param: RaycastParams,
	options: CastOptions?,
	cframe: CFrame?
)
	local cast_options = (options or {}) :: CastOptions
	local cast_mode = cast_options.Mode

	if cast_mode == "Block" then
		return workspace:Blockcast(
			cframe or CFrame.new(origin),
			cast_options.BlockSize or Vector3.one,
			direction,
			ray_param
		)
	end

	if cast_mode == "Sphere" then
		return workspace:Spherecast(origin, cast_options.SphereRadius or 1, direction, ray_param)
	end

	return workspace:Raycast(origin, direction, ray_param)
end

--[=[
	@class WorldUtil
	A premium spatial query library that simplifies physics casting (Ray/Block/Sphere casts), overlap checks, proximity calculation, and screen/camera projections.
]=]
--
local WorldUtil = {}

--[=[
	@prop RayParams { [string]: RaycastParams } -- Dictionary of registered global RaycastParams.
	@within WorldUtil
]=]
--
WorldUtil.RayParams = {}

--[=[
	@prop OverlapParams { [string]: OverlapParams } -- Dictionary of registered global OverlapParams.
	@within WorldUtil
]=]
--
WorldUtil.OverlapParams = {}

--[=[
	Registers a global set of RaycastParams with a specific identifier.
	@param id string -- The unique string identifier.
	@param params RaycastParams -- The RaycastParams to store.
]=]
--
function WorldUtil:AddRayParams(id: string, params: RaycastParams)
	WorldUtil.RayParams[id] = params
end

--[=[
	Retrieves the registered RaycastParams associated with a unique identifier.
	@param id string -- The unique identifier.
	@return RaycastParams? -- The retrieved RaycastParams, or `nil` if not found.
]=]
--
function WorldUtil:GetRayParams(id: string): RaycastParams?
	return WorldUtil.RayParams[id]
end

--[=[
	Removes the registered RaycastParams associated with a unique identifier.
	@param id string -- The unique identifier.
]=]
--
function WorldUtil:RemoveRayParams(id: string)
	WorldUtil.RayParams[id] = nil
end

--[=[
	Registers a global set of OverlapParams with a specific identifier.
	@param id string -- The unique string identifier.
	@param params OverlapParams -- The OverlapParams to store.
]=]
--
function WorldUtil:AddOverlapParams(id: string, params: OverlapParams)
	WorldUtil.OverlapParams[id] = params
end

--[=[
	Retrieves the registered OverlapParams associated with a unique identifier.
	@param id string -- The unique identifier.
	@return OverlapParams? -- The retrieved OverlapParams, or `nil` if not found.
]=]
--
function WorldUtil:GetOverlapParams(id: string): OverlapParams?
	return WorldUtil.OverlapParams[id]
end

--[=[
	Removes the registered OverlapParams associated with a unique identifier.
	@param id string -- The unique identifier.
]=]
--
function WorldUtil:RemoveOverlapParams(id: string)
	WorldUtil.OverlapParams[id] = nil
end

--[=[
	Casts a ray, block, or sphere downwards from a given position.
	@param param { Position: Vector3, Distance: number, RayParamsId: string, RayParams: RaycastParams? } & CastOptions -- The parameter object configuring the cast.
	@return RaycastResult? -- The physics cast result, or `nil` if nothing was hit.
]=]
--
function WorldUtil:RayBelow(param: {
	Position: Vector3,
	Distance: number,
	RayParamsId: string?,
	RayParams: RaycastParams?,
} & CastOptions): RaycastResult?
	local ray_param = param.RayParams or self:GetRayParams(param.RayParamsId)

	if not ray_param then
		PrintUtil:Error(`No RayParams found for id: {param.RayParamsId}`)
		return
	end

	return get_cast_result(param.Position, Below * param.Distance, ray_param, param, CFrame.new(param.Position))
end

--[=[
	Checks if a downward cast hits any solid geometry, typically used for character ground checks.
	@param param { Position: Vector3, Distance: number, RayParamsId: string, RayParams: RaycastParams? } & CastOptions -- The parameter object configuring the cast.
	@return boolean -- `true` if grounded, `false` otherwise.
]=]
--
function WorldUtil:IsGrounded(param: {
	Position: Vector3,
	Distance: number,
	RayParamsId: string?,
	RayParams: RaycastParams?,
} & CastOptions): boolean
	local raycast_result = self:RayBelow(param)

	return raycast_result ~= nil
end

--[=[
	Casts a ray, block, or sphere in front of a given CFrame (along LookVector).
	@param param { CFrame: CFrame, Distance: number, RayParamsId: string, RayParams: RaycastParams?, Direction: Vector3? } & CastOptions -- The parameter object configuring the cast.
	@return RaycastResult? -- The physics cast result, or `nil` if nothing was hit.
]=]
--
function WorldUtil:RayFront(param: {
	CFrame: CFrame,
	Distance: number,
	RayParamsId: string?,
	RayParams: RaycastParams?,
	Direction: Vector3?,
} & CastOptions): RaycastResult?
	local ray_param = param.RayParams or self:GetRayParams(param.RayParamsId)

	if not ray_param then
		PrintUtil:Error(`No RayParams found for id: {param.RayParamsId}`)
		return
	end

	return get_cast_result(
		param.CFrame.Position,
		param.CFrame.LookVector * param.Distance + (param.Direction or Vector3.zero),
		ray_param,
		param,
		param.CFrame
	)
end

--[=[
	Casts a ray, block, or sphere to the side of a given CFrame (along RightVector).
	@param param { CFrame: CFrame, Distance: number, RayParamsId: string, RayParams: RaycastParams?, Direction: Vector3? } & CastOptions -- The parameter object configuring the cast.
	@return RaycastResult? -- The physics cast result, or `nil` if nothing was hit.
]=]
--
function WorldUtil:RaySide(param: {
	CFrame: CFrame,
	Distance: number,
	RayParamsId: string?,
	RayParams: RaycastParams?,
	Direction: Vector3?,
} & CastOptions): RaycastResult?
	local ray_param = param.RayParams or self:GetRayParams(param.RayParamsId)

	if not ray_param then
		PrintUtil:Error(`No RayParams found for id: {param.RayParamsId}`)
		return
	end

	return get_cast_result(
		param.CFrame.Position,
		param.CFrame.RightVector * param.Distance + (param.Direction or Vector3.zero),
		ray_param,
		param,
		param.CFrame
	)
end

--[=[
	Casts a ray, block, or sphere upwards from a given CFrame (along UpVector).
	@param param { CFrame: CFrame, Distance: number, RayParamsId: string, RayParams: RaycastParams?, Direction: Vector3? } & CastOptions -- The parameter object configuring the cast.
	@return RaycastResult? -- The physics cast result, or `nil` if nothing was hit.
]=]
--
function WorldUtil:RayUp(param: {
	CFrame: CFrame,
	Distance: number,
	RayParamsId: string,
	RayParams: RaycastParams?,
	Direction: Vector3?,
} & CastOptions): RaycastResult?
	local ray_param = param.RayParams or self:GetRayParams(param.RayParamsId)

	if not ray_param then
		PrintUtil:Error(`No RayParams found for id: {param.RayParamsId}`)
		return
	end

	return get_cast_result(
		param.CFrame.Position,
		param.CFrame.UpVector * param.Distance + (param.Direction or Vector3.zero),
		ray_param,
		param,
		param.CFrame
	)
end

--[=[
	Gets the hit position of a downward physics cast.
	@param param { Position: Vector3, Distance: number, RayParamsId: string, RayParams: RaycastParams? } & CastOptions -- The parameters.
	@return Vector3? -- The hit position vector, or `nil` if no surface was hit.
]=]
--
function WorldUtil:GetGroundPosition(param: {
	Position: Vector3,
	Distance: number,
	RayParamsId: string?,
	RayParams: RaycastParams?,
} & CastOptions): Vector3?
	local raycast_result = self:RayBelow(param)

	if not raycast_result then
		return nil
	end

	return raycast_result.Position
end

--[=[
	Gets the surface normal vector of a downward physics cast.
	@param param { Position: Vector3, Distance: number, RayParamsId: string, RayParams: RaycastParams? } & CastOptions -- The parameters.
	@return Vector3? -- The hit surface normal Vector3, or `nil` if no surface was hit.
]=]
--
function WorldUtil:GetGroundNormal(param: {
	Position: Vector3,
	Distance: number,
	RayParamsId: string?,
	RayParams: RaycastParams?,
} & CastOptions): Vector3?
	local raycast_result = self:RayBelow(param)

	if not raycast_result then
		return nil
	end

	return raycast_result.Normal
end

--[=[
	Retrieves all BaseParts located within a spherical radius using OverlapParams.
	@param param { Center: Vector3, Radius: number, OverlapParamsId: string, OverlapParams: OverlapParams? } -- The query configuration.
	@return { BasePart } -- An array list of matching BaseParts.
]=]
--
function WorldUtil:GetPartsInRadius(param: {
	Center: Vector3,
	Radius: number,
	OverlapParamsId: string?,
	OverlapParams: OverlapParams?,
}): { BasePart }
	local overlap_param = param.OverlapParams or self:GetOverlapParams(param.OverlapParamsId)

	return workspace:GetPartBoundsInRadius(param.Center, param.Radius, overlap_param)
end

--[=[
	Retrieves all BaseParts located within a bounding box CFrame and Size using OverlapParams.
	@param param { CFrame: CFrame, Size: Vector3, OverlapParamsId: string, OverlapParams: OverlapParams? } -- The query configuration.
	@return { BasePart } -- An array list of matching BaseParts.
]=]
--
function WorldUtil:GetPartsInBox(param: {
	CFrame: CFrame,
	Size: Vector3,
	OverlapParamsId: string?,
	OverlapParams: OverlapParams?,
}): { BasePart }
	local overlap_param = param.OverlapParams or self:GetOverlapParams(param.OverlapParamsId)

	return workspace:GetPartBoundsInBox(param.CFrame, param.Size, overlap_param)
end

--[=[
	Retrieves all BaseParts overlapping the collision boundaries of a specific Part using OverlapParams.
	@param param { Part: BasePart, OverlapParamsId: string, OverlapParams: OverlapParams? } -- The query configuration.
	@return { BasePart } -- An array list of overlapping BaseParts.
]=]
--
function WorldUtil:GetPartsInPart(param: {
	Part: BasePart,
	OverlapParamsId: string?,
	OverlapParams: OverlapParams?,
}): { BasePart }
	local overlap_param = param.OverlapParams or self:GetOverlapParams(param.OverlapParamsId)

	return workspace:GetPartsInPart(param.Part, overlap_param)
end

local function resolve_position(point: Vector3 | CFrame | BasePart | Model): Vector3
	if typeof(point) == "Vector3" then
		return point
	end

	if typeof(point) == "CFrame" then
		return point.Position
	end

	if point:IsA("BasePart") then
		return point.Position
	end

	if point:IsA("Model") then
		return point:GetPivot().Position
	end

	error("Invalid point type")
end

--[=[
	Calculates the distance between two spatial points (supports Vector3, CFrame, BasePart, or Model).
	@param point_a Vector3 | CFrame | BasePart | Model -- The first point.
	@param point_b Vector3 | CFrame | BasePart | Model -- The second point.
	@return number -- The distance in studs.
]=]
--
function WorldUtil:GetDistance(
	point_a: Vector3 | CFrame | BasePart | Model,
	point_b: Vector3 | CFrame | BasePart | Model
): number
	local position_a = resolve_position(point_a)
	local position_b = resolve_position(point_b)

	return (position_a - position_b).Magnitude
end

--[=[
	Finds the nearest BasePart or Model to an origin coordinate from a list of instances.
	@param param { Origin: Vector3, Instances: { BasePart | Model } } -- The search parameters.
	@return BasePart | Model? -- The closest spatial instance found, or `nil` if list is empty.
	@return number -- The distance in studs to the closest instance.
]=]
--
function WorldUtil:GetNearest(param: {
	Origin: Vector3,
	Instances: { BasePart | Model },
}): (BasePart | Model?, number)
	local nearest_part = nil
	local nearest_distance = math.huge

	for _, instance in param.Instances do
		local position

		if instance:IsA("Model") then
			position = instance:GetPivot().Position
		else
			position = instance.Position
		end

		local distance = (param.Origin - position).Magnitude

		if distance < nearest_distance then
			nearest_part = instance
			nearest_distance = distance
		end
	end

	return nearest_part, nearest_distance
end

--[=[
	Alias for GetNearest. Finds the nearest BasePart or Model to an origin coordinate.
	@param param { Origin: Vector3, Instances: { BasePart | Model } } -- The search parameters.
	@return BasePart | Model? -- The closest spatial instance, or `nil`.
	@return number -- The distance in studs.
]=]
--
function WorldUtil:GetNearestPart(param: {
	Origin: Vector3,
	Instances: { BasePart | Model },
})
	return self:GetNearest(param)
end

--[=[
	Finds the closest Vector3 coordinate from an array list of points relative to an origin.
	@param origin Vector3 -- The baseline origin.
	@param points { Vector3 } -- The array list of target coordinates.
	@return Vector3? -- The closest coordinate point, or `nil` if array is empty.
	@return number -- The distance in studs to that point.
]=]
--
function WorldUtil:GetNearestPoint(origin: Vector3, points: { Vector3 }): (Vector3?, number)
	local nearest_point = nil
	local nearest_distance = math.huge

	for _, point in points do
		local distance = (origin - point).Magnitude
		if distance < nearest_distance then
			nearest_point = point
			nearest_distance = distance
		end
	end

	return nearest_point, nearest_distance
end

--[=[
	Projects a 3D world position vector into 2D viewport coordinates using a specified Camera.
	@param world_position Vector3 -- The 3D world coordinate.
	@param camera Camera? -- Optional target camera (defaults to CurrentCamera).
	@return Vector2? -- The projected 2D viewport coordinate, or `nil` if camera is missing.
	@return boolean -- `true` if the projected point is visible within the screen viewport boundary, `false` otherwise.
]=]
--
function WorldUtil:WorldToScreen(world_position: Vector3, camera: Camera?): (Vector2?, boolean)
	local active_camera = camera or workspace.CurrentCamera

	if not active_camera then
		return nil, false
	end

	local screen_position, on_screen = active_camera:WorldToViewportPoint(world_position)
	return Vector2.new(screen_position.X, screen_position.Y), on_screen
end

--[=[
	Projects a 2D screen coordinate outward into 3D world space at a specific depth along the camera direction.
	@param screen_position Vector2 -- The 2D viewport screen coordinate.
	@param depth number -- The distance outward in studs.
	@param camera Camera? -- Optional target camera (defaults to CurrentCamera).
	@return Vector3? -- The projected 3D world position coordinate, or `nil` if camera is missing.
]=]
--
function WorldUtil:ScreenToWorld(screen_position: Vector2, depth: number, camera: Camera?): Vector3?
	local active_camera = camera or workspace.CurrentCamera

	if not active_camera then
		return nil
	end

	local ray = active_camera:ViewportPointToRay(screen_position.X, screen_position.Y)
	return ray.Origin + ray.Direction * depth
end

return WorldUtil
