--!nonstrict
--[[
    FileName    > Component.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 20/05/2026
--]]
const PrintUtil = require("./Utilities/PrintUtil")
const Promise = require("../../../Promise")
const Config = require("./Config")
const Keeper = require("../../../Keeper")

type ModuleNode = {
	Name: string,
	Contents: any,
	Dependencies: { ModuleNode },
	Failure: string?,
	Keeper: any?,
	StartPromise: any?,
	StopPromise: any?,
}

local Component = {}
Component.Modules = {}
Component.IsLoaded = false
Component.LoadedModules = {}

--
local function resolve_dependencies(nodes: { ModuleNode }, node_by_contents: { [any]: ModuleNode })
	for _, node in nodes do
		--
		if type(node.Contents) ~= "table" then
			continue
		end
		--

		--
		local declared = rawget(node.Contents, "Dependencies")

		if declared == nil then
			continue
		end
		--

		--
		if type(declared) ~= "table" then
			PrintUtil:Warn(`Dependencies of module {node.Name} must be a table, got {type(declared)}`)
			continue
		end
		--

		--
		for index, declared_contents in declared do
			--
			local dependency_node = node_by_contents[declared_contents]

			if not dependency_node then
				PrintUtil:Warn(
					`Module {node.Name} declares a dependency at index {index} that is not a loaded module. II gnoring it`
				)
				continue
			end
			--

			--
			if dependency_node == node then
				PrintUtil:Warn(`Module {node.Name} declares itself as a dependency; ignoring it`)
				continue
			end
			--

			--
			node.Dependencies[#node.Dependencies + 1] = dependency_node
			--
		end
		--
	end
end

--
local function find_cycle(nodes: { ModuleNode }): { string }?
	--
	local visit_state: { [ModuleNode]: number } = {}
	local stack: { ModuleNode } = {}
	--

	--
	local function visit(node: ModuleNode): { string }?
		--
		local state = visit_state[node]

		if state == 2 then
			return nil
		end
		--

		--
		if state == 1 then
			--
			local cycle = {}
			local reached_entry = false
			--

			for _, entry in stack do
				--
				if entry == node then
					reached_entry = true
				end
				--

				if reached_entry then
					cycle[#cycle + 1] = entry.Name
				end
			end

			cycle[#cycle + 1] = node.Name
			return cycle
		end
		--

		--
		visit_state[node] = 1
		stack[#stack + 1] = node
		--

		--
		for _, dependency in node.Dependencies do
			local cycle = visit(dependency)
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
		local cycle = visit(node)
		if cycle then
			return cycle
		end
	end

	return nil
end

function Component:LoadModulesAsync(modules: Instance)
	--
	self.Modules = self.Modules or {}
	self.LoadedModules = self.LoadedModules or {}
	--

	--
	local module_names = {}
	local promises = {}
	local module_order = {}
	--

	--
	for index, module_name in Config.MODULE_LOAD_ORDER do
		module_order[module_name] = index
	end
	--

	--
	local descendants = modules:GetDescendants()
	local ordered_descendants = {}

	for index, module in descendants do
		ordered_descendants[#ordered_descendants + 1] = {
			module = module,
			module_name = module.Name,
			load_order = module_order[module.Name],
			source_index = index,
		}
	end
	--

	table.sort(ordered_descendants, function(left, right)
		--
		local left_order = left.load_order
		local right_order = right.load_order

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
		local module = module_entry.module

		if not module:IsA("ModuleScript") or module.Name:match("%.spec$") then
			continue
		end
		--

		--
		local module_name = module_entry.module_name
		module_names[#module_names + 1] = module_name
		--

		--
		promises[#promises + 1] = Promise.new(function(resolve, reject)
			--
			local success, module_contents = pcall(require, module)

			if not success then
				reject(module_contents)
				return
			end
			--

			local init_failure = nil

			--
			if type(module_contents) == "table" and module_contents.Init and type(module_contents.Init) == "function" then
				local init_success, init_err = pcall(module_contents.Init, module_contents)

				if not init_success then
					PrintUtil:Warn(`Error in Init of module {module_name}:`, init_err)
					init_failure = module_name
				end
			end
			--

			resolve({ contents = module_contents, init_failure = init_failure })
		end)
	end

	local results = Promise.all(promises)
		:andThen(function(init_results)
			local loaded_modules = {}
			local nodes: { ModuleNode } = {}
			local node_by_contents: { [any]: ModuleNode } = {}
			local node_by_name: { [string]: ModuleNode } = {}

			for index, init_result in init_results do
				--
				local module_name = module_names[index]
				local module_contents = init_result.contents

				loaded_modules[module_name] = module_contents
				self.Modules[module_name] = module_contents
				self.LoadedModules[module_name] = module_contents
				--

				--
				local node: ModuleNode = {
					Name = module_name,
					Contents = module_contents,
					Dependencies = {},
					Failure = init_results[index].init_failure,
				}
				--

				--
				if type(module_contents) == "table" then
					node.Keeper = rawget(module_contents, "Keeper") or Keeper.new()
					module_contents.Keeper = node.Keeper
				end
				--

				--
				nodes[#nodes + 1] = node
				node_by_name[module_name] = node
				--

				--
				if type(module_contents) == "table" then
					node_by_contents[module_contents] = node
				end
				--
			end

			resolve_dependencies(nodes, node_by_contents)

			if #Config.MODULE_LOAD_ORDER > 0 then
				PrintUtil:Warn(
					"Config.MODULE_LOAD_ORDER is deprecated. Declare Dependencies on the modules themselves instead"
				)

				local previous_node = nil
				for _, module_name in Config.MODULE_LOAD_ORDER do
					local node = node_by_name[module_name]
					if not node then
						continue
					end
					if previous_node then
						node.Dependencies[#node.Dependencies + 1] = previous_node
					end
					previous_node = node
				end
			end

			local cycle = find_cycle(nodes)
			if cycle then
				return Promise.reject(`Cyclic module dependency: {table.concat(cycle, " -> ")}`)
			end

			--
			local function start_node(node: ModuleNode)
				if node.StartPromise then
					return node.StartPromise
				end

				local dependency_promises = {}
				for _, dependency in node.Dependencies do
					dependency_promises[#dependency_promises + 1] = start_node(dependency)
				end

				node.StartPromise = Promise.all(dependency_promises)
					:andThen(function()
						--
						if node.Failure then
							return Promise.reject(node.Failure)
						end
						--

						--
						local module_contents = node.Contents

						if
							type(module_contents) ~= "table"
							or type(module_contents.Start) ~= "function"
						then
							return nil
						end
						--

						return Promise.try(module_contents.Start, module_contents):catch(function(err)
							PrintUtil:Warn(`Error in Start of module {node.Name}:`, err.error)
							return Promise.reject(node.Name)
						end)
					end)
					:catch(function(root_failure)
						--
						if root_failure ~= node.Name then
							PrintUtil:Warn(
								`Skipped Start of module {node.Name}: dependency {root_failure} failed`
							)
						end
						--
						return Promise.reject(root_failure)
					end)

				return node.StartPromise
			end
			--

			--
			local settled = {}

			for _, node in nodes do
				settled[#settled + 1] = start_node(node):catch(function() end)
			end
			--

			return Promise.all(settled):andThen(function()
				--
				self.Nodes = nodes
				self.IsLoaded = true
				PrintUtil:Print("Loaded", #nodes, "modules")
				return loaded_modules
			end)
		end)
		:catch(function(err)
			PrintUtil:Warn("Error loading modules:", err)
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
--
function Component:StopModulesAsync()
	--
	local nodes: { ModuleNode }? = self.Nodes

	if not nodes or #nodes == 0 then
		self.IsLoaded = false
		return Promise.resolve()
	end
	--

	--
	local dependents: { [ModuleNode]: { ModuleNode } } = {}

	for _, node in nodes do
		for _, dependency in node.Dependencies do
			--
			local list = dependents[dependency]

			if not list then
				list = {}
				dependents[dependency] = list
			end
			--

			list[#list + 1] = node
		end
	end
	--

	local function stop_node(node: ModuleNode)
		if node.StopPromise then
			return node.StopPromise
		end

		--
		local dependent_promises = {}

		for _, dependent in dependents[node] or {} do
			dependent_promises[#dependent_promises + 1] = stop_node(dependent)
		end
		--

		--
		node.StopPromise = Promise.all(dependent_promises)
			:andThen(function()
				local module_contents = node.Contents
				if type(module_contents) ~= "table" or type(module_contents.Stop) ~= "function" then
					return nil
				end

				--
				return Promise.try(module_contents.Stop, module_contents):catch(function(err)
					PrintUtil:Warn(`Error in Stop of module {node.Name}:`, err.error)
				end)
				--
			end)
			:andThen(function()
				if node.Keeper then
					node.Keeper:Destroy()
					node.Keeper = nil
				end
			end)
		--

		return node.StopPromise
	end


	--
	local settled = {}

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

		PrintUtil:Print("Stopped", #nodes, "modules")
	end)
end

local ComponentClass = {}
ComponentClass.__index = ComponentClass

function Component.new<m>(module: m): m
	--
	local self = (setmetatable((module :: any) :: {}, ComponentClass) :: any) :: m
	--

	--
	if rawget(self :: any, "Keeper") == nil then
		(self :: any).Keeper = Keeper.new()
	end
	--

	return self
end

return Component
