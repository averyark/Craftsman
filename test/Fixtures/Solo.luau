--!nonstrict
--[[
    FileName    > Solo.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 17/07/2026

    Depends on nothing, and nothing depends on it. Proves independent modules overlap with
    Alpha's yield instead of queueing behind it.
--]]

const SmokeRecord = require("@game/ReplicatedStorage/Shared/SmokeRecord")

local Solo = {}

function Solo.Start()
	SmokeRecord.Log("Solo", "start_begin")
	Solo.Keeper:Add(function()
		SmokeRecord.Log("Solo", "keeper_cleaned")
	end)
	SmokeRecord.Log("Solo", "start_end")
end

function Solo.Stop()
	SmokeRecord.Log("Solo", "stop")
end

return Solo
