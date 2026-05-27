--!nonstrict

--[[
    FileName    > Example.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 27/05/2026
--]]

const Craftsman = require("../Packages/Craftsman")

local Example = {}

function Example.Run()
    Craftsman.PrintUtil:Print("HFSM Example starting...")

    -- Create simple states with handlers
    local root = Craftsman.State.new("Root", {
        Enter = function(self)
            Craftsman.PrintUtil:Print("Enter Root")
        end,
        Exit = function(self)
            Craftsman.PrintUtil:Print("Exit Root")
        end,
        Update = function(self, dt)
            Craftsman.PrintUtil:Print(`Update Root (dt={dt})` )
        end,
    })

    local a = Craftsman.State.new("A", {
        Enter = function(self)
            Craftsman.PrintUtil:Print("Enter A")
        end,
        Exit = function(self)
            Craftsman.PrintUtil:Print("Exit A")
        end,
        Update = function(self, dt)
            Craftsman.PrintUtil:Print(`Update A (dt={dt})`)
        end,
    })

    local b = Craftsman.State.new("B", {
        Enter = function(self)
            Craftsman.PrintUtil:Print("Enter B")
        end,
        Exit = function(self)
            Craftsman.PrintUtil:Print("Exit B")
        end,
        Update = function(self, dt)
            Craftsman.PrintUtil:Print(`Update B (dt={dt})`)
        end,
    })

    local b1 = Craftsman.State.new("B1", {
        Enter = function(self)
            Craftsman.PrintUtil:Print("Enter B1")
        end,
        Exit = function(self)
            Craftsman.PrintUtil:Print("Exit B1")
        end,
        Update = function(self, dt)
            Craftsman.PrintUtil:Print(`Update B1 (dt={dt})`)
        end,
    })

    -- Build machine
    local m = Craftsman.Machine.new()

    assert(m:AddState(root))
    assert(m:AddState(a, root))
    assert(m:AddState(b, root))
    assert(m:AddState(b1, b))

    -- initial -> drill into target (no default child behavior is provided)
    assert(m:SetInitial(a))

    -- start machine
    local ok = m:Start()
    if not ok then
        Craftsman.PrintUtil:Error("Failed to start machine")
        return
    end

    -- Simulate update tick
    m:Update(0.016)

    -- Transition from A -> B1 (will exit A, enter B then B1)
    m:Transition(b1)

    -- Simulate a second tick
    m:Update(0.033)

    -- Demonstrate cycle detection: attempting to set parent that would create a cycle
    local _result = b:_SetParent(b1)
    Craftsman.PrintUtil:Print(`Attempted to make B child of B1 (should fail): {_result}`)

    -- Stop machine
    m:Stop()
    Craftsman.PrintUtil:Print("HFSM Example finished.")
end

return Example
