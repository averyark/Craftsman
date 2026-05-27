--!nonstrict
--[[
    FileName    > Machine.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 27/05/2026
--]]

const State = require("./State")

local MachineModule = {}

local Machine = {}
Machine.__index = Machine

type State = typeof(State.new(...))

local function new()
    local self = setmetatable({}, Machine)

    self._States = {}
    self._Initial = nil
    self._Current = nil
    self._Running = false

    return self
end

export type Machine = typeof(new(...))

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

function Machine.Start(self: Machine, context: any?): boolean
    if self._Running then
        return false
    end

    if self._Initial == nil then
        return false
    end

    local ok = self:Transition(self._Initial, context)
    self._Running = ok
    return ok
end

function Machine.Stop(self: Machine, context: any?): boolean
    if not self._Running then
        return false
    end

    local node = self._Current
    while node ~= nil do
        node:Exit(context)
        node = node.Parent
    end

    self._Current = nil
    self._Running = false
    return true
end

function Machine.Transition(self: Machine, target: State, context: any?): boolean
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
    return true
end

function Machine.Update(self: Machine, dt: number, context: any?)
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

MachineModule.new = new

return MachineModule
