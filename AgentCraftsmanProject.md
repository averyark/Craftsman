# Craftsman Project Agent Instructions

This file is for agents operating in a project that uses Craftsman as its framework. It is not the internal Craftsman agent instructions file.

## Role
You are an AI coding assistant operating within a project that uses "Craftsman", a lightweight, modular Roblox framework. Your primary focus is producing decoupled, high-performance Luau code. You must prioritize clarity, execution speed, and absolute adherence to the architectural rules defined below. Do not generate explanatory fluff; provide direct code solutions.

## Tech Stack & Dependencies
* **Environment:** Roblox, Rojo, Wally
* **Core Packages:** * `Keeper` (Memory Management / Cleanup)
	* `Signal` (Decoupled Event Bus)
	* `Promise` (Asynchronous Control)
	* `ByteNet Max` (Buffer-based Networking)
	* `Reflex` (Client State Management)
	* `DocumentService` (Datastore Handling)

## Syntax & Style Standards
* **Typing:** The project operates in `nonstrict` mode.
* Prefer explicit types on function parameters and function definitions when the type is known, especially for exported APIs and callbacks. Skip the annotation if the property or member already implies the type.
* **Declarations:** Use `const` where applicable instead of `local` for static references.
* **Imports:** Utilize string-based paths for requires (e.g., `require("./ByteNet")`) as supported by the configured LSP.
* **Control Flow & Formatting:** * Keep logic strictly flat.
	* Use guard clauses and return early to avoid deep nesting.
	* Use `continue` within loops to bypass unneeded iterations.
	* Minimize nested `if` statements.
* **No Redundant Defense:** Do not over-engineer with unnecessary helper functions, redundant `assert()` checks, or `nil` guards for instances and parameters that are structurally guaranteed to exist by the framework's lifecycle or parent hierarchies.
* **String Formatting:** Prefer template-style interpolation `something {variable_name}` over `string.format`. Example: `local msg = "Hello {name}"` instead of `string.format("Hello %s", name)`.
* **For Loops:** Avoid using `pairs` or `ipairs` directly in `for` loop expressions. For arrays prefer numeric loops (`for i = 1, #arr do`) and for generic tables prefer `for k, v in tbl do`. This reduces allocations and keeps loops explicit.
* **Casing Rules:**
	* **Constant:** `SCREAMING_SNAKE_CASE` (e.g., `const MAX_RETRIES = 5`)
	* **Module Level Variable:** `PascalCase` (e.g., `local InternalCache = {}`)
	* **Module Level Variable:** `PascalCase` (e.g., `local function Print()`)
	* **Internal Method or Properties** `Underscore-prefixed PascalCase` (e.g., `self._NextDirection`, `function Class._GetNextFrame(self: Class) `)
	* **Exposed Variable or Function:** `PascalCase` (e.g., `Craftsman.Component`, `function Service:Start()`)
	* **Function Level Variable or Function:** `snake_case` (e.g., `  local target_player = nil`, `local function calculate_num(num1, num2, special_num)`)
* **Class Declaration Guide:** Declare the module table first, then the class table, then the exported type that references the constructor result. Use the module name in `typeof(...)` and type all methods against the exported class alias.

	```luau
    local QueueModule = {}

    local Queue = {}
    Queue.__index = Queue

    local function new(...)
        local self = setmetatable({}, Queue)
        -- ...
        return self
    end

    export type Queue = typeof(new(...))

    function Queue.Function(self: Queue, ...)
    end

    QueueModule.new = new
	```

## Architectural Rules

### 1. The Loader Lifecycle
Global singletons (Services/Controllers) do not manage their own execution. They are bootstrapped by a central loader using a strict two-phase lifecycle.
* `Module:Init()`: Runs synchronously. Use this strictly for defining initial state, caching references, and setting up signals. **Never yield here.**
* `Module:Start()`: Runs asynchronously via `task.spawn`. Use this for connecting loops, listening to external events, and executing active logic.

### 2. The Component Pattern
Instance-level logic is driven by `CollectionService`, not global loops.
* A Component is a class bound to a specific string tag.
* **Memory Management:** Every Component must create a `Keeper` object in its constructor.
* When you add owned objects to `Keeper`, wrap the object directly inside `Keeper:Add(...)` instead of creating it on a separate line first whenever the value is only needed for ownership.
* Call `self.Keeper:AttachToInstance(instance)` immediately so the component cleans itself up if the Roblox engine destroys the base part.
* All connections, temporary instances, and nested tables must be added to the Keeper.

### 3. Decoupling & Utilities
* **No Cross-Requiring:** Dynamic modules should not require each other directly to trigger actions. Use the global Signal bus to broadcast and listen for events.
* **Stateless Utilities:** Utility modules (Math, Sound, Input routing) must remain isolated, stateless, and completely separate from the `Init`/`Start` lifecycle. Require them directly in the files that need them.

### 4. Craftsman Utilities
* Prefer Craftsman's existing utility modules in `src/Utilities` before writing new helper logic.
* Use `StringUtil` for trimming, casing, template formatting, and rich text escaping.
* Use `TableUtil` for deep cloning, merging, key/value extraction, and emptiness checks.
* Use `MathUtil` for vector math, dot products, and angle calculations.
* Use `PrintUtil` for logging, warnings, and debug output.
* Use `AnimationUtil` for playing, stopping, and fading animations.
* Use `SoundUtil` for sound playback and sound lifecycle management.
* Use `InputUtil` for input handling and routing.
* Use `WorldUtil` for world, instance, and spatial helper logic.
* Require these utilities directly in the module that needs them; do not recreate their behavior inline unless the utility is missing or genuinely unsuitable.
