--!nonstrict
--[[
	FileName    > DebounceTest.luau
	Author      > AveryArk
	Contact     > Twitter: https://twitter.com/averyark_
	Created     > 11/06/2026
--]]

const Craftsman = require("@game/ReplicatedStorage/Packages/Craftsman")

local test = Craftsman.Component.new({})

local function run_case(results: { { string } }, case_name: string, callback: () -> ())
	local ok, err = pcall(callback)
	table.insert(results, {
		case_name,
		if ok then "success" else "fail",
		if ok then "" else tostring(err),
	})
end

function test:Start()
	Craftsman.PrintUtil:Print("Debounce & Throttle test started")

	local results = {}

	run_case(results, "Debounce trailing: executes after wait time", function()
		local call_count = 0
		local last_args = nil
		local debounced = Craftsman.Debounce.new(function(x)
			call_count += 1
			last_args = x
		end, 0.05)

		debounced("first")
		debounced("second")
		debounced("third")

		assert(call_count == 0, "Should not execute immediately when trailing = true")
		assert(debounced:IsPending() == true, "Should be pending execution")

		task.wait(0.08)

		assert(call_count == 1, "Should execute exactly once after silence. Actual count: " .. tostring(call_count))
		assert(last_args == "third", "Should execute with the last arguments passed")
		assert(debounced:IsPending() == false, "Should no longer be pending")
	end)

	run_case(results, "Debounce leading: executes immediately on leading edge", function()
		local call_count = 0
		local last_args = nil
		local debounced = Craftsman.Debounce.new(function(x)
			call_count += 1
			last_args = x
		end, 0.05, { leading = true, trailing = false })

		local res1 = debounced("first")
		local res2 = debounced("second")

		assert(call_count == 1, "Should execute immediately on the first call")
		assert(last_args == "first", "Should execute with the first call's arguments")

		task.wait(0.08)

		assert(call_count == 1, "Should not execute on the trailing edge")
	end)

	run_case(results, "Debounce leading & trailing: executes on both edges", function()
		local call_count = 0
		local history = {}
		local debounced = Craftsman.Debounce.new(function(x)
			call_count += 1
			table.insert(history, x)
		end, 0.05, { leading = true, trailing = true })

		debounced("A") -- runs immediately (leading)
		debounced("B") -- schedules trailing
		debounced("C") -- schedules trailing (overwrites B)

		assert(call_count == 1, "Should run immediately for A. Actual: " .. tostring(call_count))
		assert(history[1] == "A", "First run should be A")

		task.wait(0.08)

		assert(call_count == 2, "Should run trailing edge for C. Actual: " .. tostring(call_count))
		assert(history[2] == "C", "Second run should be C")
	end)

	run_case(results, "Debounce Cancel: cancels pending execution", function()
		local call_count = 0
		local debounced = Craftsman.Debounce.new(function()
			call_count += 1
		end, 0.05)

		debounced()
		assert(debounced:IsPending() == true, "Should be pending")

		debounced:Cancel()
		assert(debounced:IsPending() == false, "Should not be pending after Cancel")

		task.wait(0.08)
		assert(call_count == 0, "Should not execute if cancelled")
	end)

	run_case(results, "Debounce Flush: executes pending immediately", function()
		local call_count = 0
		local last_args = nil
		local debounced = Craftsman.Debounce.new(function(x)
			call_count += 1
			last_args = x
		end, 0.05)

		debounced("hello")
		assert(debounced:IsPending() == true, "Should be pending")

		debounced:Flush()
		assert(call_count == 1, "Should execute immediately on Flush")
		assert(last_args == "hello", "Should carry arguments")
		assert(debounced:IsPending() == false, "Should no longer be pending after Flush")

		task.wait(0.08)
		assert(call_count == 1, "Should not execute again after trailing timer expires")
	end)

	run_case(results, "Throttle: throttles execution rate", function()
		local call_count = 0
		local history = {}
		local throttled = Craftsman.Debounce.throttle(function(x)
			call_count += 1
			table.insert(history, x)
		end, 0.05)

		throttled(1) -- leading edge: runs immediately
		throttled(2) -- ignored, but schedules trailing
		throttled(3) -- ignored, but schedules trailing (overwrites 2)

		assert(call_count == 1, "Should execute immediately on leading edge. Actual: " .. tostring(call_count))
		assert(history[1] == 1)

		task.wait(0.03)
		throttled(4) -- wait time 0.05 not met, schedules trailing (overwrites 3)

		task.wait(0.08) -- total 0.11 elapsed, trailing edge should have run (at 0.05)
		assert(call_count == 2, "Should execute once on trailing edge. Actual: " .. tostring(call_count))
		assert(history[2] == 4, "Should run with latest argument (4)")

		throttled(5) -- runs immediately because previous throttled interval finished and timer was idle
		assert(call_count == 3)
		assert(history[3] == 5)

		task.wait(0.08)
	end)

	run_case(results, "Debounce: handles nil and multiple arguments correctly", function()
		local received_args = nil
		local arg_count = 0
		local debounced = Craftsman.Debounce.new(function(...)
			received_args = { ... }
			arg_count = select("#", ...)
		end, 0.01)

		debounced(1, nil, 3, nil)

		task.wait(0.03)

		assert(arg_count == 4, "Should preserve exact argument count (4). Actual: " .. tostring(arg_count))
		assert(received_args[1] == 1, "Arg 1 should be 1")
		assert(received_args[2] == nil, "Arg 2 should be nil")
		assert(received_args[3] == 3, "Arg 3 should be 3")
		assert(received_args[4] == nil, "Arg 4 should be nil")
	end)

	Craftsman.PrintUtil:ListPrint("Debounce & Throttle Test Results", { "Case", "Status", "Message" }, results)
end

return test
