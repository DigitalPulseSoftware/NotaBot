-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local fs = require("coro-fs")
local json = require("json")
local path = require("path")

function Bot:DecodeChannel(guild, message)
	assert(guild)
	assert(message)

	local channelId = message:match("<#(%d+)>")
	if (channelId) then
		return guild:getChannel(channelId)
	end

	return nil
end

function Bot:DecodeEmoji(guild, message)
	assert(guild)
	assert(message)

	local emojiId = message:match("<a?:[%w_]+:(%d+)>")
	if (emojiId) then
		return self:GetEmojiData(guild, emojiId) -- Custom emoji
	else
		return self:GetEmojiData(guild, message) -- Discord emoji
	end
end

function Bot:DecodeMember(guild, message)
	assert(guild)
	assert(message)

	local userId = message:match("<@!?(%d+)>")
	if (userId) then
		return guild:getMember(userId)
	end

	return nil
end

function Bot:DecodeUser(message)
	assert(guild)
	assert(message)

	local userId = message:match("<@!?(%d+)>")
	if (userId) then
		return self.Client:getClient(userId)
	end

	return nil
end

function Bot:GenerateMessageLink(message)
	local guildId = message.guild and message.guild.id or "@me"
	return string.format("https://discordapp.com/channels/%s/%s/%s", guildId, message.channel.id, message.id)
end

local ehandler = function(err)
	return debug.traceback(tostring(err))
end

function Bot:ProtectedCall(context, func, ...)
	local success, ret = xpcall(func, ehandler, ...)
	if (not success) then
		local err = string.format("%s failed: %s", context, ret)
		self.Client:warning(err)
		return false, err
	end

	return success, ret
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
