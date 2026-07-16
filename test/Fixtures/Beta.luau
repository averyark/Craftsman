--!nonstrict
--[[
    FileName    > Beta.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 17/07/2026

    Lifecycle fixture that declares a dependency in place, by holding Alpha's module table
    rather than naming it.
--]]

const SmokeRecord = require("@game/ReplicatedStorage/Shared/SmokeRecord")
const Alpha = require("@game/ReplicatedStorage/Fixtures/Alpha")

local Beta = {
	Dependencies = { Alpha },
}

function Beta.Start()
	SmokeRecord.Log("Beta", "start_begin")
	SmokeRecord.Log("Beta", "start_end")
end

function Beta.Stop()
	SmokeRecord.Log("Beta", "stop")
end

return Beta
