--!nonstrict
--[[
    FileName    > InputUtil.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 20/05/2026
--]]

const RunService = game:GetService("RunService")
const UserInputService = game:GetService("UserInputService")

const Signal = require("../Signal")
const InputStore = require("../Store/InputStore")

--[=[
	@class InputUtil
	A centralized, stateless input bridge for action bindings, movement vectors, and device-type
	tracking.

	An action is a name, and any number of *sources* can hold it down at once -- a KeyCode, a
	gamepad button, a `TouchUtil` button. `Began` fires when the first source raises the action
	and `Ended` when the last one releases it, so a player holding the same action on two devices
	does not end it by lifting one.
]=]
--
local InputUtil = {}

export type DeviceType = "KeyboardMouse" | "Gamepad" | "Touch"
export type InputKey = Enum.KeyCode | Enum.UserInputType

local ActionBindings = {}
local PrimitiveBindings = {}
local ActiveActions = {}
local ActionSources = {}
local ActionsByKey = {}

const INPUT_TYPE_TO_DEVICE: { [Enum.UserInputType]: DeviceType } = {
	[Enum.UserInputType.Keyboard] = "KeyboardMouse",
	[Enum.UserInputType.MouseButton1] = "KeyboardMouse",
	[Enum.UserInputType.MouseButton2] = "KeyboardMouse",
	[Enum.UserInputType.MouseButton3] = "KeyboardMouse",
	[Enum.UserInputType.MouseWheel] = "KeyboardMouse",
	[Enum.UserInputType.Gamepad1] = "Gamepad",
	[Enum.UserInputType.Gamepad2] = "Gamepad",
	[Enum.UserInputType.Gamepad3] = "Gamepad",
	[Enum.UserInputType.Gamepad4] = "Gamepad",
	[Enum.UserInputType.Touch] = "Touch",
}

const FOCUS_LOST_INPUT = table.freeze({
	UserInputState = Enum.UserInputState.End,
	UserInputType = Enum.UserInputType.None,
	KeyCode = Enum.KeyCode.Unknown,
})

--[=[
	@prop Began Signal -- Fired when an action goes from no sources held to one.
	@within InputUtil
]=]
--
InputUtil.Began = Signal.new()

--[=[
	@prop Ended Signal -- Fired when an action's last held source releases.
	@within InputUtil
]=]
--
InputUtil.Ended = Signal.new()

--[=[
	@prop BindingChanged Signal -- Fired with (action_name, new_keys, old_keys) on every rebind.
	@within InputUtil
]=]
--
InputUtil.BindingChanged = Signal.new()

--
local function unindex_action(action_name: string)
	local key_array = ActionBindings[action_name]
	if not key_array then
		return
	end

	for i = 1, #key_array do
		local actions = ActionsByKey[key_array[i]]
		if actions then
			actions[action_name] = nil
		end
	end
end

local function index_action(action_name: string, key_array: { InputKey })
	for i = 1, #key_array do
		local key = key_array[i]
		local actions = ActionsByKey[key]

		if actions == nil then
			actions = {}
			ActionsByKey[key] = actions
		end

		actions[action_name] = true
	end
end
--

--
local function set_action_state(action_name: string, is_active: boolean, source: any, input_object: any)
	local sources = ActionSources[action_name]

	if sources == nil then
		sources = {}
		ActionSources[action_name] = sources
	end

	if is_active == (sources[source] == true) then
		return
	end

	local was_active = next(sources) ~= nil
	sources[source] = if is_active then true else nil
	local now_active = next(sources) ~= nil

	if now_active == was_active then
		return
	end

	ActiveActions[action_name] = now_active
	InputStore.SetActionActive(action_name, now_active)

	if now_active then
		InputUtil.Began:Fire(action_name, input_object)
	else
		InputUtil.Ended:Fire(action_name, input_object)
	end
end

local function release_key_sources(action_name: string, key_array: { InputKey }?)
	local sources = ActionSources[action_name]
	if sources == nil then
		return
	end

	if key_array then
		for i = 1, #key_array do
			set_action_state(action_name, false, key_array[i], FOCUS_LOST_INPUT)
		end
		return
	end

	for source in sources do
		if typeof(source) ~= "EnumItem" then
			continue
		end
		set_action_state(action_name, false, source, FOCUS_LOST_INPUT)
	end
end
--

--[=[
	Binds an action name to a set of KeyCodes or UserInputTypes, replacing any previous binding.

	Any key of the outgoing binding that is currently held is released first, so rebinding
	mid-hold cannot leave the action stuck active. Sources that are not keys -- a touch button
	holding the same action -- are left alone.

	@param action_name string -- The name of the action.
	@param key_array { Enum.KeyCode | Enum.UserInputType } -- The inputs that trigger this action.
]=]
--
function InputUtil.BindAction(action_name: string, key_array: { InputKey })
	local previous = ActionBindings[action_name]

	release_key_sources(action_name, previous)
	unindex_action(action_name)

	ActionBindings[action_name] = key_array

	if ActiveActions[action_name] == nil then
		ActiveActions[action_name] = false
	end

	index_action(action_name, key_array)
	InputUtil.BindingChanged:Fire(action_name, key_array, previous)
end

--[=[
	Records the default binding for an action, and binds it if nothing is bound yet.

	This is what `ResetBinding` restores to, so a keybind menu can rebind freely without
	tracking the shipped defaults itself.

	@param action_name string -- The name of the action.
	@param key_array { Enum.KeyCode | Enum.UserInputType } -- The default inputs.
]=]
--
function InputUtil.SetPrimitiveBinding(action_name: string, key_array: { InputKey })
	PrimitiveBindings[action_name] = table.clone(key_array)

	if ActionBindings[action_name] == nil then
		InputUtil.BindAction(action_name, table.clone(key_array))
	end
end

--[=[
	Restores one action's default binding, or every action's when called with no argument.

	Actions with no recorded default are left untouched.

	@param action_name string? -- The action to reset, or nil for all of them.
]=]
--
function InputUtil.ResetBinding(action_name: string?)
	if action_name then
		local primitive = PrimitiveBindings[action_name]

		if primitive == nil then
			return
		end

		InputUtil.BindAction(action_name, table.clone(primitive))
		return
	end

	for name, primitive in PrimitiveBindings do
		InputUtil.BindAction(name, table.clone(primitive))
	end
end

--[=[
	Returns a copy of an action's current binding, for drawing a keybind menu or an input glyph.

	@param action_name string -- The name of the action.
	@return { Enum.KeyCode | Enum.UserInputType }? -- The bound inputs, or nil if unbound.
]=]
--
function InputUtil.GetBinding(action_name: string): { InputKey }?
	local bound = ActionBindings[action_name]

	if bound == nil then
		return nil
	end

	return table.clone(bound)
end

--[=[
	Unbinds an action from all registered inputs.

	Releases the keys it unbinds. Any non-key source still holding the action keeps holding it,
	so unbinding a keyboard shortcut does not release a touch button under the player's thumb.

	@param action_name string -- The name of the action to unbind.
]=]
--
function InputUtil.UnbindAction(action_name: string)
	release_key_sources(action_name, ActionBindings[action_name])
	unindex_action(action_name)

	ActionBindings[action_name] = nil

	local sources = ActionSources[action_name]

	if sources == nil or next(sources) == nil then
		ActionSources[action_name] = nil
		ActiveActions[action_name] = nil
	end
end

--[=[
	Raises or lowers an action from a source that is not the keyboard, mouse or gamepad.

	`source` is any value that identifies the holder -- `TouchUtil` passes the button object.
	Held sources are counted, so `Began` fires only on the first and `Ended` only when the last
	one lets go. Calling this twice with the same source and state is a no-op.

	@param action_name string -- The name of the action.
	@param is_active boolean -- Whether this source is holding the action.
	@param source any -- The identity of the holder.
	@param input_object any? -- Passed through to Began/Ended.
]=]
--
function InputUtil.SetActionState(action_name: string, is_active: boolean, source: any, input_object: any?)
	set_action_state(action_name, is_active, source, input_object or FOCUS_LOST_INPUT)
end

--[=[
	Checks if a specified action is currently active/held.
	@param action_name string -- The name of the action.
	@return boolean -- `true` if the action is currently active, `false` otherwise.
]=]
--
function InputUtil.IsActionActive(action_name: string): boolean
	return ActiveActions[action_name] or false
end

--[=[
	Calculates the normalized WASD and left analog stick thumbstick movement vector.
	@return Vector3 -- The unit movement vector along the XZ plane.
]=]
--
function InputUtil.GetMovementVector(): Vector3
	local movement_vector = Vector3.zero

	if UserInputService:IsKeyDown(Enum.KeyCode.W) then
		movement_vector += Vector3.new(0, 0, -1)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then
		movement_vector += Vector3.new(0, 0, 1)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		movement_vector += Vector3.new(-1, 0, 0)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then
		movement_vector += Vector3.new(1, 0, 0)
	end

	local gamepad_state = UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)
	for i = 1, #gamepad_state do
		local input = gamepad_state[i]
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			movement_vector += Vector3.new(input.Position.X, 0, -input.Position.Y)
			break
		end
	end

	if movement_vector.Magnitude > 0 then
		return movement_vector.Unit
	end

	return movement_vector
end

--[=[
	Retrieves the camera movement delta from UserInputService.
	@return Vector2 -- The mouse or touch camera movement delta.
]=]
--
function InputUtil.GetCameraDelta(): Vector2
	return UserInputService:GetMouseDelta()
end

--[=[
	Returns the device the player last gave input with.

	This is the *last used* device, not the set of devices attached -- a laptop with a
	touchscreen reports `KeyboardMouse` while the player is typing, which is what decides
	whether touch buttons belong on screen.

	@return DeviceType -- `"KeyboardMouse"`, `"Gamepad"` or `"Touch"`.
]=]
--
function InputUtil.GetDeviceType(): DeviceType
	return InputStore:getState().DeviceType
end

--
local function update_device_type(input_type: Enum.UserInputType)
	local device = INPUT_TYPE_TO_DEVICE[input_type]

	if device == nil then
		return
	end

	InputStore.SetDeviceType(device)
end

local function seed_device_type()
	local device = INPUT_TYPE_TO_DEVICE[UserInputService:GetLastInputType()]

	if device then
		InputStore.SetDeviceType(device)
		return
	end

	if UserInputService.KeyboardEnabled or UserInputService.MouseEnabled then
		return
	end

	if UserInputService.TouchEnabled then
		InputStore.SetDeviceType("Touch")
		return
	end

	if UserInputService.GamepadEnabled then
		InputStore.SetDeviceType("Gamepad")
	end
end

local function process_input(input_object: InputObject, is_began: boolean)
	local key_code = input_object.KeyCode
	local target_key = if key_code == Enum.KeyCode.Unknown then input_object.UserInputType else key_code

	local actions = ActionsByKey[target_key]

	if actions == nil then
		return
	end

	for action_name in actions do
		set_action_state(action_name, is_began, target_key, input_object)
	end
end
--

--
if RunService:IsClient() then
	seed_device_type()

	UserInputService.InputBegan:Connect(function(input, game_processed)
		if game_processed then
			return
		end

		update_device_type(input.UserInputType)
		process_input(input, true)
	end)

	UserInputService.InputEnded:Connect(function(input)
		process_input(input, false)
	end)

	UserInputService.WindowFocusReleased:Connect(function()
		for action_name in ActionSources do
			release_key_sources(action_name)
		end
	end)
end
--

type InputUtilModule = {
	BindAction: (action_name: string, key_array: { InputKey }) -> (),
	SetPrimitiveBinding: (action_name: string, key_array: { InputKey }) -> (),
	ResetBinding: (action_name: string?) -> (),
	GetBinding: (action_name: string) -> { InputKey }?,
	UnbindAction: (action_name: string) -> (),
	SetActionState: (action_name: string, is_active: boolean, source: any, input_object: any?) -> (),
	IsActionActive: (action_name: string) -> boolean,
	GetMovementVector: () -> Vector3,
	GetCameraDelta: () -> Vector2,
	GetDeviceType: () -> DeviceType,
	Began: Signal.Signal<string, InputObject>,
	Ended: Signal.Signal<string, InputObject>,
	BindingChanged: Signal.Signal<string, { InputKey }, { InputKey }?>,
}

return (InputUtil :: any) :: InputUtilModule
