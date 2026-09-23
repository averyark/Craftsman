--!strict
--[[
    FileName    > Debounce.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 11/06/2026
--]]

local Debounce = {}

local Debounced = {}
Debounced.__index = Debounced

--
export type DebounceOptions = {
	leading: boolean?,
	trailing: boolean?,
	maxWait: number?,
}
--

local function new(func: (...any) -> ...any, wait: number, options: DebounceOptions?)
	--
	const self = setmetatable({}, Debounced)

	self._Func = func
	self._Wait = wait
	self._Leading = false
	self._Trailing = true
	self._Maxing = false
	self._MaxWait = 0
	--

	--
	if options and options.leading ~= nil then
		self._Leading = options.leading
	end

	if options and options.trailing ~= nil then
		self._Trailing = options.trailing
	end

	if options and options.maxWait ~= nil then
		self._Maxing = true
		self._MaxWait = math.max(0, options.maxWait)
	end
	--

	--
	self._LastArgs = nil :: { any }?
	self._LastArgsCount = 0
	self._LastCallTime = nil :: number?
	self._LastInvokeTime = 0
	self._TimerThread = nil :: thread?
	self._LastResult = nil :: { any }?
	self._LastResultCount = 0
	--

	--
	self.Call = function(...: any): ...any
		const arg_count = select("#", ...)

		if arg_count > 0 and select(1, ...) == self then
			return Debounced.Call(self, select(2, ...))
		end

		return Debounced.Call(self, ...)
	end
	--

	return self
end

--
export type Debounced = typeof(new(...))
--

local function unpack_last_result(self: Debounced): ...any
	--
	if not self._LastResult then
		return nil
	end
	--

	return unpack(self._LastResult, 1, self._LastResultCount)
end

local function ensure_timer(self: Debounced)
	--
	if self._TimerThread ~= nil then
		return
	end
	--

	--
	self._TimerThread = task.delay(self._Wait, function()
		self:_TimerExpired()
	end)
	--
end

function Debounced._InvokeFunc(self: Debounced, time: number): ...any
	--
	const args = self._LastArgs
	const count = self._LastArgsCount
	--

	--
	self._LastArgs = nil
	self._LastArgsCount = 0
	self._LastInvokeTime = time
	--

	--
	if args then
		const result = { self._Func(unpack(args, 1, count)) }
		self._LastResult = result
		self._LastResultCount = #result
	end
	--

	return unpack_last_result(self)
end

function Debounced._RemainingWait(self: Debounced, time: number): number
	--
	const time_since_last_call = time - (self._LastCallTime or 0)
	const time_since_last_invoke = time - self._LastInvokeTime
	const time_waiting = self._Wait - time_since_last_call

	if not self._Maxing then
		return time_waiting
	end
	--

	return math.min(time_waiting, self._MaxWait - time_since_last_invoke)
end

function Debounced._ShouldInvoke(self: Debounced, time: number): boolean
	--
	const time_since_last_call = time - (self._LastCallTime or 0)
	const time_since_last_invoke = time - self._LastInvokeTime
	--

	return self._LastCallTime == nil
		or time_since_last_call >= self._Wait
		or time_since_last_call < 0
		or (self._Maxing and time_since_last_invoke >= self._MaxWait)
end

function Debounced._TimerExpired(self: Debounced)
	--
	const time = os.clock()

	if not self:_ShouldInvoke(time) then
		self._TimerThread = task.delay(self:_RemainingWait(time), function()
			self:_TimerExpired()
		end)
		return
	end
	--

	--
	self._TimerThread = nil

	if self._Trailing and self._LastArgs then
		self:_InvokeFunc(time)
		return
	end
	--

	--
	self._LastArgs = nil
	self._LastArgsCount = 0
	--
end

function Debounced._LeadingEdge(self: Debounced, time: number): ...any
	--
	self._LastInvokeTime = time
	self._TimerThread = task.delay(self._Wait, function()
		self:_TimerExpired()
	end)
	--

	--
	if self._Leading then
		return self:_InvokeFunc(time)
	end
	--

	return unpack_last_result(self)
end

function Debounced.Cancel(self: Debounced)
	--
	if self._TimerThread then
		task.cancel(self._TimerThread)
		self._TimerThread = nil
	end
	--

	--
	self._LastInvokeTime = 0
	self._LastArgs = nil
	self._LastArgsCount = 0
	self._LastCallTime = nil
	--
end

function Debounced.Flush(self: Debounced): ...any
	--
	if self._TimerThread == nil then
		return unpack_last_result(self)
	end
	--

	--
	const time = os.clock()
	task.cancel(self._TimerThread)
	self._TimerThread = nil
	--

	--
	if self._Trailing and self._LastArgs then
		return self:_InvokeFunc(time)
	end
	--

	--
	self._LastArgs = nil
	self._LastArgsCount = 0
	--

	return unpack_last_result(self)
end

function Debounced.IsPending(self: Debounced): boolean
	return self._TimerThread ~= nil
end

function Debounced.Call(self: Debounced, ...: any): ...any
	--
	const time = os.clock()
	const is_invoking = self:_ShouldInvoke(time)
	--

	--
	self._LastArgs = { ... }
	self._LastArgsCount = select("#", ...)
	self._LastCallTime = time
	--

	--
	if not is_invoking then
		ensure_timer(self)
		return unpack_last_result(self)
	end

	if self._TimerThread == nil then
		return self:_LeadingEdge(time)
	end

	if not self._Maxing then
		return unpack_last_result(self)
	end
	--

	--
	task.cancel(self._TimerThread)
	self._TimerThread = task.delay(self._Wait, function()
		self:_TimerExpired()
	end)
	--

	return self:_InvokeFunc(time)
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
): Debounced
	--
	local leading = true
	local trailing = true

	if options and options.leading ~= nil then
		leading = options.leading
	end

	if options and options.trailing ~= nil then
		trailing = options.trailing
	end
	--

	return new(func, wait, {
		leading = leading,
		trailing = trailing,
		maxWait = wait,
	})
end

--
Debounce.new = new
--

return Debounce
