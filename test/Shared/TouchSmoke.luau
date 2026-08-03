--!nonstrict
--[[
    FileName    > TouchSmoke.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 03/08/2026
--]]

const Players = game:GetService("Players")

const Craftsman = require("@game/ReplicatedStorage/Packages/Craftsman")

local TouchSmoke = {}

--
local function assert_equal(label: string, got: any, expected: any)
	if got == expected then
		return
	end

	error(`TouchSmoke: {label} -- got {tostring(got)}, expected {tostring(expected)}`, 0)
end
--

--
local function run_action_sources(context: string)
	local InputUtil = Craftsman.InputUtil

	local began = 0
	local ended = 0

	local began_connection = InputUtil.Began:Connect(function(action_name)
		if action_name ~= "SmokeAction" then
			return
		end
		began += 1
	end)

	local ended_connection = InputUtil.Ended:Connect(function(action_name)
		if action_name ~= "SmokeAction" then
			return
		end
		ended += 1
	end)

	local source_a = newproxy()
	local source_b = newproxy()

	InputUtil.SetActionState("SmokeAction", true, source_a)
	InputUtil.SetActionState("SmokeAction", true, source_a)
	InputUtil.SetActionState("SmokeAction", true, source_b)

	assert_equal("Began fires once for two sources", began, 1)
	assert_equal("action is active while held", InputUtil.IsActionActive("SmokeAction"), true)

	InputUtil.SetActionState("SmokeAction", false, source_a)

	assert_equal("Ended does not fire while a source holds", ended, 0)
	assert_equal("action stays active on partial release", InputUtil.IsActionActive("SmokeAction"), true)

	InputUtil.SetActionState("SmokeAction", false, source_b)

	assert_equal("Ended fires on last release", ended, 1)
	assert_equal("action is inactive once released", InputUtil.IsActionActive("SmokeAction"), false)

	began_connection:Disconnect()
	ended_connection:Disconnect()

	print(`[TouchSmoke/{context}] action sources refcount correctly`)
end
--

--
local function run_bindings(context: string)
	local InputUtil = Craftsman.InputUtil

	InputUtil.SetPrimitiveBinding("SmokeBind", { Enum.KeyCode.Q })
	assert_equal("primitive binds when unbound", InputUtil.GetBinding("SmokeBind")[1], Enum.KeyCode.Q)

	InputUtil.BindAction("SmokeBind", { Enum.KeyCode.E })
	assert_equal("rebind takes effect", InputUtil.GetBinding("SmokeBind")[1], Enum.KeyCode.E)

	InputUtil.ResetBinding("SmokeBind")
	assert_equal("reset restores the primitive", InputUtil.GetBinding("SmokeBind")[1], Enum.KeyCode.Q)

	InputUtil.UnbindAction("SmokeBind")
	assert_equal("unbind clears the binding", InputUtil.GetBinding("SmokeBind"), nil)

	print(`[TouchSmoke/{context}] bindings rebind and reset`)
end
--

--
local function run_gating(context: string)
	local TouchUtil = Craftsman.TouchUtil

	local button = TouchUtil.Button("SmokeGate", {
		Text = "Gate",
		Zone = "TopLeft",
		ShowOn = { "KeyboardMouse", "Gamepad", "Touch" },
		VisibleWhen = { SmokeContext = true },
	})

	assert_equal("button starts hidden with its context off", button.Instance.Visible, false)

	TouchUtil.SetContext("SmokeContext", true)
	assert_equal("context on reveals the button", button.Instance.Visible, true)

	button:SetEnabled(false)
	assert_equal("disabled button keeps its layout slot", button.Instance.Visible, true)
	button:SetEnabled(true)

	button:SetVisible(false)
	assert_equal("explicit hide wins over context", button.Instance.Visible, false)
	button:SetVisible(true)

	button:SetShowOn({ "Gamepad" })
	assert_equal("device gate hides off-device", button.Instance.Visible, false)

	TouchUtil.SetContext("SmokeContext", false)
	assert_equal("button is registered against its action", #TouchUtil.GetButtons("SmokeGate"), 1)

	local instance = button.Instance
	button:Destroy()

	assert_equal("destroy unparents the button", instance.Parent, nil)
	assert_equal("destroy deregisters the button", #TouchUtil.GetButtons("SmokeGate"), 0)

	print(`[TouchSmoke/{context}] buttons gate on device and context, and clean up`)
end
--

--
local function run_layout(context: string)
	local TouchUtil = Craftsman.TouchUtil

	task.wait()

	local button = TouchUtil.Button("SmokeLayout", {
		Text = "Lay",
		Zone = "Top",
		Size = 70,
		LayoutId = "smoke.layout",
		ShowOn = { "KeyboardMouse", "Gamepad", "Touch" },
	})

	assert_equal("a fresh button is not customised", button.IsCustomised, false)
	assert_equal(
		"an uncustomised button is omitted from the layout",
		TouchUtil.GetLayout().Entries["smoke.layout"],
		nil
	)

	button:ApplyLayout({ Position = { X = 0.25, Y = 0.75 }, Scale = 90 / 70 })

	assert_equal("applying a layout marks the button customised", button.IsCustomised, true)
	assert_equal("applying a layout resizes", button:GetLayout().Scale * 70, 90)
	assert_equal("applying a layout leaves the zone", button.Zone, nil)

	local saved = TouchUtil.GetLayout()

	assert_equal("a customised button appears in the layout", saved.Entries["smoke.layout"].Scale, 90 / 70)
	assert_equal("the layout carries a version", saved.Version, 2)

	assert_equal("a mismatched version is rejected", TouchUtil.ApplyLayout({ Version = 999, Entries = {} }), false)
	assert_equal("a malformed layout is rejected", TouchUtil.ApplyLayout({} :: any), false)

	button:ResetLayout()

	assert_equal("reset restores the default size", button:GetLayout().Scale, 1)
	assert_equal("reset returns the button to its zone", button.Zone, "Top")
	assert_equal("reset clears the customised flag", button.IsCustomised, false)

	assert_equal("a saved layout reapplies", TouchUtil.ApplyLayout(saved), true)
	assert_equal("reapplying restores the size", button:GetLayout().Scale, 90 / 70)

	button:ApplyLayout({ Position = { X = 5, Y = -5 } })

	local clamped = button:GetLayout().Position

	assert_equal("clamped off-screen X stays on screen", clamped.X < 1, true)
	assert_equal("clamped off-screen Y stays on screen", clamped.Y > 0, true)

	assert_equal("lookup by layout id finds the button", TouchUtil.GetButton("smoke.layout"), button)

	TouchUtil.SetEditMode(true)
	assert_equal("edit mode reports on", TouchUtil.IsEditMode(), true)
	assert_equal("edit mode sinks input on a movable button", button.Instance.Active, true)

	TouchUtil.SetEditMode(false)
	assert_equal("edit mode reports off", TouchUtil.IsEditMode(), false)
	assert_equal("leaving edit mode restores sinking", button.Instance.Active, false)

	button:Destroy()
	assert_equal("destroy frees the layout id", TouchUtil.GetButton("smoke.layout"), nil)

	print(`[TouchSmoke/{context}] layouts serialize, clamp, reset and round-trip`)
end
--

--
local function build_edit_toggle(context: string)
	local TouchUtil = Craftsman.TouchUtil

	local screen = Instance.new("ScreenGui")
	screen.Name = "TouchSmokeEditToggle"
	screen.ResetOnSpawn = false
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local toggle = Instance.new("TextButton")
	toggle.Name = "Toggle"
	toggle.AnchorPoint = Vector2.new(0.5, 0)
	toggle.Position = UDim2.new(0.5, 0, 0, 12)
	toggle.Size = UDim2.fromOffset(150, 36)
	toggle.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	toggle.TextColor3 = Color3.fromRGB(235, 235, 235)
	toggle.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
	toggle.TextSize = 16
	toggle.Text = "Edit layout"
	toggle.Parent = screen

	toggle.Activated:Connect(function()
		TouchUtil.SetEditMode(not TouchUtil.IsEditMode())
	end)

	TouchUtil.EditModeChanged:Connect(function(enabled: boolean)
		local jump = TouchUtil.GetJumpButton()

		if jump then
			print(`[TouchSmoke/{context}] jump instance is now {jump.Instance.Name} under {jump.Instance.Parent.Name}`)
		end

		toggle.Text = if enabled then "Done" else "Edit layout"
		print(`[TouchSmoke/{context}] edit mode {if enabled then "on" else "off"}`)
	end)

	TouchUtil.LayoutChanged:Connect(function(layout_id: string, entry)
		local position = entry.Position
		local where = if position
			then `{string.format("%.3f", position.X)}, {string.format("%.3f", position.Y)}`
			else "in zone"
		print(`[TouchSmoke/{context}] {layout_id} moved to ({where}) at size {entry.Size}`)
	end)
end
--

--
const DEMO_BUTTONS = {
	{ action = "SmokeDemoA", text = "A", order = 1 },
	{ action = "SmokeDemoB", text = "B", order = 2 },
	{ action = "SmokeDemoC", text = "C", order = 3 },
	{ action = "SmokeDemoIcon", order = 4, overlay = "rbxassetid://92995853558775" },
}

local function run_demo_pad(context: string)
	local TouchUtil = Craftsman.TouchUtil
	local InputUtil = Craftsman.InputUtil

	for i = 1, #DEMO_BUTTONS do
		local entry = DEMO_BUTTONS[i]

		TouchUtil.Button(entry.action, {
			Text = entry.text,
			Overlay = entry.overlay,
			Zone = "BottomRight",
			Order = entry.order,
			ShowOn = { "KeyboardMouse", "Gamepad", "Touch" },
		})
	end

	local jump = TouchUtil.AdoptJumpButton()

	if jump then
		print(`[TouchSmoke/{context}] jump adopted, still parented to {jump.Instance.Parent.Name}`)
	else
		print(`[TouchSmoke/{context}] no CoreGui jump button to adopt`)
	end

	InputUtil.Began:Connect(function(action_name)
		if not action_name:find("SmokeDemo") then
			return
		end
		print(`[TouchSmoke/{context}] {action_name} began`)
	end)

	InputUtil.Ended:Connect(function(action_name)
		if not action_name:find("SmokeDemo") then
			return
		end
		print(`[TouchSmoke/{context}] {action_name} ended`)
	end)

	local root = TouchUtil.GetRoot()
	local scale = root:FindFirstChildOfClass("UIScale")

	print(`[TouchSmoke/{context}] device reads: {InputUtil.GetDeviceType()}`)
	print(`[TouchSmoke/{context}] viewport: {workspace.CurrentCamera.ViewportSize}`)
	print(`[TouchSmoke/{context}] UIScale: {if scale then scale.Scale else "none"}`)
	print(
		`[TouchSmoke/{context}] {#DEMO_BUTTONS} demo buttons in BottomRight -- tap them, each should print began/ended`
	)

	task.wait(1)
	TouchUtil.DebugLayout()
end
--

function TouchSmoke.Run(context: string)
	run_action_sources(context)
	run_bindings(context)

	if not game:GetService("RunService"):IsClient() then
		print(`[TouchSmoke/{context}] InputUtil required on the server without throwing`)
		return
	end

	run_gating(context)
	run_layout(context)
	run_demo_pad(context)
	build_edit_toggle(context)
end

return TouchSmoke
