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
	data.AlertMessages = data.AlertMessages or {}

	self:LogInfo(guild, "Checking mute role permission on all channels...")

	if (config.MuteRole) then
		local mutedRole = guild:getRole(config.MuteRole)
		if (mutedRole) then
			for _, channel in pairs(guild.textChannels) do
				self:CheckTextMutePermissions(channel)
			end
	
			for _, channel in pairs(guild.voiceChannels) do
				self:CheckVoiceMutePermissions(channel)
			end
		else
			self:LogError(guild, "Invalid muted role")
			config.MuteRole = nil
			self:SaveGuildConfig(guild)
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

function Module:CheckTextMutePermissions(channel)
	local config = self:GetConfig(channel.guild)
	local mutedRole = channel.guild:getRole(config.MuteRole)
	if (not mutedRole) then
		self:LogError(channel.guild, "Invalid muted role")
		return
	end

	local permissions = channel:getPermissionOverwriteFor(mutedRole)
	assert(permissions)

	local deniedPermissions = permissions:getDeniedPermissions()
	-- :enable here just sets the bit, disabling the permissions
	deniedPermissions:enable(enums.permission.addReactions, enums.permission.sendMessages, enums.permission.usePublicThreads, enums.permission.sendMessagesInThreads)

	if permissions:getAllowedPermissions() ~= discordia.Permissions() or permissions:getDeniedPermissions() ~= deniedPermissions then
		permissions:setPermissions('0', deniedPermissions)
	end
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

	local deniedPermissions = permissions:getDeniedPermissions()
	-- :enable here just sets the bit, disabling the permissions
	deniedPermissions:enable(enums.permission.speak)

	if permissions:getAllowedPermissions() ~= discordia.Permissions() or permissions:getDeniedPermissions() ~= deniedPermissions then
		permissions:setPermissions('0', deniedPermissions)
	end
end

local function GenerateJumpToComponents(message)
	return {
		type = enums.componentType.actionRow,
		components = {
			{
				type = enums.componentType.button,
				style = enums.buttonStyle.link,
				url = bot:GenerateMessageLink(message),
				label = "Jump to message"
			}		
		}
	}
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
	if not alertChannel then
		self:LogError(channel.guild, "Failed to get alert channel")
		return
	end

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
			table.insert(reporters, user and user.mentionString or "<failed to get user>")
		end

		reportedMessage.Embed.title = #reporters .. " users reported a message"
		reportedMessage.Embed.fields[2].name = "Reporters"
		reportedMessage.Embed.fields[2].value = table.concat(reporters, "\n")

		local alertMessage = alertChannel:getMessage(reportedMessage.AlertMessageId)
		if (alertMessage) then
			alertMessage:setEmbed(reportedMessage.Embed)
		end

		if not reportedMessage.Dismissed then
			local reporterCount = #reporters
			if (config.MuteThreshold > 0 and reporterCount >= config.MuteThreshold and not reportedMessage.MuteApplied) then
				-- Auto-mute
				if (config.muteRole) then
					local reportedUser = client:getUser(reportedMessage.ReportedUserId)
					if (self:Mute(guild, reportedMessage.ReportedUserId)) then
						local durationStr = util.DiscordRelativeTime(config.MuteDuration)
						alertChannel:send({
							content = string.format("%s has been auto-muted %s", reportedUser.mentionString, durationStr),
							reference = alertMessage and {
								message = alertMessage.id
							} or nil
						})
						message.channel:send(string.format("%s has been auto-muted for %s due to reporting", reportedUser.mentionString, durationStr, messageLink))
					else
						alertChannel:send({
							content = string.format("Failed to mute %s", reportedUser.mentionString),
							reference = alertMessage and {
								message = alertMessage.id
							} or nil
						})
					end
				end

				reportedMessage.MuteApplied = true
			end

			if (config.ModeratorPingThreshold > 0 and reporterCount >= config.ModeratorPingThreshold and not reportedMessage.ModeratorPinged) then
				-- Ping moderators
				local moderatorRole = guild:getRole(config.ModeratorRole)
				if (moderatorRole) then
					alertChannel:send({
						content = string.format("A message has been reported %d times %s\n<%s>", reporterCount, moderatorRole.mentionString, messageLink),
						reference = alertMessage and {
							message = alertMessage.id
						} or nil
					})
				end

				reportedMessage.ModeratorPinged = true
			end
		end
	else
		local reporterUser = client:getUser(userId)

		local content = message.cleanContent
		if (#content > 800) then
			content = content:sub(1, 800) .. "...<truncated>"
		end

		if (not content or #content == 0) then
			content = "<empty>"
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
					value = content
				},
				{
					name = "Action history",
					value = "None"
				}
			},
			timestamp = discordia.Date():toISO('T', 'Z')
		}

		local actionButtons = {
			{
				type = enums.componentType.button,
				custom_id = "alertmodule_dismiss",
				style = enums.buttonStyle.secondary,
				label = "Dismiss alert",
				emoji = { name = "🔇" }
			},
			{
				type = enums.componentType.button,
				custom_id = "alertmodule_deletemessage",
				style = enums.buttonStyle.primary,
				label = "Delete message",
				emoji = { name = "🗑️" }
			}
		}

		local components = { GenerateJumpToComponents(message) }
		table.insert(components, {
			type = enums.componentType.actionRow,
			components = actionButtons
		})

		if (Bot:GetModuleForGuild(guild, "modmail")) then
			table.insert(actionButtons, {
				type = enums.componentType.button,
				custom_id = "alertmodule_modmail",
				style = enums.buttonStyle.primary,
				label = "Open a modmail ticket",
				emoji = { name = "⚠️" }
			})
		end

		do
			-- Mute
			local muteDurations = { 10 * 60, 60 * 60, 6 * 60 * 60, 24 * 60 * 60, 0 }
			local options = {}
			for _, duration in pairs(muteDurations) do
				table.insert(options, {
					label = duration > 0 and "Mute for " .. util.FormatTime(duration) or "Mute indefinitely",
					value = tostring(duration)
				})
			end

			table.insert(components, {
				type = enums.componentType.actionRow,
				components = {
					{
						type = enums.componentType.selectMenu,
						custom_id = "alertmodule_mute",
						placeholder = "🙊 Mute member",
						disabled = Bot:GetModuleForGuild(guild, "mute") == nil,
						options = options
					}
				}
			})
		end

		local tempBanAvailable = Bot:GetModuleForGuild(guild, "mute") ~= nil
		do
			-- Ban
			local banDurations = { 60 * 60, 6 * 60 * 60, 24 * 60 * 60, 7 * 24 * 60 * 60 }
			local options = {}
			for _, duration in pairs(banDurations) do
				table.insert(options, {
					label = "Ban for " .. util.FormatTime(duration),
					value = tostring(duration),
					disabled = not tempBanAvailable
				})
			end

			table.insert(options, {
				label = "Ban permanently",
				value = "0"
			})

			table.insert(options, {
				label = "Ban permanently and delete last 24h messages",
				value = "0_deletemessages"
			})

			table.insert(components, {
				type = enums.componentType.actionRow,
				components = {
					{
						type = enums.componentType.selectMenu,
						custom_id = "alertmodule_ban",
						placeholder = "🔨 Ban member",
						options = options
					}
				}
			})
		end

		local alertMessage = alertChannel:send({
			embed = embedContent,
			components = components
		})

		if (not alertMessage) then
			self:LogError(message.guild, "Failed to post alert message (too long?) for %s", bot:GenerateMessageLink(message))
		end

		data.ReportedMessages[message.id] = {
			AlertMessageId = alertMessage and alertMessage.id or nil,
			ChannelId = message.channel.id,
			Components = components,
			Dismissed = false,
			Embed = embedContent,
			MessageId = message.id,
			ReportedUserId = message.author.id,
			ReporterIds = { userId }
		}

		if alertMessage then
			data.AlertMessages[alertMessage.id] = data.ReportedMessages[message.id]
		end
	end
end

function Module:HandleMessageRemove(channel, messageId)
	local data = self:GetPersistentData(channel.guild)

	local reportedMessage = data.ReportedMessages[messageId]
	if (not reportedMessage) then
		return
	end

	local config = self:GetConfig(channel.guild)

	-- Disable "jump to" button
	reportedMessage.Components[1].components[1].disabled = true
	-- Disable "delete message" button
	reportedMessage.Components[2].components[2].disabled = true

	local alertChannel = client:getChannel(config.AlertChannel)
	if (alertChannel and reportedMessage.AlertMessageId) then
		local alertMessage = alertChannel:getMessage(reportedMessage.AlertMessageId)
		if (alertMessage) then
			alertMessage:setComponents(reportedMessage.Components)
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

function Module:OnInteractionCreate(interaction)
	local guild = interaction.guild
	if not guild then
		return
	end

	local data = self:GetPersistentData(guild)
	local alertMessage = data.AlertMessages[interaction.message.id]
	if not alertMessage then
		-- Not our job
		return
	end

	local moderator = interaction.member

	local actionStr

	local interactionType = interaction.data.custom_id
	if interactionType == "alertmodule_dismiss" then
		if alertMessage.Dismissed then
			interaction:respond({
				type = enums.interactionResponseType.channelMessageWithSource,
				data = {
					content = "❎ Alert has already been dismissed",
					flags = enums.interactionResponseFlag.ephemeral
				}
			})
	
			return
		end

		alertMessage.Dismissed = true
		-- Disable dismiss button
		alertMessage.Components[2].components[1].disabled = true

		interaction:respond({
			type = enums.interactionResponseType.channelMessageWithSource,
			data = {
				content = "✅ Alert has been dismissed (it won't trigger mute nor ping)",
				flags = enums.interactionResponseFlag.ephemeral
			}
		})

		actionStr = "Dismissed by " .. moderator.mentionString
	elseif interactionType == "alertmodule_deletemessage" then
		-- "Waiting"
		interaction:respond({
			type = enums.interactionResponseType.deferredChannelMessageWithSource,
			data = {
				flags = enums.interactionResponseFlag.ephemeral
			}
		})

		local channel, err = client:getChannel(alertMessage.ChannelId)
		if not channel then
			interaction:editResponse({
				content = string.format("❌ failed to retrieve message channel: %s", err)
			})
			return
		end

		local message, err = channel:getMessage(alertMessage.MessageId)
		if not message then
			interaction:editResponse({
				content = string.format("❌ failed to retrieve message: %s", err)
			})
			return
		end

		local success, err = message:delete()
		if not success then
			interaction:editResponse({
				content = string.format("❌ failed to delete message: %s", err)
			})
			return
		end

		interaction:editResponse({
			content = "✅ the message was deleted"
		})

		actionStr = "Deleted by " .. moderator.mentionString
	elseif interactionType == "alertmodule_modmail" then
		local modmail = Bot:GetModuleForGuild(guild, "modmail")
		if not modmail then
			interaction:respond({
				type = enums.interactionResponseType.channelMessageWithSource,
				data = {
					content = "❌ The modmail module isn't enabled on this server",
					flags = enums.interactionResponseFlag.ephemeral
				}
			})
			return
		end

		-- "Waiting"
		interaction:respond({
			type = enums.interactionResponseType.deferredChannelMessageWithSource,
			data = {
				flags = enums.interactionResponseFlag.ephemeral
			}
		})

		local targetMember, err = guild:getMember(alertMessage.ReportedUserId)
		if not targetMember then
			interaction:editResponse({
				content = string.format("❌ failed to retrieve member: %s", err)
			})
			return
		end

		local reason = string.format("%s has opened a ticket following your message (<https://discord.com/channels/%s/%s/%s>)", moderator.mentionString, guild.id, alertMessage.ChannelId, alertMessage.MessageId)
		local ticketChannel, err = modmail:OpenTicket(moderator, targetMember, reason, true)
		if not ticketChannel then
			interaction:editResponse({
				content = string.format("❌ failed to open modmail ticket: %s", err)
			})
			return
		end

		interaction:editResponse({
			content = "✅ a modmail ticket has been created: " .. ticketChannel.mentionString
		})

		actionStr = "Modmail ticket opened by " .. moderator.mentionString
	elseif interactionType == "alertmodule_mute" then
		local mute = Bot:GetModuleForGuild(guild, "mute")
		if not mute then
			interaction:respond({
				type = enums.interactionResponseType.channelMessageWithSource,
				data = {
					content = "❌ The mute module isn't enabled on this server",
					flags = enums.interactionResponseFlag.ephemeral
				}
			})
			return
		end

		local duration = interaction.data.values and tonumber(interaction.data.values[1]) or nil
		if not duration then
			interaction:respond({
				type = enums.interactionResponseType.channelMessageWithSource,
				data = {
					content = "❌ an error occurred (invalid duration)",
					flags = enums.interactionResponseFlag.ephemeral
				}
			})
			return
		end

		-- "Waiting"
		interaction:respond({
			type = enums.interactionResponseType.deferredChannelMessageWithSource,
			data = {
				flags = enums.interactionResponseFlag.ephemeral
			}
		})

		local success, err = mute:Mute(guild, alertMessage.ReportedUserId, duration)
		if not success then
			interaction:editResponse({
				content = string.format("❌ failed to open mute member: %s", err)
			})
			return
		end

		interaction:editResponse({
			content = "✅ the member has been muted for " .. util.FormatTime(duration)
		})

		actionStr = "Muted " .. util.DiscordRelativeTime(duration) .. " by " .. moderator.mentionString
	elseif interactionType == "alertmodule_ban" then
		local duration = interaction.data.values and interaction.data.values[1] or nil
		if duration == "0" or duration == "0_deletemessages" then
			-- "Waiting"
			interaction:respond({
				type = enums.interactionResponseType.deferredChannelMessageWithSource,
				data = {
					flags = enums.interactionResponseFlag.ephemeral
				}
			})

			local purgeDays = duration == "0_deletemessages" and 1 or 0

			local reason = "banned by " .. moderator.name .. " via alert"

			local success, err = guild:banUser(alertMessage.ReportedUserId, "banned by " .. moderator.name .. " via alert", purgeDays)
			if not success then
				interaction:editResponse({
					content = string.format("❌ failed to open ban user: %s", err)
				})
				return
			end

			local ban = Bot:GetModuleForGuild(guild, "ban")
			if ban then
				ban:RegisterBan(guild, alertMessage.ReportedUserId, moderator, 0, reason)
			end

			interaction:editResponse({
				content = "✅ the member has been banned" .. (purgeDays > 0 and " (and its last 24h message deleted)" or "")
			})
	
			actionStr = "banned permanently by " .. moderator.mentionString .. (purgeDays > 0 and " (last 24h message deleted)" or "")
		else
			duration = duration and tonumber(duration) or nil
			if not duration then
				interaction:respond({
					type = enums.interactionResponseType.channelMessageWithSource,
					data = {
						content = "❌ an error occurred (invalid duration)",
						flags = enums.interactionResponseFlag.ephemeral
					}
				})
				return
			end

			-- Temp ban
			local ban = Bot:GetModuleForGuild(guild, "ban")
			if not ban then
				interaction:respond({
					type = enums.interactionResponseType.channelMessageWithSource,
					data = {
						content = "❌ The ban module isn't enabled on this server (and is required for temporary ban)",
						flags = enums.interactionResponseFlag.ephemeral
					}
				})
				return
			end

			-- "Waiting"
			interaction:respond({
				type = enums.interactionResponseType.deferredChannelMessageWithSource,
				data = {
					flags = enums.interactionResponseFlag.ephemeral
				}
			})

			local durationStr = util.FormatTime(duration)

			local success, err = guild:banUser(alertMessage.ReportedUserId, "banned by " .. moderator.name .. " via alert for " .. durationStr)
			if not success then
				interaction:editResponse({
					content = string.format("❌ failed to open ban user: %s", err)
				})
				return
			end

			ban:RegisterBan(guild, alertMessage.ReportedUserId, moderator, duration, reason)

			interaction:editResponse({
				content = "✅ the member has been banned for " .. durationStr
			})
	
			actionStr = "banned for " .. durationStr .. " by " .. moderator.mentionString
		end
	else
		interaction:respond({
			type = enums.interactionResponseType.channelMessageWithSource,
			data = {
				content = "❌ an error occurred (unknown interaction type " .. tostring(interactionType) .. ")"
			}
		})
		return
	end

	if actionStr then
		local currentActionStr = alertMessage.Embed.fields[5].value
		if currentActionStr == "None" then
			alertMessage.Embed.fields[5].value = actionStr
		else
			alertMessage.Embed.fields[5].value = currentActionStr .. "\n" .. actionStr
		end

		interaction.message:update({
			components = alertMessage.Components,
			embed = alertMessage.Embed
		})
	end
end

function Module:OnReactionAdd(reaction, userId)
	if (not bot:IsPublicChannel(reaction.message.channel)) then
		return
	end

	local guild = reaction.message.guild
	local config = self:GetConfig(guild)
	local emojiData = bot:GetEmojiData(guild, reaction.emojiId or reaction.emojiName)
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
	if (not bot:IsPublicChannel(channel)) then
		return
	end

	local guild = channel.guild
	local config = self:GetConfig(guild)
	local emojiData = bot:GetEmojiData(guild, reactionIdorName)
	if (not emojiData) then
		self:LogWarning(guild, "Emoji %s was used but not found in guild", reactionIdorName)
		return
	end

	if (emojiData.Name ~= config.Trigger or (emojiData.Custom and emojiData.FromGuild ~= guild)) then
		return
	end

	local message = channel:getMessage(messageId)
	if (not message) then
		return
	end

	self:HandleEmojiAdd(userId, message)
end

function Module:OnMessageDelete(message)
	if (not bot:IsPublicChannel(message.channel)) then
		return
	end

	self:HandleMessageRemove(message.channel, message.id)
end

function Module:OnMessageDeleteUncached(channel, messageId)
	if (not bot:IsPublicChannel(channel)) then
		return
	end

	self:HandleMessageRemove(channel, messageId)
end
