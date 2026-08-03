# Changelog

Notable changes to Craftsman. Craftsman is pre-1.0, so a breaking change bumps the **minor**
version, as `0.7.0` did.

---

## 0.8.0 — unreleased

Craftsman no longer requires its consumer, modules declare their own load order, the barrel
stopped executing subsystems nobody asked for, and the lifecycle gained a `Stop`.

Most of this is invisible at the call site. Two things are not: `Start` timing changed, and a
rig with no `Humanoid` now errors instead of hanging. Read the two **Breaking** notes before
upgrading; nothing else should need an edit.

### Breaking — `Start` no longer runs one module at a time

**What changed.** The module loader used to `:await()` each module's `Start` inside its loop, so
every module's `Start` ran to completion before the next one began, in `GetDescendants()` order.
Now a module's `Start` waits only on the modules it *declares* it depends on. Independent modules
start concurrently.

**Who this breaks.** Any module that relied on another module's `Start` having finished, without
declaring it. That ordering used to hold by accident, for every pair of modules, because everything
was serial. Now it holds only where you say so — and where you don't, the two modules race.

Nothing warns about this, because the loader cannot tell an accidental dependency from an
unrelated module. If a module reads state that another module's `Start` populates, declare it:

```lua
local Replication = require(script.Parent.Replication)

local SessionManager = { Dependencies = { Replication } }

function SessionManager.Start()
	-- Replication.Start has finished by the time this runs.
end
```

**Why it changed.** Serial `Start` meant one yielding module stalled the entire boot, and the order
it stalled in was whatever `GetDescendants()` happened to return.

### Added — modules declare their dependencies in place

`Dependencies` holds the **required module tables themselves**, not their names:

```lua
local SessionManager = { Dependencies = { Replication, Casting } }
```

The loader maps each entry back to its module by table identity, which is why this is typed,
greppable, and survives a rename — a string name would be none of those.

**How it works.** Loading is now three phases. Every module is required and `Init`ed in parallel, as
before. Then the `Dependencies` arrays are resolved into a graph. Then each module's `Start` is run
as `Promise.all(its dependencies' starts):andThen(start it)` — so a module with no dependencies
starts immediately, and the concurrency falls out of the graph without an explicit topological sort.

**Failures no longer cascade silently.** If a module's `Init` or `Start` throws, its dependents are
skipped rather than started against a half-constructed module, and each skipped module names the
*root* failure rather than reporting its own opaque error:

```
Error in Init of module Replication: attempt to index nil value
Skipped Start of module SessionManager: dependency Replication failed
```

A dependency **cycle** rejects the load with the full path (`A -> B -> A`) instead of deadlocking.

### Deprecated — `Config.MODULE_LOAD_ORDER`

Still honoured, still works. It is translated into a chain of edges between the modules it names,
and warns once per load. It is deprecated because it expressed ordering as a flat array of leaf module
names in config, far away from the modules it ordered: not typed, not greppable, and silently wrong
after a rename.

Migrate by deleting the array and declaring `Dependencies` on the modules themselves.

> **Note:** `MODULE_LOAD_ORDER` preserved the relative order of the modules it *named*. It never
> expressed the accidental ordering between modules it didn't name — that came from the serial
> `:await()`, which is gone. See the breaking note above.

### Changed — requiring Craftsman no longer executes every subsystem

**Nothing changes for callers.** `Craftsman.PrintUtil`, `Craftsman.Entity`, and every other export
work exactly as before, with the same types. There are no new import paths to write.

**What changed.** `init.luau` used to require all 30 exports at module scope. Because Luau modules
run their top level on require, `Craftsman.PrintUtil:Warn` in one leaf module also *executed* the
market and state-machine stacks — including the `ByteNet.defineNamespace` calls that sit at module
scope in `Store/Network.luau` and `StateMachine/Network.luau`. No configuration avoided this:
`AUTO_START_SERVER` is checked inside `Server:Start()`, which runs long after the require.

Now each export resolves on first access and is memoised. Touch `Craftsman.PrintUtil` and you
execute `PrintUtil` — nothing else.

**How it works.** The export surface is declared as a type and resolved through a metatable:

```lua
export type Craftsman = {
	PrintUtil: typeof(require("@self/Utilities/PrintUtil")),   -- type only; never executed
}

local loaders = {
	PrintUtil = function() return require("@self/Utilities/PrintUtil") end,
}

return (setmetatable({}, {
	__index = function(self, key)
		local module = loaders[key]()
		rawset(self, key, module)   -- memoise; later reads never hit __index again
		return module
	end,
}) :: any) :: Craftsman
```

The trick is that `typeof(require(...))` is a **type-only** expression. Luau erases it, so the type
surface is complete and permanent while costing nothing at runtime. The real requires live in
closures that only run when `__index` calls them.

This does not reduce your place file's size — Roblox has no tree-shaking, and every ModuleScript
still ships. What it removes is the *execution*.

**Unchanged behaviour:** server-only exports (`DataServer`, `MarketServer`, `StateMachineServer`,
`StoreServer`) still resolve to `nil` on the client rather than erroring, exactly as before.
Subsystems are not yet opt-in, and nothing errors on access — that needs an explicit `Configure`
entry point, which does not exist yet.

**A caveat if you fork or extend the barrel.** An export must be added to *both* the type and
`loaders`, with the same path. Nothing enforces that: the type is erased, so no runtime check can
enumerate it, and the `:: any :: Craftsman` cast is unchecked. A type field with no loader fails
only when something first touches it.

### Changed — Craftsman no longer requires your config module

**Nothing changes for existing games.** If you define `ReplicatedStorage.CraftsmanConfig`, it is
still picked up automatically, and `Data`/`Market` keep the exact `PlayerState` your schema
describes. No edit needed.

**What changed.** `Config.luau` used to `require(ReplicatedStorage.CraftsmanConfig)` at module
scope, so the library depended on its consumer: Craftsman could not load at all in a place that
did not define that exact module at that exact path. No defaults, no minimal consumer, no headless
test — which is why the `PlayerState` bug below shipped and went unnoticed.

That require was doing two unrelated jobs, and only one of them was a runtime job:

- **The type** — `PlayerState` reads your GreenTea schema. It still does. It is now inlined into
  the type position, and `typeof(...)` is erased, so it names your module without executing a
  require and cannot stop Craftsman loading. Your types are unchanged.
- **The value** — the config merge. That is now optional: applied when the module exists, defaults
  when it does not.

**Added `Config.Configure(edit)`** for configuring explicitly rather than by module placement:

```lua
Craftsman.Config.Configure({ DATA = { STORE_NAME = "MyGame" } })
```

It merges in place, so modules holding `Config.DATA` see the change, and merges from the pristine
defaults, so calling it twice replaces rather than compounds — an omitted field returns to its
default instead of keeping the earlier call's value.

One limit: a field with **no default** — `DATA.SCHEMA` is the only one — can be overwritten but not
*cleared* by a later call. There is nothing to reset it to, and dropping keys absent from the merge
would take `Configure` itself with them.

> **`DATA.SCHEMA` is the supported way to type player data.** It is what gives `Data` and `Market`
> a real `PlayerState` instead of `any`. Without it, `PlayerState` degrades silently. It is not yet
> enforced.

### Added — a `Stop` phase and a Keeper per module

The lifecycle was one-way. `Component` owned nothing, so anything that ends — sessions closing,
encounters, arena reuse — was each feature's own cleanup to remember.

Every loaded module now gets a `Keeper` scoped to its lifetime:

```lua
function SessionManager.Start()
	SessionManager.Keeper:Add(connection)   -- cleaned up automatically on Stop
end

function SessionManager.Stop() end
```

`Component:StopModulesAsync()` is the mirror of the start phase: a module stops **before** the
modules it depends on — the dependency graph walked backwards — so nothing is torn down while a
live dependent still needs it. Independent modules stop concurrently. Each module's `Keeper` is
destroyed after its own `Stop` returns, so `Stop` can still use what it holds.

Unlike `Start`, a failing `Stop` is warned and swallowed rather than poisoning dependents: a
teardown must not strand the modules that have not been torn down yet.

### Fixed — `PrintUtil:Error(msg, level)` honours `level`

It previously concatenated every argument into the message and called `error()` with no level, so
the level was printed into the output and the error blamed `PrintUtil.luau` instead of the code at
fault. Craftsman was its own victim: 11 call sites in `AnimationUtil` and `SoundUtil` already
passed `2`.

`level` now means what it means for `error`, counted from the call site: `1` (default) blames the
caller of `Error`, `2` blames that function's caller, `0` omits position.

### Added — `InterfaceUtil`, resolution-independent UI scaling

Drives a `UIScale` from the viewport so a layout authored at one reference resolution survives
phones, desktops and consoles.

```lua
self.Keeper:Add(Craftsman.InterfaceUtil:AutoScale(screenGui))
```

`AutoScale` returns a cleanup function, rebinds when `workspace.CurrentCamera` is replaced (a plain
`ViewportSize` connection silently stops updating when it is), and is idempotent — calling it twice
on one target replaces the binding rather than stacking a second `UIScale`. Client-only; it errors
on the server.

`InterfaceUtil.ComputeScale(viewport, options)` is the same maths as a pure function, if you want
the number without the binding.

Configured under `Config.INTERFACE` — `REFERENCE`, `MODE`, `MIN_SCALE`, `MAX_SCALE`, `DAMPING`,
`TEN_FOOT_BOOST` — and overridable per call.

`MODE` picks the policy: `Fit` never overflows either axis, `Height` follows vertical space alone,
`Width` horizontal, `Diagonal` degrades most evenly across unusual aspect ratios.

`DAMPING` below 1 lifts small screens — a phone at a third of the reference height scales to 0.46
rather than 0.33, which keeps touch targets reachable. It defaults to `1` (off), so the first
version changes nothing implicitly; tune it against real devices.

There is deliberately **no** scrolling-frame auto-size: `AutomaticCanvasSize` is native and already
does it.

### Added — `TouchUtil`, on-screen buttons for mobile

A touch button is a *source* for an `InputUtil` action, not an input system of its own. The same
handler serves keyboard, gamepad and thumb, so gameplay code never branches on device:

```lua
InputUtil.SetPrimitiveBinding("Dash", { Enum.KeyCode.Q })

self.Keeper:Add(Craftsman.TouchUtil.Button("Dash", {
	Text = "Dash",
	Zone = "BottomRight",
	VisibleWhen = { Combat = true },
}))

Craftsman.TouchUtil.SetContext("Combat", true)
```

Buttons are hidden until the player is actually on touch, so calling this unconditionally is the
intended usage. The gate reads `InputStore.DeviceType` — the *last used* device — rather than
`UserInputService.TouchEnabled`, which would put phone buttons on a laptop with a touchscreen while
its owner is typing. Override per button with `ShowOn`.

`Zone` lays out into one of nine named slots (`TopLeft` … `BottomRight`) with a `UIListLayout`, so
adding a button does not mean re-picking coordinates; `Position` remains as an escape hatch. The
whole layer is scaled by `InterfaceUtil:AutoScale`, and its `ScreenGui` is created on the first
`Button` call — requiring `TouchUtil` has no side effect.

`VisibleWhen` gates on named contexts. Contexts are indexed in reverse, so flipping one touches
only the buttons that named it.

Each button owns a `Keeper`. `button:Destroy()` releases the action first, so a button destroyed
mid-press cannot leave its action stuck active.

Configured under `Config.TOUCH` — asset, sprite-sheet rects, label colours and size, default button
size, zone padding and margin, display order, disabled transparency, `AUTO_SCALE`.

Also on `TouchButton`: `SetIcon`, `SetText`, `SetSize`, `SetZone`, `SetPosition`, `SetVisibleWhen`,
`SetShowOn`, `SetEnabled`, `SetVisible`, `IsPressed`. Module-level: `SetContext`, `SetContexts`,
`GetContext`, `GetButtons`, `SetEnabled`, `GetRoot`, `Destroy`, `ContextChanged`.

### Added — `TouchUtil.AdoptJumpButton()` makes Roblox's jump button editable

`BottomRight` is the obvious place for ability buttons and also exactly where Roblox puts the jump
button, so the default layout overlapped it on every phone.

Two earlier attempts were the wrong shape. The first reserved space by measuring the CoreGui
button and lifting the zone clear of it — two layout systems negotiating over one corner. The
second cloned the button, hid the original and re-implemented jumping, which meant owning
behaviour that already worked.

The button is now **adopted**: used where it is, not cloned and not hidden. It keeps its art and
it keeps jumping, because the control scripts still own it. The only thing Craftsman adds is edit
mode.

```lua
TouchUtil.AdoptJumpButton()
```

It gains an outline and a resize handle while editing, moves and resizes with the rest of the pad,
and serializes into the saved layout under `LayoutId` "Jump". Returns nil where there is no CoreGui
jump button to adopt — desktop, or a game that already disabled the default controls.

**Editing happens on a proxy.** Edit mode disables the default control module, and that takes the
whole `TouchGui` with it — so the real jump button is not on screen to be dragged, which is why an
earlier version of this looked like the jump button simply could not be moved. Entering edit mode
now clones the button into Craftsman's layer and edits the clone: it cannot trigger a jump, and
nothing else can switch it off mid-drag. On exit the clone's final rect is handed back to the real
button and the clone is discarded.

The clone's rect is carried across as a **screen-pixel centre**, not a scale position. The proxy
lives in Craftsman's ScreenGui and the real button in CoreGui's `TouchControlFrame`, and the two
have different insets, so copying a scale position straight across would land in the wrong place.

Re-enabling the controls can replace the button instance outright, which would silently discard
the player's layout, so the stored position and size are re-applied after edit mode ends and again
whenever the CoreGui controls are rebuilt — a respawn included.

**It stays in `TouchGui`.** Dragging an adopted button positions it inside whatever already owns
it -- the CoreGui `TouchControlFrame` -- rather than reparenting it into Craftsman's ScreenGui,
which would move it out from under the control scripts and take its behaviour with it. Every
measurement in the drag path is taken against that container for the same reason.

**Toggling it.** `Config.TOUCH.JUMP_BUTTON_EDITABLE` (default true) sets the starting state, and
`TouchUtil.SetJumpButtonEditable(enabled)` changes it at runtime. Disabling stops the button moving
or resizing but leaves it adopted, so a layout the player already saved survives a temporary
toggle. `TouchUtil.GetJumpButton()` returns the adopted button if there is one. The button keeps
jumping either way.

`TouchUtil.Adopt(instance, options?)` does the same for any `GuiObject`, so a game's existing HUD
buttons can join the layout editor without being rebuilt. Adopted instances are never reparented,
never cloned, never hidden, and never drive an `InputUtil` action — whatever already drives them
keeps driving them.

### Changed — edit mode disables the default controls

Dragging the real jump button would otherwise jump, and dragging anything would otherwise pan the
camera. Edit mode now calls `PlayerModule:GetControls():Disable()` for its duration and re-enables
on exit. This is also what a player expects: the character holds still while its controls are
rearranged.

### Breaking — `LayoutEntry.Size` became `LayoutEntry.Scale`

Saved layouts store a multiplier over the button's own base size rather than a pixel size.
Craftsman's buttons are authored against `BASE_SIZE`; an adopted CoreGui button's base is whatever
Roblox rendered it at, which differs per device. A multiplier means the same thing for both.

`LAYOUT_VERSION` is now `2`, so layouts saved against version 1 are rejected with a warning rather
than misread. Version 1 was never released.

### Changed — a zone is a slot index, not a live layout

Zones ran a `UIListLayout`, so dragging one button out of the row made every other button slide
over to close the gap. The player moved one control and the rest moved themselves.

A button's slot is now derived from its `Order` alone, so it depends on nothing that can change:
hiding, resizing, dragging or destroying a neighbour leaves every other button exactly where the
player last saw it. `Order` is assigned per zone in creation order when you do not pass one, so
existing code lays out the same.

The cost is that a removed button leaves a hole rather than the row closing up. That is the
intended trade — on a control pad, muscle memory beats tidiness.

`SetZoneOffset` still repositions a whole zone, since that is an explicit request rather than a
side effect of something else moving.

### Changed — buttons default to the jump button's size

A pad sitting beside Roblox's jump button should read as one set of controls, so `DEFAULT_SIZE` is
no longer a constant: buttons measure the CoreGui jump button and match it, falling back to
`Config.TOUCH.DEFAULT_SIZE` when it cannot be found. Measured in device pixels and divided back
through this layer's own `UIScale`, since button sizes are authored in reference pixels. A zero
`AbsoluteSize` before the first render falls through to the default without being cached.

Set `Config.TOUCH.MATCH_JUMP_SIZE = false` to keep a fixed size, or pass `Size` per button.

### Added — `ButtonOptions.Template`

Any `GuiButton` can be used as the source for a button, cloned with its own art, children and
styling intact:

```lua
TouchUtil.Button("Dash", { Template = MyStyledButton })
```

This is the mechanism `JumpButton` uses. Templated buttons default `IsNormalImage` to true, since
the sprite-sheet rect swap assumes Craftsman's own asset.

### Changed — button size is driven by a `UIScale`, not the `Size` property

`SetSize` used to write `Size`, which scales the button frame and nothing inside it: the label
stayed at 14pt, the overlay stayed at its authored pixel size, and the outline kept its 2px
thickness. A button resized from 70 to 140 looked like a big frame around small contents.

Each button now carries its own `UIScale`, and `SetSize(px)` sets `Scale = px / BASE_SIZE`. The
whole button scales as one. This nests under the layer-wide `UIScale` from `InterfaceUtil`, so the
two compose: device scaling times per-button sizing.

`Config.TOUCH.BASE_SIZE` (70) is the size the art is authored at and the reference the scale is
computed from. It is deliberately separate from `DEFAULT_SIZE` — they default to the same number,
but one is "what buttons start at" and the other is "what `Scale = 1` means", and welding them
would silently re-scale every label the first time someone changed the default.

The resize handle is counter-scaled so it stays a constant grab target: a button shrunk to the
40px minimum would otherwise leave a 12px handle to hit with a thumb.

Nothing changes for callers. `SetSize` takes the same reference pixels, `GetLayout` stores the
same numbers, and saved layouts are unaffected.

**[unverified]** — whether `UIListLayout` accounts for a child's own `UIScale` when spacing a zone.
If it does not, a button resized while still in its zone will overlap its neighbours until it is
dragged out. Needs a Studio check.

### Added — image overlays on touch buttons

`Icon` replaces the button art. `Overlay` draws on top of it, which is what you want for an
ability glyph or a weapon icon sitting on the standard button frame:

```lua
TouchUtil.Button("Dash", {
	Overlay = "rbxassetid://92995853558775",
	Zone = "BottomRight",
})
```

The overlay rests at `OVERLAY_TRANSPARENCY` (0.3) so it reads as part of the button rather than a
sticker on it, and sharpens on press by `OVERLAY_PRESS_DELTA` — subtracted from whatever resting
value you set, so the feedback stays proportional instead of snapping to a fixed number. It dims
with the button when disabled, and covers `OVERLAY_SCALE` (0.55) of the button by default.

`SetOverlay`, `SetOverlayTransparency` and `SetOverlayScale` change it at runtime; `SetOverlay(nil)`
hides it. New `ButtonOptions`: `Overlay`, `OverlayTransparency`, `OverlayScale`. New under
`Config.TOUCH`: `OVERLAY_TRANSPARENCY`, `OVERLAY_PRESS_DELTA`, `OVERLAY_SCALE`.

The z-order is now explicit rather than dependent on child creation order: button art, then
overlay, then label, then the edit-mode resize handle.

### Added — players can move and resize their own touch buttons

`TouchUtil.SetEditMode(true)` turns the pad into a layout editor. Buttons stop firing their
actions; a press starts a drag instead, and resizable buttons grow a corner handle. Movable
buttons temporarily sink input so a drag does not also pan the camera, and that is reverted on the
way out.

```lua
TouchUtil.SetEditMode(true)

TouchUtil.LayoutChanged:Connect(function()
	SaveTouchLayout(TouchUtil.GetLayout())
end)
```

**Craftsman does not persist the layout.** `GetLayout()` returns a plain serializable table and
`ApplyLayout(layout)` takes it back; where it lives between sessions is your game's decision.
`Data` is opt-in and its schema is yours, so a utility reaching into it would rebuild exactly the
consumer-inversion this release removed.

**The stored form is resolution-independent, deliberately.** Position is a viewport fraction and
size is in reference pixels, pre-`UIScale` — a layout arranged on a phone has to mean the same
thing on a tablet, and storing device pixels is the obvious way to get that wrong.

Entries key on `LayoutId`, which defaults to the action name and can be set explicitly. Two
buttons can drive one action, and an action can be renamed; neither should invalidate a layout a
player has already saved. Duplicate ids warn at construction.

Only customised buttons are stored, so a layout saved against one version of the pad still applies
cleanly after buttons are added, removed or repositioned in code. Unknown ids are skipped. A
layout whose `Version` does not match `Config.TOUCH.LAYOUT_VERSION` is rejected with a warning
rather than applied — there is no migration to run, and feeding an old shape to new code corrupts
the pad.

`ApplyLayout` deliberately does **not** fire `LayoutChanged`. Restoring is not a change, and
firing there would make the obvious save-on-change wiring write back on every join.

Dragging clamps the whole button inside the safe area, not just its centre, so a button cannot be
pushed somewhere only a reset can recover it from. `SetGrid(pixels)` snaps to a grid; drags start
only after `DRAG_THRESHOLD` so a sloppy tap does not nudge the pad. Multitouch drags work — two
fingers, two buttons — because the press path already keys on `InputObject` identity.

New on `TouchButton`: `SetMovable`, `SetResizable`, `SetSizeRange`, `GetLayout`, `ApplyLayout`,
`ResetLayout`, `Moved`, `Resized`, `LayoutId`, `IsCustomised`. New module-level: `SetEditMode`,
`IsEditMode`, `SetGrid`, `GetLayout`, `ApplyLayout`, `ResetLayout`, `GetButton`,
`EditModeChanged`, `LayoutChanged`. New `ButtonOptions`: `LayoutId`, `Movable`, `Resizable`,
`MinSize`, `MaxSize`.

Configured under `Config.TOUCH` — `MIN_SIZE`, `MAX_SIZE`, `EDIT_GRID`, `DRAG_THRESHOLD`,
`EDIT_OUTLINE_COLOR`, `EDIT_OUTLINE_TRANSPARENCY`, `HANDLE_SIZE`, `HANDLE_COLOR`,
`LAYOUT_VERSION`.

There is deliberately no pinch-to-resize. It fights camera zoom, cannot be tested with a mouse in
Studio, and is undiscoverable; the corner handle works one-handed and in the emulator. Pinch can
be added later beside it, not instead of it.

**Leaving edit mode is your UI's job.** A `TouchUtil` button cannot do it — in edit mode buttons
drag rather than fire, so the toggle has to live outside the touch layer.
`test/Shared/TouchSmoke.luau` builds one, and is the reference for the whole flow.

### Breaking — `InputUtil.Began` fires on the first source, not on every press

**What changed.** `InputUtil` now counts the sources holding an action. `Began` fires when the
first one raises it and `Ended` when the last one releases it. Previously every matching
`InputBegan` fired `Began`, so an action bound to two keys fired twice when both were held and
ended when either was released.

**Who this breaks.** Anyone counting `Began` events rather than treating them as an edge, or
relying on an action ending while another bound key is still down.

**Why it changed.** Without refcounting there is no correct answer when a player holds the same
action on two devices at once — which is exactly what happens the moment a touch button and a
keybind share an action name.

### Added — `InputUtil` action sources and rebindable inputs

`InputUtil.SetActionState(action_name, is_active, source, input_object?)` raises or lowers an
action from anything that is not the keyboard, mouse or gamepad. `source` identifies the holder;
`TouchUtil` passes the button.

Bindings gained a default to return to:

- `SetPrimitiveBinding(action_name, keys)` records the shipped default, and binds if nothing is
  bound yet.
- `ResetBinding(action_name?)` restores one default, or every one.
- `GetBinding(action_name)` returns a copy, for drawing a keybind menu or an input glyph.
- `BindingChanged` fires `(action_name, new_keys, old_keys)` on every rebind.

`BindAction` now releases any key of the outgoing binding that is held, so rebinding mid-hold
cannot leave an action stuck. `UnbindAction` does the same, and leaves non-key sources alone — so
unbinding a keyboard shortcut does not release a touch button under the player's thumb.

`InputUtil.GetDeviceType()` reads the tracked device without going through the store.

### Fixed — a key released into a focused text box left its action held

`InputUtil` filtered `InputEnded` on `gameProcessedEvent`, so a key pressed during play and
released after chat took focus never ended its action. Releases are no longer filtered; a press
that was ignored still ends as a no-op, because the source was never recorded. `WindowFocusReleased`
now releases every held key for the same reason — alt-tabbing mid-hold used to strand the action.

### Fixed — device type was `KeyboardMouse` until the player's first input

`InputStore.DeviceType` started at `KeyboardMouse` and only moved on `InputBegan`. On a phone no
input has happened when the UI builds, so anything gated on `Touch` — every `TouchUtil` button —
stayed hidden until the player tapped something, and there was nothing to tap.

`InputUtil` now seeds the device on load: `GetLastInputType()` first, then falling back to
capability sniffing for a device with no keyboard or mouse attached. `TouchEnabled` is still not
the *gate* — a laptop with a touchscreen reports `KeyboardMouse` and gets no touch buttons — it is
only the opening guess before any input exists to read.

### Fixed — `InputUtil` was not safe to require on the server

It connected `UserInputService` at module scope, so the lazy barrel would throw for any server code
that touched `Craftsman.InputUtil`. The connections are now behind a `RunService:IsClient()` guard;
the binding and action-source API works on both sides.

### Fixed — `InputUtil` only recognised `Gamepad1`

Device-type tracking mapped `Keyboard`, `MouseButton1`/`2` and `Gamepad1`. `Gamepad2-4`,
`MouseButton3` and `MouseWheel` fell through and left the device type stale.

### Changed — `Config` uses `TableUtil`

`Config` hand-rolled `deep_clone` and `deep_merge` that already existed as `TableUtil.DeepClone` and
`TableUtil.DeepMerge`. 56 lines deleted, no behaviour change.

### Added — a warning when `DATA.SCHEMA` is missing

`DATA.SCHEMA` is how player data gets typed: `PlayerState` reads it, and `Data`/`Market` are typed
off `PlayerState`. Without one it degrades to `any` — silently, because it fails in a type position
under `--!nonstrict`. Craftsman now warns when `DATA.ENABLED` is true and no schema is set. It is a
warning, not an error.

### Added — radian-native angle helpers

`MathUtil.ShortestAngle` is degrees, but `CFrame` and `atan2` are radians. `ShortestAngleRad` and
`ApproachAngle` are the radian-native counterparts, added alongside rather than replacing:

```lua
local facing = MathUtil.ApproachAngle(facing, target, 0.2)   -- takes the short way around
```

### Added — non-yielding rig accessors on `Entity`

`Entity:GetHumanoid()` and `Entity:GetRoot()` never yield, return `nil` rather than erroring, and
read the rig as it is *now* — so they stay correct across a Humanoid that gets replaced or
destroyed, which the `.Humanoid` field captured at construction does not.

### Breaking — `Entity.new` errors on a rig with no Humanoid

It used to `WaitForChild` without a timeout, so a rig that never got a `Humanoid` or
`HumanoidRootPart` hung `Entity.new` **forever**, with no error and no way to recover. The waits
are now bounded at 5 seconds and raise an error naming the rig.

This is strictly more recoverable than hanging — you can `pcall` it — but code that relied on
`Entity.new` blocking indefinitely will now throw.
