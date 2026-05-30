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

function Machine.GetState(self: Machine, name: string): State?
	return self._States[name]
end

function Machine.GetId(self: Machine): string?
	return self._Id
end

function Machine.SetId(self: Machine, id: string): boolean
	self._Id = id
	return true
end

function Machine.IsClientAuthoritative(self: Machine): boolean
	return self._ClientAuthoritative == true
end

function Machine.SetClientAuthoritative(self: Machine, is_client_authoritative: boolean): boolean
	self._ClientAuthoritative = is_client_authoritative == true
	return true
end

function Machine.SetInitial(self: Machine, state: State): boolean
	if state == nil then
		return false
	end

	self._Initial = state
	return true
end

function Machine.GetCurrent(self: Machine): State?
	return self._Current
end

function Machine.IsRunning(self: Machine): boolean
	return self._Running
end

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

function Machine.Replicate(self: Machine, targets: { any }?): boolean
	if RunService:IsServer() then
		return Server:Register(self, targets)
	else
		return Client:Register(self)
	end
end

function Machine.Unreplicate(self: Machine): boolean
	if RunService:IsServer() then
		return Server:Unregister(self)
	else
		return Client:Unregister(self)
	end
end

function Machine.SetReplicationTargets(self: Machine, targets: { any }?): boolean
	if RunService:IsServer() then
		return Server:SetTargets(self, targets)
	end
	return false
end

function Machine.SyncReplication(self: Machine, targets: { any }?): boolean
	if RunService:IsServer() then
		return Server:Sync(self, targets)
	else
		return Client:Sync(self)
	end
end

MachineModule.new = new

return MachineModule
