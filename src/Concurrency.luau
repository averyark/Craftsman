--!nonstrict
--[[
    FileName    > Concurrency.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 11/06/2026
--]]

const Concurrency = {}

local AsyncLock = {}
AsyncLock.__index = AsyncLock

local function new_async_lock()
	local self = setmetatable({
		_Locks = setmetatable({}, { __mode = "k" }),
	}, AsyncLock)
	return self
end

export type AsyncLock = typeof(new_async_lock())

function AsyncLock.Execute(self: AsyncLock, key: any, callback: (...any) -> ...any, ...: any): boolean
	if self._Locks[key] then
		return false
	end
	self._Locks[key] = true

	task.spawn(function(...)
		local success, err = pcall(callback, ...)
		self._Locks[key] = nil

		if not success then
			warn("Error in AsyncLock callback: " .. tostring(err))
		end
	end, ...)

	return true
end

function AsyncLock.IsLocked(self: AsyncLock, key: any): boolean
	return self._Locks[key] == true
end

function AsyncLock.Release(self: AsyncLock, key: any)
	self._Locks[key] = nil
end

AsyncLock.new = new_async_lock

local KeyedDebounce = {}
KeyedDebounce.__index = KeyedDebounce

local function new_keyed_debounce(cooldown: number)
	local self = setmetatable({
		_Cooldown = cooldown,
		_LastCalls = setmetatable({}, { __mode = "k" }),
	}, KeyedDebounce)
	return self
end

export type KeyedDebounce = typeof(new_keyed_debounce(0))

function KeyedDebounce.Call(self: KeyedDebounce, key: any, callback: (...any) -> ...any, ...: any): boolean
	local now = os.clock()
	local last_call = self._LastCalls[key]

	if last_call and (now - last_call < self._Cooldown) then
		return false
	end

	self._LastCalls[key] = now
	task.spawn(callback, ...)
	return true
end

function KeyedDebounce.Clear(self: KeyedDebounce, key: any)
	self._LastCalls[key] = nil
end

KeyedDebounce.new = new_keyed_debounce

-- Export classes
Concurrency.AsyncLock = AsyncLock
Concurrency.KeyedDebounce = KeyedDebounce

return Concurrency
