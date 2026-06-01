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

--[[
	@class TweenUtil
	A unified tweening utility that caches reusable animation templates and supports both Roblox TweenService and Spr spring physics.
]]--
local TweenUtil = {}

type EasingStyle = Enum.EasingStyle
type EasingDirection = Enum.EasingDirection
type PromiseLike = typeof(Promise.new(function() end))

local TweenTemplates = {}
local ActiveStandardTweens = setmetatable({}, { __mode = "k" })

--[[
	Registers a reusable animation template. Supports standard TweenService or Spr spring configurations.
	@param name string -- The name key for this template.
	@param style_or_type any -- EasingStyle (e.g. Quad), or "Spring" to use physics.
	@param properties { [string]: any } -- The properties target state.
	@param duration_or_damping number? -- Optional duration (for tweens) or damping ratio (for springs).
	@param direction_or_frequency any? -- Optional EasingDirection (for tweens) or undamped angular frequency (for springs).
	@return { [string]: any } -- The registered configuration dictionary.
]]--
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

--[[
	Plays a registered template on the specified instance with unified standard tween and spring deduplication.
	@param name string -- The template name to play.
	@param instance Instance -- The target Roblox instance to animate.
	@return Tween? -- The created Roblox Tween object (if standard tween), or nil (if spring).
]]--
function TweenUtil.Play(name: string, instance: Instance): Tween?
	local template = TweenTemplates[name]
	if not template then
		PrintUtil:Warn(`Template "{name}" not found!`)
		return nil
	end

	local properties = template.Properties

	-- Unified Deduplication: stop any springs and cancel any active standard tweens driving target properties
	local active_tweens_to_cancel = {}
	for property_name in properties do
		Spr.stop(instance, property_name)

		local inst_tbl = ActiveStandardTweens[instance]
		local existing_tween = inst_tbl and inst_tbl[property_name]
		if not existing_tween then
			continue
		end

		active_tweens_to_cancel[existing_tween] = true
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
		Spr.target(instance, template.Damping, template.Frequency, properties)
		return nil
	end

	local tween_info = TweenInfo.new(template.Duration, template.Style, template.Direction)
	local tween = TweenService:Create(instance, tween_info, properties)

	local inst_tbl = ActiveStandardTweens[instance]
	if not inst_tbl then
		inst_tbl = {}
		ActiveStandardTweens[instance] = inst_tbl
	end

	for property_name in properties do
		inst_tbl[property_name] = tween
	end

	local connection
	connection = tween.Completed:Connect(function()
		connection:Disconnect()
		local current_inst_tbl = ActiveStandardTweens[instance]
		if not current_inst_tbl then
			return
		end

		for property_name in properties do
			if current_inst_tbl[property_name] ~= tween then
				continue
			end

			current_inst_tbl[property_name] = nil
		end
		if next(current_inst_tbl) == nil then
			ActiveStandardTweens[instance] = nil
		end
	end)

	tween:Play()
	return tween
end

--[[
	Plays a registered template asynchronously, returning a Promise that resolves when standard tween finishes or spring settles.
	@param name string -- The template name.
	@param instance Instance -- The target Roblox instance.
	@return Promise -- A promise that resolves when the animation finishes.
]]--
function TweenUtil.PlayAsync(name: string, instance: Instance): PromiseLike
	local template = TweenTemplates[name]
	if not template then
		return Promise.reject(`TweenUtil: Template "{name}" not found!`)
	end

	if template.Type == "Spring" then
		return Promise.new(function(resolve, _, on_cancel)
			TweenUtil.Play(name, instance)

			local completed = false
			local function handle_complete()
				if completed then
					return
				end

				completed = true
				resolve(true)
			end

			pcall(function()
				Spr.completed(instance, handle_complete)
			end)

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

--[[
	Snaps target properties to starting values instantly, then plays the template to animate them to target state.
	@param name string -- The template name.
	@param instance Instance -- The target Roblox instance.
	@param start_properties { [string]: any } -- Starting property overrides to snap to first.
	@return Tween? -- The created standard Tween object, or nil if spring.
]]--
function TweenUtil.PlayFrom(name: string, instance: Instance, start_properties: { [string]: any }): Tween?
	for prop, start_value in start_properties do
		instance[prop] = start_value
	end
	return TweenUtil.Play(name, instance)
end

--[[
	Snaps target properties instantly, then returns a Promise resolving when the template animation completes.
	@param name string -- The template name.
	@param instance Instance -- The target Roblox instance.
	@param start_properties { [string]: any } -- Starting property overrides to snap to first.
	@return Promise -- A promise resolving when the animation completes.
]]--
function TweenUtil.PlayFromAsync(name: string, instance: Instance, start_properties: { [string]: any }): PromiseLike
	for prop, start_value in start_properties do
		instance[prop] = start_value
	end
	return TweenUtil.PlayAsync(name, instance)
end

--[[
	Stops any active spring and cancels any active standard tweens driving specified instance properties.
	@param instance Instance -- The target instance.
	@param property string? -- Optional specific property. If omitted, stops all animations on this instance.
]]--
function TweenUtil.Stop(instance: Instance, property: string?)
	if property then
		Spr.stop(instance, property)
	else
		Spr.stop(instance)
	end

	local inst_tbl = ActiveStandardTweens[instance]
	if not inst_tbl then
		return
	end

	if property then
		local tween = inst_tbl[property]
		if tween then
			tween:Cancel()
			inst_tbl[property] = nil
		end
	else
		local cancelled = {}
		for prop, tween in inst_tbl do
			if not cancelled[tween] then
				tween:Cancel()
				cancelled[tween] = true
			end
			inst_tbl[prop] = nil
		end
	end

	if next(inst_tbl) == nil then
		ActiveStandardTweens[instance] = nil
	end
end

return TweenUtil
