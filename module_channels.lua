-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local client = Client
local config = Config
local discordia = Discordia
local enums = discordia.enums

-- Discord base emoji codes, from https://apps.timwhitlock.info/emoji/tables/unicode
local baseEmojis = {
	one                  = "\x31\xE2\x83\xA3",
	two                  = "\x32\xE2\x83\xA3",
	three                = "\x33\xE2\x83\xA3",
	four                 = "\x34\xE2\x83\xA3",
	five                 = "\x35\xE2\x83\xA3",
	six                  = "\x36\xE2\x83\xA3",
	seven                = "\x37\xE2\x83\xA3",
	eight                = "\x38\xE2\x83\xA3",
	nine                 = "\x39\xE2\x83\xA3",
	tv                   = "\xF0\x9F\x93\xBA",
	globe_with_meridians = "\xF0\x9F\x8C\x90",
	gear                 = "\xE2\x9A\x99",
	file_cabinet         = "\xF0\x9F\x97\x84",
	no_bell              = "\xF0\x9F\x94\x95"
}

local codeToEmojis = {}
for k,v in pairs(baseEmojis) do
	codeToEmojis[v] = k
end

Module.Name = "channels"

function Module:OnEnable(guild)
	local data = self:GetData(guild)
	data.ColoredRankCache = {}
	data.ReactionsToRole = {}
	data.ReactionIdToName = {}
	data.WhiteRankCache = {}

	local t1 = os.clock()

	local emojiCache = {}

	local ProcessRole = function (channelId, messageId, reaction, roleData)
		local remove = false
		if (roleData.name:sub(1,1) == "~") then
			roleData.name = roleData.name:sub(2)
			remove = true
		end

		if (roleData.colored) then
			data.ColoredRankCache[roleData.name] = true
		else
			data.WhiteRankCache[roleData.name] = true
		end

		local reactionKey = string.format("%s_%s_%s", channelId, messageId, reaction)

		local roleActions = data.ReactionsToRole[reactionKey]
		if (not roleActions) then
			roleActions = {}
			roleActions.Add = {}
			roleActions.Remove = {}

			data.ReactionsToRole[reactionKey] = roleActions
		end

		if (not remove) then
			table.insert(roleActions.Add, roleData)
		else
			table.insert(roleActions.Remove, roleData)
		end
	end

	client:info("[%s][%s] Processing roles...", guild.name, self.Name)

	for channelId,messagetable in pairs(config.ChannelModuleConfig) do
		for messageId,reactionTable in pairs(messagetable) do
			for k,reactionInfo in pairs(reactionTable) do
				emojiCache[reactionInfo.reaction] = baseEmojis[reactionInfo.reaction] or "custom"

				if (reactionInfo.role) then
					ProcessRole(channelId, messageId, reactionInfo.reaction, reactionInfo.role)
				elseif (reactionInfo.roles) then
					for k,roleData in pairs(reactionInfo.roles) do
						ProcessRole(channelId, messageId, reactionInfo.reaction, roleData)
					end
				end
			end
		end
	end

	for k,emoji in pairs(guild.emojis) do
		if (emojiCache[emoji.name]) then
			emojiCache[emoji.name] = emoji.id
		end
	end

	for k,role in pairs(guild.roles) do
		local white = (role:getColor():toHex() == "#000000")
		local rankCache = white and data.WhiteRankCache or data.ColoredRankCache -- Select rank cache depending on rank color

		if (rankCache[role.name]) then
			rankCache[role.name] = role.id
		end
	end

	for name,id in pairs(emojiCache) do
		data.ReactionIdToName[id] = name
	end

	for roleName,roleId in pairs(data.ColoredRankCache) do
		if (type(roleId) == "boolean") then
			client:warning("[%s][%s] role %s (colored) not found", guild.name, self.Name, roleName)
		end
	end

	for roleName,roleId in pairs(data.WhiteRankCache) do
		if (type(roleId) == "boolean") then
			client:warning("[%s][%s] role %s not found", guild.name, self.Name, roleName)
		end
	end

	client:info("[%s][%s] Adding emojis to concerned messages...", guild.name, self.Name)

	-- Make sure reactions are present on messages
	for channelId,messagetable in pairs(config.ChannelModuleConfig) do
		local channel = guild:getChannel(channelId)
		for messageId,reactionTable in pairs(messagetable) do
			local message = channel:getMessage(messageId)
			
			local activeReactions = {}
			for k,reaction in pairs(message.reactions) do
				if (reaction.me) then
					local emojiName = codeToEmojis[reaction.emojiName] or reaction.emojiName
					activeReactions[emojiName] = true
				end
			end
			
			for k,reactionInfo in pairs(reactionTable) do
				local emoji = emojiCache[reactionInfo.reaction]
				assert(emoji)

				if (tonumber(emoji)) then
					emoji = guild:getEmoji(emoji)
				end

				local hasReaction = activeReactions[reactionInfo.reaction]
				if (not hasReaction and not message:addReaction(emoji)) then
					client:warning("[%s][%s] Failed to add reaction %s on message %s (channel: %s)", guild.name, self.Name, tostring(emojiName), message.id, message.channel.id)
				end
			end
		end
	end

	client:info("[%s][%s] Channels module ready (%ss).", guild.name, self.Name, (os.clock() - t1) * 1000)
	return true
end

function Module:HandleReactionAdd(guild, userId, channelId, messageId, reactionName)
	local data = self:GetData(guild)
	local reactionKey = string.format("%s_%s_%s", channelId, messageId, reactionName)
	local roleData = data.ReactionsToRole[reactionKey]
	if (not roleData) then
		return
	end

	if (client.user.id == userId) then
		return
	end

	local member = guild:getMember(userId)

	for k,roleInfo in pairs(roleData.Add) do
		local roleCache = roleInfo.colored and data.ColoredRankCache or data.WhiteRankCache -- Select rank cache depending on rank color
		local roleId = roleCache[roleInfo.name]
		
		client:info("[%s][%s] Adding %s%s to %s", guild.name, self.Name, roleInfo.name, roleInfo.colored and " (colored)" or "", member.fullname)
		if (not member:hasRole(roleId) and not member:addRole(roleId)) then
			client:warning("[%s][%s] Failed to add role % to %s", guild.name, self.Name, roleInfo.name, member.fullname)
		end
	end

	for k,roleInfo in pairs(roleData.Remove) do
		local roleCache = roleInfo.colored and data.ColoredRankCache or data.WhiteRankCache -- Select rank cache depending on rank color
		local roleId = roleCache[roleInfo.name]
		
		client:info("[%s][%s] Removing %s%s from %s", guild.name, self.Name, roleInfo.name, roleInfo.colored and " (colored)" or "", member.fullname)
		if (member:hasRole(roleId) and not member:removeRole(roleId)) then
			client:warning("[%s][%s] Failed to remove role % from %s", guild.name, self.Name, roleInfo.name, member.fullname)
		end
	end
end

function Module:HandleReactionRemove(guild, userId, channelId, messageId, reactionName)
	local data = self:GetData(guild)
	local reactionKey = string.format("%s_%s_%s", channelId, messageId, reactionName)
	local roleData = data.ReactionsToRole[reactionKey]
	if (not roleData) then
		return
	end

	if (client.user.id == userId) then
		return
	end

	local member = guild:getMember(userId)

	for k,roleInfo in pairs(roleData.Add) do
		local roleCache = roleInfo.colored and data.ColoredRankCache or data.WhiteRankCache -- Select rank cache depending on rank color
		local roleId = roleCache[roleInfo.name]

		client:info("[%s][%s] Removing %s%s from %s", guild.name, self.Name, roleInfo.name, roleInfo.colored and " (colored)" or "", member.fullname)
		if (member:hasRole(roleId) and not member:removeRole(roleId)) then
			client:warning("[%s][%s] Failed to remove role % from %s", guild.name, self.Name, roleInfo.name, member.fullname)
		end
	end

	for k,roleInfo in pairs(roleData.Remove) do
		local roleCache = roleInfo.colored and data.ColoredRankCache or data.WhiteRankCache -- Select rank cache depending on rank color
		local roleId = roleCache[roleInfo.name]
		
		client:info("[%s][%s] Adding back %s%s to %s", guild.name, self.Name, roleInfo.name, roleInfo.colored and " (colored)" or "", member.fullname)
		if (not member:hasRole(roleId) and not member:addRole(roleId)) then
			client:warning("[%s][%s] Failed to add role % to %s", guild.name, self.Name, roleInfo.name, member.fullname)
		end
	end
end

function Module:OnReactionAdd(reaction, userId)
	if (reaction.message.channel.type ~= enums.channelType.text) then
		return
	end

	local data = self:GetData(reaction.message.guild)
	local emojiName = data.ReactionIdToName[reaction.emojiId or reaction.emojiName]
	if (not emojiName) then
		return
	end

	self:HandleReactionAdd(reaction.message.channel.guild, userId, reaction.message.channel.id, reaction.message.id, emojiName)
end

function Module:OnReactionAddUncached(channel, messageId, reactionIdOrName, userId)
	if (channel.type ~= enums.channelType.text) then
		return
	end

	local data = self:GetData(channel.guild)
	local emojiName = data.ReactionIdToName[reactionIdOrName]
	if (not emojiName) then
		return
	end

	self:HandleReactionAdd(channel.guild, userId, channel.id, messageId, emojiName)
end

function Module:OnReactionRemove(reaction, userId)
	if (reaction.message.channel.type ~= enums.channelType.text) then
		return
	end

	local data = self:GetData(reaction.message.guild)
	local emojiName = data.ReactionIdToName[reaction.emojiId or reaction.emojiName]
	if (not emojiName) then
		return
	end

	self:HandleReactionRemove(reaction.message.channel.guild, userId, reaction.message.channel.id, reaction.message.id, emojiName)
end

function Module:OnReactionRemoveUncached(channel, messageId, reactionIdOrName, userId)
	if (channel.type ~= enums.channelType.text) then
		return
	end

	local data = self:GetData(channel.guild)
	local emojiName = data.ReactionIdToName[reactionIdOrName]
	if (not emojiName) then
		return
	end

	self:HandleReactionRemove(channel.guild, userId, channel.id, messageId, emojiName)
end
