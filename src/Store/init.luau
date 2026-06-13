--!nonstrict
--[[
    FileName    > Store.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 13/06/2026
--]]

local Reflex = require("../../../../Reflex")

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

local Store = {}
Store.None = {} :: any

function Store.CreateProducer<S, A>(initial_state: S, actions: A): Producer<S, A>
	local wrapped_actions = {}

	for action_name, action_callback in actions :: any do
		wrapped_actions[action_name] = function(state, ...)
			local result = action_callback(state, ...)

			if result == nil then
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

	return Reflex.createProducer(initial_state, wrapped_actions) :: any
end

function Store.Merge(target_dict: { [any]: any }, new_values: { [any]: any }): { [any]: any }
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

function Store.Omit(target_dict: { [any]: any }, key_to_remove: any): { [any]: any }
	local new_dict = table.clone(target_dict)
	new_dict[key_to_remove] = nil
	return new_dict
end

return Store
