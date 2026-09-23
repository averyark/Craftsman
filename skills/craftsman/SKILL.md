---
name: craftsman
description: Use when writing or reviewing Roblox Luau code in a project that depends on the Craftsman framework (averyark/craftsman), or when the user mentions Craftsman or one of its modules (Component, Entity, Tag, StateMachine, Queue, Debounce, Concurrency, Pathfind, Spring, TweenUtil, SoundUtil, AnimationUtil, InputUtil, TouchUtil, InterfaceUtil, WorldUtil, MathUtil, StringUtil, TableUtil, PrintUtil, Inspect). Explains how to bootstrap the game and which Craftsman utility to reach for, and gives exact call signatures, call syntax and gotchas so the agent does not hand-roll what the framework already provides.
license: MIT
metadata:
  framework-version: "0.9.0"
---

# Craftsman

Craftsman is a Roblox Luau framework. It provides:
- a lifecycle loader for singletons
- entity, tag and state-machine management
- task control
- a set of utilities

**Use Craftsman before writing your own.** If a row in the table below matches the job, use that module instead of raw engine APIs or a hand-rolled helper.

This skill covers *what to call*. It says nothing about code style: follow the project's own style guide (for example its `CLAUDE.md`). The examples here are style-neutral.

## Access

```lua
local Craftsman = require(game:GetService("ReplicatedStorage").Packages.Craftsman)
```

- The barrel lazy-loads each module the first time it is accessed.
- `Craftsman.StateMachineServer` is **`nil` on the client**.
- The framework is built on `Keeper` (cleanup), `Signal` (events), `Promise` (async) and `ByteNet` (networking). If game code uses any of these directly, add them as the project's own dependencies.

Install with Ember (`ember.toml`):

```toml
[dependencies]
Craftsman = { name = "averyark/craftsman", version = "^0.9.0" }
```

## Pick the right module

| Need | Use | Reference |
|---|---|---|
| Boot services/controllers, order startup, clean up on shutdown | `Component:LoadModulesAsync(folder)` with `Init`/`Start`/`Stop` + `Dependencies` | [lifecycle](references/lifecycle.md) |
| Framework settings (UI scale, touch, state machine) | `ReplicatedStorage.CraftsmanConfig` or `Config.Configure` | [lifecycle](references/lifecycle.md) |
| Clean up connections, instances, threads | the owning object's `Keeper` | [lifecycle](references/lifecycle.md) |
| Character/NPC states (idle, attacking, stunned…), optionally replicated | `State` + `Machine` (+ `StateMachine.Register`) | [state](references/state.md) |
| Per-character wrapper, death/removal hooks, per-life cleanup | `Entity.new` / `Entity.Get`, `Entity.Died` | [entities](references/entities.md) |
| Status effects, flags, timed buffs on instances (**not** CollectionService) | `Tag.Get(name)` → `:Add`, `:SetTag`, `:ListenToInstance` | [entities](references/entities.md) |
| NPC movement or chasing | `Pathfind.new` → `:Goto` / `:Chase` | [entities](references/entities.md) |
| Serial async jobs with retry/backoff/dedup (saves, purchases) | `Queue.new` → `:Enqueue` | [tasks](references/tasks.md) |
| Debounce or throttle a function | `Debounce.new` / `Debounce.throttle` | [tasks](references/tasks.md) |
| Per-key mutex or per-key cooldown (remote spam) | `Concurrency.AsyncLock` / `Concurrency.KeyedDebounce` | [tasks](references/tasks.md) |
| UI/property tweens and named animation presets | `TweenUtil.new` / `.Play` / `.QuickPlay` | [animation-audio](references/animation-audio.md) |
| Spring physics on properties or values | `Spring.target` / `Spring.new` | [animation-audio](references/animation-audio.md) |
| Character animations | `AnimationUtil.Register` + `GetSharedAnimate` / `QuickPlay` | [animation-audio](references/animation-audio.md) |
| Sounds: registry, 3D one-shots, per-object players | `SoundUtil.Register` / `QuickPlay` / `GetSharedSoundPlayer` | [animation-audio](references/animation-audio.md) |
| Keybinds, rebinding, device type, movement vector | `InputUtil` actions + `Began`/`Ended` | [input-ui](references/input-ui.md) |
| Mobile buttons that fire the same actions | `TouchUtil.Button(action, options)` | [input-ui](references/input-ui.md) |
| Resolution-independent UI scale | `InterfaceUtil:AutoScale(gui)` | [input-ui](references/input-ui.md) |
| Ray/block/sphere casts, ground checks, overlaps, nearest, screen↔world | `WorldUtil:*` | [world-data](references/world-data.md) |
| Lerp/map, angles, bezier, weighted random, number formatting | `MathUtil` | [world-data](references/world-data.md) |
| String helpers | `StringUtil` | [world-data](references/world-data.md) |
| Clone, merge, set ops | `TableUtil` | [world-data](references/world-data.md) |
| Debug-printing tables and values | `PrintUtil:ListPrint`, `Inspect(value)` | [world-data](references/world-data.md) |

Read the linked reference before using a module for the first time in a task. The references list every signature, default and sharp edge.

## Rules that apply everywhere

1. **Two-phase lifecycle.**
   - `Init` is synchronous: declare state and create signals. Never yield in it, because every `Init` must finish before any `Start` runs.
   - `Start` wires connections, loops and cross-module calls.
   - `Stop` is optional teardown.
   - Declare ordering with `Dependencies = { OtherModule }`, using module tables rather than names.
2. **Every connection has an owner.**
   - Route it through the `Keeper` of whatever owns it:
     - a loaded module's `self.Keeper`
     - an `Entity`'s `entity.Keeper`, which is cleaned when the entity dies
     - a Keeper you created and attached with `keeper:AttachToInstance(instance)`
   - Leave no bare `:Connect`.
3. **Decouple through signals.**
   - Game modules require each other only when the dependency is declared in `Dependencies`.
   - Everything else communicates through a `Signal` that the owning module exposes.
4. **Dot vs colon matters.** The wrong one silently shifts arguments.

   | Call with | Functions |
   |---|---|
   | `:` | every `WorldUtil` function, `InterfaceUtil:AutoScale`, `PrintUtil`, `Component:LoadModulesAsync`, `StateMachineServer:Start` / `StateMachineClient:Start`, and methods on instances (`queue:Enqueue`, `tag:Add`, `machine:Transition`, `animate:Play`…) |
   | `.` | constructors and module functions: `Tag.Get`, `Entity.Get`, `TweenUtil.Play`, `SoundUtil.QuickPlay`, `InputUtil.BindAction`, `TouchUtil.Button`, `InterfaceUtil.ComputeScale`, `MathUtil.*`, `StringUtil.*`, `TableUtil.*` |

5. **Replication has fixed entry points.** Anything else gets built by hand.
   - State machines replicate only through `Replicate` / `StateMachine.Register`.
   - Tags created on the server replicate on their own.
   - Clients read the replicated state and never mutate it.
6. **Wrap characters in entities yourself.** Nothing does it automatically: call `Entity.new(character, player)` on `CharacterAdded`.

## Minimal game skeleton

```
ReplicatedStorage/
  Packages/Craftsman
  CraftsmanConfig          -- optional ModuleScript returning config overrides
  Controllers/             -- client singletons, loaded by Component
ServerScriptService/
  Bootstrap.server.luau
  Services/                -- server singletons, loaded by Component
StarterPlayerScripts/
  Bootstrap.client.luau
```

Put only singletons in `Services/` and `Controllers/`. The loader requires every ModuleScript under the folder you pass it. The bootstrap scripts, in order:

**Server**
1. `StateMachineServer:Start()`
2. `Component:LoadModulesAsync(Services):await()`
3. Wrap characters in entities.

**Client**
1. `StateMachineClient:Start()`
2. `Component:LoadModulesAsync(Controllers):await()`

Full bootstrap code is in [lifecycle](references/lifecycle.md).

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Craftsman = require(ReplicatedStorage.Packages.Craftsman)
local Signal = require(ReplicatedStorage.Packages.Signal)

local CombatService = {}

local Stunned = Craftsman.Tag.Get("Stunned")
local HitCooldown = Craftsman.Concurrency.KeyedDebounce.new(0.4)

function CombatService:Init()
	self.PlayerKilled = Signal.new()
end

function CombatService:Start()
	self.Keeper:Connect(Craftsman.Entity.Died, function(entity)
		if not entity.Player then
			return
		end
		self.PlayerKilled:Fire(entity.Player)
	end)
end

function CombatService.TryHit(attacker: Player, victim: Model)
	local character = attacker.Character
	if not character or Stunned:IsTagged(character) then
		return
	end
	HitCooldown:Call(attacker, function()
		Stunned:Add(victim, 0.5)
	end)
end

return CombatService
```
