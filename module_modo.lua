-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local client = Client
local discordia = Discordia
local bot = Bot
local enums = discordia.enums
local bit = require("bit")

Module.Name = "modo"

function Module:GetConfigTable()
	return {
		{
			Name = "Trigger",
			Description = "Triggering emoji",
			Type = bot.ConfigType.Emoji,
			Default = "modo"
		},
		{
			Name = "AlertChannel",
			Description = "Channel where alerts will be posted",
			Type = bot.ConfigType.Channel,
			Default = ""
		},
		{
			Array = true,
			Name = "ImmunityRoles",
			Description = "Roles immune to moderators reactions",
			Type = bot.ConfigType.Role,
			Default = {}
		},
		{
			Name = "ModeratorPingThreshold",
			Description = "How many moderation emoji reactions are required to trigger a moderator ping (0 to disable)",
			Type = bot.ConfigType.Integer,
			Default = 5
		},
		{
			Name = "ModeratorRole",
			Description = "Which role should be pinged when a message reach the moderator ping threshold",
			Type = bot.ConfigType.Role,
			Default = ""
		},
		{
			Name = "MuteThreshold",
			Description = "How many moderation emoji reactions are required to auto-mute the original poster (0 to disable)",
			Type = bot.ConfigType.Integer,
			Default = 10
		},
		{
			Name = "MuteDuration",
			Description = "Duration of auto-mute",
			Type = bot.ConfigType.Duration,
			Default = 10 * 60
		},
		{
			Name = "MuteRole",
			Description = "Auto-mute role to be applied (no need to configure its permissions)",
			Type = bot.ConfigType.Role,
			Default = ""
		}
	}
end

function Module:OnLoaded()
	self.Clock = discordia.Clock()
	self.Clock:on("min", function ()
		local now = os.time()
		self:ForEachGuild(function (guildId, config, data, persistentData)
			local guild = client:getGuild(guildId)
			if (guild) then
				for userId,endTime in pairs(persistentData.MutedUsers) do
					if (now >= endTime) then
						self:Unmute(guild, userId)
					end
				end
			end
		end)
	end)

	return true
end

function Module:OnReady()
	self.Clock:start()
end

function Module:OnEnable(guild)
	local config = self:GetConfig(guild)

	local mentionEmoji = bot:GetEmojiData(guild, config.Trigger)
	if (not mentionEmoji) then
		return false, "Emoji \"" .. config.Trigger .. "\" not found (check your configuration)"
	end

	local alertChannel = guild:getChannel(config.AlertChannel)
	if (not alertChannel) then
		return false, "Alert channel not found (check your configuration)"
	end

	local data = self:GetPersistentData(guild)
	data.MutedUsers = data.MutedUsers or {}
	data.ReportedMessages = data.ReportedMessages or {}

	self:LogInfo(guild, "Checking mute role permission on all channels...")

	if (config.MuteRole) then
		for _, channel in pairs(guild.textChannels) do
			self:CheckTextMutePermissions(channel)
		end

		for _, channel in pairs(guild.voiceChannels) do
			self:CheckVoiceMutePermissions(channel)
		end
	else
		self:LogWarning(guild, "No mute role has been set")
	end

	return true
end

function Module:OnUnload()
	if (self.Clock) then
		self.Clock:stop()
	end
end

local DenyPermission = function (permissionOverwrite, permission)
	if (bit.band(permissionOverwrite.deniedPermissions, permission) ~= permission and not permissionOverwrite:denyPermissions(permission)) then
		client:warning("[%s] Failed to deny permissions on channel %s", permissionOverwrite.guild.name, permissionOverwrite.channel.name)
	end
end

function Module:CheckTextMutePermissions(channel)
	local config = self:GetConfig(channel.guild)
	local mutedRole = channel.guild:getRole(config.MuteRole)
	if (not mutedRole) then
		self:LogError(channel.guild, "Invalid muted role")
		return
	end

	local permissions = channel:getPermissionOverwriteFor(mutedRole)
	assert(permissions)

	DenyPermission(permissions, enums.permission.addReactions)
	DenyPermission(permissions, enums.permission.sendMessages)
end

function Module:CheckVoiceMutePermissions(channel)
	local config = self:GetConfig(channel.guild)
	local mutedRole = channel.guild:getRole(config.MuteRole)
	if (not mutedRole) then
		self:LogError(channel.guild, "Invalid muted role")
		return
	end

	local permissions = channel:getPermissionOverwriteFor(mutedRole)
	assert(permissions)

	DenyPermission(permissions, enums.permission.speak)
end

function Module:HandleEmojiAdd(userId, message)
	if (message.author.bot) then
		-- Ignore bot
		return
	end

	local messageMember = message.member
	if (not messageMember) then
		-- Ignore PM
		return
	end

	local guild = message.guild
	local config = self:GetConfig(guild)

	for _, roleId in pairs(config.ImmunityRoles) do
		if (messageMember:hasRole(roleId)) then
			return
		end
	end

	local alertChannel = client:getChannel(config.AlertChannel)
	assert(alertChannel)

	local data = self:GetPersistentData(guild)

	local reportedMessage = data.ReportedMessages[message.id]
	if (reportedMessage) then
		-- Check if user already reported this message
		if (table.search(reportedMessage.ReporterIds, userId)) then
			return
		end

		-- Update alert message embed
		table.insert(reportedMessage.ReporterIds, userId)

		local reporters = {}
		for _,reporterId in pairs(reportedMessage.ReporterIds) do
			local user = client:getUser(reporterId)
			table.insert(reporters, user.mentionString)
		end

		reportedMessage.Embed.title = #reporters .. " users reported a message"
		reportedMessage.Embed.fields[2].name = "Reporters"
		reportedMessage.Embed.fields[2].value = table.concat(reporters, "\n")

		local alertMessage = alertChannel:getMessage(reportedMessage.AlertMessageId)
		if (alertMessage) then
			alertMessage:setEmbed(reportedMessage.Embed)
		end

		local reporterCount = #reporters
		if (config.MuteThreshold > 0 and reporterCount >= config.MuteThreshold and not reportedMessage.MuteApplied) then
			-- Auto-mute
			if (config.muteRole) then
				local reportedUser = client:getUser(reportedMessage.ReportedUserId)
				if (self:Mute(guild, reportedMessage.ReportedUserId)) then
					local messageLink = alertMessage and bot:GenerateMessageLink(alertMessage) or "<error>"

					local durationStr = util.FormatTime(config.MuteDuration, 2)
					alertChannel:send(string.format("%s has been auto-muted for %s\n<%s>", reportedUser.mentionString, durationStr, messageLink))
					message.channel:send(string.format("%s has been auto-muted for %s due to reporting", reportedUser.mentionString, durationStr, messageLink))
				else
					alertChannel:send(string.format("Failed to mute %s", reportedUser.mentionString))
				end
			end

			reportedMessage.MuteApplied = true
		end

		if (config.ModeratorPingThreshold > 0 and reporterCount >= config.ModeratorPingThreshold and not reportedMessage.ModeratorPinged) then
			-- Ping moderators
			local moderatorRole = guild:getRole(config.ModeratorRole)
			if (moderatorRole) then
				alertChannel:send(string.format("A message has been reported %d times %s\n<%s>", reporterCount, moderatorRole.mentionString, alertMessage and bot:GenerateMessageLink(alertMessage) or "<error>"))
			end

			reportedMessage.ModeratorPinged = true
		end
	else
		local reporterUser = client:getUser(userId)

		local content = message.cleanContent
		if (#content > 800) then
			content = content:sub(1, 800) .. "...<truncated>"
		end

		local embedContent = {
			title = "One user reported a message",
			fields = {
				{
					name = "Reported user",
					value = message.author.mentionString,
					inline = true
				},
				{
					name = "Reporter",
					value = reporterUser.mentionString,
					inline = true
				},
				{
					name = "Message channel",
					value = message.channel.mentionString
				},
				{
					name = "Message content",
					value = content or "<empty>"
				},
				{
					name = "Message Link",
					value = bot:GenerateMessageLink(message)
				}
			},
			timestamp = discordia.Date():toISO('T', 'Z')
		}

		local alertMessage = alertChannel:send({
			embed = embedContent
		})

		if (not alertMessage) then
			self:LogError(message.guild, "Failed to post alert message (too long?) for %s", bot:GenerateMessageLink(message))
		end

		data.ReportedMessages[message.id] = {
			AlertMessageId = alertMessage and alertMessage.id,
			Embed = embedContent,
			ReportedUserId = message.author.id,
			ReporterIds = { userId }
		}
	end
end

function Module:HandleMessageRemove(channel, messageId)
	local data = self:GetPersistentData(channel.guild)

	local reportedMessage = data.ReportedMessages[messageId]
	if (not reportedMessage) then
		return
	end

	local config = self:GetConfig(channel.guild)

	reportedMessage.Embed.fields[5].value = "<Message deleted>"

	local alertChannel = client:getChannel(config.AlertChannel)
	assert(alertChannel)

	if (reportedMessage.AlertMessageId) then
		local alertMessage = alertChannel:getMessage(reportedMessage.AlertMessageId)
		if (alertMessage) then
			alertMessage:setEmbed(reportedMessage.Embed)
		end
	end
end

function Module:Mute(guild, userId)
	local config = self:GetConfig(guild)
	local member = guild:getMember(userId)
	if (member and member:addRole(config.MuteRole)) then
		local data = self:GetPersistentData(guild)

		data.MutedUsers[userId] = os.time() + config.MuteDuration
		return true
	end

	return false
end

function Module:Unmute(guild, userId)
	local config = self:GetConfig(guild)

	local data = self:GetPersistentData(guild)
	data.MutedUsers[userId] = nil

	local member = guild:getMember(userId)
	if (member) then
		if (member:removeRole(config.MuteRole)) then
			return true
		else
			self:LogError(guild, "Failed to unmute %s", member.fullname)
		end
	end

	return false
end

function Module:OnChannelCreate(channel)
	if (channel.type == enums.channelType.text) then
		self:CheckTextMutePermissions(channel)
	elseif (channel.type == enums.channelType.voice) then
		self:CheckVoiceMutePermissions(channel)
	end
end

function Module:OnReactionAdd(reaction, userId)
	if (reaction.message.channel.type ~= enums.channelType.text) then
		return
	end

	local guild = reaction.message.guild
	local config = self:GetConfig(guild)
	local emojiData = bot:GetEmojiData(guild, reaction.emojiName)
	if (not emojiData) then
		self:LogWarning(guild, "Emoji %s was used but not found in guild", reaction.emojiName)
		return
	end

	if (emojiData.Name ~= config.Trigger or (emojiData.Custom and emojiData.FromGuild ~= guild)) then
		return
	end

	self:HandleEmojiAdd(userId, reaction.message)
end

function Module:OnReactionAddUncached(channel, messageId, reactionIdorName, userId)
	if (channel.type ~= enums.channelType.text) then
		return
	end

	local config = self:GetConfig(channel.guild)
	local emojiData = bot:GetEmojiData(channel.guild, reactionIdorName)
	if (not emojiData) then
		self:LogWarning(channel.guild, "Emoji %s was used but not found in guild", reactionIdorName)
		return
	end

	if (emojiData.Name ~= config.Trigger) then
		return
	end

	local message = channel:getMessage(messageId)
	if (not message) then
		return
	end

	self:HandleEmojiAdd(userId, message)
end

function Module:OnMessageDelete(message)
	if (message.channel.type ~= enums.channelType.text) then
		return
	end

	self:HandleMessageRemove(message.channel, message.id)
end

function Module:OnMessageDeleteUncached(channel, messageId)
	if (channel.type ~= enums.channelType.text) then
		return
	end

	self:HandleMessageRemove(channel, messageId)
end
