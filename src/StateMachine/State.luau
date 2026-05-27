--!nonstrict
--[[
    FileName    > State.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 27/05/2026
--]]

local StateModule = {}

local State = {}
State.__index = State

export type StateHandlers<Context> = {
    Enter: ((state: State, context: Context) -> ())?,
    Exit: ((state: State, context: Context) -> ())?,
    Update: ((state: State, dt: number, context: Context) -> ())?,
}

local function new(name: string, handlers)
    local resolved_handlers = (type(handlers) == "table" and handlers or {})

    local self = setmetatable({}, State)

    self.Name = name
    self.Parent = nil
    self.Children = {}
    self._OnEnter = resolved_handlers.Enter
    self._OnExit = resolved_handlers.Exit
    self._OnUpdate = resolved_handlers.Update
    self._ChildKey = nil

    return self
end

export type State = typeof(new(...))

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

function State.Enter(self: State, context: any?)
    local handler = self._OnEnter
    if handler == nil then
        return
    end

    handler(self, context)
end

function State.Exit(self: State, context: any?)
    local handler = self._OnExit
    if handler == nil then
        return
    end

    handler(self, context)
end

function State.Update(self: State, dt: number, context: any?)
    local handler = self._OnUpdate
    if handler == nil then
        return
    end

    handler(self, dt, context)
end

StateModule.new = new

return StateModule
