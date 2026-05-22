--!strict
--[[
    FileName    > TableUti.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 22/05/2026
--]]

local TableUtil = {}

function TableUtil.DeepClone<T>(value: T, seen: { [any]: any }?): T
	if type(value) ~= "table" then
		return value
	end

	local seen_table = seen or {}
	if seen_table[value] then
		return seen_table[value]
	end

	local clone = {}
	seen_table[value] = clone

	for key, child in value :: any do
		clone[TableUtil.DeepClone(key, seen_table)] = TableUtil.DeepClone(child, seen_table)
	end

	return clone :: any
end

function TableUtil.Merge(...: { [any]: any }): { [any]: any }
	local merged = {}
	local sources = { ... }

	for i = 1, #sources do
		local source = sources[i]
		if type(source) ~= "table" then
			continue
		end

		for key, value in source do
			merged[key] = value
		end
	end

	return merged
end

function TableUtil.DeepMerge(...: { [any]: any }): { [any]: any }
	local merged = {}
	local sources = { ... }

	for i = 1, #sources do
		local source = sources[i]
		if type(source) ~= "table" then
			continue
		end

		for key, value in source do
			if type(value) == "table" and type(merged[key]) == "table" then
				merged[key] = TableUtil.DeepMerge(merged[key], value)
			else
				merged[key] = type(value) == "table" and TableUtil.DeepClone(value) or value
			end
		end
	end

	return merged
end

function TableUtil.IsEmpty(dict: { [any]: any }): boolean
	return next(dict) == nil
end

function TableUtil.Keys<K>(dict: { [K]: any }): { K }
	local keys = {}

	for key in dict do
		table.insert(keys, key)
	end

	return keys
end

function TableUtil.Values<V>(dict: { [any]: V }): { V }
	local values = {}

	for _, value in dict do
		table.insert(values, value)
	end

	return values
end

function TableUtil.FindKeyByValue<K, V>(dict: { [K]: V }, target_value: V): K?
	for key, value in dict do
		if value == target_value then
			return key
		end
	end

	return nil
end

function TableUtil.RemoveValue<K, V>(dict: { [K]: V }, target_value: V): boolean
	local removed = false

	for key, value in dict do
		if value ~= target_value then
			continue
		end

		(dict :: any)[key] = nil
		removed = true
	end

	return removed
end

function TableUtil.RemoveWhere<K, V>(dict: { [K]: V }, predicate: (value: V, key: K, dict: { [K]: V }) -> boolean): boolean
	local removed = false

	for key, value in dict do
		if not predicate(value, key, dict) then
			continue
		end

		(dict :: any)[key] = nil
		removed = true
	end

	return removed
end

function TableUtil.HasKey<K>(dict: { [K]: any }, key: K): boolean
	return dict[key] ~= nil
end

function TableUtil.GetOrDefault<K, V>(dict: { [K]: V }, key: K, default_value: V): V
	local value = dict[key]
	if value ~= nil then
		return value
	end

	return default_value
end

function TableUtil.Count(dict: { [any]: any }): number
	local count = 0

	for _ in dict do
		count += 1
	end

	return count
end

function TableUtil.EqualDeep(left: any, right: any, seen: { [any]: any }?): boolean
	if left == right then
		return true
	end

	if type(left) ~= "table" or type(right) ~= "table" then
		return false
	end

	local seen_table = seen or {}
	local left_seen = seen_table[left]
	if left_seen and left_seen[right] then
		return true
	end

	left_seen = left_seen or {}
	seen_table[left] = left_seen
	left_seen[right] = true

	for key, left_value in left :: any do
		local right_value = (right :: any)[key]
		if not TableUtil.EqualDeep(left_value, right_value, seen_table) then
			return false
		end
	end

	for key, _ in right :: any do
		if (left :: any)[key] == nil then
			return false
		end
	end

	return true
end

function TableUtil.SafeRemove<T>(array: { T }, value: T): boolean
	local index = table.find(array, value)
	if index then
		table.remove(array, index)
		return true
	end
	return false
end

function TableUtil.SafeRemoveAll<T>(array: { T }, value: T): boolean
	local removed = false
	for i = #array, 1, -1 do
		if array[i] == value then
			table.remove(array, i)
			removed = true
		end
	end
	return removed
end

return TableUtil
