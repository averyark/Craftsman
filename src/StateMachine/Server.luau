--!nonstrict
--[[
    FileName    > Server.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 30/05/2026
--]]

const RunService = game:GetService("RunService")
const Players = game:GetService("Players")

const Config = require("../Config")
const Network = require("./Network")
const Types = require("./Types")

local Server = {}

local StateMachineConfig = Config.STATE_MACHINE or {}
local Started = false

export type Machine = Types.Machine

type Record = {
	Id: string,
	Targets: { Player }?,
	Connection: any,
	DestroyConnection: any,
}

local MachineRecordsById = (setmetatable({}, { __mode = "v" }) :: any) :: { [string]: Record }
local MachineRecordsByMachine = (setmetatable({}, { __mode = "k" }) :: any) :: { [Machine]: Record }
local MachinesById = (setmetatable({}, { __mode = "v" }) :: any) :: { [string]: Machine }
local CachedStatesByMachine = (setmetatable({}, { __mode = "k" }) :: any) :: { [Machine]: { [string]: any } }

local function get_current_name(machine: Machine): string?
	local current = machine:GetCurrent()
	if current == nil then
		return nil
	end

	return current.Name
end

local function build_payload(machine: Machine, record: Record, context: any?): { [string]: any }
	return {
		Id = record.Id,
		State = get_current_name(machine),
		Running = machine:IsRunning(),
		ClientAuthoritative = machine:IsClientAuthoritative(),
		Context = context,
	}
end

local function resolve_request_id(request): string?
	if type(request) == "string" then
		return request
	end

	if type(request) ~= "table" then
		return nil
	end

	local request_id = request.Id or request.id
	if type(request_id) ~= "string" then
		return nil
	end

	return request_id
end

local function resolve_payload_id(payload): string?
	if type(payload) ~= "table" then
		return nil
	end

	local payload_id = payload.Id or payload.id
	if type(payload_id) ~= "string" then
		return nil
	end

	return payload_id
end

local function resolve_cached_state(machine: Machine, state_name: string)
	local cache = CachedStatesByMachine[machine]
	if cache == nil then
		cache = {}
		CachedStatesByMachine[machine] = cache
	end

	local cached_state = cache[state_name]
	if cached_state ~= nil then
		return cached_state
	end

	local resolved = machine:GetState(state_name)
	if resolved ~= nil then
		cache[state_name] = resolved
	end

	return resolved
end

local function apply_client_payload(machine: Machine, payload: { [string]: any }, source: Player?)
	local running = payload.Running == true
	local state_name = payload.State
	local context = payload.Context

	if not running then
		if machine:IsRunning() then
			machine:Stop(context, source)
		end
		return
	end

	if type(state_name) ~= "string" then
		return
	end

	local target = resolve_cached_state(machine, state_name)
	if target == nil then
		return
	end

	if not machine:IsRunning() then
		machine:SetInitial(target)
		machine:Start(context, source)
		return
	end

	if machine:GetCurrent() ~= target then
		machine:Transition(target, context, source)
	end
end

local function is_target_player(targets: { Player }, player: Player?): boolean
	if not player then
		return false
	end

	for index = 1, #targets do
		if targets[index] == player then
			return true
		end
	end

	return false
end

local function send_payload(payload: { [string]: any }, targets: { Player }?, exclude_player: Player?)
	if StateMachineConfig.ENABLED == false or StateMachineConfig.SYNC_CLIENT == false then
		return
	end

	if targets == nil then
		if exclude_player == nil then
			Network.packets.MachineUpdated.sendToAll(payload)
			return
		end

		local players = Players:GetPlayers()
		local active_targets = {}
		for index = 1, #players do
			local player = players[index]
			if player == exclude_player then
				continue
			end

			if player and player.Parent then
				active_targets[#active_targets + 1] = player
			end
		end

		if #active_targets == 0 then
			return
		end

		Network.packets.MachineUpdated.sendToList(payload, active_targets)
		return
	end

	local active_targets = {}
	for index = 1, #targets do
		local player = targets[index]
		if player == exclude_player then
			continue
		end
		if player and player.Parent then
			active_targets[#active_targets + 1] = player
		end
	end

	if #active_targets == 0 then
		return
	end

	Network.packets.MachineUpdated.sendToList(payload, active_targets)
end

function Server:Init()
	if Started then
		return
	end

	Started = true

	if not RunService:IsServer() or StateMachineConfig.ENABLED == false then
		return
	end

	if StateMachineConfig.SYNC_CLIENT == false then
		return
	end

	Network.queries.RequestState.listen(function(request, player)
		local request_id = resolve_request_id(request)
		if request_id == nil then
			return nil
		end

		local record = MachineRecordsById[request_id]
		local machine = MachinesById[request_id]
		if record == nil or machine == nil then
			return nil
		end

		if record.Targets and not is_target_player(record.Targets, player) then
			return nil
		end

		return build_payload(machine, record, nil)
	end)

	Network.packets.ClientMachineUpdated.listen(function(payload, player)
		if player == nil then
			return
		end

		local payload_id = resolve_payload_id(payload)
		if payload_id == nil then
			return
		end

		local record = MachineRecordsById[payload_id]
		local machine = MachinesById[payload_id]
		if record == nil or machine == nil then
			return
		end

		if not machine:IsClientAuthoritative() then
			return
		end

		if record.Targets and not is_target_player(record.Targets, player) then
			return
		end

		apply_client_payload(machine, payload, player)
	end)
end

function Server:Register(machine: Machine, targets: { Player }?): boolean
	if not machine then
		return false
	end

	local machine_id = machine:GetId()
	if type(machine_id) ~= "string" then
		return false
	end

	local existing_machine = MachinesById[machine_id]
	if existing_machine and existing_machine ~= machine then
		return false
	end

	local record = MachineRecordsById[machine_id]
	if record == nil then
		record = {
			Id = machine_id,
			Targets = targets,
			Connection = nil,
			DestroyConnection = nil,
		}

		MachineRecordsById[machine_id] = record
	end

	MachineRecordsByMachine[machine] = record
	MachinesById[machine_id] = machine
	CachedStatesByMachine[machine] = CachedStatesByMachine[machine] or {}
	record.Targets = targets

	if record.Connection == nil then
		record.Connection = machine.Transitioned:Connect(function(_machine, _previous, _current, context, source_player)
			local payload = build_payload(_machine, record, context)
			send_payload(payload, record.Targets, source_player)
		end)
	end

	if record.DestroyConnection == nil then
		record.DestroyConnection = machine.Destroyed:Connect(function()
			self:Unregister(machine)
		end)
	end

	self:Sync(machine)
	return true
end

function Server:Unregister(machine: Machine): boolean
	local record = MachineRecordsByMachine[machine]
	if record == nil then
		return false
	end

	if record.Connection then
		record.Connection:Disconnect()
	end

	if record.DestroyConnection then
		record.DestroyConnection:Disconnect()
	end

	MachineRecordsByMachine[machine] = nil
	MachineRecordsById[record.Id] = nil
	MachinesById[record.Id] = nil
	CachedStatesByMachine[machine] = nil
	return true
end

function Server:SetTargets(machine: Machine, targets: { Player }?): boolean
	local record = MachineRecordsByMachine[machine]
	if record == nil then
		return false
	end

	record.Targets = targets
	return true
end

function Server:Sync(machine: Machine, targets: { Player }?): boolean
	local record = MachineRecordsByMachine[machine]
	if record == nil then
		return false
	end

	local payload = build_payload(machine, record, nil)
	send_payload(payload, targets or record.Targets)
	return true
end

function Server:Start()
	if
		not RunService:IsServer()
		or StateMachineConfig.ENABLED == false
		or StateMachineConfig.AUTO_START_SERVER == false
	then
		return
	end

	self:Init()
end

return Server
