--!nonstrict
--[[
    FileName    > Bootstrap.client.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 21/05/2026
--]]

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Bootstrap = require("@game/ReplicatedStorage/Shared/Bootstrap")

local BootstrapClient = {}

Bootstrap:Start(ReplicatedStorage.Client)

return BootstrapClient
