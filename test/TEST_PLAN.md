# Test Plan — Data, Market, Store

Audience: an executing agent (Sonnet 4.6) who will **write and run** these tests.
Goal: cover the core behaviour of the three subsystems **and regression-lock the recent fixes**
(H2 `Data.Loaded:Once`, H3 Market receipt-before-save rollback, plus Store immutability/registry
guarantees). This document specifies *what to test and how*, not the test code itself.

---

## 0. Current state & constraints (read first)

- **No test framework is installed.** There is no TestEZ in `wally.toml`. Legacy tests under
  `test/Server/*` were Component-loaded modules run inside a live Roblox session and are currently
  **deleted from the working tree** (still in git `HEAD` for reference: `git show HEAD:test/Server/StoreTest.luau`).
- **Every subsystem module calls `game:GetService(...)` at require time**, so tests run inside a
  Roblox VM. **Target environment: a Studio Play session (F5) with both Server and Client running.**
  This gives a real `LocalPlayer`, live client↔server networking (ByteNet), and — with **“Enable
  Studio Access to API Services”** on — a real `DataStoreService`/`DocumentService`. Everything is
  available in one session; there is no separate headless gate.
- The framework is consumed as `require("@game/ReplicatedStorage/Packages/Craftsman")` exposing
  `Craftsman.Store`, `Craftsman.DataServer`, `Craftsman.DataClient`, `Craftsman.MarketServer`,
  `Craftsman.StoreServer`, `Craftsman.StoreClient`, `Craftsman.Config`, `Craftsman.PrintUtil`, etc.
- Reflex producers expose actions as **dot-call dispatchers** (`producer.AddCoins(5)`), read state via
  `producer:getState()`, and player producers add `producer:getPlayerState(player_or_id[, selector])`
  and `producer._LoadPlayer(userId, data)` / `_AddReceipt(...)`.

### Determinism tiers
The target is a single Studio Play session, so all tiers run there. The split is about
**determinism**, not availability — tag every case so a failure is easy to attribute.

- **Tier A — Deterministic (stubbed / pure).** No real `Player`, no DataStore, no network; order-
  independent and repeatable. Achieved with pure producers and by stubbing `DataServer`. Covers
  **Store (all)**, **Market core logic** (incl. things you *can't* trigger live, like a forced
  DataStore save failure or a real purchase), and **Data signal shims**. Prioritise this — it is the
  bulk of the value and the only way to deterministically exercise the H3 rollback.
- **Tier B — Live session.** Uses the running Studio session: the real `LocalPlayer`, real
  `DataStoreService`/`DocumentService` (API Services on), and real client↔server replication. Covers
  Data session lifecycle, `Market:_ProcessReceipt`, gamepass ownership, and Store/StateMachine
  networking round-trips. Some need **>1 player** — use Studio **Test ▸ Clients & Servers (2
  players)**, or fall back to mock players for the pure-function parts.

> Both the server suite and (where present) the client suite run in the same Play session; the
> client launcher must wait until the server signals "ready" (see §1.3) before running network cases.

---

## 1. Harness & infrastructure to build first

The executing agent must create a small amount of shared scaffolding before writing cases.

### 1.1 Minimal test runner — `test/Framework/TestRunner.luau`
A dependency-free runner. Required surface:
- `describe(name, fn)` / `it(name, fn)` (nestable), where `fn` may yield (tests are run in a
  `task.spawn` + completion signal so async assertions work).
- `expect(value)` with at least: `.toBe`, `.toEqual` (deep), `.toBeNil`, `.toBeTruthy`,
  `.toBeFalsy`, `.toThrow`, `.never`. Deep-equal must handle nested tables (state snapshots).
- A `spy()` helper returning a callable that records `.calls` (count + args) and supports
  `.returns(...)` / `.invokes(fn)` — needed to stub `DataServer` and assert handler invocation.
  **Caveat:** `spy()` is a callable *table*, not a function. Code that strictly checks
  `type(cb) == "function"` (e.g. `MarketServer:RegisterHandler`) or passes the callback to
  `task.spawn` will **reject** it. In those spots, register/pass a plain wrapper that forwards to the
  spy — `function(...) return mySpy(...) end` — so the call is still recorded. (Signal `:Connect`
  accepts the spy directly, since `Fire` invokes it via `__call`.)
- `run()` collects pass/fail per case and prints a readable summary via `Craftsman.PrintUtil`
  (use `PrintUtil:ListPrint`/`PrintObject` for a clean table in the Studio Output). Print a final
  `PASS n / FAIL m` line and `warn()` each failure with its assertion message + traceback so failures
  are obvious in the Output window. (No exit-code handling needed — this is an interactive session.)

> Keep it tiny; do not pull in an external framework. Match the project's lightweight, `nonstrict` style.

### 1.2 Mock helpers — `test/Framework/Mocks.luau`
- `Mocks.player(userId, name?)` → a table `{ UserId = userId, Name = name or ("P"..userId), Parent = game.Players }`.
  Sufficient for everything that only reads `UserId`/`Name`/`Parent` (Store `PlayerAction`,
  `getPlayerState`, Market `GrantProduct`/`GrantGamepass`, `make_transaction_key`). **Not** sufficient
  for APIs that call `Players:GetPlayerByUserId` (see Tier B notes).
- `Mocks.stubDataServer(overrides)` → monkeypatches methods on the **real** `Craftsman.DataServer`
  singleton table (Market captured this same reference at require time, so patching its methods is
  observed by Market). Provide stubs for `GetPlayerRecord`, `LoadPlayer`, `SavePlayer` returning
  Promises you control; return a `restore()` closure that puts the originals back in `afterEach`.
- `Mocks.newPlayerProducer(template, actions)` → thin wrapper over
  `Craftsman.Store.CreatePlayerProducer(template)(actions)` used as a real, pure `Market.Producer`.
- `Mocks.withConfig(path, value, fn)` → temporarily mutate `Craftsman.Config` (e.g.
  `Config.MARKET.PRODUCTS[id] = "Handler"`) and restore after. Note `DataServer`/`MarketServer`
  capture `Config.DATA`/`Config.MARKET` **by reference** at load, so mutating the nested tables in
  place is visible to them.

### 1.3 Launchers & project
- **Server launcher** `test/Server/RunTests.server.luau`: requires every `*.spec.luau` under
  `test/Server`, runs Tier A immediately, then for Tier B waits for the real player
  (`Players.PlayerAdded` / existing `Players:GetPlayers()`), runs the live cases, then sets a
  `ReplicatedStorage` attribute / fires a `RemoteEvent` (`__CraftsmanTestsServerDone`) so the client
  suite knows the server is ready for network round-trips.
- **Client launcher** `test/Client/RunTests.client.luau`: requires `test/Client/*.spec.luau`. For any
  network case, **await the server-ready signal** before asserting (the server broadcaster must be up
  and the player's state hydrated). Use `Craftsman.DataClient.Loaded`/`StoreClient` to detect hydrate.
- **Coordination:** create one `RemoteEvent`/`RemoteFunction` under `ReplicatedStorage` (e.g.
  `CraftsmanTestBridge`) for the few cases that need the client to ask the server to dispatch/mutate
  and then assert the replicated result client-side.
- Reuse / extend `test.project.json` so Rojo maps `test/` into the place. Confirm
  `test/CraftsmanConfig.luau` (defines `SCHEMA`, `TEMPLATE`, `PRODUCTS`, `GAMEPASSES`) is mapped into
  `ReplicatedStorage.CraftsmanConfig` since `Config.luau` hard-requires it.
- **Control bootstrap explicitly.** The production `test/Bootstrap.server.luau` auto-starts
  `DataServer`/`MarketServer`/broadcaster. For a clean run, **either**:
  - (a) keep it, and have Tier B suites reuse the already-started services + the real player
    (simplest for live lifecycle/networking tests); **or**
  - (b) omit it from the test project (or set `AUTO_START_SERVER = false`) and let each suite drive
    `Init`/`Start` itself.
  Tier A suites must **not** depend on the production bootstrap — they construct their own producers
  and stub `DataServer`. If (a) is used, run Tier A *before* starting live services, or use a separate
  producer instance so stubs don't fight the live broadcaster.

### 1.4 How to run (Studio)
1. `rojo serve test.project.json` (or build: `rojo build test.project.json -o test.rbxl` and open it).
2. In Studio: **Game Settings ▸ Security ▸ Enable Studio Access to API Services = ON** (required for
   the Tier B Data cases).
3. Press **Play (F5)** — this starts the server and one client. The server launcher runs Tier A +
   server-side Tier B; the client launcher runs client/network cases after the server-ready signal.
4. Read results in the **Output** window (filter by the `[RunTests]`/PrintUtil prefix).
5. For multi-player cases (DT/MK/network slice-filtering): use **Test ▸ Clients and Servers**, set
   **2 players**, then **Start**.

---

## 2. Store suite — `test/Server/Store.spec.luau`  (Tier A, all)

`Store` is pure; no services, no stubs. Highest-confidence suite.

| ID | Case | Arrange / Act | Assert |
|----|------|---------------|--------|
| ST-01 | `CreateProducer` returns working producer | create producer `{Coins=1}` with `AddCoins`; `producer.AddCoins(5)` | `getState().Coins == 6` |
| ST-02 | Action shallow-clones top level (immutability) | capture `s1=getState()`; dispatch; `s2=getState()` | `s1 ~= s2` and `s1.Coins` unchanged (old snapshot frozen) |
| ST-03 | Action returning `nil`/non-table is a no-op | action returns `nil` | state identity unchanged (`getState()` returns same ref) |
| ST-04 | Action returning unchanged values is a no-op | action returns `{Coins = state.Coins}` | `getState()` returns same ref (no new table) — verifies `changed` short-circuit |
| ST-05 | `Store.None` removes a key | action returns `{Coins = Store.None}` | key `Coins` is `nil` afterward |
| ST-06 | `Store:Merge` immutably merges + `None` removes | `Merge({a=1,b=2},{b=3,a=Store.None})` | result `{b=3}`, original unmutated |
| ST-07 | `Store:Omit` immutably drops a key | `Omit({a=1,b=2},"a")` | result `{b=2}`, original unmutated |
| ST-08 | `CreatePlayerProducer` seeds empty dict | create player producer | `getState()` is `{}` |
| ST-09 | `_LoadPlayer` inserts a player slice | `_LoadPlayer("1",{Coins=0})` | `getPlayerState("1").Coins == 0` |
| ST-10 | `PlayerAction` no-ops when player absent | dispatch `AddCoins("2",5)` with no slice for "2" | state ref unchanged; `getPlayerState("2") == nil` |
| ST-11 | `PlayerAction` updates only that player | load "1" and "2"; `AddCoins("1",5)` | "1" changed, "2" slice ref unchanged |
| ST-12 | `PlayerAction` accepts `Player` or id string | dispatch with `Mocks.player(1)` and with `"1"` | both resolve to user id `"1"` |
| ST-13 | `_AddReceipt` records id, clones receipts | `_LoadPlayer("1",{Receipts={}})`; `_AddReceipt("1","Receipts","r1")` | `getPlayerState("1").Receipts.r1 == true`; previous Receipts table not mutated |
| ST-14 | `_AddReceipt` no-ops for absent player | `_AddReceipt("9","Receipts","r1")` | state ref unchanged |
| ST-15 | `_UnloadPlayer` removes the slice | load "1"; `_UnloadPlayer("1")` | `getPlayerState("1") == nil` |
| ST-16 | `PlayerActionRegistry` registers custom + internal actions | after `CreatePlayerProducer` | registry has user actions **and** `_LoadPlayer`/`_UnloadPlayer`/`_AddReceipt` = true |
| ST-17 | `getPlayerState` selector form | `getPlayerState("1", function(s) return s.Coins end)` | returns the selected number, `nil` when player absent |
| ST-18 | `subscribePlayer` listener fires on that player's change | subscribe "1"; dispatch `AddCoins("1",5)` | listener called with new slice; **not** called for "2" changes |
| ST-19 | `subscribePlayer` selector + predicate overloads | use 3-arg and 4-arg forms | selector/predicate gate correctly; unsubscribe returned fn stops further calls |

Edge cases to fold in: dispatching an action whose result references a nested table must not mutate
the prior snapshot (documents the shallow-clone warning in `Store/init.luau`).

---

## 3. Market suite

### 3.1 Core logic — `test/Server/MarketServer.spec.luau`  (Tier A, via stubs)

**Shared Arrange (beforeEach):**
1. `producer = Mocks.newPlayerProducer({Coins=0, Receipts={}}, { AddCoins=..., SetCoins=... })`.
2. `Craftsman.MarketServer:Init({ Producer = producer })`.
3. `restore = Mocks.stubDataServer{ GetPlayerRecord = ()->{Loaded=true}, LoadPlayer = Promise.resolve, SavePlayer = <controllable> }`.
4. Seed: `producer._LoadPlayer("123", {Coins=0, Receipts={}})`; `player = Mocks.player(123)`.
5. `Config.MARKET.PRODUCTS[999] = "AddCoins100"` and register handler `MarketServer:RegisterHandler("AddCoins100", spyHandler)` where the handler dispatches `producer.AddCoins("123",100)` and returns `true`.
6. afterEach: `restore()`, reset `producer`, clear registered handlers / config entry.

| ID | Case | Act | Assert |
|----|------|-----|--------|
| MK-01 | `RegisterHandler` validates args | register with non-string / non-function | returns `false`; valid returns `true` |
| MK-02 | `GetProductDefinition` / `GetGamepassDefinition` normalise string defs | look up `999` | returns `{Handler="AddCoins100"}` |
| MK-03 | `GrantProduct` happy path | `SavePlayer`→resolve; `GrantProduct(player,999)` | returns `(true,false,state)`; handler called once; `getPlayerState(123).Coins == 100`; receipt recorded; `ProductGranted` fired once |
| MK-04 | **Idempotency** — duplicate receipt | call `GrantProduct(player,999,{ReceiptId="r1"})` twice | 1st: granted + fires; 2nd: returns `(true,true,state)` (already-processed), handler **not** called again, `ProductGranted` **not** fired again, Coins stays 100 |
| MK-05 | **H3 regression** — rollback on save failure | `SavePlayer`→reject("DataStoreError"); `GrantProduct(player,999,{ReceiptId="r2"})` | returns `(false, <reason>)`; `getPlayerState(123).Coins == 0` (grant rolled back); `Receipts.r2` absent; `ProductGranted` not fired |
| MK-06 | H3 — retry after rollback succeeds | after MK-05, set `SavePlayer`→resolve, call again with same `ReceiptId="r2"` | now succeeds; Coins == 100; receipt present (proves the rollback unblocked the retry path) |
| MK-07 | Handler returns `false` | handler returns `false, "NotEnough"` | `GrantProduct` returns `(false,"NotEnough")`; no save; no receipt; no signal |
| MK-08 | Handler throws | handler `error("boom")` | `GrantProduct` returns `(false, <err>)`; pcall contained; state unchanged |
| MK-09 | Missing definition | `GrantProduct(player, 12345)` (unmapped) | returns `(false,"MissingDefinition")` |
| MK-10 | Missing handler | def maps to unregistered handler name | returns `(false,"MissingHandler")` |
| MK-11 | No producer configured | fresh MarketServer w/o `Init` producer | returns failure `"MarketServer requires a Producer..."` |
| MK-12 | `GrantGamepass` sets cache + default ReceiptId | grant gamepass id `555` mapped to handler | `(true,false,state)`; `UserOwnsGamePass(player,555)` now true from cache; ReceiptId defaulted to `Gamepass:555` |
| MK-13 | Context defaulting | `GrantProduct` with `{PurchaseId="px"}` no `ReceiptId` | receipt recorded under `px` (ReceiptId←PurchaseId) |
| MK-14 | Transaction queue serialises same key | enqueue two transactions via `_EnqueueTransaction` with identical key where the first yields | second is deduped/serialised (same promise or runs after first); no double-grant |
| MK-15 | `PromptProduct`/`PromptGamepass` guards | call before `Started` / with non-number id | returns `false`, does not call MarketplaceService |

> Promote to Tier A: **MK-B2** below needs no real player, so add it to `MarketServer.spec.luau`.

### 3.2 Integration — `test/Server/MarketServer.integration.spec.luau`  (Tier B, live session)

Use the real player from the Play session (`Players:GetPlayers()[1]`, after waiting for it). With the
real player loaded, `_ProcessReceipt` runs end-to-end against the real `MarketplaceService` callback
shape (you invoke `MarketServer:_ProcessReceipt(fakeReceiptInfo)` directly — you do **not** make a
real purchase) and the real DataStore.

| ID | Case | Notes |
|----|------|-------|
| MK-B1 | `_ProcessReceipt` decision mapping | With the real player's `UserId` in `receipt_info.PlayerId` (so `Players:GetPlayerByUserId` resolves): a registered handler that succeeds → returns `Enum.ProductPurchaseDecision.PurchaseGranted`; a handler that fails / an unknown product → `NotProcessedYet`. |
| MK-B2 | `_ProcessReceipt` malformed input *(Tier A — no real player)* | non-table / `nil`/empty `PurchaseId` → `NotProcessedYet`; unknown `PlayerId` → `NotProcessedYet`. These early-return before any service call. |
| MK-B3 | `UserOwnsGamePass` caches web result | first call hits `MarketplaceService:UserOwnsGamePassAsync` (already pcall-wrapped), second served from cache; assert only one web call via a spy on a wrapper. Needs a real gamepass id from `CraftsmanConfig`. |
| MK-B4 | End-to-end purchase persists receipt | real DataStore: `GrantProduct` for the live player, then `ClosePlayer`+`LoadPlayer` (or `SavePlayer`), assert the receipt survives the save/open cycle. |

---

## 4. Data suite

### 4.1 Signal shims — `test/Server/DataServer.signals.spec.luau`  (Tier A)

`Data.Loaded` exposes `Connect/Once/Wait/Fire`; `Fire` drives the internal signal, so the
**future-load** path is fully testable without a datastore. (`Data.Saved` is a plain signal.)

| ID | Case | Act | Assert |
|----|------|-----|--------|
| DT-01 | **H2 regression** — `Once` with nothing loaded fires exactly once on a future load | `local c = Data.Loaded:Once(spy)`; `Data.Loaded:Fire(p1,s1)`; `Data.Loaded:Fire(p2,s2)` | `spy` called **once** total, with `(p1,s1)`; returned `c` is a real connection (has working `Disconnect`) |
| DT-02 | H2 — `Once` returns a cancellable handle | `Once(spy)`; `c:Disconnect()`; `Fire(p1,s1)` | `spy` **never** called (proves it is not the old no-op stub) |
| DT-03 | `Connect` fires for every future load | `Connect(spy)`; `Fire` twice | `spy` called twice; returned connection still connected |
| DT-04 | `Connect` returns disconnectable conn | disconnect then `Fire` | no further calls |
| DT-05 | `Saved` is a normal signal | connect, `Data.Saved:Fire(p,s)` | listener receives `(p,s)` |

> The **replay-to-already-loaded** branch (iterating `PlayerRecords`) cannot be exercised in Tier A
> because `PlayerRecords` is private and only populated by a real load — cover it in DT-B-series.

### 4.2 Session lifecycle & reconciliation — `test/Server/DataServer.integration.spec.luau`  (Tier B, live session + API Services)

Setup: set `Config.DATA.STORE_NAME` to a **unique per-run** name (e.g. suffix `os.time()`) to avoid
cross-test contamination; if not relying on the production bootstrap, `Config.DATA.AUTO_START_SERVER = false`
then `DataServer:Init({Producer=PlayerData})`. Use the real Play-session player
(`Players:GetPlayers()[1]`, awaited). To seed specific stored data for DT-B2/DT-B3, write it first via
`DataStoreService:GetDataStore(STORE_NAME):SetAsync(tostring(userId), data)` before `LoadPlayer`.

| ID | Case | Notes |
|----|------|-------|
| DT-B1 | Load creates default state from `TEMPLATE` | fresh key → `LoadPlayer` resolves with template-shaped state; `getPlayerState` populated; `Loaded` fires. |
| DT-B2 | Reconcile fills missing template keys | pre-write partial data via `DataStoreService` SetAsync, load → missing keys back-filled (`reconcile_template`). |
| DT-B3 | Reconcile/validate reset on corrupt data | pre-write data violating the GreenTea `SCHEMA` (e.g. `Coins="x"`), load → warns and resets to template (`reconcile_state`→`clone_template`). |
| DT-B4 | `LoadPlayer` is idempotent while in flight | call `LoadPlayer` twice rapidly → same `LoadPromise`, single open. |
| DT-B5 | Session-lock steal path | open the same key in a second `DocumentStore`, then `LoadPlayer` → `SessionLockedError` on attempt 1 triggers `Steal()` and succeeds on attempt 2. |
| DT-B6 | `SavePlayer` persists current producer state | mutate producer, `SavePlayer`, reopen doc → persisted; `Saved` fires. |
| DT-B7 | `ClosePlayer` saves, unloads, releases | after close: `getPlayerState` nil (unloaded), record removed, lock released. |
| DT-B8 | `Shutdown` closes all sessions | load 1–2 players, `Shutdown()` → all saved + records cleared (uses numeric snapshot loop, not live iteration). |
| DT-B9 | `ENABLED=false` short-circuit | `Config.DATA.ENABLED=false`, `Init` → no DataStore touched, `DefaultState` set; assert no error. (Tier A-ish, but keep with Data.) |
| DT-B10 | H2 replay branch | with a player already loaded, `Data.Loaded:Once(spy)` fires immediately for that player **and** a later `Connect` still works for subsequent loads. |

---

## 5. Store networking — server filter (Tier A) + live round-trip (Tier B)

Because the target is a Play session with client+server, the round-trip is runnable. Split it:

### 5.1 Pure broadcaster logic — `test/Server/StoreServer.spec.luau`  (Tier A)
`StoreServer.CreateStateFilter(player_state_key)` and the default `beforeDispatch` are pure closures —
call them directly with `Mocks.player(...)` and a hand-built state table; no network needed.

| ID | Case | Assert |
|----|------|--------|
| SN-01 | Filter keeps only the player's own slice | `CreateStateFilter("Players")(p1, {Players={["1"]=a,["2"]=b}, Other=x})` → `{Players={["1"]=a}, Other=x}` (other players stripped, non-player keys kept) |
| SN-02 | Filter yields empty player slice when player has none | player with no entry → `{Players={}}` |
| SN-03 | `beforeDispatch` passes a self-targeted player action | action in `PlayerActionRegistry`, first arg = sender's UserId → returns the action unchanged |
| SN-04 | `beforeDispatch` drops a spoofed player action | first arg = a *different* UserId → returns `nil` (dropped) |
| SN-05 | `beforeDispatch` passes non-player actions | action not in registry → returned unchanged |

### 5.2 Live round-trip — `test/Client/Store.network.spec.luau`  (Tier B, live session)
With the broadcaster started server-side and the real client connected:

| ID | Case | Assert |
|----|------|--------|
| SN-B1 | Client hydrates own slice | after join, client `PlayerData:getPlayerState(LocalPlayer)` matches server (and contains no other players' slices). |
| SN-B2 | Dispatched action replicates | server dispatches a player action (via the test bridge) → client observes the new value through `subscribePlayer`. |
| SN-B3 | Other players' state not leaked | in a 2-player session, client A never receives B's slice (inspect hydrate/dispatch payloads). |

---

## 6. Regression matrix (lock the recent fixes)

| Recent fix | Locked by |
|------------|-----------|
| **H2** `Data.Loaded:Once` rewrite | DT-01, DT-02 (Tier A) + DT-B10 (replay) |
| **H3** Market receipt-before-save rollback | MK-05, MK-06 (and MK-04 idempotency) |
| Store immutability / `None` / registry (touch points of M1/H3) | ST-02..05, ST-13, ST-16 |
| Market idempotency & queue serialisation | MK-04, MK-14 |
| Data reconcile/validate correctness | DT-B2, DT-B3 |
| M2 store networking trust (filter + spoof-drop) | SN-01..05, SN-B3 |

---

## 7. Suggested build order
1. Harness (`TestRunner`, `Mocks`) + server/client launchers + project wiring + the test bridge (§1).
2. **Store suite** (§2) — pure, fast feedback that the harness works.
3. **Market Tier A** (§3.1) — highest-risk logic (money + the H3 fix), deterministic via stubs.
4. **Data signal shims** (§4.1) — locks H2.
5. **StoreServer filter** (§5.1) — pure, locks the M2 trust boundary.
6. **Tier B live suites** (§3.2, §4.2, §5.2, DT-B*) in the Play session with API Services on; do the
   2-player networking/slice cases last via Test ▸ Clients and Servers.

## 8. Assumptions & risks
- **Run order vs. live services:** Tier A Market tests stub `Craftsman.DataServer` and use their own
  producer. If the production bootstrap has already started the real `DataServer`/broadcaster in the
  session, run Tier A first (or in a separate producer) and always `restore()` stubs in `afterEach`
  so they don't corrupt the live services used by Tier B.
- `Mocks.stubDataServer` works because Market captured the `DataServer` *table reference* at require
  time; if Market is ever changed to capture method references, stubbing must adapt.
- `Mocks.player` is a plain table; any path calling real `Player`/`Players` APIs (e.g.
  `Players:GetPlayerByUserId` in `_ProcessReceipt`) must use the real session player (Tier B).
- Tier B needs **API Services enabled** and consumes DataStore request budget — use unique store
  names per run and keep player counts small; expect throttling if you loop many saves.
- Single-player Play (F5) yields one `LocalPlayer`; slice-isolation cases (SN-B3, multi-player DT)
  need **Test ▸ Clients and Servers (2 players)**.
- Reflex dispatch is synchronous for these producers; replication and DataStore calls are async, so
  use the runner's yield-aware `it` (poll/await with a timeout) for all Tier B assertions.
