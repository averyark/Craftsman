# Task Control: Queue, Debounce, Concurrency

## Queue

`Queue` runs async jobs one at a time, in FIFO order. Each job gets a Promise and can use retries, exponential backoff, jitter, timeouts, a size cap and deduplication keys. It fits DataStore writes, purchase processing and anything else that must not run concurrently.

`Craftsman.Queue.new(options?)`:

| Option | Default |
|---|---|
| `DefaultMaxRetries` | `0` |
| `DefaultRetryDelay` | `0` s |
| `DefaultBackoffFactor` | `1` (constant delay) |
| `DefaultJitterFactor` | `0` |
| `DefaultTimeout` | none |
| `MaxSize` | unbounded |
| `RetryOn(err, attempt, context, entry) -> boolean` | retry on every error |

### Enqueue

`queue:Enqueue(executor, options?) -> (Promise, id?, merged)`

- `executor(context, attempt, id)` can yield, return a value, return a Promise, or throw. When the queue is idle, it starts synchronously inside `Enqueue`.
- Options: `Key`, `Context`, plus per-job overrides for `Timeout`, `MaxRetries`, `RetryDelay`, `BackoffFactor`, `JitterFactor` and `RetryOn`.
- **Dedup:** if a job with the same `Key` is already pending or running, `Enqueue` returns that job's promise with `merged = true`.

### Rejections

| When | Reason |
|---|---|
| At once, returned by `Enqueue` | `"QueueClosed"`, `"QueueFull"`, `"InvalidExecutor"` |
| Later | the executor's error, `"QueueTimeout"`, the cancel reason, `"QueueCleared"`, `"QueueClosed"`, `"QueueDestroyed"` |

Always `:catch` the promise.

### Retries

Retry *n* waits `RetryDelay * BackoffFactor^(n-1)` seconds, then applies jitter. A job makes `MaxRetries + 1` attempts. With `RetryOn` set, it can make one more.

### Methods

- `Cancel(id, reason?)`: rejects a pending job. A running job is only flagged, and still resolves if it succeeds.
- `Clear(reason?)`: rejects all pending jobs.
- `Pause()` / `Resume()`
- `Drain()`: returns `Promise<boolean>`. It resolves `true` once the queue is empty. It resolves `false` as soon as the queue is paused with nothing running and jobs still pending, because a paused queue can't drain.
- `Close(reason?)`: rejects new jobs and clears pending ones.
- `Destroy(reason?)`
- `GetSize()`, `GetPendingCount()`, `IsPaused()`, `IsClosed()`
- `GetStats()`

### Signals

- `Enqueued(id, ctx, key)`
- `Started(id, attempt, ctx, key)`
- `Succeeded(id, result, ctx, key, attempts)`
- `Failed(id, reason, ctx, key, attempts)`
- `Retried(id, err, attempt, delay, ctx, key)`
- `Cancelled(id, reason, ctx, key)`
- `Drained(stats)`

```lua
local SaveQueue = Craftsman.Queue.new({
	DefaultMaxRetries = 3,
	DefaultRetryDelay = 1,
	DefaultBackoffFactor = 2,
	DefaultTimeout = 10,
})

SaveQueue:Enqueue(function(context)
	return ProfileStore:SetAsync(context.Key, context.Data)
end, { Key = `save:{player.UserId}`, Context = { Key = tostring(player.UserId), Data = data } })
	:catch(function(err)
		warn(`save failed: {err}`)
	end)

game:BindToClose(function()
	SaveQueue:Drain():await()
end)
```

## Debounce

`Debounce` is a lodash-style debounce/throttle for a single function. All waits are in seconds.

### Constructors

- `Craftsman.Debounce.new(fn, wait, { leading?, trailing?, maxWait? }?)`: defaults are `leading = false` and `trailing = true`. **The option keys are lowercase.**
- `Craftsman.Debounce.throttle(fn, wait, { leading?, trailing? }?)`: both options default to `true`, and `maxWait` is set to `wait`.

### Calling

- Call the debounced function as `d(...)`, `d:Call(...)` or `d.Call(...)`. `d.Call` is a bound closure, so you can pass it directly as a callback.
- The return value is the result of the most recent invocation, which may be stale.
- A trailing call receives the **last** arguments and runs in a delayed thread, so its errors never reach the caller.

### Methods

- `d:Cancel()`: there is no `Destroy`, so call `Cancel` during cleanup.
- `d:Flush()`
- `d:IsPending()`

```lua
local push_settings = Craftsman.Debounce.new(function(settings)
	SettingsRemote:FireServer(settings)
end, 0.5)

self.Keeper:Add(function()
	push_settings:Cancel()
end)

slider.Changed:Connect(function()
	push_settings(current_settings)
end)

local fire = Craftsman.Debounce.throttle(shoot, 0.2)
tool.Activated:Connect(fire.Call)
```

## Concurrency

### AsyncLock

`Craftsman.Concurrency.AsyncLock.new()` creates a mutex keyed by any value.

- `lock:Execute(key, fn, ...)` returns `false` without running `fn` if `key` is locked. Otherwise it runs `fn(...)` in `task.spawn`, holds the lock until `fn` returns or errors, and returns `true`. Errors are `warn`ed and return values are discarded.
- `lock:IsLocked(key)`
- `lock:Release(key)`: forces the lock open. Avoid it while `fn` is still running, because a second holder could overlap the first.

### KeyedDebounce

`Craftsman.Concurrency.KeyedDebounce.new(cooldown)` creates a per-key cooldown gate.

- `kd:Call(key, fn, ...)` returns `false` while `key` is cooling down. Otherwise it records the time, spawns `fn(...)` and returns `true`. Rejected calls don't extend the cooldown.
- `kd:Clear(key)`

### Keys

Keys are held weakly. A table or Instance key with no other reference can be collected, which silently resets its lock or cooldown. Strings, numbers and in-game Players are safe keys.

```lua
local PurchaseLock = Craftsman.Concurrency.AsyncLock.new()
local AbilityCooldown = Craftsman.Concurrency.KeyedDebounce.new(1)

PurchaseRemote.OnServerEvent:Connect(function(player, item_id)
	PurchaseLock:Execute(player, process_purchase, player, item_id)
end)

AbilityRemote.OnServerEvent:Connect(function(player)
	AbilityCooldown:Call(player, use_ability, player)
end)
```

## Which one?

| Need | Use |
|---|---|
| Ordered async jobs with retries | `Queue` |
| One call after input settles (search box, settings save) | `Debounce.new` |
| At most one call every N seconds | `Debounce.throttle` |
| No overlapping runs per player or key | `Concurrency.AsyncLock` |
| A per-player or per-key cooldown gate on remotes | `Concurrency.KeyedDebounce` |
