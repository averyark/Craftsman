const RunService = game:GetService("RunService")

const Component = require("@self/Component")
const Config = require("@self/Config")
local DataServer = nil
local DataClient = require("@self/Data/Client")
local MarketServer = nil
local MarketClient = require("@self/Market/Client")
const Entity = require("@self/Entity")
const Player = require("@self/Player")
const Queue = require("@self/Queue")
const StringUtil = require("@self/Utilities/StringUtil")
const AnimationUtil = require("@self/Utilities/AnimationUtil")
const InputUtil = require("@self/Utilities/InputUtil")
const MathUtil = require("@self/Utilities/MathUtil")
const PrintUtil = require("@self/Utilities/PrintUtil")
const SoundUtil = require("@self/Utilities/SoundUtil")
const TableUti = require("@self/Utilities/TableUtil")
const Tag = require("@self/Tag")

if RunService:IsServer() then
	DataServer = require("@self/Data/Server")
	MarketServer = require("@self/Market/Server")
end

const ReplicatedStorage = game:GetService("ReplicatedStorage")

local Craftsman = {
	Component = Component, -- Module Loader
	Player = Player, -- Player Management
	Entity = Entity, -- Character & Entity Management
	Queue = Queue, -- Task Queue System

	DataServer = DataServer, -- Server Data Manipulation
	DataClient = DataClient, -- Client Data Access
	MarketServer = MarketServer, -- Server Marketplace Logic
	MarketClient = MarketClient, -- Client Marketplace Access

	InputUtil = InputUtil, -- User Input Handling
	PrintUtil = PrintUtil, -- Debugging and Printing
	TableUtil = TableUti, -- Table Manipulation Utilities

	AnimationUtil = AnimationUtil, -- Animation Handling
	SoundUtil = SoundUtil, -- Sound Handling
	Tag = Tag, -- Instance Tag Utility

	MathUtil = MathUtil, -- Math Utilities
	StringUtil = StringUtil, -- String Utilities

	Config = Config, -- Configuration Management
}

-- Automatically load custom configuration if it exists
local custom_config_instance = ReplicatedStorage:FindFirstChild("CraftsmanConfig")
	or ReplicatedStorage:FindFirstChild("CraftmansConfig")

if custom_config_instance and custom_config_instance:IsA("ModuleScript") then
	local success, custom_config = pcall(require, custom_config_instance)
	if success and type(custom_config) == "table" then
		-- Apply configuration
		if
			custom_config.TEMPLATE ~= nil
			or custom_config.KEYS ~= nil
			or custom_config.PRODUCTS ~= nil
			or custom_config.GAMEPASSES ~= nil
		then
			if custom_config.TEMPLATE ~= nil then
				Config.DATA.TEMPLATE = custom_config.TEMPLATE
			end
			if custom_config.KEYS ~= nil then
				Config.MARKET.KEYS = custom_config.KEYS
			end
			if custom_config.PRODUCTS ~= nil then
				Config.MARKET.PRODUCTS = custom_config.PRODUCTS
			end
			if custom_config.GAMEPASSES ~= nil then
				Config.MARKET.GAMEPASSES = custom_config.GAMEPASSES
			end
		elseif custom_config.DATA ~= nil or custom_config.MARKET ~= nil or custom_config.MODULE_LOAD_ORDER ~= nil then
			Config:Edit(custom_config)
		end
	end
end

return Craftsman
