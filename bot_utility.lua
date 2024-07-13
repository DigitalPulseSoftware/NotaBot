-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local discordia = require('discordia')
local enums = discordia.enums
local fs = require("coro-fs")
local json = require("json")
local path = require("path")

local discordDomains = {
	-- no subdomain
	["discord.com"] = true,
	["discordapp.com"] = true,
	-- public test build
	["ptb.discord.com"] = true,
	["ptb.discordapp.com"] = true,
	-- canary
	["canary.discord.com"] = true,
	["canary.discordapp.com"] = true,
}

function Bot:DecodeChannel(guild, message)
	assert(guild)
	assert(message)

	local channelId = message:match("<#(%d+)>")
	if (not channelId) then
		channelId = message:match("^(%d+)$")
		if (not channelId) then
			return nil, "Invalid channelId id"
		end
	end

	local channel = guild:getChannel(channelId)
	if (not channel) then
		return nil, "This channel is not part of this guild"
	end

	return channel
end

function Bot:DecodeEmoji(guild, message)
	assert(guild)
	assert(message)

	local emojiId = message:match("<a?:[%w_]+:(%d+)>")
	if (emojiId) then
		-- Custom emoji
		local emoji = self:GetEmojiData(guild, emojiId)
		if (not emoji) then
			return nil, "Failed to get emoji, maybe this is a global emoji?"
		end

		return emoji
	else
		-- Discord emoji
		local emoji = self:GetEmojiData(guild, message)
		if (not emoji) then
			return nil, "Invalid emoji"
		end

		return emoji
	end
end

function Bot:DecodeMember(guild, message)
	assert(guild)
	assert(message)

	local userId = message:match("<@!?(%d+)>")
	if (not userId) then
		userId = message:match("^(%d+)$")
		if (not userId) then
			return nil, "Invalid user id"
		end
	end

	local member = guild:getMember(userId)
	if (not member) then
		return nil, "This user is not part of this guild"
	end

	return member
end

function Bot:DecodeMessage(messageContent, ignoreEscaped, fullContent)
	assert(messageContent)

	local pattern = "(<?)https?://([%w%.]+)/channels/(%d+)/(%d+)/(%d+)(>?)"
	if (fullContent) then
		pattern = "^" .. pattern .. "$"
	end

	local e1, domain, guildId, channelId, messageId, e2 = messageContent:match(pattern)
	if (not e1 or not discordDomains[domain]) then
		return nil, "Invalid link"
	end

	if (ignoreEscaped and e1 == "<" and e2 == ">") then
		return nil, "Escaped link"
	end

	local guild = self.Client:getGuild(guildId)
	if (not guild) then
		return nil, "Unavailable guild"
	end

	local channel = guild:getChannel(channelId)
	if (not channel) then
		return nil, "Unavailable channel"
	end

	local message = channel:getMessage(messageId)
	if (not message) then
		return nil, "Message not found"
	end

	return message
end

function Bot:DecodeRole(guild, message)
	assert(guild)
	assert(message)

	local roleId = message:match("<@&(%d+)>")
	if (not roleId) then
		roleId = message:match("^(%d+)$")
		if (not roleId) then
			return nil, "Invalid role"
		end
	end

	local role = guild:getRole(roleId)
	if (not role) then
		return nil, "This role is not part of this guild"
	end

	return role
end

function Bot:DecodeUser(message)
	assert(message)

	local userId = message:match("<@!?(%d+)>")
	if (not userId) then
		userId = message:match("^(%d+)$")
		if (not userId) then
			return nil, "Invalid user id"
		end
	end

	local user = self.Client:getUser(userId)
	if (not user) then
		return nil, "Invalid user (maybe this account was deleted?)"
	end

	return user
end

function Bot:GenerateMessageLink(message)
	local guildId = message.guild and message.guild.id or "@me"
	return string.format("https://discord.com/channels/%s/%s/%s", guildId, message.channel.id, message.id)
end

local publicChannels = {
	[enums.channelType.text] = true,
	[enums.channelType.voice] = true,
	[enums.channelType.news] = true,
	[enums.channelType.public_thread] = true,
	[enums.channelType.news_thread] = true
}

function Bot:IsPublicChannel(channel)
	return publicChannels[channel.type]
end

local ehandler = function(err)
	return debug.traceback(tostring(err))
end

function Bot:ProtectedCall(context, func, ...)
	local success, a, b, c, d, e, f = xpcall(func, ehandler, ...)
	if (not success) then
		local err = string.format("%s failed: %s", context, a)
		self.Client:warning(err)
		return false, err
	end

	return success, a, b, c, d, e, f
end

-- Serialization/unserialization
function Bot:SerializeToFile(filepath, data, pretty)
	local dirname = path.dirname(filepath)
	if (dirname ~= ".") then
		local success, err = fs.mkdirp(dirname)
		if (not success) then
			return false, string.format("Failed to create directory %s: %s", filepath, err)
		end
	end

	local outputFile, err = io.open(filepath, "w+")
	if (not outputFile) then
		return false, string.format("Failed to open %s: %s", filepath, err)
	end

	local encoderState = {}
	if (pretty) then
		encoderState.indent = true
	end

	local success, serializedDataOrErr = pcall(json.encode, data, encoderState)
	if (not success) then
		return false, string.format("Failed to serialize data: %s", serializedDataOrErr)
	end

	local success, err = outputFile:write(serializedDataOrErr)
	if (not success) then
		return false, string.format("Failed to write data to file %s: %s", filepath, err)
	end

	outputFile:close()
	return true
end

function Bot:UnserializeFromFile(filepath)
	local saveFile, err = io.open(filepath, "r")
	if (not saveFile) then
		return nil, string.format("Failed to open %s: %s", filepath, err)
	end

	local content, err = saveFile:read("*a")
	if (not content) then
		return nil, string.format("Failed to read %s content: %s", filepath, err)
	end
	saveFile:close()

	local success, contentOrErr = pcall(json.decode, content)
	if (not success) then
		return nil, string.format("Failed to unserialize %s content: %s", filepath, contentOrErr)
	end

	return contentOrErr
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

function Bot:BuildQuoteEmbed(message, opt)
	local author = message.author
	local content = message.content

	local maxContentSize = 1800 - (opt and opt.initialContentSize or 0)

	local decorateEmbed = function(embed)
		-- Replace footer and timestamp
		embed.author = {
			name = author.tag,
			icon_url = author.avatarURL
		}
		embed.thumbnail = opt and opt.bigAvatar and { url = author.avatarURL } or nil
		embed.timestamp = message.timestamp

		return embed
	end

	-- Quoting an embed? Copy it
	if (#content == 0 and (not message.attachments or #message.attachments == 0) and message.embed) then
		return decorateEmbed(message.embed)
	end

	local fields
	local imageUrl

	local applyImages = function (imgs)
		local images = {}
		local files = {}
		local sounds = {}
		local videos = {}
		for _, image in pairs(imgs) do
			local matchedExt = image.url:match("//.-/.+%.(.-)[?].*$") or image.url:match("//.-/.+%.(.*)$") or ""
			-- Edge case for embed images with no extensions
			local ext = (#matchedExt == 0 and image.thumbnail and "png" or matchedExt):lower()
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

			table.insert(t, image)
		end

		-- Special shortcut for one image attachment
		if (#imgs == 1 and #images == 1) then
			imageUrl = images[1].url
		else
			-- Should only happens for attachments, not embeds
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

	if (message.attachments) then
		applyImages(message.attachments)
	end

	if (message.embeds and not message.attachments) then
		applyImages(message.embeds)
	end

	if (fields) then
		maxContentSize = maxContentSize - #json.encode(fields)
	end

	-- Fix emojis
	content = content:gsub("(<a?:([%w_]+):(%d+)>)", function(mention, emojiName, emojiId)
		-- Bot are allowed to use emojis from every servers they are on
		local emojiData = Bot:GetEmojiData(nil, emojiId)

		local canUse = false
		if (emojiData) then
			if (emojiData.Custom) then
				local emoji = emojiData.Emoji
				local guild = emojiData.FromGuild

				-- Check if bot has permissions to use this emoji (on the guild it comes from)
				local botMember = guild:getMember(Client.user) -- Should never make a HTTP request
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

function Bot:FetchChannelMessages(channel, nextId, limit, fromEnd)
	limit = limit or 1000
	fromEnd = fromEnd or false

	local seenMessages = {}
	local channelMessages = {}
	while limit > 0 do
		local requestLimit = math.min(limit, 100)
		local messages, err
		if fromEnd then
			messages, err = channel:getMessagesBefore(nextId, requestLimit)
		else
			messages, err = channel:getMessagesAfter(nextId or channel.id, requestLimit)
		end

		if not messages then
			return nil, err
		end

		if fromEnd then
			for message in messages:iter() do
				local messageId = message.id
				if not seenMessages[messageId] then
					seenMessages[messageId] = true
					table.insert(channelMessages, message)

					if not nextId or messageId < nextId then
						nextId = messageId
					end
				end
			end
		else
			for message in messages:iter() do
				local messageId = message.id
				if not seenMessages[messageId] then
					seenMessages[messageId] = true
					table.insert(channelMessages, message)

					if not nextId or messageId > nextId then
						nextId = messageId
					end
				end
			end
		end

		if #messages < requestLimit then
			break
		end

		limit = limit - #messages
	end

	table.sort(channelMessages, function(a, b)
		return a.id < b.id
	end)

	return channelMessages
end

function Bot:MessagesToTable(messages)
	local authors = {}
	local messageData = {}

	for _, message in ipairs(messages) do
		local author = message.member or message.author
		if not authors[author.id] then
			authors[author.id] = {
				-- User fields
				accentColor = author.accentColor and discordia.Color(author.accentColor):toHex() or nil,
				avatar = author.avatar,
				avatarURL = author.avatarURL,
				banner = author.banner,
				bot = author.bot,
				createdAt = author.timestamp,
				discriminator = author.discriminator,
				flags = author.publicFlags,
				premiumType = author.premiumType,
				system = author.system,
				username = author.username,

				-- Member fields
				color = (author.getColor and author:getColor() or discordia.Color()):toHex(),
				joinedAt = author.joinedAt,
				nickname = author.nickname,
				premiumSince = author.premiumSince
			}
		end

		local fields = {
			attachments = message.attachments,
			author = message.author and message.author.id or nil,
			content = #message.content > 0 and message.content or nil,
			createdAt = message.timestamp,
			embed = message.embed,
			components = message.components,
			interaction = message.interaction,
			components = message.components,
			tts = message.tts or nil
		}

		local embed = message.embed
		if (embed) then
			embed.type = nil
			local author = embed.author
			if (author) then
				author.proxy_icon_url = nil
			end
		end

		table.insert(messageData, fields)
	end

	return {
		authors = authors,
		messages = messageData
	}
end
