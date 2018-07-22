-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local client = Client
local config = Config
local discordia = Discordia

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

local reactionsToRole = {}

local reactionIdToName = {}
local coloredRankCache = {}
local whiteRankCache = {}

Module.Name = "channels"

function Module:OnReady()
	local t1 = os.clock()

	local emojiCache = {}

	local ProcessRole = function (channelId, messageId, reaction, roleData)
		local remove = false
		if (roleData.name:sub(1,1) == "~") then
			roleData.name = roleData.name:sub(2)
			remove = true
		end

		if (roleData.colored) then
			coloredRankCache[roleData.name] = true
		else
			whiteRankCache[roleData.name] = true
		end

		local reactionKey = string.format("%s_%s_%s", channelId, messageId, reaction)

		local roleActions = reactionsToRole[reactionKey]
		if (not roleActions) then
			roleActions = {}
			roleActions.Add = {}
			roleActions.Remove = {}

			reactionsToRole[reactionKey] = roleActions
		end

		if (not remove) then
			table.insert(roleActions.Add, roleData)
		else
			table.insert(roleActions.Remove, roleData)
		end
	end

	print("Processing roles...")

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

	local guild = client:getGuild(config.Guild)
	for k,emoji in pairs(guild.emojis) do
		if (emojiCache[emoji.name]) then
			emojiCache[emoji.name] = emoji.id
		end
	end

	for k,role in pairs(guild.roles) do
		local white = (role:getColor():toHex() == "#000000")
		local rankCache = white and whiteRankCache or coloredRankCache -- Select rank cache depending on rank color

		if (rankCache[role.name]) then
			rankCache[role.name] = role.id
		end
	end

	for name,id in pairs(emojiCache) do
		reactionIdToName[id] = name
	end

	for roleName,roleId in pairs(coloredRankCache) do
		if (type(roleId) == "boolean") then
			print("Warning: " .. roleName .. " (colored) not found")
		end
	end

	for roleName,roleId in pairs(whiteRankCache) do
		if (type(roleId) == "boolean") then
			print("Warning: " .. roleName .. " not found")
		end
	end

	print("Adding emojis to concerned messages...")

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
					print("Failed to add reaction " .. tostring(emojiName))
				end
			end
		end
	end

	print("Channels module ready (" .. (os.clock() - t1) * 1000 .. "s).")
	return true
end

function Module:HandleReactionAdd(guild, userId, channelId, messageId, reactionName)
	local reactionKey = string.format("%s_%s_%s", channelId, messageId, reactionName)
	local roleData = reactionsToRole[reactionKey]
	if (not roleData) then
		return
	end

	if (client.user.id == userId) then
		return
	end

	local member = guild:getMember(userId)

	for k,roleInfo in pairs(roleData.Add) do
		local roleCache = roleInfo.colored and coloredRankCache or whiteRankCache -- Select rank cache depending on rank color
		local roleId = roleCache[roleInfo.name]
		
		print(string.format("%s: Adding %s%s to %s", os.date("%Y-%m-%d %H:%M"), roleInfo.name, roleInfo.colored and " (colored)" or "", member.name))
		if (not member:hasRole(roleId) and not member:addRole(roleId)) then
			print("Failed to add " .. roleInfo.name .. " to " .. member.name)
		end
	end

	for k,roleInfo in pairs(roleData.Remove) do
		local roleCache = roleInfo.colored and coloredRankCache or whiteRankCache -- Select rank cache depending on rank color
		local roleId = roleCache[roleInfo.name]
		
		print(string.format("%s: Removing %s%s from %s", os.date("%Y-%m-%d %H:%M"), roleInfo.name, roleInfo.colored and " (colored)" or "", member.name))
		if (member:hasRole(roleId) and not member:removeRole(roleId)) then
			print("Failed to remove " .. roleInfo.name .. " from " .. member.name)
		end
	end
end

function Module:HandleReactionRemove(guild, userId, channelId, messageId, reactionName)
	local reactionKey = string.format("%s_%s_%s", channelId, messageId, reactionName)
	local roleData = reactionsToRole[reactionKey]
	if (not roleData) then
		return
	end

	if (client.user.id == userId) then
		return
	end

	local member = guild:getMember(userId)

	for k,roleInfo in pairs(roleData.Add) do
		local roleCache = roleInfo.colored and coloredRankCache or whiteRankCache -- Select rank cache depending on rank color
		local roleId = roleCache[roleInfo.name]

		print(string.format("%s: Removing %s%s from %s", os.date("%Y-%m-%d %H:%M"), roleInfo.name, roleInfo.colored and " (colored)" or "", member.name))
		if (member:hasRole(roleId) and not member:removeRole(roleId)) then
			print("Failed to remove " .. roleInfo.name .. " from " .. member.name)
		end
	end

	for k,roleInfo in pairs(roleData.Remove) do
		local roleCache = roleInfo.colored and coloredRankCache or whiteRankCache -- Select rank cache depending on rank color
		local roleId = roleCache[roleInfo.name]
		
		print(string.format("%s: Adding back %s%s from %s", os.date("%Y-%m-%d %H:%M"), roleInfo.name, roleInfo.colored and " (colored)" or "", member.name))
		if (not member:hasRole(roleId) and not member:addRole(roleId)) then
			print("Failed to add " .. roleInfo.name .. " to " .. member.name)
		end
	end
end

function Module:OnReactionAdd(reaction, userId)
	local emojiName = reactionIdToName[reaction.emojiId or reaction.emojiName]
	if (not emojiName) then
		return
	end

	self:HandleReactionAdd(reaction.message.channel.guild, userId, reaction.message.channel.id, reaction.message.id, emojiName)
end

function Module:OnReactionAddUncached(channel, messageId, reactionIdOrName, userId)
	local emojiName = reactionIdToName[reactionIdOrName]
	if (not emojiName) then
		return
	end

	self:HandleReactionAdd(channel.guild, userId, channel.id, messageId, emojiName)
end

function Module:OnReactionRemove(reaction, userId)
	local emojiName = reactionIdToName[reaction.emojiId or reaction.emojiName]
	if (not emojiName) then
		return
	end

	self:HandleReactionRemove(reaction.message.channel.guild, userId, reaction.message.channel.id, reaction.message.id, emojiName)
end

function Module:OnReactionRemoveUncached(channel, messageId, reactionIdOrName, userId)
	local emojiName = reactionIdToName[reactionIdOrName]
	if (not emojiName) then
		return
	end

	self:HandleReactionRemove(channel.guild, userId, channel.id, messageId, emojiName)
end

	--[[local chan = client:getChannel("358727386411565066")
	local message = chan:getMessage("436842752630587392")

	local emojisToRole = {
		["lua"] = "Lua",
		["js"] = "Web",
		["rust"] = "Rust",
		["java"] = "Java",
		["csharp"] = "C#",
		["python"] = "Python",
		["golang"] = "Go",
		["html"] = "Web",
		["css"] = "Web",
		["cpp"] = "C++"
	}
	
	for k,role in pairs(chan.guild.roles) do
		for emoji,roleName in pairs(emojisToRole) do
			if (role.name == roleName and role:getColor():toHex() ~= "#000000") then
				emojisToRole[emoji] = {["name"] = roleName, ["id"] = role.id}
			end
		end
	end

	local reactions = {}
	for k,reaction in pairs(message.reactions) do
		local role = emojisToRole[reaction.emojiName]
		if (role) then
			for k,user in pairs(reaction:getUsers()) do
				local member = chan.guild:getMember(user.id)
				print("Adding " .. role.name .. " to " .. member.name)
				if (not member:addRole(role.id)) then
					print("Failed to add " .. role.id .. " to " .. member.name)
				end
			end
		else
			print("Who the hell added reaction " .. reaction.emojiName)
		end
	end]]
