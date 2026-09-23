--!strict
--[[
    FileName    > Tag.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 26/05/2026
--]]

const Signal = require("../packages/roblox/Signal")

--[=[
	@class Tag
	A replicated tagging system for Roblox Instances.
	Tags are stored as individual `NumberValue` instances parented directly to target Instances, allowing them to automatically replicate across the network. Supports timed tags, custom tag attributes, and state listeners.
]=]
local TagModule = {}

--
const TAG_PREFIX = "__TAG_"
--

--
const TagClass = {}
TagClass.__index = TagClass
TagClass.__tostring = function(self)
	return self.Identifier
end
--

--
--[=[
	@interface TagAttributes
	@within Tag
	A dictionary of custom attribute key-value pairs applied to a tag instance.
]=]
export type TagAttributes = { [string]: any }
type TagList = { Tag }
type TagNameList = { string }

--[=[
	@type TagInput string | Tag | { Tag } | { string }
	@within Tag
	Represents the flexible tag lookup inputs accepted by tag checking methods.
]=]
export type TagInput = string | Tag | TagList | TagNameList

--[=[
	@interface TagConnection
	@within Tag
	@field Disconnect (self: TagConnection) -> () -- Disconnects the tag state listener.
	@field Destroy (self: TagConnection) -> () -- Alias for Disconnect.
	A connection handle returned by tag change listeners.
]=]
export type TagConnection = {
	Disconnect: (self: TagConnection) -> (),
	Destroy: (self: TagConnection) -> (),
}
--

--
const Tags: { [string]: Tag } = {}
--

local function apply_attributes(value_object: NumberValue, attributes: TagAttributes?)
	--
	if not attributes then
		return
	end
	--

	--
	for key, value in attributes do
		value_object:SetAttribute(key, value)
	end
	--
end

--[=[
	@function create_tag_value
	@within Tag
	@private
	@ignore
]=]
local function create_tag_value(
	tag: Tag,
	identifier: string,
	instance: Instance,
	interval: number?,
	attributes: TagAttributes?
)
	--
	const value_object = Instance.new("NumberValue")
	value_object.Name = `{TAG_PREFIX}{tag.Identifier}`
	value_object.Value = interval or -1
	value_object:SetAttribute("TagIdentifier", tag.Identifier)
	value_object:SetAttribute("TagId", identifier)
	--

	--
	if interval and interval > 0 then
		value_object:SetAttribute("TagExpiresAt", os.clock() + interval)
	end

	apply_attributes(value_object, attributes)
	--

	--
	value_object.Parent = instance
	--

	return value_object
end

local function append_named_tag(tag_objects: TagList, tag_id: string)
	--
	const tag = Tags[tag_id]

	if not tag then
		return
	end
	--

	--
	tag_objects[#tag_objects + 1] = tag
	--
end

--[=[
	@function resolve_tag_objects
	@within Tag
	@private
	@ignore
]=]
local function resolve_tag_objects(check_tags: TagInput): TagList
	--
	const tag_objects: TagList = {}
	--

	--
	if type(check_tags) == "string" then
		append_named_tag(tag_objects, check_tags)
		return tag_objects
	end

	if type(check_tags) ~= "table" then
		return tag_objects
	end

	const tag_list = check_tags :: TagList | TagNameList

	if getmetatable(tag_list) == TagClass then
		tag_objects[1] = tag_list :: Tag
		return tag_objects
	end
	--

	--
	const first_value = tag_list[1]

	if type(first_value) ~= "string" and getmetatable(first_value :: Tag) == TagClass then
		return tag_list :: TagList
	end

	if type(first_value) ~= "string" then
		return tag_objects
	end
	--

	--
	for _, tag_id in tag_list do
		append_named_tag(tag_objects, tag_id)
	end
	--

	return tag_objects
end

--[=[
	@function create_listener_connection
	@within Tag
	@private
	@ignore
]=]
local function create_listener_connection(cleanup: () -> ()): TagConnection
	return {
		Disconnect = function()
			cleanup()
		end,
		Destroy = function()
			cleanup()
		end,
	}
end

--[=[
	@function new
	@within Tag
	@param identifier string -- The unique name of the tag.
	@return Tag -- The newly registered tag instance.
	@tag constructor
	Registers a new `Tag` with the specified unique identifier. Throws an error if a tag with this identifier is already registered.
]=]
local function new(identifier: string)
	--
	assert(Tags[identifier] == nil, `A tag with this name already exists: {identifier}`)
	--

	--
	const self = setmetatable({}, TagClass)

	--[=[
		@prop Identifier string
		@within Tag
		The unique string identifier for this tag.
	]=]
	self.Identifier = identifier

	--[=[
		@prop Tagged { [string]: NumberValue }
		@within Tag
		Internal lookup of active NumberValue objects representing tag instances, keyed by tag ID.
	]=]
	self.Tagged = {} :: { [string]: NumberValue }

	--[=[
		@prop OnTagged Signal<instance: Instance, id: string, duration: number?>
		@within Tag
		Fires when this tag is applied to a Roblox Instance.
	]=]
	self.OnTagged = Signal.new() :: Signal.Signal<Instance, string, number?>

	--[=[
		@prop OnTagRemoved Signal<instance: Instance, id: string>
		@within Tag
		Fires when a specific tag ID is removed from a Roblox Instance.
	]=]
	self.OnTagRemoved = Signal.new() :: Signal.Signal<Instance, string>

	--[=[
		@prop OnInstanceTagged Signal<instance: Instance, is_tagged: boolean>
		@within Tag
		Fires with `true` when the first tag instance of this type is added to an Instance, and `false` when the last tag instance of this type is removed.
	]=]
	self.OnInstanceTagged = Signal.new() :: Signal.Signal<Instance, boolean>
	self._TagCount = 0
	--

	--
	Tags[identifier] = self
	--

	return self
end

--
export type Tag = typeof(new(...))
--

local function claim_identifier(tag: Tag, overwrite_id: string?): string
	--
	if overwrite_id then
		tag:Remove(nil, overwrite_id)
		return overwrite_id
	end
	--

	--
	tag._TagCount += 1
	--

	return `{tag.Identifier}{tag._TagCount}`
end

local function notify_removed(tag: Tag, target_instance: Instance?, id: string)
	--
	if not target_instance then
		return
	end
	--

	--
	tag.OnTagRemoved:Fire(target_instance, id)

	if tag:IsTagged(target_instance) then
		return
	end
	--

	tag.OnInstanceTagged:Fire(target_instance, false)
end

local function schedule_expiry(
	tag: Tag,
	instance: Instance,
	identifier: string,
	value_object: NumberValue,
	interval: number?
)
	--
	if not interval or not (interval > 0) then
		return
	end
	--

	--
	task.delay(interval, function()
		if tag.Tagged[identifier] ~= value_object then
			return
		end

		tag:Remove(instance, identifier)
	end)
	--
end

--[=[
	@method _RegisterTag
	@within Tag
	@private
	@ignore
]=]
function TagClass._RegisterTag(
	self: Tag,
	instance: Instance,
	interval: number?,
	attributes: TagAttributes?,
	overwrite_id: string?
): (string, NumberValue)
	--
	const was_tagged = self:IsTagged(instance)
	const identifier = claim_identifier(self, overwrite_id)
	--

	--
	const value_object = create_tag_value(self, identifier, instance, interval, attributes)
	self.Tagged[identifier] = value_object
	--

	--
	local connection: RBXScriptConnection
	connection = value_object.AncestryChanged:Connect(function(_, parent)
		if parent ~= nil then
			return
		end

		if self.Tagged[identifier] ~= value_object then
			connection:Disconnect()
			return
		end

		self.Tagged[identifier] = nil
		connection:Disconnect()

		notify_removed(self, instance, identifier)
	end)
	--

	--
	schedule_expiry(self, instance, identifier, value_object, interval)
	--

	--
	self.OnTagged:Fire(instance, identifier, interval)

	if not was_tagged then
		self.OnInstanceTagged:Fire(instance, true)
	end
	--

	return identifier, value_object
end

--[=[
	@method WhenTagRemoved
	@within Tag
	@param id string -- The tag ID to listen for.
	@param callback () -> () -- The callback to invoke.
	@return Connection -- The signal connection.
	Registers a listener that fires once the specific tag instance ID is removed from an Instance.
]=]
function TagClass.WhenTagRemoved(self: Tag, id: string, callback: () -> ()): Signal.Connection
	return self.OnTagRemoved:Connect(function(_, removed_id)
		if removed_id ~= id then
			return
		end

		callback()
	end)
end

--[=[
	@method Remove
	@within Tag
	@param instance Instance? -- The Roblox Instance (optional if the tag is parented).
	@param id string -- The unique tag ID.
	@return boolean -- True if the tag was found and successfully removed.
	Removes a specific tag instance by its ID. Destroys the corresponding Value object.
]=]
function TagClass.Remove(self: Tag, instance: Instance?, id: string): boolean
	--
	const tag_object = self.Tagged[id]

	if not tag_object then
		return false
	end
	--

	--
	const target_instance = instance or tag_object.Parent
	self.Tagged[id] = nil

	if tag_object.Parent ~= nil then
		tag_object:Destroy()
	end
	--

	--
	notify_removed(self, target_instance, id)
	--

	return true
end

--[=[
	@method GetTagId
	@within Tag
	@param instance Instance -- The tagged Roblox Instance.
	@param tag_object NumberValue -- The NumberValue tag object.
	@return string? -- The tag instance ID, or nil if not found.
	Retrieves the unique tag instance ID associated with a specific tag NumberValue object.
]=]
function TagClass.GetTagId(self: Tag, instance: Instance, tag_object: NumberValue): string?
	--
	if tag_object == nil then
		return nil
	end
	--

	--
	const id = tag_object:GetAttribute("TagId")

	if type(id) ~= "string" or self.Tagged[id] ~= tag_object then
		return nil
	end
	--

	return id
end

--[=[
	@method GetDuration
	@within Tag
	@param instance Instance -- The Roblox Instance to query.
	@return number -- The total remaining duration (in seconds) of all timed tag instances of this type.
	Calculates the total remaining time for all active timed tag instances on the Roblox Instance.
]=]
function TagClass.GetDuration(self: Tag, instance: Instance): number
	--
	local duration = 0

	for _, tag_object in self:GetTags(instance) do
		if tag_object.Value == -1 then
			continue
		end

		const expires_at = tag_object:GetAttribute("TagExpiresAt")

		if type(expires_at) ~= "number" then
			duration += tag_object.Value
			continue
		end

		duration += math.max(0, expires_at - os.clock())
	end
	--

	return duration
end

--[=[
	@method GetToggleTags
	@within Tag
	@param instance Instance -- The Roblox Instance to query.
	@return number -- The count of active toggle tags.
	Returns the count of active infinite-duration (toggle) tag instances on the given Roblox Instance.
]=]
function TagClass.GetToggleTags(self: Tag, instance: Instance): number
	--
	local count = 0

	for _, tag_object in self:GetTags(instance) do
		if tag_object.Value ~= -1 then
			continue
		end

		count += 1
	end
	--

	return count
end

--[=[
	@method RemoveAll
	@within Tag
	@param instance Instance -- The Roblox Instance to clear tags from.
	@param check_func ((tag_object: NumberValue) -> boolean)? -- Optional filter callback.
	Removes all tag instances of this type from the Roblox Instance.
]=]
function TagClass.RemoveAll(self: Tag, instance: Instance, check_func: ((tag_object: NumberValue) -> boolean)?)
	--
	const tag_ids = {}

	for id, tag_object in self.Tagged do
		if tag_object.Parent ~= instance then
			continue
		end

		if check_func and not check_func(tag_object) then
			continue
		end

		tag_ids[#tag_ids + 1] = id
	end
	--

	--
	for _, tag_id in tag_ids do
		self:Remove(instance, tag_id)
	end
	--
end

--[=[
	@method AddTag
	@within Tag
	@param instance Instance -- The Roblox Instance to tag.
	@param interval number? -- Optional duration (in seconds) before the tag expires automatically.
	@param attributes TagAttributes? -- Optional metadata attributes to attach to the tag.
	@param overwrite_id string? -- Optional specific ID to overwrite.
	@return NumberValue -- The created tag NumberValue object.
	Applies this tag to the target Roblox Instance, returning the created NumberValue object.
]=]
function TagClass.AddTag(
	self: Tag,
	instance: Instance,
	interval: number?,
	attributes: TagAttributes?,
	overwrite_id: string?
): NumberValue
	--
	const _, value_object = self(instance, interval, attributes, overwrite_id)
	--

	return value_object
end

--[=[
	@method RemoveOthersAndAdd
	@within Tag
	@param instance Instance -- The Roblox Instance to tag.
	@param interval number? -- Optional duration (in seconds).
	@param attributes TagAttributes? -- Optional metadata attributes.
	@return string -- The newly created tag instance ID.
	@return NumberValue -- The created tag NumberValue object.
	Clears all other tag instances of this type on the Instance, then adds a new one and returns its tag ID.
]=]
function TagClass.RemoveOthersAndAdd(
	self: Tag,
	instance: Instance,
	interval: number?,
	attributes: TagAttributes?
): (string, NumberValue)
	--
	self:RemoveAll(instance)
	--

	return self:Add(instance, interval, attributes)
end

--[=[
	@method ReplaceTag
	@within Tag
	@param instance Instance -- The Roblox Instance to tag.
	@param interval number? -- Optional duration.
	@param attributes TagAttributes? -- Optional metadata attributes.
	@return NumberValue -- The new tag NumberValue object.
	Replaces all existing tag instances of this type on the Instance with a single new tag instance.
]=]
function TagClass.ReplaceTag(self: Tag, instance: Instance, interval: number?, attributes: TagAttributes?): NumberValue
	--
	self:RemoveAll(instance)
	--

	return self:AddTag(instance, interval, attributes)
end

--[=[
	@method SetTag
	@within Tag
	@param instance Instance -- The Roblox Instance to tag.
	@param interval number? -- Optional duration.
	@param attributes TagAttributes? -- Optional metadata attributes.
	@return NumberValue -- The new tag NumberValue object.
	Alias for `ReplaceTag`. Replaces all existing tag instances of this type on the Instance with a single new tag instance.
]=]
function TagClass.SetTag(self: Tag, instance: Instance, interval: number?, attributes: TagAttributes?): NumberValue
	--
	self:RemoveAll(instance)
	--

	return self:AddTag(instance, interval, attributes)
end

--[=[
	@method GetTags
	@within Tag
	@param instance Instance -- The Roblox Instance to query.
	@return { NumberValue } -- An array of tag NumberValue objects parented to the Instance.
	Retrieves all tag NumberValue objects of this type currently parented to the Roblox Instance.
]=]
function TagClass.GetTags(self: Tag, instance: Instance): { NumberValue }
	--
	const tagged = {}
	const target_name = `{TAG_PREFIX}{self.Identifier}`
	--

	--
	for _, child in instance:GetChildren() do
		if child.Name ~= target_name then
			continue
		end

		if not child:IsA("NumberValue") then
			continue
		end

		tagged[#tagged + 1] = child
	end
	--

	return tagged
end

--[=[
	@method IsTagged
	@within Tag
	@param instance Instance -- The Roblox Instance to query.
	@param only_local boolean? -- If true, only checks local/locally created tag cache instead of the Instance's children.
	@return boolean -- True if the Instance is tagged with this tag.
	Checks if the Roblox Instance currently has this tag.
]=]
function TagClass.IsTagged(self: Tag, instance: Instance, only_local: boolean?): boolean
	--
	if not only_local then
		return instance:FindFirstChild(`{TAG_PREFIX}{self.Identifier}`) ~= nil
	end
	--

	--
	for _, tag_object in self.Tagged do
		if tag_object.Parent ~= instance then
			continue
		end

		return true
	end
	--

	return false
end

--[=[
	@method ListenToInstance
	@within Tag
	@param instance Instance -- The Roblox Instance to listen to.
	@param callback (is_tagged: boolean) -> () -- Invoked with the new tagged status.
	@return TagConnection -- The connection handle to stop listening.
	Listens to changes in the tagged status of the Roblox Instance (true when first tag is added, false when last tag is removed).
]=]
function TagClass.ListenToInstance(self: Tag, instance: Instance, callback: (boolean) -> ()): TagConnection
	--
	const current_tags = self:GetTags(instance)
	local state: boolean? = nil

	local function change(new_state: boolean)
		if state == new_state then
			return
		end

		state = new_state
		callback(new_state)
	end

	change(#current_tags > 0)
	--

	--
	local alive = true
	local connection_cleanup
	local connection_added
	local connection_removed

	local function cleanup()
		if not alive then
			return
		end

		alive = false

		if connection_added then
			connection_added:Disconnect()
		end
		if connection_removed then
			connection_removed:Disconnect()
		end
		if connection_cleanup then
			connection_cleanup:Disconnect()
		end
	end
	--

	--
	connection_cleanup = instance.AncestryChanged:Connect(function(_, parent)
		if parent ~= nil then
			return
		end

		cleanup()
	end)

	connection_added = instance.ChildAdded:Connect(function(object)
		if not object:IsA("NumberValue") then
			return
		end

		if object.Name ~= `{TAG_PREFIX}{self.Identifier}` then
			return
		end

		if table.find(current_tags, object) then
			return
		end

		current_tags[#current_tags + 1] = object
		change(true)
	end)

	connection_removed = instance.ChildRemoved:Connect(function(object)
		if not object:IsA("NumberValue") then
			return
		end

		if object.Name ~= `{TAG_PREFIX}{self.Identifier}` then
			return
		end

		const index = table.find(current_tags, object)

		if not index then
			return
		end

		table.remove(current_tags, index)
		change(#current_tags > 0)
	end)
	--

	return create_listener_connection(cleanup)
end

--[=[
	@method ListenToInstanceTags
	@within Tag
	@param instance Instance -- The Roblox Instance to listen to.
	@param callback (tag_object: NumberValue, is_added: boolean) -> () -- Invoked when a tag is added/removed.
	@return TagConnection -- The connection handle to stop listening.
	Listens to when individual tag instances of this type are added or removed from the Roblox Instance.
]=]
function TagClass.ListenToInstanceTags(
	self: Tag,
	instance: Instance,
	callback: (NumberValue, boolean) -> ()
): TagConnection
	--
	const current_tags = self:GetTags(instance)

	for _, current_tag in current_tags do
		callback(current_tag, true)
	end
	--

	--
	local alive = true
	local connection_cleanup
	local connection_added
	local connection_removed

	local function cleanup()
		if not alive then
			return
		end

		alive = false

		if connection_added then
			connection_added:Disconnect()
		end
		if connection_removed then
			connection_removed:Disconnect()
		end
		if connection_cleanup then
			connection_cleanup:Disconnect()
		end
	end
	--

	--
	connection_cleanup = instance.AncestryChanged:Connect(function(_, parent)
		if parent ~= nil then
			return
		end

		cleanup()
	end)

	connection_added = instance.ChildAdded:Connect(function(object)
		if not object:IsA("NumberValue") then
			return
		end

		if object.Name ~= `{TAG_PREFIX}{self.Identifier}` then
			return
		end

		if table.find(current_tags, object) then
			return
		end

		current_tags[#current_tags + 1] = object
		callback(object, true)
	end)

	connection_removed = instance.ChildRemoved:Connect(function(object)
		if not object:IsA("NumberValue") then
			return
		end

		if object.Name ~= `{TAG_PREFIX}{self.Identifier}` then
			return
		end

		const index = table.find(current_tags, object)

		if not index then
			return
		end

		table.remove(current_tags, index)
		callback(object, false)
	end)
	--

	return create_listener_connection(cleanup)
end

--[=[
	@method Destroy
	@within Tag
	Cleans up and destroys the tag object, removing all active tag instances from instances and disposing of signals.
]=]
function TagClass.Destroy(self: Tag)
	--
	const tag_ids = {}

	for id in self.Tagged do
		tag_ids[#tag_ids + 1] = id
	end
	--

	--
	for _, tag_id in tag_ids do
		self:Remove(nil, tag_id)
	end
	--

	--
	Tags[self.Identifier] = nil

	self.OnTagged:Destroy()
	self.OnTagRemoved:Destroy()
	self.OnInstanceTagged:Destroy()
	--
end

--
TagClass.__call = TagClass._RegisterTag
TagClass.Add = TagClass._RegisterTag

TagModule.new = new
--

--[=[
	@function Get
	@within Tag
	@param identifier string -- The tag name.
	@return Tag -- The registered or newly created tag.
	Retrieves an existing registered tag by its name, or registers a new one if it does not exist.
]=]
function TagModule.Get(identifier: string): Tag
	--
	if Tags[identifier] then
		return Tags[identifier]
	end
	--

	return new(identifier)
end

--[=[
	@function Is
	@within Tag
	@param value any -- The value to check.
	@return boolean -- True if the value is a Tag object.
	Checks if a given value is a valid `Tag` instance.
]=]
function TagModule.Is(value: any): boolean
	return getmetatable(value) == TagClass
end

--[=[
	@function HasTags
	@within Tag
	@param instance Instance -- The Roblox Instance to check.
	@param check_tags TagInput -- The tag(s) to check for.
	@return boolean -- True if the instance has any of the specified tags.
	Checks if a Roblox Instance has any of the specified tags (accepts a single string tag name, Tag object, array of tag names, or array of Tag objects).
]=]
function TagModule.HasTags(instance: Instance, check_tags: TagInput): boolean
	--
	const tag_objects = resolve_tag_objects(check_tags)
	--

	--
	for _, tag_object in tag_objects do
		if not tag_object:IsTagged(instance) then
			continue
		end

		return true
	end
	--

	return false
end

--[=[
	@function GetTags
	@within Tag
	@param instance Instance -- The Roblox Instance to check.
	@return { Tag } -- An array of Tag objects active on the instance.
	Retrieves all registered `Tag` objects currently active on the Roblox Instance.
]=]
function TagModule.GetTags(instance: Instance): { Tag }
	--
	const tagged = {}

	for _, tag in Tags do
		if not tag:IsTagged(instance) then
			continue
		end

		tagged[#tagged + 1] = tag
	end
	--

	return tagged
end

--[=[
	@function GetRegistered
	@within Tag
	@return { Tag } -- An array of all registered Tag objects.
	Retrieves a list of all registered `Tag` objects.
]=]
function TagModule.GetRegistered(): { Tag }
	--
	const registered = {}

	for _, tag in Tags do
		registered[#registered + 1] = tag
	end
	--

	return registered
end

return TagModule
