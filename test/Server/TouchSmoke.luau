--!nonstrict
--[[
    FileName    > TouchSmoke.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 03/08/2026

    Server half of the touch smoke test. Only the InputUtil portion runs here -- TouchUtil is
    client-only. The point of running it at all is that requiring InputUtil on the server no
    longer throws.
--]]

const TouchSmoke = require("@game/ReplicatedStorage/Shared/TouchSmoke")

local TouchSmokeServer = {}

function TouchSmokeServer.Start()
	TouchSmoke.Run("server")
end

return TouchSmokeServer
