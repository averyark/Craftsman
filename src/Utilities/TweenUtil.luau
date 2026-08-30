--!nonstrict
--[[
    FileName    > TweenUtil.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 31/05/2026
--]]

const TweenService = game:GetService("TweenService")

const Promise = require("../../../../Promise")
const Spr = require("../../../../Spr")
const PrintUtil = require("./PrintUtil")
const TableUtil = require("./TableUtil")

--[=[
	@class TweenUtil
	A unified tweening utility that caches reusable animation templates and supports both Roblox TweenService and Spr spring physics.
]=]
--
local TweenUtil = {}

type EasingStyle = Enum.EasingStyle
type EasingDirection = Enum.EasingDirection
type PromiseLike = typeof(Promise.new(function() end))

local TweenTemplates = {}
local ActiveStandardTweens = setmetatable({}, { __mode = "k" })
local TweenToEntries = setmetatable({}, { __mode = "k" })

local function parse_properties(
	current_instance: Instance,
	properties: { [string]: any },
	target_animations: { { Instance: Instance, Properties: { [string]: any } } }
)
	--
	local direct_properties = {}

	for key, val in properties do
		if typeof(val) == "table" then
			--
			local child = current_instance:FindFirstChild(key)

			if child then
				parse_properties(child, val, target_animations)
				continue
			end
			--

			PrintUtil:Warn(`Child "{key}" not found on {current_instance.Name}!`)
		else
			direct_properties[key] = val
		end
	end
	--

	--
	if next(direct_properties) == nil then
		return
	end
	--

	--
	table.insert(target_animations, {
		Instance = current_instance,
		Properties = direct_properties,
	})
	--
end

local function snap_properties(current_instance: Instance, properties: { [string]: any })
	for key, val in properties do
		if typeof(val) == "table" then
			--
			local child = current_instance:FindFirstChild(key)

			if child then
				snap_properties(child, val)
				continue
			end
			--

			PrintUtil:Warn(`Child "{key}" not found on {current_instance.Name} during snap!`)
			continue
		end

		current_instance[key] = val
	end
end

local function create_mock_completed_event()
	local connections = {}
	local event = {}

	function event:Connect(callback)
		table.insert(connections, callback)
		local connection = {}
		function connection:Disconnect()
			local index = table.find(connections, callback)
			if index then
				table.remove(connections, index)
			end
		end
		return connection
	end

	function event:Once(callback)
		local connection
		connection = event:Connect(function(...)
			connection:Disconnect()
			callback(...)
		end)
		return connection
	end

	function event:Wait()
		local running = coroutine.running()
		local connection
		connection = event:Connect(function(...)
			connection:Disconnect()
			task.spawn(running, ...)
		end)
		return coroutine.yield()
	end

	return event,
		function(playback_state)
			for _, callback in connections do
				task.spawn(callback, playback_state)
			end
		end
end

local tween_group = {}
tween_group.__index = tween_group

local function create_tween_group(tweens: { Tween })
	local completed_event, fire_completed = create_mock_completed_event()

	local self = setmetatable({
		Tweens = tweens,
		_Connections = {},

		PlaybackState = Enum.PlaybackState.Playing,
		Completed = completed_event,
		_FireCompleted = fire_completed,
	}, tween_group)

	local remaining = #tweens
	local any_cancelled = false

	local function check_finished(state)
		--
		if self.PlaybackState ~= Enum.PlaybackState.Playing then
			return
		end
		if state == Enum.PlaybackState.Cancelled then
			any_cancelled = true
		end
		--

		--
		remaining = remaining - 1

		if remaining > 0 then
			return
		end
		--

		--
		self.PlaybackState = if any_cancelled then Enum.PlaybackState.Cancelled else Enum.PlaybackState.Completed

		fire_completed(self.PlaybackState)
		--
	end

	local connections = {}

	for _, tw in tweens do
		--
		local conn
		conn = tw.Completed:Connect(function(state)
			conn:Disconnect()
			check_finished(state)
		end)
		--

		table.insert(connections, conn)
	end

	return self
end

export type TweenGroup = typeof(create_tween_group(...))

function tween_group.Play(self: TweenGroup)
	--
	for _, tw in self.Tweens do
		tw:Play()
	end
	--
end

function tween_group.Cancel(self: TweenGroup)
	--
	if self.PlaybackState ~= Enum.PlaybackState.Playing then
		return
	end

	self.PlaybackState = Enum.PlaybackState.Cancelled
	--

	--
	for _, conn in self._Connections do
		conn:Disconnect()
	end
	for _, tw in self.Tweens do
		tw:Cancel()
	end
	--

	self._FireCompleted(Enum.PlaybackState.Cancelled)
end

function tween_group.Pause(self: TweenGroup)
	for _, tw in self.Tweens do
		tw:Pause()
	end
end


--[=[
	Registers a reusable animation template. Supports standard TweenService or Spr spring configurations.
	@param name string -- The name key for this template.
	@param style_or_type any -- EasingStyle (e.g. Quad), or "Spring" to use physics.
	@param properties { [string]: any } -- The properties target state.
	@param duration_or_damping number? -- Optional duration (for tweens) or damping ratio (for springs).
	@param direction_or_frequency any? -- Optional EasingDirection (for tweens) or undamped angular frequency (for springs).
	@return { [string]: any } -- The registered configuration dictionary.
]=]
--
function TweenUtil.new(
	name: string,
	style_or_type: any,
	properties: { [string]: any },
	duration_or_damping: number?,
	direction_or_frequency: any?
)
	--
	local config: { [string]: any } = {
		Properties = properties,
	}

	if style_or_type == "Spring" then
		config.Type = "Spring"
		config.Damping = duration_or_damping or 1.0
		config.Frequency = direction_or_frequency or 8.0
	else
		config.Type = "Tween"
		config.Style = style_or_type or Enum.EasingStyle.Quad
		config.Duration = duration_or_damping or 0.3
		config.Direction = direction_or_frequency or Enum.EasingDirection.Out
	end
	--

	--
	local existing_config = TweenTemplates[name]

	if not existing_config then
		TweenTemplates[name] = config
		return config
	end
	--

	--
	local is_match = true

	if config.Type ~= existing_config.Type then
		is_match = false
	elseif config.Type == "Spring" then
		if config.Damping ~= existing_config.Damping or config.Frequency ~= existing_config.Frequency then
			is_match = false
		end
	else
		if
			config.Style ~= existing_config.Style
			or config.Duration ~= existing_config.Duration
			or config.Direction ~= existing_config.Direction
		then
			is_match = false
		end
	end
	--

	--
	if is_match then
		if not TableUtil.EqualDeep(config.Properties, existing_config.Properties) then
			is_match = false
		end
	end

	if not is_match then
		PrintUtil:Error(
			`Template "{name}" already exists with different parameters or properties. Name clashes are not allowed.`
		)
	end

	PrintUtil:Warn(`Template "{name}" already exists with identical parameters. Ignoring new definition.`)

	return existing_config
	--
end

--[=[
	Removes all tracking entries for a tween from both ActiveStandardTweens and TweenToEntries.
	@private
]=]
--
local function cleanup_tween_tracking(tween)
	local entries = TweenToEntries[tween]
	if not entries then
		return
	end

	--
	for _, entry in entries do
		--
		local et = ActiveStandardTweens[entry.Instance]

		if not et or et[entry.Property] ~= tween then
			continue
		end
		--

		et[entry.Property] = nil

		--
		if next(et) ~= nil then
			continue
		end
		--

		ActiveStandardTweens[entry.Instance] = nil
	end
	--

	TweenToEntries[tween] = nil
end

--[=[
	Internal animation executor. Handles deduplication, tween/spring creation, and tracking.
	@private
	@param config { [string]: any } -- The animation configuration dictionary.
	@param instance Instance -- The target Roblox instance to animate.
	@return Tween? -- The created Roblox Tween object (if standard tween), or nil (if spring).
]=]
--
local function play_config(config: { [string]: any }, instance: Instance): Tween
	local target_animations = {}
	parse_properties(instance, config.Properties, target_animations)

	--
	local active_tweens_to_cancel = {}

	for _, anim in target_animations do
		local anim_instance = anim.Instance
		local anim_properties = anim.Properties

		for property_name, property_value in anim_properties do
			--
			Spr.stop(anim_instance, property_name)
			--

			--
			local inst_tbl = ActiveStandardTweens[anim_instance]
			local existing_tween = inst_tbl and inst_tbl[property_name]

			if not existing_tween then
				continue
			end
			--

			active_tweens_to_cancel[existing_tween] = true

		end
	end
	--

	--
	for existing_tween in active_tweens_to_cancel do
		existing_tween:Cancel()
		cleanup_tween_tracking(existing_tween)
	end
	--

	--
	if config.Type == "Spring" then
		for _, anim in target_animations do
			Spr.target(anim.Instance, config.Damping, config.Frequency, anim.Properties)
		end
		return nil :: any
	end
	--

	local tween_info = TweenInfo.new(config.Duration, config.Style, config.Direction)
	local tweens = {}

	for _, anim in target_animations do
		--
		local tween = TweenService:Create(anim.Instance, tween_info, anim.Properties)
		table.insert(tweens, tween)
		--

		--
		local inst_tbl = ActiveStandardTweens[anim.Instance]

		if not inst_tbl then
			inst_tbl = {}
			ActiveStandardTweens[anim.Instance] = inst_tbl
		end
		--

		--
		if not TweenToEntries[tween] then
			TweenToEntries[tween] = {}
		end

		for property_name, property_value in anim.Properties do
			inst_tbl[property_name] = tween
			table.insert(TweenToEntries[tween], { Instance = anim.Instance, Property = property_name })
		end
		--

		--
		local connection
		connection = tween.Completed:Connect(function()
			connection:Disconnect()
			cleanup_tween_tracking(tween)
		end)
		--
	end

	--
	if #tweens == 0 then
		return nil :: any
	end

	if #tweens == 1 then
		tweens[1]:Play()
		return tweens[1]
	end

	local group = create_tween_group(tweens)
	group:Play()

	return group :: any
	--
end

--[=[
	Plays a registered template on the specified instance with unified standard tween and spring deduplication.
	@param name string -- The template name to play.
	@param instance Instance -- The target Roblox instance to animate.
	@return Tween? -- The created Roblox Tween object (if standard tween), or nil (if spring).
]=]
--
function TweenUtil.Play(name: string, instance: Instance): Tween
	--
	local template = TweenTemplates[name]

	if not template then
		PrintUtil:Warn(`Template "{name}" not found!`)
		return nil :: any
	end
	--

	return play_config(template, instance)
end

--[=[
	Snaps target properties to starting values instantly, then plays the template to animate them to target state.
	@param name string -- The template name.
	@param instance Instance -- The target Roblox instance.
	@param start_properties { [string]: any } -- Starting property overrides to snap to first.
	@return Tween? -- The created standard Tween object, or nil if spring.
]=]
--
function TweenUtil.PlayFrom(name: string, instance: Instance, start_properties: { [string]: any }): Tween?
	snap_properties(instance, start_properties)
	return TweenUtil.Play(name, instance)
end

--[=[
	Stops any active spring and cancels any active standard tweens driving specified instance properties.
	@param instance Instance -- The target instance.
	@param property string? -- Optional specific property. If omitted, stops all animations on this instance.
]=]
--
function TweenUtil.Stop(instance: Instance, property: string?)
	if property then
		Spr.stop(instance, property)

		--
		local inst_tbl = ActiveStandardTweens[instance]

		if not inst_tbl then
			return
		end
		--

		--
		local tween = inst_tbl[property]

		if not tween then
			return
		end
		--

		--
		tween:Cancel()
		cleanup_tween_tracking(tween)
		--
		return
	end

	--
	Spr.stop(instance)

	for _, descendant in instance:GetDescendants() do
		Spr.stop(descendant)
	end
	--

	--
	local keys_to_stop = {}

	for active_inst, inst_tbl in ActiveStandardTweens do
		--
		local is_descendant = false

		pcall(function()
			is_descendant = active_inst == instance or active_inst:IsDescendantOf(instance)
		end)

		if not is_descendant then
			continue
		end
		--

		table.insert(keys_to_stop, active_inst)
	end
	--

	--
	for _, active_inst in keys_to_stop do
		--
		local inst_tbl = ActiveStandardTweens[active_inst]

		if not inst_tbl then
			continue
		end
		--

		local cancelled = {}

		for prop, tween in inst_tbl do
			--
			if cancelled[tween] then
				continue
			end
			--

			--
			tween:Cancel()
			cancelled[tween] = true
			TweenToEntries[tween] = nil
			--
		end

		--
		ActiveStandardTweens[active_inst] = nil
		--
	end
	--
end

--[=[
	Plays a tween immediately on the target instance with the specified duration, style, direction, and properties.
	Arguments can be provided in any order (after the instance):
	- QuickPlay(instance, properties, duration?, style?, direction?)
	- QuickPlay(instance, duration?, style?, direction?, properties)
	@param instance Instance -- The target Roblox instance.
	@param ... any -- Additional optional parameters (duration, style, direction, properties).
	@return Tween? -- The created Tween object (or tween group), or nil.
]=]
--
function TweenUtil.QuickPlay(instance: Instance, ...: any): Tween
	--
	local args = { ... }
	local properties: { [string]: any }?
	local duration: number?
	local style: any?
	local direction: any?
	--

	--
	for _, arg in args do
		if type(arg) == "number" then
			duration = arg
		elseif type(arg) == "table" then
			properties = arg
		elseif typeof(arg) == "EnumItem" then
			if arg.EnumType == Enum.EasingStyle then
				style = arg
			elseif arg.EnumType == Enum.EasingDirection then
				direction = arg
			end
		end
	end
	--

	--
	if typeof(instance) ~= "Instance" then
		PrintUtil:Error("TweenUtil.QuickPlay: First argument must be an Instance")
	end

	if type(properties) ~= "table" then
		PrintUtil:Error("TweenUtil.QuickPlay: Properties table is required")
	end
	--

	--
	return play_config({
		Type = "Tween",
		Properties = properties,
		Style = style or Enum.EasingStyle.Quad,
		Duration = duration or 0.3,
		Direction = direction or Enum.EasingDirection.Out,
	}, instance)
	--
end

return TweenUtil
