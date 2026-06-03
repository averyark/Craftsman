--!nonstrict
--[[
	FileName    > Network.luau
	Author      > AveryArk
	Contact     > Twitter: https://twitter.com/averyark_
	Created     > 23/05/2026
--]]

const ByteNet = require("../../../../ByteNet")

--[=[
	@class CraftsmanDataNetwork
	@ignore
	This module defines the ByteNet namespace, packets, and queries used for data synchronization in Craftsman.
]=]

--[=[
	@prop StateUpdated Packet -- A packet sent from the server to clients to notify them of player state updates.
	@within CraftsmanDataNetwork
]=]

--[=[
	@prop RequestState Query -- A query invoked by the client to request their initial player state from the server on startup.
	@within CraftsmanDataNetwork
]=]
const Network = ByteNet.defineNamespace("CraftsmanData", function()
	return {
		structs = {},
		packets = {
			StateUpdated = ByteNet.definePacket({
				value = ByteNet.auto,
			}),
		},
		queries = {
			RequestState = ByteNet.defineQuery({
				request = ByteNet.nothing,
				response = ByteNet.auto,
			}),
		},
	}
end)

return Network
