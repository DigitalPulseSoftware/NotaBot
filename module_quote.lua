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
			Default = false
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
				quotedMessage, err = bot:DecodeMessage(message, false)
				if (not quotedMessage) then
					commandMessage:reply(string.format("Invalid message link: %s", err))
					return
				end

				if (config.AutoQuote) then
					-- Autoquote will quote this link automatically, ignore it
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
	local config = self:GetConfig(triggeringMessage.guild)
	local embed = util.BuildQuoteEmbed(message, config.BigAvatar)
	embed.footer = {
		text = string.format("Quoted by %s | in #%s at %s", triggeringMessage.author.tag, message.channel.name, message.guild.name)
	}

	triggeringMessage:reply({
		content = includesLink and "Message link: " .. Bot:GenerateMessageLink(message) or nil,
		embed = embed
	})

	if (deleteInvokation) then
		triggeringMessage:delete()
	end
end

function Module:OnMessageCreate(message)
	if (not bot:IsPublicChannel(message.channel)) then
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
