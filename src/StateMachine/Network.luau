--!strict
--[[
    FileName    > Network.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 30/05/2026
--]]

const ByteNet = require("../../packages/roblox/ByteNet")

--
export type MachinePayload = {
	Id: string,
	State: string?,
	Running: boolean,
	ClientAuthoritative: boolean,
	Context: any,
	Sequence: number?,
}
--

local function define()
	return {
		structs = {},
		packets = {
			MachineUpdated = ByteNet.definePacket({
				value = ByteNet.auto :: MachinePayload,
			}),
			ClientMachineUpdated = ByteNet.definePacket({
				value = ByteNet.auto :: unknown,
			}),
		},
		queries = {
			RequestState = ByteNet.defineQuery({
				request = ByteNet.auto :: unknown,
				response = ByteNet.auto :: MachinePayload?,
			}),
		},
	}
end

--
export type Network = typeof(define())
--

return ByteNet.defineNamespace("CraftsmanStateMachine", define :: any) :: Network
