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

local function RemoveTableKey(table, key)
	local element = table[key]
	table[key] = nil
	return element
end

local function ValidateFields(data, expectedFields, allFieldExpected, metadata)
	if (type(data) ~= "table" or #data ~= 0) then
		return false, " must be an object"
	end

	local count = 0

	for fieldName, fieldValue in pairs(data) do
		local fieldValidator = expectedFields[fieldName]
		if (not fieldValidator) then
			return false, "." .. fieldName .. " is not an expected field"
		end

		local success, err = fieldValidator(fieldValue, metadata)
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

local function ValidateInteger(data)
	if type(data) ~= "number" or math.floor(data) ~= data then
		return false, " must be an integer"
	end

	return true
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
	thumbnail = function (thumbnail)
		return ValidateFields(thumbnail, thumbnailFields, true)
	end,
	image = function (image)
		return ValidateFields(image, imageFields, true)
	end,
	author = function (author)
		local success, err = ValidateFields(author, authorFields)
		if (not success) then
			return false, err
		end

		if (not author.name) then
			return false, " must have a name field"
		end

		return true
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

local function validateRole(value, metadata)
	local success, err = util.ValidateSnowflake(value)
	if not success then
		return false, err
	end

	if metadata.guild then
		local targetRole, err = metadata.guild:getRole(value)
		if not targetRole then
			return false, ": invalid role"
		end

		if metadata.member then
			if not metadata.member:hasPermission(enums.permission.manageRoles) then
				return false, ": you need to have the manage roles permission to toggle a role"
			end

			if targetRole.position > metadata.member.highestRole.position then
				return false, ": you cannot add or remove a role higher than your own"
			end
		end
	end

	return true
end

local possibleActions = {
	reply = {
		Validate = function (value)
			local success, err = ValidateString(value)
			if not success then
				return false, err
			end

			if #value > 100 then
				return false, " is too long (must be <=100 characters)"
			end

			return true
		end,
		Action = function (member, value)
			return Module:ReplaceData(value, member)
		end
	},
	addrole = {
		Validate = validateRole,
		Action = function (member, value)
			local guild = member.guild
			local role = guild:getRole(value)

			if member:hasRole(value) then
				return
			end

			local success, err = member:addRole(value)
			if success then
				return "✅ Role " .. role.mentionString .. " added"
			else
				return "⚠️ Failed to remove " .. role.mentionString
			end
		end
	},
	removerole = {
		Validate = validateRole,
		Action = function (member, value)
			local guild = member.guild
			local role = guild:getRole(value)

			if not member:hasRole(value) then
				return
			end
			
			local success, err = member:addRole(value)
			if success then
				return "✅ Role " .. role.mentionString .. " added"
			else
				return "⚠️ Failed to remove " .. role.mentionString
			end
		end
	},
	togglerole = {
		Validate = validateRole,
		Action = function (member, value)
			local guild = member.guild
			local role = guild:getRole(value)

			if member:hasRole(value) then
				local success, err = member:removeRole(value)
				if success then
					return "❎ Role " .. role.mentionString .. " removed"
				else
					return "⚠️ Failed to remove " .. role.mentionString
				end
			else
				local success, err = member:addRole(value)
				if success then
					return "✅ Role " .. role.mentionString .. " added"
				else
					return "⚠️ Failed to remove " .. role.mentionString
				end
			end
		end
	},
	openticket = {
		Validate = function (value, metadata)
			local modmail = Bot:GetModuleForGuild(metadata.guild, "modmail")
			if not modmail then
				return false, "modmail module is disabled"
			end

			if (not value or value == "") then
				return true
			end

			local success, err = ValidateString(value)
			if not success then
				return false, err
			end

			if #value > 100 then
				return false, " is too long (must be <=100 characters)"
			end

			return true
		end,
		Action = function (member, value)
			local modmail = Bot:GetModuleForGuild(member.guild, "modmail")
			if not modmail then
				return "❌ modmail is currently disabled"
			end

			local ticketChannel, err = modmail:OpenTicket(member, member, value, true)
			if not ticketChannel then
				return string.format("❌ failed to open modmail ticket: %s", err)
			end

			return "✅ a modmail ticket has been created: " .. ticketChannel.mentionString
		end
	}
}

local function ValidateActions(actions, metadata)
	if (type(actions) ~= "table" or #actions == 0) then
		return false, " must be an array"
	end

	if #actions > 20 then
		return false, " has too many values (a maximum of 20 actions are supported)"
	end

	for idx, action in ipairs(actions) do
		if type(action) ~= "table" or #action ~= 0 then
			return false, "[" .. idx .. "] must be an object"
		end
	
		local success, err = ValidateString(action.type)
		if not success then
			return false, "[" .. idx .. "].type" .. err
		end

		local actionData = possibleActions[action.type]
		if not actionData then
			return false, "[" .. idx .. "].type is not valid"
		end

		return actionData.Validate(action.value, metadata)
	end

	return true
end

local function GenerateCustomId(actions, metadata)
	local customId = "action_" .. metadata.customIdCounter
	metadata.customIdCounter = metadata.customIdCounter + 1

	metadata.actions[customId] = actions
	return customId
end

local ValidateComponent

local function ValidateActionRowComponent(component, metadata)
	if component.type ~= enums.componentType.actionRow then
		return false, ".type must be action row"
	end

	if (type(component.components) ~= "table" or #component.components == 0) then
		return false, ".components must be an array"
	end

	for idx, component in ipairs(component.components) do
		local success, err = ValidateComponent(component, metadata)
		if not success then
			return false, ".components[" .. idx .. "]" .. err
		end
	end

	return true
end

local emojiFields = {
	id = util.ValidateSnowflake,
	name = ValidateString
}

local buttonFields = {
	type = function (type)
		if type ~= enums.componentType.button then
			return false, " must be button"
		end

		return true
	end,
	style = function (style)
		local success, err = ValidateInteger(style)
		if not success then
			return false, err
		end

		if style < 1 or style > 5 then
			return false, ".style must be a valid button style"
		end

		return true
	end,
	label = ValidateString,
	url = ValidateString,
	disabled = ValidateBoolean,
	emoji = function (emoji)
		return ValidateFields(emoji, emojiFields)
	end,
	actions = ValidateActions
}

local function ValidateButtonComponent(button, metadata)
	if button.type == nil then
		return false, ".type must exist"
	end

	if button.style == nil then
		return false, ".style must exist"
	end

	local success, err = ValidateFields(button, buttonFields, false, metadata)
	if not success then
		return false, err
	end

	if button.style == enums.buttonStyle.link then
		if button.url == nil then
			return false, " must have an url (because its style is link)"
		end

		if button.actions ~= nil then
			return false, " cannot have an actions field (because its style is link)"
		end
	else
		if button.actions == nil then
			return false, " must have an actions field (because its style is not link)"
		end

		if button.url ~= nil then
			return false, " cannot have an url (because its style is not link)"
		end
	end

	if metadata.actions and button.actions then
		button.custom_id = GenerateCustomId(button.actions, metadata)
		button.actions = nil
	end

	return true
end

local selectMenuOptionFields = {
	label = ValidateString,
	description = ValidateString,
	emoji = function (emoji)
		return ValidateFields(emoji, emojiFields)
	end,
	default = ValidateBoolean,
	actions = ValidateActions
}

local selectMenuFields = {
	type = ValidateInteger,
	options = function (options, metadata)
		if type(options) ~= "table" or #options == 0 then
			return false, " must be an array"
		end

		for idx, option in ipairs(options) do
			local success, err = ValidateFields(option, selectMenuOptionFields, false, metadata)
			if not success then
				return false, "[" .. idx .. "]" .. err
			end

			if option.label == nil then
				return false, "[" .. idx .. "].label must be valid"
			end

			if option.actions == nil then
				return false, "[" .. idx .. "].actions must be valid"
			end

			if metadata.actions then
				if metadata.discardSelection then
					table.insert(option.actions, {
						type = "refreshmenu"
					})
				end

				option.value = GenerateCustomId(option.actions, metadata)
				option.actions = nil
			end
		end

		return true
	end,
	placeholder = ValidateString,
	min_values = function (min)
		local success, err = ValidateInteger(min)
		if not success then
			return false, err
		end

		if min < 0 or min > 25 then
			return false, " must be between 0 and 25"
		end

		return true
	end,
	max_values = function (max)
		local success, err = ValidateInteger(max)
		if not success then
			return false, err
		end

		if max < 1 or max > 25 then
			return false, " must be between 1 and 25"
		end

		return true
	end,
	disabled = ValidateBoolean,
	discard_selection = ValidateBoolean
}

local function ValidateSelectMenuComponent(selectmenu, metadata)
	if selectmenu.type == nil then
		return false, ".type must exist"
	end

	if selectmenu.options == nil then
		return false, ".options must exist"
	end

	if selectmenu.discard_selection then
		metadata.discardSelection = true
	else
		metadata.discardSelection = false
	end

	local success, err = ValidateFields(selectmenu, selectMenuFields, false, metadata)
	if not success then
		return false, err
	end

	metadata.discardSelection = nil

	selectmenu.custom_id = "message_placeholder" .. metadata.customIdCounter
	metadata.customIdCounter = metadata.customIdCounter + 1

	return true
end

ValidateComponent = function (component, metadata)
	if type(component.type) ~= "number" or math.floor(component.type) ~= component.type then
		return false, ".type must be an integer"
	end

	if component.type == enums.componentType.actionRow then
		return false, "an action row cannot contain action rows"
	elseif component.type == enums.componentType.button then
		local success, err = ValidateButtonComponent(component, metadata)
		if not success then
			return false, err
		end
	elseif component.type == enums.componentType.selectMenu then
		local success, err = ValidateSelectMenuComponent(component, metadata)
		if not success then
			return false, err
		end
	else
		return false, ".type is not valid"
	end

	return true
end

local messageFields = {
	components = function (components, metadata)
		if (type(components) ~= "table" or #components == 0) then
			return false, "Components must be an array"
		end

		if #components > 5 then
			return false, "Too many components (each message can only have up to 5 components)"
		end

		metadata.customIdCounter = 1

		for idx, component in ipairs(components) do
			local success, err = ValidateActionRowComponent(component, metadata)
			if not success then
				return false, "[" .. idx .. "]" .. err
			end
		end

		return true
	end,
	content = ValidateString,
	embed = function (embed)
		return ValidateFields(embed, embedFields)
	end,
	tts = ValidateBoolean,
	deleteInvokation = ValidateBoolean
}

local function ValidateMessageData(data, member, guild, actions)
	if (type(data) ~= "table" or #data ~= 0) then
		return false, "MessageData must be an object"
	end

	local success, err = ValidateFields(data, messageFields, false, { member = member, guild = guild, actions = actions })
	if (not success) then
		return false, "MessageData" .. err
	end

	if (not data.content and not data.embed) then
		return false, "MessageData must have at least a content or embed field"
	end

	return true
end

local function GetMessageFields(message)
	local fields = {
		attachments = message.attachments,
		content = #message.content > 0 and message.content or nil,
		embed = message.embed,
		tts = message.tts or nil,
		interaction = message.interaction,
		components = message.components,
		sticker_items = message.sticker_items
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
			ValidateConfig = function (value, guildId)
				if (type(value) ~= "table" or #value ~= 0) then
					return false, "Replies must be an object"
				end

				for trigger, reply in pairs(value) do
					local success, err = ValidateString(trigger)
					if (not success) then
						return false, "Replies keys error (" .. tostring(trigger) .. " " .. err .. ")"
					end

					local success, err = ValidateMessageData(reply, nil, client:getGuild(guildId), nil)
					if (not success) then
						return false, "Replies[" .. trigger .. "]" .. err
					end
				end

				return true
			end
		},
		{
			Name = "DeleteInvokation",
			Description = "Deletes the message that invoked the reply",
			Type = bot.ConfigType.Boolean,
			Default = false
		},
		{
			Name = "MaxActionMessage",
			Description = "How many actions messages are allowed per server",
			Type = bot.ConfigType.Integer,
			Default = 20
		}
	}
end

function Module:ParseContentParameter(content, commandMessage, actions)
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

			local success, err = ValidateMessageData(messageData, commandMessage.member, commandMessage.guild, actions)
			if (not success) then
				commandMessage:reply(err)
				return
			end

			return messageData
		else
			local message = bot:DecodeMessage(content, false, true)
			if (message and message.member:hasPermission(message.channel, enums.permission.viewChannel)) then
				return GetMessageFields(message)
			else
				return {
					content = content
				}
			end	
		end
	elseif (commandMessage.attachments) then
		if (#commandMessage.attachments ~= 1) then
			commandMessage:reply("You can send only one file!")
			return
		end

		local attachment = commandMessage.attachments[1]
		if (not attachment.filename:match(".json$")) then
			commandMessage:reply("You must send a .json file")
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

		local success, err = ValidateMessageData(messageData, commandMessage.member, commandMessage.guild, actions)
		if (not success) then
			commandMessage:reply(err)
			return
		end

		return messageData
	else
		commandMessage:reply(string.format("Expected some content or a file, got nothing"))
		return
	end
end

function Module:ReplaceData(data, triggeringMember)
	if data == nil then
		return
	end

	if type(data) == "table" then
		for k,v in pairs(data) do
			data[k] = self:ReplaceData(v, triggeringMember)
		end
	elseif type(data) == "string" then
		data = data:gsub("{user}", triggeringMember.mentionString)
		data = data:gsub("{userTag}", triggeringMember.tag)
		data = data:gsub("{userMention}", triggeringMember.mentionString)
	end

	return data
end

function Module:RegisterAction(guild, messageId, actions)
	if next(actions) == nil then
		-- not actions
		return true
	end

	local config = self:GetConfig(guild)
	local persistentData = self:GetPersistentData(guild)
	persistentData.MessageActions = persistentData.MessageActions or {}

	if not persistentData.MessageActions[messageId] then
		-- Adding a new entry
		local count = table.count(persistentData.MessageActions)
		if count >= config.MaxActionMessage then
			return false, "too many messages with actions (" .. tostring(count) .. " >= " .. config.MaxActionMessage .. ")"
		end
	end

	persistentData.MessageActions[messageId] = actions
	return true
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
			local actions = {}
			local messageData = self:ParseContentParameter(content, commandMessage, actions)
			if (not messageData) then
				return
			end

			local member = commandMessage.member

			channel = channel or commandMessage.channel
			if (not member:hasPermission(channel, enums.permission.viewChannel) or not member:hasPermission(channel, enums.permission.sendMessages)) then
				commandMessage:reply("You don't have the permission to send messages in that channel")
				return
			end
		
			local message, err = channel:send(messageData)
			if (message) then
				local success, err = self:RegisterAction(commandMessage.guild, message.id, actions)
				if not success then
					commandMessage:reply(string.format("Message sent but actions couldn't be registered: %s", err))
				end
			else
				commandMessage:reply(string.format("Discord rejected the message: %s", err))
			end
		end
	})

	self:RegisterCommand({
		Name = "editmessage",
		Args = {
			{Name = "message", Type = Bot.ConfigType.Message},
			{Name = "content", Type = Bot.ConfigType.String, Optional = true},
		},
		PrivilegeCheck = function (member) return self:CheckPermissions(member) end,

		Help = "Edit one of the message posted by the bot",
		Func = function (commandMessage, message, content)
			local actions = {}
			local messageData = self:ParseContentParameter(content, commandMessage, true)
			if (not messageData) then
				return
			end

			if (message.author ~= Bot.Client.user) then
				commandMessage:reply("You can only ask me to edit my own messages")
				return
			end

			local member = commandMessage.member
			if (not member:hasPermission(message.channel, enums.permission.viewChannel) or not member:hasPermission(message.channel, enums.permission.sendMessages)) then
				commandMessage:reply("You don't have the permission to send messages in that channel")
				return
			end

			local success, err = message:update(messageData)
			if (success) then
				local success, err = self:RegisterAction(commandMessage.guild, message.id, actions)
				if not success then
					commandMessage:reply(string.format("Message sent but actions couldn't be registered: %s", err))
				end
			else
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
			local messageData = self:ParseContentParameter(content, commandMessage, nil)
			if (not messageData) then
				return
			end

			local config = self:GetConfig(commandMessage.guild)
			config.Replies = config.Replies or {}
			config.Replies[trigger] = messageData

			self:SaveGuildConfig(commandMessage.guild)

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
				commandMessage:reply(string.format("No reply is registered for %s", trigger))
				return
			end
			config.Replies[trigger] = nil

			self:SaveGuildConfig(commandMessage.guild)

			commandMessage:reply(string.format("%s will no longer trigger a reply", trigger))
		end
	})

	self:RegisterCommand({
		Name = "savechannelmessages",
		Args = {
			{Name = "channel", Type = Bot.ConfigType.Channel, Optional = true},
			{Name = "afterMessage", Type = Bot.ConfigType.Message, Optional = true},
			{Name = "limit", Type = Bot.ConfigType.Integer, Optional = true},
			{Name = "fromFirstMessage", Type = Bot.ConfigType.Boolean, Optional = true},
		},
		PrivilegeCheck = function (member) return self:CheckPermissions(member) end,

		Help = "Saves all messages posted in a channel in a json format",
		Func = function (commandMessage, targetChannel, afterMessage, limit, fromFirstMessage)
			limit = limit or 1000
			if commandMessage.member.id ~= Config.OwnerUserId then
				-- Don't allow everyone to bypass limit and get all messages (would require a lot of API calls)
				if limit > 1000 then
					commandMessage:reply("Only bot owner can ask to retrieve more than 1000+ messages at once, due to the number of API calls required to fetch messages")
					return
				end

				limit = math.min(limit, 1000)
			end

			if afterMessage then
				if targetChannel then
					if targetChannel ~= afterMessage.channel then
						commandMessage:reply("Target message doesn't belong to that channel")
						return
					end
				else
					targetChannel = afterMessage.channel
				end
			end

			if not targetChannel then
				targetChannel = commandMessage.channel
			end

			commandMessage.channel:broadcastTyping()

			local messages, err = Bot:FetchChannelMessages(targetChannel, afterMessage and afterMessage.id or nil, limit, not fromFirstMessage)
			if not messages then
				commandMessage:reply(string.format("An error occurred: %s", err))
				return
			end

			local messageData = bot:MessagesToTable(messages)
			messageData.requestedBy = commandMessage.member.id
			
			local jsonSave = json.encode(messageData, { indent = 1})
			commandMessage:reply({ 
				content = string.format("%d message(s) of channel %s have been saved to following file", #messages, targetChannel.mentionString),
				file = {
					"messages.json", 
					jsonSave
				}
			})
		end
	})

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
		reply = table.deepcopy(reply)

		local success, err = ValidateMessageData(reply, message.member, message.guild)
		if (not success) then
			message:reply(err)
			return
		end

		reply.content = self:ReplaceData(reply.content, message.member)
		reply.embed = self:ReplaceData(reply.embed, message.member)
	
		local deleteInvokation = RemoveTableKey(reply, "deleteInvokation")
		if deleteInvokation == nil then
			deleteInvokation = config.DeleteInvokation
		end
		if not deleteInvokation then
			reply.reference = { message = message }
		end

	 	local success, err = message:reply(reply)

		if (not success) then
			self:LogError(message.guild, "Failed to reply to %s: %s", message.content, err)
		elseif deleteInvokation then
			message:delete()
		end
	end
end

function Module:OnMessageDelete(message)
	local persistentData = self:GetPersistentData(message.guild)
	if persistentData.MessageActions then
		persistentData.MessageActions[message.id] = nil
	end
end

function Module:OnMessageDeleteUncached(channel, messageId)
	local persistentData = self:GetPersistentData(channel.guild)
	if persistentData.MessageActions then
		persistentData.MessageActions[messageId] = nil
	end
end

function Module:OnInteractionCreate(interaction)
	local guild = interaction.guild
	if not guild then
		return
	end

	p("interaction.data", interaction.data)

	local persistentData = self:GetPersistentData(guild)
	if not persistentData.MessageActions then
		return
	end

	local messageActions = persistentData.MessageActions[interaction.message.id]
	if not messageActions then
		return
	end

	-- "Waiting"
	interaction:respond({
		type = enums.interactionResponseType.deferredChannelMessageWithSource,
		data = {
			flags = enums.interactionResponseFlag.ephemeral
		}
	})

	local shouldRefresh = false
	local messages = {}

	local function HandleActions(id)
		local actions = messageActions[id]
		if not actions then
			return
		end

		for _, action in pairs(actions) do
			if action.type == "refreshmenu" then
				shouldRefresh = true
			else
				local actionData = possibleActions[action.type]
				if not actionData then
					table.insert(messages, "<invalid action " .. action.type .. ">")
					return
				end

				table.insert(messages, actionData.Action(interaction.member, action.value))
			end
		end
	end

	if interaction.data.component_type == 2 then
		HandleActions(interaction.data.custom_id)
	elseif interaction.data.component_type == 3 then
		for _, value in ipairs(interaction.data.values) do
			HandleActions(value)
		end
	end

	interaction:editResponse({
		content = #messages > 0 and table.concat(messages, "\n") or "Nothing to do",
	})

	-- C'est saaaaaaaaaaaaale
	if shouldRefresh then
		interaction.message:setComponents(interaction.message.components)
	end
end
