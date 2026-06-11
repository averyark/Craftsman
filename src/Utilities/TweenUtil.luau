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
local temp_counter = 0

local function parse_properties(
	current_instance: Instance,
	properties: { [string]: any },
	target_animations: { { Instance: Instance, Properties: { [string]: any } } }
)
	local direct_properties = {}
	for key, val in properties do
		if typeof(val) == "table" then
			local child = current_instance:FindFirstChild(key)
			if child then
				parse_properties(child, val, target_animations)
			else
				PrintUtil:Warn(`Child "{key}" not found on {current_instance.Name}!`)
			end
		else
			direct_properties[key] = val
		end
	end
	if next(direct_properties) ~= nil then
		table.insert(target_animations, {
			Instance = current_instance,
			Properties = direct_properties,
		})
	end
end

local function snap_properties(current_instance: Instance, properties: { [string]: any })
	for key, val in properties do
		if typeof(val) == "table" then
			local child = current_instance:FindFirstChild(key)
			if child then
				snap_properties(child, val)
			else
				PrintUtil:Warn(`Child "{key}" not found on {current_instance.Name} during snap!`)
			end
		else
			(current_instance :: any)[key] = val
		end
	end
end

local function create_mock_completed_event()
	local connections = {}
	local event = {}
	function event:Connect(callback)
		table.insert(connections, callback)
		return {
			Disconnect = function()
				local index = table.find(connections, callback)
				if index then
					table.remove(connections, index)
				end
			end,
		}
	end
	return event,
		function(playback_state)
			for _, callback in ipairs(connections) do
				task.spawn(callback, playback_state)
			end
		end
end

local function create_tween_group(tweens: { Tween })
	local self = {}
	self.PlaybackState = Enum.PlaybackState.Playing

	local completed_event, fire_completed = create_mock_completed_event()
	self.Completed = completed_event

	local remaining = #tweens
	local any_cancelled = false

	local function check_finished(state)
		if self.PlaybackState ~= Enum.PlaybackState.Playing then
			return
		end
		if state == Enum.PlaybackState.Cancelled then
			any_cancelled = true
		end
		remaining = remaining - 1
		if remaining <= 0 then
			self.PlaybackState = if any_cancelled then Enum.PlaybackState.Cancelled else Enum.PlaybackState.Completed
			fire_completed(self.PlaybackState)
		end
	end

	local connections = {}
	for _, tw in ipairs(tweens) do
		local conn
		conn = tw.Completed:Connect(function(state)
			conn:Disconnect()
			check_finished(state)
		end)
		table.insert(connections, conn)
	end

	function self:Play()
		for _, tw in ipairs(tweens) do
			tw:Play()
		end
	end

	function self:Cancel()
		if self.PlaybackState ~= Enum.PlaybackState.Playing then
			return
		end
		self.PlaybackState = Enum.PlaybackState.Cancelled
		for _, conn in ipairs(connections) do
			conn:Disconnect()
		end
		for _, tw in ipairs(tweens) do
			tw:Cancel()
		end
		fire_completed(Enum.PlaybackState.Cancelled)
	end

	function self:Pause()
		for _, tw in ipairs(tweens) do
			tw:Pause()
		end
	end

	return self
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
	local config = {
		Properties = properties,
	}

	if style_or_type == "Spring" then
		config.Type = "Spring"
		config.Damping = duration_or_damping or 1.0
		config.Frequency = direction_or_frequency or 8.0
		TweenTemplates[name] = config
		return config
	end

	config.Type = "Tween"
	config.Style = style_or_type or Enum.EasingStyle.Quad
	config.Duration = duration_or_damping or 0.3
	config.Direction = direction_or_frequency or Enum.EasingDirection.Out

	TweenTemplates[name] = config
	return config
end

--[=[
	Plays a registered template on the specified instance with unified standard tween and spring deduplication.
	@param name string -- The template name to play.
	@param instance Instance -- The target Roblox instance to animate.
	@return Tween? -- The created Roblox Tween object (if standard tween), or nil (if spring).
]=]
--
function TweenUtil.Play(name: string, instance: Instance): Tween
	local template = TweenTemplates[name]
	if not template then
		PrintUtil:Warn(`Template "{name}" not found!`)
		return nil :: any
	end

	local target_animations = {}
	parse_properties(instance, template.Properties, target_animations)

	-- Unified Deduplication: stop any springs and cancel any active standard tweens driving target properties
	local active_tweens_to_cancel = {}
	for _, anim in target_animations do
		local anim_instance = anim.Instance
		local anim_properties = anim.Properties

		for property_name in anim_properties do
			Spr.stop(anim_instance, property_name)

			local inst_tbl = ActiveStandardTweens[anim_instance]
			local existing_tween = inst_tbl and inst_tbl[property_name]
			if not existing_tween then
				continue
			end

			active_tweens_to_cancel[existing_tween] = true
		end
	end

	for existing_tween in active_tweens_to_cancel do
		existing_tween:Cancel()
		for inst, prop_tbl in ActiveStandardTweens do
			for prop, tw in prop_tbl do
				if tw ~= existing_tween then
					continue
				end
				prop_tbl[prop] = nil
			end
		end
	end

	-- Execute animation
	if template.Type == "Spring" then
		for _, anim in target_animations do
			Spr.target(anim.Instance, template.Damping, template.Frequency, anim.Properties)
		end
		return nil :: any
	end

	local tween_info = TweenInfo.new(template.Duration, template.Style, template.Direction)
	local tweens = {}

	for _, anim in target_animations do
		local tween = TweenService:Create(anim.Instance, tween_info, anim.Properties)
		table.insert(tweens, tween)

		local inst_tbl = ActiveStandardTweens[anim.Instance]
		if not inst_tbl then
			inst_tbl = {}
			ActiveStandardTweens[anim.Instance] = inst_tbl
		end

		for property_name in anim.Properties do
			inst_tbl[property_name] = tween
		end

		local connection
		connection = tween.Completed:Connect(function()
			connection:Disconnect()
			local current_inst_tbl = ActiveStandardTweens[anim.Instance]
			if not current_inst_tbl then
				return
			end

			for property_name in anim.Properties do
				if current_inst_tbl[property_name] ~= tween then
					continue
				end

				current_inst_tbl[property_name] = nil
			end
			if next(current_inst_tbl) == nil then
				ActiveStandardTweens[anim.Instance] = nil
			end
		end)
	end

	if #tweens == 1 then
		tweens[1]:Play()
		return tweens[1]
	elseif #tweens > 1 then
		local group = create_tween_group(tweens)
		group:Play()
		return group :: any
	else
		return nil :: any
	end
end

--[=[
	Plays a registered template asynchronously, returning a Promise that resolves when standard tween finishes or spring settles.
	@param name string -- The template name.
	@param instance Instance -- The target Roblox instance.
	@return Promise -- A promise that resolves when the animation finishes.
]=]
--
function TweenUtil.PlayAsync(name: string, instance: Instance): PromiseLike
	local template = TweenTemplates[name]
	if not template then
		return Promise.reject(`TweenUtil: Template "{name}" not found!`)
	end

	if template.Type == "Spring" then
		return Promise.new(function(resolve, _, on_cancel)
			TweenUtil.Play(name, instance)

			local target_animations = {}
			parse_properties(instance, template.Properties, target_animations)

			local completed = false
			local remaining = #target_animations
			local function handle_complete()
				if completed then
					return
				end
				remaining = remaining - 1
				if remaining <= 0 then
					completed = true
					resolve(true)
				end
			end

			for _, anim in target_animations do
				pcall(function()
					Spr.completed(anim.Instance, handle_complete)
				end)
			end

			on_cancel(function()
				completed = true
				TweenUtil.Stop(instance)
			end)
		end)
	end

	return Promise.new(function(resolve, reject, on_cancel)
		local tween = TweenUtil.Play(name, instance)
		if not tween then
			reject("Failed to create tween")
			return
		end

		local connection
		connection = tween.Completed:Connect(function(playback_state)
			connection:Disconnect()
			if playback_state == Enum.PlaybackState.Completed then
				resolve(true)
			else
				reject(playback_state)
			end
		end)

		on_cancel(function()
			connection:Disconnect()
			tween:Cancel()
		end)
	end)
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
	Snaps target properties instantly, then returns a Promise resolving when the template animation completes.
	@param name string -- The template name.
	@param instance Instance -- The target Roblox instance.
	@param start_properties { [string]: any } -- Starting property overrides to snap to first.
	@return Promise -- A promise resolving when the animation completes.
]=]
--
function TweenUtil.PlayFromAsync(name: string, instance: Instance, start_properties: { [string]: any }): PromiseLike
	snap_properties(instance, start_properties)
	return TweenUtil.PlayAsync(name, instance)
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

		local inst_tbl = ActiveStandardTweens[instance]
		if inst_tbl then
			local tween = inst_tbl[property]
			if tween then
				tween:Cancel()
				inst_tbl[property] = nil
			end
			if next(inst_tbl) == nil then
				ActiveStandardTweens[instance] = nil
			end
		end
	else
		Spr.stop(instance)
		for _, descendant in instance:GetDescendants() do
			Spr.stop(descendant)
		end

		local keys_to_stop = {}
		for active_inst in ActiveStandardTweens do
			local is_descendant = false
			pcall(function()
				is_descendant = active_inst == instance or active_inst:IsDescendantOf(instance)
			end)
			if is_descendant then
				table.insert(keys_to_stop, active_inst)
			end
		end

		for _, active_inst in keys_to_stop do
			local inst_tbl = ActiveStandardTweens[active_inst]
			if inst_tbl then
				local cancelled = {}
				for prop, tween in inst_tbl do
					if not cancelled[tween] then
						tween:Cancel()
						cancelled[tween] = true
					end
					inst_tbl[prop] = nil
				end
				ActiveStandardTweens[active_inst] = nil
			end
		end
	end
end

--[=[
	Plays a tween immediately on the target instance with the specified duration, style, direction, and properties.
	Supports both positional orders:
	- QuickPlay(instance, properties, duration?, style?, direction?)
	- QuickPlay(instance, duration?, style?, direction?, properties)
	@param instance Instance -- The target Roblox instance.
	@return Tween? -- The created Tween object (or tween group), or nil.
]=]
--
function TweenUtil.QuickPlay(instance: Instance, ...): Tween
	local args = { ... }
	local properties: { [string]: any }?
	local duration: number?
	local style: any?
	local direction: any?

	for _, arg in ipairs(args) do
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

	assert(typeof(instance) == "Instance", "TweenUtil.QuickPlay: First argument must be an Instance")
	assert(type(properties) == "table", "TweenUtil.QuickPlay: Properties table is required")

	temp_counter += 1
	local temp_name = "__temp_" .. tostring(temp_counter)

	TweenUtil.new(temp_name, style, properties, duration, direction)
	local tween = TweenUtil.Play(temp_name, instance)
	TweenTemplates[temp_name] = nil

	return tween
end

return TweenUtil
