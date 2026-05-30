--!strict
--[[
    FileName    > TableUtil.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 22/05/2026
--]]

--[[
	@class TableUtil
	A utility library containing operations for manipulating and querying Luau tables.
]]--
local TableUtil = {}

--[[
	Recursively deep clones a value, supporting cyclic/nested tables via a seen-table cache.
	Non-table values are returned as-is.
	@param value T -- The table or value to clone.
	@param seen { [any]: any }? -- Optional cache of already cloned tables (used internally for cyclic structures).
	@return T -- The deep cloned value or table.
]]--
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

--[[
	Shallow merges multiple tables from left to right. Later keys overwrite earlier ones.
	@param ... { [any]: any } -- The list of tables to merge.
	@return { [any]: any } -- A new merged dictionary.
]]--
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

--[[
	Deeply merges multiple tables from left to right. Nested tables are merged recursively.
	@param ... { [any]: any } -- The list of tables to deep-merge.
	@return { [any]: any } -- A new deeply-merged dictionary.
]]--
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

--[[
	Checks if a dictionary is completely empty.
	@param dict { [any]: any } -- The dictionary to check.
	@return boolean -- `true` if the dictionary has no keys, `false` otherwise.
]]--
function TableUtil.IsEmpty(dict: { [any]: any }): boolean
	return next(dict) == nil
end

--[[
	Extracts all keys from a dictionary and returns them as a list/array.
	@param dict { [K]: any } -- The source dictionary.
	@return { K } -- An array of keys from the dictionary.
]]--
function TableUtil.Keys<K>(dict: { [K]: any }): { K }
	local keys = {}

	for key in dict do
		table.insert(keys, key)
	end

	return keys
end

--[[
	Extracts all values from a dictionary and returns them as a list/array.
	@param dict { [any]: V } -- The source dictionary.
	@return { V } -- An array of values from the dictionary.
]]--
function TableUtil.Values<V>(dict: { [any]: V }): { V }
	local values = {}

	for _, value in dict do
		table.insert(values, value)
	end

	return values
end

--[[
	Searches for a specific value in a dictionary and returns its corresponding key.
	@param dict { [K]: V } -- The dictionary to search.
	@param target_value V -- The value to look for.
	@return K? -- The key corresponding to the value, or `nil` if not found.
]]--
function TableUtil.FindKeyByValue<K, V>(dict: { [K]: V }, target_value: V): K?
	for key, value in dict do
		if value == target_value then
			return key
		end
	end

	return nil
end

--[[
	Removes all occurrences of a specific value from a dictionary (in-place).
	@param dict { [K]: V } -- The dictionary to modify.
	@param target_value V -- The value to remove.
	@return boolean -- `true` if at least one value was removed, `false` otherwise.
]]--
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

--[[
	Removes all key-value pairs from a dictionary that satisfy a predicate function (in-place).
	@param dict { [K]: V } -- The dictionary to modify.
	@param predicate (value: V, key: K, dict: { [K]: V }) -> boolean -- The function to determine removal.
	@return boolean -- `true` if at least one pair was removed, `false` otherwise.
]]--
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

--[[
	Checks if a dictionary has a specific key (i.e. its value is not `nil`).
	@param dict { [K]: any } -- The dictionary to check.
	@param key K -- The key to look for.
	@return boolean -- `true` if the key exists, `false` otherwise.
]]--
function TableUtil.HasKey<K>(dict: { [K]: any }, key: K): boolean
	return dict[key] ~= nil
end

--[[
	Returns the value associated with a key, or a default value if the key does not exist.
	@param dict { [K]: V } -- The source dictionary.
	@param key K -- The key to look up.
	@param default_value V -- The fallback value if key is missing.
	@return V -- The value or the default value.
]]--
function TableUtil.GetOrDefault<K, V>(dict: { [K]: V }, key: K, default_value: V): V
	local value = dict[key]
	if value ~= nil then
		return value
	end

	return default_value
end

--[[
	Counts the total number of key-value pairs inside a dictionary.
	@param dict { [any]: any } -- The dictionary to count.
	@return number -- The total count of entries.
]]--
function TableUtil.Count(dict: { [any]: any }): number
	local count = 0

	for _ in dict do
		count += 1
	end

	return count
end

--[[
	Deeply compares two tables/values for equality, supporting cyclic structures.
	@param left any -- The first value/table to compare.
	@param right any -- The second value/table to compare.
	@param seen { [any]: any }? -- Optional cache of already-compared tables (used internally).
	@return boolean -- `true` if both values are deeply equal, `false` otherwise.
]]--
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

--[[
	Safely removes the first occurrence of a value in an array list (in-place).
	@param array { T } -- The array list to modify.
	@param value T -- The value to remove.
	@return boolean -- `true` if the value was found and removed, `false` otherwise.
]]--
function TableUtil.SafeRemove<T>(array: { T }, value: T): boolean
	local index = table.find(array, value)
	if index then
		table.remove(array, index)
		return true
	end
	return false
end

--[[
	Safely removes all occurrences of a value in an array list, traversing backwards (in-place).
	@param array { T } -- The array list to modify.
	@param value T -- The value to remove.
	@return boolean -- `true` if at least one value was found and removed, `false` otherwise.
]]--
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

--[[
	Returns a new table excluding items present in the second table.
	Works for both array list exclusions (by value check) and dictionaries (by key presence check).
	@param first { [K]: V } -- The base table.
	@param second { [any]: any } -- The items to exclude.
	@return { [K]: V } -- A new table without the items from the second table.
]]--
function TableUtil.Except<K, V>(first: { [K]: V }, second: { [any]: any }): { [K]: V }
	local result = {}
	local lookup = {}

	local second_is_array = true
	for key in second :: any do
		if type(key) ~= "number" then
			second_is_array = false
			break
		end
	end

	if second_is_array then
		for _, value in second :: any do
			lookup[value] = true
		end
	else
		for key in second :: any do
			lookup[key] = true
		end
	end

	local first_is_array = true
	for key in first :: any do
		if type(key) ~= "number" then
			first_is_array = false
			break
		end
	end

	if first_is_array then
		for _, value in first :: any do
			if not lookup[value] then
				table.insert(result, value)
			end
		end
	else
		for key, value in first :: any do
			if not lookup[key] then
				result[key] = value
			end
		end
	end

	return result :: any
end

return TableUtil
