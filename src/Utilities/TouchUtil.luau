--!nonstrict
--[[
    FileName    > TouchUtil.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 03/08/2026
--]]

const Players = game:GetService("Players")
const RunService = game:GetService("RunService")
const UserInputService = game:GetService("UserInputService")

const Keeper = require("../../../../Keeper")
const Config = require("../Config")
const Signal = require("../Signal")
const InputStore = require("../Store/InputStore")
const InputUtil = require("./InputUtil")
const InterfaceUtil = require("./InterfaceUtil")
const PrintUtil = require("./PrintUtil")

--[=[
	@class TouchUtil
	On-screen buttons that drive `InputUtil` actions.

	A touch button is a *source* for an action name, not an input system of its own -- the same
	`InputUtil.Began` handler serves the keyboard, the gamepad and the button, so gameplay code
	never branches on device. Buttons live in a lazily created ScreenGui scaled by
	`InterfaceUtil`, lay out into named zones, and hide themselves when the player is not on
	touch.

	```lua
	InputUtil.SetPrimitiveBinding("Dash", { Enum.KeyCode.Q })

	local dash = self.Keeper:Add(TouchUtil.Button("Dash", {
		Text = "Dash",
		Zone = "BottomRight",
		VisibleWhen = { Combat = true },
	}))

	TouchUtil.SetContext("Combat", true)
	```

	Players can rearrange the pad in edit mode. Craftsman does not persist the result: read it
	with `GetLayout`, store it wherever your game stores player data, and hand it back to
	`ApplyLayout` on rejoin.

	```lua
	TouchUtil.LayoutChanged:Connect(function()
		SaveTouchLayout(TouchUtil.GetLayout())
	end)

	TouchUtil.SetEditMode(true)
	```
]=]
--
local TouchUtilModule = {}

export type Zone =
	"TopLeft"
	| "Top"
	| "TopRight"
	| "Left"
	| "Center"
	| "Right"
	| "BottomLeft"
	| "Bottom"
	| "BottomRight"

export type ButtonOptions = {
	Icon: string?,
	Overlay: string?,
	OverlayTransparency: number?,
	OverlayScale: number?,
	OverlayOffset: number?,
	Text: string?,
	Zone: Zone?,
	Order: number?,
	Position: UDim2?,
	Size: number?,
	Sink: boolean?,
	IsNormalImage: boolean?,
	ShowOn: { InputUtil.DeviceType }?,
	VisibleWhen: { [string]: boolean }?,
	Adopt: GuiObject?,
	LayoutId: string?,
	Movable: boolean?,
	Resizable: boolean?,
	MinSize: number?,
	MaxSize: number?,
}

--[[
	Size is stored as a multiplier over the button's own base rather than in pixels. Craftsman's
	buttons are authored against BASE_SIZE; an adopted CoreGui button's base is whatever Roblox
	rendered it at, which differs per device. A multiplier means the same thing for both.
]]
export type LayoutEntry = {
	Position: { X: number, Y: number }?,
	Scale: number?,
}

export type Layout = {
	Version: number,
	Entries: { [string]: LayoutEntry },
}

const TouchConfig = Config.TOUCH

const ZONE_LAYOUTS: { [Zone]: { anchor: Vector2, scale: Vector2, horizontal: Enum.HorizontalAlignment } } = {
	TopLeft = { anchor = Vector2.new(0, 0), scale = Vector2.new(0, 0), horizontal = Enum.HorizontalAlignment.Left },
	Top = { anchor = Vector2.new(0.5, 0), scale = Vector2.new(0.5, 0), horizontal = Enum.HorizontalAlignment.Center },
	TopRight = { anchor = Vector2.new(1, 0), scale = Vector2.new(1, 0), horizontal = Enum.HorizontalAlignment.Right },
	Left = { anchor = Vector2.new(0, 0.5), scale = Vector2.new(0, 0.5), horizontal = Enum.HorizontalAlignment.Left },
	Center = {
		anchor = Vector2.new(0.5, 0.5),
		scale = Vector2.new(0.5, 0.5),
		horizontal = Enum.HorizontalAlignment.Center,
	},
	Right = { anchor = Vector2.new(1, 0.5), scale = Vector2.new(1, 0.5), horizontal = Enum.HorizontalAlignment.Right },
	BottomLeft = { anchor = Vector2.new(0, 1), scale = Vector2.new(0, 1), horizontal = Enum.HorizontalAlignment.Left },
	Bottom = {
		anchor = Vector2.new(0.5, 1),
		scale = Vector2.new(0.5, 1),
		horizontal = Enum.HorizontalAlignment.Center,
	},
	BottomRight = {
		anchor = Vector2.new(1, 1),
		scale = Vector2.new(1, 1),
		horizontal = Enum.HorizontalAlignment.Right,
	},
}

const PRESS_INPUT_TYPES: { [Enum.UserInputType]: boolean } = {
	[Enum.UserInputType.Touch] = true,
	[Enum.UserInputType.MouseButton1] = true,
}

const DRAG_INPUT_TYPES: { [Enum.UserInputType]: boolean } = {
	[Enum.UserInputType.Touch] = true,
	[Enum.UserInputType.MouseMovement] = true,
}

const DEFAULT_SHOW_ON: { [string]: boolean } = table.freeze({ Touch = true })
const CENTRE_ANCHOR = Vector2.new(0.5, 0.5)

local Root = nil :: ScreenGui?
local RootScale = nil :: UIScale?
local RootKeeper = nil :: any
local ZoneNextOrder: { [Zone]: number } = {}
local ZoneOffsets: { [Zone]: Vector2 } = {}
local PlayerGuiRef = nil :: Instance?
local ControlsKeeper = nil :: any
local AdoptedJump = nil :: any
local DefaultSize = nil :: number?
local Buttons: { [any]: boolean } = {}
local ButtonsByLayoutId: { [string]: any } = {}
local Contexts: { [string]: boolean } = {}
local ButtonsByContext: { [string]: { [any]: boolean } } = {}
local Drags: { [any]: any } = {}
local Claims: { [any]: any } = {}
local MouseDrag = nil :: any
local DeviceType: InputUtil.DeviceType = "KeyboardMouse"
local EditMode = false
local Grid = nil :: number?

--[=[
	@prop ContextChanged Signal -- Fired with (context, state, previous) whenever a context flips.
	@within TouchUtil
]=]
--
TouchUtilModule.ContextChanged = Signal.new()

--[=[
	@prop EditModeChanged Signal -- Fired with the new edit-mode state.
	@within TouchUtil
]=]
--
TouchUtilModule.EditModeChanged = Signal.new()

--[=[
	@prop LayoutChanged Signal -- Fired with (layout_id, entry) when a drag or resize settles.
	@within TouchUtil
]=]
--
TouchUtilModule.LayoutChanged = Signal.new()

--
local function assert_client(method_name: string)
	if not RunService:IsServer() then
		return
	end

	PrintUtil:Error(`TouchUtil.{method_name} is client-only; there is no PlayerGui on the server.`, 3)
end

local function assert_zone(zone: Zone, method_name: string)
	if ZONE_LAYOUTS[zone] then
		return
	end

	PrintUtil:Error(`TouchUtil.{method_name}: "{tostring(zone)}" is not a zone.`, 3)
end

local function get_scale_factor(): number
	if RootScale then
		return RootScale.Scale
	end

	return 1
end

local function input_position(input_object: any): Vector2
	return Vector2.new(input_object.Position.X, input_object.Position.Y)
end
--

local TouchButton = {}
TouchButton.__index = TouchButton

--
--[[
	One input object belongs to one button until it is released.

	GuiObject.InputBegan fires when an input *enters* the region, not only when it starts there,
	so without this a finger already dragging one button claims every button it passes over -- and
	outside edit mode, sliding across the pad fires every action it crosses. A second finger is a
	distinct InputObject and is unaffected, so multitouch still works.
]]
local function claim_input(self: any, input_object: any): boolean
	if input_object == nil then
		return true
	end

	if Claims[input_object] ~= nil then
		return false
	end

	Claims[input_object] = self
	return true
end

local function release_claim(input_object: any)
	if input_object == nil then
		return
	end

	Claims[input_object] = nil
end

local function overlay_transparency(self: any): number
	if not self.Enabled then
		return TouchConfig.DISABLED_TRANSPARENCY
	end

	if self._Pressed then
		return math.clamp(self._OverlayTransparency - TouchConfig.OVERLAY_PRESS_DELTA, 0, 1)
	end

	return self._OverlayTransparency
end

local function refresh_overlay(self: any)
	if not self._Overlay then
		return
	end

	self._Overlay.ImageTransparency = overlay_transparency(self)
end

local function ensure_overlay(self: any): ImageLabel
	if self._Overlay then
		return self._Overlay
	end

	local overlay = Instance.new("ImageLabel")
	overlay.Name = "Overlay"
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.ScaleType = Enum.ScaleType.Fit
	overlay.AnchorPoint = CENTRE_ANCHOR
	overlay.Position = UDim2.fromScale(0.5, 0.5)
	overlay.Size = UDim2.new(self._OverlayScale, self._OverlayOffset, self._OverlayScale, self._OverlayOffset)
	overlay.ImageTransparency = overlay_transparency(self)
	overlay.ZIndex = self.Instance.ZIndex + 1
	overlay.Parent = self.Instance

	self._Overlay = self.Keeper:Add(overlay)
	return overlay
end
--

--
local function press(self: any, input_object: InputObject)
	if self._Pressed then
		return
	end

	if not claim_input(self, input_object) then
		return
	end

	self._Pressed = true
	self._PressInput = input_object

	if not self.IsNormalImage then
		self.Instance.ImageRectOffset = TouchConfig.RECT_OFFSET_PRESSED
	end

	if self._Label then
		self._Label.TextColor3 = TouchConfig.LABEL_COLOR_PRESSED
	end

	refresh_overlay(self)

	if not self.IsAdopted then
		InputUtil.SetActionState(self.Action, true, self, input_object)
	end

	self.Pressed:Fire(input_object)
end

local function release(self: any, input_object: any)
	if not self._Pressed then
		return
	end

	release_claim(self._PressInput)

	self._Pressed = false
	self._PressInput = nil

	if not self.IsNormalImage then
		self.Instance.ImageRectOffset = TouchConfig.RECT_OFFSET_IDLE
	end

	if self._Label then
		self._Label.TextColor3 = TouchConfig.LABEL_COLOR_IDLE
	end

	refresh_overlay(self)

	if not self.IsAdopted then
		InputUtil.SetActionState(self.Action, false, self, input_object)
	end

	self.Released:Fire(input_object)
end
--

--
local function index_contexts(self: any, previous: { [string]: boolean }?)
	if previous then
		for context in previous do
			local set = ButtonsByContext[context]
			if set then
				set[self] = nil
			end
		end
	end

	for context in self._VisibleWhen do
		local set = ButtonsByContext[context]

		if set == nil then
			set = {}
			ButtonsByContext[context] = set
		end

		set[self] = true
	end
end

local function contexts_satisfied(self: any): boolean
	for context, expected in self._VisibleWhen do
		if (Contexts[context] == true) ~= expected then
			return false
		end
	end

	return true
end
--

--
local function apply_size(self: any, size: number): number
	local clamped = math.clamp(size, self.MinSize, self.MaxSize)
	local scale = clamped / self._BaseSize

	self._LayoutSize = clamped
	self._Scale.Scale = scale

	if self._Handle then
		local handle = TouchConfig.HANDLE_SIZE / (if scale > 0 then scale else 1)
		self._Handle.Size = UDim2.fromOffset(handle, handle)
	end

	return clamped
end

--[[
	An adopted button is positioned inside whatever already owns it -- the CoreGui
	TouchControlFrame, for the jump button -- so every measurement is taken against that container
	rather than this layer's ScreenGui. Reparenting it here would move it out of TouchGui and take
	its behaviour with it.
]]
local function viewport_size(): Vector2
	local camera = workspace.CurrentCamera

	if camera and camera.ViewportSize.X > 0 then
		return camera.ViewportSize
	end

	return Vector2.new(1, 1)
end

local function absolute_centre(instance: any): Vector2
	return instance.AbsolutePosition + instance.AbsoluteSize / 2
end

--[[
	Positions an instance by its centre in screen pixels, whatever container it happens to sit in.
	The edit proxy lives in this layer's ScreenGui and the real jump button lives in CoreGui's
	TouchControlFrame; the two have different insets, so a scale position copied straight across
	would land in the wrong place.
]]
local function apply_absolute_centre(instance: any, centre: Vector2)
	local parent = instance.Parent

	if parent == nil then
		return
	end

	local size = parent.AbsoluteSize

	if size.X <= 0 or size.Y <= 0 then
		return
	end

	local relative = centre - parent.AbsolutePosition

	instance.AnchorPoint = CENTRE_ANCHOR
	instance.Position = UDim2.fromScale(relative.X / size.X, relative.Y / size.Y)
end

local function layout_container(self: any): any
	if self.IsAdopted and self.Instance.Parent then
		return self.Instance.Parent
	end

	return Root
end

local function current_centre_scale(self: any): Vector2
	local container = layout_container(self)
	local root_size = container.AbsoluteSize
	local instance = self.Instance
	local centre = instance.AbsolutePosition + instance.AbsoluteSize / 2 - container.AbsolutePosition

	if root_size.X <= 0 or root_size.Y <= 0 then
		return Vector2.new(0.5, 0.5)
	end

	return Vector2.new(centre.X / root_size.X, centre.Y / root_size.Y)
end

local function place_at_scale(self: any, position: Vector2)
	local instance = self.Instance

	self.Zone = nil
	self.Position = UDim2.fromScale(position.X, position.Y)
	self._LayoutPosition = position

	instance.AnchorPoint = CENTRE_ANCHOR
	instance.Position = self.Position

	if not self.IsAdopted then
		instance.Parent = Root
	end
end

local function snap_and_clamp(self: any, position: Vector2): Vector2
	local root_size = layout_container(self).AbsoluteSize

	if root_size.X <= 0 or root_size.Y <= 0 then
		return position
	end

	local x = position.X
	local y = position.Y
	local grid = Grid or TouchConfig.EDIT_GRID

	if grid > 0 then
		local step = grid * get_scale_factor()
		x = math.round(x * root_size.X / step) * step / root_size.X
		y = math.round(y * root_size.Y / step) * step / root_size.Y
	end

	local half = self.Instance.AbsoluteSize / 2
	local half_x = math.min(half.X / root_size.X, 0.5)
	local half_y = math.min(half.Y / root_size.Y, 0.5)

	return Vector2.new(math.clamp(x, half_x, 1 - half_x), math.clamp(y, half_y, 1 - half_y))
end
--

--
local function apply_move(drag: any, delta: Vector2)
	local self = drag.button
	local root_size = layout_container(self).AbsoluteSize

	if root_size.X <= 0 or root_size.Y <= 0 then
		return
	end

	local moved = drag.origin_position + Vector2.new(delta.X / root_size.X, delta.Y / root_size.Y)
	place_at_scale(self, snap_and_clamp(self, moved))
end

local function apply_resize(drag: any, delta: Vector2)
	local self = drag.button
	--[[
		The handle sits at the bottom-left, so the button grows as the handle is dragged left and
		down -- X is inverted against the drag delta, Y is not.
	]]
	local factor = get_scale_factor()
	local growth = (-delta.X + delta.Y) / 2 / (if factor > 0 then factor else 1)

	apply_size(self, drag.origin_size + growth)

	--[[
		Resizing has to re-clamp, or growing a button near an edge pushes it off screen. Read the
		live centre when there is no stored one: a button that has been resized but never dragged
		has no _LayoutPosition yet, and an adopted button never has one until its first move.
	]]
	if self.Zone then
		return
	end

	place_at_scale(self, snap_and_clamp(self, self._LayoutPosition or current_centre_scale(self)))
end

local function finish_drag(drag: any)
	local self = drag.button

	self._DragInput = nil
	self.IsCustomised = true

	if drag.kind == "Resize" then
		self.Resized:Fire(self._LayoutSize)
	else
		self.Moved:Fire(self.Position)
	end

	TouchUtilModule.LayoutChanged:Fire(self.LayoutId, self:GetLayout())
end

local function cancel_drags_for(self: any)
	for input_object, drag in Drags do
		if drag.button ~= self then
			continue
		end
		Drags[input_object] = nil
		release_claim(input_object)
	end

	if MouseDrag and MouseDrag.button == self then
		MouseDrag = nil
	end

	self._DragInput = nil
	self._HandleInput = nil
end

local function end_drag(input_object: any)
	local drag = Drags[input_object]

	if drag == nil then
		return nil
	end

	Drags[input_object] = nil
	release_claim(input_object)

	if MouseDrag == drag then
		MouseDrag = nil
	end

	return drag
end

--[[
	A touch InputObject reports its own Change events, so a drag can be keyed on identity. A mouse
	does not: the press arrives as MouseButton1 and the movement as a separate MouseMovement
	object, so identity matching silently never fires and the button neither drags nor acts.
]]
local function find_drag(input_object: any): any
	local drag = Drags[input_object]

	if drag then
		return drag
	end

	if input_object.UserInputType ~= Enum.UserInputType.MouseMovement then
		return nil
	end

	return MouseDrag
end

local function begin_drag(self: any, input_object: any, kind: string)
	if self._DragInput then
		return
	end

	if not claim_input(self, input_object) then
		return
	end

	self._DragInput = input_object

	local drag = {
		button = self,
		kind = kind,
		started = false,
		origin_input = input_position(input_object),
		origin_position = current_centre_scale(self),
		origin_size = self._LayoutSize,
	}

	Drags[input_object] = drag

	if input_object.UserInputType == Enum.UserInputType.MouseButton1 then
		MouseDrag = drag
	end
end

local function begin_edit_drag(self: any, input_object: any): boolean
	if not PRESS_INPUT_TYPES[input_object.UserInputType] then
		return false
	end

	if not EditMode or not self.Movable then
		return false
	end

	if input_object == self._HandleInput then
		return false
	end

	begin_drag(self, input_object, "Move")
	return true
end

--

--
--[[
	Dragging the real jump button would otherwise jump, and dragging anything would otherwise pan
	the camera, so edit mode turns the default control module off for its duration. This is also
	what a player expects: the character should hold still while its controls are rearranged.
]]
local function set_default_controls(enabled: boolean)
	local scripts = Players.LocalPlayer:FindFirstChild("PlayerScripts")

	if scripts == nil then
		return
	end

	local module = scripts:FindFirstChild("PlayerModule")

	if module == nil then
		return
	end

	local ok, controls = pcall(function()
		return require(module):GetControls()
	end)

	if not ok or controls == nil then
		return
	end

	if enabled then
		pcall(function()
			controls:Enable()
		end)
		return
	end

	pcall(function()
		controls:Disable()
	end)
end

local function find_default_jump(): ImageButton?
	if PlayerGuiRef == nil then
		return nil
	end

	local touch_gui = PlayerGuiRef:FindFirstChild("TouchGui")

	if touch_gui == nil then
		return nil
	end

	local controls = touch_gui:FindFirstChild("TouchControlFrame")

	if controls == nil then
		return nil
	end

	local jump = controls:FindFirstChild("JumpButton")

	if jump and jump:IsA("ImageButton") then
		return jump
	end

	return nil
end

--[[
	Buttons default to the size of Roblox's jump button rather than a constant, so a pad that sits
	beside it reads as one set of controls. Measured in device pixels and divided back through this
	layer's own UIScale, since button sizes are authored in reference pixels. Only a real
	measurement is cached; a zero AbsoluteSize before the first render falls through to the config
	default without being remembered.
]]
local function resolve_default_size(): number
	if DefaultSize then
		return DefaultSize
	end

	if not TouchConfig.MATCH_JUMP_SIZE then
		return TouchConfig.DEFAULT_SIZE
	end

	local source = find_default_jump()

	if source == nil then
		return TouchConfig.DEFAULT_SIZE
	end

	local measured = source.AbsoluteSize.Y / get_scale_factor()

	if measured <= 0 then
		return TouchConfig.DEFAULT_SIZE
	end

	DefaultSize = measured
	return measured
end

--[[
	A zone is an origin and a slot index, not a live layout.

	Zones used to be frames running a UIListLayout, which meant dragging one button out made every
	other button in the row slide over to close the gap -- the player moved one control and the
	rest moved themselves. A slot is now derived from the button's Order alone, so it depends on
	nothing that can change: hiding, resizing, dragging or destroying a neighbour leaves every
	other button exactly where the player last saw it.

	The cost is that a removed button leaves a hole rather than the row closing up. That is the
	intended trade -- muscle memory beats tidiness on a control pad.
]]
local function place_in_zone(self: any, zone: Zone)
	local layout = ZONE_LAYOUTS[zone]
	local margin = TouchConfig.ZONE_MARGIN
	local offset = ZoneOffsets[zone] or Vector2.zero
	local anchor_x = layout.scale.X
	local anchor_y = layout.scale.Y
	local step = resolve_default_size() + TouchConfig.ZONE_PADDING
	local slot = self.Order * step

	local origin_x = margin - anchor_x * margin * 2 + offset.X
	local origin_y = margin - anchor_y * margin * 2 + offset.Y
	local item_anchor = anchor_x
	local x

	if anchor_x == 1 then
		x = origin_x - slot
	else
		x = origin_x + slot
	end

	self.Zone = zone
	self.Position = nil
	self._LayoutPosition = nil

	self.Instance.AnchorPoint = Vector2.new(item_anchor, anchor_y)
	self.Instance.Position = UDim2.new(anchor_x, x, anchor_y, origin_y)
	self.Instance.Parent = Root
end

local function next_zone_order(zone: Zone): number
	local order = ZoneNextOrder[zone] or 0
	ZoneNextOrder[zone] = order + 1
	return order
end

local function reposition_zone(zone: Zone)
	for button in Buttons do
		if button.Zone ~= zone then
			continue
		end
		place_in_zone(button, zone)
	end
end

local function get_root(): ScreenGui
	if Root then
		return Root
	end

	RootKeeper = Keeper.new()
	ControlsKeeper = RootKeeper:Extend()

	local screen_gui = Instance.new("ScreenGui")
	screen_gui.Name = "CraftsmanTouch"
	screen_gui.DisplayOrder = TouchConfig.DISPLAY_ORDER
	screen_gui.ResetOnSpawn = false
	screen_gui.ClipToDeviceSafeArea = false
	screen_gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.FullscreenExtension
	screen_gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	PlayerGuiRef = Players.LocalPlayer:WaitForChild("PlayerGui")
	screen_gui.Parent = PlayerGuiRef

	Root = screen_gui
	RootKeeper:Add(screen_gui)

	--[[
		Off by default. This pad sits beside Roblox's touch controls, which carry no UIScale and
		are already sized per device, so scaling it too fights them -- and InterfaceUtil's MIN_SCALE
		clamp renders the whole layer at half size on a phone viewport. Every size here is in
		device pixels, matching the CoreGui controls. Opt in only if the pad is meant to scale with
		the rest of your UI rather than with the controls.
	]]
	if TouchConfig.AUTO_SCALE then
		RootKeeper:Add(InterfaceUtil:AutoScale(screen_gui))
		RootScale = screen_gui:FindFirstChildOfClass("UIScale")
	end

	DeviceType = InputStore:getState().DeviceType

	RootKeeper:Connect(PlayerGuiRef.ChildAdded, function()
		if AdoptedJump == nil or EditMode then
			return
		end

		task.defer(function()
			AdoptedJump:_ApplyAdoptedLayout()
		end)
	end)

	RootKeeper:Add(InputStore:subscribe(function(state)
		return state.DeviceType
	end, function(device: InputUtil.DeviceType)
		DeviceType = device

		for button in Buttons do
			button:_Resolve()
		end
	end))

	RootKeeper:Connect(UserInputService.InputChanged, function(input_object: InputObject)
		if not DRAG_INPUT_TYPES[input_object.UserInputType] then
			return
		end

		local drag = find_drag(input_object)

		if drag == nil then
			return
		end

		local delta = input_position(input_object) - drag.origin_input

		if not drag.started then
			if delta.Magnitude < TouchConfig.DRAG_THRESHOLD then
				return
			end
			drag.started = true
		end

		if drag.kind == "Resize" then
			apply_resize(drag, delta)
		else
			apply_move(drag, delta)
		end
	end)

	RootKeeper:Connect(UserInputService.InputEnded, function(input_object: InputObject)
		local drag = end_drag(input_object)

		if drag == nil then
			return
		end

		drag.button._HandleInput = nil

		if not drag.started then
			drag.button._DragInput = nil
			return
		end

		finish_drag(drag)
	end)

	return screen_gui
end
--

local function new(action_name: string, options: ButtonOptions?)
	assert_client("Button")

	local given = options or {}
	local self = setmetatable({}, TouchButton)

	self.Action = action_name
	self.Zone = given.Zone
	self.Icon = given.Icon or TouchConfig.DEFAULT_ASSET
	self.Text = given.Text
	self.Enabled = true
	self.IsNormalImage = given.IsNormalImage == true
	self.LayoutId = given.LayoutId or action_name
	self.Movable = given.Movable ~= false
	self.Resizable = given.Resizable ~= false
	self.MinSize = given.MinSize or TouchConfig.MIN_SIZE
	self.MaxSize = given.MaxSize or TouchConfig.MAX_SIZE
	self.IsCustomised = false
	self.Keeper = Keeper.new()

	self.Pressed = self.Keeper:Add(Signal.new())
	self.Released = self.Keeper:Add(Signal.new())
	self.Moved = self.Keeper:Add(Signal.new())
	self.Resized = self.Keeper:Add(Signal.new())

	self._Pressed = false
	self._PressInput = nil
	self._DragInput = nil
	self._HandleInput = nil
	self._EditApplied = false
	self._Visible = true
	self._VisibleWhen = table.clone(given.VisibleWhen or {})
	self._ShowOn = DEFAULT_SHOW_ON

	if given.ShowOn then
		local allowed = {}
		for i = 1, #given.ShowOn do
			allowed[given.ShowOn[i]] = true
		end
		self._ShowOn = allowed
	end

	if ButtonsByLayoutId[self.LayoutId] then
		PrintUtil:Warn(
			`TouchUtil.Button: layout id "{self.LayoutId}" is already taken. Saved layouts key on this id, so give one of them an explicit LayoutId.`
		)
	end

	local root = get_root()

	local button

	if given.Adopt then
		button = given.Adopt
		self.IsAdopted = true
		self.IsNormalImage = true
	else
		button = Instance.new("ImageButton")
		button.BackgroundTransparency = 1
		button.BorderSizePixel = 0
		button.ScaleType = if self.IsNormalImage then Enum.ScaleType.Fit else Enum.ScaleType.Slice
		button.Image = self.Icon

		if not self.IsNormalImage then
			button.ImageRectSize = TouchConfig.RECT_SIZE
			button.ImageRectOffset = TouchConfig.RECT_OFFSET_IDLE
		end
	end

	if self.IsAdopted then
		self._BaseSize = if button.AbsoluteSize.Y > 0 then button.AbsoluteSize.Y else TouchConfig.DEFAULT_SIZE
		self.MinSize = given.MinSize or self._BaseSize * 0.6
		self.MaxSize = given.MaxSize or self._BaseSize * 2
	else
		self._BaseSize = TouchConfig.BASE_SIZE
		button.Name = action_name
		button.Size = UDim2.fromOffset(TouchConfig.BASE_SIZE, TouchConfig.BASE_SIZE)
		button.AnchorPoint = Vector2.zero
		button.Active = given.Sink == true
		button.Visible = false
	end

	button.LayoutOrder = given.Order or 0
	self.Order = given.Order or 0

	self.Instance = if self.IsAdopted then button else self.Keeper:Add(button)

	local button_scale = button:FindFirstChildOfClass("UIScale")

	if button_scale == nil then
		button_scale = Instance.new("UIScale")
		button_scale.Name = "Scale"
		button_scale.Parent = button
		self.Keeper:Add(button_scale)
	end

	self._Scale = button_scale
	self._LayoutPosition = nil
	self._SinkDefault = button.Active

	local size = apply_size(self, given.Size or (if self.IsAdopted then self._BaseSize else resolve_default_size()))

	self.Overlay = given.Overlay
	self._OverlayTransparency = given.OverlayTransparency or TouchConfig.OVERLAY_TRANSPARENCY
	self._OverlayScale = given.OverlayScale or TouchConfig.OVERLAY_SCALE
	self._OverlayOffset = given.OverlayOffset or TouchConfig.OVERLAY_OFFSET

	if self.Overlay then
		ensure_overlay(self).Image = self.Overlay
	end

	if self.Text then
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
		label.TextTransparency = 0.3
		label.TextColor3 = TouchConfig.LABEL_COLOR_IDLE
		label.TextSize = TouchConfig.LABEL_TEXT_SIZE
		label.TextWrapped = true
		label.Text = self.Text
		label.Size = UDim2.fromScale(1, 1)
		label.AnchorPoint = CENTRE_ANCHOR
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.ZIndex = button.ZIndex + 2
		label.Parent = button

		self._Label = label
	end

	if self.IsAdopted then
		self.Zone = nil
		self.Position = button.Position
	elseif given.Position then
		self.Position = given.Position
		self._LayoutPosition = Vector2.new(given.Position.X.Scale, given.Position.Y.Scale)
		button.AnchorPoint = CENTRE_ANCHOR
		button.Position = given.Position
		button.Parent = root
	else
		local zone = self.Zone or "BottomRight"
		assert_zone(zone, "Button")

		if given.Order == nil then
			self.Order = next_zone_order(zone)
		end

		place_in_zone(self, zone)
	end

	self._Default = {
		Zone = self.Zone,
		Order = self.Order,
		Position = self.Position,
		Size = size,
	}

	self.Keeper:Connect(button.InputBegan, function(input_object: InputObject)
		if not PRESS_INPUT_TYPES[input_object.UserInputType] then
			return
		end
		if not self.Enabled or not button.Visible then
			return
		end

		if EditMode then
			begin_edit_drag(self, input_object)
			return
		end

		if self.IsAdopted or self._PressInput then
			return
		end

		press(self, input_object)
	end)

	self.Keeper:Connect(button.InputEnded, function(input_object: InputObject)
		if input_object ~= self._PressInput then
			return
		end

		release(self, input_object)
	end)

	self.Keeper:Connect(UserInputService.InputEnded, function(input_object: InputObject)
		if input_object ~= self._PressInput then
			return
		end

		release(self, input_object)
	end)

	self.Keeper:Connect(UserInputService.WindowFocusReleased, function()
		release(self, nil)
		cancel_drags_for(self)
	end)

	Buttons[self] = true
	ButtonsByLayoutId[self.LayoutId] = self
	index_contexts(self)
	self:_Resolve()

	if EditMode then
		self:_ApplyEditMode()
	end

	return self
end

export type TouchButton = typeof(new(...))

function TouchButton._Resolve(self: TouchButton)
	if self.IsAdopted then
		return
	end

	local visible = self._Visible and self._ShowOn[DeviceType] == true and contexts_satisfied(self)

	if self.Instance.Visible == visible then
		return
	end

	self.Instance.Visible = visible

	if not visible then
		release(self, nil)
		cancel_drags_for(self)
	end
end

--[[
	Edit mode disables the default control module, and that takes the whole TouchGui with it -- so
	the real jump button is not on screen to be dragged. Editing therefore happens on a clone that
	lives in this layer: it cannot trigger a jump, and nothing else can switch it off. On the way
	out the clone's final rect is handed back to the real button and the clone is discarded.
]]
function TouchButton._BeginProxy(self: TouchButton)
	if self._Proxy or not self.IsAdopted then
		return
	end

	local real = self.Instance
	local rect = real.AbsoluteSize
	local centre = absolute_centre(real)

	local proxy = real:Clone()
	proxy.Name = `{real.Name}EditProxy`
	proxy.Active = true
	proxy.Visible = true
	proxy.Size = UDim2.fromOffset(rect.X, rect.Y)
	proxy.Parent = Root

	local proxy_scale = proxy:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	proxy_scale.Scale = 1
	proxy_scale.Parent = proxy

	self._Real = real
	self._Proxy = proxy
	self.Instance = proxy
	self._Scale = proxy_scale
	self._BaseSize = if rect.Y > 0 then rect.Y else TouchConfig.DEFAULT_SIZE
	self._LayoutSize = self._BaseSize
	self._ProxyKeeper = Keeper.new()

	apply_absolute_centre(proxy, centre)

	--[[
		The constructor's InputBegan is bound to the real instance, which is off screen for the
		duration of edit mode -- so without this the proxy could be resized (its handle is a child
		of the proxy) but never dragged.
	]]
	self._ProxyKeeper:Connect(proxy.InputBegan, function(input_object: InputObject)
		begin_edit_drag(self, input_object)
	end)
end

function TouchButton._CommitProxy(self: TouchButton)
	if self._Proxy == nil then
		return
	end

	local viewport = viewport_size()
	local centre = absolute_centre(self._Proxy)

	self._JumpCentre = Vector2.new(centre.X / viewport.X, centre.Y / viewport.Y)
	self._JumpScale = self._Scale.Scale

	self._ProxyKeeper:Destroy()
	self._ProxyKeeper = nil
	self._Proxy:Destroy()
	self._Proxy = nil
	self._Outline = nil
	self._Handle = nil
	self._HandleInput = nil
	self.Instance = self._Real
	self._Scale = self._Real:FindFirstChildOfClass("UIScale")

	self:_ApplyAdoptedLayout()
end

--[=[
	Re-applies the stored position and size to the real jump button.

	Called after edit mode ends and whenever the CoreGui controls are rebuilt -- re-enabling them
	can replace the button entirely, which would otherwise silently discard the player's layout.
]=]
--
function TouchButton._ApplyAdoptedLayout(self: TouchButton)
	if not self.IsAdopted or self._JumpCentre == nil then
		return
	end

	local real = find_default_jump()

	if real == nil then
		return
	end

	self.Instance = real
	self._Real = real

	local scale = real:FindFirstChildOfClass("UIScale")

	if scale == nil then
		scale = Instance.new("UIScale")
		scale.Name = "Scale"
		scale.Parent = real
	end

	self._Scale = scale
	scale.Scale = self._JumpScale or 1

	local viewport = viewport_size()
	apply_absolute_centre(real, Vector2.new(self._JumpCentre.X * viewport.X, self._JumpCentre.Y * viewport.Y))
end

function TouchButton._BuildEditAffordances(self: TouchButton)
	if self._Outline then
		return
	end

	local outline = Instance.new("UIStroke")
	outline.Name = "EditOutline"
	outline.Color = TouchConfig.EDIT_OUTLINE_COLOR
	outline.Transparency = TouchConfig.EDIT_OUTLINE_TRANSPARENCY
	outline.Thickness = 2
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	outline.Enabled = false
	outline.Parent = self.Instance

	local keeper = self._ProxyKeeper or self.Keeper

	self._Outline = keeper:Add(outline)

	local handle = Instance.new("ImageButton")
	handle.Name = "ResizeHandle"
	handle.BackgroundTransparency = 1
	handle.BorderSizePixel = 0
	handle.Image = TouchConfig.HANDLE_ASSET
	handle.ImageColor3 = TouchConfig.HANDLE_COLOR
	handle.ScaleType = Enum.ScaleType.Fit
	handle.Active = true
	handle.AnchorPoint = Vector2.new(0, 1)
	handle.Position = UDim2.fromScale(0, 1)
	handle.Size = UDim2.fromOffset(TouchConfig.HANDLE_SIZE, TouchConfig.HANDLE_SIZE)
	handle.Visible = false
	handle.ZIndex = self.Instance.ZIndex + 3
	handle.Parent = self.Instance

	self._Handle = keeper:Add(handle)
	apply_size(self, self._LayoutSize)

	keeper:Connect(handle.InputBegan, function(input_object: InputObject)
		if not PRESS_INPUT_TYPES[input_object.UserInputType] then
			return
		end
		if not EditMode or not self.Resizable then
			return
		end

		self._HandleInput = input_object
		begin_drag(self, input_object, "Resize")
	end)
end

function TouchButton._ExitEditMode(self: TouchButton)
	cancel_drags_for(self)

	if self._Proxy then
		self._EditApplied = false
		return
	end

	if not self._EditApplied then
		return
	end

	self._EditApplied = false
	self.Instance.Active = self._SinkDefault
	self._Outline.Enabled = false
	self._Handle.Visible = false
end

function TouchButton._ApplyEditMode(self: TouchButton)
	if not EditMode or (not self.Movable and not self.Resizable) then
		self:_ExitEditMode()
		self:_CommitProxy()
		return
	end

	self:_BeginProxy()
	self:_BuildEditAffordances()
	release(self, nil)

	if not self._EditApplied then
		self._EditApplied = true
		self._SinkDefault = self.Instance.Active
	end

	self.Instance.Active = true
	self._Outline.Enabled = true
	self._Handle.Visible = self.Resizable
end

--[=[
	Replaces the button's image.

	@param icon string -- The asset to display.
	@return TouchButton -- Self, for chaining.
]=]
--
function TouchButton.SetIcon(self: TouchButton, icon: string): TouchButton
	self.Icon = icon
	self.Instance.Image = icon
	return self
end

--[=[
	Replaces the button's label, creating one if the button was built without text.

	@param text string -- The label text.
	@return TouchButton -- Self, for chaining.
]=]
--
function TouchButton.SetText(self: TouchButton, text: string): TouchButton
	self.Text = text

	if self._Label then
		self._Label.Text = text
		return self
	end

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
	label.TextTransparency = 0.3
	label.TextColor3 = if self._Pressed then TouchConfig.LABEL_COLOR_PRESSED else TouchConfig.LABEL_COLOR_IDLE
	label.TextSize = TouchConfig.LABEL_TEXT_SIZE
	label.TextWrapped = true
	label.Text = text
	label.Size = UDim2.fromScale(1, 1)
	label.AnchorPoint = CENTRE_ANCHOR
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.ZIndex = self.Instance.ZIndex + 2
	label.Parent = self.Instance

	self._Label = label
	return self
end

--[=[
	Draws an image on top of the button art, rather than replacing it as `SetIcon` does.

	The overlay is partially transparent by default so it reads as part of the button rather than
	a sticker on it, and it sharpens on press the same way the label brightens. Pass `nil` to
	remove it.

	@param image string? -- The asset to overlay, or nil to hide it.
	@return TouchButton -- Self, for chaining.
]=]
--
function TouchButton.SetOverlay(self: TouchButton, image: string?): TouchButton
	self.Overlay = image

	if image == nil then
		if self._Overlay then
			self._Overlay.Visible = false
		end
		return self
	end

	local overlay = ensure_overlay(self)
	overlay.Image = image
	overlay.Visible = true
	return self
end

--[=[
	Sets the overlay's resting transparency.

	Pressing subtracts `Config.TOUCH.OVERLAY_PRESS_DELTA` from whatever you set here, so the press
	feedback stays proportional to the resting value rather than jumping to a fixed one.

	@param transparency number -- 0 is opaque, 1 is invisible.
	@return TouchButton -- Self, for chaining.
]=]
--
function TouchButton.SetOverlayTransparency(self: TouchButton, transparency: number): TouchButton
	self._OverlayTransparency = transparency
	refresh_overlay(self)
	return self
end

--[=[
	Sets how much of the button the overlay covers, as a fraction of its size.

	@param scale number -- 1 fills the button edge to edge.
	@return TouchButton -- Self, for chaining.
]=]
--
function TouchButton.SetOverlayScale(self: TouchButton, scale: number): TouchButton
	self._OverlayScale = scale

	if self._Overlay then
		self._Overlay.Size = UDim2.new(scale, self._OverlayOffset, scale, self._OverlayOffset)
	end

	return self
end

--[=[
	Sets the overlay's offset in pixels.

	@param offset number -- Added to the scale calculation to size the overlay.
	@return TouchButton -- Self, for chaining.
]=]
--
function TouchButton.SetOverlayOffset(self: TouchButton, offset: number): TouchButton
	self._OverlayOffset = offset

	if self._Overlay then
		self._Overlay.Size = UDim2.new(self._OverlayScale, offset, self._OverlayScale, offset)
	end

	return self
end

--[=[
	Resizes the button, clamped to its size range.

	Drives a `UIScale` rather than the `Size` property, so the label, overlay and outline grow
	with the button instead of staying at whatever pixel size they were authored at. The resize
	handle is counter-scaled to stay a constant grab target.

	The value is in device pixels unless `Config.TOUCH.AUTO_SCALE` is on, in which case it is in
	reference pixels before that scaling. Layouts store a multiplier over the button's base rather
	than the raw number, so a size chosen on a phone means the same thing on a tablet either way.

	@param size number -- The square edge length.
	@return TouchButton -- Self, for chaining.
]=]
--
function TouchButton.SetSize(self: TouchButton, size: number): TouchButton
	apply_size(self, size)
	return self
end

--[=[
	Sets the range a player may resize this button within.

	@param min number -- Smallest allowed edge length.
	@param max number -- Largest allowed edge length.
	@return TouchButton -- Self, for chaining.
]=]
--
function TouchButton.SetSizeRange(self: TouchButton, min: number, max: number): TouchButton
	self.MinSize = min
	self.MaxSize = max
	return self:SetSize(self._LayoutSize)
end

--[=[
	Whether a player may drag this button in edit mode.

	@param movable boolean -- Whether dragging is allowed.
	@return TouchButton -- Self, for chaining.
]=]
--
function TouchButton.SetMovable(self: TouchButton, movable: boolean): TouchButton
	self.Movable = movable

	if EditMode then
		self:_ApplyEditMode()
	end

	return self
end

--[=[
	Whether a player may resize this button in edit mode.

	@param resizable boolean -- Whether the resize handle appears.
	@return TouchButton -- Self, for chaining.
]=]
--
function TouchButton.SetResizable(self: TouchButton, resizable: boolean): TouchButton
	self.Resizable = resizable

	if EditMode then
		self:_ApplyEditMode()
	end

	return self
end

--[=[
	Moves the button into a managed zone, dropping any absolute position it had.

	@param zone Zone -- The zone to lay out in.
	@param order number? -- Position within the zone. Lower comes first.
	@return TouchButton -- Self, for chaining.
]=]
--
function TouchButton.SetZone(self: TouchButton, zone: Zone, order: number?): TouchButton
	assert_zone(zone, "SetZone")

	self.Order = order or next_zone_order(zone)
	self.Instance.LayoutOrder = self.Order

	place_in_zone(self, zone)
	return self
end

--[=[
	Places the button at an absolute position, removing it from its zone's layout.

	Only the scale components are kept -- offsets do not survive a change of screen, and this
	position is what gets serialized into a saved layout.

	@param position UDim2 -- Position within the touch ScreenGui, anchored at the button's centre.
	@return TouchButton -- Self, for chaining.
]=]
--
function TouchButton.SetPosition(self: TouchButton, position: UDim2): TouchButton
	place_at_scale(self, Vector2.new(position.X.Scale, position.Y.Scale))
	return self
end

--[=[
	Sets which contexts must hold for this button to show.

	`{ Combat = true, Menu = false }` shows the button only while `Combat` is on and `Menu` is
	off. An empty table means the button is never gated by context.

	@param contexts { [string]: boolean } -- The required context states.
	@return TouchButton -- Self, for chaining.
]=]
--
function TouchButton.SetVisibleWhen(self: TouchButton, contexts: { [string]: boolean }): TouchButton
	local previous = self._VisibleWhen

	self._VisibleWhen = table.clone(contexts)
	index_contexts(self, previous)
	self:_Resolve()
	return self
end

--[=[
	Sets which devices this button shows on. Defaults to touch alone.

	@param devices { DeviceType } -- The devices to show on.
	@return TouchButton -- Self, for chaining.
]=]
--
function TouchButton.SetShowOn(self: TouchButton, devices: { InputUtil.DeviceType }): TouchButton
	local allowed = {}

	for i = 1, #devices do
		allowed[devices[i]] = true
	end

	self._ShowOn = allowed
	self:_Resolve()
	return self
end

--[=[
	Enables or disables the button. A disabled button keeps its layout slot, dims, and stops
	firing its action -- releasing it first if it is held.

	@param enabled boolean -- Whether the button accepts input.
	@return TouchButton -- Self, for chaining.
]=]
--
function TouchButton.SetEnabled(self: TouchButton, enabled: boolean): TouchButton
	if self.Enabled == enabled then
		return self
	end

	self.Enabled = enabled
	self.Instance.ImageTransparency = if enabled then 0 else TouchConfig.DISABLED_TRANSPARENCY
	refresh_overlay(self)

	if not enabled then
		release(self, nil)
		cancel_drags_for(self)
	end

	return self
end

--[=[
	Hides or shows the button regardless of device and context.

	@param visible boolean -- Whether the button may be shown.
	@return TouchButton -- Self, for chaining.
]=]
--
function TouchButton.SetVisible(self: TouchButton, visible: boolean): TouchButton
	self._Visible = visible
	self:_Resolve()
	return self
end

--[=[
	Whether a finger or cursor is holding the button right now.
	@return boolean
]=]
--
function TouchButton.IsPressed(self: TouchButton): boolean
	return self._Pressed
end

--[=[
	Returns this button's layout as a plain serializable table.

	`Position` is a viewport fraction and `Size` is in reference pixels, so the entry means the
	same thing on any screen. `Position` is absent for a button still living in its zone.

	@return LayoutEntry
]=]
--
function TouchButton.GetLayout(self: TouchButton): LayoutEntry
	if self.IsAdopted then
		local entry = { Scale = self._JumpScale or 1 } :: LayoutEntry

		if self._JumpCentre then
			entry.Position = { X = self._JumpCentre.X, Y = self._JumpCentre.Y }
		end

		return entry
	end

	local entry = { Scale = self._LayoutSize / self._BaseSize } :: LayoutEntry

	if self._LayoutPosition then
		entry.Position = { X = self._LayoutPosition.X, Y = self._LayoutPosition.Y }
	end

	return entry
end

--[=[
	Applies a stored layout entry to this button.

	Deliberately does **not** fire `LayoutChanged` -- restoring a saved layout is not a change,
	and firing here would make the obvious save-on-change wiring write back on every join.

	@param entry LayoutEntry -- The entry to apply.
	@return TouchButton -- Self, for chaining.
]=]
--
function TouchButton.ApplyLayout(self: TouchButton, entry: LayoutEntry): TouchButton
	if type(entry) ~= "table" then
		return self
	end

	if self.IsAdopted then
		if type(entry.Scale) == "number" then
			self._JumpScale = entry.Scale
			self.IsCustomised = true
		end

		local centre = entry.Position

		if type(centre) == "table" and type(centre.X) == "number" and type(centre.Y) == "number" then
			self._JumpCentre = Vector2.new(centre.X, centre.Y)
			self.IsCustomised = true
		end

		self:_ApplyAdoptedLayout()
		return self
	end

	if type(entry.Scale) == "number" then
		self:SetSize(entry.Scale * self._BaseSize)
		self.IsCustomised = true
	end

	local position = entry.Position

	if type(position) == "table" and type(position.X) == "number" and type(position.Y) == "number" then
		place_at_scale(self, snap_and_clamp(self, Vector2.new(position.X, position.Y)))
		self.IsCustomised = true
	end

	return self
end

--[=[
	Returns the button to the position, order and size it was created with.

	@return TouchButton -- Self, for chaining.
]=]
--
function TouchButton.ResetLayout(self: TouchButton): TouchButton
	local default = self._Default

	self:SetSize(default.Size)

	if default.Zone then
		self:SetZone(default.Zone, default.Order)
	elseif default.Position then
		self:SetPosition(default.Position)
	end

	self.IsCustomised = false
	TouchUtilModule.LayoutChanged:Fire(self.LayoutId, self:GetLayout())
	return self
end

--[=[
	Destroys the button, releasing its action first so it cannot leave the action stuck active.
]=]
--
function TouchButton.Destroy(self: TouchButton)
	release(self, nil)
	cancel_drags_for(self)

	local previous = self._VisibleWhen
	self._VisibleWhen = {}
	index_contexts(self, previous)

	Buttons[self] = nil

	if AdoptedJump == self then
		AdoptedJump = nil
	end

	if ButtonsByLayoutId[self.LayoutId] == self then
		ButtonsByLayoutId[self.LayoutId] = nil
	end

	self.Keeper:Destroy()
end

--[=[
	Creates an on-screen button that holds `action_name` while pressed.

	The button is hidden until the player is on touch, so calling this unconditionally is the
	intended usage -- there is no need to branch on device at the call site.

	@param action_name string -- The action this button drives. It need not be bound to any key.
	@param options ButtonOptions? -- Appearance, layout, gating and edit permissions.
	@return TouchButton
]=]
--
function TouchUtilModule.Button(action_name: string, options: ButtonOptions?): TouchButton
	return new(action_name, options)
end

--[=[
	Enters or leaves layout edit mode.

	In edit mode buttons do not fire their actions: a press starts a drag instead. Movable
	buttons temporarily sink input so a drag does not also pan the camera, and resizable ones
	show a corner handle. Both revert on the way out.

	@param enabled boolean -- Whether the player is editing the layout.
]=]
--
function TouchUtilModule.SetEditMode(enabled: boolean)
	if EditMode == enabled then
		return
	end

	EditMode = enabled

	for button in Buttons do
		button:_ApplyEditMode()
	end

	set_default_controls(not enabled)

	if not enabled and AdoptedJump then
		task.defer(function()
			AdoptedJump:_ApplyAdoptedLayout()
		end)
	end

	TouchUtilModule.EditModeChanged:Fire(enabled)
end

--[=[
	Whether the layer is in edit mode.
	@return boolean
]=]
--
function TouchUtilModule.IsEditMode(): boolean
	return EditMode
end

--[=[
	Nudges a zone by a fixed offset, in reference pixels, on top of its margin and any reserved
	space. Positive Y moves down, positive X moves right.

	@param zone Zone -- The zone to nudge.
	@param offset Vector2 -- The offset, or `Vector2.zero` to clear it.
]=]
--
function TouchUtilModule.SetZoneOffset(zone: Zone, offset: Vector2)
	ZoneOffsets[zone] = offset
	reposition_zone(zone)
end

--[=[
	Makes Roblox's own jump button editable, without replacing it.

	The CoreGui button is adopted, not cloned and not hidden: it keeps its art, and it keeps
	jumping, because the control scripts still own its behaviour. All this adds is edit mode --
	the button gains an outline and a resize handle while editing, moves and resizes with the
	rest of the pad, and serializes into the saved layout under `LayoutId` "Jump".

	Returns nil when there is no CoreGui jump button to adopt: desktop, or a game that has
	already disabled the default controls.

	@param options ButtonOptions? -- Overrides. Defaults to LayoutId "Jump".
	@return TouchButton?
]=]
--
function TouchUtilModule.AdoptJumpButton(options: ButtonOptions?): TouchButton?
	assert_client("AdoptJumpButton")
	get_root()

	if AdoptedJump then
		return AdoptedJump
	end

	if not TouchConfig.JUMP_BUTTON_EDITABLE then
		return nil
	end

	local source = find_default_jump()

	if source == nil then
		return nil
	end

	local given = table.clone(options or {})

	given.Adopt = source
	given.LayoutId = given.LayoutId or "Jump"

	AdoptedJump = new("Jump", given)
	return AdoptedJump
end

--[=[
	Turns the jump button's editability on or off at runtime.

	Enabling adopts the CoreGui jump button if it has not been adopted already. Disabling leaves it
	adopted but stops it moving or resizing, so a layout the player already saved is not discarded
	by a temporary toggle -- re-enabling restores it. The button keeps jumping either way, and
	stays parented in `TouchGui` either way.

	`Config.TOUCH.JUMP_BUTTON_EDITABLE` sets the starting state.

	@param enabled boolean -- Whether the player may move and resize the jump button.
	@return TouchButton? -- The adopted button, or nil if there is none to adopt.
]=]
--
function TouchUtilModule.SetJumpButtonEditable(enabled: boolean): TouchButton?
	assert_client("SetJumpButtonEditable")

	if enabled and AdoptedJump == nil then
		local previous = TouchConfig.JUMP_BUTTON_EDITABLE
		TouchConfig.JUMP_BUTTON_EDITABLE = true
		TouchUtilModule.AdoptJumpButton()
		TouchConfig.JUMP_BUTTON_EDITABLE = previous
	end

	if AdoptedJump == nil then
		return nil
	end

	AdoptedJump:SetMovable(enabled)
	AdoptedJump:SetResizable(enabled)
	return AdoptedJump
end

--[=[
	Returns the adopted jump button, if one has been adopted.
	@return TouchButton?
]=]
--
function TouchUtilModule.GetJumpButton(): TouchButton?
	return AdoptedJump
end

--[=[
	Makes any existing GuiObject editable alongside the touch pad.

	The instance is used where it is -- never reparented, never cloned -- so whatever already
	drives it keeps driving it. This is the mechanism behind `AdoptJumpButton`, and it works the
	same for a game's own HUD buttons.

	@param instance GuiObject -- The instance to adopt.
	@param options ButtonOptions? -- Overrides. `LayoutId` defaults to the instance name.
	@return TouchButton
]=]
--
function TouchUtilModule.Adopt(instance: GuiObject, options: ButtonOptions?): TouchButton
	assert_client("Adopt")
	get_root()

	local given = table.clone(options or {})

	given.Adopt = instance
	given.LayoutId = given.LayoutId or instance.Name

	return new(instance.Name, given)
end

--[=[
	Prints what the layer actually resolved to: device, scale, and every button's real screen
	rect.

	Layout problems here are geometry, and geometry is only arguable until someone reads the
	numbers off a real device.
]=]
--
function TouchUtilModule.DebugLayout()
	assert_client("DebugLayout")

	local root = get_root()

	PrintUtil:Print(`device={DeviceType} edit={EditMode} rootScale={get_scale_factor()}`)
	PrintUtil:Print(`root abs={root.AbsoluteSize} pos={root.AbsolutePosition}`)
	PrintUtil:Print(`default jump found={find_default_jump() ~= nil}`)

	PrintUtil:Print(`default button size={resolve_default_size()}`)

	for button in Buttons do
		local instance = button.Instance
		PrintUtil:Print(
			`button {button.LayoutId} zone={tostring(button.Zone)} size={button._LayoutSize} visible={instance.Visible} abs={instance.AbsolutePosition} x {instance.AbsoluteSize}`
		)
	end
end

--[=[
	Snaps dragged buttons to a grid, in reference pixels.

	@param pixels number? -- The grid step, `0` for free placement, or nil to restore `Config.TOUCH.EDIT_GRID`.
]=]
--
function TouchUtilModule.SetGrid(pixels: number?)
	Grid = pixels
end

--[=[
	Returns every customised button's layout, ready to serialize.

	Buttons the player has not touched are omitted, so a layout saved against one version of the
	pad still applies cleanly after buttons are added, removed or moved in code.

	@return Layout
]=]
--
function TouchUtilModule.GetLayout(): Layout
	local entries = {}

	for button in Buttons do
		if not button.IsCustomised then
			continue
		end
		entries[button.LayoutId] = button:GetLayout()
	end

	return {
		Version = TouchConfig.LAYOUT_VERSION,
		Entries = entries,
	}
end

--[=[
	Applies a previously saved layout. Entries naming a button that no longer exists are ignored.

	A layout whose `Version` does not match `Config.TOUCH.LAYOUT_VERSION` is rejected with a
	warning rather than applied, because there is no migration to run: the alternative is feeding
	an old shape into new code and corrupting the pad.

	@param layout Layout -- A table previously returned by `GetLayout`.
	@return boolean -- Whether the layout was applied.
]=]
--
function TouchUtilModule.ApplyLayout(layout: Layout): boolean
	if type(layout) ~= "table" or type(layout.Entries) ~= "table" then
		PrintUtil:Warn("TouchUtil.ApplyLayout: expected a table with an Entries field.")
		return false
	end

	if layout.Version ~= TouchConfig.LAYOUT_VERSION then
		PrintUtil:Warn(
			`TouchUtil.ApplyLayout: layout version {tostring(layout.Version)} does not match {TouchConfig.LAYOUT_VERSION}; ignoring it.`
		)
		return false
	end

	for layout_id, entry in layout.Entries do
		local button = ButtonsByLayoutId[layout_id]

		if button == nil then
			continue
		end

		button:ApplyLayout(entry)
	end

	return true
end

--[=[
	Resets one button to its defaults, or every button when called with no argument.

	@param layout_id string? -- The button to reset, or nil for all of them.
]=]
--
function TouchUtilModule.ResetLayout(layout_id: string?)
	if layout_id then
		local button = ButtonsByLayoutId[layout_id]

		if button then
			button:ResetLayout()
		end

		return
	end

	for button in Buttons do
		button:ResetLayout()
	end
end

--[=[
	Sets a context and refreshes only the buttons gated on it.

	@param context string -- The context name.
	@param state boolean -- Its new state.
]=]
--
function TouchUtilModule.SetContext(context: string, state: boolean)
	local previous = Contexts[context] == true

	if previous == state then
		return
	end

	Contexts[context] = state

	local affected = ButtonsByContext[context]

	if affected then
		for button in affected do
			button:_Resolve()
		end
	end

	TouchUtilModule.ContextChanged:Fire(context, state, previous)
end

--[=[
	Sets several contexts at once.

	@param contexts { [string]: boolean } -- The contexts to set.
]=]
--
function TouchUtilModule.SetContexts(contexts: { [string]: boolean })
	for context, state in contexts do
		TouchUtilModule.SetContext(context, state)
	end
end

--[=[
	Reads a context's current state.

	@param context string -- The context name.
	@return boolean
]=]
--
function TouchUtilModule.GetContext(context: string): boolean
	return Contexts[context] == true
end

--[=[
	Returns every button driving an action.

	@param action_name string -- The action to look up.
	@return { TouchButton }
]=]
--
function TouchUtilModule.GetButtons(action_name: string): { TouchButton }
	local matches = {}

	for button in Buttons do
		if button.Action ~= action_name then
			continue
		end
		table.insert(matches, button)
	end

	return matches
end

--[=[
	Returns the button registered under a layout id, if any.

	@param layout_id string -- The id to look up.
	@return TouchButton?
]=]
--
function TouchUtilModule.GetButton(layout_id: string): TouchButton?
	return ButtonsByLayoutId[layout_id]
end

--[=[
	Shows or hides the entire touch layer without touching per-button state.

	@param enabled boolean -- Whether the layer is on screen.
]=]
--
function TouchUtilModule.SetEnabled(enabled: boolean)
	assert_client("SetEnabled")
	get_root().Enabled = enabled
end

--[=[
	Returns the touch ScreenGui, creating it if this is the first call.

	@return ScreenGui
]=]
--
function TouchUtilModule.GetRoot(): ScreenGui
	assert_client("GetRoot")
	return get_root()
end

--[=[
	Destroys every button and the touch layer itself. A later `Button` call rebuilds it.
]=]
--
function TouchUtilModule.Destroy()
	for button in Buttons do
		button:Destroy()
	end

	if RootKeeper then
		RootKeeper:Destroy()
	end

	RootKeeper = nil
	ControlsKeeper = nil
	AdoptedJump = nil
	DefaultSize = nil
	Root = nil
	RootScale = nil
	EditMode = false
	Grid = nil
	PlayerGuiRef = nil
	ZoneNextOrder = {}
	ZoneOffsets = {}
	Buttons = {}
	ButtonsByLayoutId = {}
	Contexts = {}
	ButtonsByContext = {}
	Drags = {}
	Claims = {}
end

return TouchUtilModule
