--!strict
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

--
type Server = typeof(Server)

type ServerConfig = {
	ENABLED: boolean?,
	AUTO_START_SERVER: boolean?,
	SYNC_CLIENT: boolean?,
	CLIENT_UPDATE_MIN_INTERVAL: number?,
}

type ClientPayload = { [string]: unknown }
--

--
const StateMachineConfig = (Config.STATE_MACHINE or {}) :: ServerConfig
local Started = false
--

--
const CLIENT_UPDATE_MIN_INTERVAL = StateMachineConfig.CLIENT_UPDATE_MIN_INTERVAL or 0.05
const LastClientUpdate = (setmetatable({}, { __mode = "k" }) :: any) :: { [Player]: { [string]: number } }
--

--
export type Machine = Types.Machine

type Record = {
	Id: string,
	Targets: { Player }?,
	Connection: any,
	DestroyConnection: any,
	Sequence: number,
}

const MachineRecordsById: { [string]: Record } = {}
const MachineRecordsByMachine: { [Machine]: Record } = {}
const MachinesById: { [string]: Machine } = {}
const CachedStatesByMachine = (setmetatable({}, { __mode = "k" }) :: any) :: { [Machine]: { [string]: Types.State } }
--

local function is_valid_client_context(context: any): boolean
	return context == nil or type(context) == "table"
end

local function get_current_name(machine: Machine): string?
	--
	const current = machine:GetCurrent()

	if current == nil then
		return nil
	end
	--

	return current.Name
end

local function build_payload(machine: Machine, record: Record, context: any?): Network.MachinePayload
	return {
		Id = record.Id,
		State = get_current_name(machine),
		Running = machine:IsRunning(),
		ClientAuthoritative = machine:IsClientAuthoritative(),
		Context = context,
		Sequence = record.Sequence or 0,
	}
end

local function resolve_request_id(request: unknown): string?
	--
	if type(request) == "string" then
		return request
	end

	if type(request) ~= "table" then
		return nil
	end
	--

	--
	const fields = request :: ClientPayload
	const request_id = fields.Id or fields.id

	if type(request_id) ~= "string" then
		return nil
	end
	--

	return request_id
end

local function resolve_payload_id(payload: unknown): string?
	--
	if type(payload) ~= "table" then
		return nil
	end
	--

	--
	const fields = payload :: ClientPayload
	const payload_id = fields.Id or fields.id

	if type(payload_id) ~= "string" then
		return nil
	end
	--

	return payload_id
end

local function resolve_cached_state(machine: Machine, state_name: string): Types.State?
	--
	const cache = CachedStatesByMachine[machine] or {}
	CachedStatesByMachine[machine] = cache
	--

	--
	const cached_state = cache[state_name]

	if cached_state ~= nil then
		return cached_state
	end
	--

	--
	const resolved = machine:GetState(state_name)

	if resolved == nil then
		return nil
	end
	--

	--
	cache[state_name] = resolved
	--

	return resolved
end

local function apply_client_payload(machine: Machine, payload: ClientPayload, source: Player?)
	--
	const running = payload.Running == true
	const state_name = payload.State
	const context = payload.Context

	if not running and not machine:IsRunning() then
		return
	end

	if not running then
		machine:Stop(context, source)
		return
	end
	--

	--
	if type(state_name) ~= "string" then
		return
	end

	const target = resolve_cached_state(machine, state_name)

	if target == nil then
		return
	end

	if not machine:IsRunning() then
		machine:SetInitial(target)
		machine:Start(context, source)
		return
	end
	--

	--
	if machine:GetCurrent() == target then
		return
	end
	--

	machine:Transition(target, context, source)
end

local function is_target_player(targets: { Player }, player: Player?): boolean
	--
	if not player then
		return false
	end
	--

	--
	for _, target in targets do
		if target ~= player then
			continue
		end

		return true
	end
	--

	return false
end

local function collect_active_targets(candidates: { Player }, exclude_player: Player?): { Player }
	--
	const active_targets = {}

	for _, player in candidates do
		if player == exclude_player then
			continue
		end

		if not player or not player.Parent then
			continue
		end

		active_targets[#active_targets + 1] = player
	end
	--

	return active_targets
end

local function send_payload(payload: Network.MachinePayload, targets: { Player }?, exclude_player: Player?)
	--
	if StateMachineConfig.ENABLED == false or StateMachineConfig.SYNC_CLIENT == false then
		return
	end
	--

	--
	if targets == nil and exclude_player == nil then
		Network.packets.MachineUpdated.sendToAll(payload)
		return
	end
	--

	--
	const active_targets = collect_active_targets(targets or Players:GetPlayers(), exclude_player)

	if #active_targets == 0 then
		return
	end
	--

	Network.packets.MachineUpdated.sendToList(payload, active_targets)
end

local function ensure_record(machine_id: string, targets: { Player }?): Record
	--
	const existing_record = MachineRecordsById[machine_id]

	if existing_record ~= nil then
		return existing_record
	end
	--

	--
	const record: Record = {
		Id = machine_id,
		Targets = targets,
		Connection = nil,
		DestroyConnection = nil,
		Sequence = 0,
	}

	MachineRecordsById[machine_id] = record
	--

	return record
end

function Server.Init(self: Server)
	--
	if Started then
		return
	end

	Started = true
	--

	--
	if not RunService:IsServer() or StateMachineConfig.ENABLED == false then
		return
	end

	if StateMachineConfig.SYNC_CLIENT == false then
		return
	end
	--

	Network.queries.RequestState.listen(function(request, player)
		--
		const request_id = resolve_request_id(request)

		if request_id == nil then
			return nil
		end

		const record = MachineRecordsById[request_id]
		const machine = MachinesById[request_id]

		if record == nil or machine == nil then
			return nil
		end
		--

		--
		if record.Targets and not is_target_player(record.Targets, player) then
			return nil
		end
		--

		return build_payload(machine, record, nil)
	end)

	Network.packets.ClientMachineUpdated.listen(function(payload, player)
		--
		if player == nil then
			return
		end

		const payload_id = resolve_payload_id(payload)

		if payload_id == nil then
			return
		end

		const record = MachineRecordsById[payload_id]
		const machine = MachinesById[payload_id]

		if record == nil or machine == nil then
			return
		end
		--

		--
		if not machine:IsClientAuthoritative() then
			return
		end

		if record.Targets and not is_target_player(record.Targets, player) then
			return
		end

		if not is_valid_client_context((payload :: ClientPayload).Context) then
			return
		end
		--

		--
		const now = os.clock()
		const player_times = LastClientUpdate[player] or {}
		LastClientUpdate[player] = player_times

		const last = player_times[payload_id]

		if last ~= nil and now - last < CLIENT_UPDATE_MIN_INTERVAL then
			return
		end
		--

		--
		player_times[payload_id] = now
		--

		apply_client_payload(machine, payload :: ClientPayload, player)
	end)
end

function Server.Register(self: Server, machine: Machine, targets: { Player }?): boolean
	--
	if not machine then
		return false
	end

	const machine_id = machine:GetId()

	if type(machine_id) ~= "string" then
		return false
	end

	const existing_machine = MachinesById[machine_id]

	if existing_machine and existing_machine ~= machine then
		return false
	end
	--

	--
	const record = ensure_record(machine_id, targets)

	MachineRecordsByMachine[machine] = record
	MachinesById[machine_id] = machine
	CachedStatesByMachine[machine] = CachedStatesByMachine[machine] or {}
	record.Targets = targets
	--

	--
	if record.Connection == nil then
		record.Connection = machine.Transitioned:Connect(function(_machine, _previous, _current, context, source_player)
			record.Sequence = (record.Sequence or 0) + 1

			const payload = build_payload(_machine, record, context)
			send_payload(payload, record.Targets, source_player)
		end)
	end
	--

	--
	if record.DestroyConnection == nil then
		record.DestroyConnection = machine.Destroyed:Connect(function()
			self:Unregister(machine)
		end)
	end
	--

	--
	self:Sync(machine)
	--

	return true
end

function Server.Unregister(self: Server, machine: Machine): boolean
	--
	const record = MachineRecordsByMachine[machine]

	if record == nil then
		return false
	end
	--

	--
	if record.Connection then
		record.Connection:Disconnect()
	end

	if record.DestroyConnection then
		record.DestroyConnection:Disconnect()
	end
	--

	--
	MachineRecordsByMachine[machine] = nil
	MachineRecordsById[record.Id] = nil
	MachinesById[record.Id] = nil
	CachedStatesByMachine[machine] = nil
	--

	return true
end

function Server.SetTargets(self: Server, machine: Machine, targets: { Player }?): boolean
	--
	const record = MachineRecordsByMachine[machine]

	if record == nil then
		return false
	end
	--

	--
	record.Targets = targets
	--

	return true
end

function Server.Sync(self: Server, machine: Machine, targets: { Player }?): boolean
	--
	const record = MachineRecordsByMachine[machine]

	if record == nil then
		return false
	end
	--

	--
	const payload = build_payload(machine, record, nil)
	send_payload(payload, targets or record.Targets)
	--

	return true
end

function Server.Start(self: Server)
	--
	if
		not RunService:IsServer()
		or StateMachineConfig.ENABLED == false
		or StateMachineConfig.AUTO_START_SERVER == false
	then
		return
	end
	--

	self:Init()
end

return Server
