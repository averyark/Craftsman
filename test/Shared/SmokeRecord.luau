--!nonstrict
--[[
    FileName    > SmokeRecord.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 17/07/2026

    Ordered event log shared by the lifecycle fixtures. Lives outside test/Fixtures so the
    loader does not pick it up as a module of its own.
--]]

local SmokeRecord = {}

SmokeRecord.Events = {}

function SmokeRecord.Log(name: string, event: string)
	table.insert(SmokeRecord.Events, { name = name, event = event })
end

function SmokeRecord.Reset()
	table.clear(SmokeRecord.Events)
end

-- Position of an event in the log, or nil. Comparing positions is how ordering is asserted.
function SmokeRecord.IndexOf(name: string, event: string): number?
	for index, entry in SmokeRecord.Events do
		if entry.name == name and entry.event == event then
			return index
		end
	end
	return nil
end

return SmokeRecord
