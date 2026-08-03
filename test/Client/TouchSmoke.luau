--!nonstrict
--[[
    FileName    > TouchSmoke.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 03/08/2026

    Client half of the touch-button smoke test. Picked up by Component:LoadModulesAsync, so it
    runs during a normal boot with a real PlayerGui.
--]]

const TouchSmoke = require("@game/ReplicatedStorage/Shared/TouchSmoke")

local TouchSmokeClient = {}

function TouchSmokeClient.Start()
	TouchSmoke.Run("client")
end

return TouchSmokeClient
