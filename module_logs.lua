-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local client = Client
local discordia = Discordia
local bot = Bot
local enums = discordia.enums

Module.Name = "logs"

function Module:GetConfigTable()
	return {
		{
			Name = "ChannelManagementLogChannel",
			Description = "Where channel created/updated/deleted should be logged",
			Type = bot.ConfigType.Channel,
			Optional = true
		},
		{
			Name = "DeletedMessageChannel",
			Description = "Where deleted messages should be logged",
			Type = bot.ConfigType.Channel,
			Optional = true
		},
		{
			Name = "NicknameChangedLogChannel",
			Description = "Where nickname changes should be logged",
			Type = bot.ConfigType.Channel,
			Optional = true
		},
		{
			Name = "IgnoredDeletedMessageChannels",
			Description = "Messages deleted in those channels will not be logged",
			Type = bot.ConfigType.Channel,
			Array = true,
			Default = {}
		},
		{
			Global = true,
			Name = "PersistentMessageCacheSize",
			Description = "How many of the last messages of every text channel should stay in bot memory?",
			Type = bot.ConfigType.Integer,
			Default = 50
		},
	}
end

function Module:OnEnable(guild)
	local data = self:GetData(guild)

	-- Keep a reference to the last X messages of every text channel
	local messageCacheSize = self.GlobalConfig.PersistentMessageCacheSize
	data.cachedMessages = {}

	data.nicknames = {}
	for userId, user in pairs(guild.members) do
		data.nicknames[userId] = user.nickname
	end
	data.usernames = {}
	for userId, user in pairs(guild.members) do
		data.usernames[userId] = user._user._username
	end

	coroutine.wrap(function ()
		for _, channel in pairs(guild.textChannels) do
			data.cachedMessages[channel.id] = Bot:FetchChannelMessages(channel, nil, messageCacheSize, true)
		end
	end)()

	return true
end

function Module:OnChannelDelete(channel)
	local guild = channel.guild
	if not guild then
		return
	end

	local data = self:GetData(guild)
	data.cachedMessages[channel.id] = nil

	local config = self:GetConfig(guild)
	local channelManagementLogChannel = config.ChannelManagementLogChannel
	if not channelManagementLogChannel then
		return
	end

	local logChannel = guild:getChannel(channelManagementLogChannel)
	if not logChannel then
		self:LogWarning(guild, "Channel management log channel %s no longer exists", channelManagementLogChannel)
		return
	end

	logChannel:send({
		embed = {
			title = "Channel deleted",
			description = channel.name,
			timestamp = discordia.Date():toISO('T', 'Z')
		}
	})
end

function Module:OnChannelCreate(channel)
	local guild = channel.guild
	if not guild then
		return
	end

	local config = self:GetConfig(guild)
	local channelManagementLogChannel = config.ChannelManagementLogChannel
	if not channelManagementLogChannel then
		return
	end

	local logChannel = guild:getChannel(channelManagementLogChannel)
	if not logChannel then
		self:LogWarning(guild, "Channel management log channel %s no longer exists", channelManagementLogChannel)
		return
	end

	logChannel:send({
		embed = {
			title = "Channel created",
			description = "<#" .. channel.id .. ">",
			timestamp = discordia.Date():toISO('T', 'Z')
		}
	})
end

function Module:OnMemberUpdate(member)
	local guild = member.guild
	if not guild then
		return
	end

	local config = self:GetConfig(guild)
	local nicknameChangeLogChannel = config.NicknameChangedLogChannel
	if not nicknameChangeLogChannel then
		return
	end

	local logChannel = guild:getChannel(nicknameChangeLogChannel)
	if not logChannel then
		self:LogWarning(guild, "Channel management log channel %s no longer exists", nicknameChangeLogChannel)
		return
	end

	local data = self:GetData(guild)

	-- Ignore the first nickname change because new members tend to change it directly after joining which generates a lot of useless logs
	if data.nicknames[member.id] ~= nil and data.nicknames[member.id] ~= member.name then
		logChannel:send({
			embed = {
				title = "Nickname changed",
				description = string.format("%s - `%s` → `%s`", member.mentionString, data.nicknames[member.id], member.name),
				timestamp = discordia.Date():toISO('T', 'Z')
			}
		})
	end

	if data.usernames[member.id] ~= nil and data.usernames[member.id] ~= member.user.username then
		logChannel:send({
			embed = {
				title = "Username changed",
				description = string.format("%s - `%s` → `%s`", member.mentionString, data.usernames[member.id], member.user.username),
				timestamp = discordia.Date():toISO('T', 'Z')
			}
		})
	end

	data.nicknames[member.id] = member.name
	data.usernames[member.id] = member.user.username
end

function Module:OnMessageDelete(message)
	local guild = message.guild
	local config = self:GetConfig(guild)

	if table.search(config.IgnoredDeletedMessageChannels, message.channel.id) then
		return
	end

	local deletedMessageChannel = config.DeletedMessageChannel
	if not deletedMessageChannel then
		return
	end

	local logChannel = guild:getChannel(deletedMessageChannel)
	if not logChannel then
		self:LogWarning(guild, "Deleted message log channel %s no longer exists", deletedMessageChannel)
		return
	end

	local desc = "🗑️ **Deleted message - sent by " .. message.author.mentionString .. " in " .. message.channel.mentionString .. "**\n"

	local embed = Bot:BuildQuoteEmbed(message, { initialContentSize = #desc })
	embed.description = desc .. (embed.description or "")
	embed.footer = {
		text = string.format("Author ID: %s | Message ID: %s", message.author.id, message.id)
	}
	embed.timestamp = discordia.Date():toISO('T', 'Z')

	logChannel:send({
		embed = embed
	})
end

function Module:OnMessageDeleteUncached(channel, messageId)
	local guild = channel.guild
	local config = self:GetConfig(guild)

	if table.search(config.IgnoredDeletedMessageChannels, channel.id) then
		return
	end

	local deletedMessageChannel = config.DeletedMessageChannel
	if not deletedMessageChannel then
		return
	end

	local logChannel = guild:getChannel(deletedMessageChannel)
	if not logChannel then
		self:LogWarning(guild, "Deleted message log channel %s no longer exists", deletedMessageChannel)
		return
	end

	logChannel:send({
		embed = {
			description = "🗑️ **Deleted message (uncached) - sent by <unknown> in " .. channel.mentionString .. "**",
			footer = {
				text = string.format("Message ID: %s", messageId)
			},
			timestamp = discordia.Date():toISO('T', 'Z')
		}
	})
end

function Module:OnMessageCreate(message)
	local guild = message.guild
	if not guild then
		return
	end

	local data = self:GetData(guild)
	local cachedMessages = data.cachedMessages[message.channel.id]
	if not cachedMessages then
		cachedMessages = {}
		data.cachedMessages[message.channel.id] = cachedMessages
	end

	-- Remove oldest message from permanent cache and add the new message
	table.insert(cachedMessages, message)

	local messageCacheSize = self.GlobalConfig.PersistentMessageCacheSize
	while #cachedMessages > messageCacheSize do
		table.remove(cachedMessages, 1)
	end
end
