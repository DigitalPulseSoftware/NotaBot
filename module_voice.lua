-- Copyright (C) 2024 Mjöllnir#3515
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE


--[[
	This module allows a server member to create a private voice channel that cannot be joined by other members by
	default.
	The channel owner has the ability to invite other members to join.
	Administrators and authorized roles can still join this type of channel without an invitation from the owner.

	Usage:
		When a member joins a specific voice channel, a private voice channel is created with the appropriate
		permissions. The member is then moved there and becomes the owner of the channel. The channel owner can
		invite other members to join their channel.
		The private voice channel is automatically deleted when the channel owner disconnects.
		All roles listed in AuthorizedRoles will recieve the same permissions as the channel owner.
]]

--[[
	Storage Model

	{
		"PrivateVoiceChannels": {
			"<ChannelId>" : "<UserId>",
			...
		}
	}
]]


Module.Name = 'voice'

local EnumPermission      = Discordia.enums.permission
local EnumComponent       = Discordia.enums.componentType
local EnumInteractionType = Discordia.enums.interactionResponseType
local EnumInteractionFlag = Discordia.enums.interactionResponseFlag
local selectInteractionId = 'private_voice_invite'

function Module:GetConfigTable()
	return {
		{
			Name        = 'TriggerChannel',
			Description = 'The voice channel that members must join in order to create a private voice channel',
			Type        = Bot.ConfigType.Channel,
			Default     = false,
		},
		{
			Name        = 'AuthorizedRoles',
			Description = 'Authorized roles to join a private voice channel',
			Type        = Bot.ConfigType.Role,
			Default     = {},
			Array       = true,
			Optional    = true,
		}
	}
end


function Module:OnEnable(guild)
	local config = self:GetConfig(guild)

	if not config.TriggerChannel then
		return false, Bot:Format(guild, 'VOICE_MISCONFIG')
	end

	local persistentData = self:GetPersistentData(guild)
	if not persistentData.PrivateVoiceChannels then
		persistentData.PrivateVoiceChannels = {}

		return true
	end

--  cleanup config and unused channels after reboot
	for channelId, ownerId in pairs(persistentData.PrivateVoiceChannels) do
		local channel = guild.voiceChannels:find(
			function(voice) if voice.id == channelId then return voice end end
		)

		if channel then
			local isOwnerConnected = channel.connectedMembers:find(
				function(member) if member.id == ownerId then return true end end
			)

			if not isOwnerConnected then
				channel:delete()
				persistentData.PrivateVoiceChannels[channelId] = nil
				Client:info(string.format('[%s][%s] Deleted an unused channel %s', guild.name, Module.Name, channelId))
			end
		else
			persistentData.PrivateVoiceChannels[channelId] = nil
		end
	end

	Bot:Save()

	return true
end

function Module:OnvoiceChannelJoin(member, channel)
	local guild = channel.guild
	local category = channel.category
	local config = self:GetConfig(guild)
	local triggerChannelId = config.TriggerChannel


	if channel.id ~= triggerChannelId then
		return
	end

	local data = self:GetPersistentData(guild)

	local privateVoice
	local privateVoiceName = Bot:Format(guild, 'VOICE_CHAN_PREFIX') .. member.name
	if category then
		privateVoice = category:createVoiceChannel(privateVoiceName)
	else
		privateVoice = guild:createVoiceChannel(privateVoiceName)
	end

	local everyoneFilter = function(role) if role.name == '@everyone' then return role end end
	local everyone = guild.roles:find(everyoneFilter)
	local everyonePermissions = privateVoice:getPermissionOverwriteFor(everyone)

	everyonePermissions:denyPermissions(EnumPermission.connect)

	local ownerPermissions = privateVoice:getPermissionOverwriteFor(member)
	ownerPermissions:allowPermissions(
		EnumPermission.connect,
		EnumPermission.moveMembers,
		EnumPermission.setVoiceChannelStatus
	)

	for _, roleId in ipairs(config.AuthorizedRoles) do
		local role = guild:getRole(roleId)
		local rolePermissions = privateVoice:getPermissionOverwriteFor(role)
		rolePermissions:allowPermissions(
			EnumPermission.connect,
			EnumPermission.moveMembers,
			EnumPermission.setVoiceChannelStatus
		)
	end


	member:setVoiceChannel(privateVoice.id)

	local rowComponent = {
		type = EnumComponent.actionRow,
		components = {
			{
				type        = EnumComponent.userSelect,
				custom_id   = selectInteractionId,
				placeholder = Bot:Format(guild, 'VOICE_INTERAC_PLACEHOLDER'),
			}
		}
	}

	local messageData = {
		content = Bot:Format(guild, 'VOICE_MSG'),
		components = { rowComponent }
	}

	privateVoice:send(messageData)

	data.PrivateVoiceChannels[privateVoice.id] = member.id
	Bot:Save()
end

function Module:OnInteractionCreate(interaction)
	local interactionId = interaction.data.custom_id

	if interactionId ~= selectInteractionId then
		return
	end

	-- cannot use interaction.guild because it's a partial object
	local guild     = Client:getGuild(interaction.guild)
	local channel   = interaction.channel
	local selectionnedMembers = interaction.data.resolved.members

	-- cannot use map values (member) because they are partial objects
	for memberId, _ in pairs(selectionnedMembers) do
		local member = guild:getMember(memberId)
		local memberPermissions = channel:getPermissionOverwriteFor(member)

		memberPermissions:allowPermissions(EnumPermission.connect)
	end

	return interaction:respond({
		type = EnumInteractionType.channelMessageWithSource,
		data = {
			content = Bot:Format(guild, 'VOICE_CONFIRM'),
			flags = EnumInteractionFlag.ephemeral
		}
	})
end

function Module:OnvoiceChannelLeave(member, channel)
	local guild = channel.guild
	local data = self:GetPersistentData(guild)

	if not data.PrivateVoiceChannels[channel.id] then
		return
	end

	if member.id == data.PrivateVoiceChannels[channel.id] then
		-- will throw an HTTP error if a member with "manage" permission deletes the channel while connected
		channel:delete()
		data.PrivateVoiceChannels[channel.id] = nil
		Bot:Save()
	end
end
