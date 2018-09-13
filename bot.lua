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
	Message  = 8,
	Number   = 9,
	Role     = 10,
	String   = 11,
	User	 = 12
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
	[Bot.ConfigType.Member] = tostring,
	[Bot.ConfigType.Message] = function (value, guild)
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

Bot.ConfigTypeParameter = {
	[Bot.ConfigType.Boolean] = function (value, guild) 
		if (value == "yes" or value == "1" or value == "true") then
			return true
		elseif (value == "no" or value == "0" or value == "false") then
			return false
		end
	end,
	[Bot.ConfigType.Channel] = function (value, guild)
		return Bot:DecodeChannel(guild, value)
	end,
	[Bot.ConfigType.Custom] = function (value, guild) 
		return nil
	end,
	[Bot.ConfigType.Duration] = function (value, guild)
		return string.ConvertToTime(value)
	end,
	[Bot.ConfigType.Emoji] = function (value, guild)
		local emojiData = Bot:DecodeEmoji(guild, value)
		return emojiData
	end,
	[Bot.ConfigType.Integer] = function (value, guild)
		return tonumber(value:match("^(%d+)$"))
	end,
	[Bot.ConfigType.Member] = function (value, guild)
		return Bot:DecodeMember(guild, value)
	end,
	[Bot.ConfigType.Message] = function (value, guild)
		return Bot:DecodeMessage(value)
	end,
	[Bot.ConfigType.Number] = function (value)
		return tonumber(value)
	end,
	[Bot.ConfigType.Role] = function (value, guild)
		return guild:getRole(value)
	end,
	[Bot.ConfigType.String] = function (value, guild)
		return value
	end,
	[Bot.ConfigType.User] = function (value, guild)
		return Bot:DecodeUser(value)
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
	[Bot.ConfigType.Message] = function (value, guild)
		local message = Bot:DecodeMessage(value)
		return message and Bot:GenerateMessageLink(message)
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

-- Why is this required Oo
local env = setmetatable({}, { __index = _G })
env.Bot = Bot
env.Client = client
env.Config = Config
env.discordia = discordia
env.require = require

loadfile("bot_emoji.lua", "t", env)()
loadfile("bot_utility.lua", "t", env)()
loadfile("bot_commands.lua", "t", env)()
loadfile("bot_modules.lua", "t", env)()

Bot:RegisterCommand({
	Name = "exec",
	Args = {
		{Name = "filename", Type = Bot.ConfigType.String}
	},
	PrivilegeCheck = function (member) return member.id == Config.OwnerUserId end,

	Help = "Executes a file",
	Func = function (message, fileName)
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
	end
})

Bot:RegisterCommand({
	Name = "save",
	Args = {},
	PrivilegeCheck = function (member) return member.id == Config.OwnerUserId end,

	Help = "Saves bot data",
	Func = function (message)
		Bot:Save()
		message:reply("Bot data saved")
	end
})

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
