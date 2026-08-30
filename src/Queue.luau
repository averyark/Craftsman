--!nonstrict
--[[
    FileName    > Queue.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 23/05/2026
--]]

const Promise = require("../../../Promise")
const Signal = require("./Signal")

--[=[
	@class Queue
	An asynchronous task execution queue. Executed tasks are processed sequentially
	in first-in, first-out (FIFO) order. Features robust retry mechanisms, exponential
	backoff, delay jitter, execution timeouts, maximum queue capacities, and task
	deduplication via unique keys.

	:::note
	Task execution functions are wrapped in Promises. The queue supports pause, resume, and drain states.
	:::
]=]
local QueueModule = {}

local Queue = {}
Queue.__index = Queue

--[=[
	@interface QueueOptions
	@within Queue
	@field DefaultMaxRetries number? -- The default maximum retry attempts for tasks. Defaults to 0.
	@field DefaultRetryDelay number? -- The default delay (in seconds) between retry attempts. Defaults to 0.
	@field DefaultBackoffFactor number? -- The default exponential multiplier for retries. Defaults to 1 (constant delay).
	@field DefaultJitterFactor number? -- The default percentage of delay range to randomize (0 to 1). Defaults to 0.
	@field DefaultTimeout number? -- The default timeout duration (in seconds) for each task execution.
	@field MaxSize number? -- The maximum number of items allowed in the queue (pending + running).
	@field RetryOn ((error: any, attempt: number, context: any, entry: any) -> boolean)? -- Optional callback to decide if a task retry should be attempted.
	Configuration options for instantiating a new queue.
]=]
export type QueueOptions = {
	DefaultMaxRetries: number?,
	DefaultRetryDelay: number?,
	DefaultBackoffFactor: number?,
	DefaultJitterFactor: number?,
	DefaultTimeout: number?,
	MaxSize: number?,
	RetryOn: ((error_value: any, attempt: number, context: any, entry: any) -> boolean)?,
}

--[=[
	@interface EnqueueOptions
	@within Queue
	@field Key any? -- Optional deduplication key. If another task with this key is pending/running, Enqueue returns the existing task's promise.
	@field Context any? -- Optional state/data passed as the first parameter to the executor function.
	@field Timeout number? -- Override for the task execution timeout (in seconds).
	@field MaxRetries number? -- Override for maximum retry attempts.
	@field RetryDelay number? -- Override for retry delay (in seconds).
	@field BackoffFactor number? -- Override for exponential backoff multiplier.
	@field JitterFactor number? -- Override for delay jitter factor.
	@field RetryOn ((error: any, attempt: number, context: any, entry: any) -> boolean)? -- Override callback to decide if this task retry should be attempted.
	Configuration options for enqueueing a task.
]=]
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
	for index, entry in pending do
		if entry.Id ~= id then
			continue
		end

		return table.remove(pending, index)
	end

	return nil
end

local function clone_map(source: { [any]: any }): { [any]: any }
	local output = {}
	for key, value in source do
		output[key] = value
	end
	return output
end

--[=[
	@function new
	@within Queue
	@param options QueueOptions? -- Optional configuration settings for the queue.
	@return Queue -- A new Queue instance.
	@tag constructor
	Creates a new queue instance with default retry behavior, backoff multiplier, timeout, and queue limit configuration.
]=]
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

	--[=[
		@prop Enqueued Signal<id: number, context: any, key: any>
		@within Queue
		Fires when a new task is successfully added to the queue.
	]=]
	self.Enqueued = Signal.new()

	--[=[
		@prop Started Signal<id: number, attempt: number, context: any, key: any>
		@within Queue
		Fires when a task begins execution or starts a retry attempt.
	]=]
	self.Started = Signal.new()

	--[=[
		@prop Succeeded Signal<id: number, result: any, context: any, key: any, attempts: number>
		@within Queue
		Fires when a task completes execution successfully.
	]=]
	self.Succeeded = Signal.new()

	--[=[
		@prop Failed Signal<id: number, reason: any, context: any, key: any, attempts: number>
		@within Queue
		Fires when a task fails and has exhausted all retry attempts.
	]=]
	self.Failed = Signal.new()

	--[=[
		@prop Retried Signal<id: number, error: any, attempt: number, delay: number, context: any, key: any>
		@within Queue
		Fires when a task execution fails but is scheduled for retry after a delay.
	]=]
	self.Retried = Signal.new()

	--[=[
		@prop Cancelled Signal<id: number, reason: any, context: any, key: any>
		@within Queue
		Fires when a task is cancelled before or during execution.
	]=]
	self.Cancelled = Signal.new()

	--[=[
		@prop Drained Signal<stats: table>
		@within Queue
		Fires when the queue becomes completely empty (no running or pending tasks remaining).
	]=]
	self.Drained = Signal.new()

	return self
end

export type Queue = typeof(QueueModule.new(...))

--[=[
	@method _ResolveDefaults
	@within Queue
	@private
	@ignore
]=]
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

--[=[
	@method _ReleaseKey
	@within Queue
	@private
	@ignore
]=]
function Queue._ReleaseKey(self: Queue, entry: QueueEntry)
	local key = entry.Key
	if key ~= nil and self._KeyIndex[key] == entry.Id then
		self._KeyIndex[key] = nil
	end
end

--[=[
	@method _ResolveDrainWaiters
	@within Queue
	@private
	@ignore
]=]
function Queue._ResolveDrainWaiters(self: Queue)
	if self._SuppressDrainResolution then
		return
	end

	if #self._Pending > 0 or self._RunningEntry ~= nil then
		return
	end

	local waiters = self._DrainWaiters
	self._DrainWaiters = {}

	for _, waiter in waiters do
		waiter(true)
	end

	self.Drained:Fire(self:GetStats())
end

--[=[
	@method _RejectEntry
	@within Queue
	@private
	@ignore
]=]
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

--[=[
	@method _FulfillEntry
	@within Queue
	@private
	@ignore
]=]
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

--[=[
	@method _ComputeRetryDelay
	@within Queue
	@private
	@ignore
]=]
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

--[=[
	@method _CanRetry
	@within Queue
	@private
	@ignore
]=]
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

--[=[
	@method _ExecuteEntry
	@within Queue
	@private
	@ignore
]=]
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

--[=[
	@method _Pump
	@within Queue
	@private
	@ignore
]=]
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

--[=[
	@method GetSize
	@within Queue
	@return number -- The total number of tasks in the queue.
	Returns the current number of tasks in the queue (both pending and actively running).
]=]
function Queue.GetSize(self: Queue)
	local running = if self._RunningEntry ~= nil then 1 else 0
	return #self._Pending + running
end

--[=[
	@method GetPendingCount
	@within Queue
	@return number -- The number of pending tasks.
	Returns the count of tasks that are currently waiting in the queue but have not yet started executing.
]=]
function Queue.GetPendingCount(self: Queue)
	return #self._Pending
end

--[=[
	@method IsPaused
	@within Queue
	@return boolean -- True if the queue is paused.
	Checks whether the queue is currently paused.
]=]
function Queue.IsPaused(self: Queue)
	return self._Paused
end

--[=[
	@method IsClosed
	@within Queue
	@return boolean -- True if the queue is closed.
	Checks whether the queue is currently closed and rejecting new tasks.
]=]
function Queue.IsClosed(self: Queue)
	return self._Closed
end

--[=[
	@method GetStats
	@within Queue
	@return table -- A table containing a copy of queue statistics.
	Retrieves diagnostic and performance statistics for the queue, including counts of enqueued, started, succeeded, failed, retried, and cancelled tasks.
]=]
function Queue.GetStats(self: Queue)
	local stats = clone_map(self._Stats)
	stats.Pending = #self._Pending
	stats.HasRunning = self._RunningEntry ~= nil
	stats.Closed = self._Closed
	stats.Paused = self._Paused
	return stats
end

--[=[
	@method Pause
	@within Queue
	Pauses the execution of the queue. Active tasks currently running will complete, but no new tasks from the pending list will be started.
]=]
function Queue.Pause(self: Queue)
	self._Paused = true
end

--[=[
	@method Resume
	@within Queue
	@return boolean -- True if the queue was resumed or is active; false if closed.
	Resumes task execution in the queue. If there are pending tasks, they will begin processing sequentially.
]=]
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

--[=[
	@method Enqueue
	@within Queue
	@param executor (context: any, attempt: number, id: number) -> any -- The execution function for the task.
	@param options EnqueueOptions? -- Optional parameters for the task.
	@return (Promise<any>, number?, boolean) -- Returns the task Promise, task ID, and whether it was merged as a duplicate.
	Adds a new task to the queue. If a deduplication `Key` is specified in `options` and a matching task is already pending or running, the queue merges them and returns the existing task's Promise and ID.

	:::caution
	If the queue size exceeds `MaxSize`, this method will reject the returned Promise with `"QueueFull"`. If the queue is closed, it rejects with `"QueueClosed"`.
	:::
]=]
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

--[=[
	@method Cancel
	@within Queue
	@param id number -- The ID of the task to cancel.
	@param reason string? -- Optional cancellation reason. Defaults to `"Cancelled"`.
	@return boolean -- True if a task with the given ID was found and cancellation was requested.
	Requests the cancellation of a task. If the task is pending, it is immediately rejected. If it is currently executing, the cancel request flag is set, and the executor can check it.
]=]
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

--[=[
	@method Clear
	@within Queue
	@param reason string? -- Optional cancellation reason to reject tasks with. Defaults to `"QueueCleared"`.
	Cancels and rejects all pending tasks in the queue. The currently running task (if any) is not aborted, but all other tasks are cleared.
]=]
function Queue.Clear(self: Queue, reason: string?)
	reason = reason or "QueueCleared"

	local pending = self._Pending
	self._Pending = {}
	self._SuppressDrainResolution = true

	for _, entry in pending do
		entry.CancelRequested = true
		entry.CancelReason = reason
		self:_RejectEntry(entry, reason, true)
	end

	self._SuppressDrainResolution = false
	self:_ResolveDrainWaiters()
end

--[=[
	@method Drain
	@within Queue
	@return Promise<boolean> -- Resolves to true when the queue is completely empty.
	Returns a Promise that resolves when the queue becomes completely empty (no running or pending tasks remaining).
]=]
function Queue.Drain(self: Queue)
	if #self._Pending == 0 and self._RunningEntry == nil then
		return Promise.resolve(true)
	end

	return Promise.new(function(resolve)
		self._DrainWaiters[#self._DrainWaiters + 1] = resolve
	end)
end

--[=[
	@method Close
	@within Queue
	@param reason string? -- Optional close reason. Defaults to `"QueueClosed"`.
	Closes the queue to reject any new task submissions and clears/rejects all pending tasks.
]=]
function Queue.Close(self: Queue, reason: string?)
	if self._Closed then
		return
	end

	self._Closed = true
	self:Clear(reason or "QueueClosed")
end

--[=[
	@method Destroy
	@within Queue
	@param reason string? -- Optional reason. Defaults to `"QueueDestroyed"`.
	Closes the queue, cancels all pending tasks, and destroys all internal lifecycle Signal instances.
]=]
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
