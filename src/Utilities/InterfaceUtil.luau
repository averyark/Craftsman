--!nonstrict
--[[
    FileName    > InterfaceUtil.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 17/07/2026
--]]

const RunService = game:GetService("RunService")
const GuiService = game:GetService("GuiService")

const Config = require("../Config")
const PrintUtil = require("./PrintUtil")

--[=[
	@class InterfaceUtil
	Resolution-independent interface scaling. Drives a UIScale from the viewport so a layout
	authored at one reference resolution holds up across phones, desktops and consoles.
]=]
--
local InterfaceUtil = {}

export type ScaleMode = "Fit" | "Height" | "Width" | "Diagonal"

export type ScaleOptions = {
	Reference: Vector2?,
	Mode: ScaleMode?,
	Min: number?,
	Max: number?,
	Damping: number?,
	Boost: number?,
}

local active_bindings: { [Instance]: () -> () } = {}

--
local function resolve_options(options: ScaleOptions?): ScaleOptions
	local given = options or {}
	local defaults = Config.INTERFACE

	return {
		Reference = given.Reference or defaults.REFERENCE,
		Mode = given.Mode or defaults.MODE,
		Min = given.Min or defaults.MIN_SCALE,
		Max = given.Max or defaults.MAX_SCALE,
		Damping = given.Damping or defaults.DAMPING,
		Boost = given.Boost or 1,
	}
end
--

--[=[
	Returns the UIScale factor for a viewport, as a pure function of its arguments.

	Modes: `Fit` never overflows either axis, `Height` follows vertical space alone, `Width`
	follows horizontal, `Diagonal` degrades most evenly across unusual aspect ratios.

	`Damping` below 1 lifts small screens: a phone at a third of the reference height scales
	to 0.46 rather than 0.33, which keeps touch targets reachable. `Boost` is an
	environmental multiplier, applied before clamping.

	A viewport or reference with a non-positive axis returns `Min` rather than dividing by
	zero -- the client reports (0, 0) or (1, 1) for a frame or two during boot.

	@param viewport Vector2 -- The current viewport size.
	@param options ScaleOptions? -- Overrides for the configured defaults.
	@return number -- The scale, clamped to [Min, Max].
]=]
--
function InterfaceUtil.ComputeScale(viewport: Vector2, options: ScaleOptions?): number
	local resolved = resolve_options(options)
	local reference = resolved.Reference

	--
	if viewport.X <= 0 or viewport.Y <= 0 or reference.X <= 0 or reference.Y <= 0 then
		return resolved.Min
	end
	--

	--
	local base
	local mode = resolved.Mode

	if mode == "Height" then
		base = viewport.Y / reference.Y
	elseif mode == "Width" then
		base = viewport.X / reference.X
	elseif mode == "Diagonal" then
		base = viewport.Magnitude / reference.Magnitude
	else
		base = math.min(viewport.X / reference.X, viewport.Y / reference.Y)
	end
	--

	--
	if resolved.Damping ~= 1 then
		base ^= resolved.Damping
	end
	--

	return math.clamp(base * resolved.Boost, resolved.Min, resolved.Max)
end

--[=[
	Binds a UIScale on `target` to the viewport, and keeps it bound.

	Rebinds when workspace.CurrentCamera is replaced, which a plain ViewportSize connection
	silently misses. Calling this twice on one target replaces the first binding rather than
	stacking a second UIScale and a second set of connections.

	The returned function undoes everything: it destroys the UIScale if this created one, or
	restores the previous Scale if one was already there. Pass it to a Keeper.

	@param target Instance -- The ScreenGui or GuiObject to scale.
	@param options ScaleOptions? -- Overrides for the configured defaults.
	@return () -> () -- Unbinds and restores.
]=]
--
function InterfaceUtil:AutoScale(target: Instance, options: ScaleOptions?): () -> ()
	--
	if RunService:IsServer() then
		PrintUtil:Error("InterfaceUtil:AutoScale is client-only; there is no viewport on the server.", 2)
	end
	--

	--
	local existing = active_bindings[target]

	if existing then
		existing()
	end
	--

	--
	local scale = target:FindFirstChildWhichIsA("UIScale")
	local created = scale == nil
	local previous = if scale then scale.Scale else nil

	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = target
	end
	--

	--
	local bound = table.clone(options or {})

	if bound.Boost == nil then
		bound.Boost = if GuiService:IsTenFootInterface() then Config.INTERFACE.TEN_FOOT_BOOST else 1
	end
	--

	local viewport_connection = nil

	--
	local function apply()
		local camera = workspace.CurrentCamera

		if not camera then
			return
		end

		scale.Scale = InterfaceUtil.ComputeScale(camera.ViewportSize, bound)
	end
	--

	--
	local function bind_camera()
		if viewport_connection then
			viewport_connection:Disconnect()
			viewport_connection = nil
		end

		local camera = workspace.CurrentCamera
		
		if not camera then
			return
		end

		viewport_connection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(apply)
		apply()
	end
	--

	local camera_connection = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bind_camera)
	bind_camera()

	--
	local function unbind()
		if active_bindings[target] ~= nil then
			active_bindings[target] = nil
		end

		camera_connection:Disconnect()

		if viewport_connection then
			viewport_connection:Disconnect()
			viewport_connection = nil
		end

		if created then
			scale:Destroy()
		elseif scale.Parent then
			scale.Scale = previous
		end
	end
	--

	active_bindings[target] = unbind
	return unbind
end

return InterfaceUtil
