--!nonstrict
--[[
    FileName    > Queue.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 23/05/2026
--]]

const Promise = require("../../../Promise")
const Signal = require("./Signal")

local QueueModule = {}

local Queue = {}
Queue.__index = Queue

export type QueueOptions = {
	DefaultMaxRetries: number?,
	DefaultRetryDelay: number?,
	DefaultBackoffFactor: number?,
	DefaultJitterFactor: number?,
	DefaultTimeout: number?,
	MaxSize: number?,
	RetryOn: ((error_value: any, attempt: number, context: any, entry: any) -> boolean)?,
}

export type EnqueueOptions = {
	Key: any?,
	Context: any?,
	Timeout: number?,
	MaxRetries: number?,
	RetryDelay: number?,
	BackoffFactor: number?,
	JitterFactor: number?,
	RetryOn: ((error_value: any, attempt: number, context: any, entry: any) -> boolean)?,
}

type RetryOnCallback = (error_value: any, attempt: number, context: any, entry: QueueEntry) -> boolean
type QueuePromise = typeof(Promise.new(function() end))
type QueueEntry = {
	Id: number,
	Key: any,
	Executor: (context: any, attempt: number, id: number) -> any,
	Context: any,
	Timeout: number?,
	MaxRetries: number,
	RetryDelay: number,
	BackoffFactor: number,
	JitterFactor: number,
	RetryOn: RetryOnCallback?,
	CreatedAt: number,
	Attempts: number,
	Completed: boolean,
	CancelRequested: boolean,
	CancelReason: string?,
	Status: string,
	Promise: QueuePromise,
	Resolve: (value: any?) -> (),
	Reject: (reason: any?) -> (),
	Result: any?,
}

local EntryStatus = {
	Pending = "Pending",
	Running = "Running",
	Succeeded = "Succeeded",
	Failed = "Failed",
	Cancelled = "Cancelled",
}

local function now_seconds(): number
	return os.clock()
end

local function random_jitter(base_delay: number, jitter_factor: number): number
	if jitter_factor <= 0 then
		return base_delay
	end

	local spread = base_delay * jitter_factor
	if spread <= 0 then
		return base_delay
	end

	return base_delay + (math.random() * 2 * spread - spread)
end

local function remove_pending_by_id(pending: { QueueEntry }, id: number): QueueEntry?
	for index = 1, #pending do
		if pending[index].Id == id then
			return table.remove(pending, index)
		end
	end

	return nil
end

local function clone_map(source: { [any]: any }): { [any]: any }
	local output = {}
	for key, value in next, source do
		output[key] = value
	end
	return output
end

function QueueModule.new(options: QueueOptions?)
	local resolved_options: QueueOptions = (type(options) == "table" and options or {}) :: QueueOptions

	local self = setmetatable({}, Queue)

	self._NextId = 0
	self._Pending = {}
	self._Entries = {} :: { [number]: QueueEntry }
	self._KeyIndex = {}
	self._DrainWaiters = {} :: { (boolean) -> () }
	self._RunningEntry = nil
	self._Running = false
	self._Paused = false
	self._Closed = false
	self._SuppressDrainResolution = false

	self._DefaultMaxRetries = resolved_options.DefaultMaxRetries or 0
	self._DefaultRetryDelay = resolved_options.DefaultRetryDelay or 0
	self._DefaultBackoffFactor = resolved_options.DefaultBackoffFactor or 1
	self._DefaultJitterFactor = resolved_options.DefaultJitterFactor or 0
	self._DefaultTimeout = resolved_options.DefaultTimeout
	self._MaxSize = resolved_options.MaxSize
	self._RetryOn = resolved_options.RetryOn

	self._Stats = {
		Enqueued = 0,
		Started = 0,
		Succeeded = 0,
		Failed = 0,
		Retried = 0,
		Cancelled = 0,
	}

	self.Enqueued = Signal.new()
	self.Started = Signal.new()
	self.Succeeded = Signal.new()
	self.Failed = Signal.new()
	self.Retried = Signal.new()
	self.Cancelled = Signal.new()
	self.Drained = Signal.new()

	return self
end

export type Queue = typeof(QueueModule.new(...))

function Queue._ResolveDefaults(self: Queue, options: EnqueueOptions?): EnqueueOptions
	local resolved_options: EnqueueOptions = (type(options) == "table" and options or {}) :: EnqueueOptions

	return {
		Key = resolved_options.Key,
		Context = resolved_options.Context,
		Timeout = if resolved_options.Timeout ~= nil then resolved_options.Timeout else self._DefaultTimeout,
		MaxRetries = if resolved_options.MaxRetries ~= nil
			then resolved_options.MaxRetries
			else self._DefaultMaxRetries,
		RetryDelay = if resolved_options.RetryDelay ~= nil
			then resolved_options.RetryDelay
			else self._DefaultRetryDelay,
		BackoffFactor = if resolved_options.BackoffFactor ~= nil
			then resolved_options.BackoffFactor
			else self._DefaultBackoffFactor,
		JitterFactor = if resolved_options.JitterFactor ~= nil
			then resolved_options.JitterFactor
			else self._DefaultJitterFactor,
		RetryOn = if resolved_options.RetryOn ~= nil then resolved_options.RetryOn else self._RetryOn,
	}
end

function Queue._ReleaseKey(self: Queue, entry: QueueEntry)
	local key = entry.Key
	if key ~= nil and self._KeyIndex[key] == entry.Id then
		self._KeyIndex[key] = nil
	end
end

function Queue._ResolveDrainWaiters(self: Queue)
	if self._SuppressDrainResolution then
		return
	end

	if #self._Pending > 0 or self._RunningEntry ~= nil then
		return
	end

	local waiters = self._DrainWaiters
	self._DrainWaiters = {}

	for index = 1, #waiters do
		waiters[index](true)
	end

	self.Drained:Fire(self:GetStats())
end

function Queue._RejectEntry(self: Queue, entry: QueueEntry, reason: any, should_count_cancel: boolean)
	if entry.Completed then
		return
	end

	entry.Completed = true
	self:_ReleaseKey(entry)
	self._Entries[entry.Id] = nil

	if should_count_cancel then
		entry.Status = EntryStatus.Cancelled
		self._Stats.Cancelled += 1
		self.Cancelled:Fire(entry.Id, reason, entry.Context, entry.Key)
	else
		entry.Status = EntryStatus.Failed
		self._Stats.Failed += 1
		self.Failed:Fire(entry.Id, reason, entry.Context, entry.Key, entry.Attempts)
	end

	entry.Reject(reason)
	self:_ResolveDrainWaiters()
end

function Queue._FulfillEntry(self: Queue, entry: QueueEntry, result: any)
	if entry.Completed then
		return
	end

	entry.Completed = true
	entry.Status = EntryStatus.Succeeded
	entry.Result = result

	self:_ReleaseKey(entry)
	self._Entries[entry.Id] = nil

	self._Stats.Succeeded += 1
	self.Succeeded:Fire(entry.Id, result, entry.Context, entry.Key, entry.Attempts)
	entry.Resolve(result)
	self:_ResolveDrainWaiters()
end

function Queue._ComputeRetryDelay(self: Queue, entry: QueueEntry): number
	local delay = math.max(0, entry.RetryDelay or 0)
	if delay <= 0 then
		return 0
	end

	local retries_used = math.max(0, entry.Attempts - 1)
	local factor = entry.BackoffFactor or 1
	if factor > 1 and retries_used > 0 then
		delay = delay * (factor ^ retries_used)
	end

	return math.max(0, random_jitter(delay, entry.JitterFactor or 0))
end

function Queue._CanRetry(self: Queue, entry: QueueEntry, error_value: any): boolean
	if entry.CancelRequested then
		return false
	end

	if entry.Attempts > entry.MaxRetries + 1 then
		return false
	end

	if type(entry.RetryOn) == "function" then
		local ok, value = pcall(entry.RetryOn, error_value, entry.Attempts, entry.Context, entry)
		if not ok then
			return false
		end

		return value == true
	end

	return entry.Attempts <= entry.MaxRetries
end

function Queue._ExecuteEntry(self: Queue, entry: QueueEntry)
	return Promise.new(function(resolve)
		local function step()
			if entry.CancelRequested then
				self:_RejectEntry(entry, entry.CancelReason or "Cancelled", true)
				resolve()
				return
			end

			entry.Attempts += 1
			entry.Status = EntryStatus.Running
			self._Stats.Started += 1
			self.Started:Fire(entry.Id, entry.Attempts, entry.Context, entry.Key)

			local promise = Promise.try(entry.Executor, entry.Context, entry.Attempts, entry.Id)

			if type(entry.Timeout) == "number" and entry.Timeout > 0 then
				promise = promise:timeout(entry.Timeout, "QueueTimeout")
			end

			promise
				:andThen(function(result)
					self:_FulfillEntry(entry, result)
					resolve()
				end)
				:catch(function(error_value)
					if self:_CanRetry(entry, error_value) then
						self._Stats.Retried += 1
						local delay = self:_ComputeRetryDelay(entry)
						self.Retried:Fire(entry.Id, error_value, entry.Attempts, delay, entry.Context, entry.Key)

						if delay > 0 then
							task.delay(delay, step)
						else
							step()
						end

						return
					end

					if entry.CancelRequested then
						self:_RejectEntry(entry, entry.CancelReason or "Cancelled", true)
					else
						self:_RejectEntry(entry, error_value, false)
					end

					resolve()
				end)
		end

		step()
	end)
end

function Queue._Pump(self: Queue)
	if self._Running or self._Paused or self._Closed then
		return
	end

	self._Running = true

	Promise.try(function()
		while not self._Paused and not self._Closed do
			local entry = table.remove(self._Pending, 1)
			if not entry then
				break
			end

			self._RunningEntry = entry
			self:_ExecuteEntry(entry):await()
			self._RunningEntry = nil
		end
	end):finally(function()
		self._Running = false
		self:_ResolveDrainWaiters()

		if not self._Paused and not self._Closed and #self._Pending > 0 then
			self:_Pump()
		end
	end)
end

function Queue.GetSize(self: Queue)
	local running = if self._RunningEntry ~= nil then 1 else 0
	return #self._Pending + running
end

function Queue.GetPendingCount(self: Queue)
	return #self._Pending
end

function Queue.IsPaused(self: Queue)
	return self._Paused
end

function Queue.IsClosed(self: Queue)
	return self._Closed
end

function Queue.GetStats(self: Queue)
	local stats = clone_map(self._Stats)
	stats.Pending = #self._Pending
	stats.HasRunning = self._RunningEntry ~= nil
	stats.Closed = self._Closed
	stats.Paused = self._Paused
	return stats
end

function Queue.Pause(self: Queue)
	self._Paused = true
end

function Queue.Resume(self: Queue)
	if self._Closed then
		return false
	end

	if not self._Paused then
		return true
	end

	self._Paused = false
	self:_Pump()
	return true
end

function Queue.Enqueue(
	self: Queue,
	executor: (context: any, attempt: number, id: number) -> any,
	options: EnqueueOptions?
): (QueuePromise, number?, boolean)
	if self._Closed then
		return Promise.reject("QueueClosed"), nil, false
	end

	if type(executor) ~= "function" then
		return Promise.reject("InvalidExecutor"), nil, false
	end

	local resolved = self:_ResolveDefaults(options)
	local key = resolved.Key

	if key ~= nil then
		local active_id = self._KeyIndex[key]
		if active_id ~= nil then
			local active_entry = self._Entries[active_id]
			if active_entry then
				return active_entry.Promise, active_entry.Id, true
			end
		end
	end

	if type(self._MaxSize) == "number" and self:GetSize() >= self._MaxSize then
		return Promise.reject("QueueFull"), nil, false
	end

	self._NextId += 1
	local id = self._NextId

	local resolve_ref = nil
	local reject_ref = nil
	local promise = Promise.new(function(resolve, reject)
		resolve_ref = resolve
		reject_ref = reject
	end)

	local entry: QueueEntry = {
		Id = id,
		Key = key,
		Executor = executor,
		Context = resolved.Context,
		Timeout = resolved.Timeout,
		MaxRetries = math.max(0, resolved.MaxRetries or 0),
		RetryDelay = math.max(0, resolved.RetryDelay or 0),
		BackoffFactor = math.max(1, resolved.BackoffFactor or 1),
		JitterFactor = math.max(0, resolved.JitterFactor or 0),
		RetryOn = resolved.RetryOn,
		CreatedAt = now_seconds(),
		Attempts = 0,
		Completed = false,
		CancelRequested = false,
		CancelReason = nil,
		Status = EntryStatus.Pending,
		Promise = promise,
		Resolve = resolve_ref,
		Reject = reject_ref,
	}

	self._Entries[id] = entry
	self._Pending[#self._Pending + 1] = entry

	if key ~= nil then
		self._KeyIndex[key] = id
	end

	self._Stats.Enqueued += 1
	self.Enqueued:Fire(id, entry.Context, key)
	self:_Pump()

	return promise, id, false
end

function Queue.Cancel(self: Queue, id: number, reason: string?): boolean
	local entry = self._Entries[id]
	if not entry then
		return false
	end

	entry.CancelRequested = true
	entry.CancelReason = reason or "Cancelled"

	if self._RunningEntry and self._RunningEntry.Id == id then
		return true
	end

	local pending_entry = remove_pending_by_id(self._Pending, id)
	if pending_entry then
		self:_RejectEntry(pending_entry, pending_entry.CancelReason, true)
		return true
	end

	return true
end

function Queue.Clear(self: Queue, reason: string?)
	reason = reason or "QueueCleared"

	local pending = self._Pending
	self._Pending = {}
	self._SuppressDrainResolution = true

	for index = 1, #pending do
		local entry = pending[index]
		entry.CancelRequested = true
		entry.CancelReason = reason
		self:_RejectEntry(entry, reason, true)
	end

	self._SuppressDrainResolution = false
	self:_ResolveDrainWaiters()
end

function Queue.Drain(self: Queue)
	if #self._Pending == 0 and self._RunningEntry == nil then
		return Promise.resolve(true)
	end

	return Promise.new(function(resolve)
		self._DrainWaiters[#self._DrainWaiters + 1] = resolve
	end)
end

function Queue.Close(self: Queue, reason: string?)
	if self._Closed then
		return
	end

	self._Closed = true
	self:Clear(reason or "QueueClosed")
end

function Queue:Destroy(reason: string?)
	self:Close(reason or "QueueDestroyed")

	self.Enqueued:Destroy()
	self.Started:Destroy()
	self.Succeeded:Destroy()
	self.Failed:Destroy()
	self.Retried:Destroy()
	self.Cancelled:Destroy()
	self.Drained:Destroy()
end

return QueueModule
