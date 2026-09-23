--!strict
--[[
    FileName    > Client.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 30/05/2026
--]]

const RunService = game:GetService("RunService")

const Config = require("../Config")
const Network = require("./Network")
const Types = require("./Types")

local Client = {}

--
type Client = typeof(Client)

type ClientConfig = {
	ENABLED: boolean?,
	AUTO_START_CLIENT: boolean?,
}
--

--
const StateMachineConfig = (Config.STATE_MACHINE or {}) :: ClientConfig
local Initialized = false
local Started = false
--

--
export type Machine = Types.Machine

const MachinesById: { [string]: Machine } = {}
const MachineIdsByMachine: { [Machine]: string } = {}
const ClientConnectionsByMachine: { [Machine]: any } = {}

const SERVER_SOURCE = newproxy(false)
const DestroyConnectionsByMachine: { [Machine]: any } = {}
const CachedStatesByMachine = (setmetatable({}, { __mode = "k" }) :: any) :: { [Machine]: { [string]: Types.State } }
const LastSequenceByMachine = (setmetatable({}, { __mode = "k" }) :: any) :: { [Machine]: number }
--

local function get_current_name(machine: Machine): string?
	--
	const current = machine:GetCurrent()

	if current == nil then
		return nil
	end
	--

	return current.Name
end

local function build_payload(machine: Machine, machine_id: string, context: any?): Network.MachinePayload
	return {
		Id = machine_id,
		State = get_current_name(machine),
		Running = machine:IsRunning(),
		ClientAuthoritative = machine:IsClientAuthoritative(),
		Context = context,
	}
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

local function resolve_payload_id(payload: unknown): string?
	--
	if type(payload) ~= "table" then
		return nil
	end
	--

	--
	const fields = payload :: { [string]: unknown }
	const payload_id = fields.Id or fields.id

	if type(payload_id) ~= "string" then
		return nil
	end
	--

	return payload_id
end

local function accept_sequence(machine: Machine, sequence: number?): boolean
	--
	if type(sequence) ~= "number" then
		return true
	end

	const last = LastSequenceByMachine[machine]

	if last ~= nil and sequence <= last then
		return false
	end
	--

	--
	LastSequenceByMachine[machine] = sequence
	--

	return true
end

local function apply_payload(machine: Machine, payload: Network.MachinePayload)
	--
	if not accept_sequence(machine, payload.Sequence) then
		return
	end
	--

	--
	const running = payload.Running == true
	const state_name = payload.State
	const context = payload.Context

	if not running and not machine:IsRunning() then
		return
	end

	if not running then
		machine:Stop(context, SERVER_SOURCE)
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
		machine:Start(context, SERVER_SOURCE)
		return
	end
	--

	--
	if machine:GetCurrent() == target then
		return
	end
	--

	machine:Transition(target, context, SERVER_SOURCE)
end

local function request_state(machine_id: string, machine: Machine)
	task.spawn(function()
		--
		const ok, payload = pcall(function()
			return Network.queries.RequestState.invoke(machine_id)
		end)

		if not ok or type(payload) ~= "table" then
			return
		end
		--

		apply_payload(machine, payload)
	end)
end

local function release_client_connection(machine: Machine)
	--
	const connection = ClientConnectionsByMachine[machine]

	if not connection then
		return
	end
	--

	--
	connection:Disconnect()
	ClientConnectionsByMachine[machine] = nil
	--
end

local function ensure_client_connection(machine: Machine, machine_id: string)
	--
	if not machine:IsClientAuthoritative() then
		release_client_connection(machine)
		return
	end

	if ClientConnectionsByMachine[machine] then
		return
	end
	--

	--
	ClientConnectionsByMachine[machine] = machine.Transitioned:Connect(
		function(_machine, _previous, _current, context, _source)
			if _source == SERVER_SOURCE then
				return
			end

			if not Started or StateMachineConfig.ENABLED == false or StateMachineConfig.AUTO_START_CLIENT == false then
				return
			end

			const payload = build_payload(_machine, machine_id, context)
			Network.packets.ClientMachineUpdated.send(payload)
		end
	)
	--
end

function Client.Init(self: Client)
	--
	if Initialized then
		return
	end

	Initialized = true
	--

	--
	if
		not RunService:IsClient()
		or StateMachineConfig.ENABLED == false
		or StateMachineConfig.AUTO_START_CLIENT == false
	then
		return
	end
	--

	Network.packets.MachineUpdated.listen(function(payload)
		--
		const payload_id = resolve_payload_id(payload)

		if payload_id == nil then
			return
		end

		const machine = MachinesById[payload_id]

		if machine == nil then
			return
		end
		--

		--
		apply_payload(machine, payload)
		--
	end)
end

function Client.Register(self: Client, machine: Machine): boolean
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
	MachinesById[machine_id] = machine
	MachineIdsByMachine[machine] = machine_id

	ensure_client_connection(machine, machine_id)

	CachedStatesByMachine[machine] = CachedStatesByMachine[machine] or {}
	--

	--
	if DestroyConnectionsByMachine[machine] == nil then
		DestroyConnectionsByMachine[machine] = machine.Destroyed:Connect(function()
			self:Unregister(machine)
		end)
	end
	--

	--
	if Started then
		request_state(machine_id, machine)
	end
	--

	return true
end

function Client.Unregister(self: Client, machine: Machine): boolean
	--
	const machine_id = MachineIdsByMachine[machine]

	if machine_id == nil then
		return false
	end
	--

	--
	release_client_connection(machine)

	const destroy_connection = DestroyConnectionsByMachine[machine]

	if destroy_connection then
		destroy_connection:Disconnect()
	end
	--

	--
	MachineIdsByMachine[machine] = nil
	MachinesById[machine_id] = nil
	DestroyConnectionsByMachine[machine] = nil
	CachedStatesByMachine[machine] = nil
	LastSequenceByMachine[machine] = nil
	--

	return true
end

function Client.Sync(self: Client, machine: Machine): boolean
	--
	const machine_id = MachineIdsByMachine[machine]

	if machine_id == nil then
		return false
	end
	--

	--
	request_state(machine_id, machine)
	--

	return true
end

function Client.Start(self: Client)
	--
	if
		not RunService:IsClient()
		or StateMachineConfig.ENABLED == false
		or StateMachineConfig.AUTO_START_CLIENT == false
	then
		return
	end
	--

	--
	self:Init()
	Started = true
	--

	--
	for machine_id, machine in MachinesById do
		ensure_client_connection(machine, machine_id)
		request_state(machine_id, machine)
	end
	--
end

return Client
