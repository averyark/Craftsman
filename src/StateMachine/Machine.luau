--!nonstrict
--[[
    FileName    > Machine.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 27/05/2026
--]]

const RunService = game:GetService("RunService")

const Signal = require("../Signal")
const Types = require("./Types")
const Server = RunService:IsServer() and require("./Server")
const Client = RunService:IsClient() and require("./Client")

local MachineModule = {}

--[=[
	@class Machine
	A hierarchical state machine (HSM) implementation supporting nested states,
	state replication, and client/server synchronization.
]=]
local Machine = {}
Machine.__index = Machine

export type State = Types.State
export type Machine = Types.Machine

type PendingTransition = {
	Target: State,
	Context: any?,
	Source: Player?,
}

local MAX_TRANSITION_BATCH = 10

--[=[
	@prop Transitioned Signal<Machine, State, State, any, Player>
	@within Machine
	Fires when the active state transitions to a new state.
]=]

--[=[
	@prop Destroyed Signal<Machine>
	@within Machine
	Fires when the state machine is destroyed.
]=]

--[=[
	@function new
	@within Machine
	@param id string? -- Optional unique identifier for the machine
	@param is_client_authoritative boolean? -- Whether the state machine allows client-authoritative transitions
	@return Machine -- A new state machine instance
	@tag constructor
	Creates a new State Machine instance.
]=]
local function new(id: string?, is_client_authoritative: boolean?)
	local self = setmetatable({}, Machine)

	self._Id = id
	self._ClientAuthoritative = is_client_authoritative == true
	self.Transitioned = Signal.new()
	self.Destroyed = Signal.new()
	self._States = {}
	self._Initial = nil
	self._Current = nil
	self._Running = false
	self._IsTransitioning = false
	self._PendingTransitions = {}
	self._PendingTransitionHead = 1
	self._PendingTransitionTail = 0
	self._PendingTransitionDrainScheduled = false
	self._Destroyed = false

	return self
end

local function build_ancestor_set(state: State?): { [State]: boolean }
	local set = {}
	local node = state
	while node ~= nil do
		set[node] = true
		node = node.Parent
	end
	return set
end

local function build_path_to_root(state: State?): { State }
	local path = {}
	local node = state
	while node ~= nil do
		table.insert(path, node)
		node = node.Parent
	end
	return path
end

local function enqueue_transition(self: Machine, target: State, context: any?, source: Player?)
	local pending = self._PendingTransitions
	local next_index = self._PendingTransitionTail + 1
	self._PendingTransitionTail = next_index
	pending[next_index] = {
		Target = target,
		Context = context,
		Source = source,
	}
end

local function reset_transition_queue(self: Machine)
	table.clear(self._PendingTransitions)
	self._PendingTransitionHead = 1
	self._PendingTransitionTail = 0
end

--[=[
	@method AddState
	@within Machine
	@param state State -- The state object to add
	@param parent State? -- Optional parent state to nest this state under
	@return boolean -- Whether the state was successfully added
	Adds a state to the state machine, optionally setting a parent state for hierarchy.
]=]
function Machine.AddState(self: Machine, state: State, parent: State?): boolean
	if state == nil then
		return false
	end

	local name = state.Name
	local existing = self._States[name]
	if existing ~= nil and existing ~= state then
		return false
	end

	self._States[name] = state

	if parent ~= nil then
		if not state:_SetParent(parent) then
			return false
		end
	end

	return true
end

--[=[
	@method GetState
	@within Machine
	@param name string -- The name of the state
	@return State? -- The state object, if found
	Retrieves a registered state by its name.
]=]
function Machine.GetState(self: Machine, name: string): State?
	return self._States[name]
end

--[=[
	@method GetId
	@within Machine
	@return string? -- The unique identifier
	Returns the unique identifier of the machine.
]=]
function Machine.GetId(self: Machine): string?
	return self._Id
end

--[=[
	@method SetId
	@within Machine
	@param id string -- The new unique identifier
	@return boolean -- Whether setting the ID succeeded
	Sets the unique identifier of the machine.
]=]
function Machine.SetId(self: Machine, id: string): boolean
	self._Id = id
	return true
end

--[=[
	@method IsClientAuthoritative
	@within Machine
	@return boolean -- True if client-authoritative
	Returns whether the state machine transitions are client-authoritative.
]=]
function Machine.IsClientAuthoritative(self: Machine): boolean
	return self._ClientAuthoritative == true
end

--[=[
	@method SetClientAuthoritative
	@within Machine
	@param is_client_authoritative boolean -- The new authoritative state
	@return boolean
	Sets whether the state machine transitions are client-authoritative.
]=]
function Machine.SetClientAuthoritative(self: Machine, is_client_authoritative: boolean): boolean
	self._ClientAuthoritative = is_client_authoritative == true
	return true
end

--[=[
	@method SetInitial
	@within Machine
	@param state State -- The initial state
	@return boolean -- Whether setting the initial state succeeded
	Sets the initial starting state for the machine.
]=]
function Machine.SetInitial(self: Machine, state: State): boolean
	if state == nil then
		return false
	end

	self._Initial = state
	return true
end

--[=[
	@method GetCurrent
	@within Machine
	@return State? -- The currently active state
	Returns the currently active state of the machine.
]=]
function Machine.GetCurrent(self: Machine): State?
	return self._Current
end

--[=[
	@method IsRunning
	@within Machine
	@return boolean -- True if the machine is active and running
	Returns whether the state machine is active and running.
]=]
function Machine.IsRunning(self: Machine): boolean
	return self._Running
end

--[=[
	@method Start
	@within Machine
	@param context any? -- Optional context data to pass to the initial state's Enter handler
	@param source Player? -- Optional player context initiating the start
	@return boolean -- Whether the state machine successfully started
	Starts the state machine, entering the initial state.
]=]
function Machine.Start(self: Machine, context: any?, source: Player?): boolean
	if self._Destroyed then
		return false
	end

	if self._Running then
		return false
	end

	if self._Initial == nil then
		return false
	end

	self._Running = true
	local ok = self:Transition(self._Initial, context, source)
	if not ok then
		self._Running = false
	end
	return ok
end

--[=[
	@method Stop
	@within Machine
	@param context any? -- Optional context data to pass to state Exit handlers
	@param source Player? -- Optional player context initiating the stop
	@return boolean -- Whether the state machine successfully stopped
	Stops the state machine, exiting the current active state and any active parent states.
]=]
function Machine.Stop(self: Machine, context: any?, source: Player?): boolean
	if self._Destroyed then
		return false
	end

	if not self._Running then
		return false
	end

	local previous = self._Current
	local node = previous
	while node ~= nil do
		node:Exit(context)
		node = node.Parent
	end

	self._Current = nil
	self._Running = false
	self.Transitioned:Fire(self, previous, nil, context, source)
	return true
end

local function perform_transition(self: Machine, target: State, context: any?, source: Player?): boolean
	if self._Destroyed then
		return false
	end

	if target == nil then
		return false
	end

	if self._Current == target then
		return false
	end

	local current = self._Current
	if current == nil then
		local enter_chain = build_path_to_root(target)
		for index = #enter_chain, 1, -1 do
			enter_chain[index]:Enter(context)
		end
		self._Current = target
		self.Transitioned:Fire(self, current, target, context, source)
		return true
	end

	local current_ancestors = build_ancestor_set(current)
	local lca = nil
	local node = target
	while node ~= nil do
		if current_ancestors[node] then
			lca = node
			break
		end
		node = node.Parent
	end

	node = current
	while node ~= nil and node ~= lca do
		node:Exit(context)
		node = node.Parent
	end

	local enter_chain = {}
	node = target
	while node ~= nil and node ~= lca do
		table.insert(enter_chain, node)
		node = node.Parent
	end

	for index = #enter_chain, 1, -1 do
		enter_chain[index]:Enter(context)
	end

	self._Current = target
	self.Transitioned:Fire(self, current, target, context, source)
	return true
end

local function process_pending_transitions(self: Machine)
	if self._Destroyed or self._IsTransitioning then
		return
	end

	local pending = self._PendingTransitions
	local processed = 0

	while self._PendingTransitionHead <= self._PendingTransitionTail do
		local entry = pending[self._PendingTransitionHead]
		pending[self._PendingTransitionHead] = nil
		self._PendingTransitionHead += 1

		if entry ~= nil and entry.Target ~= nil and entry.Target ~= self._Current then
			self._IsTransitioning = true
			perform_transition(self, entry.Target, entry.Context, entry.Source)
			self._IsTransitioning = false
		end

		processed += 1
		if processed >= MAX_TRANSITION_BATCH then
			break
		end
	end

	if self._PendingTransitionHead > self._PendingTransitionTail then
		reset_transition_queue(self)
		return
	end

	if self._PendingTransitionDrainScheduled then
		return
	end

	self._PendingTransitionDrainScheduled = true
	task.defer(function()
		self._PendingTransitionDrainScheduled = false
		process_pending_transitions(self)
	end)
end

--[=[
	@method Transition
	@within Machine
	@param target State -- The target state to transition to
	@param context any? -- Optional context data to pass to Exit/Enter handlers
	@param source Player? -- Optional player context initiating the transition
	@return boolean -- Whether the transition completed successfully (or was queued)
	Initiates a transition to the target state. If a transition is already in progress,
	this transition is enqueued to run sequentially.
]=]
function Machine.Transition(self: Machine, target: State, context: any?, source: Player?): boolean
	if self._Destroyed then
		return false
	end

	if target == nil then
		return false
	end

	if self._IsTransitioning then
		enqueue_transition(self, target, context, source)
		return true
	end

	self._IsTransitioning = true
	local ok = perform_transition(self, target, context, source)
	self._IsTransitioning = false
	process_pending_transitions(self)

	return ok
end

--[=[
	@method Update
	@within Machine
	@param dt number -- Delta time since last update
	@param context any? -- Optional context data passed to state Update handlers
	Updates the active state and its parent hierarchy by running their Update handlers.
]=]
function Machine.Update(self: Machine, dt: number, context: any?)
	if self._Destroyed then
		return
	end

	if not self._Running then
		return
	end

	local current = self._Current
	if current == nil then
		return
	end

	local chain = build_path_to_root(current)
	for index = #chain, 1, -1 do
		chain[index]:Update(dt, context)
	end
end

--[=[
	@method Destroy
	@within Machine
	@return boolean -- Whether the machine was successfully destroyed
	Destroys the state machine, cleaning up all internal states, signals, and queues.
]=]
function Machine.Destroy(self: Machine): boolean
	if self._Destroyed then
		return false
	end

	self._Destroyed = true
	self.Destroyed:Fire(self)
	self.Transitioned:Destroy()
	self.Destroyed:Destroy()

	self._Id = nil
	self._ClientAuthoritative = false
	self._Initial = nil
	self._Current = nil
	self._Running = false
	self._IsTransitioning = false

	local states = self._States
	if states then
		table.clear(states)
	end

	local pending = self._PendingTransitions
	if pending then
		reset_transition_queue(self)
	end

	return true
end

--[=[
	@method Replicate
	@within Machine
	@param targets { any }? -- Optional replication targets (players or namespaces) on server
	@return boolean -- Whether replication setup succeeded
	Registers the machine for networking/replication.
]=]
function Machine.Replicate(self: Machine, targets: { any }?): boolean
	if RunService:IsServer() then
		return Server:Register(self, targets)
	else
		return Client:Register(self)
	end
end

--[=[
	@method Unreplicate
	@within Machine
	@return boolean -- Whether replication teardown succeeded
	Unregisters the machine from replication.
]=]
function Machine.Unreplicate(self: Machine): boolean
	if RunService:IsServer() then
		return Server:Unregister(self)
	else
		return Client:Unregister(self)
	end
end

--[=[
	@method SetReplicationTargets
	@within Machine
	@param targets { any }? -- New replication targets (players or namespaces)
	@return boolean -- Whether setting targets succeeded
	Sets replication targets for the state machine (server-only).
]=]
function Machine.SetReplicationTargets(self: Machine, targets: { any }?): boolean
	if RunService:IsServer() then
		return Server:SetTargets(self, targets)
	end
	return false
end

--[=[
	@method SyncReplication
	@within Machine
	@param targets { any }? -- Optional sync target override
	@return boolean -- Whether the sync succeeded
	Manually syncs replication state.
]=]
function Machine.SyncReplication(self: Machine, targets: { any }?): boolean
	if RunService:IsServer() then
		return Server:Sync(self, targets)
	else
		return Client:Sync(self)
	end
end

MachineModule.new = new

return MachineModule
