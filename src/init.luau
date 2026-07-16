--!nonstrict
const RunService = game:GetService("RunService")

export type Craftsman = {
	Component: typeof(require("@self/Component")), -- Module Loader
	Debounce: typeof(require("@self/Debounce")), -- Debouncing and Throttling
	Concurrency: typeof(require("@self/Concurrency")), -- Keyed Concurrency Control (AsyncLock and KeyedDebounce)
	Queue: typeof(require("@self/Queue")), -- Task Queue System
	State: typeof(require("@self/StateMachine/State")), -- State Machine State
	Machine: typeof(require("@self/StateMachine/Machine")), -- State Machine
	Pathfind: typeof(require("@self/Pathfind")), -- Simple Pathfinding, cover most usecases
	Spring: typeof(require("@self/Spring")), -- Spring System

	Entity: typeof(require("@self/Entity")), -- Character or NPC abstraction

	DataServer: typeof(require("@self/Data/Server")), -- Server Data Manipulation
	DataClient: typeof(require("@self/Data/Client")), -- Client Data Access
	MarketServer: typeof(require("@self/Market/Server")), -- Server Marketplace Logic
	MarketClient: typeof(require("@self/Market/Client")), -- Client Marketplace Access
	StateMachine: typeof(require("@self/StateMachine")), -- State Machine Namespace
	StateMachineServer: typeof(require("@self/StateMachine/Server")), -- Server State Machine Replication
	StateMachineClient: typeof(require("@self/StateMachine/Client")), -- Client State Machine Replication

	StoreServer: typeof(require("@self/Store/Server")), -- Server Store Replication
	StoreClient: typeof(require("@self/Store/Client")), -- Client Store Replication

	InputUtil: typeof(require("@self/Utilities/InputUtil")), -- User Input Handling
	InterfaceUtil: typeof(require("@self/Utilities/InterfaceUtil")), -- Interface Scaling
	PrintUtil: typeof(require("@self/Utilities/PrintUtil")), -- Debugging and Printing
	TableUtil: typeof(require("@self/Utilities/TableUtil")), -- Table Manipulation Utilities
	WorldUtil: typeof(require("@self/Utilities/WorldUtil")), -- World and Instance Utilities

	AnimationUtil: typeof(require("@self/Utilities/AnimationUtil")), -- Animation Handling
	SoundUtil: typeof(require("@self/Utilities/SoundUtil")), -- Sound Handling
	TweenUtil: typeof(require("@self/Utilities/TweenUtil")), -- Tween Handling
	Tag: typeof(require("@self/Tag")), -- Instance Tag Utility

	MathUtil: typeof(require("@self/Utilities/MathUtil")), -- Math Utilities
	StringUtil: typeof(require("@self/Utilities/StringUtil")), -- String Utilities

	Config: typeof(require("@self/Config")), -- Configuration Management
	Store: typeof(require("@self/Store")), -- Store Utility
}

local loaders: { [string]: () -> any } = {
	Component = function()
		return require("@self/Component")
	end,
	Debounce = function()
		return require("@self/Debounce")
	end,
	Concurrency = function()
		return require("@self/Concurrency")
	end,
	Queue = function()
		return require("@self/Queue")
	end,
	State = function()
		return require("@self/StateMachine/State")
	end,
	Machine = function()
		return require("@self/StateMachine/Machine")
	end,
	Pathfind = function()
		return require("@self/Pathfind")
	end,
	Spring = function()
		return require("@self/Spring")
	end,

	Entity = function()
		return require("@self/Entity")
	end,

	DataServer = function()
		return require("@self/Data/Server")
	end,
	DataClient = function()
		return require("@self/Data/Client")
	end,
	MarketServer = function()
		return require("@self/Market/Server")
	end,
	MarketClient = function()
		return require("@self/Market/Client")
	end,
	StateMachine = function()
		return require("@self/StateMachine")
	end,
	StateMachineServer = function()
		return require("@self/StateMachine/Server")
	end,
	StateMachineClient = function()
		return require("@self/StateMachine/Client")
	end,

	StoreServer = function()
		return require("@self/Store/Server")
	end,
	StoreClient = function()
		return require("@self/Store/Client")
	end,

	InterfaceUtil = function()
		return require("@self/Utilities/InterfaceUtil")
	end,
	InputUtil = function()
		return require("@self/Utilities/InputUtil")
	end,
	PrintUtil = function()
		return require("@self/Utilities/PrintUtil")
	end,
	TableUtil = function()
		return require("@self/Utilities/TableUtil")
	end,
	WorldUtil = function()
		return require("@self/Utilities/WorldUtil")
	end,

	AnimationUtil = function()
		return require("@self/Utilities/AnimationUtil")
	end,
	SoundUtil = function()
		return require("@self/Utilities/SoundUtil")
	end,
	TweenUtil = function()
		return require("@self/Utilities/TweenUtil")
	end,
	Tag = function()
		return require("@self/Tag")
	end,

	MathUtil = function()
		return require("@self/Utilities/MathUtil")
	end,
	StringUtil = function()
		return require("@self/Utilities/StringUtil")
	end,

	Config = function()
		return require("@self/Config")
	end,
	Store = function()
		return require("@self/Store")
	end,
}

local SERVER_ONLY = {
	DataServer = true,
	MarketServer = true,
	StateMachineServer = true,
	StoreServer = true,
}

local IS_SERVER = RunService:IsServer()

local Craftsman = setmetatable({}, {
	__index = function(self, key)
		local loader = loaders[key]
		if loader == nil then
			return nil
		end

		if SERVER_ONLY[key] and not IS_SERVER then
			return nil
		end

		local module = loader()
		rawset(self, key, module)
		return module
	end,
})

return (Craftsman :: any) :: Craftsman
