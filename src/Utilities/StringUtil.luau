const StringUtil = {}

const ALPHANUMERIC_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
const RICH_TEXT_ESCAPES = {
	["&"] = "&amp;",
	["<"] = "&lt;",
	[">"] = "&gt;",
	["\""] = "&quot;",
	["'"] = "&apos;",
}

function StringUtil.StartsWith(text, prefix)
	return string.sub(text, 1, #prefix) == prefix
end

function StringUtil.EndsWith(text, suffix)
	return suffix == "" or string.sub(text, -#suffix) == suffix
end

function StringUtil.IsWhitespace(text)
	return string.match(text, "^%s*$") ~= nil
end

-- Faster and safer than string.match or string.find without the 'true' plain flag
function StringUtil.Contains(text, substring)
	return string.find(text, substring, 1, true) ~= nil
end

function StringUtil.Trim(text)
	return string.match(text, "^%s*(.-)%s*$")
end

-- Strips all spaces entirely, useful for sanitizing player input or network keys
function StringUtil.RemoveWhitespace(text)
	return string.gsub(text, "%s+", "")
end

function StringUtil.ToTitleCase(text)
	return string.gsub(text, "(%w)(%w*)", function(first_letter, rest_of_word)
		return string.upper(first_letter) .. string.lower(rest_of_word)
	end)
end

-- Converts "Hello World" or "Hello-World" into "hello_world"
function StringUtil.ToSnakeCase(text)
	local replaced_spaces = string.gsub(text, "[%s%-]+", "_")
	return string.lower(replaced_spaces)
end

function StringUtil.PadStart(text, target_length, pad_character)
	local current_length = #text
	if current_length >= target_length then
		return text
	end

	local padding = string.rep(pad_character or " ", target_length - current_length)
	return padding .. text
end

function StringUtil.PadEnd(text, target_length, pad_character)
	local current_length = #text
	if current_length >= target_length then
		return text
	end

	local padding = string.rep(pad_character or " ", target_length - current_length)
	return text .. padding
end

-- Safely cuts off text for UI and appends an ellipsis without exceeding max bounds
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

-- Automatically appends an 's' or custom suffix if count is not 1 (e.g., Pluralize("Coin", 2) -> "Coins")
function StringUtil.Pluralize(text, count, custom_suffix)
	if count == 1 then
		return text
	end
	return text .. (custom_suffix or "s")
end

function StringUtil.EscapeRichText(text)
	return string.gsub(text, "[&<>\"']", RICH_TEXT_ESCAPES)
end

function StringUtil.StripRichText(text)
	return string.gsub(text, "<[^>]+>", "")
end

-- Swaps bracketed keys with dictionary values. Ex: FormatTemplate("Score: {score}", { score = 50 }) -> "Score: 50"
function StringUtil.FormatTemplate(template, dictionary)
	return string.gsub(template, "{(.-)}", function(key)
		local value = dictionary[key]
		if value == nil then
			return "{" .. key .. "}"
		end
		return tostring(value)
	end)
end

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
