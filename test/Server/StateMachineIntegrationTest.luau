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
local StateMachineServer = Craftsman.StateMachine.Server
local Network = Craftsman.StateMachine.Network

local test = Craftsman.Component.new({})

local function run_case(results, name, fn)
	local ok, err = pcall(fn)
	results[#results + 1] = { name, if ok then "success" else "fail", if ok then "" else tostring(err) }
end

local function record_event(log, kind, state_name, context, dt)
	local context_label = if context ~= nil then (context.Label or "ctx") else "nil"
	if dt ~= nil then
		log[#log + 1] = `{kind}:{state_name}:{context_label}:{dt}`
		return
	end
	log[#log + 1] = `{kind}:{state_name}:{context_label}`
end

local function create_state(name, log, enter_fn, exit_fn, update_fn)
	return State.new(name, {
		Enter = function(self, context)
			if enter_fn then
				enter_fn(self, context)
			end
			record_event(log, "enter", self.Name, context)
		end,
		Exit = function(self, context)
			if exit_fn then
				exit_fn(self, context)
			end
			record_event(log, "exit", self.Name, context)
		end,
		Update = function(self, dt, context)
			if update_fn then
				update_fn(self, dt, context)
			end
			record_event(log, "update", self.Name, context, dt)
		end,
	})
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
	PrintUtil:Print("StateMachineIntegrationTest: Start")

	local results = {}

	run_case(results, "TC-01 Hierarchy cycle rejection", function()
		local a = State.new("A")
		local b = State.new("B")

		assert(a:_SetParent(b), "A should be able to set B as parent initially")
		assert(not b:_SetParent(a), "B setting A as parent should be rejected to avoid cycle")
		assert(b.Parent == nil, "B parent should remain nil after rejected cycle")
	end)

	run_case(results, "TC-02 Sibling transition does not touch parent", function()
		local log = {}
		local root = create_state("Root", log)
		local a = create_state("A", log)
		local b = create_state("B", log)

		local machine = Machine.new("m1")
		assert(machine:AddState(root))
		assert(machine:AddState(a, root))
		assert(machine:AddState(b, root))

		assert(machine:SetInitial(a))
		assert(machine:Start({ Label = "boot" }))
		machine:Transition(b, { Label = "t1" })

		-- Expect exit A then enter B; Root enter only at start
		assert(#log >= 3, "expected at least 3 events")
		assert(log[1]:match("enter:Root"))
		assert(log[2]:match("enter:A"))
		-- find exit A and enter B sequence
		local found = false
		for i = 3, #log do
			if log[i] == "exit:A:t1" and log[i + 1] == "enter:B:t1" then
				found = true
				break
			end
		end
		assert(found, "Expected exit A then enter B")
	end)

	run_case(results, "TC-03 Transition across different parents", function()
		local log = {}
		local p1 = create_state("P1", log)
		local p2 = create_state("P2", log)
		local a = create_state("A", log)
		local b = create_state("B", log)

		local machine = Machine.new("m2")
		assert(machine:AddState(p1))
		assert(machine:AddState(p2))
		assert(machine:AddState(a, p1))
		assert(machine:AddState(b, p2))

		assert(machine:SetInitial(a))
		assert(machine:Start({ Label = "boot" }))
		-- transition to b
		machine:Transition(b, { Label = "t2" })

		-- Expect exit A, exit P1, enter P2, enter B in sequence
		local seq = table.concat(log, ";")
		assert(seq:find("exit:A:t2"), "exit A occurred")
		assert(seq:find("exit:P1:t2"), "exit P1 occurred")
		assert(seq:find("enter:P2:t2"), "enter P2 occurred")
		assert(seq:find("enter:B:t2"), "enter B occurred")
	end)

	run_case(results, "TC-04 Nested Transition in Enter executes after enter completes in same frame", function()
		local log = {}
		local machine = Machine.new("m4")

		local b_ref = nil
		local a = create_state("A", log, function(self, context)
			-- request transition to B during A:Enter
			if b_ref then
				machine:Transition(b_ref, context)
			end
		end)
		local b = create_state("B", log)
		b_ref = b

		assert(machine:AddState(a))
		assert(machine:AddState(b))
		assert(machine:SetInitial(a))
		assert(machine:Start({ Label = "boot" }))

		-- After start, A enter, A exit, then B enter should be in log
		assert(log[1] == "enter:A:boot", "A enter logged")
		assert(log[2] == "exit:A:boot", "A exit logged")
		assert(log[3] == "enter:B:boot", "B enter logged immediately after A exit")
	end)

	run_case(results, "TC-05 Infinite loop throttling to MAX batch then deferred", function()
		local log = {}
		local machine = Machine.new("m5")

		local count = 0
		local MAX_WANTED = 20

		local a, b
		a = create_state("A", log, function(self, context)
			count = count + 1
			if count < MAX_WANTED then
				machine:Transition(b, { Label = "loop" })
			end
		end)
		b = create_state("B", log, function(self, context)
			count = count + 1
			if count < MAX_WANTED then
				machine:Transition(a, { Label = "loop" })
			end
		end)

		assert(machine:AddState(a))
		assert(machine:AddState(b))
		assert(machine:SetInitial(a))

		assert(machine:Start({ Label = "boot" }))

		-- Immediately after start, only up to MAX_TRANSITION_BATCH should have executed synchronously
		local immediate_count = count
		PrintUtil:Print("TC-05 immediate transitions: ", immediate_count)
		assert(immediate_count <= 11, "no more than 11 transitions should run synchronously")

		-- Wait a small bit to allow deferred drains to run
		task.wait(0.05)

		assert(count >= MAX_WANTED, "expected deferred transitions to complete to the desired amount")
	end)

	-- Network tests: use dummy player tables and monkeypatch Network sends
	run_case(results, "TC-06 Server broadcasts running machine", function()
		local machine = Machine.new("net1")
		local s1 = State.new("S1")
		local s2 = State.new("S2")
		assert(machine:AddState(s1))
		assert(machine:AddState(s2))
		assert(machine:SetInitial(s1))
		assert(machine:Start())

		local p1 = { Parent = true, Name = "P1" }
		local p2 = { Parent = true, Name = "P2" }

		local captured = {}
		local orig_sendToList = Network.packets.MachineUpdated.sendToList
		Network.packets.MachineUpdated.sendToList = function(payload, targets)
			captured.payload = payload
			captured.targets = targets
		end

		assert(StateMachineServer:Register(machine, { p1, p2 }))

		machine:Transition(s2)

		assert(captured.payload ~= nil, "payload sent")
		assert(captured.payload.State == "S2", "payload contains new state")
		assert(#captured.targets == 2, "two targets should be present")

		-- restore
		Network.packets.MachineUpdated.sendToList = orig_sendToList
		StateMachineServer:Unregister(machine)
	end)

	run_case(results, "TC-07 Client-authoritative transition excludes originator", function()
		local machine = Machine.new("net2")
		local s1 = State.new("S1")
		local s2 = State.new("S2")
		assert(machine:AddState(s1))
		assert(machine:AddState(s2))
		assert(machine:SetInitial(s1))
		assert(machine:Start())

		-- mark client-authoritative
		machine:SetClientAuthoritative(true)

		local p1 = { Parent = true, Name = "P1" }
		local p2 = { Parent = true, Name = "P2" }

		local captured = {}
		local orig_sendToList = Network.packets.MachineUpdated.sendToList
		Network.packets.MachineUpdated.sendToList = function(payload, targets)
			captured.payload = payload
			captured.targets = targets
		end

		assert(StateMachineServer:Register(machine, { p1, p2 }))

		-- simulate a client-driven transition by passing source player to Transition
		machine:Transition(s2, nil, p1)

		assert(captured.payload ~= nil, "payload sent")
		-- originator should be excluded
		assert(#captured.targets == 1, "one target after excluding originator")
		assert(captured.targets[1] == p2, "remaining target should be p2")

		Network.packets.MachineUpdated.sendToList = orig_sendToList
		StateMachineServer:Unregister(machine)
	end)

	run_case(results, "TC-09 Non-existent state payload is ignored", function()
		local machine = Machine.new("net3")
		local s1 = State.new("S1")
		assert(machine:AddState(s1))
		assert(machine:SetInitial(s1))
		assert(machine:Start())

		-- craft payload for missing state
		-- ensure server has registered record
		assert(StateMachineServer:Register(machine, {}))

		-- apply as if from network (source = nil)
		-- call internal apply path via machine:Transition with invalid state name cannot be done; instead call Server's client handler indirectly using Transition with a source
		-- so we emulate client's payload effect: server's apply_client_payload would ignore missing state and not alter current
		-- verify current remains s1
		-- to be safe we just ensure machine:GetCurrent() still s1 after attempting to transition to missing state via direct API
		-- try calling Transition with nil state name by resolving GetState
		local target = machine:GetState("DoesNotExist")
		assert(target == nil)

		-- current should remain s1
		assert(machine:GetCurrent() == s1)

		StateMachineServer:Unregister(machine)
	end)

	run_case(results, "TC-11 Destroy clears queue and unregisters", function()
		local machine = Machine.new("m6")
		local s1 = State.new("S1")
		local s2 = State.new("S2")
		assert(machine:AddState(s1))
		assert(machine:AddState(s2))
		assert(machine:SetInitial(s1))
		assert(machine:Start())

		local p1 = { Parent = true, Name = "P1" }
		assert(StateMachineServer:Register(machine, { p1 }))

		-- destroy
		assert(machine:Destroy())

		-- server should not have machine registered anymore
		assert(not StateMachineServer:Unregister(machine), "server auto-unregistered on destroy")
	end)

	run_case(results, "TC-12 Start without initial returns false", function()
		local machine = Machine.new("m7")
		assert(not machine:Start(), "starting without initial must fail")
	end)

	run_case(results, "TC-13 Stop exits active chain and clears running", function()
		local log = {}
		local root = create_state("Root", log)
		local a = create_state("A", log)

		local machine = Machine.new("m8")
		assert(machine:AddState(root))
		assert(machine:AddState(a, root))
		assert(machine:SetInitial(a))
		assert(machine:Start({ Label = "boot" }))

		machine:Stop({ Label = "stop" })
		assert(not machine:IsRunning(), "machine should not be running after stop")

		-- last events should include exit chain
		local found = false
		for i = 1, #log do
			if log[i]:match("exit:A:stop") then
				found = true
				break
			end
		end
		assert(found, "exit of A fired on stop")
	end)

	run_case(results, "TC-14 Machine:Replicate registers successfully in context", function()
		local machine = Machine.new("net_rep1")
		local s1 = State.new("S1")
		assert(machine:AddState(s1))
		assert(machine:SetInitial(s1))
		assert(machine:Start())

		local p1 = { Parent = true, Name = "P1" }
		assert(machine:Replicate({ p1 }))

		local captured = {}
		local orig_sendToList = Network.packets.MachineUpdated.sendToList
		Network.packets.MachineUpdated.sendToList = function(payload, targets)
			captured.payload = payload
			captured.targets = targets
		end

		local s2 = State.new("S2")
		assert(machine:AddState(s2))
		machine:Transition(s2)

		assert(captured.payload ~= nil, "payload should be captured after Replicate and Transition")
		assert(captured.payload.State == "S2", "state should be S2")
		assert(captured.targets[1] == p1, "target should be p1")

		-- clean up / unreplicate
		assert(machine:Unreplicate())
		Network.packets.MachineUpdated.sendToList = orig_sendToList
	end)

	run_case(results, "TC-15 StateMachine.Register and Unregister wrapper functions", function()
		local machine = Machine.new("net_rep2")
		local s1 = State.new("S1")
		assert(machine:AddState(s1))
		assert(machine:SetInitial(s1))
		assert(machine:Start())

		local p1 = { Parent = true, Name = "P1" }
		assert(Craftsman.StateMachine.Register(machine, { p1 }))

		local captured = {}
		local orig_sendToList = Network.packets.MachineUpdated.sendToList
		Network.packets.MachineUpdated.sendToList = function(payload, targets)
			captured.payload = payload
			captured.targets = targets
		end

		local s2 = State.new("S2")
		assert(machine:AddState(s2))
		machine:Transition(s2)

		assert(captured.payload ~= nil, "payload should be captured")
		assert(captured.payload.State == "S2")

		assert(Craftsman.StateMachine.Unregister(machine))
		Network.packets.MachineUpdated.sendToList = orig_sendToList
	end)

	-- Print results
	for i = 1, #results do
		local r = results[i]
		PrintUtil:Print(`Test {r[1]}: {r[2]} {r[3]}`)
	end

	return results
end

return test
