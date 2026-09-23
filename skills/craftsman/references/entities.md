# Entities, Tags & Pathfinding: Entity, Tag, Pathfind

## Entity

`Entity` wraps a character `Model` with cached rig references, a `Keeper` and lifecycle signals. Each machine keeps its own registry, so server and client wrappers are independent.

**Construction**

- **`Entity.new(model, player?) -> Entity`**
  - Returns the existing wrapper if the model already has one.
  - Otherwise it **yields** up to 5s each for `Humanoid` and `HumanoidRootPart`, and errors if either is missing.
  - Fires `Entity.Spawned`.
- **`Entity.Get(model) -> Entity`**
  - Looks up the wrapper, and creates it when it's missing.
  - It yields and errors exactly like `new`, and never returns nil.
- **`Entity.Entities[model]`** is a lookup that never creates.
- **Nothing creates entities automatically.** Wrap characters yourself on `CharacterAdded`, as in the bootstrap in `lifecycle.md`, and wrap NPCs when they spawn.

**Fields**

- `Instance`
- `Player?`
- `Humanoid`
- `HumanoidRootPart`
- `Keeper`

**Methods** (called with `:`)

- `GetHumanoid()` and `GetRoot()` never yield, and they read the rig as it is now.
- `Destroy()` fires `Removing` and destroys the model.

**Signals**

The signals are **module-level**: connect to `Entity.Died`, not `entity.Died`. Each one passes the `Entity`.

- `Entity.Spawned` fires when an entity is created.
- `Entity.Died` fires on `Humanoid.Died`, **or** when the model leaves the DataModel (respawn, `LoadCharacter`, destroy).
- `Entity.Removing` fires only from `entity:Destroy()`.

**Cleanup and rules**

- When an entity dies, `entity.Keeper` is destroyed and the entity is removed from the registry. Attach per-character connections, VFX and state to `entity.Keeper`.
- After death the model may still exist. Calling `Entity.Get` on it builds a *new* wrapper, and that wrapper's `Died` never fires. Check `Entity.Entities[model]` before calling `Get` on bodies that might be dead.

```lua
Craftsman.Entity.Spawned:Connect(function(entity)
	entity.Keeper:Connect(entity.Humanoid.HealthChanged, function(health)
		-- ...
	end)
end)

Craftsman.Entity.Died:Connect(function(entity)
	if entity.Player then
		-- award kill, respawn timer, ...
	end
end)
```

## Tag

`Tag` stores tags as child `NumberValue`s named `__TAG_<Identifier>`.

- Tags created on the server replicate to clients.
- Tags stack, can be timed, and can carry attributes.
- **Use `Tag`, not CollectionService.**

**Registration**

- `Tag.Get(identifier)` is idempotent, so it is the one to use. `Tag.new` errors if the tag already exists.
- **Register every tag on both server and client.** Name-based lookups only see tags registered on the current machine.

**Module functions** (called with `.`)

- `Tag.HasTags(instance, "A" | TagObj | { ... })` returns true if **any** of the tags is present.
- `Tag.GetTags(instance)` returns every registered tag present on the instance.
- `Tag.GetRegistered()` returns every registered tag.
- `Tag.Is(value)` checks whether a value is a Tag object.

**Methods** (called with `:`)

`interval = nil` makes a toggle tag that lasts until removed. A positive `interval` makes a timed tag that is removed after that many seconds.

| Call | Returns | Behaviour |
|---|---|---|
| `Add(inst, interval?, attributes?, overwrite_id?)` | `(id, NumberValue)` | Adds another instance of the tag, so tags stack. |
| `AddTag(inst, ...)` | `NumberValue` | Same as `Add`, but returns only the value object. |
| `SetTag(inst, interval?, attributes?)` / `ReplaceTag(...)` | `NumberValue` | Removes this tag's existing instances, then adds one. |
| `RemoveOthersAndAdd(inst, interval?, attributes?)` | `(id, NumberValue)` | Same as `SetTag`, but returns the id as well. |
| `Remove(inst?, id)` | `boolean` | Removes one tag instance. |
| `RemoveAll(inst, filter?)` | – | Removes all of them, optionally filtered. **Only affects tags created on this machine.** |
| `IsTagged(inst, only_local?)` | `boolean` | By default it sees replicated tags too. |
| `GetTags(inst)` | `{ NumberValue }` | Includes replicated tags. |
| `GetDuration(inst)` | `number` | Sum of the time remaining on all timed tags. Wrong on clients for server-created tags. |
| `GetToggleTags(inst)` | `number` | Number of toggle (untimed) tags. |
| `ListenToInstance(inst, cb(is_tagged))` | `TagConnection` | Calls `cb` **immediately** with the current state, then on every change. Works on clients. Cleans itself up when the instance is removed. |
| `ListenToInstanceTags(inst, cb(value, added))` | `TagConnection` | Calls `cb` immediately for each existing tag, then on every add or remove. |
| `WhenTagRemoved(id, cb)` | `Connection` | Fires when that tag id is removed. Not filtered by instance, and does not disconnect itself. |
| `Destroy()` | – | Unregisters the tag and removes this machine's instances of it. |

**Tag signals**

These fire only for adds and removes that go through this machine's API.

- `OnTagged(inst, id, interval?)`
- `OnTagRemoved(inst, id)`
- `OnInstanceTagged(inst, is_tagged)`

**Attributes and ids**

- Attributes are set on the `NumberValue`. Read them with `value:GetAttribute(name)`.
- `TagIdentifier`, `TagId` and `TagExpiresAt` are reserved.
- Tag ids are global per tag. Reusing a custom `overwrite_id` on another instance removes the first instance's tag.

**Server vs client**

- Clients cannot remove server tags.
- Mutate tags on the server. On the client, only read them or listen to them.

```lua
local Stunned = Craftsman.Tag.Get("Stunned")

-- server
Stunned:Add(character, 1.5, { Source = "Slam" })

if Craftsman.Tag.HasTags(character, { "Stunned", "Ragdolled" }) then
	return
end

-- client
entity.Keeper:Add(Stunned:ListenToInstance(character, function(is_stunned)
	set_stun_vfx(is_stunned)
end))
```

## Pathfind

Drives an NPC along `PathfindingService` paths. It handles throttled re-pathing, stuck recovery, blocked paths, jump waypoints and chasing a moving target, and can draw its path for debugging.

`Pathfind.new({ Entity, Humanoid?, Mover?, Config? })`

- `Entity` must already be in the DataModel, because the pathfinder's Keeper is attached to it.
- Pass a `Humanoid`, or a custom `Mover: (Vector3) -> ()`. The default mover is `Pathfind.Movers.Humanoid(humanoid)`.
- On the server it takes network ownership of the NPC's parts, so **never use it on player characters**.

`Config` is a partial override. Unknown keys are dropped, and a table value replaces the default table instead of merging into it. Defaults:

| Key | Default |
|---|---|
| `RECALCULATE_THROTTLE` | `0.2` |
| `RECALCULATE_DISTANCE_THRESHOLD` | `4` |
| `IDLE_RECALCULATE_INTERVAL` | `1` |
| `AGENT_RADIUS` | `2` |
| `AGENT_HEIGHT` | `5` |
| `AGENT_CAN_JUMP` | `true` |
| `AGENT_COSTS` | `{}` |
| `WAYPOINT_SPACING` | `4` |
| `WAYPOINT_ARRIVAL_RADIUS` | `1.5` |
| `WAYPOINT_ADVANCE_RADIUS` | `2.8` |
| `STUCK_TIMEOUT` | `2` |
| `STUCK_RETRIES` | `2` |
| `STALL_TIMEOUT` | `2` |
| `PARTIAL_PATH` | `true` |
| `VISUALISE` | `false` |

`VISUALISE` is read only at construction. It draws a billboard, waypoint balls and lines.

### Methods (colon)

| Call | Behaviour |
|---|---|
| `Goto(position)` | Computes a path (throttled) and walks it. Cancels any chase. |
| `Chase(target: BasePart \| Model, stopping_distance?)` | Re-paths while the target moves, and re-paths periodically while idle. Inside `stopping_distance` it halts and fires `OnArrived`. It calls `Stop` on its own when the target is removed or its Humanoid dies. Calling `Chase` again replaces the previous chase. |
| `Stop()` | Cancels the chase, clears the path, moves the NPC to where it stands and fires `OnPathEnded`. |
| `Destroy()` | Cleans everything up. It does **not** call `Stop`, so call `Stop()` first if the NPC should halt. |
| `ComputePathToAsync(position)` | Returns `Promise<{ Status, Waypoints }>`. It uses the shared internal `Path`, so don't call it while `Goto` or `Chase` is active. |
| `GetRoot()` | The NPC's root part. |
| `GetCurrentPosition()` | The NPC's current position. |

### Signals

| Signal | Fires when |
|---|---|
| `OnPathCalculated(waypoints)` | A path computes successfully. |
| `OnPathEnded()` | Movement ends for any reason: arrival, `Stop`, or giving up when stuck. |
| `OnArrived()` | The target is reached, or the NPC enters the chase stopping distance. |
| `OnStuck()` | Recovery fails more than `STUCK_RETRIES` times. The NPC halts. |
| `OnPathFailed(reason)` | No usable path was found. `reason` is `"Unreachable"`, a `PathStatus` name, or the error from `ComputeAsync`. |

Useful fields: `IsMoving`, `Waypoints`, `CurrentWaypointIndex`, `TargetPosition`, `ChaseTarget`, `Keeper`.

```lua
local humanoid = npc:FindFirstChildOfClass("Humanoid")
local pathfind = Craftsman.Pathfind.new({ Entity = npc, Humanoid = humanoid, Config = { AGENT_RADIUS = 2.5 } })

pathfind.OnArrived:Connect(function()
	attack(target_character)
end)

pathfind.OnPathFailed:Connect(function(reason)
	warn(`{npc.Name} cannot reach target: {reason}`)
end)

pathfind:Chase(target_character, 6)

-- later
pathfind:Stop()
pathfind:Destroy()
```
