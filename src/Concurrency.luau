--!strict
--[[
    FileName    > Concurrency.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 11/06/2026
--]]

local Concurrency = {}

--
local AsyncLock = {}
AsyncLock.__index = AsyncLock
--

local function new_async_lock()
	--
	const self = setmetatable({
		_Locks = setmetatable({} :: { [unknown]: boolean }, { __mode = "k" }),
	}, AsyncLock)
	--

	return self
end

--
export type AsyncLock = typeof(new_async_lock())
--

function AsyncLock.Execute<A...>(self: AsyncLock, key: unknown, callback: (A...) -> ...unknown, ...: A...): boolean
	--
	if self._Locks[key] then
		return false
	end

	self._Locks[key] = true
	--

	--
	task.spawn(function(...)
		const success, err = pcall(callback, ...)
		self._Locks[key] = nil

		if success then
			return
		end

		warn(`Error in AsyncLock callback: {err}`)
	end, ...)
	--

	return true
end

function AsyncLock.IsLocked(self: AsyncLock, key: unknown): boolean
	return self._Locks[key] == true
end

function AsyncLock.Release(self: AsyncLock, key: unknown)
	--
	self._Locks[key] = nil
	--
end

--
AsyncLock.new = new_async_lock
--

--
local KeyedDebounce = {}
KeyedDebounce.__index = KeyedDebounce
--

local function new_keyed_debounce(cooldown: number)
	--
	const self = setmetatable({
		_Cooldown = cooldown,
		_LastCalls = setmetatable({} :: { [unknown]: number }, { __mode = "k" }),
	}, KeyedDebounce)
	--

	return self
end

--
export type KeyedDebounce = typeof(new_keyed_debounce(0))
--

function KeyedDebounce.Call<A...>(self: KeyedDebounce, key: unknown, callback: (A...) -> ...unknown, ...: A...): boolean
	--
	const now = os.clock()
	const last_call = self._LastCalls[key]

	if last_call and (now - last_call < self._Cooldown) then
		return false
	end
	--

	--
	self._LastCalls[key] = now
	task.spawn(callback, ...)
	--

	return true
end

function KeyedDebounce.Clear(self: KeyedDebounce, key: unknown)
	--
	self._LastCalls[key] = nil
	--
end

--
KeyedDebounce.new = new_keyed_debounce
--

--
Concurrency.AsyncLock = AsyncLock
Concurrency.KeyedDebounce = KeyedDebounce
--

return Concurrency
