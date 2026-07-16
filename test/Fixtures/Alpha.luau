--!nonstrict
--[[
    FileName    > Alpha.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 17/07/2026

    Lifecycle fixture with no dependencies. Beta depends on this one, so Alpha must finish
    starting before Beta begins, and must stop only after Beta has stopped.
--]]

const SmokeRecord = require("@game/ReplicatedStorage/Shared/SmokeRecord")

local Alpha = {}

function Alpha.Start()
	SmokeRecord.Log("Alpha", "start_begin")
	-- Yield, so "Beta waited for Alpha" means Alpha *finished*, not merely that it was
	-- reached first. Without this the ordering assertion would pass even when serialised.
	task.wait(0.1)
	SmokeRecord.Log("Alpha", "start_end")
end

function Alpha.Stop()
	SmokeRecord.Log("Alpha", "stop")
end

return Alpha
