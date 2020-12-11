-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local client = Client
local discordia = Discordia
local bot = Bot
local enums = discordia.enums

local http = require("coro-http")
local json = require("json")

Module.Name = "message"

local function ValidateFields(data, expectedFields, allFieldExpected)
	if (type(data) ~= "table" or #data ~= 0) then
		return false, " must be an object"
	end

	local count = 0

	for fieldName, fieldValue in pairs(data) do
		local fieldValidator = expectedFields[fieldName]
		if (not fieldValidator) then
			return false, "." .. fieldName .. " is not an expected field"
		end

		local success, err = fieldValidator(fieldValue)
		if (not success) then
			return false, "." .. fieldName .. err
		end

		count = count + 1
	end

	if (allFieldExpected and count ~= table.count(expectedFields)) then
		for fieldName, validator in pairs(expectedFields) do
			if (data[fieldName] == nil) then
				return false, "." .. fieldName .. " has no value"
			end
		end
	end

	if (count == 0) then
		return false, " must contain something"
	end

	return count
end

local function ValidateBoolean(data)
	return type(data) == "boolean"
end

local function ValidateString(str)
	if (type(str) ~= "string") then
		return false, " must be a string"
	end

	if (#str == 0) then
		return false, " cannot be empty"
	end

	return true
end

local footerFields = {
	icon_url = ValidateString,
	text = ValidateString
}

local imageFields = {
	url = ValidateString
}

local thumbnailFields = {
	url = ValidateString
}

local authorFields = {
	name = ValidateString,
	url = ValidateString,
	icon_url = ValidateString
}

local fieldFields = {
	name = ValidateString,
	value = ValidateString,
	inline = ValidateBoolean
}

local embedFields = {
	title = ValidateString,
	description = ValidateString,
	url = ValidateString,
	color = function (color)
		if (type(color) ~= "number" or math.floor(color) ~= color) then
			return false, " must be an integer"
		end

		if (color < 0 or color > 16777215) then
			return false, " must be an integer in [0, 16777215] range"
		end

		return true
	end,
	timestamp = function (timestamp)
		local success, err = ValidateString(timestamp)
		if (not success) then
			return err
		end

		if (not timestamp:match("^(%d%d%d%d)-(%d%d)-(%d%d)[T ](%d%d):(%d%d):?([%d%.]*)([Z%+%-]?)(%d?%d?)%:?(%d?%d?)$")) then
			return false, " is not a valid date"
		end

		return true
	end,
	footer = function (footer)
		return ValidateFields(footer, footerFields)
	end,
	thumbnail = function (footer)
		return ValidateFields(footer, thumbnailFields, true)
	end,
	image = function (footer)
		return ValidateFields(footer, imageFields, true)
	end,
	author = function (footer)
		return ValidateFields(footer, authorFields, true)
	end,
	fields = function (fields)
		if (type(fields) ~= "table" or #fields ~= table.count(fields)) then
			return false, " must be an object"
		end

		for idx, fieldData in pairs(fields) do
			local success, err = ValidateFields(fieldData, fieldFields)
			if (not success) then
				return false, "[" .. idx .. "]" .. err
			end

			if (fieldData.name == nil) then
				return false, "[" .. idx .. "].name must contain something"
			end

			if (fieldData.value == nil) then
				return false, "[" .. idx .. "].value must contain something"
			end
		end

		return true
	end,
}

local messageFields = {
	content = ValidateString,
	embed = function (embed)
		return ValidateFields(embed, embedFields)
	end,
	tts = ValidateBoolean
}

local function ValidateMessageData(data)
	if (type(data) ~= "table" or #data ~= 0) then
		return false, "MessageData must be an object"
	end

	local success, err = ValidateFields(data, messageFields)
	if (not success) then
		return false, "MessageData" .. err
	end

	if (not messageFields.content and not messageFields.embed) then
		return false, "MessageData must have at least a content or embed field"
	end

	return true
end

local function GetMessageFields(message)
	local fields = {
		content = #message.content > 0 and message.content or nil,
		embed = message.embed,
		tts = message.tts or nil
	}

	local embed = message.embed
	if (embed) then
		embed.type = nil
		local author = embed.author
		if (author) then
			author.proxy_icon_url = nil
		end
	end

	return fields
end

function Module:CheckPermissions(member)
	local config = self:GetConfig(member.guild)
	for _,roleId in pairs(config.AuthorizedRoles) do
		if (member:hasRole(roleId)) then
			return true
		end
	end

	return member:hasPermission(enums.permission.administrator)
end

function Module:GetConfigTable()
	return {
		{
			Name = "AuthorizedRoles",
			Description = "Roles which can use the commands",
			Type = bot.ConfigType.Role,
			Default = {},
			Array = true
		},
		{
			Name = "Replies",
			Description = "Map associating a trigger with a reply",
			Type = bot.ConfigType.Custom,
			Default = {},
			ValidateConfig = function (value)
				if (type(value) ~= "table" or #value ~= 0) then
					return false, "Replies must be an array"
				end

				for trigger, reply in pairs(value) do
					local success, err = ValidateString(trigger)
					if (not success) then
						return false, "Replies keys error (" .. tostring(trigger) .. " " .. err .. ")"
					end

					local success, err = ValidateMessageData(reply)
					if (not success) then
						return false, "Replies[" .. trigger .. "]" .. err
					end
				end

				return true
			end
		}
	}
end

function Module:ParseContentParameter(content, commandMessage)
	if (content) then
		local language, code = content:match("^```(%w*)\n(.+)```$")
		if (language) then
			if (#language > 0 and language ~= "json") then
				commandMessage:reply(string.format("Expected a json message, got %s", language))
				return
			end

			local messageData, idx, err = json.decode(code)
			if (not messageData) then
				commandMessage:reply(string.format("Expected a valid json code, parsing failed at %d: %s", idx, err))
				return
			end

			local success, err = ValidateMessageData(messageData)
			if (not success) then
				commandMessage:reply(err)
				return
			end

			return messageData
		else
			local messageObject = bot:DecodeMessage(content)
			if (messageObject) then
				return GetMessageFields(messageObject)
			else
				return {
					content = content
				}
			end	
		end
	else
		if (#commandMessage.attachments ~= 1) then
			commandMessage:reply("You must send only one file to update a module config!")
			return
		end

		local attachment = commandMessage.attachments[1]
		if (not attachment.filename:match(".json$")) then
			commandMessage:reply("You must send a .json file to update a module config")
			return
		end

		if (attachment.size >= 1024 * 1024) then
			commandMessage:reply("This file is too big!")
			return
		end

		local res, body = http.request("GET", attachment.url)
		if (res.code ~= 200) then
			commandMessage:reply(string.format("Failed to download file (%d): ", res.code, body))
			return
		end

		local messageData, idx, err = json.decode(body)
		if (not messageData) then
			commandMessage:reply(string.format("Expected a valid json code, parsing failed at %d: %s", idx, err))
			return
		end

		local success, err = ValidateMessageData(messageData)
		if (not success) then
			commandMessage:reply(err)
			return
		end

		return messageData
	end
end

function Module:OnLoaded()
	self:RegisterCommand({
		Name = "rawmessage",
		Args = {
			{Name = "message", Type = Bot.ConfigType.Message},
		},
		PrivilegeCheck = function (member) return self:CheckPermissions(member) end,

		Help = "Prints a message in a raw form",
		Func = function (commandMessage, message)
			local fields = GetMessageFields(message)

			local fieldJson = json.encode(fields, { indent = 1 })
			
			local success, err
			if (#fieldJson > 1800) then
				success, err = commandMessage:reply({
					embed = {
						title = "Raw form of message " .. message.link,
						description = "Message json was too big and has been sent as a file"
					}
				})
				commandMessage:reply({ file = {"mesage.json", fieldJson} })
			else
				success, err = commandMessage:reply({
					embed = {
						title = "Raw form of message " .. message.link,
						description = string.format("```json\n%s```", json.encode(fields, { indent = 1 }))
					}
				})
			end

			if (not success) then
				commandMessage:reply(string.format("Discord rejected the message: %s", err))
			end
		end
	})

	self:RegisterCommand({
		Name = "sendmessage",
		Args = {
			{Name = "channel", Type = Bot.ConfigType.Channel, Optional = true},
			{Name = "content", Type = Bot.ConfigType.String, Optional = true},
		},
		PrivilegeCheck = function (member) return self:CheckPermissions(member) end,

		Help = "Makes the bot send a message",
		Func = function (commandMessage, channel, content)
			local messageData = self:ParseContentParameter(content, commandMessage)
			if (not messageData) then
				return
			end

			channel = channel or commandMessage.channel
			local success, err = channel:send(messageData)
			if (not success) then
				commandMessage:reply(string.format("Discord rejected the message: %s", err))
			end
		end
	})

	self:RegisterCommand({
		Name = "addreply",
		Args = {
			{Name = "trigger", Type = Bot.ConfigType.String},
			{Name = "content", Type = Bot.ConfigType.String, Optional = true},
		},
		PrivilegeCheck = function (member) return self:CheckPermissions(member) end,

		Help = "Registers a reply to a particular message",
		Func = function (commandMessage, trigger, content)
			local messageData = self:ParseContentParameter(content, commandMessage)
			if (not messageData) then
				return
			end

			local config = self:GetConfig(commandMessage.guild)
			config.Replies = config.Replies or {}
			config.Replies[trigger] = messageData
			commandMessage:reply(string.format("Registered a reply for \"%s\"", trigger))
		end
	})

	self:RegisterCommand({
		Name = "removereply",
		Args = {
			{Name = "trigger", Type = Bot.ConfigType.String},
		},
		PrivilegeCheck = function (member) return self:CheckPermissions(member) end,

		Help = "Unregisters a reply to a particular message",
		Func = function (commandMessage, trigger, content)
			local config = self:GetConfig(commandMessage.guild)
			config.Replies = config.Replies or {}
			if (not config.Replies[trigger]) then
				commandMessage:reply(string.format("No reply is registered for \"%s\"", trigger))
				return
			end
			config.Replies[trigger] = nil
			commandMessage:reply(string.format("\"%s\" will no longer trigger a reply", trigger))
		end
	})

	return true
end

function Module:OnEnable(guild)
	local config = self:GetConfig(guild)
	config.Replies = {}

	return true
end

function Module:OnMessageCreate(message)
	if (not bot:IsPublicChannel(message.channel)) then
		return
	end

	if (message.author.bot) then
		return
	end

	if (not message.content or (message.attachments and not table.empty(message.attachments))) then
		return
	end

	local config = self:GetConfig(message.guild)
	local reply = config.Replies[message.content]
	if (reply) then
		local success, err = message:reply(reply)
		if (not success) then
			self:LogError(message.guild, "Failed to reply to %s: %s", message.content, err)
		end
	end
end
