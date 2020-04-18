-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local client = Client
local discordia = Discordia
local bot = Bot
local enums = discordia.enums

Module.Name = "quote"

function Module:GetConfigTable()
	return {
		{
			Name = "AutoQuote",
			Description = "Should quote messages when an user posts a message link (when not using quote command)",
			Type = bot.ConfigType.Boolean,
			Default = true
		}
	}
end

function Module:OnLoaded()
	self:RegisterCommand({
		Name = "quote",
		Args = {
			{Name = "message", Type = bot.ConfigType.String}
		},

		Help = "Quote message",
		Func = function (commandMessage, message)
			local messageId = message:match("^(%d+)$")
			local quotedMessage, err
			local includesLink = false
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

			self:QuoteMessage(commandMessage, quotedMessage, includesLink)
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

function Module:QuoteMessage(triggeringMessage, message, includesLink)
	local author = message.author
	local content = message.content
	if (#content > 1800) then
		content = content:sub(1, 1800) .. "... <truncated>"
	end

	triggeringMessage:reply({
		content = includesLink and "Message link: " .. Bot:GenerateMessageLink(message) or nil,
		embed = {
			author = {
				name = author.tag,
				icon_url = author.avatarURL
			},
			thumbnail = {
				url = author.avatarURL
			},
			description = content,
			footer = {
				text = string.format("Quoted by %s | in #%s at %s", triggeringMessage.author.tag, message.channel.name, message.guild.name)
			},
			timestamp = message.timestamp
		}
	})
end

function Module:OnMessageCreate(message)
	if (message.channel.type ~= enums.channelType.text) then
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

			self:QuoteMessage(message, quotedMessage)
		end
	end
end
