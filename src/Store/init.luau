--!nonstrict
--[[
    FileName    > Store.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 13/06/2026
--]]

--

const Reflex = require("../../../Reflex")

export type Producer<State, Actions> = {
	getState: ((self: Producer<State, Actions>) -> State)
		& (<Selection>(self: Producer<State, Actions>, selector: (state: State) -> Selection) -> Selection),
	setState: (self: Producer<State, Actions>, state: State) -> (),
	resetState: (self: Producer<State, Actions>) -> (),
	getDispatchers: (self: Producer<State, Actions>) -> Actions,
	getActions: (self: Producer<State, Actions>) -> {
		[string]: (state: State, ...any) -> any,
	},
	clone: (self: Producer<State, Actions>) -> Producer<State, Actions>,
	flush: (self: Producer<State, Actions>) -> (),
	subscribe: ((self: Producer<State, Actions>, listener: (state: State, prevState: State) -> ()) -> () -> ())
		& (<Selection>(
			self: Producer<State, Actions>,
			selector: (state: State) -> Selection,
			listener: (state: Selection, prevState: Selection) -> ()
		) -> () -> ())
		& <Selection>(
			self: Producer<State, Actions>,
			selector: (state: State) -> Selection,
			predicate: (state: Selection, prevState: Selection) -> boolean,
			listener: (state: Selection, prevState: Selection) -> ()
		) -> () -> (),
	once: (<Selection>(
		self: Producer<State, Actions>,
		selector: (state: State) -> Selection,
		listener: (state: Selection, prevState: Selection) -> ()
	) -> () -> ()) & <Selection>(
		self: Producer<State, Actions>,
		selector: (state: State) -> Selection,
		predicate: ((state: Selection, prevState: Selection) -> boolean)?,
		listener: (state: Selection, prevState: Selection) -> ()
	) -> () -> (),
	wait: <Selection>(
		self: Producer<State, Actions>,
		selector: ((state: State) -> Selection)?,
		predicate: ((state: Selection, prevState: Selection) -> boolean)?
	) -> any,
	observe: (<K, V>(
		self: Producer<State, Actions>,
		selector: (state: State) -> { [K]: V },
		discriminator: ((item: V, index: K) -> unknown)?,
		observer: (item: V, index: K) -> (() -> ())?
	) -> () -> ()) & (<K, V>(
		self: Producer<State, Actions>,
		selector: (state: State) -> { [K]: V },
		observer: (item: V, index: K) -> (() -> ())?
	) -> () -> ()),
	observeWhile: (<T>(
		self: Producer<State, Actions>,
		selector: (state: State) -> T,
		predicate: (state: T, prevState: T) -> boolean,
		observer: (state: T) -> (() -> ())?
	) -> () -> ()) & (<T>(
		self: Producer<State, Actions>,
		selector: (state: State) -> T?,
		observer: (state: T) -> (() -> ())?
	) -> () -> ()),
	destroy: (self: Producer<State, Actions>) -> (),
	applyMiddleware: (
		self: Producer<State, Actions>,
		...(producer: any) -> (dispatch: (...any) -> any, name: string) -> (...any) -> any
	) -> Producer<State, Actions>,
} & Actions

--[=[
	@class Store
	A core state management utility module that wraps Reflex producers.
	Provides curried producer building, action wrapping, and helper functions for immutable state manipulation.
]=]
local Store = {}

--[=[
	@prop None any
	@within Store
	A sentinel value used in action results to mark a key for removal/deletion.
]=]
Store.None = newproxy(true)

local function GetWrapped(action_callback)
	return function(state, ...)
		local result = action_callback(state, ...)

		if result == nil or type(result) ~= "table" then
			return state
		end

		local new_state = table.clone(state :: any)
		local changed = false

		for key, value in result do
			if value == Store.None then
				value = nil
			end

			if new_state[key] == value then
				continue
			end

			new_state[key] = value
			changed = true
		end

		if not changed then
			return state
		end

		return new_state :: any
	end
end

--[=[
	@function CreateProducer
	@within Store
	@param initial_state S -- The initial state of the producer.
	@return <A>(actions: A) -> Producer<S, A> -- A builder function expecting action callbacks to return the Producer.

	Creates a curried producer factory that automatically wraps action callbacks. Actions wrapped by this
	producer perform a shallow clone of the top-level state dictionary and merge partial action result tables.

	:::warning Immutability Warning
	Because actions perform a **shallow clone** (`table.clone`) of the top-level state, nested tables and
	dictionaries inside the state are **not** automatically cloned.

	You must never mutate nested properties in-place within action callbacks. Instead, you must explicitly
	return new table references for nested table updates. Use helpers like `Store:Merge` or `Store:Omit`
	to modify nested dictionaries immutably.

	```lua
	-- ❌ INCORRECT (mutates nested table in-place):
	AddInventoryItem = function(state, item_id, amount)
		state.Inventory[item_id] = (state.Inventory[item_id] or 0) + amount
		return state
	end

	-- ✅ CORRECT (returns new nested references):
	AddInventoryItem = function(state, item_id, amount)
		return {
			Inventory = Store:Merge(state.Inventory, {
				[item_id] = (state.Inventory[item_id] or 0) + amount,
			})
		}
	end
	```
	:::
]=]
function Store.CreateProducer<S>(initial_state: S)
	return function<A>(actions: A & { [string]: (state: S, ...any) -> any }): Producer<S, A>
		local wrapped_actions = {}

		for action_name, action_callback in actions :: any do
			wrapped_actions[action_name] = GetWrapped(action_callback)
		end

		return Reflex.createProducer(initial_state, wrapped_actions) :: any
	end
end

--[=[
	@method Merge
	@within Store
	@param target_dict { [any]: any } -- The original dictionary to merge values into.
	@param new_values { [any]: any } -- The dictionary containing keys to merge/update.
	@return { [any]: any } -- A new, shallow-cloned dictionary containing the merged values.

	Performs a shallow clone and merges key-value pairs into a dictionary. Supports removing keys
	by setting their value to `Store.None`. Useful for updating nested state immutably.
]=]
function Store:Merge(target_dict: { [any]: any }, new_values: { [any]: any }): { [any]: any }
	local new_dict = table.clone(target_dict)
	for k, v in new_values do
		if v == Store.None then
			new_dict[k] = nil
			continue
		end

		new_dict[k] = v
	end
	return new_dict
end

--[=[
	@method Omit
	@within Store
	@param target_dict { [any]: any } -- The original dictionary.
	@param key_to_remove any -- The key to omit from the returned dictionary.
	@return { [any]: any } -- A new, shallow-cloned dictionary without the omitted key.

	Performs a shallow clone of a dictionary and removes a specified key. Useful for updating
	nested state immutably.
]=]
function Store:Omit(target_dict: { [any]: any }, key_to_remove: any): { [any]: any }
	local new_dict = table.clone(target_dict)
	new_dict[key_to_remove] = nil
	return new_dict
end

--[=[
	@prop PlayerActionRegistry { [string]: boolean }
	@within Store
	A registry of action names created by `CreatePlayerProducer`. Used by the server broadcaster
	to ensure client actions are correctly filtered and not leaked to other players.
]=]
Store.PlayerActionRegistry = {}

--[=[
	@function PlayerAction
	@within Store
	@param callback (player_state: any, ...any) -> any
	@return (global_state: any, user_id: string, ...any) -> any

	Wraps a single-player action callback into a global players-dictionary action.
	Automatically handles looking up the `user_id` and immutably merging the results back
	into the global dictionary.
]=]
function Store.PlayerAction(callback: (any, ...any) -> any)
	return function(state: any, user_id_or_player: string | Player, ...)
		local user_id = type(user_id_or_player) == "string" and user_id_or_player
			or tostring((user_id_or_player :: Player).UserId)
		local player_state = state[user_id]
		if not player_state then
			return state
		end

		local result = callback(player_state, ...)
		if result == nil or type(result) ~= "table" then
			return state
		end

		local changed = false
		local new_player_state = table.clone(player_state)

		for key, value in result do
			if value == Store.None then
				value = nil
			end

			if new_player_state[key] == value then
				continue
			end

			new_player_state[key] = value
			changed = true
		end

		if not changed then
			return state
		end

		local new_state = table.clone(state)
		new_state[user_id] = new_player_state
		return new_state
	end
end

--[=[
	@function CreatePlayerProducer
	@within Store
	@param initial_player_state S -- The template state for a single player.
	@return <A>(actions: A) -> PlayerProducer<S, A>

	A specialized producer factory for player-keyed state dictionaries.
	Initializes the state as an empty dictionary, wraps all provided actions in `PlayerAction`,
	registers them in `PlayerActionRegistry`, and injects internal lifecycle actions (`_LoadPlayer`, `_UnloadPlayer`).
	Also attaches `getPlayerState` and `subscribePlayer` convenience methods to the producer.
]=]
function Store.CreatePlayerProducer<S>(initial_player_state: S)
	return function<A>(actions: A)
		local wrapped_actions = {
			_LoadPlayer = function(state: any, user_id: string, data: S)
				local new_state = table.clone(state)
				new_state[user_id] = data
				return new_state
			end,
			_UnloadPlayer = function(state: any, user_id: string)
				local new_state = table.clone(state)
				new_state[user_id] = nil
				return new_state
			end,
			_AddReceipt = function(state: any, user_id: string, receipts_field: string, receipt_id: string)
				local player_state = state[user_id]
				if not player_state then
					return state
				end
				local new_state = table.clone(state)
				local new_player_state = table.clone(player_state)
				local receipts = type(new_player_state[receipts_field]) == "table"
						and table.clone(new_player_state[receipts_field])
					or {}
				receipts[receipt_id] = true
				new_player_state[receipts_field] = receipts
				new_state[user_id] = new_player_state
				return new_state
			end,
		}

		Store.PlayerActionRegistry["_LoadPlayer"] = true
		Store.PlayerActionRegistry["_UnloadPlayer"] = true
		Store.PlayerActionRegistry["_AddReceipt"] = true

		for action_name, action_callback in actions :: any do
			wrapped_actions[action_name] = Store.PlayerAction(action_callback)
			Store.PlayerActionRegistry[action_name] = true
		end

		local producer = Reflex.createProducer({}, wrapped_actions) :: any

		function producer.getPlayerState(self: any, player_or_id: Player | string, selector: ((S) -> any)?): any
			local user_id = type(player_or_id) == "string" and player_or_id or tostring((player_or_id :: Player).UserId)
			local state = self:getState()[user_id]
			if not state then
				return nil
			end
			if selector then
				return selector(state)
			end
			return state
		end

		function producer.subscribePlayer(
			self: any,
			player_or_id: Player | string,
			arg2: any,
			arg3: any?,
			arg4: any?
		): () -> ()
			local user_id = type(player_or_id) == "string" and player_or_id or tostring((player_or_id :: Player).UserId)

			if arg3 == nil then
				local listener = arg2
				return self:subscribe(function(state)
					return state[user_id]
				end, listener)
			elseif arg4 == nil then
				local selector = arg2
				local listener = arg3
				return self:subscribe(function(state)
					local player_state = state[user_id]
					if not player_state then
						return nil
					end
					return selector(player_state)
				end, listener)
			else
				local selector = arg2
				local predicate = arg3
				local listener = arg4
				return self:subscribe(function(state)
					local player_state = state[user_id]
					if not player_state then
						return nil
					end
					return selector(player_state)
				end, predicate, listener)
			end
		end

		return producer :: {
			getPlayerState: ((self: Producer<S, A>, player_or_id: Player | string) -> S?) & (<Selection>(
				self: Producer<S, A>,
				player_or_id: Player | string,
				selector: (state: S) -> Selection
			) -> Selection?),
			subscribePlayer: (
				self: Producer<S, A>,
				player: Player | string,
				listener: (state: S?, prevState: S?) -> ...any
			) -> () -> (),
		} & Producer<S, A>
	end
end

return Store
