--!nonstrict
--[[
    FileName    > Debounce.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 11/06/2026
--]]

export type DebounceOptions = {
	leading: boolean?,
	trailing: boolean?,
	maxWait: number?,
}

local Debounce = {}

local Debounced = {}
Debounced.__index = Debounced

local function new(func: (...any) -> ...any, wait: number, options: DebounceOptions?)
	local self = setmetatable({}, Debounced)

	self._Func = func
	self._Wait = wait
	self._Leading = false
	self._Trailing = true
	self._Maxing = false
	self._MaxWait = 0

	if options then
		if options.leading ~= nil then
			self._Leading = options.leading
		end
		if options.trailing ~= nil then
			self._Trailing = options.trailing
		end
		if options.maxWait ~= nil then
			self._Maxing = true
			self._MaxWait = math.max(0, options.maxWait)
		end
	end

	self._LastArgs = nil
	self._LastArgsCount = 0
	self._LastCallTime = nil
	self._LastInvokeTime = 0
	self._TimerThread = nil
	self._LastResult = nil
	self._LastResultCount = 0

	-- Bind Call to support direct event connections without losing 'self' context
	self.Call = function(...: any): ...any
		local arg_count = select("#", ...)
		if arg_count > 0 and select(1, ...) == self then
			return Debounced.Call(self, select(2, ...))
		end
		return Debounced.Call(self, ...)
	end

	return self
end

export type Debounced = typeof(new(...))

function Debounced._InvokeFunc(self: Debounced, time: number): ...any
	local args = self._LastArgs
	local count = self._LastArgsCount

	self._LastArgs = nil
	self._LastArgsCount = 0
	self._LastInvokeTime = time

	if args then
		local result = { self._Func(unpack(args, 1, count)) }
		self._LastResult = result
		self._LastResultCount = #result
	end

	if self._LastResult then
		return unpack(self._LastResult, 1, self._LastResultCount)
	end
	return nil
end

function Debounced._RemainingWait(self: Debounced, time: number): number
	local time_since_last_call = time - (self._LastCallTime or 0)
	local time_since_last_invoke = time - self._LastInvokeTime
	local time_waiting = self._Wait - time_since_last_call

	if self._Maxing then
		return math.min(time_waiting, self._MaxWait - time_since_last_invoke)
	end
	return time_waiting
end

function Debounced._ShouldInvoke(self: Debounced, time: number): boolean
	local time_since_last_call = time - (self._LastCallTime or 0)
	local time_since_last_invoke = time - self._LastInvokeTime

	return self._LastCallTime == nil
		or time_since_last_call >= self._Wait
		or time_since_last_call < 0
		or (self._Maxing and time_since_last_invoke >= self._MaxWait)
end

function Debounced._TimerExpired(self: Debounced)
	local time = os.clock()
	if self:_ShouldInvoke(time) then
		self._TimerThread = nil
		if self._Trailing and self._LastArgs then
			self:_InvokeFunc(time)
		else
			self._LastArgs = nil
			self._LastArgsCount = 0
		end
		return
	end

	self._TimerThread = task.delay(self:_RemainingWait(time), function()
		self:_TimerExpired()
	end)
end

function Debounced._LeadingEdge(self: Debounced, time: number): ...any
	self._LastInvokeTime = time
	self._TimerThread = task.delay(self._Wait, function()
		self:_TimerExpired()
	end)
	if self._Leading then
		return self:_InvokeFunc(time)
	end
	if self._LastResult then
		return unpack(self._LastResult, 1, self._LastResultCount)
	end
	return nil
end

function Debounced.Cancel(self: Debounced)
	if self._TimerThread then
		task.cancel(self._TimerThread)
		self._TimerThread = nil
	end
	self._LastInvokeTime = 0
	self._LastArgs = nil
	self._LastArgsCount = 0
	self._LastCallTime = nil
end

function Debounced.Flush(self: Debounced): ...any
	if self._TimerThread == nil then
		if self._LastResult then
			return unpack(self._LastResult, 1, self._LastResultCount)
		end
		return nil
	end

	local time = os.clock()
	task.cancel(self._TimerThread)
	self._TimerThread = nil

	if self._Trailing and self._LastArgs then
		return self:_InvokeFunc(time)
	end

	self._LastArgs = nil
	self._LastArgsCount = 0

	if self._LastResult then
		return unpack(self._LastResult, 1, self._LastResultCount)
	end
	return nil
end

function Debounced.IsPending(self: Debounced): boolean
	return self._TimerThread ~= nil
end

function Debounced.Call(self: Debounced, ...: any): ...any
	local time = os.clock()
	local is_invoking = self:_ShouldInvoke(time)

	self._LastArgs = { ... }
	self._LastArgsCount = select("#", ...)
	self._LastCallTime = time

	if is_invoking then
		if self._TimerThread == nil then
			return self:_LeadingEdge(self._LastCallTime)
		end
		if self._Maxing then
			task.cancel(self._TimerThread)
			self._TimerThread = task.delay(self._Wait, function()
				self:_TimerExpired()
			end)
			return self:_InvokeFunc(self._LastCallTime)
		end
	end

	if self._TimerThread == nil then
		self._TimerThread = task.delay(self._Wait, function()
			self:_TimerExpired()
		end)
	end

	if self._LastResult then
		return unpack(self._LastResult, 1, self._LastResultCount)
	end
	return nil
end

function Debounced.__call(self: Debounced, ...: any): ...any
	return Debounced.Call(self, ...)
end

function Debounce.throttle(
	func: (...any) -> ...any,
	wait: number,
	options: {
		leading: boolean?,
		trailing: boolean?,
	}?
)
	local leading = true
	local trailing = true

	if options then
		if options.leading ~= nil then
			leading = options.leading
		end
		if options.trailing ~= nil then
			trailing = options.trailing
		end
	end

	return new(func, wait, {
		leading = leading,
		trailing = trailing,
		maxWait = wait,
	})
end

Debounce.new = new

return Debounce
