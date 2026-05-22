--!nonstrict
--[[
    FileName    > Bootstrap.server.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 21/05/2026
--]]

const ServerScriptService = game:GetService("ServerScriptService")

const Bootstrap = require("@game/ReplicatedStorage/Shared/Bootstrap")

local BootstrapServer = {}

Bootstrap:Start(ServerScriptService.Server)

return BootstrapServer
