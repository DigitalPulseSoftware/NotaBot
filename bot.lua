-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local discordia = require('discordia')
local client = discordia.Client()
local enums = discordia.enums
local fs = require("coro-fs")
local json = require("json")
local path = require("path")
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
Bot.Clock = discordia.Clock()
Bot.Commands = {}
Bot.Events = {}
Bot.Modules = {}

local isReady = false

-- Maps event name to function to retrieve its guild
local discordiaEvents = {
	["channelCreate"] = function (channel) return channel.guild end,
	["channelDelete"] = function (channel) return channel.guild end,
	["channelUpdate"] = function (channel) return channel.guild end,
	["debug"] = function (message) end,
	["emojisUpdate"] = function (guild) return guild end,
	["error"] = function (message) end,
	["guildAvailable"] = function (guild) return guild end,
	["guildCreate"] = function (guild) return guild end,
	["guildDelete"] = function (guild) return guild end,
	["guildUnavailable"] = function (guild) return guild end,
	["guildUpdate"] = function (guild) return guild end,
	["heartbeat"] = function (shardId, latency) end,
	["info"] = function (message) end,
	["memberJoin"] = function (member) return member.guild end,
	["memberLeave"] = function (member) return member.guild end,
	["memberUpdate"] = function (member) return member.guild end,
	["messageCreate"] = function (message) return message.guild end,
	["messageDelete"] = function (message) return message.guild end,
	["messageDeleteUncached"] = function (channel, messageId) return channel.guild end,
	["messageUpdate"] = function (message) return message.guild end,
	["messageUpdateUncached"] = function (channel, messageId) return channel.guild end,
	["pinsUpdate"] = function (channel) return channel.guild end,
	["presenceUpdate"] = function (member) return member.guild end,
	["raw"] = function (string) end,
	["reactionAdd"] = function (reaction, userId) return reaction.message.guild end,
	["reactionAddUncached"] = function (channel, messageId, hash, userId) return channel.guild end,
	["reactionRemove"] = function (reaction, userId) return reaction.message.guild end,
	["reactionRemoveUncached"] = function (channel, messageId, hash, userId) return channel.guild end,
	["ready"] = function () end,
	["recipientAdd"] = function (relationship) end,
	["recipientRemove"] = function (relationship) end,
	["relationshipAdd"] = function (relationship) end,
	["relationshipRemove"] = function (relationship) end,
	["relationshipUpdate"] = function (relationship) end,
	["roleCreate"] = function (role) return role.guild end,
	["roleDelete"] = function (role) return role.guild end,
	["roleUpdate"] = function (role) return role.guild end,
	["shardReady"] = function (shardId) end,
	["shardResumed"] = function (shardId) end,
	["typingStart"] = function (userId, channelId, timestamp)
		local channel = client:getChannel(channelId)
		if (not channel) then
			return
		end

		return channel.guild
	end,
	["userBan"] = function (user, guild) return guild end,
	["userUnban"] = function (user, guild) return guild end,
	["userUpdate"] = function (user) end,
	["voiceChannelJoin"] = function (member, channel) return channel.guild end,
	["voiceChannelLeave"] = function (member, channel) return channel.guild end,
	["voiceConnect"] = function (member) return member.guild end,
	["voiceDisconnect"] = function (member) return member.guild end,
	["voiceUpdate"] = function (member) return member.guild end,
	["warning"] = function (message) end,
	["webhooksUpdate"] = function (channel) return channel.guild end
}

client:onSync("ready", function ()
	print('Logged in as '.. client.user.username)

	if (isReady) then
		for moduleName,moduleTable in pairs(Bot.Modules) do
			Bot:CallOnReady(moduleTable)
		end
	else
		for moduleName,moduleTable in pairs(Bot.Modules) do
			Bot:CallOnReady(moduleTable)
			Bot:MakeModuleReady(moduleTable)
		end
	end

	isReady = true
end)

function Bot:LoadModule(moduleTable)
	self:UnloadModule(moduleTable.Name)

	-- Parse events
	local moduleEvents = {}
	for key,func in pairs(moduleTable) do
		if (key:startswith("On") and type(func) == "function") then
			local eventName = key:sub(3, 3):lower() .. key:sub(4)
			if (eventName ~= "loaded" and eventName ~= "unload" and eventName ~= "enable" and eventName ~= "disable" and eventName ~= "ready") then
				if (not discordiaEvents[eventName]) then
					return false, "Module tried to bind hook \"" .. eventName .. "\" which doesn't exist"
				end

				moduleEvents[eventName] = {Module = moduleTable, Callback = function (moduleTable, ...) self:CallModuleFunction(moduleTable, key, ...) end}
			end
		end
	end
	moduleTable._Events = moduleEvents

	-- Prepare guild data
	moduleTable._Guilds = {}
	function moduleTable:GetGuildData(guildId, noCreate)
		local guildData = self._Guilds[guildId]
		if (not guildData and not noCreate) then
			guildData = {}
			guildData.Config = {}
			guildData.Data = {}
			guildData.PersistentData = {}

			self._Guilds[guildId] = guildData
		end

		return guildData
	end

	function moduleTable:GetData(guild, noCreate)
		local guildData = self:GetGuildData(guild.id, noCreate)
		if (not guildData) then
			return nil
		end

		return guildData.Data
	end

	function moduleTable:GetPersistentData(guild, noCreate)
		local guildData = self:GetGuildData(guild.id, noCreate)
		if (not guildData) then
			return nil
		end

		return guildData.PersistentData
	end

	function moduleTable:ForEachGuild(callback)
		for guildId, data in pairs(self._Guilds) do
			callback(guildId, data.Config, data.Data, data.PersistentData)
		end
	end

	-- Load module persistent data from disk
	self:LoadModuleData(moduleTable)

	function moduleTable:IsEnabledForGuild(guild)
		local persistentData = self:GetPersistentData(guild, true)
		return persistentData and persistentData._Enabled
	end

	local bot = self
	function moduleTable:EnableForGuild(guild, ignoreCheck)
		if (not ignoreCheck and self:IsEnabledForGuild(guild)) then
			return true
		end

		local success, err
		if (self.OnEnable) then
			success, err = bot:CallModuleFunction(self, "OnEnable", guild)
		else
			success = true
		end

		if (success) then
			local persistentData = self:GetPersistentData(guild)
			persistentData._Enabled = true
			client:info("[%s][%s] Module enabled", guild.name, self.Name)
			return true
		else
			return false, err
		end
	end

	function moduleTable:DisableForGuild(guild)
		if (not self:IsEnabledForGuild(guild)) then
			return true
		end

		local success
		if (self.OnDisable) then
			success, err = bot:CallModuleFunction(self, "OnDisable", guild)
		else
			success = true
		end

		if (success) then
			local persistentData = self:GetPersistentData(guild)
			persistentData._Enabled = false
			self:SavePersistentData(guild)

			client:info("[%s][%s] Module disabled", guild.name, self.Name)
			return true
		else
			return false, err
		end
	end

	function moduleTable:SavePersistentData(guild)
		local save = function (guildId, persistentData)
			local filepath = string.format("data/module_%s/guild_%s.json", self.Name, guildId)
			local dirname = path.dirname(filepath)

			local success, err = fs.mkdirp(dirname)
			if (not success) then
				client:warning("Failed to create directory to save module data (%s) for guild %s: %s", self.Name, guildId, err)
				return
			end

			local dataFile = io.open(filepath, "w+")
			if (not dataFile) then
				client:warning("Failed to open save file for module data (%s) for guild %s: %s", self.Name, guildId, err)
				return
			end

			local success, err = dataFile:write(json.encode(persistentData))
			if (not success) then
				client:warning("Failed to write module data (%s) to file for guild %s: %s", self.Name, guildId, err)
				return
			end

			dataFile:close()
		end

		if (guild) then
			local guildData = self:GetPersistentData(guild, true)
			if (guildData) then
				save(guild.id, guildData)
			end
		else
			self:ForEachGuild(function (guildId, config, data, persistentData)
				save(guildId, persistentData)
			end)
		end
	end

	-- Loading finished, call callback
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
		self:MakeModuleReady(moduleTable)
	end

	return moduleTable
end

function Bot:CallOnReady(moduleTable)
	if (moduleTable.OnReady) then
		wrap(function () self:CallModuleFunction(moduleTable, "OnReady") end)()
	end
end

function Bot:MakeModuleReady(moduleTable)
	moduleTable:ForEachGuild(function (guildId, config, data, persistentData)
		moduleTable:EnableForGuild(client:getGuild(guildId), true, true)
	end)

	for eventName,eventData in pairs(moduleTable._Events) do
		local eventTable = self.Events[eventName]
		if (not eventTable) then
			eventTable = {}
			client:onSync(eventName, function (...)
				local eventGuild = discordiaEvents[eventName](...)
				for _, eventData in pairs(eventTable) do
					if (not eventGuild or eventData.Module:IsEnabledForGuild(eventGuild)) then
						wrap(eventData.Callback)(eventData.Module, ...)
					end
				end
			end)

			self.Events[eventName] = eventTable
		end

		table.insert(eventTable, eventData)
	end
end

function Bot:CallModuleFunction(moduleTable, functionName, ...)
	return self:ProtectedCall(string.format("Module (%s) function (%s)", moduleTable.Name, functionName), moduleTable[functionName], moduleTable, ...)
end

function Bot:DisableModule(moduleName, guild)
	local moduleTable = self.Modules[moduleName]
	if (moduleTable) then
		return moduleTable:DisableForGuild(guild)
	end
	
	return false, "Module not loaded"
end

function Bot:EnableModule(moduleName, guild)
	local moduleTable = self.Modules[moduleName]
	if (moduleTable) then
		return moduleTable:EnableForGuild(guild)
	end
	
	return false, "Module not loaded"
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

function Bot:LoadModuleData(moduleTable)
	-- Must be called from within a coroutine
	local dataFolder = string.format("data/module_%s", moduleTable.Name)

	local dataIt = fs.scandir(dataFolder)
	if (dataIt) then
		for entry in assert(dataIt) do
			if (entry.type == "file") then
				local guildId = entry.name:match("guild_(%d+)%.json")
				if (guildId) then
					local dataFile, err = io.open(dataFolder .. "/" .. entry.name, "r")
					if (dataFile) then
						local content = dataFile:read("*a")
						if (content) then
							local success, contentOrErr = pcall(json.decode, content)
							if (success) then
								local guildData = moduleTable:GetGuildData(guildId)
								guildData.PersistentData = contentOrErr
							else
								client:error("Failed to decode persistent data json for guild %s (module: %s): %s", guildId, moduleTable.Name, contentOrErr)
							end
						else
							client:error("Failed to read persistent data for guild %s (module: %s): %s", guildId, moduleTable.Name, err)
						end

						dataFile:close()
					else
						client:error("Failed to open persistent data file for guild %s (module: %s): %s", guildId, moduleTable.Name, err)
					end
				end
			end
		end
	end
end

function Bot:Save()
	for _, moduleTable in pairs(self.Modules) do
		self:ProtectedCall(string.format("Module (%s) save", moduleTable.Name), moduleTable.SavePersistentData, moduleTable)
	end
end

local saveCounter = 0
Bot.Clock:on("min", function ()
	saveCounter = saveCounter + 1
	if (saveCounter >= 5) then
		Bot:Save()

		saveCounter = 0
	end
end)

function Bot:UnloadModule(moduleName)
	local moduleTable = self.Modules[moduleName]
	if (moduleTable) then
		if (isReady and moduleTable.OnUnload) then
			moduleTable:OnUnload()
		end

		moduleTable:SavePersistentData()

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

function Bot:DecodeUser(guild, message)
	assert(guild)
	assert(message)

	local userId = message:match("<@!?(%d+)>")
	if (userId) then
		return guild:getMember(userId)
	end

	return nil
end

function Bot:GenerateMessageLink(message)
	local guildId = message.guild and message.guild.id or "@me"
	return string.format("https://discordapp.com/channels/%s/%s/%s", guildId, message.channel.id, message.id)
end

-- Why is this required Oo
local env = setmetatable({ }, { __index = _G })
env.Bot = Bot
env.Client = client
env.Config = Config
env.discordia = discordia
env.require = require

loadfile("bot_emoji.lua", "t", env)()

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

Bot:RegisterCommand("disable", "Disables a module", function (message, moduleName)
	if (not message.member:hasPermission(enums.permission.administrator)) then
		print(tostring(message.member.name) .. " tried to use !disable")
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
	if (not message.member:hasPermission(enums.permission.administrator)) then
		print(tostring(message.member.name) .. " tried to use !save")
		return
	end
	
	Bot:Save()
	message:reply("Bot data saved")
end)

Bot:RegisterCommand("unload", "Unloads a module", function (message, moduleName)
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

Bot.Clock:start()

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
