--!nonstrict
--[[
	FileName    > Client.luau
	Author      > AveryArk
	Contact     > Twitter: https://twitter.com/averyark_
	Created     > 13/06/2026
--]]

const Reflex = require("../../../../Reflex")
const Network = require("./Network")

local Client = {}

function Client.CreateReceiver(store: any, options: { [string]: any }?)
	local receiver_options = options or {}

	receiver_options.start = function()
		Network.queries.StartReceiver()
	end

	local receiver = Reflex.createBroadcastReceiver(receiver_options)
	store:applyMiddleware(receiver.middleware)

	Network.packets.DispatchActions.listen(function(actions)
		receiver:dispatch(actions)
	end)

	Network.packets.HydrateState.listen(function(state)
		receiver:hydrate(state)
	end)

	return receiver
end

return Client
