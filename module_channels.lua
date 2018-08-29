-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local bot = Bot
local client = Client
local discordia = Discordia
local enums = discordia.enums

Module.Name = "channels"

function Module:GetConfigTable()
	return {
		{
			Name = "ChannelConfig",
			Description = "Map explaining which role to add/remove from which reaction on which message, use the !channelconfig command to setup this",
			Type = bot.ConfigType.Custom,
			Default = {}
		}
	}
end

function Module:OnLoaded()
	bot:RegisterCommand("channelconfig", "Configures the channel module messages and reactions", function (commandMessage)
		--[[if (not commandMessage.member:hasPermission(enums.permission.administrator)) then
			print(tostring(commandMessage.member.name) .. " tried to use !channelconfig")
			return
		end]]

		local guild = commandMessage.guild
		local config = self:GetConfig(guild)
		local data = self:GetData(guild)
		local channelConfig = config.ChannelConfig

		for channelId,messageTable in pairs(channelConfig) do
			local channel = guild:getChannel(channelId)
			if (channel) then
				for messageId,reactionTable in pairs(messageTable) do
					local message = channel:getMessage(messageId)
					if (message) then
						local fields = {}
						for k,reactionInfo in pairs(reactionTable) do
							local roleActions = self:GetReactionActions(guild, channelId, messageId, reactionInfo.reaction, true)
							assert(roleActions)

							local addedRoles = {}
							for _, roleId in pairs(roleActions.Add) do
								local role = guild:getRole(roleId)
								if (role) then
									table.insert(addedRoles, role.mentionString)
								else
									table.insert(addedRoles, "<invalid role " .. roleId .. ">") 
								end
							end

							local removedRoles = {}
							for _, roleId in pairs(roleActions.Remove) do
								local role = guild:getRole(roleId)
								if (role) then
									table.insert(removedRoles, role.mentionString)
								else
									table.insert(removedRoles, "<invalid role " .. roleId .. ">") 
								end
							end

							local actions = ""

							if (#addedRoles > 0) then
								actions = string.format("%s**Adds role%s**\n-  %s\n", actions, #addedRoles > 1 and "s" or "", table.concat(addedRoles, "\n-  "))
							end

							if (#removedRoles > 0) then
								actions = string.format("%s**Removes role%s:**\n-  %s\n", actions, #removedRoles > 1 and "s" or "", table.concat(removedRoles, "\n-  "))
							end

							if (roleActions.Message) then
								actions = string.format("%s**Sends private message:**\n\"%s\"\n", actions, roleActions.Message)
							end

							local emoji = bot:GetEmojiData(guild, reactionInfo.reaction)

							table.insert(fields, {
								name = emoji and emoji.MentionString or "<invalid emoji>",
								value = actions
							})
						end

						commandMessage:reply({
							embed = { 
								description = string.format("Message in %s:\n%s", channel.mentionString, bot:GenerateMessageLink(message)),
								fields = fields
							}
						})
					end
				end
			end
		end
	end)

	return true
end

function Module:OnUnload()
	bot:UnregisterCommand("channelconfig")
end

function Module:GetReactionActions(guild, channelId, messageId, reaction, noCreate)
	local reactionKey = string.format("%s_%s_%s", channelId, messageId, reaction)

	local data = self:GetData(guild)
	local roleActions = data.ReactionActions[reactionKey]
	if (not roleActions and not noCreate) then
		roleActions = {}
		roleActions.Add = {}
		roleActions.Remove = {}

		data.ReactionActions[reactionKey] = roleActions
	end

	return roleActions
end

function Module:OnEnable(guild)
	local config = self:GetConfig(guild)

	local data = self:GetData(guild)
	data.ReactionActions = {}

	local t1 = os.clock()

	local ProcessRole = function (channelId, messageId, reaction, roleId)
		local remove = false
		if (roleId:sub(1,1) == "-") then
			roleId = roleId:sub(2)
			remove = true
		end

		if (guild:getRole(roleId)) then
			local roleActions = self:GetReactionActions(guild, channelId, messageId, reaction)
			if (not remove) then
				table.insert(roleActions.Add, roleId)
			else
				table.insert(roleActions.Remove, roleId)
			end
		else
			self:LogWarning(guild, "Role %s not found", roleId)
		end
	end

	self:LogInfo(guild, "Processing roles...")

	for channelId,messagetable in pairs(config.ChannelConfig) do
		for messageId,reactionTable in pairs(messagetable) do
			for k,reactionInfo in pairs(reactionTable) do
				if (reactionInfo.roles) then
					for k,roleId in pairs(reactionInfo.roles) do
						ProcessRole(channelId, messageId, reactionInfo.reaction, roleId)
					end
				end

				if (reactionInfo.message) then
					local roleActions = self:GetReactionActions(guild, channelId, messageId, reactionInfo.reaction)
					roleActions.Message = reactionInfo.message
				end
			end
		end
	end

	self:LogInfo(guild, "Adding emojis to concerned messages...")

	-- Make sure reactions are present on messages
	for channelId,messagetable in pairs(config.ChannelConfig) do
		local channel = guild:getChannel(channelId)
		for messageId,reactionTable in pairs(messagetable) do
			local message = channel:getMessage(messageId)
			
			local hasReaction = {}
			for k,reaction in pairs(message.reactions) do
				if (reaction.me) then
					local emoji = bot:GetEmojiData(guild, reaction.emojiName)
					if (emoji) then
						hasReaction[emoji.Name] = true
					else
						self:LogError(guild, "Found reaction which does not exist in guild: %s", reaction.emojiName)
					end
				end
			end
			
			for k,reactionInfo in pairs(reactionTable) do
				local emoji = bot:GetEmojiData(guild, reactionInfo.reaction)
				if (emoji) then
					if (not hasReaction[emoji.Name] and not message:addReaction(emoji)) then
						self:LogWarning(guild, "Failed to add reaction %s on message %s (channel: %s)", tostring(emojiName), message.id, message.channel.id)
					end
				else
					self:LogError(guild, "Emoji \"%s\" does not exist", reactionInfo.reaction)
				end
			end
		end
	end

	return true
end

function Module:HandleReactionAdd(guild, userId, channelId, messageId, reactionName)
	if (client.user.id == userId) then
		return
	end

	local roleActions = self:GetReactionActions(guild, channelId, messageId, reactionName, true)
	if (not roleActions) then
		return
	end

	local member = guild:getMember(userId)

	for k,roleId in pairs(roleActions.Add) do
		local role = guild:getRole(roleId)
		if (role) then
			self:LogInfo(guild, "Adding %s%s to %s", role.name, (role.color ~= 0) and " (colored)" or "", member.tag)
			if (not member:addRole(roleId)) then
				self:LogWarning(guild, "Failed to add role % to %s", role.name, member.tag)
			end
		else
			self:LogWarning(guild, "Role %s appears to have been removed", roleId)
		end
	end

	for k,roleId in pairs(roleActions.Remove) do
		local role = guild:getRole(roleId)
		if (role) then
			self:LogInfo(guild, "Removing %s%s from %s", role.name, (role.color ~= 0) and " (colored)" or "", member.tag)
			if (not member:removeRole(roleId)) then
				self:LogWarning(guild, "Failed to remove role % from %s", role.name, member.tag)
			end
		else
			self:LogWarning(guild, "Role %s appears to have been removed", roleId)
		end
	end

	if (roleActions.Message) then
		local privateChannel = member.user:getPrivateChannel()
		if (privateChannel) then
			local message = privateChannel:send(string.format("[From %s]\n%s", guild.name, roleActions.Message))
			if (not message) then
				self:LogWarning(guild, "Failed to send reaction message to %s (maybe user disabled private messages from this server?)", targetMember.user.tag)
			end
		else
			self:LogWarning(guild, "Failed to get private channel with %s", targetMember.user.tag)
		end
	end
end

function Module:HandleReactionRemove(guild, userId, channelId, messageId, reactionName)
	if (client.user.id == userId) then
		return
	end

	local roleActions = self:GetReactionActions(guild, channelId, messageId, reactionName, true)
	if (not roleActions) then
		return
	end

	local member = guild:getMember(userId)

	for k,roleId in pairs(roleActions.Add) do
		local role = guild:getRole(roleId)
		if (role) then
			self:LogInfo(guild, "Removing %s%s from %s", role.name, (role.color ~= 0) and " (colored)" or "", member.tag)
			if (not member:removeRole(roleId)) then
				self:LogWarning(guild, "Failed to remove role % from %s", role.name, member.tag)
			end
		else
			self:LogWarning(guild, "Role %s appears to have been removed", roleId)
		end
	end

	for k,roleId in pairs(roleActions.Remove) do
		local role = guild:getRole(roleId)
		if (role) then
			self:LogInfo(guild, "Adding back %s%s to %s", role.name, (role.color ~= 0) and " (colored)" or "", member.tag)
			if (not member:addRole(roleId)) then
				self:LogWarning(guild, "Failed to add role % to %s", role.name, member.tag)
			end
		else
			self:LogWarning(guild, "Role %s appears to have been removed", roleId)
		end
	end
end

function Module:OnReactionAdd(reaction, userId)
	if (reaction.message.channel.type ~= enums.channelType.text) then
		return
	end

	local emoji = bot:GetEmojiData(reaction.message.guild, reaction.emojiName)
	if (not emoji) then
		self:LogWarning(reaction.message.guild, "Emoji %s was used but not found in guild", reaction.emojiName)
		return
	end

	self:HandleReactionAdd(reaction.message.channel.guild, userId, reaction.message.channel.id, reaction.message.id, emoji.Name)
end

function Module:OnReactionAddUncached(channel, messageId, reactionIdOrName, userId)
	if (channel.type ~= enums.channelType.text) then
		return
	end

	local emoji = bot:GetEmojiData(channel.guild, reactionIdOrName)
	if (not emoji) then
		self:LogWarning(channel.guild, "Emoji %s was used but not found in guild", reactionIdOrName)
		return
	end

	self:HandleReactionAdd(channel.guild, userId, channel.id, messageId, emoji.Name)
end

function Module:OnReactionRemove(reaction, userId)
	if (reaction.message.channel.type ~= enums.channelType.text) then
		return
	end

	local emoji = bot:GetEmojiData(reaction.message.guild, reaction.emojiName)
	if (not emoji) then
		self:LogWarning(reaction.message.guild, "Emoji %s was used but not found in guild", reaction.emojiName)
		return
	end

	self:HandleReactionRemove(reaction.message.channel.guild, userId, reaction.message.channel.id, reaction.message.id, emoji.Name)
end

function Module:OnReactionRemoveUncached(channel, messageId, reactionIdOrName, userId)
	if (channel.type ~= enums.channelType.text) then
		return
	end

	local emoji = bot:GetEmojiData(channel.guild, reactionIdOrName)
	if (not emoji) then
		self:LogWarning(channel.guild, "Emoji %s was used but not found in guild", reactionIdOrName)
		return
	end

	self:HandleReactionRemove(channel.guild, userId, channel.id, messageId, emoji.Name)
end
