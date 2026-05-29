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

local WorldUtil = {}
WorldUtil.RayParams = {}
WorldUtil.OverlapParams = {}

function WorldUtil:AddRayParams(id: string, params: RaycastParams)
	WorldUtil.RayParams[id] = params
end

function WorldUtil:GetRayParams(id: string): RaycastParams?
	return WorldUtil.RayParams[id]
end

function WorldUtil:RemoveRayParams(id: string)
	WorldUtil.RayParams[id] = nil
end

function WorldUtil:AddOverlapParams(id: string, params: OverlapParams)
	WorldUtil.OverlapParams[id] = params
end

function WorldUtil:GetOverlapParams(id: string): OverlapParams?
	return WorldUtil.OverlapParams[id]
end

function WorldUtil:RemoveOverlapParams(id: string)
	WorldUtil.OverlapParams[id] = nil
end

function WorldUtil:RayBelow(param: {
	Position: Vector3,
	Distance: number,
	RayParamsId: string,
	RayParams: RaycastParams?,
} & CastOptions)
	local ray_param = param.RayParams or self:GetRayParams(param.RayParamsId)

	if not ray_param then
		PrintUtil:Error(`No RayParams found for id: {param.RayParamsId}`)
		return
	end

	return get_cast_result(param.Position, Below * param.Distance, ray_param, param, CFrame.new(param.Position))
end

function WorldUtil:IsGrounded(param: {
	Position: Vector3,
	Distance: number,
	RayParamsId: string,
	RayParams: RaycastParams?,
} & CastOptions)
	local raycast_result = self:RayBelow(param)

	return raycast_result ~= nil
end

function WorldUtil:RayFront(param: {
	CFrame: CFrame,
	Distance: number,
	RayParamsId: string,
	RayParams: RaycastParams?,
	Direction: Vector3?,
} & CastOptions)
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

function WorldUtil:RaySide(param: {
	CFrame: CFrame,
	Distance: number,
	RayParamsId: string,
	RayParams: RaycastParams?,
	Direction: Vector3?,
} & CastOptions)
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

function WorldUtil:RayUp(param: {
	CFrame: CFrame,
	Distance: number,
	RayParamsId: string,
	RayParams: RaycastParams?,
	Direction: Vector3?,
} & CastOptions)
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

function WorldUtil:GetGroundPosition(param: {
	Position: Vector3,
	Distance: number,
	RayParamsId: string,
	RayParams: RaycastParams?,
} & CastOptions)
	local raycast_result = self:RayBelow(param)

	if not raycast_result then
		return nil
	end

	return raycast_result.Position
end

function WorldUtil:GetGroundNormal(param: {
	Position: Vector3,
	Distance: number,
	RayParamsId: string,
	RayParams: RaycastParams?,
} & CastOptions)
	local raycast_result = self:RayBelow(param)

	if not raycast_result then
		return nil
	end

	return raycast_result.Normal
end

function WorldUtil:GetPartsInRadius(param: {
	Center: Vector3,
	Radius: number,
	OverlapParamsId: string,
	OverlapParams: OverlapParams?,
})
	local overlap_param = param.OverlapParams or self:GetOverlapParams(param.OverlapParamsId)

	return workspace:GetPartBoundsInRadius(param.Center, param.Radius, overlap_param)
end

function WorldUtil:GetPartsInBox(param: {
	CFrame: CFrame,
	Size: Vector3,
	OverlapParamsId: string,
	OverlapParams: OverlapParams?,
})
	local overlap_param = param.OverlapParams or self:GetOverlapParams(param.OverlapParamsId)

	return workspace:GetPartBoundsInBox(param.CFrame, param.Size, overlap_param)
end

function WorldUtil:GetPartsInPart(param: {
	Part: BasePart,
	OverlapParamsId: string,
	OverlapParams: OverlapParams?,
})
	local overlap_param = param.OverlapParams or self:GetOverlapParams(param.OverlapParamsId)

	return workspace:GetPartsInPart(param.Part, overlap_param)
end

function WorldUtil:GetNearest(param: {
	Origin: Vector3,
	Instances: { BasePart | Model },
})
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

function WorldUtil:GetNearestPart(param: {
	Origin: Vector3,
	Instances: { BasePart | Model },
})
	return self:GetNearest(param)
end

function WorldUtil:GetNearestPoint(origin: Vector3, points: { Vector3 })
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

function WorldUtil:WorldToScreen(world_position: Vector3, camera: Camera?)
	local active_camera = camera or workspace.CurrentCamera

	if not active_camera then
		return nil
	end

	local screen_position, on_screen = active_camera:WorldToViewportPoint(world_position)
	return Vector2.new(screen_position.X, screen_position.Y), on_screen
end

function WorldUtil:ScreenToWorld(screen_position: Vector2, depth: number, camera: Camera?)
	local active_camera = camera or workspace.CurrentCamera

	if not active_camera then
		return nil
	end

	local ray = active_camera:ViewportPointToRay(screen_position.X, screen_position.Y)
	return ray.Origin + ray.Direction * depth
end

return WorldUtil
