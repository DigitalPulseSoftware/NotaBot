-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

-- TODO: Use this list extracted from Discord source: https://pastebin.com/ZbBPhZ6w

local emojiNameToCode = require("./data_emoji.lua")

Bot.EmojiNameToCode = emojiNameToCode

local emojiCodeToName = {}
for name, code in pairs(emojiNameToCode) do
	if (type(code) == "table") then
		for _, c in pairs(code) do
			emojiCodeToName[c] = name
		end
	else
		emojiCodeToName[code] = name
	end
end
Bot.EmojiCodeToName = emojiCodeToName

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
	local emojiName = emojiCodeToName[emojiIdOrName]
	if (emojiName) then
		emojiData = {}
		emojiData.Custom = false
		emojiData.Id = emojiIdOrName
		emojiData.Name = emojiName
		emojiData.MentionString = emojiIdOrName
	else
		local emojiId = emojiNameToCode[emojiIdOrName]
		if (emojiId) then
			if (type(emojiId) == "table") then
				emojiId = emojiId[1]
			end

			emojiData = {}
			emojiData.Custom = false
			emojiData.Id = emojiId
			emojiData.Name = emojiIdOrName
			emojiData.MentionString = emojiId
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

Bot.Client:on('emojisUpdate', function (guild)
	emojiGuildsCache[guild.id] = nil
	emojiGlobalGuildCache = {}
end)

Bot.Client:on("guildDelete", function (guild)
	emojiGuildsCache[guild.id] = nil
	emojiGlobalGuildCache = {}
end)
