-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local client = Client
local discordia = Discordia
local bot = Bot
local enums = discordia.enums
local bit = require("bit")

Module.Name = "pin"

function Module:GetConfigTable()
	return {
		{
			Name = "Trigger",
			Description = "Triggering emoji",
			Type = bot.ConfigType.Emoji,
			Default = "pushpin"
		},
		{
			Array = true,
			Name = "DisabledChannels",
			Description = "Channels where emoji pin is disabled",
			Type = bot.ConfigType.Channel,
			Default = {}
		},
		{
			Name = "PinThreshold",
			Description = "How many pin emoji are required to pin a message",
			Type = bot.ConfigType.Integer,
			Default = 10
		},
		{
			Name = "AlertChannel",
			Description = "Channel where a message will be posted (if set) once a message is auto-pinned",
			Type = bot.ConfigType.Channel,
			Optional = true
		}
	}
end

function Module:HandleEmojiAdd(config, reaction)
	if (reaction.count >= config.PinThreshold) then
		local message = reaction.message
		if (not message.pinned) then
			if (not message:pin()) then
				self:LogError(message.guild, "Failed to pin message %s in channel %s", message.id, message.channel.id)
				return
			end

			if (config.AlertChannel) then
				local alertChannel = message.guild:getChannel(config.AlertChannel)
				if (not alertChannel) then
					self:LogWarning(message.guild, "Invalid alert channel")
					return
				end

				local author = message.author
				local content = message.content
				if (#content > 1800) then
					content = content:sub(1, 1800) .. "... <truncated>"
				end

				alertChannel:send({
					content = string.format("A message has been auto-pinned in %s:\n%s", message.channel.mentionString, Bot:GenerateMessageLink(message)),
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
							text = string.format("in #%s at %s", message.channel.name, message.guild.name)
						},
						timestamp = message.timestamp
					}
				})
			end
		end
	end
end

function Module:OnReactionAdd(reaction, userId)
	local channel = reaction.message.channel
	if (not bot:IsPublicChannel(channel)) then
		return
	end

	local guild = reaction.message.guild
	local config = self:GetConfig(guild)
	local emojiData = bot:GetEmojiData(guild, reaction.emojiId or reaction.emojiName)
	if (not emojiData) then
		return
	end

	if (emojiData.Name ~= config.Trigger or (emojiData.Custom and emojiData.FromGuild ~= guild)) then
		return
	end

	for _, disabledChannelId in pairs(config.DisabledChannels) do
		if (channel.id == disabledChannelId) then
			return
		end
	end

	self:HandleEmojiAdd(config, reaction)
end

function Module:OnReactionAddUncached(channel, messageId, reactionIdorName, userId)
	if (not bot:IsPublicChannel(channel)) then
		return
	end

	local guild = channel.guild
	local config = self:GetConfig(guild)
	local emojiData = bot:GetEmojiData(guild, reactionIdorName)
	if (not emojiData) then
		return
	end

	if (emojiData.Name ~= config.Trigger or (emojiData.Custom and emojiData.FromGuild ~= guild)) then
		return
	end

	for _, disabledChannelId in pairs(config.DisabledChannels) do
		if (channel.id == disabledChannelId) then
			return
		end
	end

	local message = channel:getMessage(messageId)
	if (not message) then
		return -- Maybe message has been deleted
	end

	local reaction = message.reactions:get(reactionIdorName)
	if (not reaction) then
		return -- Maybe reaction has been removed
	end

	self:HandleEmojiAdd(config, reaction)
end

function Module:OnLoaded()
	self:RegisterCommand({
		Name = "pin",
		Args = {
			{ Name = "<messageId>", Type = bot.ConfigType.Message },
		},

		Help = function (guild) return Bot:Format(guild, "PIN_PIN_HELP") end,
		Silent = true,
		Func = function (commandMessage, targetMessage)
			local guild = commandMessage.guild
			local sender = commandMessage.member
			local senderId = sender.id
			local channelOwnerId = commandMessage.channel._owner_id

			if (sender:hasPermission(enums.permission.manageMessages) or senderId == channelOwnerId) then
				local res = targetMessage:pin()
				if not res then
					commandMessage:reply(Bot:Format(guild, "PIN_PIN_ERROR"))
				end
			end
		end
	})

	self:RegisterCommand({
		Name = "unpin",
		Args = {
			{ Name = "<messageId>", Type = bot.ConfigType.Message },
		},

		Help = function (guild) return Bot:Format(guild, "PIN_UNPIN_HELP") end,
		Silent = true,
		Func = function (commandMessage, targetMessage)
			local sender = commandMessage.member
			local senderId = sender.id
			local channelOwnerId = commandMessage.channel._owner_id

			if (sender:hasPermission(enums.permission.manageMessages) or senderId == channelOwnerId) then
				local res = targetMessage:unpin()
				if not res then
					commandMessage:reply(Bot:Format(guild, "PIN_UNPIN_ERROR"))
				end
			end
		end
	})

	return true
end
