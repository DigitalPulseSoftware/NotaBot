-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local emojiTable = require("./data_emoji.lua")

local emojiByName = {}
for _, emojiData in pairs(emojiTable) do
	for _, name in pairs(emojiData.names) do
		emojiByName[name] = emojiData
	end
end
Bot.EmojiByName = emojiByName

local emojiByCode = {}
for _, emojiData in pairs(emojiTable) do
	for _, code in pairs(emojiData.codes) do
		emojiByCode[code] = emojiData
	end
end
Bot.EmojiByCode = emojiByCode

local emojiGlobalCache = {}
local emojiGuildsCache = {}
local emojiGlobalGuildCache = {}
function Bot:GetEmojiData(guild, emojiIdOrName)
	if (not guild) then
		assert(emojiIdOrName:match("^%d+$"), "When searching in global emoji cache, id must be used")
	end

	local emojiData

	-- Check in global cache first
	emojiData = emojiGlobalCache[emojiIdOrName]
	if (emojiData) then
		return emojiData
	end

	-- Not in global cache, search in guild cache
	if (guild) then
		local emojiGuildCache = emojiGuildsCache[guild.id]
		if (emojiGuildCache) then
			emojiData = emojiGuildCache[emojiIdOrName]
		else
			emojiGuildCache = {}
			emojiGuildsCache[guild.id] = emojiGuildCache
		end
	else
		emojiData = emojiGlobalGuildCache[emojiIdOrName]
	end

	if (emojiData) then
		return emojiData
	end

	-- First check if it is a Discord emoji
	local discordEmoji = emojiByCode[emojiIdOrName]
	if (not discordEmoji) then
		discordEmoji = emojiByName[emojiIdOrName]
	end

	if (discordEmoji) then
		emojiData = {}
		emojiData.Custom = false
		emojiData.Id = discordEmoji.codes[1]
		emojiData.Name = discordEmoji.names[1]
		emojiData.MentionString = discordEmoji.codes[1]
	else
		-- Not a discord emoji, check in guild
		if (guild) then
			for _,emoji in pairs(guild.emojis) do
				if (emojiIdOrName == emoji.id or emojiIdOrName == emoji.name) then
					emojiData = {}
					emojiData.Custom = true
					emojiData.Emoji = emoji
					emojiData.Id = emoji.id
					emojiData.Name = emoji.name
					emojiData.MentionString = emoji.mentionString
					emojiData.FromGuild = guild
					break
				end
			end
		else
			for _, guild in pairs(Bot.Client.guilds) do
				for _,emoji in pairs(guild.emojis) do
					if (emojiIdOrName == emoji.id) then
						emojiData = {}
						emojiData.Custom = true
						emojiData.Emoji = emoji
						emojiData.Id = emoji.id
						emojiData.Name = emoji.name
						emojiData.MentionString = emoji.mentionString
						emojiData.FromGuild = guild
						break
					end
				end

				if (emojiData) then
					break
				end
			end
		end
	end

	if (not emojiData) then
		-- Not a valid emoji
		return nil
	end

	-- Register new emoji
	if (emojiData.Custom) then
		if (guild) then
			local emojiGuildCache = emojiGuildsCache[guild.id]
	
			emojiGuildCache[emojiData.Id] = emojiData
			emojiGuildCache[emojiData.Name] = emojiData
		else
			emojiGlobalGuildCache[emojiData.Id] = emojiData
		end
	else
		emojiGlobalCache[emojiData.Id] = emojiData
		emojiGlobalCache[emojiData.Name] = emojiData
	end

	return emojiData
end

local function deleteGuildCache(guild)
	emojiGuildsCache[guild.id] = nil
	for k, emojiData in pairs(emojiGlobalGuildCache) do
		if (emojiData.FromGuild == guild) then
			emojiGlobalGuildCache[k] = nil
		end
	end
end

Bot.Client:on('emojisUpdate', deleteGuildCache)
Bot.Client:on("guildDelete", deleteGuildCache)
