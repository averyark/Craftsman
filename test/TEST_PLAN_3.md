# Test Plan (Part 3) — MathUtil, StringUtil, TableUtil, TweenUtil, WorldUtil

Companion to `test/TEST_PLAN.md` and `test/TEST_PLAN_2.md`. Same target environment (**Studio Play
session, Server + Client**), same harness (§1 of the first plan), same `run_case`+assert idiom from
the deleted reference tests (`TweenUtilTest.luau` is the closest reference for this batch).

Goal: cover the utility surface and regression-lock the one recent fix in this group — **L2**
(`MathUtil.InverseLerp` divide-by-zero guard, `a == b` → `0`).

---

## 0. What's different from Parts 1–2

- **Three modules are pure** (no Roblox services, only datatypes like `Vector3`/`CFrame` which exist
  in the VM): **MathUtil, StringUtil, TableUtil** → **Tier A (pure)**. Fully deterministic.
- **Two modules touch real Instances** but need **no** API Services, players, or networking:
  **TweenUtil** (real `Tween`/`Spr` on `Part`s) and **WorldUtil** (raycasts/overlaps against
  `workspace`) → **Tier A (in-VM)**. They run fine in the same Play session; just build and clean up
  throwaway `Part`s. The only genuine Tier-B bits are `WorldUtil:WorldToScreen`/`:ScreenToWorld`
  (need a `CurrentCamera` → run client-side).
- **Two recurring concerns drive the harness additions below:** floating-point comparison and
  randomness.

### Harness additions (extend `TestRunner`/`Mocks`)
- **`expect(x).toBeCloseTo(y, eps?)`** (default `eps = 1e-6`) for floats, and a `approxVec(a, b, eps)`
  helper for `Vector3` (compare per-component, or `(a-b).Magnitude <= eps`). Bezier/Lerp/trig/spring
  results must use these, never `==`.
- **Randomness:** call `math.randomseed(<fixed>)` at the start of any case asserting a specific
  random outcome; otherwise assert **invariants/bounds** (membership, length, in-radius) over a
  handful of draws rather than exact values.
- **`Mocks.tempPart(props?)`** → an anchored `Part` parented under a dedicated
  `workspace.__CraftsmanTest` folder, returned with a `destroy()`; a `Mocks.tempFolder()` for batches.
  Always clean up in `afterEach` so casts don't accumulate geometry.
- **`Mocks.includeParams(parts)`** → `RaycastParams`/`OverlapParams` with
  `FilterType = Enum.RaycastFilterType.Include` and `FilterDescendantsInstances = parts`, so WorldUtil
  casts only hit the test parts (not the baseplate) — this is what makes WorldUtil deterministic.

> Note (gotcha): several StringUtil/TableUtil functions use `string.gsub`/return multiple values.
> When asserting, bind to a single local (`local r = StringUtil.ToSnakeCase(x)`) or pass as a
> non-trailing arg so the extra return (match count) is truncated.

---

## 1. MathUtil — `test/Server/MathUtil.spec.luau`  (Tier A, pure)

Use `toBeCloseTo`/`approxVec` for all non-integer results.

| ID | Case | Assert |
|----|------|--------|
| MU-01 | `Map` | `Map(5,0,10,0,100)≈50`; works with reversed output range and negative ranges |
| MU-02 | `Lerp` | `Lerp(0,10,0)==0`, `(…,1)==10`, `(…,0.5)≈5`; extrapolates for `alpha>1` |
| MU-03 | **L2 regression** — `InverseLerp` | `InverseLerp(0,10,5)≈0.5`; round-trips `Lerp`; **`InverseLerp(5,5,5)==0`** (no div-by-zero / NaN) |
| MU-04 | `SmoothLerp` | `dt=0` → returns `current`; moves toward `target` as `dt`/`rate` grow; never overshoots |
| MU-05 | `Abbreviate` | `999→"999"`, `1000→"1k"`, `1500→"1.5k"`, `1000000→"1M"`; trailing `.0` stripped |
| MU-06 | `AddCommas` | `1000000→"1,000,000"`, `-1234→"-1,234"`, `999→"999"` |
| MU-07 | `NumberToWords` | `0→"zero"`, `123→"one hundred twenty three"`, negatives prefixed `"minus "`, `million`/`thousand` scales, decimal → `"point …"` |
| MU-08 | `FormatTime` | `0→"00:00"`, `150→"02:30"`, `3661→"61:01"` (no hour rollover) |
| MU-09 | `RoundTo` | `RoundTo(7,5)==5`, `RoundTo(8,5)==10`, `RoundTo(0.7,0.5)≈0.5` |
| MU-10 | `Wrap` | `Wrap(370,0,360)==10`, `Wrap(-10,0,360)==350`, in-range unchanged |
| MU-11 | `Direction` | unit vector toward target; equal points → `Vector3.zero` |
| MU-12 | `Flatten` | zeroes `Y`, keeps `X`/`Z` |
| MU-13 | `FlatDistance` | ignores `Y` (e.g. points differing only in Y → `0`) |
| MU-14 | `AngleBetween` | orthogonal → `≈π/2`; identical dir → `≈0`; opposite → `≈π`; zero-magnitude → `0`; clamps domain (no NaN) |
| MU-15 | `ShortestAngle` | `(350,10)→20`, `(10,350)→-20`, result always in `[-180,180]` |
| MU-16 | `QuadraticBezier` / `CubicBezier` | `t=0`→`p0`; `t=1`→`p2`/`p3`; midpoint between control hull (sanity) |
| MU-17 | `ApplyDeadzone` | below threshold → `0`; above → remapped magnitude, sign preserved |
| MU-18 | `WeightedRandom` `@random` | always returns a key present in the table; empty table → `nil`; single-entry always returned; (seeded) heavy-weight key dominates over N draws |
| MU-19 | `RandomInRadius` `@random` | result `Y == center.Y`; XZ distance from center `<= radius` over many draws |

---

## 2. StringUtil — `test/Server/StringUtil.spec.luau`  (Tier A, pure)

| ID | Case | Assert |
|----|------|--------|
| SU-01 | `StartsWith` / `EndsWith` | true/false cases; `EndsWith(text, "")` → `true` |
| SU-02 | `IsWhitespace` | `""`→true, `"   "`→true, `"a"`→false |
| SU-03 | `Contains` | plain search; matches literal special chars (e.g. `Contains("a.b",".")` true, `Contains("axb",".")` **false** — proves plain, not pattern) |
| SU-04 | `Trim` / `RemoveWhitespace` | trims ends only / removes all interior whitespace |
| SU-05 | `ToTitleCase` / `ToSnakeCase` | `"hello world"→"Hello World"`; `"Hello World"`/`"Hello-World"`→`"hello_world"` |
| SU-06 | `PadStart` / `PadEnd` | pads to length with default space and a custom char; already-long string unchanged |
| SU-07 | `Truncate` | short text unchanged; long text cut + suffix; `max_length <= #suffix` → returns suffix |
| SU-08 | `Pluralize` | `count==1`→singular; else `+"s"`; custom suffix honored |
| SU-09 | `FormatDecimal` | default 2 places; custom precision |
| SU-10 | `EscapeRichText` / `StripRichText` | escapes `& < > " '`; strips `<...>` tags |
| SU-11 | `FormatTemplate` | replaces `{key}` from dict; **missing key left literally** as `{key}` |
| SU-12 | `Random` `@random` | returned length matches; every char ∈ alphanumeric set |

---

## 3. TableUtil — `test/Server/TableUtil.spec.luau`  (Tier A, pure)

Use `TableUtil.EqualDeep` (the module under test) carefully — prefer the harness `toEqual` to assert,
and test `EqualDeep` itself with explicit cases (don't let it grade its own correctness).

| ID | Case | Assert |
|----|------|--------|
| TU-01 | `DeepClone` | deep-copies nested tables (mutating clone doesn't affect source); **cyclic** table clones without infinite loop; values **with a metatable** are returned as-is (not cloned) |
| TU-02 | `Merge` | shallow left→right overwrite; non-table args skipped; result is a new table |
| TU-03 | `DeepMerge` | nested tables merged recursively; source-only nested tables deep-cloned (not shared by ref); metatable values treated atomically |
| TU-04 | `IsEmpty` | `{}`→true, `{a=1}`→false |
| TU-05 | `Keys` / `Values` | returns arrays of the dict's keys / values (order-independent membership check) |
| TU-06 | `FindKeyByValue` | returns the key for a present value; `nil` when absent |
| TU-07 | `RemoveValue` | removes all matching values in-place; returns `true`/`false` for removed-any |
| TU-08 | `RemoveWhere` | removes pairs where predicate true; returns removed-any bool |
| TU-09 | `HasKey` / `GetOrDefault` | key presence; default returned only when key missing (present `false`/`0` values returned, not defaulted — note `HasKey` uses `~= nil`) |
| TU-10 | `Count` | counts all pairs incl. non-array dict keys |
| TU-11 | `EqualDeep` | deeply-equal nested → true; differing value → false; **extra key on right** → false; cyclic structures terminate; metatable on either side → false |
| TU-12 | `SafeRemove` / `SafeRemoveAll` | array first-occurrence vs all-occurrences removal; returns removed bool; missing value → false |
| TU-13 | `Except` | array input → excludes by **value**; dict input → excludes by **key**; returns a new table |

---

## 4. TweenUtil — `test/Server/TweenUtil.spec.luau`  (Tier A, in-VM)

Pattern (from the reference test): register short templates (`duration ≈ 0.05`), make an anchored
`Part`, `Play`, `task.wait(duration*2)`, assert the final property, then destroy the part. Use
`Mocks.tempPart`/`afterEach` cleanup. `@timing` on anything that waits for completion/spring settle.

| ID | Case | Assert |
|----|------|--------|
| TW-01 | `new` template config | returns config; defaults `Type=="Tween"`, `Duration==0.3`, `Style==Quad`, `Direction==Out`; `"Spring"` type sets `Damping`/`Frequency`; template retrievable by name |
| TW-02 | `Play` standard tween animates `@timing` | returns a `Tween`; after wait the target property reaches the goal (e.g. `Transparency==1`) |
| TW-03 | `Play` unknown template | warns; returns `nil` (no error) |
| TW-04 | Nested-child properties | template with a nested `{ Child = { Prop = v } }` animates the child; missing child warns but doesn't error |
| TW-05 | `PlayFrom` | snaps to `start_properties` immediately, then animates to the template target `@timing` |
| TW-06 | `PlayAsync` resolves/rejects | standard tween: promise **resolves** on completion; on `Cancel`/cancel → rejects/cleans up `@timing` |
| TW-07 | Spring template | `Play` of a `"Spring"` returns `nil`; `PlayAsync` resolves once the spring settles (`Spr.completed`) `@timing` |
| TW-08 | Dedup cancels prior tween on same property | `Play` A then immediately `Play` B targeting the same property → the first tween is cancelled; only B's target is reached |
| TW-09 | `Stop` | `Stop(instance, prop)` cancels just that property's tween; `Stop(instance)` cancels all (and springs on descendants) |
| TW-10 | `QuickPlay` both arg orders | `QuickPlay(part, {Transparency=1}, 0.05, Enum.EasingStyle.Linear)` and the alternate order both work; asserts on missing properties table; temp template is removed afterward |
| TW-11 | Multi-instance/prop → tween group | a template hitting multiple instances returns a group whose `Completed` fires once all finish; `group:Cancel()`/`Pause()` work `@timing` |

---

## 5. WorldUtil — `test/Server/WorldUtil.spec.luau`  (Tier A, in-VM) + a client case (Tier B)

Build a dedicated `workspace.__CraftsmanTest` folder with anchored parts at known positions, and use
`Mocks.includeParams` so casts hit only those parts. Clean up in `afterEach`.

| ID | Case | Assert |
|----|------|--------|
| WU-01 | RayParams / OverlapParams registry | `AddRayParams`/`GetRayParams`/`RemoveRayParams` round-trip; same for OverlapParams; `Get` of unknown → `nil` |
| WU-02 | `RayBelow` hit + missing-params guard | place a part below the origin → returns a `RaycastResult` whose `Instance` is that part; with no `RayParams`/`RayParamsId` → `PrintUtil:Error` **throws** (assert `toThrow`) |
| WU-03 | `IsGrounded` | part below → `true`; clear air (Include params with no parts in path) → `false` |
| WU-04 | `RayFront` / `RaySide` / `RayUp` | place a part along the CFrame's look / right / up vector at `Distance` → each returns a hit; `Direction` offset is applied |
| WU-05 | `GetGroundPosition` / `GetGroundNormal` | hit → expected `Position` (≈ part top) / upward `Normal` (`≈ (0,1,0)`); miss → `nil` |
| WU-06 | `GetPartsInRadius` / `GetPartsInBox` / `GetPartsInPart` | parts within the volume are returned; parts outside excluded (use Include params) |
| WU-07 | `GetDistance` | accepts `Vector3`, `CFrame`, `BasePart`, `Model` in any mix; matches `(a-b).Magnitude`; invalid type → errors |
| WU-08 | `GetNearest` / `GetNearestPart` | returns the closest instance **and** its distance; handles `Model` (uses pivot) and `BasePart`; empty list → `(nil, math.huge)` |
| WU-09 | `GetNearestPoint` | returns closest `Vector3` + distance; empty → `(nil, math.huge)` |
| WU-10 | `Cast` modes | `options.Mode = "Block"`/`"Sphere"` route to `Blockcast`/`Spherecast` (place a part only the wider volume would catch to distinguish from a thin ray) |
| WU-B1 | `WorldToScreen` / `ScreenToWorld` *(Tier B, client)* | with `workspace.CurrentCamera`: a point in front of the camera projects on-screen (`onScreen==true`) and round-trips approximately via `ScreenToWorld`; with `camera=nil` and no CurrentCamera → `(nil,false)` / `nil` |

---

## 6. Regression matrix
| Recent fix | Locked by |
|------------|-----------|
| **L2** `MathUtil.InverseLerp` `a==b` guard | MU-03 |

(The other recent fixes — Tag/InputUtil L3, SoundUtil/AnimationUtil — are out of this batch's scope.)

---

## 7. Suggested build order
1. **MathUtil** (§1) — pure; introduces `toBeCloseTo`/`approxVec` and the `@random` convention.
2. **StringUtil** (§2) and **TableUtil** (§3) — pure; fast.
3. **TweenUtil** (§4) — in-VM, `@timing`; introduces `Mocks.tempPart` cleanup.
4. **WorldUtil** (§5) — in-VM; introduces `Mocks.includeParams` + the test folder.
5. **WU-B1** — run client-side last (needs `CurrentCamera`).

## 8. Assumptions & risks
- **Floats:** never assert exact equality on `Lerp`/Bezier/trig/`Map`/spring results — use
  `toBeCloseTo`/`approxVec`. Integer-valued helpers (`RoundTo`, `FormatTime`, `AddCommas`) may assert
  exact.
- **Randomness (`@random`):** seed for outcome-specific assertions; otherwise assert invariants over
  several draws. `WeightedRandom` iteration order over a dict is unspecified — assert *membership*,
  not which equal-weight key wins.
- **WorldUtil determinism hinges on Include-filtered params** and a clean test folder; without them
  the baseplate/other geometry will pollute casts. Always parent test parts, `Anchored=true`, and
  destroy them in `afterEach`.
- **TweenUtil `@timing`:** use short durations and wait ≥ `2×` duration; spring settle time is
  approximate — assert "settled near target", not an exact frame. The module keeps global
  `TweenTemplates`/`ActiveStandardTweens` state — use unique template names per case (or clean up) so
  suites don't interfere.
- **`PrintUtil:Error` throws** (verified): the WorldUtil missing-params cases assert `toThrow`, not a
  `nil` return.
- Tier A here needs no API Services / players / network; only **WU-B1** uses the client camera.
