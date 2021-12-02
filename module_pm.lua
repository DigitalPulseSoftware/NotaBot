-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local client = Client
local discordia = Discordia
local bot = Bot
local enums = discordia.enums

Module.Global = true
Module.Name = "pm"

function Module:GetConfigTable()
	return {
		{
			Global = true,
			Name = "TargetChannel",
			Description = "Where private messages should be logged",
			Type = bot.ConfigType.Channel,
			Optional = true
		}
	}
end

function Module:HandleResponse(message)
	local function Failure(text, ...)
		message:reply({
			content = string.format("❌ " .. text, ...),
			reference = {
				message = message,
				mention = true
			}
		})
	end

	if message.type ~= enums.messageType.reply then
		return Failure("You must reply to a message so I know whom to send your message")
	end

	local mirrorMessage = message.referencedMessage
	if not mirrorMessage then
		return Failure("Failed to retrieve referenced message, maybe its too old?")
	end

	local mirrorMessageId = mirrorMessage.id

	local persistentData = self:GetPersistentData()
	local mirrorData = persistentData.mirrors[mirrorMessageId]
	p(mirrorData)

	if not mirrorData then
		return Failure("Failed to identify message, maybe its too old?")
	end

	local user, err = client:getUser(mirrorData.userId)
	if not user then
		return Failure("Failed to get user: %s", err)
	end

	local privateMessageChannel, err = user:getPrivateChannel()
	if not privateMessageChannel then
		return Failure("Failed to get private channel: %s", err)
	end

	local authorData = persistentData.users[mirrorData.userId]
	if not authorData then
		return Failure("An internal error occurred (no author data found)")
	end

	local reply, err = privateMessageChannel:send({
		attachments = message.attachments,
		content = message.content,
		reference = {
			message = authorData.lastMessageId ~= mirrorData.messageId and mirrorData.messageId or nil -- only reply if we're answering another message than the last one
		}
	})

	if not reply then
		return Failure("Failed to send reply to user: %s", err)
	end

	local success, err = message:addReaction("✅")
	if not success then
		self:LogError("failed to add confirmation reaction to message: %s", err)
	end
end

function Module:HandlePrivateMessage(message)
	if not self.GlobalConfig.TargetChannel then
		return
	end

	local logChannel = client:getChannel(self.GlobalConfig.TargetChannel)
	if not logChannel then
		self:LogError("invalid target channel (%s)", self.GlobalConfig.TargetGuild)
		return
	end

	local authorId = message.author.id
	local messageId = message.id

	local embed = Bot:BuildQuoteEmbed(message)
	embed.footer = {
		text = string.format("Author ID: %s | Message ID: %s", authorId, messageId)
	}

	local mirrorMessage, err = logChannel:send({
		embed = embed
	})
	if not mirrorMessage then
		self:LogError("failed to log private message: %s", err)
		return
	end

	local mirrorMessageId = mirrorMessage.id

	local persistentData = self:GetPersistentData()
	persistentData.mirrors[mirrorMessageId] = {
		userId = authorId,
		messageId = messageId
	}

	local authorData = persistentData.users[authorId]
	if not authorData then
		authorData = {
			mirrorMessages = {}
		}
		persistentData.users[authorId] = authorData
	end

	authorData.lastMessageId = messageId
	table.insert(authorData.mirrorMessages, mirrorMessageId)

	-- Keep only 100 previous message IDs per user (just in case)
	while #authorData.mirrorMessages > 100 do
		local mirrorMessageId = table.remove(authorData.mirrorMessages, 1)
		persistentData.mirrors[mirrorMessageId] = nil
	end
end

function Module:OnLoaded()
	local persistentData = self:GetPersistentData()
	persistentData.mirrors = persistentData.mirrors or {}
	persistentData.users = persistentData.users or {}

	return true
end

function Module:OnMessageCreate(message)
	local channel = message.channel
	if not channel then
		return
	end

	if (message.author.bot) then
		return
	end

	if channel.type == enums.channelType.private then
		self:HandlePrivateMessage(message)
	elseif channel.id == self.GlobalConfig.TargetChannel then
		self:HandleResponse(message)
	end
end
