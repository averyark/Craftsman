--!nonstrict
--[[
    FileName    > StateMachineIntegrationTest.luau
    Author      > AI
    Created     > 30/05/2026
--]]

const ReplicatedStorage = game:GetService("ReplicatedStorage")
const Craftsman = require(ReplicatedStorage.Packages.Craftsman)
local PrintUtil = Craftsman.PrintUtil
local State = Craftsman.State
local Machine = Craftsman.Machine
local StateMachineClient = Craftsman.StateMachine.Client
local Network = Craftsman.StateMachine.Network

local test = Craftsman.Component.new({})

local function run_case(results, name, fn)
	local ok, err = pcall(fn)
	results[#results + 1] = { name, if ok then "success" else "fail", if ok then "" else tostring(err) }
end

local function with_patched_method(object, key, replacement, callback)
	local original = object[key]
	object[key] = replacement

	local ok, err = pcall(callback)
	object[key] = original

	if not ok then
		error(err)
	end
end

function test:Start()
	PrintUtil:Print("StateMachineClientIntegrationTest: Start")

	local results = {}

	run_case(results, "TC-08 Non-authoritative client does not send updates", function()
		local machine = Machine.new("net4")
		local s1 = State.new("S1")
		local s2 = State.new("S2")
		assert(machine:AddState(s1))
		assert(machine:AddState(s2))
		assert(machine:SetInitial(s1))
		assert(machine:Start())

		local sent_count = 0
		with_patched_method(Network.packets.ClientMachineUpdated, "send", function(_payload)
			sent_count += 1
		end, function()
			assert(StateMachineClient:Register(machine))
			machine:Transition(s2)
		end)

		assert(sent_count == 0, "non-authoritative machines should not send outbound updates")
		assert(StateMachineClient:Unregister(machine))
	end)

	run_case(results, "TC-10 Client Start syncs multiple machines", function()
		local requests = {}

		with_patched_method(Network.queries.RequestState, "invoke", function(request_id)
			requests[#requests + 1] = request_id
			if request_id == "sync1" then
				return { Id = "sync1", State = "B", Running = true }
			end

			if request_id == "sync2" then
				return { Id = "sync2", State = "D", Running = true }
			end

			return nil
		end, function()
			local machine1 = Machine.new("sync1")
			local machine2 = Machine.new("sync2")
			local a = State.new("A")
			local b = State.new("B")
			local c = State.new("C")
			local d = State.new("D")

			assert(machine1:AddState(a))
			assert(machine1:AddState(b))
			assert(machine2:AddState(c))
			assert(machine2:AddState(d))
			assert(StateMachineClient:Register(machine1))
			assert(StateMachineClient:Register(machine2))
			task.wait(0.05)

			assert(machine1:GetCurrent() == b, "machine1 should sync to state B")
			assert(machine2:GetCurrent() == d, "machine2 should sync to state D")
			assert(#requests == 2, "client should request both registered machines")

			assert(StateMachineClient:Unregister(machine1))
			assert(StateMachineClient:Unregister(machine2))
		end)
	end)

	run_case(results, "TC-11 Client auto-unregisters destroyed machine", function()
		local machine = Machine.new("net5")
		local s1 = State.new("S1")
		assert(machine:AddState(s1))
		assert(machine:SetInitial(s1))
		assert(machine:Start())
		assert(StateMachineClient:Register(machine))

		assert(machine:Destroy())
		assert(not StateMachineClient:Unregister(machine), "destroyed machine should already be unregistered")
	end)

	for i = 1, #results do
		local r = results[i]
		PrintUtil:Print(`Test {r[1]}: {r[2]} {r[3]}`)
	end

	return results
end

return test
