# Input & UI: InputUtil, TouchUtil, InterfaceUtil

## InputUtil

InputUtil works with **named actions**. Several sources can hold the same action at once: keys, gamepad buttons, touch buttons, or your own code. `Began` fires when the first source presses the action, and `Ended` fires when the last source lets go. Game code should only listen to actions, never to raw `UserInputService`.

- Call every function with `.`.
- It is safe to require on the server, but only the client actually receives input.
- An input matches a binding by its `KeyCode`. When the KeyCode is `Unknown` (mouse buttons), it matches by its `UserInputType` instead.
- Game-processed input, such as typing in chat, never starts an action.

**Bindings**

| Call | Behaviour |
|---|---|
| `SetPrimitiveBinding(action, keys)` | Records the default binding. It also binds it, but only if the action is currently unbound. **Use this for defaults.** |
| `BindAction(action, keys)` | Replaces the current binding, e.g. a player rebind. Keys that are held when you rebind are released. Fires `BindingChanged`. Don't mutate `keys` afterwards: it's stored by reference. |
| `ResetBinding(action?)` | Restores the default binding for one action, or for every action if you omit `action`. |
| `GetBinding(action)` | Returns a copy of the keys, or `nil`. |
| `UnbindAction(action)` | Removes the binding. Doesn't fire `BindingChanged`. |

**State**

| Call | Behaviour |
|---|---|
| `SetActionState(action, is_active, source, input_object?)` | Presses or releases the action on behalf of `source`, which is any unique value. |
| `IsActionActive(action)` | `true` while any source holds the action. |

**Signals**

| Signal | Arguments |
|---|---|
| `Began` | `(action, input_object)` |
| `Ended` | `(action, input_object)` |
| `BindingChanged` | `(action, new_keys, old_keys?)` |
| `DeviceChanged` | `(device, previous_device)`. Fires only when the last used device actually changes. |

`input_object` can be a frozen stand-in rather than a real `InputObject`, for example after focus is lost or the action was released from code.

**Helpers**

| Call | Behaviour |
|---|---|
| `GetMovementVector()` | Unit vector from WASD and the left thumbstick. Forward is −Z. It ignores bindings and has no deadzone. |
| `GetCameraDelta()` | Mouse delta. |
| `GetDeviceType()` | The most recently used device: `"KeyboardMouse" \| "Gamepad" \| "Touch"`. Listen to `DeviceChanged` to react when it changes. |

```lua
InputUtil.SetPrimitiveBinding("Dash", { Enum.KeyCode.Q, Enum.KeyCode.ButtonX })
InputUtil.SetPrimitiveBinding("Attack", { Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2 })

self.Keeper:Add(InputUtil.Began:Connect(function(action)
	if action ~= "Dash" then
		return
	end
	dash()
end))
```

## TouchUtil (client only)

Touch buttons are just another **source** for InputUtil actions, so one `InputUtil.Began` handler serves keyboard, gamepad and touch alike. Create buttons unconditionally. Each button only shows on the devices listed in its `ShowOn` option, which defaults to `{ "Touch" }`.

- Call module functions with `.` and `TouchButton` methods with `:`.
- `TouchUtil.Button(action, options?) -> TouchButton`

**`ButtonOptions`**

| Group | Fields |
|---|---|
| Appearance | `Icon`, `IsNormalImage`, `Text`, `Overlay`, `OverlayTransparency`, `OverlayScale`, `OverlayOffset` |
| Placement | `Zone` (default `"BottomRight"`), `Order`, `Position` |
| Size | `Size`, `MinSize`, `MaxSize` |
| Visibility | `ShowOn`, `VisibleWhen` (a context map, e.g. `{ Combat = true }`) |
| Editing | `LayoutId` (defaults to the action name), `Movable`, `Resizable` |
| Input | `Sink` |

`Zone` is one of `TopLeft | Top | TopRight | Left | Center | Right | BottomLeft | Bottom | BottomRight`.

**`TouchButton` methods**
- The setters chain: `:SetIcon`, `:SetText`, `:SetOverlay`, `:SetSize`, `:SetSizeRange`, `:SetZone(zone, order?)`, `:SetPosition`, `:SetVisibleWhen`, `:SetShowOn`, `:SetEnabled`, `:SetVisible`, `:SetMovable`, `:SetResizable`.
- Also: `:IsPressed()`, `:GetLayout()`, `:ApplyLayout(entry)`, `:ResetLayout()`, `:Destroy()`.
- Signals: `Pressed`, `Released`, `Moved`, `Resized`.
- Put buttons into a Keeper so they are destroyed with their owner.

**Contexts**
- `SetContext(name, bool)` / `SetContexts(map)` / `GetContext(name)` switch whole groups of buttons on and off.
- A context that has never been set reads as `false`.

**Edit mode.** `SetEditMode(bool)` lets the player drag and resize buttons. While it is on, buttons don't fire their actions. Related calls:
- `IsEditMode()`
- `SetGrid(px?)`
- `SetZoneOffset(zone, Vector2)`

**Layouts.** Persisting layouts is up to you.
- `GetLayout()` returns `{ Version, Entries }`, containing only the buttons the player has customised.
- `ApplyLayout(layout)` returns `false` when the version doesn't match. **Create the buttons first**, then apply the layout.
- `ResetLayout(layout_id?)` restores defaults for one button, or for all of them.
- Save the layout from the module signal `LayoutChanged(layout_id, entry)`.

**Adoption.** Adopting adds edit and layout support to an existing GUI without taking over its input.
- `Adopt(gui_object, options?)` works with any existing GuiObject.
- `AdoptJumpButton(options?)`, `SetJumpButtonEditable(bool)` and `GetJumpButton()` do the same for the Roblox jump button.
- Adopted buttons never drive InputUtil.

**Other module calls**
- Lookup: `GetButtons(action)`, `GetButton(layout_id)`, `GetRoot()`
- Global switches: `SetEnabled(bool)` shows or hides the whole layer. `Destroy()` removes it.

Module signals:
- `ContextChanged(context, state, previous)`
- `EditModeChanged(enabled)`
- `LayoutChanged(layout_id, entry)`

```lua
InputUtil.SetPrimitiveBinding("Dash", { Enum.KeyCode.Q })

self.Keeper:Add(TouchUtil.Button("Dash", { Text = "Dash", Zone = "BottomRight", VisibleWhen = { Combat = true } }))
TouchUtil.SetContext("Combat", true)

TouchUtil.ApplyLayout(saved_layout)
self.Keeper:Add(TouchUtil.LayoutChanged:Connect(function()
	save_layout(TouchUtil.GetLayout())
end))
```

Visual defaults such as the sprite asset, sizes, colours, grid and display order live under `Config.TOUCH`; see `lifecycle.md`. `DISPLAY_ORDER` and `AUTO_SCALE` are read once, when the first button is created.

## InterfaceUtil

InterfaceUtil scales UI to any resolution by driving a `UIScale` from the viewport size.

`ScaleOptions = { Reference?: Vector2, Mode?: "Fit" | "Height" | "Width" | "Diagonal", Min?, Max?, Damping?, Boost? }`. Any field you leave out falls back to `Config.INTERFACE`.

| Call | Behaviour |
|---|---|
| `InterfaceUtil.ComputeScale(viewport, options?) -> number` | Pure calculation. Called with **`.`**. |
| `InterfaceUtil:AutoScale(target, options?) -> () -> ()` | Called with **`:`**. Client only. Reuses the target's existing `UIScale` or creates one, and tracks the viewport and camera. On console, `Boost` defaults to `TEN_FOOT_BOOST`. Calling it again on the same target replaces the old binding. The returned function unbinds; add it to a Keeper. |

```lua
self.Keeper:Add(InterfaceUtil:AutoScale(hud_gui, { Mode = "Height", Damping = 0.7 }))
```
