const RunService = game:GetService("RunService")

const Component = require("@self/Component")
const Config = require("@self/Config")
local DataServer = nil
local DataClient = require("@self/Data/Client")
local MarketServer = nil
local MarketClient = require("@self/Market/Client")
const Entity = require("@self/Entity")
const Player = require("@self/Player")
const StringUtil = require("@self/Utilities/StringUtil")
const AnimationUtil = require("@self/Utilities/AnimationUtil")
const InputUtil = require("@self/Utilities/InputUtil")
const MathUtil = require("@self/Utilities/MathUtil")
const PrintUtil = require("@self/Utilities/PrintUtil")
const SoundUtil = require("@self/Utilities/SoundUtil")
const TableUti = require("@self/Utilities/TableUtil")

if RunService:IsServer() then
	DataServer = require("@self/Data/Server")
	MarketServer = require("@self/Market/Server")
end

const ReplicatedStorage = game:GetService("ReplicatedStorage")

local Craftsman = {
	Component = Component,
	Player = Player,
	Entity = Entity,

	DataServer = DataServer,
	DataClient = DataClient,
	MarketServer = MarketServer,
	MarketClient = MarketClient,

	InputUtil = InputUtil,
	PrintUtil = PrintUtil,
	TableUtil = TableUti,

	AnimationUtil = AnimationUtil,
	SoundUtil = SoundUtil,

	MathUtil = MathUtil,
	StringUtil = StringUtil,

	Config = Config,
}

-- Automatically load custom configuration if it exists
local customConfigInstance = ReplicatedStorage:FindFirstChild("CraftsmanConfig")
	or ReplicatedStorage:FindFirstChild("CraftmansConfig")

if customConfigInstance and customConfigInstance:IsA("ModuleScript") then
	local success, customConfig = pcall(require, customConfigInstance)
	if success and type(customConfig) == "table" then
		-- Apply configuration
		if
			customConfig.TEMPLATE ~= nil
			or customConfig.KEYS ~= nil
			or customConfig.PRODUCTS ~= nil
			or customConfig.GAMEPASSES ~= nil
		then
			if customConfig.TEMPLATE ~= nil then
				Config.DATA.TEMPLATE = customConfig.TEMPLATE
			end
			if customConfig.KEYS ~= nil then
				Config.MARKET.KEYS = customConfig.KEYS
			end
			if customConfig.PRODUCTS ~= nil then
				Config.MARKET.PRODUCTS = customConfig.PRODUCTS
			end
			if customConfig.GAMEPASSES ~= nil then
				Config.MARKET.GAMEPASSES = customConfig.GAMEPASSES
			end
		elseif customConfig.DATA ~= nil or customConfig.MARKET ~= nil or customConfig.MODULE_LOAD_ORDER ~= nil then
			Config:Edit(customConfig)
		end
	end
end

return Craftsman
