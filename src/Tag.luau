--!nonstrict
--[[
    FileName    > Tag.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 26/05/2026
--]]

const Signal = require("./Signal")

local TAG_PREFIX = "__TAG_"

local TagModule = {}

local TagClass = {}
TagClass.__index = TagClass
TagClass.__tostring = function(self)
	return self.Identifier
end


type TagAttributes = { [string]: any }
type TagList = { Tag }
type TagNameList = { string }
type TagInput = string | Tag | TagList | TagNameList
type TagConnection = {
	Disconnect: (self: TagConnection) -> (),
	Destroy: (self: TagConnection) -> (),
}

local Tags: { [string]: Tag } = {}

local function create_tag_value(
	tag: Tag,
	identifier: string,
	instance: Instance,
	interval: number?,
	attributes: TagAttributes?
)
	local value_object = Instance.new("NumberValue")
	value_object.Name = TAG_PREFIX .. tag.Identifier
	value_object.Value = interval or -1
	value_object:SetAttribute("TagIdentifier", tag.Identifier)
	value_object:SetAttribute("TagId", identifier)

	if interval and interval > 0 then
		value_object:SetAttribute("TagExpiresAt", os.clock() + interval)
	end

	if attributes then
		for key, value in attributes do
			value_object:SetAttribute(key, value)
		end
	end

	value_object.Parent = instance

	return value_object
end

local function resolve_tag_objects(check_tags: TagInput): TagList
	local tag_objects: TagList = {}

	if type(check_tags) == "string" then
		local tag = Tags[check_tags]
		if tag then
			tag_objects[1] = tag
		end

		return tag_objects
	end

	if type(check_tags) ~= "table" then
		return tag_objects
	end

	local tag_list = check_tags :: TagList | TagNameList

	if getmetatable(tag_list) == TagClass then
		tag_objects[1] = tag_list :: Tag
		return tag_objects
	end

	local first_value = tag_list[1]
	if type(first_value) == "string" then
		for index = 1, #tag_list do
			local tag = Tags[tag_list[index]]
			if tag then
				tag_objects[#tag_objects + 1] = tag
			end
		end
		return tag_objects
	end

	if type(first_value) ~= "string" and getmetatable(first_value :: Tag) == TagClass then
		return tag_list :: TagList
	end

	return tag_objects
end

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

local function new(identifier: string)
	assert(Tags[identifier] == nil, `A tag with this name already exists: {identifier}`)

	local self = setmetatable({}, TagClass)

	self.Identifier = identifier
	self.Tagged = {}
	self.OnTagged = Signal.new()
	self.OnTagRemoved = Signal.new()
	self.OnInstanceTagged = Signal.new()
	self._TagCount = 0

	Tags[identifier] = self

	return self
end

export type Tag = typeof(new(...))

function TagClass._RegisterTag(
	self: Tag,
	instance: Instance,
	interval: number?,
	attributes: TagAttributes?,
	overwrite_id: string?
): (string, NumberValue)
	local was_tagged = self:IsTagged(instance)
	local identifier = overwrite_id

	if identifier then
		self:Remove(nil, identifier)
	else
		self._TagCount += 1
		identifier = self.Identifier .. tostring(self._TagCount)
	end

	local value_object = create_tag_value(self, identifier, instance, interval, attributes)
	self.Tagged[identifier] = value_object

	local connection
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

		self.OnTagRemoved:Fire(instance, identifier)
		if not self:IsTagged(instance) then
			self.OnInstanceTagged:Fire(instance, false)
		end
	end)

	if interval and interval > 0 then
		task.delay(interval, function()
			if self.Tagged[identifier] ~= value_object then
				return
			end

			self:Remove(instance, identifier)
		end)
	end

	self.OnTagged:Fire(instance, identifier, interval)

	if not was_tagged then
		self.OnInstanceTagged:Fire(instance, true)
	end

	return identifier, value_object
end

function TagClass.WhenTagRemoved(self: Tag, id: string, callback: () -> ())
	return self.OnTagRemoved:Connect(function(_, removed_id)
		if removed_id == id then
			callback()
		end
	end)
end

function TagClass.Remove(self: Tag, instance: Instance?, id: string): boolean
	local tag_object = self.Tagged[id]
	if not tag_object then
		return false
	end

	local target_instance = instance or tag_object.Parent
	self.Tagged[id] = nil

	if tag_object.Parent ~= nil then
		tag_object:Destroy()
	end

	if target_instance then
		self.OnTagRemoved:Fire(target_instance, id)
		if not self:IsTagged(target_instance) then
			self.OnInstanceTagged:Fire(target_instance, false)
		end
	end

	return true
end

function TagClass.GetTagId(self: Tag, instance: Instance, tag_object: NumberValue): string?
	for id, current_tag in self.Tagged do
		if current_tag == tag_object then
			return id
		end
	end

	return nil
end

function TagClass.GetDuration(self: Tag, instance: Instance): number
	local duration = 0

	for _, tag_object in self:GetTags(instance) do
		if tag_object.Value == -1 then
			continue
		end

		local expires_at = tag_object:GetAttribute("TagExpiresAt")
		if type(expires_at) == "number" then
			duration += math.max(0, expires_at - os.clock())
		else
			duration += tag_object.Value
		end
	end

	return duration
end

function TagClass.GetToggleTags(self: Tag, instance: Instance): number
	local count = 0

	for _, tag_object in self:GetTags(instance) do
		if tag_object.Value == -1 then
			count += 1
		end
	end

	return count
end

function TagClass.RemoveAll(self: Tag, instance: Instance, check_func: ((tag_object: NumberValue) -> boolean)?)
	local tag_ids = {}

	for id, tag_object in self.Tagged do
		if tag_object.Parent ~= instance then
			continue
		end

		if check_func and not check_func(tag_object) then
			continue
		end

		tag_ids[#tag_ids + 1] = id
	end

	for index = 1, #tag_ids do
		self:Remove(instance, tag_ids[index])
	end
end


function TagClass.AddTag(
	self: Tag,
	instance: Instance,
	interval: number?,
	attributes: TagAttributes?,
	overwrite_id: string?
): NumberValue
	local _, value_object = self (instance, interval, attributes, overwrite_id)
	return value_object
end

function TagClass.RemoveOthersAndAdd(
	self: Tag,
	instance: Instance,
	interval: number?,
	attributes: TagAttributes?
): string
	self:RemoveAll(instance)
	return self:Add(instance, interval, attributes)
end

function TagClass.ReplaceTag(self: Tag, instance: Instance, interval: number?, attributes: TagAttributes?): NumberValue
	self:RemoveAll(instance)
	return self:AddTag(instance, interval, attributes)
end

function TagClass.SetTag(self: Tag, instance: Instance, interval: number?, attributes: TagAttributes?): NumberValue
	self:RemoveAll(instance)
	return self:AddTag(instance, interval, attributes)
end

function TagClass.GetTags(self: Tag, instance: Instance): { NumberValue }
	local tagged = {}
	local target_name = TAG_PREFIX .. self.Identifier

	for _, child in instance:GetChildren() do
		if child.Name ~= target_name then
			continue
		end

		if not child:IsA("NumberValue") then
			continue
		end

		tagged[#tagged + 1] = child
	end

	return tagged
end

function TagClass.IsTagged(self: Tag, instance: Instance, only_local: boolean?): boolean
	if only_local then
		for _, tag_object in self.Tagged do
			if tag_object.Parent == instance then
				return true
			end
		end

		return false
	end

	return instance:FindFirstChild(TAG_PREFIX .. self.Identifier) ~= nil
end

function TagClass.ListenToInstance(self: Tag, instance: Instance, callback: (boolean) -> ())
	local current_tags = self:GetTags(instance)
	local state = nil

	local function change(new_state)
		if state == new_state then
			return
		end

		state = new_state
		callback(new_state)
	end

	change(#current_tags > 0)

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
		if object.Name ~= TAG_PREFIX .. self.Identifier then
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
		if object.Name ~= TAG_PREFIX .. self.Identifier then
			return
		end

		local index = table.find(current_tags, object)
		if not index then
			return
		end

		table.remove(current_tags, index)
		change(#current_tags > 0)
	end)

	return create_listener_connection(cleanup)
end

function TagClass.ListenToInstanceTags(self: Tag, instance: Instance, callback: (NumberValue, boolean) -> ())
	local current_tags = self:GetTags(instance)

	for index = 1, #current_tags do
		callback(current_tags[index], true)
	end

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
		if object.Name ~= TAG_PREFIX .. self.Identifier then
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
		if object.Name ~= TAG_PREFIX .. self.Identifier then
			return
		end

		local index = table.find(current_tags, object)
		if not index then
			return
		end

		table.remove(current_tags, index)
		callback(object, false)
	end)

	return create_listener_connection(cleanup)
end

function TagClass.Destroy(self: Tag)
	local tag_ids = {}

	for id in self.Tagged do
		tag_ids[#tag_ids + 1] = id
	end

	for index = 1, #tag_ids do
		self:Remove(nil, tag_ids[index])
	end

	Tags[self.Identifier] = nil
	self.OnTagged:Destroy()
	self.OnTagRemoved:Destroy()
	self.OnInstanceTagged:Destroy()
end

TagModule.new = new

function TagModule.Get(identifier: string): Tag
	if Tags[identifier] then
		return Tags[identifier]
	end

	return new(identifier)
end

function TagModule.Is(value: any): boolean
	return getmetatable(value) == TagClass
end

function TagModule.HasTags(instance: Instance, check_tags: TagInput): boolean
	local tag_objects = resolve_tag_objects(check_tags)

	for index = 1, #tag_objects do
		if tag_objects[index]:IsTagged(instance) then
			return true
		end
	end

	return false
end

function TagModule.GetTags(instance: Instance): { Tag }
	local tagged = {}

	for _, tag in Tags do
		if not tag:IsTagged(instance) then
			continue
		end

		tagged[#tagged + 1] = tag
	end

	return tagged
end

function TagModule.GetRegistered(): { Tag }
	local registered = {}

	for _, tag in Tags do
		registered[#registered + 1] = tag
	end

	return registered
end

return TagModule
