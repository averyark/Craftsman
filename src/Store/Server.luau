--!nonstrict
--[[
	FileName    > Server.luau
	Author      > AveryArk
	Contact     > Twitter: https://twitter.com/averyark_
	Created     > 13/06/2026
--]]

const Reflex = require("../../../../Reflex")
const Store = require("./")
const Network = require("./Network")

local Server = {}

function Server.CreateStateFilter(player_state_key: string)
	return function(player: Player, state: { [string]: any }): { [string]: any }
		local filtered_state = {}

		for key, value in state do
			if key ~= player_state_key then
				filtered_state[key] = value
				continue
			end

			if type(value) ~= "table" then
				continue
			end

			local user_id_str = tostring(player.UserId)
			local user_id_num = player.UserId
			local player_data = value[user_id_str] or value[user_id_num]

			filtered_state[player_state_key] = {}

			if not player_data then
				continue
			end

			filtered_state[player_state_key][user_id_str] = player_data
		end

		return filtered_state
	end
end

function Server.CreateBroadcaster(store: any, options: { [string]: any }?)
	local broadcaster_options = options or {}
	local player_state_key = broadcaster_options.player_state_key or "Players"

	if not broadcaster_options.beforeHydrate then
		broadcaster_options.beforeHydrate = Server.CreateStateFilter(player_state_key)
	end

	if not broadcaster_options.beforeDispatch then
		broadcaster_options.beforeDispatch = function(player: Player, action: any)
			if Store.PlayerActionRegistry[action.name] then
				local target_arg = action.arguments[1]
				local target_id_str = typeof(target_arg) == "Instance" and target_arg:IsA("Player") and tostring(target_arg.UserId) or tostring(target_arg)
				if target_id_str ~= tostring(player.UserId) then
					return nil
				end
			end
			return action
		end
	end

	if not broadcaster_options.producers then
		broadcaster_options.producers = {
			[player_state_key] = store,
		}
	end

	broadcaster_options.dispatch = function(player, actions)
		Network.packets.DispatchActions.sendTo(actions, player)
	end

	broadcaster_options.hydrate = function(player, state)
		Network.packets.HydrateState.sendTo(state, player)
	end

	local broadcaster = Reflex.createBroadcaster(broadcaster_options)
	store:applyMiddleware(broadcaster.middleware)

	Network.queries.StartReceiver.listen(function(_data, player)
		broadcaster:start(player)
	end)

	return broadcaster
end

return Server
