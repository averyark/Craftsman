# Scope
This file defines how Craftsman code is written: formatting, comments, naming and typing. It does not cover how to use the framework; that lives in the `craftsman-kit` skill at `skills/craftsman-kit/`.

Before writing, reviewing or changing code that uses a Craftsman module, read `skills/craftsman-kit/SKILL.md` and the reference files it links for the modules involved. When a change alters a public API, update the matching `skills/craftsman-kit/references/*.md` in the same change.

# Syntax & Style
* **Typing:** `strict` mode (`--!strict` directive on line 1). The bar is zero diagnostics under Luau's new type solver: run `scripts/analyze.ps1`.
* **Vars:** Use `const` for static references instead of `local`.
* **Imports:** Use string-based paths (e.g., `require("./ByteNet")`).
* **Formatting:** Flat logic. Return early. Use `continue` in loops. Minimize nested `if`s.
* **Guard Clauses (MANDATORY):** Invert every condition that wraps the body of a function or loop. Handle the reject case first and bail — `return`, `continue`, or `break` — then let the real work sit at the outermost indent level. Never wrap the body in an `if`. Elegance is measured in nesting depth: aim for one level, never accept a level you could have inverted away. `else` is a smell; a guard clause almost always removes it.
  * **DO:**
  * ```lua
    for player, score in self.Scores do
        if score.Kills ~= best_kills then
            continue
        end

        table.insert(winners, player)
    end
    ```
  * **DO NOT:**
  * ```lua
    for player, score in self.Scores do
        if score.Kills == best_kills then
            table.insert(winners, player)
        end
    end
    ```
* **Defense:** Do not use redundant `assert()` or `nil` guards for framework-guaranteed instances.
* **Strings:** Use backtick template interpolation: ``` `Hello {name}` ```. Do not use `string.format` or `..` concatenation.
* **Loops:** Always use generalized iteration: `for _, v in arr do` and `for k, v in tbl do`. NEVER write `for i = 1, #arr do` — index only when the index itself is used. Avoid `pairs`/`ipairs`.
* **Comments & Spacing:** See the dedicated section below. Comments are visual structural boundaries, never prose.

# Comments & Code Separation

Comments are **visual structural delimiters and nothing else**. Code is a stack of fenced, single-purpose phases separated by blank lines. Reading any function top to bottom, every phase is visually bounded before a single line of logic is read.

**Reference implementation:** `src/StateMachine/Client.luau`. When in doubt, match it exactly.

## The Bare `--` Rule
* A comment is a **bare `--` on its own line**. Nothing follows it. Ever.
* **NEVER** write a comment that explains, describes, justifies, or names anything. No prose. No rationale. No "why". No summaries above functions. No `TODO`/`NOTE` narration.
* **NEVER** use trailing comments at the end of code lines.
* If code feels like it needs an explanation, restructure the code or put explanations in an external markdown file.
* The **only** exceptions in any file are:
  1. The top directive: `--!strict`
  2. The standard file header block (`--[[ FileName > ... --]]`)

## Fences
A fence is a pair of bare `--` lines around **one logical phase**, at the **exact same indentation level** as the enclosed code.

1. **Opening `--`:** directly above the first line of the phase. Zero blank lines after it.
2. **Closing `--`:** directly below the last line of the phase. Zero blank lines before it.
3. **Between fences:** exactly one blank line.
4. **Never two consecutive blank lines**, anywhere in the file.
5. **Never a mid-block `--` divider.** To split sub-groups inside one fence, use a blank line.
6. **Fences never nest.** A fence never contains another fence, whether directly or through a callback, loop or branch body. Fence the statement *or* the phases inside its body, never both.
7. **Top-level functions are not fenced.** Fences live inside function bodies and around top-level declaration groups only.

```
	--              <- opening fence (flush against first statement)
	code

	code            <- blank line splits sub-groups inside the phase
	--              <- closing fence (flush against last statement)
                    <- exactly one blank line
	--
	code
	--
                    <- exactly one blank line
	return value    <- bare tail statement
```

## Blank Lines
Blank lines are the second tier of separation. They split the parts of one phase from each other.

* **Binding → check:** one blank line between a statement that produces a value and the `if` that checks it.
  * **DO:**
  * ```lua
    	const current = machine:GetCurrent()

    	if current == nil then
    		return nil
    	end
    ```
  * **DO NOT:**
  * ```lua
    	const current = machine:GetCurrent()
    	if current == nil then
    		return nil
    	end
    ```
* **Guard → guard:** consecutive lookup/guard pairs in one fence are separated by one blank line.
* **Sub-groups:** related statements that belong to the same phase but do different things (a pair of assignments, a call, a cache init) are separated by one blank line inside the fence.
* **Between functions:** exactly one blank line.
* **Before a bare tail:** exactly one blank line between the last closing `--` and the final statement.

## What Goes In One Fence
A fence holds one phase: validate, resolve, compute, mutate, connect, or dispatch.

* **Same subject, same fence.** Guards that validate the same input chain together in one fence, separated by blank lines:
  ```lua
  function Client.Register(self: Client, machine: Machine): boolean
  	--
  	if not machine then
  		return false
  	end

  	const machine_id = machine:GetId()

  	if type(machine_id) ~= "string" then
  		return false
  	end

  	const existing_machine = MachinesById[machine_id]

  	if existing_machine and existing_machine ~= machine then
  		return false
  	end
  	--

  	--
  	MachinesById[machine_id] = machine
  	MachineIdsByMachine[machine] = machine_id

  	ensure_client_connection(machine, machine_id)

  	CachedStatesByMachine[machine] = CachedStatesByMachine[machine] or {}
  	--

  	--
  	if Started then
  		request_state(machine_id, machine)
  	end
  	--

  	return true
  end
  ```
* **Different concern, different fence.** A once-guard and an environment check are separate phases:
  ```lua
  function Client.Init(self: Client)
  	--
  	if Initialized then
  		return
  	end

  	Initialized = true
  	--

  	--
  	if not RunService:IsClient() or StateMachineConfig.ENABLED == false then
  		return
  	end
  	--
  ```
* **A one-line phase is still a phase.** A lone statement that is a step of its own in the middle of a function gets its own fence (see `request_state` in `Client.Sync`).
* **Bare tail.** The function's **final single statement** may sit unfenced, one blank line below the last closing `--`. This is either a `return` or one terminal call. Two or more statements make a phase, and a phase gets fenced.
* **No phases, no fences.** A function whose body is a single `return` expression has no fences at all:
  ```lua
  local function build_payload(machine: Machine, machine_id: string, context: any?): Network.MachinePayload
  	return {
  		Id = machine_id,
  		State = get_current_name(machine),
  		Running = machine:IsRunning(),
  	}
  end
  ```

## Function Layout
* No outer fence. One blank line between functions.
* When the body has fences, the first `\t--` sits on the line immediately after the signature, with no blank line before or after it.
* The final statement is either the last closing `--` or a bare tail one blank line below it.

```lua
local function get_current_name(machine: Machine): string?
	--
	const current = machine:GetCurrent()

	if current == nil then
		return nil
	end
	--

	return current.Name
end

local function resolve_payload_id(payload: unknown): string?
	--
	if type(payload) ~= "table" then
		return nil
	end
	--

	--
	const fields = payload :: { [string]: unknown }
	const payload_id = fields.Id or fields.id

	if type(payload_id) ~= "string" then
		return nil
	end
	--

	return payload_id
end
```

## Callbacks, Loops & Branches (One Fence Level)
Because fences never nest, pick exactly one level for each statement that owns a body:

* **Multi-phase body:** leave the wrapping statement bare, and fence the phases inside the body.
  ```lua
  	Network.packets.MachineUpdated.listen(function(payload)
  		--
  		const payload_id = resolve_payload_id(payload)

  		if payload_id == nil then
  			return
  		end

  		const machine = MachinesById[payload_id]

  		if machine == nil then
  			return
  		end
  		--

  		--
  		apply_payload(machine, payload)
  		--
  	end)
  ```
  ```lua
  local function request_state(machine_id: string, machine: Machine)
  	task.spawn(function()
  		--
  		const ok, payload = pcall(function()
  			return Network.queries.RequestState.invoke(machine_id)
  		end)

  		if not ok or type(payload) ~= "table" then
  			return
  		end
  		--

  		apply_payload(machine, payload)
  	end)
  end
  ```
* **Single-phase body:** fence the whole statement and leave its body bare. Inside the body, still separate guards and actions with blank lines.
  ```lua
  	--
  	ClientConnectionsByMachine[machine] = machine.Transitioned:Connect(
  		function(_machine, _previous, _current, context, _source)
  			if _source == SERVER_SOURCE then
  				return
  			end

  			const payload = build_payload(_machine, machine_id, context)
  			Network.packets.ClientMachineUpdated.send(payload)
  		end
  	)
  	--
  ```
  ```lua
  	--
  	for machine_id, machine in MachinesById do
  		ensure_client_connection(machine, machine_id)
  		request_state(machine_id, machine)
  	end
  	--
  ```
* **Multi-phase loop body:** the same rule applies. The `for` stays bare and its phases are fenced at the inner indent:
  ```lua
  	for _, character in Gameplay.EntityFolder:GetChildren() do
  		--
  		if not is_valid_target(character) then
  			continue
  		end

  		const aim_part = get_aim_part(character)

  		if not aim_part then
  			continue
  		end
  		--

  		--
  		const angle, distance = get_angle_to(cam_cf, aim_part.Position)

  		if distance > MAX_TARGET_DISTANCE then
  			continue
  		end
  		--

  		--
  		best_score = angle
  		best_character = character
  		--
  	end
  ```

## Instance Construction & UI Hierarchy
Blocks that instantiate, style and parent instances form one phase and share one fence. Sibling instances are separated by blank lines inside it:

```lua
	--
	const ring = Instance.new("Frame")
	ring.Name = "Window"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.BackgroundTransparency = 1
	ring.Parent = gui

	const corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ring
	--
```

## Module-Level Layout
1. **Header & requires (unfenced):** `--!strict` on line 1, the header block, one blank line, services (`const`), one blank line, requires, one blank line, then the module table (`local Module = {}`).
2. **Top-level declaration groups (fenced):** each group gets its own fence, one blank line apart. Examples are types, config and lifecycle flags, registries, public signals, tuning tables, and player/GUI singletons. A blank line inside a fence splits sub-groups:
   ```lua
   local Client = {}

   --
   type Client = typeof(Client)

   type ClientConfig = {
   	ENABLED: boolean?,
   	AUTO_START_CLIENT: boolean?,
   }
   --

   --
   const StateMachineConfig = (Config.STATE_MACHINE or {}) :: ClientConfig
   local Initialized = false
   local Started = false
   --

   --
   export type Machine = Types.Machine

   const MachinesById = ...
   const MachineIdsByMachine = ...

   const SERVER_SOURCE = newproxy(false)
   const LastSequenceByMachine = ...
   --
   ```
3. **Functions (unfenced):** one blank line apart.
4. **Export:** `return Module` one blank line below the last `end`. Never fenced.

## Lifecycle Methods (`:Init()` & `:Start()`)
Lifecycle methods follow the same function layout, with no outer fence. A run of one-line listener registrations is one phase. A registration with a multi-phase callback stays bare, and its callback body is fenced.

```lua
function TutorialServer:Init()
	--
	TutorialNetwork.packets.Request.listen(handle_request)
	TutorialNetwork.packets.SpawnClicked.listen(handle_spawn_clicked)
	TutorialNetwork.packets.ClaimCase.listen(handle_claim_case)
	--
end

function TutorialServer:Start()
	--
	Players.PlayerAdded:Connect(function(player)
		TutorialServer.Sync(player)
	end)
	--
end
```

## Complete File Skeleton

```lua
--!strict
--[[
    FileName    > ExampleController.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > DD/MM/YYYY
--]]

const Players = game:GetService("Players")
const RunService = game:GetService("RunService")

const Craftsman = require("@game/ReplicatedStorage/Packages/Craftsman")
const Weapon = require("./Weapon")

local ExampleController = { Dependencies = { Weapon } }

--
type ExampleController = typeof(ExampleController)
--

--
const Player = Players.LocalPlayer
const PlayerGui = Player:WaitForChild("PlayerGui")
--

--
const MAX_RANGE = 120
const CHECK_INTERVAL = 1 / 60
--

--
local IsActive = false
local LastCheck = 0
--

local function get_weapon_context()
	--
	if not IsActive then
		return nil
	end
	--

	--
	const weapon = Weapon:GetEquippedWeapon()

	if not weapon or not weapon.IsEquipped then
		return nil
	end
	--

	return weapon
end

local function step(dt: number)
	--
	const now = os.clock()

	if now - LastCheck < CHECK_INTERVAL then
		return
	end

	LastCheck = now
	--

	--
	const weapon = get_weapon_context()

	if not weapon then
		return
	end

	const target = weapon:GetAimTarget()

	if not target then
		return
	end
	--

	weapon:Process(target, dt)
end

function ExampleController:Init()
	--
	IsActive = true
	LastCheck = 0
	--
end

function ExampleController:Start()
	--
	RunService.Heartbeat:Connect(step)
	--
end

return ExampleController
```

# Casing Rules
| Element | Case | Example |
| :--- | :--- | :--- |
| Constant | `SCREAMING_SNAKE_CASE` | `const MAX_RETRIES = 5` |
| Module Var/Func | `PascalCase` | `local InternalCache = {}` |
| Exposed Var/Func | `PascalCase` | `Craftsman.Component` |
| Local Var/Func | `snake_case` | `local target_player = nil` |
| Global Var/Func | `PascalCase` | `local WeaponsController = ...` |
