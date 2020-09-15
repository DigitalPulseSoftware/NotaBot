-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local client = Client
local discordia = Discordia
local bot = Bot
local enums = discordia.enums

local json = require("json")

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

Module.Name = "quote"

function Module:GetConfigTable()
	return {
		{
			Name = "AutoQuote",
			Description = "Should quote messages when an user posts a message link (when not using quote command)",
			Type = bot.ConfigType.Boolean,
			Default = true
		},
		{
			Name = "BigAvatar",
			Description = "Should quote messages include big avatars",
			Type = bot.ConfigType.Boolean,
			Default = true
		},
		{
			Name = "DeleteInvokationOnAutoQuote",
			Description = "Deletes the message that invoked the quote when auto-quoting",
			Type = bot.ConfigType.Boolean,
			Default = false
		},
		{
			Name = "DeleteInvokationOnManualQuote",
			Description = "Deletes the message that invoked the quote when quoting via command",
			Type = bot.ConfigType.Boolean,
			Default = false
		}
	}
end

function Module:OnLoaded()
	self:RegisterCommand({
		Name = "quote",
		Args = {
			{
				Name = "message", Type = bot.ConfigType.String
			},
			{
				Name = "deleteInvokation",
				Type = bot.ConfigType.Boolean,
				Optional = true
			}
		},

		Help = "Quote message",
		Func = function (commandMessage, message, deleteInvokation)
			local messageId = message:match("^(%d+)$")
			local quotedMessage, err
			local includesLink = false
			local config = self:GetConfig(commandMessage.guild)

			if (messageId) then
				quotedMessage = commandMessage.channel:getMessage(messageId)
				if (not quotedMessage) then
					commandMessage:reply("Message not found in this channel")
					return
				end

				includesLink = true
			else
				quotedMessage, err = bot:DecodeMessage(message)
				if (not quotedMessage) then
					commandMessage:reply(string.format("Invalid message link: %s", err))
					return
				end

				-- Checks if user has permission to see this message
				if (not self:CheckReadPermission(commandMessage.author, quotedMessage)) then
					commandMessage:reply("You can only quote messages you are able to see yourself")
					return
				end
			end

			-- Only delete the message that invoked the quote if no argument to the command is passed
			-- and auto deletion is set true, or if command argument is specifically set to true
			local shouldDeleteInvokation = deleteInvokation == nil and config.DeleteInvokationOnManualQuote or deleteInvokation

			self:QuoteMessage(commandMessage, quotedMessage, includesLink, shouldDeleteInvokation)
		end
	})

	return true
end

function Module:CheckReadPermission(user, message)
	local quotedGuild = message.guild
	local member = quotedGuild:getMember(user.id)
	if (not member) then
		return false
	end

	if (not member:hasPermission(message.channel, enums.permission.readMessages)) then
		return false
	end

	return true
end

function Module:QuoteMessage(triggeringMessage, message, includesLink, deleteInvokation)
	local author = message.author
	local content = message.content

	local config = self:GetConfig(triggeringMessage.guild)

	local thumbnail = config.BigAvatar and author.avatarURL or nil
	local imageUrl = nil

	local maxContentSize = 1800

	local decorateEmbed = function(embed)
		-- Replace footer and timestamp
		embed.author = {
			name = author.tag,
			icon_url = author.avatarURL
		}
		embed.thumbnail = thumbnail and { url = thumbnail } or nil
		embed.footer = {
			text = string.format("Quoted by %s | in #%s at %s", triggeringMessage.author.tag, message.channel.name, message.guild.name)
		}
		embed.timestamp = message.timestamp

		return embed
	end

	-- Quoting an embed? Copy it
	if (#content == 0 and (not message.attachments or #message.attachments == 0) and message.embed) then
		triggeringMessage:reply({
			content = includesLink and "Message link: " .. Bot:GenerateMessageLink(message) or nil,
			embed = decorateEmbed(message.embed)
		})
		return
	end

	local fields
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
	local guild = triggeringMessage.guild
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

	triggeringMessage:reply({
		content = includesLink and "Message link: " .. Bot:GenerateMessageLink(message) or nil,
		embed = decorateEmbed({
			image = imageUrl and { url = imageUrl } or nil,
			description = content,
			fields = fields
		})
	})

	if (deleteInvokation) then
		triggeringMessage:delete()
	end
end

function Module:OnMessageCreate(message)
	if (not self:IsPublicChannel(message.channel)) then
		return
	end

	if (message.author.bot) then
		return
	end

	local config = self:GetConfig(message.guild)
	if (config.AutoQuote) then
		local quotedMessage = bot:DecodeMessage(message.content, true)
		if (quotedMessage) then
			if (not self:CheckReadPermission(message.author, quotedMessage)) then
				return
			end

			self:QuoteMessage(message, quotedMessage, false, config.DeleteInvokationOnAutoQuote)
		end
	end
end
