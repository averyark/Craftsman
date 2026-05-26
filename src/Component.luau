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

local Component = {}
Component.Modules = {}
Component.IsLoaded = false
Component.LoadedModules = {}

-- Print a compact debug state for this component

function Component:LoadModulesAsync(modules: Instance)
	self.Modules = self.Modules or {}
	self.LoadedModules = self.LoadedModules or {}

	local module_names = {}
	local promises = {}
	local module_order = {}

	for index = 1, #Config.MODULE_LOAD_ORDER do
		module_order[Config.MODULE_LOAD_ORDER[index]] = index
	end

	local descendants = modules:GetDescendants()
	local ordered_descendants = {}

	for index = 1, #descendants do
		local module = descendants[index]
		ordered_descendants[#ordered_descendants + 1] = {
			module = module,
			module_name = module.Name,
			load_order = module_order[module.Name],
			source_index = index,
		}
	end

	table.sort(ordered_descendants, function(left, right)
		local left_order = left.load_order
		local right_order = right.load_order

		if left_order and right_order then
			return left_order < right_order
		end

		if left_order then
			return true
		end

		if right_order then
			return false
		end

		return left.source_index < right.source_index
	end)

	for index = 1, #ordered_descendants do
		local module_entry = ordered_descendants[index]
		local module = module_entry.module
		if not module:IsA("ModuleScript") then
			continue
		end

		local module_name = module_entry.module_name
		module_names[#module_names + 1] = module_name

		promises[#promises + 1] = Promise.new(function(resolve, reject)
			local ok, module_contents = pcall(require, module)
			if not ok then
				reject(module_contents)
				return
			end

			if module_contents.Init and type(module_contents.Init) == "function" then
				local init_ok, init_err = pcall(module_contents.Init, module_contents)
				if not init_ok then
					PrintUtil:Warn(`Error in Init of module {module_name}:`, init_err)
				end
			end

			resolve(module_contents)
		end)
	end

	local results = Promise.all(promises)
		:andThen(function(module_contents)
			local loaded_modules = {}

			for index = 1, #module_contents do
				local module_name = module_names[index]
				local module_contents = module_contents[index]

				loaded_modules[module_name] = module_contents
				self.Modules[module_name] = module_contents
				self.LoadedModules[module_name] = module_contents
				if module_contents.Start and type(module_contents.Start) == "function" then
					Promise.try(module_contents.Start, module_contents)
						:catch(function(err)
							PrintUtil:Warn(`Error in Start of module {module_name}:`, err.error)
						end)
						:await()
				end
			end

			self.IsLoaded = true
			PrintUtil:Print("Loaded", #module_contents, "modules")
			return loaded_modules
		end)
		:catch(function(err)
			PrintUtil:Warn("Error loading modules:", err)
			return Promise.reject(err)
		end)

	return results
end

local ComponentClass = {}
ComponentClass.__index = ComponentClass

function Component.new<m>(module: m): m
	local self = (setmetatable((module :: any) :: {}, ComponentClass) :: any) :: m

	return self
end

return Component
