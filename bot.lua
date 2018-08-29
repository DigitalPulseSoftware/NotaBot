-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local discordia = require('discordia')
local client = discordia.Client()
local enums = discordia.enums
local wrap = coroutine.wrap

discordia.extensions() -- load all helpful extensions

local function code(str)
    return string.format('```\n%s```', str)
end

local function printLine(...)
    local ret = {}
    for i = 1, select('#', ...) do
        local arg = tostring(select(i, ...))
        table.insert(ret, arg)
    end
    return table.concat(ret, '\t')
end

dofile("utils.lua")

-- Config

Config = {}
local func, err = loadfile("config.lua", "bt", Config)
if (not func) then
	print("Failed to load config file:\n" .. code(tostring(err)))
	return
end

local ret, err = pcall(func)
if (not ret) then
	print("Failed to execute config file:\n" .. code(tostring(err)))
	return
end

-- Bot code

Bot = {}
Bot.Client = client
Bot.Clock = discordia.Clock()
Bot.Commands = {}
Bot.Events = {}
Bot.Modules = {}
Bot.ConfigType = enums.enum {
	Boolean  = 0,
	Channel  = 1,
	Custom   = 2,
	Duration = 3,
	Emoji    = 4,
	Integer  = 5,
	Member   = 7,
	Number   = 8,
	Role     = 9,
	String   = 10,
	User	 = 11
}

Bot.ConfigTypeString = {}
for name,value in pairs(Bot.ConfigType) do
	Bot.ConfigTypeString[value] = name
end

Bot.ConfigTypeToString = {
	[Bot.ConfigType.Boolean] = tostring,
	[Bot.ConfigType.Channel] = function (value, guild)
		local channel = guild:getChannel(value)
		return channel and channel.mentionString or "<Invalid channel>"
	end,
	[Bot.ConfigType.Custom] = function (value, guild) return "<custom-type>" end,
	[Bot.ConfigType.Duration] = function (value, guild) return util.FormatTime(value) end,
	[Bot.ConfigType.Emoji] = function (value, guild)
		local emojiData = Bot:GetEmojiData(guild, value)
		return emojiData and emojiData.MentionString or "<Invalid emoji>"
	end,
	[Bot.ConfigType.Integer] = tostring,
	[Bot.ConfigType.Member] = function (value, guild)
		local member = guild:getMember(value)
		return member and member.user.mentionString or "<Invalid member>"
	end,
	[Bot.ConfigType.Number] = function (value) return type(value) == "number" end,
	[Bot.ConfigType.Role] = function (value, guild)
		local role = guild:getRole(value)
		return role and role.mentionString or "<Invalid role>"
	end,
	[Bot.ConfigType.String] = tostring,
	[Bot.ConfigType.User] = function (value, guild)
		local user = client:getUser(value)
		return user and user.mentionString or "<Invalid user>"
	end
}

Bot.ConfigTypeParser = {
	[Bot.ConfigType.Boolean] = function (value, guild) 
		if (value == "yes" or value == "1" or value == "true") then
			return true
		elseif (value == "no" or value == "0" or value == "false") then
			return false
		end
	end,
	[Bot.ConfigType.Channel] = function (value, guild)
		local channel = Bot:DecodeChannel(guild, value)
		return channel and channel.id
	end,
	[Bot.ConfigType.Custom] = function (value, guild) 
		return nil
	end,
	[Bot.ConfigType.Duration] = function (value, guild)
		return string.ConvertToTime(value)
	end,
	[Bot.ConfigType.Emoji] = function (value, guild)
		local emojiData = Bot:DecodeEmoji(guild, value)
		return emojiData and emojiData.Name
	end,
	[Bot.ConfigType.Integer] = function (value, guild)
		return tonumber(value:match("^(%d+)$"))
	end,
	[Bot.ConfigType.Member] = function (value, guild)
		local member = Bot:DecodeMember(guild, value)
		return member and member.id
	end,
	[Bot.ConfigType.Number] = function (value)
		return tonumber(value)
	end,
	[Bot.ConfigType.Role] = function (value, guild)
		local role = guild:getRole(value)
		return role and role.id
	end,
	[Bot.ConfigType.String] = function (value, guild)
		return value
	end,
	[Bot.ConfigType.User] = function (value, guild)
		local user = Bot:DecodeUser(value)
		return user and user.id
	end
}

client:onSync("ready", function ()
	print('Logged in as '.. client.user.username)
end)

function Bot:Save()
	local stopwatch = discordia.Stopwatch()

	for _, moduleTable in pairs(self.Modules) do
		self:ProtectedCall(string.format("Module (%s) persistent data save", moduleTable.Name), moduleTable.SavePersistentData, moduleTable)
	end

	client:info("Modules data saved (%.3fs)", stopwatch.milliseconds / 1000)
end

local saveCounter = 0
Bot.Clock:on("min", function ()
	saveCounter = saveCounter + 1
	if (saveCounter >= 5) then
		Bot:Save()

		saveCounter = 0
	end
end)

function Bot:RegisterCommand(commandName, description, exec)
	self.Commands[commandName] = {
		help = description,
		func = exec
	}
end

function Bot:UnregisterCommand(commandName)
	self.Commands[commandName] = nil
end

-- Why is this required Oo
local env = setmetatable({ }, { __index = _G })
env.Bot = Bot
env.Client = client
env.Config = Config
env.discordia = discordia
env.require = require

loadfile("bot_emoji.lua", "t", env)()
loadfile("bot_utility.lua", "t", env)()
loadfile("bot_modules.lua", "t", env)()

Bot:RegisterCommand("exec", "Executes a file", function (message, fileName)
	if (message.member.id ~= Config.OwnerUserId) then
		print(tostring(message.member.name) .. " tried to use !exec")
		return
	end

	if (not fileName) then
		message:reply("You must enter a filename")
		return
	end

	local sandbox = setmetatable({ }, { __index = _G })
	sandbox.Bot = Bot
	sandbox.Client = client
	sandbox.Config = Config
	sandbox.CommandMessage = message
	sandbox.Discordia = discordia
	sandbox.require = require

	local lines = {}
	sandbox.print = function(...)
		table.insert(lines, printLine(...))
	end

	local func, err = loadfile(fileName, "bt", sandbox)
	if (not func) then
		message:reply("Failed to load file:\n" .. code(tostring(err)))
		return
	end

	local ret, err = pcall(func)
	if (not ret) then
		message:reply("Failed to call file:\n" .. code(tostring(err)))
		return
	end

	if (#lines > 0) then
		lines = table.concat(lines, '\n')
		if #lines > 1990 then -- truncate long messages
			lines = lines:sub(1, 1990)
		end

		message:reply(code(lines))
	end
end)

Bot:RegisterCommand("modulelist", "Lists modules", function (message)
	if (not message.member:hasPermission(enums.permission.administrator)) then
		print(tostring(message.member.name) .. " tried to use !modules")
		return
	end

	local moduleList = {}
	for moduleName, moduleTable in pairs(Bot.Modules) do
		table.insert(moduleList, moduleTable)
	end
	table.sort(moduleList, function (a, b) return a.Name < b.Name end)

	local moduleListStr = {}
	for _, moduleTable in pairs(moduleList) do
		table.insert(moduleListStr, string.format("%s **%s**", moduleTable:IsEnabledForGuild(message.guild) and ":white_check_mark:" or ":x:", moduleTable.Name))
	end

	message:reply({
		embed = {
			title = "Module list",
			fields = {
				{name = "Loaded modules", value = table.concat(moduleListStr, '\n')},
			},
			timestamp = discordia.Date():toISO('T', 'Z')
		}
	})
end)

Bot:RegisterCommand("config", "Configures a module", function (message, moduleName, action, key, ...)
	if (not message.member:hasPermission(enums.permission.administrator)) then
		print(tostring(message.member.name) .. " tried to use !config")
		return
	end

	if (not moduleName) then
		message:reply("You must enter a module name")
		return
	end

	moduleName = moduleName:lower()

	local moduleTable = Bot.Modules[moduleName]
	if (not moduleTable) then
		message:reply("Invalid module \"" .. moduleName .. "\"")
		return
	end

	action = action and action:lower() or "list"

	local guild = message.guild
	local config = moduleTable:GetConfig(guild)

	local StringifyConfigValue = function (configTable, value)
		if (value ~= nil) then
			local valueToString = Bot.ConfigTypeToString[configTable.Type]
			if (configTable.Array) then
				valueStr = {}
				for _, value in pairs(value) do
					table.insert(valueStr, valueToString(value, guild))
				end

				return table.concat(valueStr, ", ")
			else
				return valueToString(value, guild)
			end
		else
			assert(configTable.Optional)
			return "<None>"
		end
	end

	if (action == "list") then
		local fields = {}
		for k,configTable in pairs(moduleTable._Config) do
			local valueStr = StringifyConfigValue(configTable, config[configTable.Name])
			local fieldType = Bot.ConfigTypeString[configTable.Type]

			table.insert(fields, {
				name = ":gear: " .. configTable.Name,
				value = string.format("**Description:** %s\n**Value (%s):** %s", configTable.Description, fieldType, valueStr)
			})
		end

		local enabledText
		if (moduleTable:IsEnabledForGuild(guild)) then
			enabledText = ":white_check_mark: Module **enabled** (use `!disable " .. moduleTable.Name .. "` to disable it)"
		else
			enabledText = ":x: Module **disabled** (use `!enable " .. moduleTable.Name .. "` to enable it)"
		end

		message:reply({
			embed = {
				title = "Configuration for " .. moduleTable.Name .. " module",
				description = string.format("%s\n\nConfiguration list:", enabledText, moduleTable.Name),
				fields = fields,
				footer = {text = string.format("Use `!config %s add/remove/reset/set ConfigName <value>` to change configuration settings.", moduleTable.Name)}
			}
		})
	elseif (action == "add" or action == "remove" or action == "reset" or action == "set") then
		if (not key) then
			message:reply("Missing config key name")
			return
		end

		local configTable
		for k,configData in pairs(moduleTable._Config) do
			if (configData.Name == key) then
				configTable = configData
				break
			end
		end

		if (not configTable) then
			message:reply(string.format("Module %s has no config key \"%s\"", moduleTable.Name, key))
			return
		end

		if (not configTable.Array and (action == "add" or action == "remove")) then
			message:reply("Configuration **" .. configTable.Name .. "** is not an array, use the *set* action to change its value")
			return
		end

		local newValue
		if (action ~= "reset") then
			local value = table.concat({...}, " ")
			if (not value or #value == 0) then
				if (configTable.Optional and action == "set") then
					value = nil
				else
					message:reply("Missing config value")
					return
				end
			end

			if (value) then
				local valueParser = Bot.ConfigTypeParser[configTable.Type]

				newValue = valueParser(value, guild)
				if (newValue == nil) then
					message:reply("Failed to parse new value (type: " .. Bot.ConfigTypeString[configTable.Type] .. ")")
					return
				end
			end
		else
			local default = configTable.Default
			if (type(default) == "table") then
				newValue = table.deepcopy(default)
			else
				newValue = default
			end
		end

		local wasModified = false

		if (action == "add") then
			assert(configTable.Array)
			-- Insert value (if not present)
			local found = false
			local values = config[configTable.Name]
			for _, value in pairs(values) do
				if (value == newValue) then
					found = true
					break
				end
			end

			if (not found) then
				table.insert(values, newValue)
				wasModified = true
			end
		elseif (action == "remove") then
			assert(configTable.Array)
			-- Remove value (if present)
			local values = config[configTable.Name]
			for i = 1, #values do
				if (values[i] == newValue) then
					table.remove(values, i)
					wasModified = true
					break
				end
			end
		elseif (action == "reset" or action == "set") then
			-- Replace value
			if (configTable.Array and action ~= "reset") then
				config[configTable.Name] = {newValue}
			else
				config[configTable.Name] = newValue
			end

			wasModified = true
		end

		if (wasModified) then
			moduleTable:SaveConfig(guild)
		end

		local valueStr =  StringifyConfigValue(configTable, config[configTable.Name])
		local fieldType = Bot.ConfigTypeString[configTable.Type]

		message:reply({
			embed = {
				title = "Configuration update for " .. moduleTable.Name .. " module",
				fields = {
					{
						name = ":gear: " .. configTable.Name,
						value = string.format("**Description:** %s\n**New value (%s):** %s%s", configTable.Description, fieldType, valueStr, wasModified and "" or " (nothing changed)")
					}
				},
				timestamp = discordia.Date():toISO('T', 'Z')
			}
		})
	else
		message:reply("Invalid action \"" .. action .. "\" (valid actions are *add*, *remove* or *set*)")
	end
end)

Bot:RegisterCommand("load", "(Re)loads a module", function (message, moduleFile)
	if (message.member.id ~= Config.OwnerUserId) then
		print(tostring(message.member.name) .. " tried to use !load")
		return
	end

	if (not moduleFile) then
		message:reply("You must enter a module filename")
		return
	end

	local moduleTable, err, codeErr = Bot:LoadModuleFile(moduleFile)
	if (moduleTable) then
		message:reply("Module **" .. moduleTable.Name .. "** loaded")
	else
		local errorMessage = err
		if (codeErr) then
			errorMessage = errorMessage .. "\n" .. code(codeErr)
		end

		message:reply("Failed to load module: " .. errorMessage)
		return
	end
end)

Bot:RegisterCommand("disable", "Disables a module", function (message, moduleName)
	if (not message.member:hasPermission(enums.permission.administrator)) then
		print(tostring(message.member.name) .. " tried to use !enable")
		return
	end

	if (not moduleName) then
		message:reply("You must enter a module name")
		return
	end

	local success, err = Bot:DisableModule(moduleName, message.guild)
	if (success) then
		message:reply("Module **" .. moduleName .. "** disabled")
	else
		message:reply("Failed to disable module: " .. err)
	end
end)

Bot:RegisterCommand("enable", "Enables a module", function (message, moduleName)
	if (not message.member:hasPermission(enums.permission.administrator)) then
		print(tostring(message.member.name) .. " tried to use !enable")
		return
	end

	if (not moduleName) then
		message:reply("You must enter a module name")
		return
	end

	local success, err = Bot:EnableModule(moduleName, message.guild)
	if (success) then
		message:reply("Module **" .. moduleName .. "** enabled")
	else
		message:reply("Failed to enable module: " .. tostring(err))
	end
end)

Bot:RegisterCommand("save", "Saves bot data", function (message)
	if (message.member.id ~= Config.OwnerUserId) then
		print(tostring(message.member.name) .. " tried to use !save")
		return
	end
	
	Bot:Save()
	message:reply("Bot data saved")
end)

Bot:RegisterCommand("unload", "Unloads a module", function (message, moduleName)
	if (message.member.id ~= Config.OwnerUserId) then
		print(tostring(message.member.name) .. " tried to use !unload")
		return
	end
	
	if (not moduleName) then
		message:reply("You must enter a module name")
		return
	end

	if (Bot:UnloadModule(moduleName)) then
		message:reply("Module \"" .. moduleName .. "\" unloaded.")
	else
		message:reply("Module \"" .. moduleName .. "\" not found.")
	end
end)

client:on('messageCreate', function(message)
	if (message.channel.type ~= enums.channelType.text) then
		return
	end

	local prefix = '!'
	local content = message.content
	if (content:sub(1,1) ~= prefix) then
		return
	end
	
	local args = content:split(" ")
	local commandName = args[1]:sub(2)
	local commandTable = Bot.Commands[commandName]
	if (commandTable) then
		Bot:ProtectedCall("Command " .. commandName, commandTable.func, message, table.unpack(args, 2))
	end
end)

Bot.Clock:start()

client:run('Bot ' .. Config.Token)

for k,moduleFile in pairs(Config.AutoloadModules) do
	wrap(function ()
		local moduleTable, err, codeErr = Bot:LoadModuleFile(moduleFile)
		if (moduleTable) then
			client:info("Auto-loaded module \"%s\"", moduleTable.Name)
		else
			local errorMessage = err
			if (codeErr) then
				errorMessage = errorMessage .. "\n" .. codeErr
			end

			client:error(errorMessage)
		end
	end)()
end
