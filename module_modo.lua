-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local client = Client
local config = Config
local discordia = Discordia
local bot = Bot
local enums = discordia.enums
local bit = require("bit")

Module.Name = "modo"
Module.MutedUsers = {}
Module.ReportedMessages = {}

function Module:OnLoaded()
	self.Config = config.ModoModule
	assert(self.Config)
	assert(self.Config.AlertChannel)
	assert(self.Config.EmojiName)
	assert(self.Config.ImmunityRoles)
	assert(self.Config.ModeratorRoleId)
	assert(self.Config.ModeratorPingThreshold)
	assert(self.Config.MuteDuration)
	assert(self.Config.MuteRoleId)
	assert(self.Config.MuteThreshold)

	self.Clock = discordia.Clock()
	self.Clock:on("sec", function ()
		local now = os.time()
		for userId,endTime in pairs(self.MutedUsers) do
			if (now >= endTime) then
				self:Unmute(userId)
			end
		end
	end)
	self.Clock:start()

	return true
end

function Module:OnReady()
	local guild = client:getGuild(config.Guild)
	local t1 = os.clock()

	print("Unmuting all previously muted users, if any")
	local mutedRole = guild:getRole(self.Config.MuteRoleId)

	for _,member in pairs(mutedRole.members) do
		if (not member:removeRole(mutedRole.id)) then
			print("Failed to unmute " .. member.fullname)
		end
	end

	local t2 = os.clock()
	print("Users unmuted (" .. (t2 - t1) * 1000 .. "s).")

	print("Checking mute role permission on all channels...")
	for _, channel in pairs(guild.textChannels) do
		self:CheckTextMutePermissions(channel)
	end

	for _, channel in pairs(guild.voiceChannels) do
		self:CheckVoiceMutePermissions(channel)
	end
	
	print("Permissions applied (" .. (os.clock() - t2) * 1000 .. "s).")
end

function Module:OnUnload()
	if (self.Clock) then
		self.Clock:stop()
	end
end

local DenyPermission = function (permissionOverwrite, permission)
	if (bit.band(permissionOverwrite.deniedPermissions, permission) ~= permission and not permissionOverwrite:denyPermissions(permission)) then
		print("Failed to deny permissions on channel " .. permissionOverwrite.channel.name)
	end
end

function Module:CheckTextMutePermissions(channel)
	local guild = client:getGuild(config.Guild)
	local mutedRole = guild:getRole(self.Config.MuteRoleId)
	local permissions = channel:getPermissionOverwriteFor(mutedRole)
	DenyPermission(permissions, enums.permission.addReactions)
	DenyPermission(permissions, enums.permission.sendMessages)
end

function Module:CheckVoiceMutePermissions(channel)
	local guild = client:getGuild(config.Guild)
	local mutedRole = guild:getRole(self.Config.MuteRoleId)
	local permissions = channel:getPermissionOverwriteFor(mutedRole)
	DenyPermission(permissions, enums.permission.speak)
end

function Module:GenerateMessageLink(message)
	local guildId = message.guild and message.guild.id or "@me"
	return string.format("https://discordapp.com/channels/%s/%s/%s", guildId, message.channel.id, message.id)
end

function Module:HandleEmojiAdd(userId, message)
	if (message.author.bot) then
		-- Ignore bot
		return
	end

	if (not message.member) then
		-- Ignore PM
		return
	end

	local guild = message.guild
	local messageMember = message.member
	for _,roleId in pairs(self.Config.ImmunityRoles) do
		if (messageMember:hasRole(roleId)) then
			return
		end
	end

	local alertChannel = client:getChannel(self.Config.AlertChannel)

	local reportedMessage = self.ReportedMessages[message.id]
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
		alertMessage:setEmbed(reportedMessage.Embed)

		local reporterCount = #reporters
		if (reporterCount >= self.Config.MuteThreshold and not reportedMessage.MuteApplied) then
			reportedMessage.MuteApplied = true

			-- Auto-mute
			if (self:Mute(reportedMessage.ReportedUserId)) then
				local reportedUser = client:getUser(reportedMessage.ReportedUserId)
				alertChannel:send(string.format("%s has been auto-muted for %d seconds\n<%s>", reportedUser.mentionString, self.Config.MuteDuration, self:GenerateMessageLink(alertMessage)))
				message.channel:send(string.format("%s has been auto-muted for %d seconds due to reporting", reportedUser.mentionString, self.Config.MuteDuration, self:GenerateMessageLink(alertMessage)))
			else
				alertChannel:send(string.format("Failed to mute %s", member.user.fullname))
			end
		end

		if (reporterCount >= self.Config.ModeratorPingThreshold and not reportedMessage.ModeratorPinged) then
			reportedMessage.ModeratorPinged = true

			-- Ping moderators
			local guild = client:getGuild(config.Guild)
			local moderatorRole = guild:getRole(self.Config.ModeratorRoleId)
			if (moderatorRole) then
				alertChannel:send(string.format("A message has been reported %d times %s\n<%s>", reporterCount, moderatorRole.mentionString, self:GenerateMessageLink(alertMessage)))
			end
		end
	else
		local reporterUser = client:getUser(userId)
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
					name = "Message content",
					value = message.cleanContent
				},
				{
					name = "Message Link",
					value = self:GenerateMessageLink(message)
				}
			},
			timestamp = discordia.Date():toISO('T', 'Z')
		}

		local alertMessage = alertChannel:send({
			embed = embedContent
		})

		self.ReportedMessages[message.id] = {
			AlertMessageId = alertMessage.id,
			Embed = embedContent,
			ReportedUserId = message.author.id,
			ReporterIds = { userId }
		}
	end
end

function Module:HandleMessageRemove(channel, messageId)
	local reportedMessage = self.ReportedMessages[messageId]
	if (not reportedMessage) then
		return
	end

	reportedMessage.Embed.fields[4].value = "<Message deleted>"

	local alertChannel = client:getChannel(self.Config.AlertChannel)
	local alertMessage = alertChannel:getMessage(reportedMessage.AlertMessageId)
	alertMessage:setEmbed(reportedMessage.Embed)
end

function Module:Mute(userId)
	local guild = client:getGuild(config.Guild)
	local member = guild:getMember(userId)
	if (member and member:addRole(self.Config.MuteRoleId)) then
		self.MutedUsers[userId] = os.time() + self.Config.MuteDuration
		return true
	end

	return false
end

function Module:Unmute(userId)
	local guild = client:getGuild(config.Guild)
	local member = guild:getMember(userId)
	if (member) then
		Module.MutedUsers[userId] = nil
		if (member:removeRole(self.Config.MuteRoleId)) then
			return true
		else
			print("Failed to unmute " .. member.fullname)
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

	if (reaction.emojiName ~= self.Config.EmojiName) then
		return
	end

	self:HandleEmojiAdd(userId, reaction.message)
end

function Module:OnReactionAddUncached(channel, messageId, reactionIdorName, userId)
	if (channel.type ~= enums.channelType.text) then
		return
	end

	local emojiData = bot:GetEmojiData(channel.guild, reactionIdorName)
	if (emojiData.Name ~= self.Config.EmojiName) then
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
