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
			Description = "Roles allowed to create polls",
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
	return util.MemberHasAnyRole(member, config.AuthorizedRoles)
end

function Module:OnLoaded()
	self:RegisterCommand({
		Name = "mute",
		Args = {
			{Name = "target", Type = Bot.ConfigType.Member},
			{Name = "duration", Type = Bot.ConfigType.Duration, Optional = true},
			{Name = "reason", Type = Bot.ConfigType.String, Optional = true},
		},
		PrivilegeCheck = function (member) return self:CheckPermissions(member) end,

		Help = "Mutes a member",
		Func = function (commandMessage, targetMember, duration, reason)
			local guild = commandMessage.guild
			local config = self:GetConfig(guild)
			local mutedBy = commandMessage.member

			-- Duration
			if (not duration) then
				duration = config.DefaultMuteDuration
			end

			local durationStr = util.FormatTime(duration, 3)

			-- Reason
			reason = reason or ""

			local mutedByRole = mutedBy.highestRole
			local targetRole = targetMember.highestRole
			if (targetRole.position > mutedByRole.position) then
				commandMessage:reply("You cannot mute that user due to your lower permissions.")
				return
			end

			if (config.SendPrivateMessage) then
				local privateChannel = targetMember:getPrivateChannel()
				if (privateChannel) then
					local durationText
					if (duration > 0) then
						durationText = string.format("You will be unmuted in %s", duration > 0 and durationStr or "")
					else
						durationText = ""
					end

					privateChannel:send(string.format("You have been muted from **%s** by %s (%s)\n%s", commandMessage.guild.name, mutedBy.user.mentionString, #reason > 0 and ("reason: " .. reason) or "no reason given", durationText))
				end
			end

			local success, err = self:Mute(guild, targetMember.id, duration)
			if (success) then
				commandMessage:reply(string.format("%s has muted %s (%s)%s", mutedBy.name, targetMember.tag, duration > 0 and ("for " .. durationStr) or "permanent", #reason > 0 and (" for the reason: " .. reason) or ""))
			else
				commandMessage:reply(string.format("Failed to mute %s: %s", targetMember.tag, err))
			end
		end
	})

	self:RegisterCommand({
		Name = "unmute",
		Args = {
			{Name = "target", Type = Bot.ConfigType.User},
			{Name = "reason", Type = Bot.ConfigType.String, Optional = true},
		},
		PrivilegeCheck = function (member) return self:CheckPermissions(member) end,

		Help = "Unmutes a member",
		Func = function (commandMessage, targetUser, reason)
			local guild = commandMessage.guild
			local config = self:GetConfig(guild)

			-- Reason
			reason = reason or ""

			if (config.SendPrivateMessage) then
				local privateChannel = targetUser:getPrivateChannel()
				if (privateChannel) then
					privateChannel:send(string.format("You have been unmuted from **%s** by %s (%s)", commandMessage.guild.name, commandMessage.member.user.mentionString, #reason > 0 and ("reason: " .. reason) or "no reason given"))
				end
			end

			local success, err = self:Unmute(guild, targetUser.id)
			if (success) then
				commandMessage:reply(string.format("%s has unmuted %s%s", commandMessage.member.name, targetUser.tag, #reason > 0 and (" for the reason: " .. reason) or ""))
			else
				commandMessage:reply(string.format("Failed to unmute %s: %s", targetUser.tag, err))
			end
		end
	})

	return true
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
	for userId, timer in pairs(data.UnmuteTimers) do
		timer:Stop()
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

function Module:Mute(guild, userId, duration)
	local config = self:GetConfig(guild)
	local member = guild:getMember(userId)
	if (not member) then
		return false, "not part of guild"
	end

	local success, err = member:addRole(config.MuteRole)
	if (not success) then
		self:LogError(guild, "Failed to mute %s: %s", member.tag, err)
		return false, "failed to mute user: " .. err
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

		data.UnmuteTimers[userId] = Bot:ScheduleAction(timestamp, function () self:Unmute(guild, userId) end)
	end
end

function Module:Unmute(guild, userId)
	local config = self:GetConfig(guild)

	local member = guild:getMember(userId)
	if (member) then
		local success, err = member:removeRole(config.MuteRole)
		if (not success) then
			self:LogError(guild, "Failed to unmute %s: %s", member.tag, err)
			return false, "failed to unmute user: " .. err
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

	return false
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
		local success, err = member:addRole(config.MuteRole)
		if (not success) then
			self:LogError(guild, "Failed to apply mute role to %s: %s", member.tag, err)
		end
	end
end
