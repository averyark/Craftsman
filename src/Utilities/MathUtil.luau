--!nonstrict
--[[
    FileName    > MathUtil.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 20/05/2026
--]]

--[=[
	@class MathUtil
	A comprehensive library of mathematical utilities, vector helper operations, interpolation functions, and Bezier curves.
]=]
--
const MathUtil = {}

const SUFFIXES = { "k", "M", "B", "T", "Qd", "Qn" }

const ONES = { "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine" }
const TEENS =
	{ "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen" }
const TENS = { "", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety" }
const SCALES = { "", "thousand", "million", "billion", "trillion", "quadrillion", "quintillion" }

--[=[
	Maps a value from one range to another range.
	@param value number -- The value to map.
	@param in_min number -- The lower bound of the input range.
	@param in_max number -- The upper bound of the input range.
	@param out_min number -- The lower bound of the output range.
	@param out_max number -- The upper bound of the output range.
	@return number -- The mapped value.
]=]
--
function MathUtil.Map(value, in_min, in_max, out_min, out_max)
	return out_min + (value - in_min) * (out_max - out_min) / (in_max - in_min)
end

--[=[
	Linearly interpolates between two numbers.
	@param a number -- The starting value.
	@param b number -- The target value.
	@param alpha number -- The interpolation fraction (usually 0 to 1).
	@return number -- The interpolated value.
]=]
--
function MathUtil.Lerp(a, b, alpha)
	return a + (b - a) * alpha
end

--[=[
	Calculates the inverse linear interpolation (fraction) of a value between two numbers.
	@param a number -- The starting value.
	@param b number -- The target value.
	@param value number -- The interpolated value.
	@return number -- The interpolation fraction (alpha).
]=]
--
function MathUtil.InverseLerp(a, b, value)
	return (value - a) / (b - a)
end

--[=[
	Exponential decay lerp. Frame-rate independent smoothing for cameras, UI, and following logic.
	@param current number -- The current value.
	@param target number -- The target value.
	@param rate number -- The decay rate (higher values reach the target faster).
	@param delta_time number -- The time step (dt).
	@return number -- The smoothed value.
]=]
--
function MathUtil.SmoothLerp(current, target, rate, delta_time)
	return target + (current - target) * math.exp(-rate * delta_time)
end

--[=[
	Abbreviates large numbers into short strings (e.g., 1500 -> "1.5k", 1000000 -> "1M").
	@param value number -- The number to abbreviate.
	@return string -- The abbreviated string.
]=]
--
function MathUtil.Abbreviate(value)
	if value < 1000 then
		return tostring(value)
	end

	local index = math.floor(math.log10(value) / 3)
	local divisor = 10 ^ (index * 3)
	local formatted_number = string.format("%.1f", value / divisor)

	formatted_number = formatted_number:gsub("%.0$", "")

	return formatted_number .. SUFFIXES[index]
end

--[=[
	Formats a number with comma separators (e.g., 1000000 -> "1,000,000").
	@param value number -- The number to format.
	@return string -- The formatted string with commas.
]=]
--
function MathUtil.AddCommas(value)
	local formatted = tostring(value)
	local replacements

	while true do
		formatted, replacements = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		if replacements == 0 then
			break
		end
	end

	return formatted
end

--[=[
	Converts a number into its English word representation (e.g., 123 -> "one hundred twenty three").
	Supports decimals and negative numbers.
	@param number number -- The number to convert.
	@return string -- The word representation of the number.
]=]
--
function MathUtil.NumberToWords(number)
	if number == 0 then
		return "zero"
	end

	local negative = false
	if number < 0 then
		negative = true
		number = -number
	end

	local integer_part = math.floor(number)

	local function three_digits_to_words(n)
		local parts = {}
		local hundreds = math.floor(n / 100)
		local remainder = n % 100

		if hundreds > 0 then
			table.insert(parts, ONES[hundreds + 1])
			table.insert(parts, "hundred")
		end

		if remainder >= 20 then
			local tens = math.floor(remainder / 10)
			local ones_digit = remainder % 10
			table.insert(parts, TENS[tens + 1])
			if ones_digit > 0 then
				table.insert(parts, ONES[ones_digit + 1])
			end
		elseif remainder >= 10 then
			table.insert(parts, TEENS[remainder - 9])
		elseif remainder > 0 then
			table.insert(parts, ONES[remainder + 1])
		end

		return table.concat(parts, " ")
	end

	local words_parts = {}
	local scale_index = 1
	while integer_part > 0 do
		local chunk = integer_part % 1000
		if chunk > 0 then
			local chunk_words = three_digits_to_words(chunk)
			local scale_word = SCALES[scale_index]
			if scale_word ~= nil and scale_word ~= "" then
				chunk_words = chunk_words .. " " .. scale_word
			end
			table.insert(words_parts, 1, chunk_words)
		end

		integer_part = math.floor(integer_part / 1000)
		scale_index += 1
	end

	local result = table.concat(words_parts, " ")
	if result == "" then
		result = "zero"
	end
	if negative then
		result = "minus " .. result
	end

	local fractional = number - math.floor(number)
	if fractional > 0 then
		local frac_str = tostring(number):match("%.(%d+)$")
		if frac_str then
			local frac_words = { "point" }
			for i = 1, #frac_str do
				local digit = tonumber(frac_str:sub(i, i))
				table.insert(frac_words, ONES[digit + 1])
			end
			result = result .. " " .. table.concat(frac_words, " ")
		end
	end

	return result
end

--[=[
	Formats seconds into a standard digital timer format `MM:SS`.
	@param total_seconds number -- The time in seconds.
	@return string -- The formatted time string (e.g., "02:30").
]=]
--
function MathUtil.FormatTime(total_seconds)
	local minutes = math.floor(total_seconds / 60)
	local seconds = math.floor(total_seconds % 60)

	return string.format("%02d:%02d", minutes, seconds)
end

--[=[
	Rounds a number to the nearest step/multiple.
	@param value number -- The number to round.
	@param step number -- The step increment (e.g., 0.5, 5, 10).
	@return number -- The rounded value.
]=]
--
function MathUtil.RoundTo(value, step)
	return math.round((value / step)) * step
end

--[=[
	Wraps a value within a specified range [min, max).
	@param value number -- The value to wrap.
	@param min number -- The lower bound (inclusive).
	@param max number -- The upper bound (exclusive).
	@return number -- The wrapped value.
]=]
--
function MathUtil.Wrap(value, min, max)
	return min + (value - min) % (max - min)
end

--[=[
	Calculates the unit direction vector pointing from `origin_pos` to `target_pos`.
	Returns Vector3.zero if the distance is 0.
	@param origin_pos Vector3 -- The starting position.
	@param target_pos Vector3 -- The destination position.
	@return Vector3 -- The normalized unit direction vector.
]=]
--
function MathUtil.Direction(origin_pos, target_pos)
	local direction_vector = target_pos - origin_pos
	if direction_vector.Magnitude == 0 then
		return Vector3.zero
	end

	return direction_vector.Unit
end

--[=[
	Zeroes out the Y component of a Vector3, leaving X and Z intact.
	@param vector Vector3 -- The input vector.
	@return Vector3 -- The flattened Vector3.
]=]
--
function MathUtil.Flatten(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

--[=[
	Calculates the 2D distance between two points ignoring height (Y component).
	@param pos_a Vector3 -- The first position.
	@param pos_b Vector3 -- The second position.
	@return number -- The horizontal distance between pos_a and pos_b.
]=]
--
function MathUtil.FlatDistance(pos_a, pos_b)
	local dx = pos_a.X - pos_b.X
	local dz = pos_a.Z - pos_b.Z
	return math.sqrt(dx * dx + dz * dz)
end

--[=[
	Calculates the angle in radians between two vectors.
	@param vec_a Vector3 -- The first vector.
	@param vec_b Vector3 -- The second vector.
	@return number -- The angle in radians between the two vectors.
]=]
--
function MathUtil.AngleBetween(vec_a, vec_b)
	local dot_product = vec_a:Dot(vec_b)
	local magnitudes = vec_a.Magnitude * vec_b.Magnitude
	if magnitudes == 0 then
		return 0
	end

	return math.acos(math.clamp(dot_product / magnitudes, -1, 1))
end

--[=[
	Returns the shortest angular distance in degrees between two angles (-180 to 180).
	Useful for motor hinges, turrets, and angle alignments.
	@param current_angle number -- The current angle in degrees.
	@param target_angle number -- The target angle in degrees.
	@return number -- The shortest angular difference in degrees.
]=]
--
function MathUtil.ShortestAngle(current_angle, target_angle)
	local difference = (target_angle - current_angle) % 360
	if difference > 180 then
		difference -= 360
	end

	return difference
end

--[=[
	Calculates a point along a quadratic Bezier curve.
	@param t number -- The interpolation fraction (0 to 1).
	@param p0 Vector3 -- The starting point.
	@param p1 Vector3 -- The control point.
	@param p2 Vector3 -- The ending point.
	@return Vector3 -- The calculated point on the curve.
]=]
--
function MathUtil.QuadraticBezier(t, p0, p1, p2)
	local u = 1 - t
	return (u ^ 2) * p0 + 2 * u * t * p1 + (t ^ 2) * p2
end

--[=[
	Calculates a point along a cubic Bezier curve.
	@param t number -- The interpolation fraction (0 to 1).
	@param p0 Vector3 -- The starting point.
	@param p1 Vector3 -- The first control point.
	@param p2 Vector3 -- The second control point.
	@param p3 Vector3 -- The ending point.
	@return Vector3 -- The calculated point on the curve.
]=]
--
function MathUtil.CubicBezier(t, p0, p1, p2, p3)
	local u = 1 - t
	return (u ^ 3) * p0 + 3 * (u ^ 2) * t * p1 + 3 * u * (t ^ 2) * p2 + (t ^ 3) * p3
end

--[=[
	Zeroes out joystick/analog inputs below a certain deadzone threshold and cleanly remaps the remaining range from 0 to 1.
	@param value number -- The raw analog value.
	@param threshold number -- The deadzone threshold limit.
	@return number -- The deadzone-adjusted value.
]=]
--
function MathUtil.ApplyDeadzone(value, threshold)
	local absolute_value = math.abs(value)
	if absolute_value < threshold then
		return 0
	end

	return math.sign(value) * ((absolute_value - threshold) / (1 - threshold))
end

--[=[
	Performs a weighted random selection on a table where keys are items and values are weights.
	@param weights_table { [any]: number } -- Dictionary mapping choices to their positive weights.
	@return any? -- The selected key/item, or `nil` if the table is empty or has zero total weight.
]=]
--
function MathUtil.WeightedRandom(weights_table)
	local total_weight = 0
	for _, weight in weights_table do
		total_weight += weight
	end

	local random_value = math.random() * total_weight
	local current_weight = 0

	for item, weight in weights_table do
		current_weight += weight
		if random_value <= current_weight then
			return item
		end
	end

	return nil
end

--[=[
	Generates a random Vector3 position within a 2D radius along the XZ plane.
	@param center_pos Vector3 -- The center origin position.
	@param radius number -- The maximum radius distance.
	@return Vector3 -- The randomized position.
]=]
--
function MathUtil.RandomInRadius(center_pos, radius)
	local theta = math.random() * math.pi * 2
	local randomized_radius = math.sqrt(math.random()) * radius

	local x_offset = randomized_radius * math.cos(theta)
	local z_offset = randomized_radius * math.sin(theta)

	return center_pos + Vector3.new(x_offset, 0, z_offset)
end

return MathUtil
