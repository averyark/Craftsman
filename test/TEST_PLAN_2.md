# Test Plan (Part 2) — StateMachine, Concurrency, Debounce, Queue

Companion to `test/TEST_PLAN.md` (Data/Market/Store). Same target environment (**Studio Play
session, Server + Client**), same harness (§1 of the first plan: `TestRunner`/`expect`/`spy`,
`Mocks`), same Tier A/B convention. Read the first plan's §0–§1 before starting; this document only
adds what is specific to these four modules.

Goal: cover core behaviour **and** regression-lock the recent fixes that touched these modules —
**M2** (StateMachine server: client-update rate-limit + Context guard), **M3** (StateMachine client:
`SERVER_SOURCE` echo sentinel), **L4** (`Machine.Stop` drains the pending-transition queue), and the
**Queue dedup-after-free** guard.

---

## 0. What's different from Part 1

- **Almost everything here is Tier A** (deterministic, no Roblox services): Concurrency, Debounce,
  Queue, `State`, and `Machine` are pure Luau. Only **StateMachine replication** needs the live
  client↔server session (Tier B), and even most of *that* is testable Tier A by **patching the
  ByteNet packet/query methods** (the pattern the deleted `StateMachineIntegrationTest` used).
- **Timing-sensitive modules:** Debounce, Concurrency `KeyedDebounce`, and Queue retry-delays use
  real timers (`task.delay`/`os.clock`). Tests must use real `task.wait` with **generous margins**
  and assert *ordering and bounds*, not exact timestamps. Suggested convention: pick a base
  `WAIT = 0.05`s and always wait `WAIT * 1.5`+ before asserting a trailing/expiry effect. Mark these
  cases `@timing` so a flaky failure is easy to recognise (re-run before treating as a real bug).
- **Established idiom (reuse it):** the deleted reference tests used
  `run_case(results, name, fn)` (pcall+assert, collect `{name, status, err}`) loaded as a Component,
  and `with_patched_method(object, key, replacement, fn)` to stub/capture ByteNet calls. The new
  `TestRunner.spy()` + a `Mocks.patch(obj, key, fn)` (returns `restore()`) cover the same ground;
  either is fine — match the surrounding suite.
- **Async modules (Queue, Machine re-entrancy):** use the runner's **yield-aware `it`**. Await
  Promises with `promise:await()` (or `:andThen` + a completion signal) and `task.wait` for
  `task.defer`/`task.delay` boundaries.

---

## 1. Concurrency — `test/Server/Concurrency.spec.luau`  (Tier A)

`Craftsman.Concurrency.AsyncLock` and `.KeyedDebounce`. Both spawn callbacks via `task.spawn`, so a
callback's effects are visible only after a yield — `task.wait()` (one frame) before asserting
spawned side-effects.

### 1.1 AsyncLock
| ID | Case | Assert |
|----|------|--------|
| CN-01 | `Execute` starts + locks | `lock:Execute(key, fn)` returns `true`; `lock:IsLocked(key) == true` immediately |
| CN-02 | Re-entrant `Execute` blocked while running | first `fn` yields (`task.wait(WAIT)`); second `Execute(key, fn2)` returns `false`; `fn2` never runs |
| CN-03 | Lock releases after completion | after first `fn` finishes (`task.wait(WAIT*1.5)`): `IsLocked(key) == false`; exactly one callback ran |
| CN-04 | Distinct keys are independent | `Execute(key_a, …)` and `Execute(key_b, …)` both return `true`; both run |
| CN-05 | Lock releases even when callback errors `@timing` | callback `error()`s → still `IsLocked(key) == false` afterward (pcall in `Execute` releases + warns); lock reusable |
| CN-06 | `Release` frees the key | while locked, `lock:Release(key)` → `IsLocked` false and a fresh `Execute` succeeds |
| CN-07 | Varargs forwarded | `Execute(key, fn, "a", 1)` → `fn` receives `("a", 1)` (assert after a frame) |
| CN-08 | `IsLocked` false for unknown key | `IsLocked({})` → `false` |

### 1.2 KeyedDebounce
| ID | Case | Assert |
|----|------|--------|
| CN-09 | First `Call` runs + returns true | `kd = KeyedDebounce.new(WAIT)`; `kd:Call(key, fn)` returns `true`; `fn` ran (after a frame) |
| CN-10 | Second `Call` within cooldown blocked | immediate second `kd:Call(key, fn2)` returns `false`; `fn2` did not run |
| CN-11 | `Call` after cooldown elapses runs again `@timing` | wait `WAIT*1.5`; `kd:Call(key, fn)` returns `true` and runs |
| CN-12 | Distinct keys independent | `Call(a)` then `Call(b)` both `true` |
| CN-13 | `Clear` resets cooldown | after a `Call`, `kd:Clear(key)`; immediate `Call` returns `true` |
| CN-14 | Varargs forwarded | args reach the callback |
| CN-15 | `cooldown == 0` lets every call run | `KeyedDebounce.new(0)`; back-to-back `Call`s all return `true` |

> Note (no assertion): `_Locks`/`_LastCalls` use weak (`__mode="k"`) keys; GC reclamation of table
> keys is not deterministically testable — do **not** write a GC-timing case.

---

## 2. Debounce — `test/Server/Debounce.spec.luau`  (Tier A, `@timing`)

`Craftsman.Debounce.new(func, wait, options?)` (default `leading=false, trailing=true`) and
`Debounce.throttle(func, wait, options?)` (`leading+trailing`, `maxWait=wait`). The instance is
callable (`__call`) and exposes `Call/Cancel/Flush/IsPending`. Use `WAIT = 0.05`.

| ID | Case | Act | Assert |
|----|------|-----|--------|
| DB-01 | Trailing (default): coalesce to one trailing call | `d("a"); d("b"); d("c")` then `wait(WAIT*1.5)` | not invoked synchronously; `IsPending()` true between; runs **once** with `"c"`; then `IsPending()` false |
| DB-02 | Leading-only fires immediately, not trailing | `new(fn, WAIT, {leading=true, trailing=false})`; two rapid calls; `wait(WAIT*1.5)` | invoked **once**, on the first call (count stays 1) |
| DB-03 | Leading + trailing | `{leading=true, trailing=true}`; call, then call again within window; `wait(WAIT*1.5)` | invoked twice: once leading, once trailing with last args |
| DB-04 | `IsPending` reflects timer | after a call | `IsPending()` true; false after `wait(WAIT*1.5)` |
| DB-05 | `Cancel` drops the pending trailing call | call; `d:Cancel()`; `wait(WAIT*1.5)` | `fn` never invoked; `IsPending()` false |
| DB-06 | `Flush` forces the pending call now | call; `local r = d:Flush()` | `fn` invoked immediately; `r` is the func's return; `IsPending()` false |
| DB-07 | `Flush` with nothing pending | fresh instance, `d:Flush()` | returns last result or `nil`; no error |
| DB-08 | `maxWait` forces an invoke mid-stream | `new(fn, WAIT, {maxWait=WAIT})`; call continuously every < WAIT for > WAIT total | at least one invoke occurs before the call stream stops (not starved) |
| DB-09 | Return-value propagation | leading invoke returns func result; later coalesced calls return the cached last result | assert returned values match |
| DB-10 | `__call` metamethod | `d(x)` behaves like `d:Call(x)` | same effect as DB-01 driver |
| DB-11 | `self.Call` connection-safe closure | call `d.Call("x")` (no self) **and** `d:Call("x")` (with self) | both treat `"x"` as the real arg (the closure strips a leading `self`); verifies event-`:Connect(d.Call)` compatibility |
| DB-12 | `throttle` = leading + trailing, capped per window | `throttle(fn, WAIT)`; spam calls across 2 windows | invokes on leading edge and at most ~once per `WAIT` window |
| DB-13 | Varargs incl. embedded `nil` preserved | call with `("a", nil, 3)` (count 3 via `select("#")`) | trailing invoke receives all 3 positionally |

---

## 3. Queue — `test/Server/Queue.spec.luau`  (Tier A, Promise-based)

`Craftsman.Queue.new(options?)`. FIFO, single in-flight task, retries/backoff/jitter/timeout,
`MaxSize`, key dedup, Pause/Resume/Cancel/Clear/Drain/Close/Destroy, lifecycle Signals. Await the
returned Promises; use `spy()` on signals where useful.

| ID | Case | Act | Assert |
|----|------|-----|--------|
| QU-01 | Single task resolves with result | `p = q:Enqueue(function() return 42 end)`; `p:await()` | resolves `42`; `Succeeded` fired with `(id, 42, …)`; `GetStats().Succeeded == 1` |
| QU-02 | FIFO + non-concurrent | enqueue 3 executors that append their id to a log and `task.wait(WAIT)` | log order `{1,2,3}`; never two running at once (assert via a running-counter that never exceeds 1) |
| QU-03 | Failure (no retries) rejects | executor `error("x")` | promise rejects; `Failed` fired; `GetStats().Failed == 1` |
| QU-04 | Retry then succeed | `MaxRetries=2`; executor fails on attempts 1–2, succeeds on 3 | promise resolves; `Retried` fired (≥1); `Started` fired 3×; resolves with success value |
| QU-05 | Retries exhausted | `MaxRetries=1`; always fails | rejects after `MaxRetries+1 = 2` attempts; `Failed` fired once |
| QU-06 | `RetryOn` gates retries | `MaxRetries=3`, `RetryOn=() -> false` | no retry; rejects after first attempt |
| QU-07 | Backoff delay grows `@timing` | `RetryDelay=WAIT, BackoffFactor=2`, fail twice then succeed | total elapsed ≥ `WAIT + 2*WAIT` (bounded check, not exact); resolves |
| QU-08 | Timeout rejects | executor yields `> Timeout`; `Timeout=WAIT` | rejects with `"QueueTimeout"` |
| QU-09 | Key dedup merges | enqueue twice with same `Key="k"` while first pending/running | 2nd returns the **same** promise + id and `merged == true`; executor runs **once** |
| QU-10 | Key released after completion | after QU-09 first completes, enqueue `Key="k"` again | new id, `merged == false`, runs again |
| QU-11 | `MaxSize` rejects overflow | `MaxSize=1`; enqueue a yielding task then a second | 2nd promise rejects `"QueueFull"`; `GetSize()` counts running+pending |
| QU-12 | Cancel a **pending** task | enqueue A (yields) + B; `q:Cancel(idB, "stop")` | B rejects `"stop"`; `Cancelled` fired; B removed from pending; A unaffected |
| QU-13 | Cancel a **running** task (flag only) | cancel the in-flight task | `Cancel` returns `true`, sets `CancelRequested`; the task is **not** force-aborted — it rejects as Cancelled only if it later errors/retries (document this; executors can't read the flag). Assert: a running task that *then errors* rejects with the cancel reason |
| QU-14 | `Clear` rejects all pending | enqueue running A + pending B,C; `q:Clear()` | B,C reject `"QueueCleared"`; A keeps running; `Drain()` resolves after A finishes |
| QU-15 | `Drain` semantics | (a) empty queue `q:Drain():await()` resolves immediately `true`; (b) with work, resolves after the last task completes; `Drained` signal fires |
| QU-16 | Pause / Resume | enqueue A,B; `q:Pause()` during A | B does not start while paused; after A completes `GetPendingCount()==1`; `Resume()` runs B |
| QU-17 | `Close` rejects new + clears | `q:Close()`; then `q:Enqueue(fn)` | enqueue promise rejects `"QueueClosed"`; `IsClosed()` true; pending cleared |
| QU-18 | Invalid executor | `q:Enqueue("notafunc")` | promise rejects `"InvalidExecutor"`, returns `(promise, nil, false)` |
| QU-19 | Context + attempt + id passed | `Enqueue(fn, {Context=ctx})` where `fn = function(c, attempt, id) … end` | `fn` receives `(ctx, 1, id)` |
| QU-20 | Stats snapshot shape | after a mix of success/fail | `GetStats()` has `Enqueued/Started/Succeeded/Failed/Retried/Cancelled/Pending/HasRunning/Closed/Paused` |
| QU-21 | `Destroy` closes + destroys signals | `q:Destroy()` | `IsClosed()` true; subsequent signal use does not fire (no error); pending rejected |

> Regression: QU-09/QU-10 lock the dedup-by-key path (the earlier review flagged the
> dedup-after-free lookup — `Enqueue` already guards with `if active_entry then`; these cases prove it).

---

## 4. StateMachine

Three suites: pure `State`, pure `Machine`, and replication (Tier A via packet-patching + Tier B
live). Reuse the reference helpers: an `enter/exit/update` **event log** per state and an
`expect_events(actual, expected)` comparator (see deleted `StateMachineTest.luau` for the exact shape).

### 4.1 `State` — `test/Server/StateMachine.State.spec.luau`  (Tier A)
`Craftsman.State.new(name, handlers?)`.
| ID | Case | Assert |
|----|------|--------|
| SS-01 | Constructor defaults | `new("A")` → `Name=="A"`, `Parent==nil`, `Children=={}`; handlers optional |
| SS-02 | `Enter/Exit/Update` invoke handlers with context | handlers log `(self, context)` / `(self, dt, context)` and are called with the passed args |
| SS-03 | Handlers absent → no-op | `new("A")` then `:Enter()` does nothing, no error |
| SS-04 | `_SetParent` nests + updates `Children` | `child:_SetParent(parent)` → `parent.Children[child.Name]==child`; returns `true` |
| SS-05 | `_SetParent` rejects a cycle | make `b` child of `a`, then `a:_SetParent(b)` → returns `false`; `a.Parent` unchanged |
| SS-06 | Re-parenting moves the child-key | move child from p1 to p2 → removed from `p1.Children`, present in `p2.Children` |
| SS-07 | `SetName` updates parent's `Children` key | nested child `SetName("X")` → `parent.Children["X"]==child`, old key gone, `_ChildKey=="X"` |
| SS-08 | `SetName` same name is a no-op true | returns `true`, nothing changes |

### 4.2 `Machine` (HSM) — `test/Server/StateMachine.Machine.spec.luau`  (Tier A)
`Craftsman.Machine.new(id?, isClientAuthoritative?)`.
| ID | Case | Assert |
|----|------|--------|
| SM-01 | `AddState` / `GetState` | add `A` → `GetState("A")==A`; adding a *different* state with the same name → `false`; re-adding the same instance → `true` |
| SM-02 | `Start` enters initial (+ ancestor chain) | nested `Root>Child`, initial `Child`, `Start()` → enter order `Root` then `Child`; `IsRunning()` true; `GetCurrent()==Child`; `Transitioned` fired `(m, nil, Child, …)` |
| SM-03 | `Start` guards | no initial → `false`; second `Start()` while running → `false`; after `Destroy` → `false` |
| SM-04 | Flat transition | `A`→`B`: events `exit:A`, `enter:B`; `GetCurrent()==B`; `Transitioned` `(m, A, B, ctx, src)` |
| SM-05 | Hierarchical LCA transition | tree `Root>{X>X1, Y>Y1}`; `X1`→`Y1` exits `X1,X` and enters `Y,Y1` (Root not re-entered); assert exact event log |
| SM-06 | Transition to current is a no-op | `Transition(current)` → `false`, no events |
| SM-07 | Context + source propagate | `Transition(B, ctx, player)` → handlers receive `ctx`; `Transitioned` carries `ctx` and `player` |
| SM-08 | Re-entrant transition queues + runs sequentially | inside `B.Enter`, call `m:Transition(C)` → `C` runs **after** `B` completes (assert log order `…enter:B, exit:B, enter:C`); no interleave |
| SM-09 | `Update` runs current + ancestors | running `Root>Child`; `m:Update(dt, ctx)` → both `Update` handlers fire with `dt` |
| SM-10 | `Stop` exits the active chain | running `Root>Child`; `Stop(ctx)` → exits `Child` then `Root`; `GetCurrent()==nil`; `IsRunning()` false; `Transitioned` `(m, Child, nil, …)` |
| SM-11 | **L4 regression** — `Stop` drains pending queue | force `> MAX_TRANSITION_BATCH (10)` re-entrant `Transition` enqueues from one `Enter` so the drain defers; call `Stop()` immediately; `task.wait()` (let the deferred drain fire) → machine stays stopped (`GetCurrent()==nil`, not resurrected by a queued transition) |
| SM-12 | `Destroy` idempotent + disables | `Destroy()` → `true`, `Destroyed` fired; second `Destroy()` → `false`; subsequent `Start`/`Transition` → `false` |

### 4.3 Replication — server filter & client echo
Two layers. **4.3a (Tier A, packet-patching)** drives `StateMachine.Server`/`.Client` in one context
by patching the ByteNet surface — `Network.packets.{MachineUpdated,ClientMachineUpdated}` methods
(`sendToAll`/`sendToList`/`send`/`listen`) and `Network.queries.RequestState` — to **capture**
outgoing payloads and to **manually invoke** the registered `listen`/`RequestState` handlers with
synthetic `(payload, player)`. (`Mocks.player(id)` supplies the fake player.) This is exactly how the
deleted `StateMachineIntegrationTest` worked.

`test/Server/StateMachine.replication.spec.luau`  (Tier A)
| ID | Case | Assert |
|----|------|--------|
| SR-01 | Server broadcasts on transition | `Server:Register(m)`; capture `MachineUpdated.sendToAll`; `m:Start()` then transition | payload has `Id`, `State`, `Running`, `ClientAuthoritative`, and a **monotonically increasing `Sequence`** |
| SR-02 | `SetTargets` → `sendToList` excludes non-targets | register with targets `{p1}`; transition | uses `sendToList` to `{p1}`; a second player not included |
| SR-03 | `Sync` sends current snapshot | `Server:Sync(m)` | one payload reflecting current state, no `Sequence` advance beyond a transition's |
| SR-04 | Server ignores non-authoritative client update | machine **not** client-authoritative; invoke captured `ClientMachineUpdated.listen` handler with `(payload, p1)` | machine state unchanged (rejected at the authority check) |
| SR-05 | **M2 regression** — Context type guard | client-authoritative machine; feed a payload whose `Context` is a non-table (e.g. a string) | update **dropped**; state unchanged |
| SR-06 | **M2 regression** — per-(player,machine) rate-limit | feed two valid client updates for the same machine within `CLIENT_UPDATE_MIN_INTERVAL` (default 0.05s) | the **second is dropped** (first applied); after `task.wait(0.06)` a third is accepted |
| SR-07 | M2 — target gate on client updates | machine has `Targets={p1}`; feed update from `p2` | dropped |
| SR-08 | Server applies a valid authoritative client update | authoritative machine, `p1` a target, valid `State`+table `Context`, spaced beyond the interval | machine transitions to the named state; unknown state name is ignored |
| SR-09 | **M3 regression** — no echo of server-applied transitions | `Client:Register(m)` (client-authoritative); capture `ClientMachineUpdated.send`; apply a **server** payload by invoking the captured `MachineUpdated.listen` handler (drives `apply_payload` → `Transition(…, SERVER_SOURCE)`) | `ClientMachineUpdated.send` is **not** called (the `SERVER_SOURCE` sentinel suppresses the echo) |
| SR-10 | M3 — genuine client transition **is** sent | same registered authoritative machine; call `m:Transition(S2)` directly (local, source nil) | `ClientMachineUpdated.send` **is** called once |
| SR-11 | M3 — echo suppressed even through the queued path | apply a server payload that lands while a transition is in progress (forces enqueue), so the real transition fires later via `task.defer` | still **no** `ClientMachineUpdated.send` after `task.wait()` (source preserved through the queue) |
| SR-12 | Client drops stale sequence | apply payload `Sequence=5` then `Sequence=3` | second ignored (no revert); applying `Sequence=6` is accepted |

`test/Client/StateMachine.replication.live.spec.luau`  (Tier B, live session)
| ID | Case | Assert |
|----|------|--------|
| SR-B1 | Server→client replication round-trip | server registers + transitions a machine with a known `Id`; client registers the same `Id` | client machine reaches the same state (observe `Transitioned`/`GetCurrent`) |
| SR-B2 | Client-authoritative round-trip | client transitions an authoritative machine | server applies it; **no echo storm** (server's rebroadcast to other clients carries the change once) — in a 2-player session, the other client converges without a feedback loop |

---

## 5. Regression matrix (lock the recent fixes)

| Recent fix | Locked by |
|------------|-----------|
| **M2** SM server rate-limit + Context guard + target gate | SR-05, SR-06, SR-07 (SR-04 authority) |
| **M3** SM client `SERVER_SOURCE` echo sentinel (incl. queued path) | SR-09, SR-10, SR-11 (+ SR-B2 live) |
| **L4** `Machine.Stop` drains pending queue | SM-11 |
| Queue dedup-by-key after free | QU-09, QU-10 |
| (Sanity) HSM transition correctness | SM-05, SM-08 |

---

## 6. Suggested build order
1. **Concurrency** (§1) — smallest surface; confirms the harness + `task.wait` timing conventions.
2. **Debounce** (§2) — pure timing, builds confidence in `@timing` margins.
3. **Queue** (§3) — Promise/async; exercises the yield-aware `it`.
4. **State** (§4.1) then **Machine** (§4.2) — pure; lock L4 (SM-11).
5. **SM replication Tier A** (§4.3a) — packet-patching; locks M2 + M3.
6. **SM replication live** (§4.3b) — final 2-context confidence (do last, may need 2 players).

## 7. Assumptions & risks
- **Timing flakiness** is the main risk (`@timing` cases). Use margins ≥ 1.5× the wait; never assert
  exact `os.clock` deltas — assert ordering and lower/upper bounds. Re-run a single failing
  `@timing` case before treating it as a real regression.
- **Packet-patching depends on the ByteNet method names** (`sendToAll`/`sendToList`/`send`/`listen`,
  `queries.RequestState.listen`/`.invoke`). If ByteNet's API shifts, the patch helper must adapt —
  the deleted `StateMachineIntegrationTest` is the working reference for the exact shape.
- **SM-11 (L4)** requires forcing `> MAX_TRANSITION_BATCH (10)` re-entrant enqueues to make the drain
  defer; if that constant changes, adjust the count. If it proves too fiddly, fall back to asserting
  the simpler invariant: after `Stop()`, the pending queue is empty and `GetCurrent()` stays `nil`.
- **Cancel-of-running (QU-13)** cannot force-abort an executor (executors get `(context, attempt,
  id)`, not the entry) — only failure/retry boundaries observe the cancel flag. Test the documented
  behaviour, not an immediate abort.
- **`task.spawn` deferral:** AsyncLock/KeyedDebounce callbacks and Queue steps run on spawned threads;
  always `task.wait()` at least one frame before asserting their side-effects.
- Tier A here needs **no API Services and no second player**; only SR-B1/SR-B2 use the live session
  (SR-B2 ideally 2 players via Test ▸ Clients and Servers).
