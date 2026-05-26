--!nonstrict
-- InputUtil.luau
-- Centralized, stateless input bridge for high-frequency events

local UserInputService = game:GetService("UserInputService")

local Signal = require("../Signal")

local InputStore = require("../Store/InputStore")

local InputUtil = {}

local ActionBindings = {}
local ActiveActions = {}

InputUtil.Began = Signal.new()
InputUtil.Ended = Signal.new()

function InputUtil.BindAction(action_name, key_array)
	ActionBindings[action_name] = key_array
	ActiveActions[action_name] = false
end

function InputUtil.UnbindAction(action_name)
	ActionBindings[action_name] = nil
	ActiveActions[action_name] = nil
end

function InputUtil.IsActionActive(action_name)
	return ActiveActions[action_name] or false
end

function InputUtil.GetMovementVector()
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

function InputUtil.GetCameraDelta()
	return UserInputService:GetMouseDelta()
end

local function update_device_type(input_type)
	if
		input_type == Enum.UserInputType.Keyboard
		or input_type == Enum.UserInputType.MouseButton1
		or input_type == Enum.UserInputType.MouseButton2
	then
		InputStore.SetDeviceType("KeyboardMouse")
		return
	end

	if input_type == Enum.UserInputType.Gamepad1 then
		InputStore.SetDeviceType("Gamepad")
		return
	end

	if input_type == Enum.UserInputType.Touch then
		InputStore.SetDeviceType("Touch")
	end
end

local function process_input(input_object, is_began)
	local key_code = input_object.KeyCode
	local user_input_type = input_object.UserInputType

	local target_key = (key_code == Enum.KeyCode.Unknown) and user_input_type or key_code

	for action_name, key_array in ActionBindings do
		local is_match = false

		for i = 1, #key_array do
			local bound_key = key_array[i]
			if bound_key == target_key then
				is_match = true
				break
			end
		end

		if not is_match then
			continue
		end

		ActiveActions[action_name] = is_began
		InputStore.SetActionActive(action_name, is_began)

		if is_began then
			InputUtil.Began:Fire(action_name, input_object)
		else
			InputUtil.Ended:Fire(action_name, input_object)
		end
	end
end

UserInputService.InputBegan:Connect(function(input, game_processed)
	if game_processed then
		return
	end
	update_device_type(input.UserInputType)
	process_input(input, true)
end)

UserInputService.InputEnded:Connect(function(input, game_processed)
	if game_processed then
		return
	end
	process_input(input, false)
end)

type InputUtilModule = {
	BindAction: (action_name: string, key_array: { Enum.KeyCode | Enum.UserInputType }) -> (),
	UnbindAction: (action_name: string) -> (),
	IsActionActive: (action_name: string) -> boolean,
	GetMovementVector: () -> Vector3,
	GetCameraDelta: () -> Vector2,
	Began: Signal.Signal<string, InputObject>,
	Ended: Signal.Signal<string, InputObject>,
}

return (InputUtil :: any) :: InputUtilModule
