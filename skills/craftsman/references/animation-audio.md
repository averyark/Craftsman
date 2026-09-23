# Animation & Audio: TweenUtil, Spring, AnimationUtil, SoundUtil

Every module function is called with `.`. Methods on returned objects (`SoundPlayer`, `Animate`, `TweenGroup`, value springs) are called with `:`.

## TweenUtil

TweenUtil stores named animation templates and plays them with either TweenService or Spring. Registering names up front is the idiom. Use `QuickPlay` for one-off tweens.

### `TweenUtil.new(name, style_or_type, properties, duration_or_damping?, direction_or_frequency?)`

- `name` is a key shared by the whole Lua VM (client and server each have their own).
- `style_or_type` is an `Enum.EasingStyle`, or the string `"Spring"`.
- A property whose value is a **table** targets a child with that name: `{ Title = { TextTransparency = 1 } }` animates `instance.Title`.
- When `style_or_type` is an easing style:
  - `duration_or_damping` is the duration in seconds (default `0.3`).
  - `direction_or_frequency` is the easing direction (default `Out`).
- When it is `"Spring"`:
  - `duration_or_damping` is the damping ratio (default `1`).
  - `direction_or_frequency` is the frequency in Hz (default `8`).
- Registering a name twice with the same definition warns and keeps the original. Registering it with a **different** definition **errors**, so register each template once, from a single place.

### Playback

| Call | Returns | Notes |
|---|---|---|
| `TweenUtil.Play(name, instance)` | `Tween \| TweenGroup \| nil` | Returns `nil` when the name is missing, when the template is a Spring, or when no properties resolve. Returns a `TweenGroup` when the template also targets children. |
| `TweenUtil.PlayFrom(name, instance, start_props)` | same as `Play` | Sets `start_props` instantly, then plays. |
| `TweenUtil.QuickPlay(instance, ...)` | same as `Play` | Always TweenService. The arguments after `instance` can come in any order: `number` is the duration, `table` is the properties (required), `EasingStyle` is the style, `EasingDirection` is the direction. |
| `TweenUtil.Stop(instance, property?)` | – | With `property`, stops that one property on this instance. Without it, stops all TweenUtil tweens and all springs on the instance and its descendants. |

`TweenGroup` has these members:
- `Tweens`
- `PlaybackState`
- `Completed`, which supports `:Connect`, `:Once` and `:Wait`, and fires once after every tween in the group ends.
- `:Play()`, `:Pause()`, `:Cancel()`

**Dedup:** before every play, TweenUtil stops springs and cancels any TweenUtil-tracked tween that is animating the same instance+property. It cancels the whole old Tween, so properties that the new play doesn't touch are cut off mid-flight too. Tweens you create directly with TweenService are not tracked.

```lua
TweenUtil.new("PanelOut", Enum.EasingStyle.Quad, { BackgroundTransparency = 1, Title = { TextTransparency = 1 } }, 0.25)
TweenUtil.new("Pop", "Spring", { Size = UDim2.fromOffset(120, 120) }, 0.6, 4)

local tween = TweenUtil.PlayFrom("PanelOut", panel, { BackgroundTransparency = 0 })
if tween then
	tween.Completed:Wait()
end

TweenUtil.Play("Pop", button)
TweenUtil.QuickPlay(frame, { Position = UDim2.fromScale(0.5, 0.5) }, 0.4, Enum.EasingStyle.Back)
```

## Spring (`Craftsman.Spring`, the vendored `spr`)

Spring animates by physics.
- **Damping ratio:** `1` means no overshoot, below `1` bounces, above `1` is sluggish.
- **Frequency:** in Hz; higher is faster.
- Passing `math.huge` as the frequency snaps to the target immediately.

| Call | Behaviour |
|---|---|
| `Spring.target(instance, damping, frequency, props)` | Retargets properties while keeping their velocity. Each target must have the same type as the current property value, or it errors. Also supports the pseudo-properties `Pivot` (on a PVInstance) and `Scale` (on a Model). |
| `Spring.stop(instance, property?)` | Stops without firing `completed`. |
| `Spring.completed(instance, callback)` | Fires once every spring on the instance has settled. If the instance is not animating, it waits for the next run to finish. |
| `Spring.new(value, damping, frequency, render_phase?)` | Creates a standalone value spring. Methods: `:setGoal`, `:getValue`, `:getGoal`, `:getVelocity`, `:setVelocity`, `:setDampingRatio`, `:setFrequency`, `:reset(value?)`, `:stop()`, `:isAnimating()`, `:onComplete(cb)`, `:destroy()`. |

Supported value types: number, boolean, UDim, UDim2, Vector2, Vector3, Color3, CFrame, NumberRange and ColorSequence.

## AnimationUtil

`AnimationProperties = { FadeTime?, Weight?, Speed?, Priority?: Enum.AnimationPriority, Looped? }`

**Registry.** Register every animation once, then refer to it by name.
- `AnimationUtil.Register(name, animation_id, should_preload?) -> Animation`: preloading happens on the client only.
- `AnimationUtil.BulkRegister({ [name] = { AnimationId = "rbxassetid://..." } }, should_preload?)`: only `AnimationId` is read from each entry.
- `AnimationUtil.Unregister(name)`: **errors** if `name` is not registered.

**One-shot playback.**
- `AnimationUtil.QuickPlay(animator: Animator, name, props?) -> AnimationTrack`
- **Errors** if `name` is not registered.
- It always plays non-looped, and the track cleans itself up when it ends.

**Per-rig track manager (`Animate`).**
- `AnimationUtil.GetSharedAnimate(container)`: returns the same `Animate` for the same container on every call. The container must be an `Animator`, `Humanoid` or `AnimationController` (a Model errors at runtime).
- `AnimationUtil.GetLocalAnimate() -> Animate?`: client only. Returns `nil` and does not wait if the character or its Animator isn't there yet.
- `AnimationUtil.new(container)`: creates an `Animate` that is not shared.

**`Animate` methods.**
- `:Load({ FromRegistry = name, AnimationName? })`, or `:Load({ AnimationName, AnimationId })`
- `:Play(name, props?)`
- `:Stop(name, fade?)`, `:StopAll(fade?)`
- `:Unload(name)`, `:UnloadAll()`
- `:Destroy()`

`Play`, `Stop` and `Unload` **error** when `name` has not been loaded.

**Gotcha:** `Animate:Destroy()` does not remove the `Animate` from the shared cache. Destroy it only if you created it with `.new`.

```lua
AnimationUtil.BulkRegister({ Slash = { AnimationId = "rbxassetid://789" } }, true)

local animate = AnimationUtil.GetSharedAnimate(entity.Humanoid)
animate:Load({ FromRegistry = "Slash" })
animate:Play("Slash", { FadeTime = 0.1, Priority = Enum.AnimationPriority.Action })
```

## SoundUtil

`SoundProperties = { SoundGroup?: string | SoundGroup, Volume?, Looped?, RollOffMode?, RollOffMaxDistance?, RollOffMinDistance?, TimePosition?, PlaybackSpeed? }`

**Sound groups.**
- `SoundUtil.AddSoundGroup(name_or_group)`: gets or creates the group under SoundService.
- `SoundUtil.ConfigureSoundGroup(name_or_group, props)`
- `SoundUtil.GetSoundGroup(name)`: never creates the group.
- `SoundUtil.RemoveSoundGroup(name)`: errors unless the group was obtained through SoundUtil.

**Registry.**
- `SoundUtil.Register(name, sound_id, props?, should_preload?)`: registering an existing name replaces it.
- `SoundUtil.BulkRegister({ [name] = { SoundId = ..., Volume = ..., SoundGroup = "SFX" } }, should_preload?)`
- `SoundUtil.Unregister(name)`: errors if `name` is not registered.

A string `SoundGroup` inside these props creates the group if it doesn't exist yet.

**Fire-and-forget: `SoundUtil.QuickPlay(params) -> Sound`.**
- `params = { SoundName, SoundId?, SoundGroup?, Properties?, Part?, CFrame?, Position? }`
- If `SoundName` is registered, it clones the registered sound. Otherwise it uses `SoundId`.
- Where the sound plays:
  - `Part`: the sound is parented to that part.
  - `CFrame` or `Position`: a temporary anchored part is spawned there.
  - Neither: it plays non-positionally.
- `Looped` is always forced off.
- The sound and any temporary part are cleaned up when the sound ends, when you call `:Stop()` on the returned sound, or when either is destroyed.

**Per-container player (`SoundPlayer`).**
- `SoundUtil.GetSharedSoundPlayer(container)`: one shared player per container.
- `SoundUtil.GetLocalSoundPlayer()`: the shared player for SoundService. It is not per player.
- `SoundUtil.new(container)`: a player that is not shared.

**`SoundPlayer` methods.**
- `:Load({ FromRegistry = name })`, or `:Load({ SoundName, SoundId, ...props })`
- `:Play(name, { PlayDuplicate = true, ...props }?)`: without `PlayDuplicate = true`, it replays the cached sound and ignores the props.
- `:Stop(name)`, `:Pause(name)`, `:Resume(name)`
- `:StopAll()`, `:PauseAll()`, `:ResumeAll()`
- `:Unload(name)`, `:UnloadAll()`
- `:Destroy()`

Any method that takes a name errors when that name has not been loaded.

```lua
SoundUtil.ConfigureSoundGroup("SFX", { Volume = 0.8 })
SoundUtil.BulkRegister({
	Hit = { SoundId = "rbxassetid://123", SoundGroup = "SFX" },
	Coin = { SoundId = "rbxassetid://456", SoundGroup = "SFX" },
}, true)

SoundUtil.QuickPlay({ SoundName = "Hit", Position = hit_position, Properties = { PlaybackSpeed = 1.1 } })

local player_sfx = SoundUtil.GetSharedSoundPlayer(entity.HumanoidRootPart)
player_sfx:Load({ FromRegistry = "Coin" })
player_sfx:Play("Coin", { PlayDuplicate = true })
```
