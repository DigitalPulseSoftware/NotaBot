-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local client = Client
local discordia = Discordia
local bot = Bot
local enums = discordia.enums
local bit = require("bit")

Module.Name = "mute"

function Module:GetConfigTable()
	return {
		{
			Array = true,
			Name = "AuthorizedRoles",
			Description = "Roles allowed to use mute commands",
			Type = bot.ConfigType.Role,
			Default = {}
		},
		{
			Name = "DefaultMuteDuration",
			Description = "Default mute duration if no duration is set",
			Type = bot.ConfigType.Duration,
			Default = 10 * 60
		},
		{
			Name = "SendPrivateMessage",
			Description = "Should the bot try to send a private message when muting someone?",
			Type = bot.ConfigType.Boolean,
			Default = true
		},
		{
			Name = "MuteRole",
			Description = "Mute role to be applied (no need to configure its permissions)",
			Type = bot.ConfigType.Role,
			Default = ""
		}
	}
end

function Module:CheckPermissions(member)
	local config = self:GetConfig(member.guild)
	if (util.MemberHasAnyRole(member, config.AuthorizedRoles)) then
		return true
	end

	if (member:hasPermission(enums.permission.administrator)) then
		return true
	end

	return false
end

function Module:PerformMute(guild, mutedBy, targetMember, duration, reason)
			local config = self:GetConfig(guild)
	if (not duration) then duration = config.DefaultMuteDuration end
	reason = (reason and #reason > 0) and (" " .. bot:Format(guild, "MUTE_REASON", reason)) or ""

			local mutedByRole = mutedBy.highestRole
			local targetRole = targetMember.highestRole
			if (targetRole.position >= mutedByRole.position) then
		return false, bot:Format(guild, "MUTE_NOTAUTHORIZED")
			end

			if (config.SendPrivateMessage) then
		local durationText = ""
				if (duration > 0) then
					durationText = "\n" .. bot:Format(guild, "MUTE_YOU_WILL_BE_UNMUTED_IN", util.DiscordRelativeTime(duration))
				end

				local privateChannel = targetMember:getPrivateChannel()
				if (privateChannel) then
			privateChannel:send(
				bot:Format(guild, "MUTE_PRIVATE_MESSAGE", guild.name, mutedBy.user.mentionString, reason, durationText)
			)
				end
			end

			local success, err = self:Mute(guild, targetMember.id, duration)
			if (success) then
		local durationText = ""
				if (duration > 0) then
					durationText = "\n" .. bot:Format(guild, "MUTE_THEY_WILL_BE_UNMUTED_IN", util.DiscordRelativeTime(duration))
		end

		return true, bot:Format(guild, "MUTE_GUILD_MESSAGE", mutedBy.name, targetMember.tag, reason, durationText)
				else
		return false, bot:Format(guild, "MUTE_MUTE_FAILED", targetMember.tag, err)
	end
				end

function Module:PerformUnmute(guild, unmutedBy, targetUser, reason)
	local config = self:GetConfig(guild)
	reason = (reason and #reason > 0) and (" " .. bot:Format(guild, "MUTE_REASON", reason)) or ""

	if (config.SendPrivateMessage) then
		local privateChannel = targetUser:getPrivateChannel()
		if (privateChannel) then
			privateChannel:send(bot:Format(guild, "MUTE_UNMUTE_MESSAGE", guild.name, unmutedBy.mentionString, reason))
		end
	end

	local success, err = self:Unmute(guild, targetUser.id)
	if (success) then
		return true, bot:Format(guild, "MUTE_UNMUTE_GUILD_MESSAGE", unmutedBy.name, targetUser.tag, reason)
			else
		return false, bot:Format(guild, "MUTE_UNMUTE_FAILED", targetUser.tag, err)
	end
end

local function BuildMuteModal(targetMember)
	return {
		type = enums.interactionResponseType.modal,
		data = {
			custom_id = "mute_modal_" .. targetMember.id,
			title = "Mute " .. targetMember.tag,
			components = {
				{
					type = enums.componentType.actionRow,
					components = {
						{
							type = enums.componentType.textInput,
							custom_id = "duration",
							style = enums.textInputStyle.short,
							label = "Duration",
							placeholder = "30m, 2h, 1d... (leave empty for default duration)",
							required = false
						}
					}
				},
				{
					type = enums.componentType.actionRow,
					components = {
						{
							type = enums.componentType.textInput,
							custom_id = "reason",
							style = enums.textInputStyle.paragraph,
							label = "Reason",
							required = false
						}
					}
				}
			}
		}
	}
end

local function BuildUnmuteModal(targetUser)
	return {
		type = enums.interactionResponseType.modal,
		data = {
			custom_id = "unmute_modal_" .. targetUser.id,
			title = "Unmute " .. targetUser.tag,
			components = {
				{
					type = enums.componentType.actionRow,
					components = {
						{
							type = enums.componentType.textInput,
							custom_id = "reason",
							style = enums.textInputStyle.paragraph,
							label = "Reason",
							required = false
						}
					}
				}
			}
		}
	}
end

function Module:OnLoaded()
	self:RegisterCommand({
		Name = "mute",
		Args = {
			{ Name = "target", Type = Bot.ConfigType.Member, Description = "Member to mutes" },
			{
				Name = "duration",
				Type = Bot.ConfigType.Duration,
				Description = "Duration to mutes for (seconds by default, or use m/h/d/w suffix, e.g. 30m, 2h)",
				Optional = true
			},
			{ Name = "reason", Type = Bot.ConfigType.String, Description = "Mutes reason", Optional = true }
		},
		PrivilegeCheck = function (member) return self:CheckPermissions(member) end,
		Help = "Mutes a member",
		Silent = true,
		Func = function (commandMessage, targetMember, duration, reason)
			local success, text = self:PerformMute(
				commandMessage.guild, commandMessage.member, targetMember, duration, reason
			)
			commandMessage:reply(text)
		end,
		Slash = {
			Description = "Mute a member",
			Func = function (interaction, targetMember, duration, reason)
				local success, text = self:PerformMute(
					interaction.guild, interaction.member, targetMember, duration, reason
				)
				interaction:respond({
					type = enums.interactionResponseType.channelMessageWithSource,
					data = { content = text }
				})
			end
		},
		ContextMenu = {
			Type = "user",
			Func = function (interaction, targetMember)
				interaction:respond(BuildMuteModal(targetMember))
		end
		}
	})

	self:RegisterCommand({
		Name = "unmute",
		Args = {
			{ Name = "target", Type = Bot.ConfigType.User, Description = "Member to unmutes" },
			{ Name = "reason", Type = Bot.ConfigType.String, Description = "Unmutes reason", Optional = true }
		},
		PrivilegeCheck = function (member) return self:CheckPermissions(member) end,
		Help = "Unmutes a member",
		Silent = true,
		Func = function (commandMessage, targetUser, reason)
			local success, text = self:PerformUnmute(commandMessage.guild, commandMessage.member, targetUser, reason)
			commandMessage:reply(text)
		end,
		Slash = {
			Description = "Unmute a member",
			Func = function (interaction, targetUser, reason)
				local success, text = self:PerformUnmute(interaction.guild, interaction.member, targetUser, reason)
				interaction:respond(
					{ type = enums.interactionResponseType.channelMessageWithSource, data = { content = text } }
				)
			end
		},
		ContextMenu = {
			Type = "user",
			Func = function (interaction, targetUser)
				interaction:respond(BuildUnmuteModal(targetUser.user or targetUser))
			end
		}
	})

	return true
				end

function Module:OnInteractionCreate(interaction)
	if (interaction.type ~= enums.interactionRequestType.modalSubmit) then
		return
			end

	local guild = interaction.guild
	if (not guild) then
		return
			end

	local customId = interaction.data.custom_id
	local muteTargetId = customId:match("^mute_modal_(%d+)$")
	local unmuteTargetId = customId:match("^unmute_modal_(%d+)$")
	if (not muteTargetId and not unmuteTargetId) then
		return
		end

	if (not self:CheckPermissions(interaction.member)) then
		return interaction:respond({
			type = enums.interactionResponseType.channelMessageWithSource,
			data = { content = "You are not authorized to use this command.", flags = enums.interactionResponseFlag.ephemeral }
	})
	end

	local fields = Bot:ParseModalFields(interaction)
	local success, text
	if (muteTargetId) then
		local targetMember = guild:getMember(muteTargetId)
		local duration = Bot.ConfigTypeParameter[Bot.ConfigType.Duration](fields.duration or "", guild)
		success, text = self:PerformMute(guild, interaction.member, targetMember, duration, fields.reason)
	else
		local targetUser = Bot:DecodeUser(unmuteTargetId)
		success, text = self:PerformUnmute(guild, interaction.member, targetUser, fields.reason)
	end

	interaction:respond({
		type = enums.interactionResponseType.channelMessageWithSource,
		data = { content = text }
	})
end

function Module:OnEnable(guild)
	local config = self:GetConfig(guild)

	local muteRole = config.MuteRole and guild:getRole(config.MuteRole) or nil
	if (not muteRole) then
		return false, "Invalid mute role (check your configuration)"
	end

	self:LogInfo(guild, "Checking mute role permission on all channels...")

	for _, channel in pairs(guild.textChannels) do
		self:CheckTextMutePermissions(channel)
	end

	for _, channel in pairs(guild.voiceChannels) do
		self:CheckVoiceMutePermissions(channel)
	end

	local persistentData = self:GetPersistentData(guild)
	persistentData.MutedUsers = persistentData.MutedUsers or {}

	local data = self:GetData(guild)
	data.UnmuteTimers = {}

	for userId, unmuteTimestamp in pairs(persistentData.MutedUsers) do
		self:RegisterUnmute(guild, userId, unmuteTimestamp)
	end

	return true
end

function Module:OnDisable(guild)
	local data = self:GetData(guild)
	if (data.UnmuteTimers) then
		for userId, timer in pairs(data.UnmuteTimers) do
			timer:Stop()
		end
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
	deniedPermissions:enable(
		enums.permission.addReactions, enums.permission.sendMessages, enums.permission.usePublicThreads,
		enums.permission.sendMessagesInThreads
	)

	if permissions:getAllowedPermissions() ~= discordia.Permissions()
		or permissions:getDeniedPermissions() ~= deniedPermissions then
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

	if permissions:getAllowedPermissions() ~= discordia.Permissions()
		or permissions:getDeniedPermissions() ~= deniedPermissions then
		permissions:setPermissions('0', deniedPermissions)
	end
end

function Module:Mute(guild, userId, duration)
	local config = self:GetConfig(guild)
	local member = guild:getMember(userId)
	if (not member) then
		return false, bot:Format(guild, "MUTE_ERROR_NOT_PART_OF_GUILD", "<@" .. userId .. ">")
	end

	local success, err = member:addRole(config.MuteRole)
	if (not success) then
		self:LogError(guild, "failed to mute %s: %s", member.tag, err)
		return false, err
	end

	local persistentData = self:GetPersistentData(guild)
	local unmuteTimestamp = duration > 0 and os.time() + duration or 0
		
	persistentData.MutedUsers[userId] = unmuteTimestamp
	self:RegisterUnmute(guild, userId, unmuteTimestamp)

	return true
end

function Module:RegisterUnmute(guild, userId, timestamp)
	if (timestamp ~= 0) then
		local data = self:GetData(guild)
		local timer = data.UnmuteTimers[userId]
		if (timer) then
			timer:Stop()
		end

		data.UnmuteTimers[userId] = Bot:ScheduleTimer(timestamp, function ()
			self:Unmute(guild, userId)
		end)
	end
end

function Module:Unmute(guild, userId)
	local config = self:GetConfig(guild)

	local member = guild:getMember(userId)
	if (member) then
		local success, err = member:removeRole(config.MuteRole)
		if (not success) then
			self:LogError(guild, "Failed to unmute %s: %s", member.tag, err)
			return false, err
		end
	end

	local data = self:GetData(guild)
	local timer = data.UnmuteTimers[userId]
	if (timer) then
		timer:Stop()

		data.UnmuteTimers[userId] = nil
	end

	local persistentData = self:GetPersistentData(guild)
	persistentData.MutedUsers[userId] = nil

	return true
end

function Module:OnChannelCreate(channel)
	if (channel.type == enums.channelType.text) then
		self:CheckTextMutePermissions(channel)
	elseif (channel.type == enums.channelType.voice) then
		self:CheckVoiceMutePermissions(channel)
	end
end

function Module:OnMemberJoin(member)
	local guild = member.guild

	local config = self:GetConfig(guild)
	local persistentData = self:GetPersistentData(guild)
	if (persistentData.MutedUsers[member.id]) then
		local success, err = member:addRole(config.MuteRole, true)
		if (not success) then
			self:LogError(guild, "failed to apply mute role to %s: %s", member.tag, err)
		end
	end
end
