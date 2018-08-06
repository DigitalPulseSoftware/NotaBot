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
Bot.Commands = {}
Bot.EmojiCache = {}
Bot.Events = {}
Bot.Modules = {}

local isReady = false

client:onSync("ready", function ()
	print('Logged in as '.. client.user.username)
	isReady = true

	for moduleName,moduleTable in pairs(Bot.Modules) do
		Bot:EnableModule(moduleTable)
	end
end)

function Bot:LoadModule(moduleTable)
	self:UnloadModule(moduleTable.Name)

	local moduleEvents = {}
	for key,func in pairs(moduleTable) do
		if (key:startswith("On") and type(func) == "function") then
			local eventName = key:sub(3, 3):lower() .. key:sub(4)
			if (eventName ~= "loaded" and eventName ~= "unload") then
				moduleEvents[eventName] = function (...) self:CallModuleFunction(moduleTable, key, ...) end
			end
		end
	end
	moduleTable._Events = moduleEvents
	
	self.Modules[moduleTable.Name] = moduleTable
	
	if (moduleTable.OnLoaded) then
		local success, err = self:CallModuleFunction(moduleTable, "OnLoaded")
		if (not success) then
			self.Modules[moduleTable.Name] = nil

			err = err or "OnLoaded hook returned false"
			return false, err
		end
	end

	print("Loaded module " .. moduleTable.Name)

	if (isReady) then
		self:EnableModule(moduleTable)
	end

	return moduleTable
end

function Bot:EnableModule(moduleTable)
	if (moduleTable.OnReady) then
		wrap(function () self:CallModuleFunction(moduleTable, "OnReady") end)()
	end

	for eventName,cb in pairs(moduleTable._Events) do
		local eventTable = self.Events[eventName]
		if (not eventTable) then
			eventTable = {}
			client:onSync(eventName, function (...)
				for k,cb in pairs(eventTable) do
					wrap(cb)(...)
				end
			end)

			self.Events[eventName] = eventTable
		end

		table.insert(eventTable, cb)
	end
end

function Bot:CallModuleFunction(moduleTable, functionName, ...)
	return self:ProtectedCall(string.format("Module (%s) function (%s)", moduleTable.Name, functionName), moduleTable[functionName], moduleTable, ...)
end

function Bot:LoadModuleFile(fileName)
	local sandbox = setmetatable({ }, { __index = _G })
	sandbox.Bot = self
	sandbox.Client = client
	sandbox.Config = Config
	sandbox.Discordia = discordia
	sandbox.Module = {}
	sandbox.require = require -- I still don't understand why we have to do this

	local func, err = loadfile(fileName, "bt", sandbox)
	if (not func) then
		return false, "Failed to load module:", err
	end

	local ret, err = pcall(func)
	if (not ret) then
		return false, "Failed to call module:", err
	end

	local moduleName = sandbox.Module.Name
	if (not moduleName or type(moduleName) ~= "string") then
		return false, "Module has an invalid name"
	end

	return self:LoadModule(sandbox.Module)
end

function Bot:UnloadModule(moduleName)
	local moduleTable = self.Modules[moduleName]
	if (moduleTable) then
		if (isReady and moduleTable.OnUnload) then
			moduleTable:OnUnload()
		end

		for eventName,func in pairs(moduleTable._Events) do
			local eventTable = self.Events[eventName]
			assert(eventTable)
			local i = table.search(eventTable, func)
			assert(i)

			table.remove(eventTable, i)
		end

		self.Modules[moduleName] = nil
		print("Unloaded module " .. moduleTable.Name)
		return true
	end
	
	return false
end

function Bot:ProtectedCall(context, func, ...)
	local success, err = pcall(func, ...)
	if (not success) then
		err = string.format("%s failed: %s", context, err)
		client:warning(err)
		return false, err
	end

	return true
end

function Bot:RegisterCommand(commandName, description, exec)
	self.Commands[commandName] = {
		help = description,
		func = exec
	}
end

function Bot:UnregisterCommand(commandName)
	self.Commands[commandName] = nil
end


function Bot:GetEmojiData(guild, emojiIdOrName)
	local emojiCache = self.EmojiCache[guild.id]
	if (not emojiCache) then
		emojiCache = {}
		self.EmojiCache[guild.id] = emojiCache
	end

	local reactionData = emojiCache[reactionIdOrName]
	if (not reactionName) then
		for k,emoji in pairs(guild.emojis) do
			if (emojiIdOrName == emoji.id or emojiIdOrName == emoji.name) then
				reactionData = {}
				reactionData.Custom = true
				reactionData.Emoji = emoji
				reactionData.Id = emoji.id
				reactionData.Name = emoji.name
				reactionData.MentionString = emoji.mentionString
				break
			end
		end

		if (not reactionData) then
			reactionData = {}
			reactionData.Custom = false
			reactionData.Id = emojiIdOrName
			reactionData.Name = emojiIdOrName
			reactionData.MentionString = emojiIdOrName
		end

		emojiCache[reactionData.Id] = reactionData
		emojiCache[reactionData.Name] = reactionData
	end

	return reactionData
end

client:on('emojisUpdate', function (guild)
	Bot.EmojiCache[guild.id] = nil
end)


Bot:RegisterCommand("exec", "Executes a file", function (message, fileName)
	if (not message.member:hasPermission(enums.permission.administrator)) then
		print(tostring(message.member.name) .. " tried to use !exec")
		return
	end

	if (not fileName) then
		message:reply("You must enter a filename")
		return
	end

	local sandbox = setmetatable({ }, { __index = _G })
	sandbox.Bot = self
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

Bot:RegisterCommand("load", "(Re)loads a module", function (message, moduleFile)
	if (not message.member:hasPermission(enums.permission.administrator)) then
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

Bot:RegisterCommand("unload", "Unload a module", function (message, moduleName)
	if (not message.member:hasPermission(enums.permission.administrator)) then
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

client:run('Bot ' .. Config.Token)

for k,moduleFile in pairs(Config.AutoloadModules) do
	wrap(function ()
		local moduleTable, err, codeErr = Bot:LoadModuleFile(moduleFile)
		if (moduleTable) then
			print("Auto-loaded module \"" .. moduleTable.Name .. "\"")
		else
			local errorMessage = err
			if (codeErr) then
				errorMessage = errorMessage .. "\n" .. codeErr
			end

			print(errorMessage)
		end
	end)()
end
