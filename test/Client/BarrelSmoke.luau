--!nonstrict
--[[
    FileName    > BarrelSmoke.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 16/07/2026

    Client half of the lazy-barrel smoke test. Picked up by Component:LoadModulesAsync
    from ReplicatedStorage.Client, so it runs during a normal boot.

    The client half also covers the server-only exports resolving to nil rather than
    erroring, which is the behaviour P1.2 deliberately left unchanged.
--]]

const BarrelSmoke = require("@game/ReplicatedStorage/Shared/BarrelSmoke")

local BarrelSmokeClient = {}

function BarrelSmokeClient.Start()
	BarrelSmoke.Run("client")
end

return BarrelSmokeClient
