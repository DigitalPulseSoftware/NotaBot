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

function Module:PerformKick(guild, kickedBy, targetMember, reason)
	local config = self:GetConfig(guild)

			-- Permission check
			local kickedByRole = kickedBy.highestRole
			local targetRole = targetMember.highestRole
			if (targetRole.position >= kickedByRole.position) then
		return false, "You cannot kick that user due to your lower permissions."
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
		return true, string.format("%s has kicked %s%s", kickedBy.user.tag, targetMember.user.tag, reason and string.format(": %s", reason) or "")
			else
		return false, string.format("Failed to kick %s", targetMember.user.tag)
	end
			end

local function BuildKickModal(targetMember)
	return {
		type = enums.interactionResponseType.modal,
		data = {
			custom_id = "kick_modal_" .. targetMember.id,
			title = "Kick " .. targetMember.tag,
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
		Name = "kick",
		Args = {
			{ Name = "target", Type = Bot.ConfigType.Member, Description = "Member to kick" },
			{ Name = "reason", Type = Bot.ConfigType.String, Description = "Kick reason", Optional = true }
		},
		PrivilegeCheck = function (member) return self:CheckPermissions(member) end,

		Help = "Kicks a member",
		Silent = true,
		Func = function (commandMessage, targetMember, reason)
			local success, text = self:PerformKick(commandMessage.guild, commandMessage.member, targetMember, reason)
			commandMessage:reply(text)
		end,
		Slash = {
			Description = "Kick a member",
			Func = function (interaction, targetMember, reason)
				local success, text = self:PerformKick(interaction.guild, interaction.member, targetMember, reason)
				interaction:respond({
					type = enums.interactionResponseType.channelMessageWithSource,
					data = { content = text }
				})
			end
		},
		ContextMenu = {
			Type = "user",
			Func = function (interaction, targetMember)
				interaction:respond(BuildKickModal(targetMember))
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
	local kickTargetId = customId:match("^kick_modal_(%d+)$")
	if (not kickTargetId) then
		return
	end

	if (not self:CheckPermissions(interaction.member)) then
		return interaction:respond({
			type = enums.interactionResponseType.channelMessageWithSource,
			data = { content = "You are not authorized to use this command.", flags = enums.interactionResponseFlag.ephemeral }
		})
	end

	local fields = Bot:ParseModalFields(interaction)
	local targetMember = guild:getMember(kickTargetId)
	local success, text = self:PerformKick(guild, interaction.member, targetMember, fields.reason)

	interaction:respond({
		type = enums.interactionResponseType.channelMessageWithSource,
		data = { content = text }
	})
end
