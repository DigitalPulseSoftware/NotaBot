-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local bot = Bot
local client = Client
local discordia = Discordia
local enums = discordia.enums

discordia.extensions() -- load all helpful extensions

Module.Name = "channels"

function Module:GetConfigTable()
	return {
		{
			Name = "ReactionActions",
			Description = "Map explaining which role to add/remove from which reaction on which message, use the !channelconfig command to setup this",
			Type = bot.ConfigType.Custom,
			Default = {}
		}
	}
end

function Module:OnLoaded()
	self:RegisterCommand({
		Name = "channelconfig",
		Args = {
			{Name = "configMessage", Type = Bot.ConfigType.Message, Optional = true}
		},
		PrivilegeCheck = function (member) return member:hasPermission(enums.permission.administrator) end,

		Help = "Lists the channel module messages and reactions",
		Func = function (commandMessage, configMessage)
			local guild = commandMessage.guild
			local config = self:GetConfig(guild)
			local data = self:GetData(guild)

			local channelConfig = config.ReactionActions
			for channelId,messageTable in pairs(channelConfig) do
				local channel = guild:getChannel(channelId)
				if (channel) then
					for messageId,reactionTable in pairs(messageTable) do
						local message = channel:getMessage(messageId)
						if (message and (not configMessage or configMessage.id == message.id)) then
							local fields = {}
							for emoji,actions in pairs(reactionTable) do
								local actionStr = ""

								if (actions.AddRoles) then
									local addedRoles = {}
									for _, roleId in pairs(actions.AddRoles) do
										local role = guild:getRole(roleId)
										if (role) then
											table.insert(addedRoles, role.mentionString)
										else
											table.insert(addedRoles, "<invalid role " .. roleId .. ">") 
										end
									end

									if (#addedRoles > 0) then
										actionStr = string.format("%s**Adds role%s** %s\n", actionStr, #addedRoles > 1 and "s" or "", table.concat(addedRoles, ", "))
									end
								end

								if (actions.RemoveRoles) then
									local removedRoles = {}
									for _, roleId in pairs(actions.RemoveRoles) do
										local role = guild:getRole(roleId)
										if (role) then
											table.insert(removedRoles, role.mentionString)
										else
											table.insert(removedRoles, "<invalid role " .. roleId .. ">") 
										end
									end

									if (#removedRoles > 0) then
										actionStr = string.format("%s**Removes role%s** %s\n", actionStr, #removedRoles > 1 and "s" or "", table.concat(removedRoles, ", "))
									end
								end

								if (actions.SendMessage) then
									actionStr = string.format("%s**Sends private message:**\n\"%s\"\n", actionStr, actions.SendMessage)
								end

								local emoji = bot:GetEmojiData(guild, emoji)

								table.insert(fields, {
									name = string.format("- %s:", emoji and emoji.MentionString or "<invalid emoji>"),
									value = actionStr
								})
							end

							commandMessage:reply({
								embed = { 
									description = string.format("Message in %s:\n%s", channel.mentionString, bot:GenerateMessageLink(message)),
									fields = fields,
									footer = {
										text = "Use `!updatechannelconfig <message link> <emoji> <action>` to update channels reactions settings."
									}
								}
							})
						end
					end
				end
			end
		end
	})

	self:RegisterCommand({
		Name = "updatechannelconfig",
		Args = {
			{Name = "message", Type = Bot.ConfigType.Message},
			{Name = "emoji", Type = Bot.ConfigType.Emoji},
			{Name = "action", Type = Bot.ConfigType.String},
			{Name = "value", Type = Bot.ConfigType.String, Optional = true}
		},
		PrivilegeCheck = function (member) return member:hasPermission(enums.permission.administrator) end,

		Help = "Configures the channel module messages and reactions",
		Func = function (commandMessage, message, emoji, action, value)
			local guild = commandMessage.guild
			local config = self:GetConfig(guild)

			local GetReactionActionsConfig = function (channelId, messageId, reaction, noCreate)
				local guildConfig = config.ReactionActions

				local channelTable = guildConfig[channelId]
				if (not channelTable) then
					if (noCreate) then
						return
					end

					channelTable = {}
					guildConfig[channelId] = channelTable
				end

				local messageTable = channelTable[messageId]
				if (not messageTable) then
					if (noCreate) then
						return
					end

					messageTable = {}
					channelTable[messageId] = messageTable
				end

				local reactionActions = messageTable[reaction]
				if (not reactionActions) then
					if (noCreate) then
						return
					end

					reactionActions = {}
					messageTable[reaction] = reactionActions
				end

				return reactionActions
			end

			local success = false

			if (action == "addrole") then
				local role = guild:getRole(value)
				if (not role) then
					commandMessage:reply(string.format("Invalid role %s", value))
					return
				end

				local roleValue = tostring(role.id)

				local reactionActions = GetReactionActionsConfig(message.channel.id, message.id, emoji.Name)
				if (reactionActions.AddRoles) then
					local found = false
					for _, role in pairs(reactionActions.AddRoles) do
						if (role == roleValue) then
							found = true
							break
						end
					end

					if (reactionActions.RemoveRoles) then
						for key, role in pairs(reactionActions.RemoveRoles) do
							if (role == roleValue) then
								table.remove(reactionActions.RemoveRoles, key)
							end
						end
					end

					if (not found) then
						table.insert(reactionActions.AddRoles, tostring(role.id))
					end
				else
					reactionActions.AddRoles = {roleValue}
				end

				success = true
				commandMessage:reply(string.format("Reactions on %s for %s will now adds role %s (%s)", Bot:GenerateMessageLink(message), emoji.MentionString, role.name, role.id))
			elseif (action == "removerole") then
				local role = guild:getRole(value)
				if (not role) then
					commandMessage:reply(string.format("Invalid role %s", value))
					return
				end

				local roleValue = tostring(role.id)

				local reactionActions = GetReactionActionsConfig(message.channel.id, message.id, emoji.Name)
				if (reactionActions.RemoveRoles) then
					local found = false
					for _, role in pairs(reactionActions.RemoveRoles) do
						if (role == roleValue) then
							found = true
							break
						end
					end

					if (reactionActions.AddRoles) then
						for key, role in pairs(reactionActions.AddRoles) do
							if (role == roleValue) then
								table.remove(reactionActions.AddRoles, key)
							end
						end
					end

					if (not found) then
						table.insert(reactionActions.RemoveRoles, tostring(role.id))
					end
				else
					reactionActions.RemoveRoles = {roleValue}
				end

				success = true
				commandMessage:reply(string.format("Reactions on %s for %s will now remove role %s (%s)", Bot:GenerateMessageLink(message), emoji.MentionString, role.name, role.id))
			elseif (action == "send") then
				if (not value) then
					commandMessage:reply("Empty message")
					return
				end

				local reactionActions = GetReactionActionsConfig(message.channel.id, message.id, emoji.Name)
				reactionActions.SendMessage = value

				success = true
				commandMessage:reply(string.format("Reactions on %s for %s will now send private message: %s", Bot:GenerateMessageLink(message), emoji.MentionString, value))
			elseif (action == "clear") then
				local reactionActions = GetReactionActionsConfig(message.channel.id, message.id, emoji.Name, true)
				if (reactionActions) then
					reactionActions.AddRoles = nil
					reactionActions.RemoveRoles = nil
					reactionActions.SendMessage = nil
				end

				success = true
				commandMessage:reply(string.format("Reactions actions on %s for %s have been cleared", Bot:GenerateMessageLink(message), emoji.MentionString))
			else
				commandMessage:reply("Invalid action (must be addrole/clear/removerole/send)")
			end

			if (success) then
				self:SaveGuildConfig(guild)
				commandMessage:reply(string.format("Configuration of module %s has been saved, use the `!reload %s` command to activate it", self.Name, self.Name))
			end
		end
	})
	return true
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

	--[[if (config.ChannelConfig) then
		self:LogInfo(guild, "Converting old config format to new config format...")

		local guildConfig = {}
		for channelId,messagetable in pairs(config.ChannelConfig) do
			local channelMessages = {}
			guildConfig[channelId] = channelMessages

			for messageId,reactionTable in pairs(messagetable) do
				local messageActions = {}
				channelMessages[messageId] = messageActions

				for k,reactionInfo in pairs(reactionTable) do
					local reactionActions = {}
					messageActions[reactionInfo.reaction] = reactionActions

					if (reactionInfo.roles) then
						for k,roleId in pairs(reactionInfo.roles) do
							if (roleId:sub(1,1) ~= "-") then
								reactionActions.AddRoles = reactionActions.AddRoles or {}
								table.insert(reactionActions.AddRoles, roleId)
							else
								roleId = roleId:sub(2)

								reactionActions.RemoveRoles = reactionActions.RemoveRoles or {}
								table.insert(reactionActions.RemoveRoles, roleId)
							end
						end
					end

					if (reactionInfo.message) then
						reactionActions.SendMessage = reactionInfo.message
					end
				end
			end
		end
		config.ReactionActions = guildConfig

		config.ChannelConfig = nil
		self:SaveConfig(guild)
	end]]

	self:LogInfo(guild, "Processing roles...")

	local ProcessRole = function (channelId, messageId, reaction, roleId, remove)
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

	for channelId,messageTable in pairs(config.ReactionActions) do
		for messageId,reactionTable in pairs(messageTable) do
			for reaction, actions in pairs(reactionTable) do
				local hasActions = false

				if (actions.AddRoles) then
					for _,roleId in pairs(actions.AddRoles) do
						ProcessRole(channelId, messageId, reaction, roleId, false)
						hasActions = true
					end
				end

				if (actions.RemoveRoles) then
					for _,roleId in pairs(actions.RemoveRoles) do
						ProcessRole(channelId, messageId, reaction, roleId, true)
						hasActions = true
					end
				end

				if (actions.SendMessage) then
					local roleActions = self:GetReactionActions(guild, channelId, messageId, reaction)
					roleActions.Message = actions.SendMessage

					hasActions = true
				end

				if (not hasActions) then
					reactionTable[reaction] = nil
				end
			end

			if (next(reactionTable) == nil) then
				messageTable[messageId] = nil
			end
		end

		if (next(messageTable) == nil) then
			config.ReactionActions[channelId] = nil
		end
	end

	self:LogInfo(guild, "Adding emojis to concerned messages...")

	-- Make sure reactions are present on messages
	for channelId,messageTable in pairs(config.ReactionActions) do
		local channel = guild:getChannel(channelId)
		if (channel) then
			for messageId,reactionTable in pairs(messageTable) do
				local message = channel:getMessage(messageId)
				if (message) then
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
					
					for reaction, _ in pairs(reactionTable) do
						local emoji = bot:GetEmojiData(guild, reaction)
						if (emoji) then
							if (not hasReaction[emoji.Name]) then
								local success, err = message:addReaction(emoji.Emoji or emoji.Id)
								if (not success) then
									self:LogWarning(guild, "Failed to add reaction %s on message %s (channel: %s): %s", emoji.Name, message.id, message.channel.id, err)
								end
							end
						else
							self:LogError(guild, "Emoji \"%s\" does not exist", reaction.emojiName)
						end
					end
				else
					self:LogError(guild, "Message %s no longer exists in channel %s", messageId, channelId)
				end
			end
		else
			self:LogError(guild, "Channel %s no longer exists", channelId)
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

			local success, err = member:addRole(roleId)
			if (not success) then
				self:LogWarning(guild, "Failed to add role %s to %s: %s", role.name, member.tag, err)
			end
		else
			self:LogWarning(guild, "Role %s appears to have been removed", roleId)
		end
	end

	for k,roleId in pairs(roleActions.Remove) do
		local role = guild:getRole(roleId)
		if (role) then
			self:LogInfo(guild, "Removing %s%s from %s", role.name, (role.color ~= 0) and " (colored)" or "", member.tag)

			local success, err = member:removeRole(roleId)
			if (not success) then
				self:LogWarning(guild, "Failed to remove role % from %s: %s", role.name, member.tag, err)
			end
		else
			self:LogWarning(guild, "Role %s appears to have been removed", roleId)
		end
	end

	if (roleActions.Message) then
		local privateChannel = member.user:getPrivateChannel()
		if (privateChannel) then

			local success, err = privateChannel:send(string.format("[From %s]\n%s", guild.name, roleActions.Message))
			if (not success) then
				self:LogWarning(guild, "Failed to send reaction message to %s (maybe user disabled private messages from this server?): %s", member.user.tag, err)
			end
		else
			self:LogWarning(guild, "Failed to get private channel with %s", member.user.tag)
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

			local success, err = member:removeRole(roleId)
			if (not success) then
				self:LogWarning(guild, "Failed to remove role %s from %s: %s", role.name, member.tag, err)
			end
		else
			self:LogWarning(guild, "Role %s appears to have been removed", roleId)
		end
	end

	for k,roleId in pairs(roleActions.Remove) do
		local role = guild:getRole(roleId)
		if (role) then
			self:LogInfo(guild, "Adding back %s%s to %s", role.name, (role.color ~= 0) and " (colored)" or "", member.tag)

			local success, err = member:addRole(roleId)
			if (not success) then
				self:LogWarning(guild, "Failed to add role %s to %s: %s", role.name, member.tag, err)
			end
		else
			self:LogWarning(guild, "Role %s appears to have been removed", roleId)
		end
	end
end

function Module:OnReactionAdd(reaction, userId)
	if (not self:IsPublicChannel(reaction.message.channel)) then
		return
	end

	local emoji = bot:GetEmojiData(reaction.message.guild, reaction.emojiName)
	if (not emoji) then
		return
	end

	self:HandleReactionAdd(reaction.message.channel.guild, userId, reaction.message.channel.id, reaction.message.id, emoji.Name)
end

function Module:OnReactionAddUncached(channel, messageId, reactionIdOrName, userId)
	if (not self:IsPublicChannel(channel)) then
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
	if (not self:IsPublicChannel(reaction.message.channel)) then
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
	if (not self:IsPublicChannel(channel)) then
		return
	end

	local emoji = bot:GetEmojiData(channel.guild, reactionIdOrName)
	if (not emoji) then
		self:LogWarning(channel.guild, "Emoji %s was used but not found in guild", reactionIdOrName)
		return
	end

	self:HandleReactionRemove(channel.guild, userId, channel.id, messageId, emoji.Name)
end
