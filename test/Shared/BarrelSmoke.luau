--!nonstrict
--[[
    FileName    > BarrelSmoke.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 16/07/2026

    Smoke test for the lazy Craftsman barrel (P1.2), for things only Roblox can answer.

    The lune harness stubs `require`, so it can prove the memoisation semantics but not
    that Roblox resolves a string require deferred inside a closure. That is the whole
    assumption the barrel rests on, and it is what check 2 below exists for.

    Run by the module loader from test/Server and test/Client during a normal boot, so
    the laziness checks are measuring a real startup rather than a synthetic one.
--]]

const Craftsman = require("@game/ReplicatedStorage/Packages/Craftsman")

local BarrelSmoke = {}

-- Every export the barrel promises, in declaration order.
local EXPORTS = {
	"Component",
	"Debounce",
	"Concurrency",
	"Queue",
	"State",
	"Machine",
	"Pathfind",
	"Spring",
	"Entity",
	"DataServer",
	"DataClient",
	"MarketServer",
	"MarketClient",
	"StateMachine",
	"StateMachineServer",
	"StateMachineClient",
	"StoreServer",
	"StoreClient",
	"InputUtil",
	"InterfaceUtil",
	"PrintUtil",
	"TableUtil",
	"WorldUtil",
	"AnimationUtil",
	"SoundUtil",
	"TweenUtil",
	"Tag",
	"MathUtil",
	"StringUtil",
	"Config",
	"Store",
}

local SERVER_ONLY = {
	DataServer = true,
	MarketServer = true,
	StateMachineServer = true,
	StoreServer = true,
}

-- Shared/Bootstrap touches Component, Entity, and the Data/Market/StateMachine/Store
-- pairs before the loader runs. These are the exports it never mentions, so if the
-- barrel is lazy they must still be unresolved by the time Start is called.
local UNTOUCHED_BY_BOOTSTRAP = {
	"Pathfind",
	"WorldUtil",
	"MathUtil",
	"Tag",
	"TweenUtil",
}

--[[
	Reports against the raw output rather than PrintUtil, so the test does not depend
	on the barrel it is testing.
]]
function BarrelSmoke.Run(context: "server" | "client"): number
	local failures = 0
	local checks = 0

	local function check(name: string, ok: boolean, detail: string?)
		checks += 1
		if not ok then
			failures += 1
			warn(`[BarrelSmoke/{context}] FAIL  {name}` .. (if detail then `  -- {detail}` else ""))
		end
	end

	-- 1. Laziness survived a real boot: untouched exports are still unresolved.
	--    rawget bypasses __index, so this observes without resolving.
	for _, name in UNTOUCHED_BY_BOOTSTRAP do
		check(
			`{name} unresolved before first access`,
			rawget(Craftsman :: any, name) == nil,
			"already resolved -- the barrel loaded eagerly"
		)
	end

	-- 2. THE critical one: a require("@self/...") deferred inside a closure must
	--    actually resolve under Roblox, not just under the lune stub.
	local resolved, first = pcall(function()
		return Craftsman.Pathfind
	end)
	check("deferred string require resolves", resolved and first ~= nil, tostring(first))

	-- 3. It memoises: the resolved module is written back as a raw field.
	check("memoised as raw field after access", rawget(Craftsman :: any, "Pathfind") ~= nil)

	local second = Craftsman.Pathfind
	check("same identity on repeat access", first == second)

	-- 4. Every export still resolves, and server-only ones keep their nil-on-client
	--    behaviour exactly as before the barrel became lazy.
	for _, name in EXPORTS do
		local ok, value = pcall(function()
			return (Craftsman :: any)[name]
		end)

		if not ok then
			check(`{name} resolves`, false, tostring(value))
			continue
		end

		if SERVER_ONLY[name] and context == "client" then
			check(`{name} is nil on client`, value == nil, "server-only export leaked to the client")
		else
			check(`{name} resolves`, value ~= nil, "resolved to nil")
		end
	end

	-- 5. An unknown key is nil, not an error.
	local ok, value = pcall(function()
		return (Craftsman :: any).NotARealExport
	end)
	check("unknown key returns nil", ok and value == nil, tostring(value))

	if failures == 0 then
		print(`[BarrelSmoke/{context}] all {checks} checks passed`)
	else
		warn(`[BarrelSmoke/{context}] {failures} of {checks} checks FAILED`)
	end

	return failures
end

return BarrelSmoke
