-- Copyright (C) 2023 Mjöllnir#3515
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

-- API limitations on bulk deletion:
-- It is not possible to delete less than 2 messages or more than 100 messages at a time
-- It is not possible to delete messages older than 14 days
-- getMessagesBefore and getMessagesAfter have also a limitation to 100 messages at a time

local Date = Discordia.Date
local Enums = Discordia.enums

local MSG_TIME_LIMIT    = 1209600 -- seconds
local NB_MSG_MAX_LIMIT  = 100

Module.Name = "prune"

function Module:GetConfigTable()
	return {
		{
			Name = "Silent",
			Description = "Delete the command message used to invoke prunefrom",
			Type = Bot.ConfigType.Boolean,
			Default = true
		}
	}
end

local function bulkDeleteChunks(channel, messagesChunks)
	local nbDeletedMessages = 0

	for _, chunk in ipairs(messagesChunks) do
		if #chunk > 1 then
			channel:bulkDelete(chunk)
			nbDeletedMessages = nbDeletedMessages + #chunk
		else
			chunk[1]:delete()
			nbDeletedMessages = nbDeletedMessages + 1
		end
	end

	return nbDeletedMessages
end

local function hasValidDate(message)
	local messageTimestamp = Date.fromSnowflake(message.id):toSeconds()
	return os.difftime(os.time(), messageTimestamp) < MSG_TIME_LIMIT
end

local function hasManagePermission(member)
	return member:hasPermission(Enums.permission.manageMessages)
end

function Module:bulkDeleteByNumber(commandMessage, nbMessages)
	local channel = commandMessage.channel
	local currentMessageId = commandMessage.id

	local messagesToDelete = {}
	local quotient = math.floor(nbMessages / NB_MSG_MAX_LIMIT)
	local remainder = nbMessages - quotient * NB_MSG_MAX_LIMIT
	for _ = 1, quotient do
		local messages = channel:getMessagesBefore(currentMessageId, NB_MSG_MAX_LIMIT):toArray("id", hasValidDate)

		if next(messages) ~= nil then
			table.insert(messagesToDelete, messages)
			currentMessageId = messages[1].id
		end
	end

	if remainder > 0 then
		table.insert(
			messagesToDelete, channel:getMessagesBefore(currentMessageId, remainder):toArray("id", hasValidDate)
		)
	end

	return bulkDeleteChunks(channel, messagesToDelete)
end

function Module:bulkDeleteById(channel, targetMessage, trimInvokingMessage)
	local currentMessageId = targetMessage.id

	local messagesToDelete = {}
	local messages
	repeat
		messages = channel:getMessagesAfter(currentMessageId, NB_MSG_MAX_LIMIT):toArray("id", hasValidDate)
		if next(messages) ~= nil then
			table.insert(messagesToDelete, messages)
			currentMessageId = messages[#messages].id
		end
	until next(messages) == nil

	-- Text command invocation posts a message right after the range we just fetched; strip it.
	-- Context-menu invocations don't post one, so this must stay conditional.
	if (trimInvokingMessage) then
	table.remove(messagesToDelete[#messagesToDelete], #messagesToDelete[#messagesToDelete])
	end

	-- Delete also the selected message
	if hasValidDate(targetMessage) then
		table.insert(messagesToDelete[#messagesToDelete], targetMessage)
	end

	return bulkDeleteChunks(channel, messagesToDelete)
end

function Module:OnLoaded()
	self:RegisterCommand({
		Name = "prune",
		Args = {
			{ Name = "nbOfMessages", Type = Bot.ConfigType.Integer, Description = "Number of recent messages to delete" }
		},
		PrivilegeCheck = hasManagePermission,
		Help = function (guild) return Bot:Format(guild, "PRUNE_HELP") end,
		Silent = true,
		Func = function (commandMessage, nbMessages)
			local guild = commandMessage.guild

			local nbDeletedMessages = self:bulkDeleteByNumber(commandMessage, nbMessages)
			local response = ""
			if nbDeletedMessages ~= nbMessages then
				response = string.format("%s\n", Bot:Format(guild, "PRUNE_CANNOT_DELETE"))
			end
			response = response .. Bot:Format(guild, "PRUNE_RESULT", nbDeletedMessages)

			return commandMessage:reply(response)
		end,
		Slash = {
			Description = "Delete a number of recent messages in this channel",
			Func = function (interaction, nbMessages)
				local guild = interaction.guild

				interaction:respond({ type = Enums.interactionResponseType.deferredChannelMessageWithSource })

				local nbDeletedMessages = self:bulkDeleteByNumber(interaction, nbMessages)
				local response = ""
				if nbDeletedMessages ~= nbMessages then
					response = string.format("%s\n", Bot:Format(guild, "PRUNE_CANNOT_DELETE"))
				end
				response = response .. Bot:Format(guild, "PRUNE_RESULT", nbDeletedMessages)

				interaction:editResponse({ content = response })
		end
		}
	})

	self:RegisterCommand({
		Name = "prunefrom",
		Args = {
			{ Name = "messageId", Type = Bot.ConfigType.Message }
		},
		PrivilegeCheck = hasManagePermission,
		Help = function (guild) return Bot:Format(guild, "PRUNEFROM_HELP") end,
		Func = function (commandMessage, targetMessage)
			local guild = commandMessage.guild
			local config = self:GetConfig(guild)
			local nbDeletedMessages = self:bulkDeleteById(commandMessage.channel, targetMessage, config.Silent)

			local response = ""
			if not hasValidDate(targetMessage) then
				response = string.format("%s\n", Bot:Format(guild, "PRUNE_CANNOT_DELETE"))
			end

			response = response .. Bot:Format(guild, "PRUNE_RESULT", nbDeletedMessages)

			return commandMessage:reply(response)
		end,
		ContextMenu = {
			Type = "message",
			Func = function (interaction, targetMessage)
				local guild = interaction.guild

				interaction:respond({
					type = Enums.interactionResponseType.deferredChannelMessageWithSource
				})

				local nbDeletedMessages = self:bulkDeleteById(interaction.channel, targetMessage, false)

				local response = ""
				if not hasValidDate(targetMessage) then
					response = string.format("%s\n", Bot:Format(guild, "PRUNE_CANNOT_DELETE"))
				end

				response = response .. Bot:Format(guild, "PRUNE_RESULT", nbDeletedMessages)

				interaction:editResponse({ content = response })
		end
		}
	})

	return true
end
