--!nonstrict
--[[
    FileName    > InputStore.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 20/05/2026
--]]

const Store = require("./")

local InitialState = {
	DeviceType = "KeyboardMouse",
	ActiveActions = {},
}

local InputSlice = Store.CreateProducer(InitialState)({
	SetDeviceType = function(state, device_type)
		if state.DeviceType == device_type then
			return nil
		end

		return {
			DeviceType = device_type,
		}
	end,

	SetActionActive = function(state, action_name, is_active)
		if state.ActiveActions[action_name] == is_active then
			return nil
		end

		local updated_actions = table.clone(state.ActiveActions)
		updated_actions[action_name] = is_active

		return {
			ActiveActions = updated_actions,
		}
	end,
})

return InputSlice
