--!nonstrict
--[=[
	@class StringUtil
	A utility library containing common string manipulation and formatting operations.
]=]
--
const StringUtil = {}

const ALPHANUMERIC_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
const RICH_TEXT_ESCAPES = {
	["&"] = "&amp;",
	["<"] = "&lt;",
	[">"] = "&gt;",
	["\""] = "&quot;",
	["'"] = "&apos;",
}

--[=[
	Checks if a string starts with a given prefix.
	@param text string -- The full string to check.
	@param prefix string -- The prefix to check for.
	@return boolean -- `true` if the text starts with the prefix, `false` otherwise.
]=]
--
function StringUtil.StartsWith(text, prefix)
	return string.sub(text, 1, #prefix) == prefix
end

--[=[
	Checks if a string ends with a given suffix.
	@param text string -- The full string to check.
	@param suffix string -- The suffix to check for.
	@return boolean -- `true` if the text ends with the suffix, `false` otherwise.
]=]
--
function StringUtil.EndsWith(text, suffix)
	return suffix == "" or string.sub(text, -#suffix) == suffix
end

--[=[
	Checks if a string consists entirely of whitespace characters.
	@param text string -- The string to check.
	@return boolean -- `true` if the text is empty or contains only whitespace, `false` otherwise.
]=]
--
function StringUtil.IsWhitespace(text)
	return string.match(text, "^%s*$") ~= nil
end

--[=[
	Checks if a string contains a specified substring (plain search).
	Faster and safer than string.match or string.find without the 'true' plain flag.
	@param text string -- The full string to search within.
	@param substring string -- The substring to search for.
	@return boolean -- `true` if the substring is found, `false` otherwise.
]=]
--
function StringUtil.Contains(text, substring)
	return string.find(text, substring, 1, true) ~= nil
end

--[=[
	Strips leading and trailing whitespace from a string.
	@param text string -- The string to trim.
	@return string -- The trimmed string.
]=]
--
function StringUtil.Trim(text)
	return string.match(text, "^%s*(.-)%s*$")
end

--[=[
	Strips all whitespace characters from a string entirely.
	Useful for sanitizing player input or network keys.
	@param text string -- The string to clean.
	@return string -- The string with all spaces removed.
]=]
--
function StringUtil.RemoveWhitespace(text)
	return string.gsub(text, "%s+", "")
end

--[=[
	Converts a string to Title Case (e.g., "hello world" -> "Hello World").
	@param text string -- The string to convert.
	@return string -- The title-cased string.
]=]
--
function StringUtil.ToTitleCase(text)
	return string.gsub(text, "(%w)(%w*)", function(first_letter, rest_of_word)
		return string.upper(first_letter) .. string.lower(rest_of_word)
	end)
end

--[=[
	Converts a string to Snake Case (e.g., "Hello World" or "Hello-World" -> "hello_world").
	@param text string -- The string to convert.
	@return string -- The snake-cased string.
]=]
--
function StringUtil.ToSnakeCase(text)
	local replaced_spaces = string.gsub(text, "[%s%-]+", "_")
	return string.lower(replaced_spaces)
end

--[=[
	Pads the start of a string with a specified character until it reaches the target length.
	@param text string -- The string to pad.
	@param target_length number -- The desired length of the resulting string.
	@param pad_character string? -- The character to pad with (defaults to " ").
	@return string -- The padded string.
]=]
--
function StringUtil.PadStart(text, target_length, pad_character)
	local current_length = #text
	if current_length >= target_length then
		return text
	end

	local padding = string.rep(pad_character or " ", target_length - current_length)
	return padding .. text
end

--[=[
	Pads the end of a string with a specified character until it reaches the target length.
	@param text string -- The string to pad.
	@param target_length number -- The desired length of the resulting string.
	@param pad_character string? -- The character to pad with (defaults to " ").
	@return string -- The padded string.
]=]
--
function StringUtil.PadEnd(text, target_length, pad_character)
	local current_length = #text
	if current_length >= target_length then
		return text
	end

	local padding = string.rep(pad_character or " ", target_length - current_length)
	return text .. padding
end

--[=[
	Safely cuts off text for UI and appends an ellipsis without exceeding max bounds.
	@param text string -- The string to truncate.
	@param max_length number -- The maximum length of the resulting string, including the suffix.
	@param suffix string? -- The suffix to append if truncated (defaults to "...").
	@return string -- The truncated string.
]=]
--
function StringUtil.Truncate(text, max_length, suffix)
	if #text <= max_length then
		return text
	end

	local append_string = suffix or "..."
	local cut_length = max_length - #append_string

	if cut_length <= 0 then
		return append_string
	end
	return string.sub(text, 1, cut_length) .. append_string
end

--[=[
	Automatically appends an 's' or custom suffix if the count is not 1.
	For example: `Pluralize("Coin", 2) -> "Coins"`.
	@param text string -- The singular form of the word.
	@param count number -- The quantity to check.
	@param custom_suffix string? -- Optional custom plural suffix (defaults to "s").
	@return string -- The singular or plural form of the word based on count.
]=]
--
function StringUtil.Pluralize(text, count, custom_suffix)
	if count == 1 then
		return text
	end
	return text .. (custom_suffix or "s")
end

--[=[
	Formats a numeric value as a decimal string with a specified number of decimal places.
	@param value number -- The number to format.
	@param decimal_places number? -- The number of decimal places (defaults to 2).
	@return string -- The formatted decimal string.
]=]
--
function StringUtil.FormatDecimal(value: number, decimal_places: number?): string
	local precision = decimal_places or 2
	local multiplier = 10 ^ precision
	local sign = value < 0 and "-" or ""
	local scaled = math.floor(math.abs(value) * multiplier + 0.5)
	local integer_part = math.floor(scaled / multiplier)

	if precision <= 0 then
		return `{sign}{integer_part}`
	end

	local fraction_text = tostring(scaled - integer_part * multiplier)
	local padding = string.rep("0", precision - #fraction_text)

	return `{sign}{integer_part}.{padding}{fraction_text}`
end

--[=[
	Escapes special characters in a string to make it safe for Roblox RichText tags.
	@param text string -- The raw string.
	@return string -- The escaped RichText-safe string.
]=]
--
function StringUtil.EscapeRichText(text)
	return string.gsub(text, "[&<>\"']", RICH_TEXT_ESCAPES)
end

--[=[
	Strips all HTML/XML-like RichText tags from a string.
	@param text string -- The string containing RichText.
	@return string -- The plain text with tags removed.
]=]
--
function StringUtil.StripRichText(text)
	return string.gsub(text, "<[^>]+>", "")
end

--[=[
	Replaces bracketed template placeholders with values from a dictionary.
	For example: `FormatTemplate("Score: {score}", { score = 50 }) -> "Score: 50"`.
	@param template string -- The template string containing placeholders like `{key}`.
	@param dictionary { [string]: any } -- The lookup table of values.
	@return string -- The formatted string.
]=]
--
function StringUtil.FormatTemplate(template, dictionary)
	return string.gsub(template, "{(.-)}", function(key)
		local value = dictionary[key]
		if value == nil then
			return "{" .. key .. "}"
		end
		return tostring(value)
	end)
end

--[=[
	Generates a random alphanumeric string of the specified length.
	@param length number -- The length of the string to generate.
	@return string -- The randomly generated string.
]=]
--
function StringUtil.Random(length)
	local result_chars = {}
	local chars_length = #ALPHANUMERIC_CHARS

	for _ = 1, length do
		local random_index = math.random(1, chars_length)
		table.insert(result_chars, string.sub(ALPHANUMERIC_CHARS, random_index, random_index))
	end

	return table.concat(result_chars)
end

return StringUtil
