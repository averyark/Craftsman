--!nonstrict
--[[
	FileName    > Server.luau
	Author      > AveryArk
	Contact     > Twitter: https://twitter.com/averyark_
	Created     > 13/06/2026
--]]

const Reflex = require("../../../../Reflex")
const Network = require("./Network")

local Server = {}

function Server.FilterStateByPlayer(player: Player, state: { [string]: any }): { [string]: any }
	local filtered_state = {}

	for key, value in state do
		if key == "Players" and type(value) == "table" then
			local user_id_str = tostring(player.UserId)
			local user_id_num = player.UserId

			-- Support both string and number user_ids
			local player_data = value[user_id_str] or value[user_id_num]

			filtered_state.Players = {}
			if player_data then
				filtered_state.Players[user_id_str] = player_data
			end
		else
			filtered_state[key] = value
		end
	end

	return filtered_state
end

function Server.CreateBroadcaster(store: any, options: { [string]: any }?)
	local broadcaster_options = options or {}

	if not broadcaster_options.beforeHydrate then
		broadcaster_options.beforeHydrate = Server.FilterStateByPlayer
	end

	broadcaster_options.producers = store
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
