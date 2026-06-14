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
const Promise = require("../../../../Promise")

const Config = require("../Config")
const PrintUtil = require("../Utilities/PrintUtil")
const TableUtil = require("../Utilities/TableUtil")

export type PlayerState = Config.PlayerState

local DataServer = nil
if RunService:IsServer() then
	DataServer = require("../Data/Server")
end

--[=[
	@class MarketServer
	The server-side monetization module for Craftsman. It processes receipt processing for developer products
	(integrating with standard MarketplaceService.ProcessReceipt), user gamepass ownership checks (caching and syncing),
	and queueing transactions for robust player data changes.
]=]
local Market = {}

local MarketConfig = Config.MARKET or {}

local Initiated = false
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

--[=[
	@prop ProductGranted Signal<Player, number, any, PlayerState, any>
	@within MarketServer
	A signal that fires when a product purchase is successfully processed and state has saved.
]=]
Market.ProductGranted = Signal.new()

--[=[
	@prop GamepassGranted Signal<Player, number, any, PlayerState, any>
	@within MarketServer
	A signal that fires when a gamepass ownership is granted and state has saved.
]=]
Market.GamepassGranted = Signal.new()

--[=[
	@prop PurchaseFailed Signal<Player, number, any, string, any>
	@within MarketServer
	A signal that fires when a product or gamepass purchase/sync fails.
]=]
Market.PurchaseFailed = Signal.new()

--[=[
	@prop Handlers { [string]: PurchaseHandler }
	@within MarketServer
	The active registry of purchase handlers.
]=]
Market.Handlers = Handlers

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

local function apply_definition(player, definition, context)
	definition = normalize_definition(definition)
	if not definition then
		return nil, false, "MissingDefinition"
	end

	local record, load_error = ensure_player_loaded(player)
	if not record then
		return nil, false, load_error
	end

	if not Market.Producer then
		return nil, false, "MarketServer requires a Producer configured via Init()"
	end

	local state = Market.Producer:getPlayerState(player)
	if not state then
		return nil, false, "Player state not found in producer"
	end

	local receipts_field = get_receipts_field()
	local receipts = state[receipts_field]
	if type(receipts) ~= "table" then
		receipts = {}
	end

	local receipt_id = context and context.ReceiptId or nil
	if receipt_id and receipts[receipt_id] then
		return state, true, nil
	end

	local handler = resolve_handler(definition)
	if not handler then
		return nil, false, "MissingHandler"
	end

	local ok, result, reason = pcall(handler, player, definition, context)
	if not ok then
		return nil, false, result
	end

	if result == false then
		return nil, false, reason or "HandlerRejected"
	end

	if receipt_id then
		Market.Producer._AddReceipt(tostring(player.UserId), receipts_field, receipt_id)
	end

	local save_ok, save_error = DataServer:SavePlayer(player):await()
	if not save_ok then
		return nil, false, save_error
	end

	return Market.Producer:getPlayerState(player), false, nil
end

--[=[
	@method RegisterHandler
	@within MarketServer
	@param handler_name string -- Unique name of the purchase handler
	@param callback function -- The handler function (player, definition, context) -> (boolean, string?)
	@return boolean -- Whether registration succeeded
	Registers a callback function as a purchase handler.
]=]
function Market:RegisterHandler(handler_name, callback)
	if type(handler_name) ~= "string" or type(callback) ~= "function" then
		return false
	end

	Handlers[handler_name] = callback
	return true
end

--[=[
	@method GetProductDefinition
	@within MarketServer
	@param product_id number -- Developer product ID
	@return any -- The normalized configuration definition for this product
	Retrieves the product definition from the config.
]=]
function Market:GetProductDefinition(product_id)
	return normalize_definition(get_product_definitions()[product_id])
end

--[=[
	@method GetGamepassDefinition
	@within MarketServer
	@param gamepass_id number -- Gamepass ID
	@return any -- The normalized configuration definition for this gamepass
	Retrieves the gamepass definition from the config.
]=]
function Market:GetGamepassDefinition(gamepass_id)
	return normalize_definition(get_gamepass_definitions()[gamepass_id])
end

--[=[
	@method UserOwnsGamePass
	@within MarketServer
	@param player Player -- Player to check
	@param gamepass_id number -- Gamepass ID to check
	@return boolean -- Whether the player owns the gamepass
	Checks if a player owns the specified gamepass. Utilizes internal caching for performance.
]=]
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

--[=[
	@method GrantProduct
	@within MarketServer
	@param player Player -- Player purchasing the product
	@param product_id number -- Developer product ID
	@param context any? -- Optional purchase context
	@return boolean -- Whether the grant succeeded
	@return any -- Details (e.g. true if already processed, or error string if failed)
	@return PlayerState? -- The updated player state if successful
	Processes and grants a developer product. Invokes the matching registered handler and saves state.
]=]
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

--[=[
	@method GrantGamepass
	@within MarketServer
	@param player Player -- Player purchasing/syncing the gamepass
	@param gamepass_id number -- Gamepass ID
	@param context any? -- Optional purchase/sync context
	@return boolean -- Whether the grant succeeded
	@return any -- Details (e.g. true if already processed, or error string if failed)
	@return PlayerState? -- The updated player state if successful
	Processes and grants a gamepass. Invokes the matching registered handler and saves state.
]=]
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

--[=[
	@method PromptProduct
	@within MarketServer
	@param player Player -- Player to prompt
	@param product_id number -- Developer product ID
	@return boolean -- Whether the prompt was successfully initiated
	Prompts the player to purchase a developer product from the server.
]=]
function Market:PromptProduct(player, product_id)
	if not Started or not player or type(product_id) ~= "number" then
		return false
	end

	MarketplaceService:PromptProductPurchase(player, product_id)
	return true
end

--[=[
	@method PromptGamepass
	@within MarketServer
	@param player Player -- Player to prompt
	@param gamepass_id number -- Gamepass ID
	@return boolean -- Whether the prompt was successfully initiated
	Prompts the player to purchase a gamepass from the server.
]=]
function Market:PromptGamepass(player, gamepass_id)
	if not Started or not player or type(gamepass_id) ~= "number" then
		return false
	end

	MarketplaceService:PromptGamePassPurchase(player, gamepass_id)
	return true
end

--[=[
	@method _EnqueueTransaction
	@private
	@ignore
	@within MarketServer
	Enqueues a transaction in the transaction queue to guarantee serialized processing.
]=]
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

--[=[
	@method _ProcessReceipt
	@private
	@ignore
	@within MarketServer
	Main entry point for Roblox MarketplaceService.ProcessReceipt.
]=]
function Market:_ProcessReceipt(receipt_info)
	if type(receipt_info) ~= "table" then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local receipt_id = receipt_info.PurchaseId
	if receipt_id == nil or receipt_id == "" then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	receipt_id = tostring(receipt_id)

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

--[=[
	@method Init
	@within MarketServer
	Initializes the server-side Market service.
]=]
function Market:Init(options: { Producer: any }?)
	if not RunService:IsServer() or Initiated then
		return
	end

	if options and options.Producer then
		self.Producer = options.Producer
	end

	get_transaction_queue()
	Initiated = true
end

--[=[
	@method Start
	@within MarketServer
	Starts the server-side Market service. Hooks up PlayerAdded, PlayerRemoving, PromptGamePassPurchaseFinished, and ProcessReceipt.
]=]
function Market:Start()
	if not RunService:IsServer() or MarketConfig.ENABLED == false or Started then
		return
	end

	self:Init()

	local function cache_player_gamepasses(player)
		GamepassCache[player] = {}

		local promises = {}

		for gp_id in get_gamepass_definitions() do
			table.insert(
				promises,
				Promise.try(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, gp_id)
					:catch(function(err)
						PrintUtil:Warn(`Failed to check ownership of gamepass {gp_id} for {player.Name}`)
						return err
					end)
					:andThen(function(owns)
						if not owns then
							return
						end

						GamepassCache[player][gp_id] = true

						local transaction_key = make_transaction_key(player, "Gamepass", gp_id)
						return self:_EnqueueTransaction(player, transaction_key, {
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
			)
		end

		Promise.all(promises)
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

type PurchaseHandler = (player: Player, definition: any, context: any) -> (boolean, string?)

type MarketModule = {
	Producer: any?,
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
	Init: (self: MarketModule, options: { Producer: any }?) -> (),
	Start: (self: MarketModule) -> (),
	ProductGranted: Signal.Signal<Player, number, any, PlayerState, any>,
	GamepassGranted: Signal.Signal<Player, number, any, PlayerState, any>,
	PurchaseFailed: Signal.Signal<Player, number, any, string, any>,
	Handlers: { [string]: PurchaseHandler },
}

return (Market :: any) :: MarketModule
