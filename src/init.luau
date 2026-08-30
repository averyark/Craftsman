--!nonstrict
const RunService = game:GetService("RunService")

export type Craftsman = {
	Component: typeof(require("@self/Component")),
	Debounce: typeof(require("@self/Debounce")),
	Concurrency: typeof(require("@self/Concurrency")),
	Queue: typeof(require("@self/Queue")),
	State: typeof(require("@self/StateMachine/State")),
	Machine: typeof(require("@self/StateMachine/Machine")),
	Pathfind: typeof(require("@self/Pathfind")),
	Spring: typeof(require("@self/Spring")),

	Entity: typeof(require("@self/Entity")),

	DataServer: typeof(require("@self/Data/Server")),
	DataClient: typeof(require("@self/Data/Client")),
	MarketServer: typeof(require("@self/Market/Server")),
	MarketClient: typeof(require("@self/Market/Client")),
	StateMachine: typeof(require("@self/StateMachine")),
	StateMachineServer: typeof(require("@self/StateMachine/Server")),
	StateMachineClient: typeof(require("@self/StateMachine/Client")),

	StoreServer: typeof(require("@self/Store/Server")),
	StoreClient: typeof(require("@self/Store/Client")),

	InputUtil: typeof(require("@self/Utilities/InputUtil")),
	TouchUtil: typeof(require("@self/Utilities/TouchUtil")),
	InterfaceUtil: typeof(require("@self/Utilities/InterfaceUtil")),
	PrintUtil: typeof(require("@self/Utilities/PrintUtil")),
	TableUtil: typeof(require("@self/Utilities/TableUtil")),
	WorldUtil: typeof(require("@self/Utilities/WorldUtil")),

	AnimationUtil: typeof(require("@self/Utilities/AnimationUtil")),
	SoundUtil: typeof(require("@self/Utilities/SoundUtil")),
	TweenUtil: typeof(require("@self/Utilities/TweenUtil")),
	Tag: typeof(require("@self/Tag")),

	MathUtil: typeof(require("@self/Utilities/MathUtil")),
	StringUtil: typeof(require("@self/Utilities/StringUtil")),

	Config: typeof(require("@self/Config")),
	Store: typeof(require("@self/Store")),
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
	TouchUtil = function()
		return require("@self/Utilities/TouchUtil")
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
