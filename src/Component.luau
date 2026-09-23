--!strict
--[[
    FileName    > Component.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 20/05/2026
--]]

const Promise = require("../packages/roblox/Promise")
const Config = require("./Config")
const Keeper = require("../packages/roblox/Keeper")

local Component = {}

--
type ModuleNode = {
	Name: string,
	Contents: any,
	Dependencies: { ModuleNode },
	Failure: string?,
	Keeper: Keeper.Keeper?,
	StartPromise: Promise.Promise?,
	StopPromise: Promise.Promise?,
}

type InitResult = {
	contents: any,
	init_failure: string?,
}

type OrderedDescendant = {
	module: Instance,
	module_name: string,
	load_order: number?,
	source_index: number,
}

export type LoaderState = {
	Modules: { [string]: any },
	LoadedModules: { [string]: any },
	IsLoaded: boolean,
	Nodes: { ModuleNode }?,
}
--

--
Component.Modules = {} :: { [string]: any }
Component.IsLoaded = false
Component.LoadedModules = {} :: { [string]: any }
Component.Nodes = nil :: { ModuleNode }?
--

local function resolve_dependencies(nodes: { ModuleNode }, node_by_contents: { [any]: ModuleNode })
	for _, node in nodes do
		--
		if type(node.Contents) ~= "table" then
			continue
		end

		const declared = rawget(node.Contents, "Dependencies")

		if declared == nil then
			continue
		end

		if type(declared) ~= "table" then
			warn(`Dependencies of module {node.Name} must be a table, got {type(declared)}`)
			continue
		end
		--

		for index, declared_contents in declared do
			--
			const dependency_node = node_by_contents[declared_contents]

			if not dependency_node then
				warn(
					`Module {node.Name} declares a dependency at index {index} that is not a loaded module. II gnoring it`
				)
				continue
			end

			if dependency_node == node then
				warn(`Module {node.Name} declares itself as a dependency; ignoring it`)
				continue
			end
			--

			--
			node.Dependencies[#node.Dependencies + 1] = dependency_node
			--
		end
	end
end

local function collect_cycle(stack: { ModuleNode }, node: ModuleNode): { string }
	--
	const cycle = {}
	local reached_entry = false
	--

	--
	for _, entry in stack do
		if entry == node then
			reached_entry = true
		end

		if not reached_entry then
			continue
		end

		cycle[#cycle + 1] = entry.Name
	end
	--

	--
	cycle[#cycle + 1] = node.Name
	--

	return cycle
end

local function find_cycle(nodes: { ModuleNode }): { string }?
	--
	const visit_state: { [ModuleNode]: number } = {}
	const stack: { ModuleNode } = {}
	--

	local function visit(node: ModuleNode): { string }?
		--
		const state = visit_state[node]

		if state == 2 then
			return nil
		end

		if state == 1 then
			return collect_cycle(stack, node)
		end
		--

		--
		visit_state[node] = 1
		stack[#stack + 1] = node
		--

		--
		for _, dependency in node.Dependencies do
			const cycle = visit(dependency)

			if cycle then
				return cycle
			end
		end
		--

		--
		stack[#stack] = nil
		visit_state[node] = 2
		--

		return nil
	end

	--
	for _, node in nodes do
		const cycle = visit(node)

		if cycle then
			return cycle
		end
	end
	--

	return nil
end

local function run_init(module_name: string, module_contents: any): string?
	--
	if type(module_contents) ~= "table" or not module_contents.Init or type(module_contents.Init) ~= "function" then
		return nil
	end
	--

	--
	const init_success, init_err = pcall(module_contents.Init, module_contents)

	if init_success then
		return nil
	end
	--

	--
	warn(`Error in Init of module {module_name}:`, init_err)
	--

	return module_name
end

local function apply_legacy_load_order(node_by_name: { [string]: ModuleNode })
	--
	if #Config.MODULE_LOAD_ORDER <= 0 then
		return
	end
	--

	--
	warn("Config.MODULE_LOAD_ORDER is deprecated. Declare Dependencies on the modules themselves instead")
	--

	--
	local previous_node: ModuleNode? = nil

	for _, module_name in Config.MODULE_LOAD_ORDER do
		const node = node_by_name[module_name]

		if not node then
			continue
		end

		if previous_node then
			node.Dependencies[#node.Dependencies + 1] = previous_node
		end

		previous_node = node
	end
	--
end

function Component.LoadModulesAsync(self: LoaderState, modules: Instance): Promise.Promise
	--
	self.Modules = self.Modules or {}
	self.LoadedModules = self.LoadedModules or {}
	--

	--
	const module_names: { string } = {}
	const promises: { Promise.TypedPromise<InitResult> } = {}
	const module_order: { [string]: number } = {}
	--

	--
	for index, module_name in Config.MODULE_LOAD_ORDER do
		module_order[module_name] = index
	end
	--

	--
	const descendants = modules:GetDescendants()
	const ordered_descendants: { OrderedDescendant } = {}

	for index, module in descendants do
		ordered_descendants[#ordered_descendants + 1] = {
			module = module,
			module_name = module.Name,
			load_order = module_order[module.Name],
			source_index = index,
		}
	end
	--

	table.sort(ordered_descendants, function(left: OrderedDescendant, right: OrderedDescendant): boolean
		--
		const left_order = left.load_order
		const right_order = right.load_order

		if left_order and right_order then
			return left_order < right_order
		end
		--

		--
		if left_order then
			return true
		end

		if right_order then
			return false
		end
		--

		return left.source_index < right.source_index
	end)

	for index, module_entry in ordered_descendants do
		--
		const module = module_entry.module

		if not module:IsA("ModuleScript") or module.Name:match("%.spec$") then
			continue
		end
		--

		--
		const module_name = module_entry.module_name
		module_names[#module_names + 1] = module_name
		--

		promises[#promises + 1] = Promise.new(function(resolve, reject)
			--
			const success, module_contents = pcall(require, module)

			if not success then
				reject(module_contents)
				return
			end
			--

			--
			const init_failure = run_init(module_name, module_contents)
			--

			resolve({ contents = module_contents, init_failure = init_failure })
		end)
	end

	const results = Promise.all(promises)
		:andThen(function(init_results)
			--
			const loaded_modules: { [string]: any } = {}
			const nodes: { ModuleNode } = {}
			const node_by_contents: { [any]: ModuleNode } = {}
			const node_by_name: { [string]: ModuleNode } = {}
			--

			for index, init_result in init_results do
				--
				const module_name = module_names[index]
				const module_contents = init_result.contents

				loaded_modules[module_name] = module_contents
				self.Modules[module_name] = module_contents
				self.LoadedModules[module_name] = module_contents
				--

				--
				const node: ModuleNode = {
					Name = module_name,
					Contents = module_contents,
					Dependencies = {},
					Failure = init_results[index].init_failure,
				}

				nodes[#nodes + 1] = node
				node_by_name[module_name] = node
				--

				--
				if type(module_contents) ~= "table" then
					continue
				end
				--

				--
				node.Keeper = (rawget(module_contents, "Keeper") :: Keeper.Keeper?) or Keeper.new()
				module_contents.Keeper = node.Keeper

				node_by_contents[module_contents] = node
				--
			end

			--
			resolve_dependencies(nodes, node_by_contents)
			apply_legacy_load_order(node_by_name)
			--

			--
			const cycle = find_cycle(nodes)

			if cycle then
				return Promise.reject(`Cyclic module dependency: {table.concat(cycle, " -> ")}`)
			end
			--

			local function start_node(node: ModuleNode): Promise.Promise
				--
				if node.StartPromise then
					return node.StartPromise
				end
				--

				--
				const dependency_promises: { Promise.Promise } = {}

				for _, dependency in node.Dependencies do
					dependency_promises[#dependency_promises + 1] = start_node(dependency)
				end
				--

				const start_promise = Promise.all(dependency_promises)
					:andThen(function()
						--
						if node.Failure then
							return Promise.reject(node.Failure)
						end
						--

						--
						const module_contents = node.Contents

						if type(module_contents) ~= "table" or type(module_contents.Start) ~= "function" then
							return nil
						end
						--

						return Promise.try(module_contents.Start, module_contents):catch(function(err)
							--
							warn(`Error in Start of module {node.Name}:`, err.error)
							--

							return Promise.reject(node.Name)
						end)
					end)
					:catch(function(root_failure)
						--
						if root_failure ~= node.Name then
							warn(`Skipped Start of module {node.Name}: dependency {root_failure} failed`)
						end
						--

						return Promise.reject(root_failure)
					end)

				--
				node.StartPromise = start_promise
				--

				return start_promise
			end

			--
			const settled: { Promise.Promise } = {}

			for _, node in nodes do
				settled[#settled + 1] = start_node(node):catch(function() end)
			end
			--

			return Promise.all(settled):andThen(function()
				--
				self.Nodes = nodes
				self.IsLoaded = true

				print("Loaded", #nodes, "modules")
				--

				return loaded_modules
			end)
		end)
		:catch(function(err)
			--
			warn("Error loading modules:", err)
			--

			return Promise.reject(err)
		end)

	return results
end

--[=[
	Stops every loaded module and destroys its Keeper.

	The mirror of the start phase: a module stops before the modules it depends on, which
	is the reverse of the order they started in. `Replication` starting before
	`SessionManager` means `SessionManager` stops before `Replication` -- so a module is
	never torn down while something still depending on it is live. Modules that do not
	depend on each other stop concurrently, for the same reason they start concurrently.

	A module's Keeper is destroyed after its own `Stop` returns, so `Stop` can still use
	whatever the Keeper is holding.

	@return Promise -- Resolves once every module has stopped.
]=]
function Component.StopModulesAsync(self: LoaderState): Promise.Promise
	--
	const nodes: { ModuleNode }? = self.Nodes

	if not nodes or #nodes == 0 then
		self.IsLoaded = false
		return Promise.resolve()
	end
	--

	--
	const dependents: { [ModuleNode]: { ModuleNode } } = {}

	for _, node in nodes do
		for _, dependency in node.Dependencies do
			local list = dependents[dependency]

			if not list then
				list = {}
				dependents[dependency] = list
			end

			list[#list + 1] = node
		end
	end
	--

	local function stop_node(node: ModuleNode): Promise.Promise
		--
		if node.StopPromise then
			return node.StopPromise
		end
		--

		--
		const dependent_promises: { Promise.Promise } = {}

		for _, dependent in dependents[node] or {} do
			dependent_promises[#dependent_promises + 1] = stop_node(dependent)
		end
		--

		const stop_promise = Promise.all(dependent_promises)
			:andThen(function()
				--
				const module_contents = node.Contents

				if type(module_contents) ~= "table" or type(module_contents.Stop) ~= "function" then
					return nil
				end
				--

				return Promise.try(module_contents.Stop, module_contents):catch(function(err)
					warn(`Error in Stop of module {node.Name}:`, err.error)
				end)
			end)
			:andThen(function()
				--
				const keeper = node.Keeper

				if not keeper then
					return
				end
				--

				--
				keeper:Destroy()
				node.Keeper = nil
				--
			end)

		--
		node.StopPromise = stop_promise
		--

		return stop_promise
	end

	--
	const settled: { Promise.Promise } = {}

	for _, node in nodes do
		settled[#settled + 1] = stop_node(node)
	end
	--

	return Promise.all(settled):andThen(function()
		--
		self.Nodes = nil
		self.Modules = {}
		self.LoadedModules = {}
		self.IsLoaded = false
		--

		print("Stopped", #nodes, "modules")
	end)
end

--
local ComponentClass = {}
ComponentClass.__index = ComponentClass
--

function Component.new<m>(module: m): m
	--
	const self = (setmetatable((module :: any) :: {}, ComponentClass) :: any) :: m
	--

	--
	if rawget(self :: any, "Keeper") == nil then
		(self :: any).Keeper = Keeper.new()
	end
	--

	return self
end

return Component
