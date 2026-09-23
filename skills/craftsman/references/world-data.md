# World & Data helpers: WorldUtil, MathUtil, StringUtil, TableUtil, PrintUtil, Inspect

## WorldUtil

**Always call WorldUtil with `:`** (`WorldUtil:RayBelow({...})`). Every function uses `self` internally, so calling one with `.` shifts the arguments and errors.

### Cached params

Casts need either `RayParams` or a registered `RayParamsId`. There is **no default**: a missing id errors with `No RayParams found for id: nil`. Overlap queries fall back to engine defaults.

Register params once, usually in a module's `Init`:

- `WorldUtil:AddRayParams(id, RaycastParams)`
- `WorldUtil:GetRayParams(id)`
- `WorldUtil:RemoveRayParams(id)`
- The same three exist for overlaps: `AddOverlapParams`, `GetOverlapParams`, `RemoveOverlapParams`.

### Casts

Every cast accepts these `CastOptions`:

| Option | Values | Default |
|---|---|---|
| `Mode` | `"Raycast"`, `"Block"`, `"Sphere"` | `"Raycast"` |
| `BlockSize` | `Vector3` | `Vector3.one` |
| `SphereRadius` | number | `1` |

| Call | Param table | Returns |
|---|---|---|
| `:RayBelow` | `{ Position, Distance, RayParamsId? \| RayParams? }` | `RaycastResult?` |
| `:IsGrounded` | same as `RayBelow` | `boolean` |
| `:GetGroundPosition` | same as `RayBelow` | `Vector3?` |
| `:GetGroundNormal` | same as `RayBelow` | `Vector3?` |
| `:RayFront` | `{ CFrame, Distance, Direction?, RayParamsId? \| RayParams? }` | `RaycastResult?` (casts along `LookVector`; `Direction` is **added** to the cast vector) |
| `:RaySide` | same as `RayFront` | `RaycastResult?` (casts along `RightVector`) |
| `:RayUp` | same as `RayFront` | `RaycastResult?` (casts along `UpVector`) |

### Overlaps

Each returns `{ BasePart }`.

| Call | Param table |
|---|---|
| `:GetPartsInRadius` | `{ Center, Radius, OverlapParamsId? \| OverlapParams? }` |
| `:GetPartsInBox` | `{ CFrame, Size, ... }` |
| `:GetPartsInPart` | `{ Part, ... }` |

### Proximity

| Call | Returns | Notes |
|---|---|---|
| `:GetDistance(a, b)` | number | `a` and `b` can each be a Vector3, CFrame, BasePart or Model. |
| `:GetNearest({ Origin, Instances })` | `(instance?, distance)` | Alias: `GetNearestPart`. |
| `:GetNearestPoint(origin, points)` | `(Vector3?, distance)` | Takes positional arguments. |

### Projection

Both use viewport coordinates, so the GUI inset is not included.

| Call | Returns |
|---|---|
| `:WorldToScreen(pos, camera?)` | `(Vector2?, on_screen)` |
| `:ScreenToWorld(screen_pos, depth, camera?)` | `Vector3?` |

### Example

```lua
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = { workspace.Characters }
WorldUtil:AddRayParams("IgnoreCharacters", params)

local grounded = WorldUtil:IsGrounded({ Position = root.Position, Distance = 3.5, RayParamsId = "IgnoreCharacters" })
local hits = WorldUtil:GetPartsInRadius({ Center = root.Position, Radius = 12 })
```

## MathUtil

All functions are pure and called with `.`.

**Interpolation**

| Function | Behaviour |
|---|---|
| `Lerp(a, b, t)` | Unclamped. |
| `InverseLerp(a, b, v)` | Unclamped. |
| `Map(v, in_min, in_max, out_min, out_max)` | Unclamped. |
| `SmoothLerp(current, target, rate, dt)` | Framerate-independent. |

**Numbers**

| Function | Behaviour |
|---|---|
| `RoundTo(v, step)` | Rounds to the nearest multiple of `step`. |
| `Wrap(v, min, max)` | Wraps into `[min, max)`. |
| `ApplyDeadzone(v, threshold)` | Rescales what is left above the threshold. |

**Vectors**

| Function | Behaviour |
|---|---|
| `Direction(origin, target)` | Unit vector, or zero. |
| `Flatten(v)` | Sets Y to 0. |
| `FlatDistance(a, b)` | Distance on the XZ plane. |
| `AngleBetween(a, b)` | Radians. |

**Angles**

| Function | Behaviour |
|---|---|
| `ShortestAngle(cur, target)` | **Degrees**. |
| `ShortestAngleRad(cur, target)` | Radians. |
| `ApproachAngle(cur, target, alpha)` | Radians, along the shortest path. |

**Curves and randomness**

| Function | Behaviour |
|---|---|
| `QuadraticBezier(t, p0, p1, p2)` | `t` comes first. |
| `CubicBezier(t, p0, p1, p2, p3)` | `t` comes first. |
| `WeightedRandom({ [key] = weight })` | Returns `key?`. |
| `RandomInRadius(center, radius)` | Random point on the XZ disc. |

**Formatting**

| Function | Behaviour |
|---|---|
| `Abbreviate(n)` | `"1.5k"`, `"2.3M"` |
| `AddCommas(n)` | `"1,000,000"` |
| `NumberToWords(n)` | Number spelled out in words. |
| `FormatTime(seconds)` | `"MM:SS"`; there is no hours field. |

## StringUtil

All functions are called with `.`. Lengths are counted in bytes.

**Functions built on `gsub` return `(string, count)`.** These are `RemoveWhitespace`, `ToTitleCase`, `EscapeRichText`, `StripRichText` and `FormatTemplate`. Wrap the call in parentheses when it is the last argument of another call, or the extra count gets passed along too.

| Group | Functions |
|---|---|
| Tests | `StartsWith`, `EndsWith`, `Contains` (plain find, not a pattern), `IsWhitespace` |
| Whitespace | `Trim`, `RemoveWhitespace` |
| Case | `ToTitleCase` (lowercases the rest of each word), `ToSnakeCase` (converts spaces and hyphens to `_`, lowercases; does **not** split camelCase) |
| Padding & length | `PadStart(text, len, char?)`, `PadEnd(text, len, char?)`, `Truncate(text, max, suffix?)` (the suffix counts toward `max`) |
| Words | `Pluralize(text, count, suffix?)` |
| Numbers | `FormatDecimal(v, places?)` |
| Rich text | `EscapeRichText`, `StripRichText` |
| Templating | `FormatTemplate(template, dict)` (replaces `{key}`) |
| Random | `Random(len)` (not secure) |

## TableUtil

All functions are called with `.`.

**Return a new table.** Use these when the original must stay untouched.

| Function | Notes |
|---|---|
| `DeepClone` | Tables that have a metatable are copied by reference, not cloned. |
| `Merge(...)` | Shallow. |
| `DeepMerge(...)` | Arrays are merged index by index, not replaced. |
| `Except(first, second)` | Treats `first` as an array (filter by value) or a dictionary (filter by key). |
| `Keys`, `Values` | |

**Read only**

| Function | Notes |
|---|---|
| `IsEmpty`, `Count`, `HasKey`, `GetOrDefault`, `FindKeyByValue` | |
| `EqualDeep` | Deep equality, safe on cycles. |

**Mutate in place.**

| Function | Notes |
|---|---|
| `RemoveValue` | Leaves holes in arrays. |
| `RemoveWhere(dict, predicate)` | |
| `SafeRemove(array, value)` | Removes the first match and shifts later elements down. |
| `SafeRemoveAll(array, value)` | Removes every match. |

## PrintUtil & Inspect

**`PrintUtil`**
- Both functions are called with **`:`**.
- `PrintUtil:ListPrint(title?, columns?, rows?, max_width?)` prints an ASCII table.
  - `rows` can be an array of positional arrays.
  - `rows` can also be a dictionary: each key becomes column 1, and other columns read the row object's fields by header name.
- `PrintUtil:PrintObject(object)` prints a two-column table of an object's `Field` and `Value` pairs.

**`Inspect`**
- The module is itself the function: `Inspect(value, settings?) -> string`.
- It renders any value as Luau-like source.
- Settings:
  - `Pretty`
  - `Indent`
  - `MaxDepth`
  - `MaxItems`
  - `SortKeys`
  - `Precision` (applies to datatype floats)
  - `FullName`
  - `ClassName`
  - `Metamethods`
  - `Semicolons`

```lua
PrintUtil:ListPrint("Inventory", { "Item", "Qty" }, { { "Sword", 1 }, { "Potion", 12 } })
print(Craftsman.Inspect(state, { Pretty = true, MaxDepth = 3 }))
```
