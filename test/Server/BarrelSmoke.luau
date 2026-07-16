--!nonstrict
--[[
    FileName    > BarrelSmoke.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 16/07/2026

    Server half of the lazy-barrel smoke test. Picked up by Component:LoadModulesAsync
    from ServerScriptService.Server, so it runs during a normal boot.
--]]

const BarrelSmoke = require("@game/ReplicatedStorage/Shared/BarrelSmoke")

local BarrelSmokeServer = {}

function BarrelSmokeServer.Start()
	BarrelSmoke.Run("server")
end

return BarrelSmokeServer
