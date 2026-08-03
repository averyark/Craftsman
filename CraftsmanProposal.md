# Craftsman - Proposal from nexamon

An outside-in review of `averyark/craftsman@0.7.8` using nexamon as the evidence base. The question
behind it: nexamon is Craftsman's flagship consumer, so what does the way it *actually* uses the
framework tell us about what the framework should be?

Every claim below cites a file and line so it can be audited or refuted. Claims I could not verify
are marked **[unverified]**.

---

## Method

- Grepped every `Craftsman.*` reference across `src/` to establish real uptake.
- Read the full export surface of `init.luau`, `Component`, `Config`, and all eight `Utilities/`.
- Cross-referenced nexamon's file-local helpers (`^local function`) against existing utility APIs.
- Ran the `PrintUtil` frame-resolution question under `lune` rather than reasoning about it — then
  re-ran it in Studio, because `lune` gave the wrong answer. See Rejected.
- Ran the `typeof(require(...))` erasure and lazy-`__index` questions (P1.2) under `lune` the same
  way — the require counts in that section are measured, not assumed.
- **Where a claim depends on the runtime, it was checked in Studio.** `lune` stubs `require`,
  `game`, `task` and `Keeper`, so it proves logic and not integration; the frame-depth question in
  Rejected is a worked example of it disagreeing with Roblox outright.
- Excluded `src/Shared/Forge/` throughout — it is vendored third-party (licensed emit module), so
  its helpers are not evidence of what nexamon needs.

**Citations are prefixed by repo:** `craftsman:Config.luau:105` is Craftsman's own source,
`nexamon:ContextManager.luau:58` is the consumer's. Claims resting on `craftsman:` paths hold
regardless of which game is looking; claims resting on `nexamon:` paths are subject to the
sample-of-one limitation below.

**Known limitation: this is a sample of one.** nexamon is a creature-combat game with a lockstep
ability runtime; `rblx-fast-fps` is a different genre with different needs and is a real consumer of
modules nexamon never touches. Evidence here supports claims of the form *"nexamon needs X"* or
*"X is broken"*. It does **not** support *"Craftsman should drop Y"* — absence of use in one game is
not evidence of low value, and an earlier draft of this document made exactly that mistake about
`StateMachine` and `Store`. Proposals below are scoped accordingly: additive, or fixes to things
demonstrably broken. Anything genuinely subtractive needs a second consumer's data before it earns
an opinion.

---

## TL;DR

**Craftsman does not use its own `TableUtil`.**

`craftsman:Config.luau:46-100` hand-rolls `deep_clone` and `deep_merge` that already exist as
`TableUtil.DeepClone` / `TableUtil.DeepMerge` — not approximately, but near-identically, down to the
`getmetatable(...) ~= nil` skip that treats GreenTea schemas as opaque. `TableUtil` requires nothing,
so no dependency cycle explains the copy. The framework's own author reached for a hand-rolled helper
while the library version sat one directory away.

This evidence is framework-internal: it holds no matter what any consumer does, and it is the one
uptake claim in this document that a second consumer cannot refute.

Consumer-side, nexamon references `MathUtil`, `TableUtil`, and `WorldUtil` **exactly zero times**
while hand-rolling helpers alongside them. That is offered as *context, not proof* — per the
limitation above, silence in one game is not evidence of low value, and that rule applies to
`WorldUtil` exactly as it applies to `StateMachine` (P1.2). nexamon answered casts with its own
hitbox code the same way it answered state with JECS. If `rblx-fast-fps` calls these freely, the
consumer-side half of this section evaporates and only the `TableUtil` finding above survives —
which is enough to act on, and is the only part that should be acted on without a second data point.

The module loader has the same shape of problem. `nexamon:Bootstrap.server.luau:17` points
`Component:LoadModulesAsync` at `ServerScriptService.Server`, which contains exactly one module —
`GameplayHandler.luau`, which requires Craftsman and returns an empty table. The real game starts on
the next line, by hand:

```lua
Bootstrap:Start(ServerScriptService.Server)   -- the loader, fed an empty folder
Combat.Start()                                -- the actual game
```

**So the recommendation is not "add a 21st utility."** The framework duplicates its own `TableUtil`
internally, and its core loader is fed an empty folder by the game it ships for. Adding surface area
on top of that is treating the symptom. The proposals below are ordered to fix uptake first.

---

## P0 - Correctness

These are bugs, not design opinions. They are cheap and independent of everything else.

### P0.1 - `PrintUtil:Error(msg, level?)` does not exist — **[implemented]**

`nexamon:CLAUDE.md` documents the contract as `Craftsman.PrintUtil:Error(msg, level?)`, and
`nexamon:ContextManager.luau:58` relies on it:

```lua
Craftsman.PrintUtil:Error(`Client cannot write to server-owned context key {key}`, 2)
```

But `craftsman:PrintUtil.luau:116-124` concatenates **all** varargs into the message and calls
`error(message)` with no level argument. So the `2` is stringified into the output, and the error
blames `PrintUtil.luau` rather than the offending `__newindex` caller.

**Fix:** accept `level` as a real trailing parameter and forward it to `error(msg, level)`.

### P0.2 - `Config.PlayerState` is broken for any consumer without a `SCHEMA`

`craftsman:Config.luau:105`:

```lua
export type PlayerState = typeof(CraftsmanConfig.DATA.SCHEMA:type())
```

`nexamon:CraftsmanConfig.luau` never sets `DATA.SCHEMA`, so this indexes `nil`. It survives only
because it sits in a type position under `--!nonstrict`. `PlayerState` backs
`ConfigEditType.DATA.TEMPLATE`, so the config's own type contract is dead here.

**Fix (superseded — see below):** make `PlayerState` a generic parameter rather than a global
reach-through into the consumer's config module.

**Revised, and the original fix was wrong.** `DATA.SCHEMA` is canon: `rblx-fast-fps` defines one,
nexamon will once it does its data work, and defining one is the supported way to type player data.
Given that, the reach-through is *correct* and generics would be a downgrade — they would push the
type back onto every call site to restore what the schema already states once.

The real defect was never the reach-through; it was that the reach-through was welded to a *runtime*
require. P1.1 separates them: `PlayerState` still reads the consumer's schema, inlined into a type
position where `typeof` erases it, so it costs nothing and cannot stop Craftsman loading. That
lands as part of P1.1.

What survives of P0.2 is narrower: a consumer with no `SCHEMA` still indexes `nil` and gets a
silently degraded `PlayerState`. **Open question:** warn or throw? Throwing today would break
nexamon, which uses `Data` with no schema. Currently it does neither.

---

## P1 - Uptake

This is where the actual leverage is.

### P1.1 - Invert the config dependency — **[implemented]**

`craftsman:Config.luau:102-103` hard-requires `ReplicatedStorage.CraftsmanConfig` **at module
scope**:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CraftsmanConfig = require(ReplicatedStorage.CraftsmanConfig)
```

The library depends on its consumer. Craftsman cannot load in a place that does not define this
exact module at this exact path — no defaults, no minimal consumer, no headless test.

**Proposal:** an explicit `Craftsman.Configure(config)` call, made from `Shared/Bootstrap.luau`
(which already exists and already does `require(".../CraftsmanConfig")` for its side effect).
Defaults apply when it is never called.

This one change is a prerequisite for P1.2 and P2.2. **It is numbered P1.1 for cross-reference
stability, but it belongs in P0 by priority** — it is not a preference. Craftsman cannot load
anywhere that lacks this exact module at this exact path, which means it cannot be tested headlessly,
which is the reason P0.2 shipped dead and went unnoticed. Every other proposal here gets cheaper once
this lands.

### P1.2 - Make the barrel lazy — **[laziness implemented; gating withdrawn]**

`craftsman:init.luau` eagerly requires 30 modules behind 30 exports — 26 unconditionally, plus
`Data/Server`, `Market/Server`, `StateMachine/Server`, and `Store/Server` on the server.

The cost is not the autostart flag. `AUTO_START_SERVER` is checked *inside* `Server:Start()`
(`craftsman:StateMachine/Server.luau:385`), which the consumer calls explicitly — requiring the
module does not autostart anything. The cost is one layer down:
`craftsman:StateMachine/Network.luau:11` and `craftsman:Store/Network.luau:11` call
`ByteNet.defineNamespace` **at module scope**. Requiring the module registers the namespace and
allocates its packet IDs, before any consumer opts in.

**So `AUTO_START_SERVER = false` does not avoid this cost.** There is no configuration that avoids
it. The only lever is not requiring the module, and `init.luau` removes that lever.

What nexamon uses: `PrintUtil` (~30 of ~45 call sites), `Entity`, `Component`, `Data`/`Market`,
`Spring`, `InputUtil`, `AnimationUtil`, `SoundUtil`.

What nexamon uses **zero** of: `StateMachine` (7 files + networking), `Store` (5 files +
networking), `Queue`, `Debounce`, `Concurrency`, `Tag`, `Pathfind`, `TableUtil`, `MathUtil`,
`StringUtil`, `TweenUtil`, `WorldUtil`.

A `Craftsman.PrintUtil:Warn` in a leaf Director action therefore *executes* the entire market and
state-machine stack. This has a concrete design consequence today: `nexamon:Hitbox.luau` deliberately
does **not** require Craftsman, because dragging the barrel into a lockstep action to save one line
is not worth it.

**Be precise about what the cost is.** Roblox has no tree-shaking, but that is not the problem here
and long require paths would not fix it — every ModuleScript ships into the place file either way.
The cost is **module-scope execution**, and that is entirely avoidable without touching a single
call site.

**Proposal:** keep `Craftsman.X` exactly as it is and make the barrel lazy.

```lua
-- init.luau
export type Craftsman = {
	PrintUtil: typeof(require("@self/Utilities/PrintUtil")),   -- type only; never executed
	StateMachine: typeof(require("@self/StateMachine")),
}

local loaders = {
	PrintUtil = function() return require("@self/Utilities/PrintUtil") end,
	StateMachine = function() return require("@self/StateMachine") end,
}

return (setmetatable({}, {
	__index = function(self, key)
		local module = loaders[key]()
		rawset(self, key, module)   -- memoise; subsequent access is a plain hit
		return module
	end,
}) :: any) :: Craftsman
```

Both halves were verified under `lune` rather than assumed:

| probe | requires executed |
| --- | --- |
| `local M = require(x)` (baseline) | 1 |
| `type M = typeof(require(x))` | **0** |
| `export type B = { X: typeof(require(x)) }` | **0** |
| lazy `__index` barrel, untouched | **0** |
| lazy `__index` barrel, one member read twice | **1** |

So the type surface is permanent and free — `typeof(require(...))` is erased, and costs nothing at
runtime — while `StateMachine` is never executed unless something reads `Craftsman.StateMachine`.
The consumer-facing path never changes, and `nexamon:Hitbox.luau` could require Craftsman freely.

**Gate what has side effects; leave the utilities alone.** Once the barrel is lazy, `MathUtil`,
`TableUtil`, `StringUtil`, and `WorldUtil` have no cost left to opt out of — they are pure, with no
network surface. Gating them would buy nothing and cost real safety: a permanent type plus an
error-when-disabled means `Craftsman.MathUtil.Lerp(a, b, t)` typechecks clean, ships, and fails at
runtime because a config table omitted a name. That is a footgun that only fires in production, in
exchange for a cost laziness already removed.

`Data` / `Market` / `StateMachine` / `Store` are the opposite case, and should be opt-in via
`Configure` with a hard error on disabled access — because there the typechecker can never answer the
question that matters:

**Namespace setup has to stay symmetric across the network boundary.** ByteNet assigns packet IDs on
the server at `defineNamespace` time and writes them to a replicated value; the client reads them
back *by key name* rather than allocating its own. Require *order* is therefore safe on its own — but
a consumer that enables `Store` on the client while the server does not will have the client reading
a namespace that was never written. Today `init.luau` hides this by requiring everything on both
sides; laziness exposes it.

**An earlier draft of this section claimed that failure is a silent, permanent client hang. It is
not — that was wrong, and it was the main argument for gating.** `values.access`
(`bytenet-max/src/replicated/values.luau:26-56`) uses `FindFirstChild`, not `WaitForChild`: a
namespace the server never wrote returns `nil`, and `namespace.luau:70` then calls `nil:read()`. The
client **errors immediately**. Cryptic — `attempt to index nil value` from inside a vendored package
— but loud, immediate, and impossible to ship past.

That materially weakens the case for gating. The failure is already fatal at boot; gating would only
improve the *wording* of an error you cannot miss. Weigh that against its costs: `Config` has
`ENABLED` keys for `DATA`, `MARKET` and `STATE_MACHINE` but **none for `Store`**, so a quarter of
the subsystems have nothing to gate on; and making `Craftsman.StateMachineServer` throw is a live
behaviour change for `rblx-fast-fps`, which uses it — breaking a working game to reword an error it
never sees.

**Recommendation: drop the gating half of P1.2.** Laziness already delivered the cost argument that
justified this section. What remains worth doing is smaller and unrelated to opt-in:

`values.access` uses `FindFirstChild` for the namespace *even in the symmetric case*, so a client
that requires a namespace before it has replicated gets the same nil-index. It works today only
because the server defines its namespaces before client scripts run. A `WaitForChild` preflight in
`craftsman:Store/Network.luau` and `craftsman:StateMachine/Network.luau` would close that race
**and** replace the nil-index with a message naming the subsystem and the missing context. That is
two files and no new configuration surface. **[unverified]** — the race is inferred from reading
`values.access`; it has not been reproduced.

**Independent requires (`require(".../Craftsman/PrintUtil")`) are a secondary benefit, not the
headline.** With a lazy barrel there is little left to gain: they help only a consumer who wants to
skip `init.luau` entirely. Worth offering; not worth ugly paths at every call site.

**Status: the laziness half is landed in `craftsman:init.luau`.** The export surface is a
`typeof(require(...))` type resolved through a memoising `__index`; `Craftsman.X` is unchanged for
every caller. Measured under `lune` against the real file: 0 requires at load, exactly 1 per touched
export, no re-require on repeat access, all 30 exports resolve, and every export maps to the same
module path as before.

Confirmed in Studio via `craftsman:test/Shared/BarrelSmoke.luau`, which runs under the real loader
during a normal boot on both server and client. This settles the one assumption `lune` could not
test — whether Roblox resolves a `require("@self/...")` deferred inside a closure rather than at
module scope. It does. The smoke test also asserts laziness against a real boot: `rawget` bypasses
`__index`, so exports `Bootstrap` never touches must still be unresolved when `Start` runs.

**The gating half is not built, and P1.1 is a hard blocker — not a preference.** Verified while
implementing: `craftsman:Store/Client.luau:10` requires `./Network` at module scope, so the client's
namespace *read* happens on require, exactly as the server's *write* does. Today `init.luau`
guarantees those stay paired by requiring both sides eagerly. Laziness removes that guarantee, so
the symmetry constraint above stops being theoretical the moment this lands: the only thing that can
restore it is a `Configure` that declares subsystems for both contexts at once. Until P1.1 exists
there is nothing to hang the gate on, so server-only exports still resolve to `nil` on the client
exactly as before, and no subsystem errors on access.

This ordering was not obvious from the outside. The prerequisite claim in P1.1 is stronger than it
first reads: without `Configure`, laziness is safe only because every consumer's bootstrap happens
to touch both sides of each networked subsystem.

**One seam to watch.** `__index` metatables typecheck poorly in Luau, so the `:: any :: Craftsman`
cast is load-bearing — it is what makes the barrel type at all. It is also unchecked: a key present
in the `Craftsman` type but missing from `loaders` fails only on access.

An earlier draft of this section proposed a `.spec` to assert the two agree. **That cannot work** —
the same erasure that makes the type free also makes it invisible at runtime, so no spec can
enumerate the fields of `Craftsman` to check them against `loaders`. The check has to be static: parse
the source, extract both lists, assert the name *and* module path match. It belongs in CI, not in a
spec file. (Craftsman has no test runner today and `lune` is not in `aftman.toml`, so wiring this up
is real work, not a one-liner.)

**This is a packaging argument, not a case against those modules.** `StateMachine` and `Store` are
in genuine use in `rblx-fast-fps`; nexamon's zero uptake reflects that it answered persistent state,
time-based behaviour, and view state with JECS, Director, and Reflex before reaching for them. Two
consumers with disjoint needs is the *normal* case for a framework — and it is precisely the
argument for P1.2. Today nexamon pays to execute and network-register `StateMachine` and `Store`
because fast-fps needs them, and fast-fps presumably pays for `Pathfind` or `Market` it may not
touch. Laziness lets each consumer pay only for what it touches, which makes the modules *more*
viable, not less — and unlike the packaging change, it costs neither consumer a single edit.

### P1.3 - Dependency-declared lifecycle — **[implemented]**

Ordering *was* a flat global array of **leaf module names** (`Config.MODULE_LOAD_ORDER`),
declared far from the modules it orders. nexamon leaves it empty and routes around the loader
entirely — `nexamon:Features/Combat/Server/init.luau:33` hand-orders startup:

```lua
Replication.Start()
SessionManager.Start()
Encounters.Start()
Casting.Start()
ActionStateManager.Start()
```

Five explicit lines beat the loader because the fact that `Replication` must precede
`SessionManager` lives *in Combat*, and there is no way to say so locally.

**Proposal:** declare dependencies in place, then topologically sort.

```lua
local SessionManager = { Dependencies = { Replication, Casting } }
function SessionManager.Start() end
```

This also fixed a real hazard: `craftsman:Component.luau:102-108` `:await()`ed each `Start`
**inside** the loop, so every module's `Start` serially blocked the next, with order decided by
`GetDescendants()`. One yielding module stalled the whole boot. A dependency graph parallelises
independent modules and serialises only real edges.

**Status: landed in `craftsman:Component.luau`.** Requires and `Init` still run in parallel; the
`Dependencies` array is resolved to graph edges by table identity; cycles reject the load with the
full path rather than deadlocking; and each module's `Start` awaits only its declared dependencies,
so independent modules overlap. `Init`/`Start` failures now poison dependents rather than starting
them against a half-constructed module, and the resulting warning names the *root* failure rather
than cascading.

Two notes for consumers:

- `MODULE_LOAD_ORDER` is **deprecated but still honoured** — it is translated into a chain of edges
  between the modules it names, and warns once. It is not removed.
- **This is a breaking change** for anyone relying on the old serial `:await()`. Previously *every*
  module's `Start` completed before the next began, including for pairs that never declared a
  relationship. Orderings that were genuinely relied upon but never written down now race. That is the
  intended outcome — it forces real edges to be declared — but it warrants a major-version note.

### P1.4 - Teardown and scoped cleanup — **[implemented]**

The lifecycle is one-way: there is no `Stop`, no `Unload`. But nexamon is built around things that
end — `Session.Start` / sessions closing, `Encounters`, arena reuse — which is why it pulls in
`Keeper` separately. `Entity` already owns a `Keeper` (`craftsman:Entity.luau:39`); `Component` owns
nothing.

**Proposal:** give each Component a `Keeper` scoped to its lifetime and a `Stop` phase, so session
teardown is a framework concern rather than five features each remembering to clean up.

---

## P2 - Genuinely new surface

Only two candidates survived scrutiny. Both are backed by a hand-rolled workaround in nexamon.

### P2.1 - Radian-native angle helpers in `MathUtil` — **[implemented]**

`MathUtil.ShortestAngle` is **degrees** (`% 360`, `> 180`, `-= 360`). Roblox `CFrame` and `atan2`
math is radians. So `nexamon:Controller.luau:179` hand-rolls the radian version:

```lua
local function approach_angle(current: number, target: number, alpha: number): number
	local difference = (target - current + math.pi) % (2 * math.pi) - math.pi
	return current + difference * alpha
end
```

This helper exists *because MathUtil could not serve it*. Wrapping the degrees version in
`math.deg`/`math.rad` would be more code and more float error than the four lines it replaces.

**Proposal:** radian-native variants (`ShortestAngleRad`, `ApproachAngle`), or make the module
radian-first with degree variants, matching the engine.

### P2.2 - Non-yielding rig accessors on `Entity` — **[implemented]**

`Entity` is billed as the "Character or NPC abstraction" and exposes `.Humanoid` /
`.HumanoidRootPart`, but its constructor (`craftsman:Entity.luau:37-38`) does:

```lua
self.Humanoid = entity:WaitForChild("Humanoid")
self.HumanoidRootPart = entity:WaitForChild("HumanoidRootPart")
```

Yielding, with no timeout — a rig lacking a Humanoid hangs `Entity.new` forever. So nexamon writes
the non-yielding version by hand: `get_humanoid` (`nexamon:Director/Actor.luau:18`) and `get_root`
(`nexamon:Actions/Mechanics/Dash.luau:53`), both type-guard + `FindFirstChildWhichIsA`/`PrimaryPart`
+ return `nil`. It is also why `nexamon:SessionManager.luau:230-236` hand-checks "rig has no
Humanoid."

**Proposal:** safe, non-yielding accessors on `Entity`, and a timeout on the constructor's waits.

### P2.3 - A Scheduler **[speculative]**

`nexamon:Features/Combat/Shared/Schedule.luau` is nexamon-authored and Craftsman has no equivalent —
`Queue`, `Debounce`, and `Concurrency` are all rate-limiting, none is "run these systems every frame
in a defined order." The game's version is deliberately thin: insertion order, variable `dt`, no
pause.
Director is a lockstep timeline runtime, so deterministic ordering and a fixed timestep are exactly
its requirements, and it currently has neither.

Marked speculative because, unlike P2.1 and P2.2, nothing shows nexamon is *blocked* — it wrote 30
lines and moved on. **Do not build this before P1 lands.** A Scheduler shipped into a library with
three zero-uptake utility modules is a 21st utility nobody requires.

---

## Rejected

Recorded so they are not re-proposed.

### `PrintUtil` frame depth - **not a bug, do not "fix" this**

`craftsman:PrintUtil.luau:21-24` resolves the calling module by counting stack frames:

```lua
local function get_calling_module_name()
	local info = debug.info(3, "s")
	return info:match("([^%.]+)$")
end
```

Read on the page, `3` looks wrong. Counting the frames as written gives
`get_calling_module_name` (1), `get_formatted_prefix_and_suffix` (2), `PrintUtil:Error` (3) — so
frame 3 is *PrintUtil itself*, and every message should be prefixed `[PrintUtil]`. Running it
outside Roblox agrees: under `lune` it reads `[PrintUtil]`.

**In Roblox it reads `[LifecycleSmoke]` — the caller — which is correct.** Measured on both server
and client via `craftsman:test/Shared/LifecycleSmoke.luau`, which prints the prefix rather than
asserting it:

```
[LifecycleSmoke/server] PrintUtil:Error prefix reads: [LifecycleSmoke] smoke_probe
[LifecycleSmoke/client] PrintUtil:Error prefix reads: [LifecycleSmoke] smoke_probe
```

The difference is optimisation. Roblox compiles at `-O2` and inlines small local functions, which
collapses one of the two helper frames; `lune` does not, so the frame it lands on differs. The `3`
is calibrated against the *inlined* stack — the one that actually exists at runtime — not the one
in the source.

**So the trap is specific and worth naming:** anyone who reads this function, counts frames on the
page, and "corrects" the `3` will break every log prefix in Roblox. The same goes for anyone who
verifies it under `lune`, `luau`, or any non-Roblox runtime and concludes it is off by one — the
tooling that looks most authoritative here is the tooling that is wrong. Verify claims about this
function **in Studio**, or not at all.

**[unverified]** The inlining explanation is inference from the two runtimes disagreeing; it fits,
but it was not confirmed against Luau's optimiser directly. The observable — Roblox names the
caller, and that is what the function is for — holds regardless.

**Residual risk, recorded rather than acted on:** this correctness depends on an optimiser detail.
If Roblox's inlining of these helpers ever changes, the prefix silently becomes `[PrintUtil]`
everywhere — wrong, but not broken, and nothing would fail. That is a cheap, quiet failure and not
worth pre-emptively hardening; it is the reason `craftsman:test/Shared/LifecycleSmoke.luau` prints
the prefix on every run, so a change would at least be visible in the output.
