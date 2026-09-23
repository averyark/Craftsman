# StateMachine

This is a hierarchical state machine (HSM) with optional server→client replication.

### States

`Craftsman.State.new(name, { Enter = fn(state, ctx), Exit = fn(state, ctx), Update = fn(state, dt, ctx) }?)`

- Handlers **don't receive the machine**. Pass anything they need, such as the entity or the machine, in `context`.
- Don't rename a state after it has been added to a machine.

### Machine

`Craftsman.Machine.new(id?, is_client_authoritative?)`. An `id` is required for replication.

**Signals**

| Signal | Arguments |
|---|---|
| `Transitioned` | `(machine, from, to, context, source)` |
| `Destroyed` | `(machine)` |

**Methods (call with `:`)**

| Method | Behaviour |
|---|---|
| `AddState(state, parent?)` | Registers by name. The parent is not registered automatically; add it first. |
| `GetState(name)`, `GetCurrent()`, `IsRunning()` | Lookups. |
| `SetInitial(state)` | Sets the state that `Start` enters. |
| `Start(context?)` | Enters from the root down to the initial state. |
| `Stop(context?)` | Exits from the current leaf up to the root. |
| `Transition(target, context?)` | Exits up to the lowest common ancestor, then enters down to `target`. Returns `false` if `target` is already current. When called from inside Enter or Exit, the transition is queued and the call returns `true`. |
| `Update(dt, context?)` | Runs Update handlers from the root to the current state. **Nothing calls this for you:** drive it from Heartbeat. It does nothing unless the machine is running. |
| `Destroy()` | Fires `Destroyed`, clears the machine and unregisters replication. |
| `Replicate(targets?)`, `Unreplicate()` | Same as `StateMachine.Register(machine, targets?)` and `StateMachine.Unregister(machine)`. |
| `SetReplicationTargets(targets?)` | Server only. |
| `SyncReplication(targets?)` | Re-sends the current state (server) or re-requests it (client). |

- Don't call `Transition` before `Start`. It changes the current state without starting the machine, and a later `Start` into that same state then fails.

### Replication

1. Start the hosts in the bootstrap: `StateMachineServer:Start()` and `StateMachineClient:Start()`.
2. Build the machine with the **same `id` and the same state names** on both sides. Put the builder in a shared module.
3. Call `machine:Replicate(targets?)` on both sides. `targets = nil` means all players.
4. The client mirror runs its own Enter/Exit handlers and receives the server's transition `context`. Initial syncs arrive with a `nil` context.
5. Registration keeps the machine alive until you call `machine:Unreplicate()` or `machine:Destroy()`. Do one of those when the owner goes away, for example from the player's or entity's Keeper, or the machine leaks.

On the client, the `source` argument of a server-driven `Transitioned` is an internal sentinel: it is neither `nil` nor a `Player`.

**Client-authoritative mode**
- Mark the machine as client-authoritative on **both** sides, before calling `Replicate`.
- The server accepts a client's transitions only when all of these hold:
  - The player is in the targets, or `targets` is nil (then any player can drive the machine).
  - `context` is `nil` or a table.
  - The update respects `CLIENT_UPDATE_MIN_INTERVAL`. Faster updates are dropped, not queued.
- The server only checks that the named state exists. Validate game rules yourself.

**Config (`STATE_MACHINE`)**

| Key | Effect when `false` |
|---|---|
| `ENABLED` | Disables everything. |
| `AUTO_START_SERVER` | Makes `StateMachineServer:Start()` a no-op. |
| `AUTO_START_CLIENT` | Makes `StateMachineClient:Start()` a no-op. |
| `SYNC_CLIENT` | The server sends nothing to clients. |

```lua
-- ReplicatedStorage/Shared/CombatMachine.luau
local Craftsman = require(game:GetService("ReplicatedStorage").Packages.Craftsman)

return function(player: Player)
	local machine = Craftsman.Machine.new(`Combat:{player.UserId}`)
	local alive = Craftsman.State.new("Alive")
	local idle = Craftsman.State.new("Idle")
	local attacking = Craftsman.State.new("Attacking", {
		Enter = function(_state, context)
			-- context.Combo
		end,
	})
	machine:AddState(alive)
	machine:AddState(idle, alive)
	machine:AddState(attacking, alive)
	machine:SetInitial(idle)
	return machine
end
```

```lua
-- server
local machine = build_combat_machine(player)
Machines[player] = machine
machine:Start()
machine:Replicate()
machine:Transition(machine:GetState("Attacking"), { Combo = 1 })

-- client
local machine = build_combat_machine(player)
Machines[player] = machine
machine:Replicate()
self.Keeper:Connect(RunService.Heartbeat, function(dt)
	machine:Update(dt)
end)
```
