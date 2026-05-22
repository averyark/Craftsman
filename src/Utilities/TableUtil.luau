--!nonstrict
--[[
    FileName    > TableUti.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 22/05/2026
--]]

local TableUtil = {}

function TableUtil.DeepClone(value, seen)
	if type(value) ~= "table" then
		return value
	end

	seen = seen or {}
	if seen[value] then
		return seen[value]
	end

	local clone = {}
	seen[value] = clone

	for key, child in value do
		clone[TableUtil.DeepClone(key, seen)] = TableUtil.DeepClone(child, seen)
	end

	return clone
end

function TableUtil.Merge(...)
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

function TableUtil.DeepMerge(...)
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

function TableUtil.IsEmpty(dict)
	return next(dict) == nil
end

function TableUtil.Keys(dict)
	local keys = {}

	for key in dict do
		table.insert(keys, key)
	end

	return keys
end

function TableUtil.Values(dict)
	local values = {}

	for _, value in dict do
		table.insert(values, value)
	end

	return values
end

function TableUtil.FindKeyByValue(dict, target_value)
	for key, value in dict do
		if value == target_value then
			return key
		end
	end

	return nil
end

function TableUtil.RemoveValue(dict, target_value)
	local removed = false

	for key, value in dict do
		if value ~= target_value then
			continue
		end

		dict[key] = nil
		removed = true
	end

	return removed
end

function TableUtil.RemoveWhere(dict, predicate)
	local removed = false

	for key, value in dict do
		if not predicate(value, key, dict) then
			continue
		end

		dict[key] = nil
		removed = true
	end

	return removed
end

function TableUtil.HasKey(dict, key)
	return dict[key] ~= nil
end

function TableUtil.GetOrDefault(dict, key, default_value)
	local value = dict[key]
	if value ~= nil then
		return value
	end

	return default_value
end

function TableUtil.Count(dict)
	local count = 0

	for _ in dict do
		count += 1
	end

	return count
end

function TableUtil.EqualDeep(left, right, seen)
	if left == right then
		return true
	end

	if type(left) ~= "table" or type(right) ~= "table" then
		return false
	end

	seen = seen or {}
	local left_seen = seen[left]
	if left_seen and left_seen[right] then
		return true
	end

	left_seen = left_seen or {}
	seen[left] = left_seen
	left_seen[right] = true

	for key, left_value in left do
		local right_value = right[key]
		if not TableUtil.EqualDeep(left_value, right_value, seen) then
			return false
		end
	end

	for key, _ in right do
		if left[key] == nil then
			return false
		end
	end

	return true
end

function TableUtil.SafeRemove(array, value)
	local index = table.find(array, value)
	if index then
		table.remove(array, index)
		return true
	end
	return false
end

function TableUtil.SafeRemoveAll(array, value)
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
