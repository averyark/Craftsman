--!nonstrict
--[[
    FileName    > test.luau
    Author      > Antigravity
    Created     > 22/05/2026
--]]

const MarketplaceService = game:GetService("MarketplaceService")
const Players = game:GetService("Players")

const Craftsman = require("@game/ReplicatedStorage/Packages/Craftsman")
const CraftsmanConfig = require("@game/ReplicatedStorage/Shared/CraftsmanConfig")
const Promise = require("../Packages/Promise")

local test = Craftsman.Component.new({})

local function get_product_info(id: number, is_gamepass: boolean)
	local info_type = if is_gamepass then Enum.InfoType.GamePass else Enum.InfoType.Product
	local success, info = pcall(function()
		return MarketplaceService:GetProductInfo(id, info_type)
	end)

	if success and info then
		return info.Name, info.PriceInRobux or 0
	end

	return nil
end

local function configure_card(card, name: string, price: number, on_click: () -> ())
	card.Text = name .. " - " .. tostring(price) .. " R$"
	card.MouseButton1Click:Connect(on_click)
end

test.Start = function()
	Craftsman.PrintUtil:Print("Client test component started!")

	local player = Players.LocalPlayer
	local player_gui = player:WaitForChild("PlayerGui")
	local coins_gui = player_gui:WaitForChild("Coins")
	local coins_label = coins_gui:WaitForChild("Label") :: TextLabel

	local function update_label(coins)
		coins_label.Text = "Coins: " .. tostring(coins)
	end

	-- Initialize the HUD label immediately with the current loaded state
	local current_state = Craftsman.DataClient:GetState()
	if current_state then
		update_label(current_state.Coins or 0)
	end

	-- Subscribe to any future changes
	Craftsman.DataClient:Subscribe(function(state, previous_state)
		local coins = state.Coins or 0
		local previous_coins = previous_state and previous_state.Coins
		if previous_state == nil or coins ~= previous_coins then
			update_label(coins)
		end
	end)

	-- Populate Marketplace UI
	local marketplace_gui = player_gui:WaitForChild("Marketplace")

	local product_ids = Craftsman.TableUtil.Keys(CraftsmanConfig.PRODUCTS)
	local gamepass_ids = Craftsman.TableUtil.Keys(CraftsmanConfig.GAMEPASSES)

	-- Developer Products
	local products_container = marketplace_gui:WaitForChild("Products")
	local product_template = products_container:WaitForChild("Template")
	product_template.Visible = false

	for i = 1, #product_ids do
		local product_id = product_ids[i]
		local card = product_template:Clone()
		card.Name = "Product_" .. tostring(product_id)
		card.Parent = products_container

		Promise.try(function()
			return get_product_info(product_id, false)
		end):andThen(function(name, price)
			configure_card(card, name, price, function()
				Craftsman.MarketClient:PromptProduct(product_id)
			end)
			card.Visible = true
		end)
	end

	-- Gamepasses
	local gamepasses_container = marketplace_gui:WaitForChild("Gamepasses")
	local gamepass_template = gamepasses_container:WaitForChild("Template")
	gamepass_template.Visible = false

	for i = 1, #gamepass_ids do
		local gamepass_id = gamepass_ids[i]
		local card = gamepass_template:Clone()
		card.Name = "Gamepass_" .. tostring(gamepass_id)
		card.Parent = gamepasses_container

		Promise.try(function()
			return get_product_info(gamepass_id, true)
		end):andThen(function(name, price)
			configure_card(card, name, price, function()
				Craftsman.MarketClient:PromptGamepass(gamepass_id)
			end)
			card.Visible = true
		end)
	end
end

return test
