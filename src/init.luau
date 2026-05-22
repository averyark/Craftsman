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

return {
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
