util = util or {}

local json = require("json")

local timeUnits = {}
local timeUnitByUnit = {}

do
	local minuteSecond = 60
	local hourSecond = 60 * minuteSecond
	local daySecond = 24 * hourSecond
	local weekSecond = 7 * daySecond
	local monthSecond = 30 * daySecond -- Prendre 4 semaines n'aurait fait que 28 jours
	local yearSecond = 365 * daySecond -- Prendre 12 mois n'aurait fait que 360 jours
	local centurySecond = 100 * yearSecond
	local millenniumSecond = 10 * centurySecond

	table.insert(timeUnits, {
		AltNames = {"mi"},
		NameSingular = "millennium",
		NamePlural = "millennia",
		Seconds = millenniumSecond
	})

	table.insert(timeUnits, {
		AltNames = {"c"},
		NameSingular = "century",
		NamePlural = "centuries",
		Seconds = centurySecond
	})

	table.insert(timeUnits, {
		AltNames = {"y"},
		NameSingular = "year",
		NamePlural = "years",
		Seconds = yearSecond
	})

	table.insert(timeUnits, {
		AltNames = {"M"},
		NameSingular = "month",
		NamePlural = "months",
		Seconds = monthSecond
	})

	table.insert(timeUnits, {
		AltNames = {"w"},
		NameSingular = "week",
		NamePlural = "weeks",
		Seconds = weekSecond
	})

	table.insert(timeUnits, {
		AltNames = {"d"},
		NameSingular = "day",
		NamePlural = "days",
		Seconds = daySecond
	})

	table.insert(timeUnits, {
		AltNames = {"h"},
		NameSingular = "hour",
		NamePlural = "hours",
		Seconds = hourSecond
	})

	table.insert(timeUnits, {
		AltNames = {"m", "min"},
		NameSingular = "minute",
		NamePlural = "minutes",
		Seconds = minuteSecond
	})

	table.insert(timeUnits, {
		AltNames = {"s", "sec"},
		NameSingular = "second",
		NamePlural = "seconds",
		Seconds = 1
	})

	-- Processing
	for _, data in pairs(timeUnits) do
		local function registerUnit(unit)
			if (timeUnitByUnit[unit] ~= nil) then
				error("TimeUnit name " .. unit .. " is already registered")
			end

			timeUnitByUnit[unit] = data
		end

		registerUnit(data.NameSingular)
		registerUnit(data.NamePlural)
		for _, name in pairs(data.AltNames) do
			registerUnit(name)
		end
	end
end

function string.ConvertToTime(str)
	local seconds = tonumber(str)
	if (seconds) then
		return seconds
	end

	local isValid = false

	seconds = 0
	for value, timeUnit in string.gmatch(str, "([%d-]+)%s*(%a+)") do
		value = tonumber(value)
		if (not value) then
			return -- Invalid value
		end

		local unit = timeUnitByUnit[timeUnit]
		if (not unit) then
			return -- Invalid unit
		end

		isValid = true
		seconds = seconds + value * unit.Seconds
	end

	if (not isValid) then
		return
	end

	return seconds
end

function string.GetArguments(text, limit)
    local args = {}

    local e = 0
    while true do
        local b = e+1
        b = text:find("%S", b)
        if b == nil then 
            break
        end
        
        if limit and #args >= limit - 1 then
            table.insert(args, text:sub(b))
            break
        end

        local k = false -- should keep delimiter
        local c = text:sub(b, b)
        if c == "`" then
            k = true
            if text:sub(b, b + 2) == "```" then
                e = text:find("```", b + 3)
            else
                e = text:find("`", b + 1)
            end
        elseif c == "'" or c == '"' then
            e = text:find(c, b + 1)
            if e ~= nil then
                b = b+1
            end
        else
            e = text:find("%s", b+1)
        end
        if e == nil then
            e = #text+1
        end

        table.insert(args, text:sub(b, k and e or e - 1))
    end

	return args
end

function string.ToTable(str)
	local tbl = {}

	for i = 1, string.len( str ) do
		tbl[i] = string.sub( str, i, i )
	end

	return tbl
end

local totable = string.ToTable
local string_sub = string.sub
local string_find = string.find
local string_len = string.len
function string.Explode(separator, str, withpattern)
	if ( separator == "" ) then return totable( str ) end
	if ( withpattern == nil ) then withpattern = false end

	local ret = {}
	local current_pos = 1

	for i = 1, string_len( str ) do
		local start_pos, end_pos = string_find( str, separator, current_pos, not withpattern )
		if ( not start_pos ) then break end
		ret[ i ] = string_sub( str, current_pos, start_pos - 1 )
		current_pos = end_pos + 1
	end

	ret[ #ret + 1 ] = string_sub( str, current_pos )

	return ret
end

function string.UpperizeFirst(str)
	return string.upper(str:sub(1,1)) .. str:sub(2)
end

function table.empty(tab)
	for k,v in pairs(tab) do
		return false
	end

	return true
end

function table.NiceConcat(tab)
	if (#tab > 1) then
		return table.concat(tab, ", ", 1, #tab - 1) .. " and " .. tab[#tab]
	elseif (#tab == 1) then
		return tab[1]
	else
		return ""
	end
end

function util.FormatTime(seconds, depth)
	if (type(seconds) ~= "number") then
		return seconds
	end

	local units = timeUnits
	if (seconds < units[#units].Seconds) then
		return "zero " .. units[#units].NameSingular
	end

	depth = depth or 0

	local txt = {}
	for k,v in pairs(units) do
		if (seconds >= v.Seconds) then
			local count = math.floor(seconds/v.Seconds)
			seconds = seconds - count*v.Seconds
			if (count > 1) then
				table.insert(txt, count .. " " .. v.NamePlural)
			else
				table.insert(txt, "one " .. v.NameSingular)
			end

			if (depth > 0) then
				depth = depth - 1
				if (depth < 1) then
					break
				end
			end
		end
	end

	return table.NiceConcat(txt)
end

function util.MemberHasAnyRole(member, roles)
	for _, roleId in pairs(roles) do
		if (member:hasRole(roleId)) then
			return true
		end
	end

	return false
end

function util.MemberHasAllRoles(member, roles)
	if (#roles == 0) then
		return true
	end

	for _, roleId in pairs(roles) do
		if (not member:hasRole(roleId)) then
			return false
		end
	end

	return true
end

function util.ValidateSnowflake(snowflake)
	if (type(snowflake) ~= "string") then
		return false, "not a string"
	end

	if (not string.match(snowflake, "%d+")) then
		return false, "must contain only number"
	end

	return true
end


function table.binsearch( tbl, value, comp )
	local comp = comp or function (a, b)
		if (a == b) then return 0 end
		if (a < b) then return -1 end
		if (a > b) then return 1 end
	end

	local iStart,iEnd,iMid = 1,#tbl,0
	while iStart <= iEnd do
		iMid = math.floor( (iStart+iEnd)/2 )
		local r = comp( value, tbl[iMid] )

		if r == 0 then
			return tbl[iMid], iMid
		elseif r < 0 then
			iEnd = iMid - 1
		else
			iStart = iMid + 1
		end
	end

	return nil, iStart, iEnd
end

function table.length( tbl )
	local count = 0

	for _ in pairs(tbl) do
		count = count + 1
	end
	
	return count
end

local fileTypes = {
	aac = "sound",
	avi = "video",
	apng = "image",
	bmp = "image",
	flac = "video",
	gif = "image",
	ico = "image",
	jpg = "image",
	jpeg = "image",
	ogg = "sound",
	m4a = "sound",
	mkv = "video",
	mov = "video",
	mp1 = "sound",
	mp2 = "sound",
	mp3 = "sound",
	mp4 = "video",
	png = "image",
	tif = "image",
	wav = "sound",
	webm = "video",
	webp = "image",
	wma = "sound",
	wmv = "video"
}

function util.BuildQuoteEmbed(message, bigAvatar)
	local author = message.author
	local content = message.content

	local maxContentSize = 1800

	local decorateEmbed = function(embed)
		-- Replace footer and timestamp
		embed.author = {
			name = author.tag,
			icon_url = author.avatarURL
		}
		embed.thumbnail = bigAvatar and { url = author.avatarURL } or nil
		embed.timestamp = message.timestamp

		return embed
	end

	-- Quoting an embed? Copy it
	if (#content == 0 and (not message.attachments or #message.attachments == 0) and message.embed) then
		return decorateEmbed(message.embed)
	end

	local fields
	local imageUrl 
	if (message.attachments) then
		local images = {}
		local files = {}
		local sounds = {}
		local videos = {}

		-- Sort into differents types
		for _, attachment in pairs(message.attachments) do
			local ext = attachment.url:match("//.-/.+%.(.*)$"):lower()
			local fileType = fileTypes[ext]
			local t = files
			if (fileType) then
				if (fileType == "image") then
					t = images
				elseif (fileType == "sound") then
					t = sounds
				elseif (fileType == "video") then
					t = videos
				end
			end

			table.insert(t, attachment)
		end

		-- Special shortcut for one image attachment
		if (#message.attachments == 1 and #images == 1) then
			imageUrl = images[1].url
		else
			fields = {}
			local function LinkList(title, attachments)
				if (#attachments == 0) then
					return
				end

				local desc = {}
				for _, attachment in pairs(attachments) do
					table.insert(desc, "[" .. attachment.filename .. "](" .. attachment.url .. ")")
				end

				table.insert(fields, {
					name = title,
					value = table.concat(desc, "\n"),
					inline = true
				})
			end

			LinkList("Images 🖼️", images)
			LinkList("Sounds 🎵", sounds)
			LinkList("Videos 🎥", videos)
			LinkList("Files 🖥️", files)

			if (#images > 0) then
				imageUrl = images[1].url
			end
		end
	end

	if (fields) then
		maxContentSize = maxContentSize - #json.encode(fields)
	end

	-- Fix emojis
	content = content:gsub("(<a?:([%w_]+):(%d+)>)", function (mention, emojiName, emojiId)
		-- Bot are allowed to use emojis from every servers they are on
		local emojiData = bot:GetEmojiData(nil, emojiId)

		local canUse = false
		if (emojiData) then
			if (emojiData.Custom) then
				local emoji = emojiData.Emoji
				local guild = emojiData.FromGuild

				-- Check if bot has permissions to use this emoji (on the guild it comes from)
				local botMember = guild:getMember(client.user) -- Should never make a HTTP request
				local found = true
				for _, role in pairs(emoji.roles) do
					found = false -- Set false if we enter the loop

					if (botMember:hasRole(role)) then
						found = true
						break
					end
				end

				canUse = found
			else
				canUse = true
			end
		else
			canUse = false
		end

		if (canUse) then
			return mention
		else
			return ":" .. emojiName .. ":"
		end			
	end)

	if (#content > maxContentSize) then
		content = content:sub(1, maxContentSize) .. "... <truncated>"
	end

	-- TODO: support multiple stickers (up to 3 per message), even if there's already an attached image?
	-- A sticker can be a (1) PNG, (2) APNG or (3) LOTTIE (JSON), if it's a LOTTIE, don't attach it
	-- https://discord.com/developers/docs/resources/sticker#sticker-object-sticker-format-types
	if (not imageUrl and message._stickers and message._stickers[1].format_type ~= 3) then
		imageUrl = "https://media.discordapp.net/stickers/" .. message._stickers[1].id .. ".png?size=128"
	end

	return decorateEmbed({
		image = imageUrl and { url = imageUrl } or nil,
		description = content,
		fields = fields
	})
end
