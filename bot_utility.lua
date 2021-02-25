-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local discordia = require('discordia')
local enums = discordia.enums
local fs = require("coro-fs")
local json = require("json")
local path = require("path")

local discordDomains = {
	-- no subdomain
	["discord.com"] = true,
	["discordapp.com"] = true,
	-- public test build
	["ptb.discord.com"] = true,
	["ptb.discordapp.com"] = true,
	-- canary
	["canary.discord.com"] = true,
	["canary.discordapp.com"] = true,
}

function Bot:DecodeChannel(guild, message)
	assert(guild)
	assert(message)

	local channelId = message:match("<#(%d+)>")
	if (not channelId) then
		channelId = message:match("^(%d+)$")
		if (not channelId) then
			return nil, "Invalid channelId id"
		end
	end

	local channel = guild:getChannel(channelId)
	if (not channel) then
		return nil, "This channel is not part of this guild"
	end

	return channel
end

function Bot:DecodeEmoji(guild, message)
	assert(guild)
	assert(message)

	local emojiId = message:match("<a?:[%w_]+:(%d+)>")
	if (emojiId) then
		 -- Custom emoji
		local emoji = self:GetEmojiData(guild, emojiId)
		if (not emoji) then
			return nil, "Failed to get emoji, maybe this is a global emoji?"
		end

		return emoji
	else
		-- Discord emoji
		local emoji = self:GetEmojiData(guild, message)
		if (not emoji) then
			return nil, "Invalid emoji"
		end

		return emoji
	end
end

function Bot:DecodeMember(guild, message)
	assert(guild)
	assert(message)

	local userId = message:match("<@!?(%d+)>")
	if (not userId) then
		userId = message:match("^(%d+)$")
		if (not userId) then
			return nil, "Invalid user id"
		end
	end

	local member = guild:getMember(userId)
	if (not member) then
		return nil, "This user is not part of this guild"
	end

	return member
end

function Bot:DecodeMessage(message, ignoreEscaped, fullContent)
	assert(message)

	local pattern = "(<?)https?://([%w%.]+)/channels/(%d+)/(%d+)/(%d+)(>?)"
	if (fullContent) then
		pattern = "^" .. pattern .. "$"
	end

	local e1, domain, guildId, channelId, messageId, e2 = message:match(pattern)
	if (not e1 or not discordDomains[domain]) then
		return nil, "Invalid link"
	end

	if (ignoreEscaped and e1 == "<" and e2 == ">") then
		return nil, "Escaped link"
	end

	local guild = self.Client:getGuild(guildId)
	if (not guild) then
		return nil, "Unavailable guild"
	end

	local channel = guild:getChannel(channelId)
	if (not channel) then
		return nil, "Unavailable channel"
	end

	local message = channel:getMessage(messageId)
	if (not message) then
		return nil, "Message not found"
	end

	return message
end

function Bot:DecodeRole(guild, message)
	assert(guild)
	assert(message)

	local roleId = message:match("<@&(%d+)>")
	if (not roleId) then
		roleId = message:match("^(%d+)$")
		if (not roleId) then
			return nil, "Invalid role"
		end
	end

	local role = guild:getRole(roleId)
	if (not role) then
		return nil, "This role is not part of this guild"
	end

	return role
end

function Bot:DecodeUser(message)
	assert(message)

	local userId = message:match("<@!?(%d+)>")
	if (not userId) then
		userId = message:match("^(%d+)$")
		if (not userId) then
			return nil, "Invalid user id"
		end
	end

	local user = self.Client:getUser(userId)
	if (not user) then
		return nil, "Invalid user (maybe this account was deleted?)"
	end

	return user
end

function Bot:GenerateMessageLink(message)
	local guildId = message.guild and message.guild.id or "@me"
	return string.format("https://discord.com/channels/%s/%s/%s", guildId, message.channel.id, message.id)
end

local publicChannels = {
	[enums.channelType.text] = true,
	[enums.channelType.news] = true
}

function Bot:IsPublicChannel(channel)
	return publicChannels[channel.type]
end

local ehandler = function(err)
	return debug.traceback(tostring(err))
end

function Bot:ProtectedCall(context, func, ...)
	local success, a, b, c, d, e, f = xpcall(func, ehandler, ...)
	if (not success) then
		local err = string.format("%s failed: %s", context, a)
		self.Client:warning(err)
		return false, err
	end

	return success, a, b, c, d, e, f
end

-- Serialization/unserialization
function Bot:SerializeToFile(filepath, data, pretty)
	local dirname = path.dirname(filepath)
	if (dirname ~= ".") then
		local success, err = fs.mkdirp(dirname)
		if (not success) then
			return false, string.format("Failed to create directory %s: %s", filepath, err)
		end
	end

	local outputFile, err = io.open(filepath, "w+")
	if (not outputFile) then
		return false, string.format("Failed to open %s: %s", filepath, err)
	end

	local encoderState = {}
	if (pretty) then
		encoderState.indent = true
	end

	local success, serializedDataOrErr = pcall(json.encode, data, encoderState)
	if (not success) then
		return false, string.format("Failed to serialize data: %s", serializedDataOrErr)
	end

	local success, err = outputFile:write(serializedDataOrErr)
	if (not success) then
		return false, string.format("Failed to write data to file %s: %s", filepath, err)
	end

	outputFile:close()
	return true
end

function Bot:UnserializeFromFile(filepath)
	local saveFile, err = io.open(filepath, "r")
	if (not saveFile) then
		return nil, string.format("Failed to open %s: %s", filepath, err) 
	end

	local content, err = saveFile:read("*a")
	if (not content) then
		return nil, string.format("Failed to read %s content: %s", filepath, err) 
	end
	saveFile:close()

	local success, contentOrErr = pcall(json.decode, content)
	if (not success) then
		return nil, string.format("Failed to unserialize %s content: %s", filepath, contentOrErr) 
	end

	return contentOrErr
end
