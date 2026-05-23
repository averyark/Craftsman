--!nonstrict
--[[
	FileName    > Network.luau
	Author      > AveryArk
	Contact     > Twitter: https://twitter.com/averyark_
	Created     > 23/05/2026
--]]

const ByteNet = require("../../../../ByteNet")

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
