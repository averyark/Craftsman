--!nonstrict
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

local StateMachineConfig = Config.STATE_MACHINE or {}
local Initialized = false
local Started = false

export type Machine = Types.Machine

local MachinesById = (setmetatable({}, { __mode = "v" }) :: any) :: { [string]: Machine }
local MachineIdsByMachine = (setmetatable({}, { __mode = "k" }) :: any) :: { [Machine]: string }
local ClientConnectionsByMachine = (setmetatable({}, { __mode = "k" }) :: any) :: { [Machine]: any }
local SuppressClientSendByMachine = (setmetatable({}, { __mode = "k" }) :: any) :: { [Machine]: boolean }
local DestroyConnectionsByMachine = (setmetatable({}, { __mode = "k" }) :: any) :: { [Machine]: any }
local CachedStatesByMachine = (setmetatable({}, { __mode = "k" }) :: any) :: { [Machine]: { [string]: any } }

local function get_current_name(machine: Machine): string?
	local current = machine:GetCurrent()
	if current == nil then
		return nil
	end

	return current.Name
end

local function build_payload(machine: Machine, machine_id: string, context: any?): { [string]: any }
	return {
		Id = machine_id,
		State = get_current_name(machine),
		Running = machine:IsRunning(),
		ClientAuthoritative = machine:IsClientAuthoritative(),
		Context = context,
	}
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

local function apply_payload(machine: Machine, payload: { [string]: any })
	SuppressClientSendByMachine[machine] = true
	local running = payload.Running == true
	local state_name = payload.State
	local context = payload.Context

	if not running then
		if machine:IsRunning() then
			machine:Stop(context)
		end
		SuppressClientSendByMachine[machine] = nil
		return
	end

	if type(state_name) ~= "string" then
		SuppressClientSendByMachine[machine] = nil
		return
	end

	local target = resolve_cached_state(machine, state_name)
	if target == nil then
		SuppressClientSendByMachine[machine] = nil
		return
	end

	if not machine:IsRunning() then
		machine:SetInitial(target)
		machine:Start(context)
		SuppressClientSendByMachine[machine] = nil
		return
	end

	if machine:GetCurrent() ~= target then
		machine:Transition(target, context)
	end

	SuppressClientSendByMachine[machine] = nil
end

local function request_state(machine_id: string, machine: Machine)
	task.spawn(function()
		local ok, payload = pcall(function()
			return Network.queries.RequestState.invoke(machine_id)
		end)

		if not ok or type(payload) ~= "table" then
			return
		end

		apply_payload(machine, payload)
	end)
end

local function ensure_client_connection(machine: Machine, machine_id: string)
	local connection = ClientConnectionsByMachine[machine]
	if not machine:IsClientAuthoritative() then
		if connection then
			connection:Disconnect()
			ClientConnectionsByMachine[machine] = nil
		end
		return
	end

	if connection then
		return
	end

	ClientConnectionsByMachine[machine] = machine.Transitioned:Connect(
		function(_machine, _previous, _current, context, _source)
			if SuppressClientSendByMachine[_machine] then
				return
			end

			if not Started or StateMachineConfig.ENABLED == false or StateMachineConfig.AUTO_START_CLIENT == false then
				return
			end

			local payload = build_payload(_machine, machine_id, context)
			Network.packets.ClientMachineUpdated.send(payload)
		end
	)
end

function Client:Init()
	if Initialized then
		return
	end

	Initialized = true

	if
		not RunService:IsClient()
		or StateMachineConfig.ENABLED == false
		or StateMachineConfig.AUTO_START_CLIENT == false
	then
		return
	end

	Network.packets.MachineUpdated.listen(function(payload)
		local payload_id = resolve_payload_id(payload)
		if payload_id == nil then
			return
		end

		local machine = MachinesById[payload_id]
		if machine == nil then
			return
		end

		apply_payload(machine, payload)
	end)
end

function Client:Register(machine: Machine): boolean
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

	MachinesById[machine_id] = machine
	MachineIdsByMachine[machine] = machine_id
	ensure_client_connection(machine, machine_id)
	CachedStatesByMachine[machine] = CachedStatesByMachine[machine] or {}

	if DestroyConnectionsByMachine[machine] == nil then
		DestroyConnectionsByMachine[machine] = machine.Destroyed:Connect(function()
			self:Unregister(machine)
		end)
	end

	if Started then
		request_state(machine_id, machine)
	end

	return true
end

function Client:Unregister(machine: Machine): boolean
	local machine_id = MachineIdsByMachine[machine]
	if machine_id == nil then
		return false
	end

	local connection = ClientConnectionsByMachine[machine]
	if connection then
		connection:Disconnect()
	end

	local destroy_connection = DestroyConnectionsByMachine[machine]
	if destroy_connection then
		destroy_connection:Disconnect()
	end

	MachineIdsByMachine[machine] = nil
	MachinesById[machine_id] = nil
	ClientConnectionsByMachine[machine] = nil
	SuppressClientSendByMachine[machine] = nil
	DestroyConnectionsByMachine[machine] = nil
	CachedStatesByMachine[machine] = nil
	return true
end

function Client:Sync(machine: Machine): boolean
	local machine_id = MachineIdsByMachine[machine]
	if machine_id == nil then
		return false
	end

	request_state(machine_id, machine)
	return true
end

function Client:Start()
	if
		not RunService:IsClient()
		or StateMachineConfig.ENABLED == false
		or StateMachineConfig.AUTO_START_CLIENT == false
	then
		return
	end

	self:Init()
	Started = true

	for machine_id, machine in MachinesById do
		ensure_client_connection(machine, machine_id)
		request_state(machine_id, machine)
	end
end

return Client
