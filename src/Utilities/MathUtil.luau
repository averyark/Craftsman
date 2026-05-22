--!nonstrict
--[[
    FileName    > MathUtil.luau
    Author      > AveryArk
    Contact     > Twitter: https://twitter.com/averyark_
    Created     > 20/05/2026
--]]

const MathUtil = {}

const SUFFIXES = { "k", "M", "B", "T", "Qd", "Qn" }

const ONES = { "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine" }
const TEENS =
	{ "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen" }
const TENS = { "", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety" }
const SCALES = { "", "thousand", "million", "billion", "trillion", "quadrillion", "quintillion" }

function MathUtil.Map(value, in_min, in_max, out_min, out_max)
	return out_min + (value - in_min) * (out_max - out_min) / (in_max - in_min)
end

function MathUtil.Lerp(a, b, alpha)
	return a + (b - a) * alpha
end

function MathUtil.InverseLerp(a, b, value)
	return (value - a) / (b - a)
end

-- Exponential decay lerp. Frame-rate independent smoothing for cameras, UI, and following logic.
function MathUtil.SmoothLerp(current, target, rate, delta_time)
	return target + (current - target) * math.exp(-rate * delta_time)
end

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
		local frac_str = tostring(number):match("%%.(%d+)$")
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

function MathUtil.FormatTime(total_seconds)
	local minutes = math.floor(total_seconds / 60)
	local seconds = math.floor(total_seconds % 60)

	return string.format("%02d:%02d", minutes, seconds)
end

function MathUtil.RoundTo(value, step)
	return math.floor((value / step) + 0.5) * step
end

function MathUtil.Wrap(value, min, max)
	return min + (value - min) % (max - min)
end

function MathUtil.Direction(origin_pos, target_pos)
	local direction_vector = target_pos - origin_pos
	if direction_vector.Magnitude == 0 then
		return Vector3.zero
	end

	return direction_vector.Unit
end

function MathUtil.Flatten(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

-- Calculates distance between two points ignoring height differences.
function MathUtil.FlatDistance(pos_a, pos_b)
	local dx = pos_a.X - pos_b.X
	local dz = pos_a.Z - pos_b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Returns the angle in radians between two vectors.
function MathUtil.AngleBetween(vec_a, vec_b)
	local dot_product = vec_a:Dot(vec_b)
	local magnitudes = vec_a.Magnitude * vec_b.Magnitude
	if magnitudes == 0 then
		return 0
	end

	return math.acos(math.clamp(dot_product / magnitudes, -1, 1))
end

-- Returns the shortest angular distance between two degrees (-180 to 180). Useful for turrets and hinges.
function MathUtil.ShortestAngle(current_angle, target_angle)
	local difference = (target_angle - current_angle) % 360
	if difference > 180 then
		difference -= 360
	end

	return difference
end

function MathUtil.QuadraticBezier(t, p0, p1, p2)
	local u = 1 - t
	return (u ^ 2) * p0 + 2 * u * t * p1 + (t ^ 2) * p2
end

function MathUtil.CubicBezier(t, p0, p1, p2, p3)
	local u = 1 - t
	return (u ^ 3) * p0 + 3 * (u ^ 2) * t * p1 + 3 * u * (t ^ 2) * p2 + (t ^ 3) * p3
end

-- Zeroes out joystick inputs below a threshold and cleanly remaps the remaining value from 0 to 1.
function MathUtil.ApplyDeadzone(value, threshold)
	local absolute_value = math.abs(value)
	if absolute_value < threshold then
		return 0
	end

	return math.sign(value) * ((absolute_value - threshold) / (1 - threshold))
end

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

function MathUtil.RandomInRadius(center_pos, radius)
	local theta = math.random() * math.pi * 2
	local randomized_radius = math.sqrt(math.random()) * radius

	local x_offset = randomized_radius * math.cos(theta)
	local z_offset = randomized_radius * math.sin(theta)

	return center_pos + Vector3.new(x_offset, 0, z_offset)
end

return MathUtil
