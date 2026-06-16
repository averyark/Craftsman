const RunService = game:GetService("RunService")

const Component = require("@self/Component")
const Config = require("@self/Config")
local DataServer = nil
local DataClient = require("@self/Data/Client")
local MarketServer = nil
local MarketClient = require("@self/Market/Client")
local StateMachineServer = nil
local StateMachineClient = require("@self/StateMachine/Client")
local StoreServer = nil
local StoreClient = require("@self/Store/Client")
const Queue = require("@self/Queue")
const StringUtil = require("@self/Utilities/StringUtil")
const AnimationUtil = require("@self/Utilities/AnimationUtil")
const InputUtil = require("@self/Utilities/InputUtil")
const MathUtil = require("@self/Utilities/MathUtil")
const PrintUtil = require("@self/Utilities/PrintUtil")
const SoundUtil = require("@self/Utilities/SoundUtil")
const TableUtil = require("@self/Utilities/TableUtil")
const TweenUtil = require("@self/Utilities/TweenUtil")
const Tag = require("@self/Tag")
const Debounce = require("@self/Debounce")
const Concurrency = require("@self/Concurrency")

if RunService:IsServer() then
	DataServer = require("@self/Data/Server")
	MarketServer = require("@self/Market/Server")
	StateMachineServer = require("@self/StateMachine/Server")
	StoreServer = require("@self/Store/Server")
end

const Entity = require("@self/Entity")
const Pathfind = require("@self/Pathfind")

local StateMachine = require("@self/StateMachine")
local Machine = require("@self/StateMachine/Machine")

local State = require("@self/StateMachine/State")
const WorldUtil = require("@self/Utilities/WorldUtil")
const Store = require("@self/Store")

local Craftsman = {
	Component = Component, -- Module Loader
	Debounce = Debounce, -- Debouncing and Throttling
	Concurrency = Concurrency, -- Keyed Concurrency Control (AsyncLock & KeyedDebounce)
	Queue = Queue, -- Task Queue System,
	State = State, -- State Machine State
	Machine = Machine, -- State Machine
	Pathfind = Pathfind,

	Entity = Entity,

	DataServer = DataServer, -- Server Data Manipulation
	DataClient = DataClient, -- Client Data Access
	MarketServer = MarketServer, -- Server Marketplace Logic
	MarketClient = MarketClient, -- Client Marketplace Access
	StateMachine = StateMachine, -- State Machine Namespace
	StateMachineServer = StateMachineServer, -- Server State Machine Replication
	StateMachineClient = StateMachineClient, -- Client State Machine Replication

	StoreServer = StoreServer, -- Server Store Replication
	StoreClient = StoreClient, -- Client Store Replication

	InputUtil = InputUtil, -- User Input Handling
	PrintUtil = PrintUtil, -- Debugging and Printing
	TableUtil = TableUtil, -- Table Manipulation Utilities
	WorldUtil = WorldUtil, -- World and Instance Utilities

	AnimationUtil = AnimationUtil, -- Animation Handling
	SoundUtil = SoundUtil, -- Sound Handling
	TweenUtil = TweenUtil, -- Tween Handling
	Tag = Tag, -- Instance Tag Utility

	MathUtil = MathUtil, -- Math Utilities
	StringUtil = StringUtil, -- String Utilities

	Config = Config, -- Configuration Management
	Store = Store, -- Store Utility
}

-- Custom configuration (ReplicatedStorage.CraftsmanConfig) is merged into the defaults
-- by Config.luau at load time. That is the single source of truth; do not re-merge here.

return Craftsman
