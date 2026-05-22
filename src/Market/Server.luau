--!nonstrict
--[[
    FileName    > Server.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 22/05/2026
--]]

const MarketplaceService = game:GetService("MarketplaceService")
const Players = game:GetService("Players")
const RunService = game:GetService("RunService")

local Signal = require("../Signal")
const Queue = require("../Queue")

const Config = require("../Config")
const PrintUtil = require("../Utilities/PrintUtil")
const TableUtil = require("../Utilities/TableUtil")

export type PlayerState = Config.PlayerState

local DataServer = nil
if RunService:IsServer() then
	DataServer = require("../Data/Server")
end

local Market = {}

local MarketConfig = Config.MARKET or {}

local Started = false
local Handlers = {}
local GamepassCache = {}
local TransactionQueue = nil

local function get_market_config()
	return Config.MARKET or {}
end

local function get_product_definitions()
	return get_market_config().PRODUCTS or {}
end

local function get_gamepass_definitions()
	return get_market_config().GAMEPASSES or {}
end

local function get_receipts_field()
	return get_market_config().RECEIPTS_FIELD or "Receipts"
end

local function get_transaction_queue()
	if TransactionQueue then
		return TransactionQueue
	end

	TransactionQueue = Queue.new({
		DefaultMaxRetries = 2,
		DefaultRetryDelay = 0.5,
		DefaultBackoffFactor = 2,
		DefaultJitterFactor = 0.15,
	})

	return TransactionQueue
end

local function make_transaction_key(player, transaction_type, transaction_id)
	return `{transaction_type}:{player.UserId}:{transaction_id}`
end

Market.ProductGranted = Signal.new()
Market.GamepassGranted = Signal.new()
Market.PurchaseFailed = Signal.new()
Market.Handlers = Handlers

local function clone_state(state)
	if type(state) ~= "table" then
		return {}
	end

	return TableUtil.DeepClone(state)
end

local function normalize_definition(definition)
	if type(definition) == "string" then
		return {
			Handler = definition,
		}
	end

	if type(definition) ~= "table" then
		return nil
	end

	return definition
end

local function ensure_receipts(state)
	state = type(state) == "table" and state or {}

	local receipts_field = get_receipts_field()
	local receipts = state[receipts_field]
	if type(receipts) ~= "table" then
		receipts = {}
		state[receipts_field] = receipts
	end

	return state, receipts
end

local function resolve_handler(definition)
	local handler_name = nil

	if type(definition) == "string" then
		handler_name = definition
	elseif type(definition) == "table" then
		handler_name = definition.Handler or definition.handler
	end

	if type(handler_name) ~= "string" then
		return nil
	end

	return Handlers[handler_name]
end

local function ensure_player_loaded(player)
	local record = DataServer:GetPlayerRecord(player)
	if record.Loaded then
		return record
	end

	local ok, result = DataServer:LoadPlayer(player):await()
	if not ok then
		return nil, result
	end

	return record
end

local function save_player_state(player, state)
	local normalized_state = DataServer:SetState(player, state)
	local ok, result = DataServer:SavePlayer(player):await()
	if not ok then
		return nil, result
	end

	return normalized_state
end

local function apply_definition(player, definition, context)
	definition = normalize_definition(definition)
	if not definition then
		return nil, false, "MissingDefinition"
	end

	local record, load_error = ensure_player_loaded(player)
	if not record then
		return nil, false, load_error
	end

	local state = clone_state(DataServer:GetState(player))
	local receipts = nil
	state, receipts = ensure_receipts(state)

	local receipt_id = context and context.ReceiptId or nil
	if receipt_id and receipts[receipt_id] then
		return state, true, nil
	end

	local handler = resolve_handler(definition)
	if not handler then
		return nil, false, "MissingHandler"
	end

	local ok, result, reason = pcall(handler, player, state, definition, context)
	if not ok then
		return nil, false, result
	end

	if result == false then
		return nil, false, reason or "HandlerRejected"
	end

	if type(result) == "table" then
		state = result
	end

	state, receipts = ensure_receipts(state)
	if receipt_id then
		receipts[receipt_id] = true
	end

	local saved_state, save_error = save_player_state(player, state)
	if not saved_state then
		return nil, false, save_error
	end

	return saved_state, false, nil
end

function Market:RegisterHandler(handler_name, callback)
	if type(handler_name) ~= "string" or type(callback) ~= "function" then
		return false
	end

	Handlers[handler_name] = callback
	return true
end

function Market:GetProductDefinition(product_id)
	return normalize_definition(get_product_definitions()[product_id])
end

function Market:GetGamepassDefinition(gamepass_id)
	return normalize_definition(get_gamepass_definitions()[gamepass_id])
end

function Market:UserOwnsGamePass(player, gamepass_id)
	if not player or type(gamepass_id) ~= "number" then
		return false
	end

	local player_cache = GamepassCache[player]
	if player_cache and player_cache[gamepass_id] ~= nil then
		return player_cache[gamepass_id]
	end

	local success, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamepass_id)
	end)

	if success then
		if not GamepassCache[player] then
			GamepassCache[player] = {}
		end
		GamepassCache[player][gamepass_id] = owns
		return owns
	end

	return false
end

function Market:GrantProduct(player, product_id, context)
	local definition = self:GetProductDefinition(product_id)
	if not definition then
		return false, "MissingDefinition"
	end

	context = type(context) == "table" and TableUtil.DeepClone(context) or {}
	context.ProductId = product_id
	context.ReceiptId = context.ReceiptId or context.PurchaseId

	local state, already_processed, reason = apply_definition(player, definition, context)
	if not state then
		return false, reason
	end

	if not already_processed then
		self.ProductGranted:Fire(player, product_id, definition, state, context)
	end

	return true, already_processed, state
end

function Market:GrantGamepass(player, gamepass_id, context)
	local definition = self:GetGamepassDefinition(gamepass_id)
	if not definition then
		return false, "MissingDefinition"
	end

	context = type(context) == "table" and TableUtil.DeepClone(context) or {}
	context.GamepassId = gamepass_id
	context.ReceiptId = context.ReceiptId or `Gamepass:{gamepass_id}`

	local state, already_processed, reason = apply_definition(player, definition, context)
	if not state then
		return false, reason
	end

	if not GamepassCache[player] then
		GamepassCache[player] = {}
	end
	GamepassCache[player][gamepass_id] = true

	if not already_processed then
		self.GamepassGranted:Fire(player, gamepass_id, definition, state, context)
	end

	return true, already_processed, state
end

function Market:PromptProduct(player, product_id)
	if not Started or not player or type(product_id) ~= "number" then
		return false
	end

	MarketplaceService:PromptProductPurchase(player, product_id)
	return true
end

function Market:PromptGamepass(player, gamepass_id)
	if not Started or not player or type(gamepass_id) ~= "number" then
		return false
	end

	MarketplaceService:PromptGamePassPurchase(player, gamepass_id)
	return true
end

function Market:_EnqueueTransaction(player, transaction_key, context, callback)
	local queue = get_transaction_queue()

	local promise = queue:Enqueue(function()
		local granted, detail, state = callback()
		if granted then
			return granted, detail, state
		end

		error(detail or "TransactionFailed")
	end, {
		Key = transaction_key,
		Context = context,
	})

	return promise
end

function Market:_ProcessReceipt(receipt_info)
	if type(receipt_info) ~= "table" then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local receipt_id = receipt_info.PurchaseId
	if type(receipt_id) ~= "string" or receipt_id == "" then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local player = Players:GetPlayerByUserId(receipt_info.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local definition = self:GetProductDefinition(receipt_info.ProductId)
	if not definition then
		PrintUtil:Warn(`No product handler configured for product {receipt_info.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local context = {
		ReceiptId = receipt_id,
		ProductId = receipt_info.ProductId,
		PlayerId = receipt_info.PlayerId,
		CurrencySpent = receipt_info.CurrencySpent,
		PurchaseDate = receipt_info.PurchaseDate,
	}
	local transaction_key = make_transaction_key(player, "Receipt", receipt_id)

	local success, granted, reason = self:_EnqueueTransaction(player, transaction_key, context, function()
		return self:GrantProduct(player, receipt_info.ProductId, context)
	end):await()

	if not success then
		reason = granted
		granted = false
	end

	if not granted then
		self.PurchaseFailed:Fire(player, receipt_info.ProductId, definition, reason, context)
		PrintUtil:Warn(`Failed to process product {receipt_info.ProductId} for {player.Name}: {reason}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function Market:Init()
	if not RunService:IsServer() or Started then
		return
	end

	get_transaction_queue()
end

function Market:Start()
	if not RunService:IsServer() or MarketConfig.ENABLED == false or Started then
		return
	end

	self:Init()

	local function cache_player_gamepasses(player)
		GamepassCache[player] = {}
		task.spawn(function()
			local gamepass_ids = TableUtil.Keys(get_gamepass_definitions())
			for i = 1, #gamepass_ids do
				local gp_id = gamepass_ids[i]
				local success, owns = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gp_id)
				end)
				if success and owns then
					GamepassCache[player][gp_id] = true
					task.spawn(function()
						local transaction_key = make_transaction_key(player, "Gamepass", gp_id)
						self:_EnqueueTransaction(player, transaction_key, {
							GamepassId = gp_id,
							SyncSource = "OwnershipCache",
						}, function()
							return self:GrantGamepass(player, gp_id, {
								SyncSource = "OwnershipCache",
							})
						end):catch(function(reason)
							PrintUtil:Warn(`Failed to sync owned gamepass {gp_id} for {player.Name}: {reason}`)
						end)
					end)
				end
			end
		end)
	end

	local players = Players:GetPlayers()
	for i = 1, #players do
		cache_player_gamepasses(players[i])
	end

	Players.PlayerAdded:Connect(cache_player_gamepasses)
	Players.PlayerRemoving:Connect(function(player)
		GamepassCache[player] = nil
	end)

	MarketplaceService.ProcessReceipt = function(receipt_info)
		return self:_ProcessReceipt(receipt_info)
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamepass_id, was_purchased)
		if not was_purchased then
			return
		end

		local context = {
			GamepassId = gamepass_id,
			WasPurchased = was_purchased,
		}
		local transaction_key = make_transaction_key(player, "Gamepass", gamepass_id)
		local success, granted, reason = self:_EnqueueTransaction(player, transaction_key, context, function()
			return self:GrantGamepass(player, gamepass_id, context)
		end):await()

		if not success then
			reason = granted
			granted = false
		end

		if granted then
			return
		end

		self.PurchaseFailed:Fire(player, gamepass_id, self:GetGamepassDefinition(gamepass_id), reason, context)
		PrintUtil:Warn(`Failed to process gamepass {gamepass_id} for {player.Name}: {reason}`)
	end)

	Started = true
	PrintUtil:Print("Marketplace server started")
end

type PurchaseHandler = (
	player: Player,
	state: PlayerState,
	definition: any,
	context: any
) -> (PlayerState | boolean, string?)

type MarketModule = {
	RegisterHandler: (self: MarketModule, handler_name: string, callback: PurchaseHandler) -> boolean,
	GetProductDefinition: (self: MarketModule, product_id: number) -> any,
	GetGamepassDefinition: (self: MarketModule, gamepass_id: number) -> any,
	UserOwnsGamePass: (self: MarketModule, player: Player, gamepass_id: number) -> boolean,
	GrantProduct: (
		self: MarketModule,
		player: Player,
		product_id: number,
		context: any?
	) -> (boolean, any, PlayerState?),
	GrantGamepass: (
		self: MarketModule,
		player: Player,
		gamepass_id: number,
		context: any?
	) -> (boolean, any, PlayerState?),
	PromptProduct: (self: MarketModule, player: Player, product_id: number) -> boolean,
	PromptGamepass: (self: MarketModule, player: Player, gamepass_id: number) -> boolean,
	Init: (self: MarketModule) -> (),
	Start: (self: MarketModule) -> (),
	ProductGranted: Signal.Signal<Player, number, any, PlayerState, any>,
	GamepassGranted: Signal.Signal<Player, number, any, PlayerState, any>,
	PurchaseFailed: Signal.Signal<Player, number, any, string, any>,
	Handlers: { [string]: PurchaseHandler },
}

return (Market :: any) :: MarketModule
