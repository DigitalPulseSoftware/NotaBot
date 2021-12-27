-- Copyright (C) 2020 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local bot = Bot
local client = Client
local discordia = Discordia
local enums = discordia.enums

discordia.extensions() -- load all helpful extensions

local json = require("json")

Module.Name = "modmail"

function Module:GetConfigTable()
	return {
		{
			Name = "Category",
			Description = "Where should modmail channels be created",
			Type = bot.ConfigType.Category,
			Default = ""
		},
		{
			Name = "ArchiveCategory",
			Description = "Category where modmail channels are moved to when closed",
			Type = bot.ConfigType.Category,
			Optional = true
		},
		{
			Name = "LogChannel",
			Description = "Where should modmail logs should be stored",
			Type = bot.ConfigType.Channel,
			Optional = true
		},
		{
			Array = true,
			Name = "TicketHandlingRoles",
			Description = "Roles allowed to close tickets (and force open them for members)",
			Type = bot.ConfigType.Role,
			Default = {}
		},
		{
			Array = true,
			Name = "ForbiddenRoles",
			Description = "Roles that aren't allowed to open a ticket",
			Type = bot.ConfigType.Role,
			Default = {}
		},
		{
			Array = true,
			Name = "AllowedRoles",
			Description = "Roles allowed to open tickets for them (if empty, everyone)",
			Type = bot.ConfigType.Role,
			Default = {}
		},
		{
			Name = "MaxConcurrentChannels",
			Description = "How many concurrents (active) channels can be created",
			Type = bot.ConfigType.Integer,
			Default = 10
		},
		{
			Name = "DeleteDuration",
			Description = "How many time does a ticket channel take to be deleted after being closed",
			Type = bot.ConfigType.Duration,
			Default = 24 * 60 * 60
		},
		{
			Name = "SaveTicketContent",
			Description = "Should the bot save every message in a modmail ticket when closing them? (up to 2000 messages)",
			Type = bot.ConfigType.Boolean,
			Default = true
		}
	}
end

function Module:OnLoaded()
	self.Timer = Bot:CreateRepeatTimer(1, -1, function ()
		local now = os.time()
		self:ForEachGuild(function (guildId, config, data, persistentData)
			local guild = client:getGuild(guildId)
			if (guild) then
				local config = self:GetConfig(guild)
				local deleteDuration = config.DeleteDuration

				local data = self:GetPersistentData(guild)

				local archiveData = data.archivedChannels[1]
				if (archiveData and now >= archiveData.closedAt + deleteDuration) then
					table.remove(data.archivedChannels, 1)

					local channel = guild:getChannel(archiveData.channelId)

					if (channel) then
						channel:delete()
					end
				end
			end
		end)
	end)

	self:RegisterCommand({
		Name = "newticket",
		Args = {
			{Name = "member", Type = Bot.ConfigType.Member, Optional = true},
			{Name = "message", Type = Bot.ConfigType.String, Optional = true},
		},

		Help = "Allows you to contact the server staff in private",
		Silent = true,
		Func = function (commandMessage, targetMember, reason)
			local fromMember = commandMessage.member
			local guild = commandMessage.guild
			local config = self:GetConfig(guild)

			if (util.MemberHasAnyRole(fromMember, config.ForbiddenRoles)) then
				return commandMessage:reply("You do not have the permission to open a ticket on this server")
			end
		
			if (targetMember and targetMember ~= fromMember) then
				local authorized = util.MemberHasAnyRole(fromMember, config.TicketHandlingRoles)
		
				if (not authorized) then
					return commandMessage:reply("You do not have the permission to open a ticket for someone else")
				end
			else
				local allowedRoles = config.AllowedRoles
				if (#allowedRoles > 0) then
					local authorized = util.MemberHasAnyRole(fromMember, allowedRoles)
					if (not authorized) then
						return commandMessage:reply("You do not have the permission to open a ticket")
					end
				end
		
				targetMember = fromMember
			end
		
			local success, err = self:OpenTicket(commandMessage.member, targetMember, reason, true)
			if (not success) then
				return commandMessage:reply(err)
			end
		end
	})

	self:RegisterCommand({
		Name = "modticket",
		Args = {
			{Name = "member", Type = Bot.ConfigType.Member},
			{Name = "message", Type = Bot.ConfigType.String, Optional = true},
		},
		PrivilegeCheck = function (member) 
			local guild = member.guild
			local config = self:GetConfig(guild)

			return util.MemberHasAnyRole(member, config.TicketHandlingRoles)
		end,

		Help = "Opens a moderation ticket for someone (same as newticket but doesn't allow the target user to talk)",
		Silent = true,
		Func = function (commandMessage, targetMember, reason)
			local success, err = self:OpenTicket(commandMessage.member, targetMember, reason, false)
			if (not success) then
				return commandMessage:reply(err)
			end
		end
	})

	self:RegisterCommand({
		Name = "closeticket",
		Args = {
			{Name = "reason", Type = Bot.ConfigType.String, Optional = true},
		},

		Help = "When used in a ticket channel, close it",
		Silent = true,
		Func = function (commandMessage, reason)
			local ret = self:HandleTicketClose(commandMessage.member, commandMessage, reason, false)
			if (ret == nil) then
				commandMessage:reply(string.format("You must type this in an active ticket channel, %s.", commandMessage.member.user.mentionString))
			elseif (ret == false) then
				commandMessage:reply(string.format("You are not authorized to do that %s.", commandMessage.member.user.mentionString))
			end
		end
	})

	return true
end

function Module:OnUnload()
	self.Timer:Stop()
end

function Module:OnEnable(guild)
	local config = self:GetConfig(guild)
	local modmailCategory = guild:getChannel(config.Category)
	if (not modmailCategory or modmailCategory.type ~= enums.channelType.category) then
		return false, "Invalid modmail category (check your configuration)"
	end

	local data = self:GetPersistentData(guild)
	data.activeChannels = data.activeChannels or {}
	data.archivedChannels = data.archivedChannels or {}

	return true
end

function Module:HandleEmojiAdd(userId, message, reactionName)
	if (userId == client.user.id) then
		-- Ignore bot own reaction
		return
	end

	if (reactionName ~= "👋") then
		return
	end

	local guild = message.guild
	local member = guild:getMember(userId)
	if (not member) then
		return
	end

	self:HandleTicketClose(member, message, nil, true)
end

function Module:HandleTicketClose(member, message, reason, reactionClose)
	local guild = message.guild
	local config = self:GetConfig(guild)

	local authorized = false
	for _, roleId in pairs(config.TicketHandlingRoles) do
		if (member:hasRole(roleId)) then
			authorized = true
			break
		end
	end

	if (not authorized) then
		return false
	end

	local data = self:GetPersistentData(guild)

	for userId, channelData in pairs(data.activeChannels) do
		local channelTest = false
		if (reactionClose) then
			channelTest = (channelData.topMessageId == message.id)
		else
			channelTest = (channelData.channelId == message.channel.id)
		end

		if (channelTest) then
			local archiveData = channelData

			local config = self:GetConfig(guild)

			local ticketChannel = guild:getChannel(channelData.channelId)
			local closeMessage = string.format("%s has closed the ticket, this channel will automatically be deleted in about %s", member.user.mentionString, util.FormatTime(config.DeleteDuration, 2))

			if (reason and #reason > 0) then
				local author = member.user
				ticketChannel:send({
					content = closeMessage,
					embed = {
						author = {
							name = author.tag,
							icon_url = author.avatarURL
						},
						description = reason,
						timestamp = discordia.Date():toISO('T', 'Z')
					}
				})
			else
				ticketChannel:send(closeMessage)
			end

			ticketChannel:setName(ticketChannel.name .. "✅")

			data.activeChannels[userId] = nil

			if (config.ArchiveCategory and config.ArchiveCategory ~= ticketChannel.id) then
				local archiveCategory = guild:getChannel(config.ArchiveCategory)
				if (archiveCategory and archiveCategory.type == enums.channelType.category) then
					ticketChannel:setCategory(config.ArchiveCategory)
				end
			end

			local ticketMember = guild:getMember(userId)
			if (ticketMember) then
				local permissions = ticketChannel:getPermissionOverwriteFor(ticketMember)

				if (not permissions or not permissions:setPermissions(enums.permission.viewChannel, enums.permission.sendMessages)) then
					ticketChannel:sendf("Failed to deny send messages permission to %s.", ticketMember.mentionString)
				end
			end

			if (config.LogChannel) then
				local channel = guild:getChannel(config.LogChannel)
				if (channel) then
					local author
					if (ticketMember) then
						author = {
							name = ticketMember.tag,
							icon_url = ticketMember.avatarURL
						}
					end

					local fields
					if (reason and #reason > 0) then
						fields = {
							{
								name = "Close message",
								value = reason
							}
						}
					end

					local file
					if config.SaveTicketContent then
						local messages, err = Bot:FetchChannelMessages(ticketChannel, nil, 2000)
						if not messages then
							table.insert(fields, {
								{
									name = "⚠️ Failed to save ticket content",
									value = string.format("error: %s", err)
								}
							})
						end

						local jsonSave = json.encode(bot:MessagesToTable(messages), { indent = 1})
						file = {
							"messages.json", 
							jsonSave
						}

						fields = fields or {}
						table.insert(fields, {
							name = "🗒️ ticket content has been saved",
							value = "Check attachment file"
						})
					end

					local success, err = channel:send({
						embed = {
							author = author,
							color = 16711680,
							description = member.mentionString .. " has closed ticket " .. ticketChannel.mentionString,
							fields = fields,
							footer = {
								text = "UserID: " .. userId .. " | TicketID: " .. ticketChannel.id
							},
							timestamp = discordia.Date():toISO('T', 'Z')
						},
						file = file
					})
					if not success then
						self:LogError(guild, "Failed to post closing ticket message (%s)", err)
					end
				end
			end

			-- Insert into archived channels once deletion is possible
			table.insert(data.archivedChannels, {
				channelId = ticketChannel.id,
				closedAt = os.time()
			})

			return true
		end
	end
end

function Module:OpenTicket(fromMember, targetMember, reason, twoWays)
	local guild = fromMember.guild
	local config = self:GetConfig(guild)
	local data = self:GetPersistentData(guild)

	if (data.activeChannels[targetMember.user.id]) then
		if (targetMember == fromMember) then
			return false, string.format("you already have an active ticket on this server, %s.", targetMember.user.mentionString)
		else
			return false, string.format("%s already has an active ticket on this server.", targetMember.user.tag, targetMember.user.mentionString)
		end

		return
	end

	if (config.MaxConcurrentChannels > 0 and table.count(data.activeChannels) >= config.MaxConcurrentChannels) then
		return false, string.format("sorry %s, but there are actually too many tickets open at the same time, please retry in a moment", fromMember.user.mentionString)
	end

	local modmailCategory = guild:getChannel(config.Category)
	if (not modmailCategory or modmailCategory.type ~= enums.channelType.category) then
		return false, "this server is not well configured, please tell the admins!"
	end

	local filteredUsername = targetMember.user.username:gsub("[^%w]", ""):sub(1, 8)
	if (#filteredUsername == 0) then
		filteredUsername = "empty"
	end

	local ticketChannel, err = modmailCategory:createTextChannel(string.format("%s-%s", filteredUsername, targetMember.user.discriminator))
	if (not ticketChannel) then
		print(err)
		return false, "failed to create the channel, this is likely a bug."
	end

	local permissionOverwrite, err = ticketChannel:getPermissionOverwriteFor(targetMember)
	if (not permissionOverwrite) then
		print(err)
		return false, "failed to create the channel, this is likely a bug."
	end

	local allowedPermissions = enums.permission.viewChannel
	local deniedPermissions = 0
	if (twoWays) then
		allowedPermissions = bit.bor(allowedPermissions, enums.permission.sendMessages)
	else
		deniedPermissions = bit.bor(deniedPermissions, enums.permission.sendMessages)
	end
 
	if (not permissionOverwrite:setPermissions(allowedPermissions, deniedPermissions)) then
		return false, "failed to create the channel, this is likely a bug."
	end

	if (config.LogChannel) then
		local channel = guild:getChannel(config.LogChannel)
		if (channel) then
			local color, desc
			if (fromMember == targetMember) then
				color = 61695
				desc = targetMember.mentionString .. " has opened a new ticket (" .. ticketChannel.mentionString .. ")"
			elseif (twoWays) then
				color = 65280
				desc = fromMember.mentionString .. " has opened a new ticket for " .. targetMember.mentionString .. " (" .. ticketChannel.mentionString .. ")"
			else
				color = 16776960
				desc = fromMember.mentionString .. " has opened a moderator ticket for " .. targetMember.mentionString .. " (" .. ticketChannel.mentionString .. ")"
			end

			local fields
			if (reason and #reason > 0) then
				fields = {
					{
						name = "Ticket message",
						value = reason
					}
				}
			end

			local success, err = channel:send({
				embed = {
					author = {
						name = targetMember.tag,
						icon_url = targetMember.avatarURL
					},
					color = color,
					description = desc,
					fields = fields,
					footer = {
						text = "UserID: " .. targetMember.user.id .. " | TicketID: " .. ticketChannel.id
					},
					timestamp = discordia.Date():toISO('T', 'Z')
				}
			})
			if not success then
				self:LogError(guild, "Failed to post opening ticket message (%s)", err)
			end
		end
	end

	local activeChannelData = {
		createdAt = os.time(),
		channelId = ticketChannel.id
	}

	data.activeChannels[targetMember.user.id] = activeChannelData

	local message
	if (targetMember == fromMember) then
		message = string.format("Hello %s, use this private channel to communicate with **%s** staff.\n\nStaff can react on this message with 👋 to close the ticket", targetMember.user.mentionString, guild.name)
	else
		message = string.format("Hello %s, **%s** staff wants to communicate with you.\n\nStaff can react on this message with 👋 to close the ticket", targetMember.user.mentionString, guild.name)
	end

	local message = ticketChannel:send(message)
	message:addReaction("👋")
	message:pin()

	activeChannelData.topMessageId = message.id

	if (reason and #reason > 0) then
		local author = fromMember.user
		local message, err = ticketChannel:send({
			content = "Ticket message:",
			embed = {
				author = {
					name = author.tag,
					icon_url = author.avatarURL
				},
				description = reason,
				timestamp = discordia.Date():toISO()
			}
		})

		if not message then
			self:LogError(guild, "Failed to post reason message (%s)", err)
		end
	end

	return ticketChannel
end

function Module:OnReactionAdd(reaction, userId)
	local message = reaction.message
	if (not bot:IsPublicChannel(message.channel)) then
		return
	end

	self:HandleEmojiAdd(userId, message, reaction.emojiName)
end

function Module:OnReactionAddUncached(channel, messageId, reactionIdOrName, userId)
	if (not bot:IsPublicChannel(channel)) then
		return
	end

	local message = channel:getMessage(messageId)
	if (not message) then
		return
	end

	self:HandleEmojiAdd(userId, message, reactionIdOrName)
end

function Module:OnChannelDelete(channel)
	if (not bot:IsPublicChannel(channel)) then
		return
	end

	local guild = channel.guild

	local data = self:GetPersistentData(guild)
	for userId, channelData in pairs(data.activeChannels) do
		if (channelData.channelId == channel.id) then
			data.activeChannels[userId] = nil
			break
		end
	end
end
