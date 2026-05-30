--!nonstrict
--[[
    FileName    > Network.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 30/05/2026
--]]

const ByteNet = require("../../../../ByteNet")

const Network = ByteNet.defineNamespace("CraftsmanStateMachine", function()
	return {
		structs = {},
		packets = {
			MachineUpdated = ByteNet.definePacket({
				value = ByteNet.auto,
			}),
			ClientMachineUpdated = ByteNet.definePacket({
				value = ByteNet.auto,
			}),
		},
		queries = {
			RequestState = ByteNet.defineQuery({
				request = ByteNet.auto,
				response = ByteNet.auto,
			}),
		},
	}
end)

return Network
