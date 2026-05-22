--!nonstrict
--[[
    FileName    > Client.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 22/05/2026
--]]

const MarketplaceService = game:GetService("MarketplaceService")
const Players = game:GetService("Players")
const RunService = game:GetService("RunService")

local Signal = require("../Signal")

const Config = require("../Config")

local Market = {}

local MarketConfig = Config.MARKET or {}
local Started = false

Market.PromptStarted = Signal.new()
Market.GamepassPromptFinished = Signal.new()

local function get_local_player()
	if not RunService:IsClient() then
		return nil
	end

	return Players.LocalPlayer
end

function Market:Init()
	if Started then
		return
	end

	Started = true
end

function Market:Start()
	if not RunService:IsClient() or MarketConfig.ENABLED == false or MarketConfig.AUTO_START_CLIENT == false then
		return
	end

	self:Init()

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamepass_id, was_purchased)
		self.GamepassPromptFinished:Fire(player, gamepass_id, was_purchased)
	end)
end

function Market:PromptProduct(product_id)
	local player = get_local_player()
	if not player or type(product_id) ~= "number" then
		return false
	end

	self.PromptStarted:Fire("Product", product_id, player)
	MarketplaceService:PromptProductPurchase(player, product_id)
	return true
end

function Market:PromptGamepass(gamepass_id)
	local player = get_local_player()
	if not player or type(gamepass_id) ~= "number" then
		return false
	end

	self.PromptStarted:Fire("Gamepass", gamepass_id, player)
	MarketplaceService:PromptGamePassPurchase(player, gamepass_id)
	return true
end

type MarketModule = {
	Init: (self: MarketModule) -> (),
	Start: (self: MarketModule) -> (),
	PromptProduct: (self: MarketModule, product_id: number) -> boolean,
	PromptGamepass: (self: MarketModule, gamepass_id: number) -> boolean,
	PromptStarted: Signal.Signal<string, number, Player>,
	GamepassPromptFinished: Signal.Signal<Player, number, boolean>,
}

return (Market :: any) :: MarketModule
