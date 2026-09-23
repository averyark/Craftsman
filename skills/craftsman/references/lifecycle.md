# Lifecycle, Config & Cleanup: Component, Config, Keeper

## Component loader

`Craftsman.Component:LoadModulesAsync(folder) -> Promise<{ [name]: module }>` boots every singleton in the folder. Call it with **`:`**.

### What the loader does

1. **Require.** It requires every `ModuleScript` descendant of `folder`, skipping names that end in `.spec`. Each module is keyed by its `ModuleScript.Name`. A require error rejects the whole load.
2. **Init.** It calls `Module:Init()` on every table module, and **every Init finishes before any Start begins**.
   - An Init that errors is `warn`ed.
   - That module's `Start` is skipped, and so is the `Start` of every module that depends on it.
   - A yielding Init holds up the whole boot. Keep Init synchronous.
3. **Keeper.** It injects a Keeper as `Module.Keeper`. If the module already has one, that Keeper is kept.
4. **Dependency graph.** It builds the graph from `Module.Dependencies = { OtherModuleTable, ... }`.
   - Entries are **module tables** (the value the dependency's `require` returned), not names.
   - Entries that aren't loaded modules, and self-references, are ignored with a warning.
   - A cycle rejects the load with `Cyclic module dependency: A -> B -> A`.
5. **Start.** It calls `Module:Start()` after all of that module's dependencies' `Start`s have **finished**.
   - Modules that don't depend on each other start concurrently.
   - `Start` may yield, but yielding delays its dependents.

The promise resolves once every Start has settled. After that, `Component.IsLoaded` is `true` and `Component.LoadedModules[name]` holds each module.

### Shutdown

`Craftsman.Component:StopModulesAsync()` calls `Module:Stop()` in reverse dependency order, meaning dependents stop first. It destroys each module's Keeper *after* that module's `Stop` returns.

### Other members

`Component.new(tbl)` sets a metatable and adds a `Keeper` to a plain table. You rarely need it.

`Config.MODULE_LOAD_ORDER` is deprecated. Use `Dependencies` instead.

### Singleton shape

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Craftsman = require(ReplicatedStorage.Packages.Craftsman)
local CombatService = require(script.Parent.CombatService)

local RoundService = {
	Dependencies = { CombatService },
}

local Round = nil

function RoundService:Init()
	Round = { Number = 0 }
end

function RoundService:Start()
	self.Keeper:Connect(CombatService.PlayerKilled, function(killer, victim)
		-- ...
	end)
end

function RoundService:Stop()
	-- optional; self.Keeper is destroyed right after this returns
end

return RoundService
```

### Rules

- **Put state and signals in `Init`, connections and loops in `Start`.** Another module's `Start` may read your module's fields, and every Init runs before any Start, so those fields already exist.
- **Only singletons go in the loaded folder.** Helpers, classes and shared data belong somewhere else. The loader requires everything it finds and calls `Init`/`Start` on anything that has them.
- **A game module only requires another game module when it lists it in `Dependencies`.** Otherwise, talk through a `Signal` that the owning module exposes.

## Bootstrap (one server Script, one client LocalScript)

Order matters:

1. Configure (automatic when you use the `CraftsmanConfig` ModuleScript described below).
2. Start the state machine server/client.
3. Load the modules.
4. Wrap characters in entities.

```lua
-- ServerScriptService/Bootstrap.server.luau
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Craftsman = require(ReplicatedStorage.Packages.Craftsman)

Craftsman.StateMachineServer:Start()

Craftsman.Component:LoadModulesAsync(ServerScriptService.Services):await()

local function track(player: Player)
	player.CharacterAdded:Connect(function(character)
		Craftsman.Entity.new(character, player)
	end)
	if player.Character then
		Craftsman.Entity.new(player.Character, player)
	end
end

Players.PlayerAdded:Connect(track)
for _, player in Players:GetPlayers() do
	track(player)
end
```

```lua
-- StarterPlayerScripts/Bootstrap.client.luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Craftsman = require(ReplicatedStorage.Packages.Craftsman)

Craftsman.StateMachineClient:Start()

Craftsman.Component:LoadModulesAsync(ReplicatedStorage.Controllers):await()
```

The StateMachine hosts **must** be started explicitly. The `AUTO_START_*` settings only permit starting; they don't start anything themselves.

Skip whichever pieces the game doesn't use.

## Config

The preferred way to configure Craftsman is a ModuleScript named **`CraftsmanConfig` directly under `ReplicatedStorage`**. It returns a partial table, and Craftsman applies it automatically the first time Config is required.

The alternative is `Craftsman.Config.Configure(edit)`, called with `.`. It merges `edit` over a **baseline**: the built-in defaults with `CraftsmanConfig` applied on top. It does not merge over the current values, so each call replaces the previous `Configure` call:
- Any key you leave out goes back to its baseline value, and a key that has no default is removed.
- Values from `CraftsmanConfig` are never lost.
- Arrays are replaced whole.

Call it before using any other module, because a few settings are only read once.

```lua
-- ReplicatedStorage/CraftsmanConfig
return {
	INTERFACE = { REFERENCE = Vector2.new(1920, 1080), MODE = "Fit", TEN_FOOT_BOOST = 1.5 },
	TOUCH = { AUTO_SCALE = true, EDIT_GRID = 8 },
	STATE_MACHINE = { CLIENT_UPDATE_MIN_INTERVAL = 0.1 },
}
```

### Sections

- **`STATE_MACHINE`**
  - `ENABLED`: default `true`
  - `AUTO_START_SERVER`: default `true`
  - `AUTO_START_CLIENT`: default `true`
  - `SYNC_CLIENT`: default `true`
  - `CLIENT_UPDATE_MIN_INTERVAL`: default `0.05`. It is read when the module loads, so set it before the StateMachine module is first required.
  - See `state.md` for what each key does.
- **`INTERFACE`**
  - `REFERENCE`: default `1920×1080`
  - `MODE`: default `"Fit"`
  - `MIN_SCALE`: default `0.5`
  - `MAX_SCALE`: default `2`
  - `DAMPING`: default `1`
  - `TEN_FOOT_BOOST`: default `1.25`
- **`TOUCH`** holds the look and behaviour of touch buttons:
  - `DEFAULT_ASSET` and the sprite-rect keys
  - label and overlay styling
  - `BASE_SIZE`, `DEFAULT_SIZE` (both `70`), `MIN_SIZE` (`40`), `MAX_SIZE` (`160`), `MATCH_JUMP_SIZE` (`true`)
  - `ZONE_PADDING` (`8`), `ZONE_MARGIN` (`16`)
  - `DISPLAY_ORDER` (`-1`), `AUTO_SCALE` (`false`). Both are read once, when the first button is created.
  - `EDIT_GRID` (`0`), `DRAG_THRESHOLD` (`6`) and the edit-handle styling
  - `JUMP_BUTTON_EDITABLE` (`true`)
  - `LAYOUT_VERSION` (`2`). Bump it to invalidate saved layouts.

## Keeper (cleanup)

Every loaded singleton, `Entity` and `Pathfind` owns a Keeper. Route every connection, instance, thread and promise through the Keeper of the object that owns it. That ties the lifetime of everything it creates to the owner.

| Call | Use |
|---|---|
| `Keeper.new()` | Create a Keeper for your own classes. |
| `keeper:Add(obj, key?, cleanup_method?)` | Track anything: an Instance, a connection, a function, a thread, a promise, or an object with `Destroy`/`Disconnect`. Returns `obj`. |
| `keeper:Connect(signal, fn, key?)` | Same as `Add(signal:Connect(fn))`. Works for RBXScriptSignal and Signal. |
| `keeper:Once(signal, fn, key?)` | One-shot connection. |
| `keeper:Construct(class_or_fn, key?, ...args)` | Same as `Add(class.new(...))`. **The key is the second argument.** |
| `keeper:Clone(instance, key?)` | Clones the instance and tracks the clone. |
| `keeper:AddPromise(promise, key?)` | Cancels the promise on cleanup. |
| `keeper:BindToRenderStep(name, priority, fn, key?)` | Unbinds on cleanup. |
| `keeper:Extend(key?)` | Creates a child Keeper that is cleaned along with this one. |
| `keeper:Remove(obj, key?)` | Removes and cleans one object. |
| `keeper:Pop(obj)` | Stops tracking an object without cleaning it. |
| `keeper:Clean()` | Cleans everything. The Keeper stays usable. |
| `keeper:WrapClean()` | Returns a function that calls `Clean`. |
| `keeper:AttachToInstance(inst)` | Destroys the Keeper when `inst` leaves the game. `inst` must already be in the DataModel. |
| `keeper:Destroy()` | Cleans everything and ends the Keeper. |

**Class constructor pattern:** create the Keeper, then call `AttachToInstance` on it immediately, then add everything through it.

```lua
function Turret.new(model: Model)
	local self = setmetatable({}, Turret)
	self.Keeper = Keeper.new()
	self.Keeper:AttachToInstance(model)
	self.Fired = self.Keeper:Add(Signal.new())
	self.Keeper:Connect(RunService.Heartbeat, function(dt)
		self:Step(dt)
	end)
	return self
end
```

`Keeper:Add` errors if it's called while that Keeper is being cleaned up.

## Signal & Promise

- **`Signal`** is sleitnick's Signal, used for decoupled events.
  - Expose signals as fields on the module that owns them, and create them in `Init` or the constructor.
  - Listeners connect in `Start`.
  - Every Craftsman event (`Entity.Died`, `InputUtil.Began`, `Queue.Succeeded`, …) is a Signal: use `:Connect`, `:Once` and `:Wait` on it.
- **`Promise`** is typed-promise (evaera API): `Promise.new`, `.try`, `.all`, `:andThen`, `:catch`, `:await` and `:expect`.
  - `LoadModulesAsync`, `Queue:Enqueue`, `Queue:Drain` and `Pathfind:ComputePathToAsync` all return promises.
  - Always `:catch` a rejection you don't propagate, or Promise warns about it.
