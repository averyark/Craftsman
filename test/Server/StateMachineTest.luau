--!nonstrict
--[[
	FileName    > StateMachineTest.luau
	Author      > AveryArk
	Contact     > Twitter: https://twitter.com/averyark_
	Created     > 27/05/2026
--]]

const Craftsman = require("@game/ReplicatedStorage/Packages/Craftsman")

type TestContext = {
	Label: string,
}

type TestResult = { string }

local test = Craftsman.Component.new({})

local Clock = os.clock()

local function trace(message: string)
	Craftsman.PrintUtil:Print(`{message} +{Craftsman.StringUtil.FormatDecimal(os.clock() - Clock, 8)}s`)
end

local function record_event(log: { string }, kind: string, state_name: string, context: TestContext?, dt: number?)
	local context_label = if context ~= nil then context.Label else "nil"
	if dt ~= nil then
		table.insert(log, `{kind}:{state_name}:{context_label}:{dt}`)
		return
	end

	table.insert(log, `{kind}:{state_name}:{context_label}`)
end

local function create_state(name: string, log: { string })
	return Craftsman.State.new(name, {
		Enter = function(self, context: TestContext?)
			record_event(log, "enter", self.Name, context)
		end,
		Exit = function(self, context: TestContext?)
			record_event(log, "exit", self.Name, context)
		end,
		Update = function(self, dt: number, context: TestContext?)
			record_event(log, "update", self.Name, context, dt)
		end,
	})
end

local function expect_events(actual: { string }, expected: { string }, label: string)
	assert(#actual == #expected, `{label}: expected {#expected} events, got {#actual}`)

	for index = 1, #expected do
		assert(
			actual[index] == expected[index],
			`{label}: event {index} expected {expected[index]}, got {actual[index]}`
		)
	end
end

local function create_machine(log: { string })
	local root = create_state("Root", log)
	local a = create_state("A", log)
	local b = create_state("B", log)
	local leaf = create_state("Leaf", log)

	local machine = Craftsman.Machine.new()

	assert(machine:AddState(root))
	assert(machine:AddState(a, root))
	assert(machine:AddState(b, root))
	assert(machine:AddState(leaf, b))

	return machine, root, a, b, leaf
end

local function run_case(results: { TestResult }, case_name: string, callback: () -> ())
	local ok, err = pcall(callback)
	results[#results + 1] = { case_name, if ok then "success" else "fail", if ok then "" else tostring(err) }
end

function test:Start()
	trace("StateMachine test started")

	local results: { TestResult } = {}

	run_case(results, "register and wire states", function()
		local log: { string } = {}
		local machine, root, a, b, leaf = create_machine(log)

		local duplicate_a = Craftsman.State.new("A")
		assert(not machine:AddState(duplicate_a), "duplicate state names should be rejected")

		assert(root.Children.A == a, "root should track A as a child")
		assert(root.Children.B == b, "root should track B as a child")
		assert(b.Children.Leaf == leaf, "B should track Leaf as a child")
		assert(a.Parent == root, "A should have Root as its parent")
		assert(b.Parent == root, "B should have Root as its parent")
		assert(leaf.Parent == b, "Leaf should have B as its parent")

		assert(not root:_SetParent(leaf), "cycles should be rejected")
		assert(root.Parent == nil, "failed cycle check should not change Root parent")
	end)

	run_case(results, "start enters chain", function()
		local log: { string } = {}
		local context: TestContext = { Label = "boot" }
		local machine, _, a = create_machine(log)

		assert(machine:SetInitial(a))
		assert(machine:Start(context))
		assert(machine:IsRunning())
		assert(machine:GetCurrent() == a, "machine should start on the initial state")
		assert(not machine:Start(context), "starting an already running machine should fail")

		expect_events(log, {
			"enter:Root:boot",
			"enter:A:boot",
		}, "start")
	end)

	run_case(results, "update walks active path", function()
		local log: { string } = {}
		local context: TestContext = { Label = "boot" }
		local machine, _, a = create_machine(log)

		assert(machine:SetInitial(a))
		assert(machine:Start(context))
		machine:Update(0.5, context)

		expect_events(log, {
			"enter:Root:boot",
			"enter:A:boot",
			"update:Root:boot:0.5",
			"update:A:boot:0.5",
		}, "first update")
	end)

	run_case(results, "transition to leaf path", function()
		local log: { string } = {}
		local context: TestContext = { Label = "boot" }
		local machine, _, a, _, leaf = create_machine(log)

		assert(machine:SetInitial(a))
		assert(machine:Start(context))
		machine:Update(0.5, context)
		assert(machine:Transition(leaf, context))
		assert(machine:GetCurrent() == leaf, "machine should transition to Leaf")

		expect_events(log, {
			"enter:Root:boot",
			"enter:A:boot",
			"update:Root:boot:0.5",
			"update:A:boot:0.5",
			"exit:A:boot",
			"enter:B:boot",
			"enter:Leaf:boot",
		}, "transition to leaf")
	end)

	run_case(results, "transition to root and back", function()
		local log: { string } = {}
		local context: TestContext = { Label = "boot" }
		local machine, root, a, _, leaf = create_machine(log)

		assert(machine:SetInitial(a))
		assert(machine:Start(context))
		machine:Update(0.5, context)
		assert(machine:Transition(leaf, context))
		machine:Update(0.25, context)
		assert(machine:Transition(root, context))
		assert(machine:GetCurrent() == root, "machine should transition back to Root")
		machine:Update(0.1, context)
		assert(machine:Transition(a, context))
		assert(machine:GetCurrent() == a, "machine should transition back to A")

		expect_events(log, {
			"enter:Root:boot",
			"enter:A:boot",
			"update:Root:boot:0.5",
			"update:A:boot:0.5",
			"exit:A:boot",
			"enter:B:boot",
			"enter:Leaf:boot",
			"update:Root:boot:0.25",
			"update:B:boot:0.25",
			"update:Leaf:boot:0.25",
			"exit:Leaf:boot",
			"exit:B:boot",
			"update:Root:boot:0.1",
			"enter:A:boot",
		}, "transition back to A")
	end)

	run_case(results, "stop exits active chain", function()
		local log: { string } = {}
		local context: TestContext = { Label = "boot" }
		local machine, _, a, _, leaf = create_machine(log)

		assert(machine:SetInitial(a))
		assert(machine:Start(context))
		machine:Update(0.5, context)
		assert(machine:Transition(leaf, context))
		machine:Update(0.25, context)
		assert(machine:Stop(context))
		assert(not machine:IsRunning())
		assert(machine:GetCurrent() == nil, "machine should clear the current state on stop")
		machine:Update(0.2, context)

		expect_events(log, {
			"enter:Root:boot",
			"enter:A:boot",
			"update:Root:boot:0.5",
			"update:A:boot:0.5",
			"exit:A:boot",
			"enter:B:boot",
			"enter:Leaf:boot",
			"update:Root:boot:0.25",
			"update:B:boot:0.25",
			"update:Leaf:boot:0.25",
			"exit:Leaf:boot",
			"exit:B:boot",
			"exit:Root:boot",
		}, "stop")
	end)

	Craftsman.PrintUtil:ListPrint("StateMachine Test Results", { "Case", "Status", "Message" }, results)
end

return test
