-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local client = Client
local discordia = Discordia
local bot = Bot
local enums = discordia.enums

Module.Name = "kick"

function Module:CheckPermissions(member)
	local config = self:GetConfig(member.guild)
	for _,roleId in pairs(config.AuthorizedRoles) do
		if (member:hasRole(roleId)) then
			return true
		end
	end

	return member:hasPermission(enums.permission.kickMembers)
end

function Module:GetConfigTable()
	return {
		{
			Name = "PrivateMessage",
			Description = "If set, the bot will try to send a private message before kicking the user.\nAvailable variables: {guild}, {user}, {reason}.",
			Type = bot.ConfigType.String,
			Default = "You have been kicked from {guild} by {user}: {reason}",
			Optional = true
		},
		{
			Name = "AuthorizedRoles",
			Description = "Roles which can use the kick command (not required if user/role has kick member permission)",
			Type = bot.ConfigType.Role,
			Default = {},
			Array = true
		}
	}
end

function Module:OnLoaded()
	self:RegisterCommand({
		Name = "kick",
		Args = {
			{Name = "target", Type = Bot.ConfigType.Member},
			{Name = "reason", Type = Bot.ConfigType.String, Optional = true},
		},
		PrivilegeCheck = function (member) return self:CheckPermissions(member) end,

		Help = "Kicks a member",
		Silent = true,
		Func = function (commandMessage, targetMember, reason)
			local config = self:GetConfig(commandMessage.guild)

			local guild = commandMessage.guild
			local kickedBy = commandMessage.member

			-- Permission check
			local kickedByRole = kickedBy.highestRole
			local targetRole = targetMember.highestRole
			if (targetRole.position > kickedByRole.position) then
				commandMessage:reply("You cannot kick that user due to your lower permissions.")
				return
			end

			if (config.PrivateMessage) then
				local privateChannel = targetMember.user:getPrivateChannel()
				if (privateChannel) then
					local message = config.PrivateMessage
					message = message:gsub("{guild}", guild.name)
					message = message:gsub("{user}", kickedBy.mentionString)
					message = message:gsub("{reason}", reason or "no reason given")

					privateChannel:send(message)
				end
			end

			if (targetMember:kick(string.format("Kicked by %s%s", kickedBy.mentionString, reason and string.format(": %s", reason) or ""))) then
				commandMessage:reply(string.format("%s has kicked %s%s", kickedBy.user.tag, targetMember.user.tag, reason and string.format(": %s", reason) or ""))
			else
				commandMessage:reply(string.format("Failed to kick %s", targetMember.user.tag))
			end
		end
	})

	return true
end
