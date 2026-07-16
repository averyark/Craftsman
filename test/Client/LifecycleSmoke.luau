--!nonstrict
--[[
    FileName    > LifecycleSmoke.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 17/07/2026

    Client half of the 0.8.0 lifecycle smoke test. Picked up by Component:LoadModulesAsync,
    so it runs during a normal boot.
--]]

const LifecycleSmoke = require("@game/ReplicatedStorage/Shared/LifecycleSmoke")

local LifecycleSmokeClient = {}

function LifecycleSmokeClient.Start()
	LifecycleSmoke.Run("client")
end

return LifecycleSmokeClient
