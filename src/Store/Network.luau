--!nonstrict
--[[
	FileName    > Network.luau
	Author      > AveryArk
	Contact     > Twitter: https://twitter.com/averyark_
	Created     > 13/06/2026
--]]

const ByteNet = require("../../../../ByteNet")

local Network = ByteNet.defineNamespace("CraftsmanStore", function()
	return {
		structs = {},
		packets = {
			DispatchActions = ByteNet.definePacket({
				value = ByteNet.auto,
			}),
			HydrateState = ByteNet.definePacket({
				value = ByteNet.auto,
			}),
		},
		queries = {
			StartReceiver = ByteNet.defineQuery({
				request = ByteNet.nothing,
				response = ByteNet.nothing,
			}),
		},
	}
end)

return Network
