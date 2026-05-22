--!nonstrict
--[[
    FileName    > InputStore.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 20/05/2026
--]]

const Reflex = require("../../../../Reflex")

local InitialState = {
	DeviceType = "KeyboardMouse",
	ActiveActions = {},
}

local InputSlice = Reflex.createProducer(InitialState, {
	SetDeviceType = function(state, device_type)
		if state.DeviceType == device_type then
			return state
		end

		return {
			DeviceType = device_type,
			ActiveActions = state.ActiveActions,
		}
	end,

	SetActionActive = function(state, action_name, is_active)
		if state.ActiveActions[action_name] == is_active then
			return state
		end

		local updated_actions = table.clone(state.ActiveActions)
		updated_actions[action_name] = is_active

		return {
			DeviceType = state.DeviceType,
			ActiveActions = updated_actions,
		}
	end,
})

return InputSlice
