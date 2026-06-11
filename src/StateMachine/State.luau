--!nonstrict
--[[
    FileName    > State.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 27/05/2026
--]]

const Types = require("./Types")

local StateModule = {}

--[=[
	@class State
	A state node in a hierarchical state machine (HSM). States can have optional Enter, Exit, and Update callbacks,
	and can be nested under a parent state.
]=]
local State = {}
State.__index = State

export type State = Types.State
--[=[
	@prop Name string
	@within State
	The unique name of the state.
]=]

--[=[
	@prop Parent State?
	@within State
	The parent state under which this state is nested.
]=]

--[=[
	@prop Children { [string]: State }
	@within State
	Map of child states registered under this state.
]=]

--[=[
	@function new
	@within State
	@param name string -- The name of the state
	@param handlers StateHandlers? -- Optional table of event handlers (Enter, Exit, Update)
	@return State -- A new state instance
	@tag constructor
	Creates a new State instance.
]=]
local function new(name: string, handlers)
	local resolved_handlers = (type(handlers) == "table" and handlers or {})

	local self = setmetatable({}, State)

	self.Name = name
	self.Parent = nil
	self.Children = {}
	self.OnEnter = resolved_handlers.Enter
	self.OnExit = resolved_handlers.Exit
	self.OnUpdate = resolved_handlers.Update
	self._ChildKey = nil

	return self
end

export type StateInternal = typeof(new(...))

--[=[
	@method _SetParent
	@private
	@ignore
	@within State
	Sets the parent state of this state, updating children maps.
]=]
function State._SetParent(self: State, parent: State?): boolean
	if self.Parent == parent then
		return true
	end

	local node = parent
	while node ~= nil do
		if node == self then
			return false
		end
		node = node.Parent
	end

	if self.Parent ~= nil then
		local child_key = self._ChildKey or self.Name
		self.Parent.Children[child_key] = nil
	end

	self.Parent = parent

	if parent ~= nil then
		local child_key = self.Name
		self._ChildKey = child_key
		parent.Children[child_key] = self
	else
		self._ChildKey = nil
	end

	return true
end

--[=[
	@method SetName
	@within State
	@param name string -- The new name of the state
	@return boolean -- Whether setting the name succeeded
	Sets the name of the state and updates parent children map entries if nested.
]=]
function State.SetName(self: State, name: string): boolean
	if self.Name == name then
		return true
	end

	if self.Parent ~= nil then
		local previous_key = self._ChildKey or self.Name
		self.Parent.Children[previous_key] = nil
		self.Parent.Children[name] = self
		self._ChildKey = name
	end

	self.Name = name
	return true
end

--[=[
	@method Enter
	@within State
	@param context any? -- Optional context data passed to the handler
	Runs the state's Enter handler callback, if configured.
]=]
function State.Enter(self: State, context: any?)
	local handler = self.OnEnter
	if handler == nil then
		return
	end

	handler(self, context)
end

--[=[
	@method Exit
	@within State
	@param context any? -- Optional context data passed to the handler
	Runs the state's Exit handler callback, if configured.
]=]
function State.Exit(self: State, context: any?)
	local handler = self.OnExit
	if handler == nil then
		return
	end

	handler(self, context)
end

--[=[
	@method Update
	@within State
	@param dt number -- Delta time since last update
	@param context any? -- Optional context data passed to the handler
	Runs the state's Update handler callback, if configured.
]=]
function State.Update(self: State, dt: number, context: any?)
	local handler = self.OnUpdate
	if handler == nil then
		return
	end

	handler(self, dt, context)
end

StateModule.new = new :: <State>(name: string, handlers: Types.StateHandlers<State>?) -> State

return StateModule
