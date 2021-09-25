-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local bot = Bot
local client = Client
local discordia = Discordia
local enums = discordia.enums
local timer = require("timer")

discordia.extensions() -- load all helpful extensions

Module.Name = "channels"

local emojiOrder = {
	zero = 0,
	one = 1,
	two = 2,
	three = 3,
	four = 4,
	five = 5,
	six = 6,
	seven = 7,
	eight = 8,
	nine = 9
}

local function arrayRemoveValue(t, v)
	local i = 1
	while (i <= #t) do
		if (t[i] == v) then
			table.remove(t, i)
		else
			i = i + 1
		end
	end
end

local function arrayFilter(t, fn)
	local i = 1
	while (i <= #t) do
		if (not fn(t[i])) then
			table.remove(t, i)
		else
			i = i + 1
		end
	end
end

function Module:GetConfigTable()
	return {
		{
			Name = "ReactionActions",
			Description = "Map explaining which role to add/remove from which reaction on which message, use the !channelconfig command to setup this",
			Type = bot.ConfigType.Custom,
			Default = {},
			ValidateConfig = function (value)
				if (type(value) ~= "table" or #value ~= 0) then
					return false, "ReactionActions must be an array"
				end

				for channelId, messageTable in pairs(value) do
					if (not util.ValidateSnowflake(channelId)) then
						return false, "ReactionActions keys must be channel snowflakes"
					end

					if (type(messageTable) ~= "table" or #messageTable ~= 0) then
						return false, "ReactionActions[" .. channelId .. "] must be an object"
					end

					for messageId, reactionTable in pairs(messageTable) do
						if (not util.ValidateSnowflake(messageId)) then
							return false, "ReactionActions[" .. channelId .. "] keys must be message snowflakes (" .. tostring(messageId) .. ")"
						end

						if (type(reactionTable) ~= "table" or #reactionTable ~= 0) then
							return false, "ReactionActions[" .. channelId .. "][" .. messageId .. "] must be an object"
						end
	
						for emoji, actions in pairs(reactionTable) do
							if (type(emoji) ~= "string") then
								return false, "ReactionActions[" .. channelId .. "][" .. messageId .. "] keys must be strings (" .. tostring(emoji) .. ")"
							end
							
							if (type(actions) ~= "table" or #actions ~= 0) then
								return false, "ReactionActions[" .. channelId .. "][" .. messageId .. "][" .. emoji .. "] must be an object"
							end

							for actionType, values in pairs(actions) do
								if (actionType == "AddRoles" or actionType == "RemoveRoles" or actionType == "ToggleRoles") then
									if (type(values) ~= "table" or #values ~= table.count(values)) then
										return false, "ReactionActions[" .. channelId .. "][" .. messageId .. "][" .. emoji .. "]." .. actionType .. " must be an array"
									end
		
									for i, roleId in pairs(values) do
										if (not util.ValidateSnowflake(roleId)) then
											return false, "ReactionActions[" .. channelId .. "][" .. messageId .. "][" .. emoji .. "]." .. actionType .. "[" .. i .. "] isn't a snowflake"
										end
									end
								elseif (actionType == "SendMessage") then
									if (type(values) ~= "string") then
										return false, "ReactionActions[" .. channelId .. "][" .. messageId .. "][" .. emoji .. "]." .. actionType .. " value must be a string"
									end
								else
									return false, "ReactionActions[" .. channelId .. "][" .. messageId .. "][" .. emoji .. "]." .. actionType .. " is not a valid action type"
								end
							end
						end
					end
				end
				
				return true
			end
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
								local actionStr = {}

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
										table.insert(actionStr, string.format("**Adds role%s** %s\n", #addedRoles > 1 and "s" or "", table.concat(addedRoles, ", ")))
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
										table.insert(actionStr, string.format("**Removes role%s** %s\n", #removedRoles > 1 and "s" or "", table.concat(removedRoles, ", ")))
									end
								end

								if (actions.SendMessage) then
									table.insert(actionStr, string.format("**Sends private message:**\n\"%s\"\n", actions.SendMessage))
								end

								if (actions.ToggleRoles) then
									local toggleRoles = {}
									for _, roleId in pairs(actions.ToggleRoles) do
										local role = guild:getRole(roleId)
										if (role) then
											table.insert(toggleRoles, role.mentionString)
										else
											table.insert(toggleRoles, "<invalid role " .. roleId .. ">") 
										end
									end

									if (#toggleRoles > 0) then
										table.insert(actionStr, string.format("**Toggles role%s** %s", #toggleRoles > 1 and "s" or "", table.concat(toggleRoles, ", ")))
									end
								end

								local emoji = bot:GetEmojiData(guild, emoji)

								table.insert(fields, {
									name = string.format("- %s:", emoji and emoji.MentionString or "<invalid emoji>"),
									value = table.concat(actionStr, "\n")
								})
							end

							commandMessage:reply({
								embed = { 
									description = string.format("Message in %s:\n%s", channel.mentionString, bot:GenerateMessageLink(message)),
									fields = fields,
									footer = {
										text = "Use `!updatechannelconfig <message link> <emoji> <action> <data>` to update channels reactions settings."
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
				local role, err = Bot:DecodeRole(value)
				if (not role) then
					commandMessage:reply(string.format("Invalid role: %s", err))
					return
				end

				local roleValue = tostring(role.id)

				local reactionActions = GetReactionActionsConfig(message.channel.id, message.id, emoji.Name)
				if (reactionActions.AddRoles) then
					if (not table.search(reactionActions.AddRoles, roleValue)) then
						table.insert(reactionActions.AddRoles, tostring(role.id))
					end
				else
					reactionActions.AddRoles = {roleValue}
				end

				if (reactionActions.RemoveRoles) then
					arrayRemoveValue(reactionActions.RemoveRoles, roleValue)
				end

				if (reactionActions.ToggleRoles) then
					arrayRemoveValue(reactionActions.ToggleRoles, roleValue)
				end

				success = true
				commandMessage:reply(string.format("Reactions on %s for %s will now adds role %s (%s)", Bot:GenerateMessageLink(message), emoji.MentionString, role.name, role.id))
			elseif (action == "removerole") then
				local role, err = Bot:DecodeRole(value)
				if (not role) then
					commandMessage:reply(string.format("Invalid role: %s", err))
					return
				end

				local roleValue = tostring(role.id)

				local reactionActions = GetReactionActionsConfig(message.channel.id, message.id, emoji.Name)
				if (reactionActions.RemoveRoles) then
					if (not table.search(reactionActions.RemoveRoles, roleValue)) then
						table.insert(reactionActions.RemoveRoles, tostring(role.id))
					end
				else
					reactionActions.RemoveRoles = {roleValue}
				end

				if (reactionActions.AddRoles) then
					arrayRemoveValue(reactionActions.AddRoles, roleValue)
				end

				if (reactionActions.ToggleRoles) then
					arrayRemoveValue(reactionActions.ToggleRoles, roleValue)
				end

				success = true
				commandMessage:reply(string.format("Reactions on %s for %s will now remove role %s (%s)", Bot:GenerateMessageLink(message), emoji.MentionString, role.name, role.id))
			elseif (action == "togglerole") then
				local role, err = Bot:DecodeRole(value)
				if (not role) then
					commandMessage:reply(string.format("Invalid role: %s", err))
					return
				end

				local roleValue = tostring(role.id)

				local reactionActions = GetReactionActionsConfig(message.channel.id, message.id, emoji.Name)
				if (reactionActions.ToggleRoles) then
					if (not table.search(reactionActions.ToggleRoles, roleValue)) then
						table.insert(reactionActions.ToggleRoles, tostring(role.id))
					end
				else
					reactionActions.ToggleRoles = {roleValue}
				end

				if (reactionActions.AddRoles) then
					arrayRemoveValue(reactionActions.AddRoles, roleValue)
				end

				if (reactionActions.RemoveRoles) then
					arrayRemoveValue(reactionActions.RemoveRoles, roleValue)
				end

				success = true
				commandMessage:reply(string.format("Reactions on %s for %s will now toggle role %s (%s)", Bot:GenerateMessageLink(message), emoji.MentionString, role.name, role.id))
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
					reactionActions.ToggleRoles = nil
					reactionActions.SendMessage = nil
				end

				success = true
				commandMessage:reply(string.format("Reactions actions on %s for %s have been cleared", Bot:GenerateMessageLink(message), emoji.MentionString))
			else
				commandMessage:reply("Invalid action (must be addrole/clear/removerole/send/togglerole)")
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
		roleActions.Toggle = {}

		data.ReactionActions[reactionKey] = roleActions
	end

	return roleActions
end

function Module:OnEnable(guild)
	local config = self:GetConfig(guild)

	local data = self:GetData(guild)
	data.ReactionActions = {}

	self:HandleConfig(guild, config)

	return true
end

function Module:HandleConfig(guild, config)
	self:LogInfo(guild, "Processing roles...")

	local ProcessRole = function (channelId, messageId, reaction, roleId, field)
		local roleActions = self:GetReactionActions(guild, channelId, messageId, reaction)
		table.insert(roleActions[field], roleId)
	end

	local configUpdated = false
	for channelId,messageTable in pairs(config.ReactionActions) do
		for messageId,reactionTable in pairs(messageTable) do
			for reaction, actions in pairs(reactionTable) do
				local hasActions = false

				if (actions.AddRoles) then
					arrayFilter(actions.AddRoles, function (roleId)
						local role = guild:getRole(roleId)
						if (role) then
							ProcessRole(channelId, messageId, reaction, roleId, "Add")
							hasActions = true

							return true
						else
							self:LogWarning(guild, "Role %s not found", roleId)
							configUpdated = true

							return false
						end
					end)
				end

				if (actions.RemoveRoles) then
					arrayFilter(actions.RemoveRoles, function (roleId)
						local role = guild:getRole(roleId)
						if (role) then
							ProcessRole(channelId, messageId, reaction, roleId, "Remove")
							hasActions = true

							return true
						else
							self:LogWarning(guild, "Role %s not found", roleId)
							configUpdated = true

							return false
						end
					end)
				end

				if (actions.ToggleRoles) then
					arrayFilter(actions.ToggleRoles, function (roleId)
						local role = guild:getRole(roleId)
						if (role) then
							ProcessRole(channelId, messageId, reaction, roleId, "Toggle")
							hasActions = true

							return true
						else
							self:LogWarning(guild, "Role %s not found", roleId)
							configUpdated = true

							return false
						end
					end)
				end

				if (actions.SendMessage) then
					local roleActions = self:GetReactionActions(guild, channelId, messageId, reaction)
					roleActions.Message = actions.SendMessage

					hasActions = true
				end

				if (not hasActions) then
					reactionTable[reaction] = nil
					configUpdated = true
				end
			end

			if (next(reactionTable) == nil) then
				messageTable[messageId] = nil
				configUpdated = true
			end
		end

		if (next(messageTable) == nil) then
			config.ReactionActions[channelId] = nil
			configUpdated = true
		end
	end

	if (configUpdated) then
		self:SaveGuildConfig(guild)
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
							local emoji = bot:GetEmojiData(guild, reaction.emojiId or reaction.emojiName)
							if (emoji) then
								hasReaction[emoji.Name] = true
							else
								self:LogError(guild, "Found reaction which does not exist in guild: %s", reaction.emojiName)
							end
						end
					end

					local reactionToAdd = {}
					for reaction, _ in pairs(reactionTable) do
						local emoji = bot:GetEmojiData(guild, reaction)
						if (emoji) then
							if (not hasReaction[emoji.Name]) then
								table.insert(reactionToAdd, reaction)
							end
						else
							self:LogError(guild, "Emoji \"%s\" does not exist", reaction.emojiName)
						end
					end

					table.sort(reactionToAdd, function (a, b)
						local i = emojiOrder[a]
						local j = emojiOrder[b]
						if (i and j) then
							return i < j
						else
							return a < b
						end
					end)

					for _, reaction in pairs(reactionToAdd) do
						local emoji = Bot:GetEmojiData(guild, reaction)
						local success, err = message:addReaction(emoji.Emoji or emoji.Id)
						if (not success) then
							self:LogWarning(guild, "Failed to add reaction %s on message %s (channel: %s): %s", emoji.Name, message.id, message.channel.id, err)
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
end

function Module:HandleConfigUpdate(guild, config, configName)
	if (not configName or configName == "ReactionActions") then
		self:HandleConfig(guild, config)
	end
end

function Module:HandleReactionAdd(guild, userId, channelId, messageId, reactionName)
	if (client.user.id == userId) then
		return false
	end

	local roleActions = self:GetReactionActions(guild, channelId, messageId, reactionName, true)
	if (not roleActions) then
		return false
	end

	local isActive = false

	local member = guild:getMember(userId)

	for _,roleId in pairs(roleActions.Add) do
		local role = guild:getRole(roleId)
		if (role) then
			if (not member:hasRole(role)) then
				self:LogInfo(guild, "Adding %s%s to %s", role.name, (role.color ~= 0) and " (colored)" or "", member.tag)

				local success, err = member:addRole(roleId)
				if (not success) then
					self:LogWarning(guild, "Failed to add role %s to %s: %s", role.name, member.tag, err)
				end
			end

			isActive = true
		else
			self:LogWarning(guild, "Role %s appears to have been removed", roleId)
		end
	end

	for _,roleId in pairs(roleActions.Remove) do
		local role = guild:getRole(roleId)
		if (role) then
			if (member:hasRole(role)) then
				self:LogInfo(guild, "Removing %s%s from %s", role.name, (role.color ~= 0) and " (colored)" or "", member.tag)

				local success, err = member:removeRole(roleId)
				if (not success) then
					self:LogWarning(guild, "Failed to remove role %s from %s: %s", role.name, member.tag, err)
				end
			end

			isActive = true
		else
			self:LogWarning(guild, "Role %s appears to have been removed", roleId)
		end
	end

	for _,roleId in pairs(roleActions.Toggle) do
		local role = guild:getRole(roleId)
		if (role) then
			local hasRole = member:hasRole(role)
			self:LogInfo(guild, "Toggling %s%s (%s) from %s", role.name, (role.color ~= 0) and " (colored)" or "", hasRole and "removing" or "adding", member.tag)

			local success, err
			if (hasRole) then
				success, err = member:removeRole(role)
			else
				success, err = member:addRole(role)
			end

			if (not success) then
				self:LogWarning(guild, "Failed to toggle role %s from %s: %s", role.name, member.tag, err)
			end

			isActive = true
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

			isActive = true
		else
			self:LogWarning(guild, "Failed to get private channel with %s", member.user.tag)
		end
	end

	return isActive
end

function Module:OnReactionAdd(reaction, userId)
	if (not bot:IsPublicChannel(reaction.message.channel)) then
		return
	end

	local emoji = bot:GetEmojiData(reaction.message.guild, reaction.emojiId or reaction.emojiName)
	if (not emoji) then
		return
	end

	if (self:HandleReactionAdd(reaction.message.channel.guild, userId, reaction.message.channel.id, reaction.message.id, emoji.Name)) then
		timer.sleep(3000) -- Wait a bit before removing reaction (so user won't think it failed)
		local success, err = reaction.message:removeReaction(emoji.Emoji or emoji.Id, userId)
		if (not success) then
			self:LogWarning(reaction.message.guild, "Failed to remove reaction for message (%s)", err)
		end
	end
end

function Module:OnReactionAddUncached(channel, messageId, reactionIdOrName, userId)
	if (not bot:IsPublicChannel(channel)) then
		return
	end

	local emoji = bot:GetEmojiData(channel.guild, reactionIdOrName)
	if (not emoji) then
		self:LogWarning(channel.guild, "Emoji %s was used but not found in guild", reactionIdOrName)
		return
	end

	if (self:HandleReactionAdd(channel.guild, userId, channel.id, messageId, emoji.Name)) then
		local message = channel:getMessage(messageId)
		if (message) then
			timer.sleep(3000) -- Wait a bit before removing reaction (so user won't think it failed)
			local success, err = message:removeReaction(emoji.Emoji or emoji.Id, userId)
			if (not success) then
				self:LogWarning(channel.guild, "Failed to remove reaction for uncached message (%s)", err)
			end
		end
	end
end
