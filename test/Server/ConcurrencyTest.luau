--!nonstrict
--[[
	FileName    > ConcurrencyTest.luau
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
	Craftsman.PrintUtil:Print("Concurrency (AsyncLock & KeyedDebounce) test started")

	local results = {}

	-- Test keys (using dummy tables/objects)
	local key_a = { name = "PlayerA" }
	local key_b = { name = "PlayerB" }

	----------------------------------------------------------------------------
	-- AsyncLock Tests
	----------------------------------------------------------------------------

	run_case(results, "AsyncLock: blocks subsequent calls while yielding", function()
		local lock = Craftsman.Concurrency.AsyncLock.new()
		local execution_count = 0
		local done_yielding = false

		local success1 = lock:Execute(key_a, function()
			task.wait(0.05)
			execution_count += 1
			done_yielding = true
		end)

		assert(success1 == true, "First execution should start successfully")
		assert(lock:IsLocked(key_a) == true, "Key should be locked immediately")

		local success2 = lock:Execute(key_a, function()
			execution_count += 1
		end)

		assert(success2 == false, "Second execution should be blocked by active lock")
		assert(execution_count == 0, "Callback should not have run yet")

		task.wait(0.08)

		assert(done_yielding == true, "Yielding task should have finished")
		assert(execution_count == 1, "Only the first callback should have executed")
		assert(lock:IsLocked(key_a) == false, "Key should be unlocked after completion")
	end)

	run_case(results, "AsyncLock: releases lock even if callback errors", function()
		local lock = Craftsman.Concurrency.AsyncLock.new()

		local success1 = lock:Execute(key_a, function()
			error("Intentionally failing async lock task")
		end)

		assert(success1 == true, "First execution starts")
		task.wait(0.02) -- Wait for task.spawn thread to execute and fail

		assert(lock:IsLocked(key_a) == false, "Lock should be released after callback error")

		local success2 = lock:Execute(key_a, function()
			-- do nothing
		end)
		assert(success2 == true, "Next execution should be allowed to start after error release")
	end)

	run_case(results, "AsyncLock: handles key release manually", function()
		local lock = Craftsman.Concurrency.AsyncLock.new()

		lock:Execute(key_a, function()
			task.wait(0.1)
		end)

		assert(lock:IsLocked(key_a) == true, "Should be locked")

		lock:Release(key_a)
		assert(lock:IsLocked(key_a) == false, "Should be unlocked after manual release")

		local success = lock:Execute(key_a, function()
			-- do nothing
		end)
		assert(success == true, "Should start execution immediately after manual release")
	end)

	----------------------------------------------------------------------------
	-- KeyedDebounce Tests
	----------------------------------------------------------------------------

	run_case(results, "KeyedDebounce: rate-limits calls on a key during cooldown", function()
		local limiter = Craftsman.Concurrency.KeyedDebounce.new(0.05)
		local run_count = 0

		local success1 = limiter:Call(key_a, function()
			run_count += 1
		end)
		assert(success1 == true, "First call should succeed")

		local success2 = limiter:Call(key_a, function()
			run_count += 1
		end)
		assert(success2 == false, "Second call within cooldown should be ignored")

		task.wait(0.08)

		local success3 = limiter:Call(key_a, function()
			run_count += 1
		end)
		assert(success3 == true, "Call after cooldown should succeed")
		task.wait(0.02) -- Allow task.spawns to execute

		assert(run_count == 2, "Only two calls should have executed. Actual: " .. tostring(run_count))
	end)

	run_case(results, "KeyedDebounce: rate limits independently per key", function()
		local limiter = Craftsman.Concurrency.KeyedDebounce.new(0.05)
		local a_runs = 0
		local b_runs = 0

		limiter:Call(key_a, function()
			a_runs += 1
		end)

		local success_b = limiter:Call(key_b, function()
			b_runs += 1
		end)

		assert(success_b == true, "Limiter on key B should succeed independently of key A")
		task.wait(0.02)

		assert(a_runs == 1)
		assert(b_runs == 1)
	end)

	run_case(results, "KeyedDebounce: Clear removes cooldown immediately", function()
		local limiter = Craftsman.Concurrency.KeyedDebounce.new(0.05)
		local run_count = 0

		limiter:Call(key_a, function()
			run_count += 1
		end)

		local success_before_clear = limiter:Call(key_a, function()
			run_count += 1
		end)
		assert(success_before_clear == false, "Should be rate-limited")

		limiter:Clear(key_a)

		local success_after_clear = limiter:Call(key_a, function()
			run_count += 1
		end)
		assert(success_after_clear == true, "Should succeed immediately after clearing cooldown")

		task.wait(0.02)
		assert(run_count == 2, "Both allowed calls should execute")
	end)

	Craftsman.PrintUtil:ListPrint(
		"Concurrency (AsyncLock & KeyedDebounce) Test Results",
		{ "Case", "Status", "Message" },
		results
	)
end

return test
