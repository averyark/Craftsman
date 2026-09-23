--!strict
--[[
    FileName    > Component.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 20/05/2026
--]]

const Config = require("./Config")
const Lifecycle = require("../packages/roblox/Lifecycle")

--
warn(
	`[Craftsman] Craftsman.Component is now averyark/craftsman-lifecycle. Require Lifecycle directly, because this alias is removed in the next minor version`
)
--

--
if #Config.MODULE_LOAD_ORDER > 0 then
	warn(`[Craftsman] Config.MODULE_LOAD_ORDER is ignored now. Declare Dependencies on the modules themselves instead`)
end
--

return Lifecycle
