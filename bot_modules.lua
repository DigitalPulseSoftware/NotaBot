-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local fs = require("coro-fs")
local wrap = coroutine.wrap

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
	["typingStart"] = function (userId, channelId, timestamp, client)
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

local ModuleMetatable = {}
ModuleMetatable["__index"] = ModuleMetatable

-- Config validation
local validateSnowflake = function (snowflake)
	if (type(snowflake) ~= "string") then
		return false
	end

	return string.match(snowflake, "%d+")
end

local configTypeValidation = {
	[Bot.ConfigType.Boolean] = function (value) return type(value) == "boolean" end,
	[Bot.ConfigType.Channel] = validateSnowflake,
	[Bot.ConfigType.Custom] = function (value) return true end,
	[Bot.ConfigType.Duration] = function (value) return type(value) == "number" end,
	[Bot.ConfigType.Emoji] = function (value) return type(value) == "string" end,
	[Bot.ConfigType.Integer] = function (value) return type(value) == "number" and math.floor(value) == value end,
	[Bot.ConfigType.Number] = function (value) return type(value) == "number" end,
	[Bot.ConfigType.Role] = validateSnowflake,
	[Bot.ConfigType.String] = function (value) return type(value) == "string" end,
	[Bot.ConfigType.User] = validateSnowflake,
}

local validateConfigType = function (configTable, value)
	local validator = configTypeValidation[configTable.Type]
	assert(validator)

	if (configTable.Array) then
		if (type(value) ~= "table") then
			return false
		end

		for _, arrayValue in pairs(value) do
			if (not validator(arrayValue)) then
				return false
			end
		end

		return true
	else
		return validator(value)
	end
end

function ModuleMetatable:_PrepareConfig(guildId, guildConfig)
	local moduleConfig = self._Config

	for optionIndex, configTable in pairs(moduleConfig) do
		local reset = false
		local guildConfigValue = guildConfig[configTable.Name]
		if (guildConfigValue == nil) then
			reset = true
		elseif (not validateConfigType(configTable, guildConfigValue)) then
			self:LogWarning("Guild %s has invalid value for option %s, resetting...", guildId, configTable.Name)
			reset = true
		end

		if (reset) then
			local default = configTable.Default
			if (type(default) == "table") then
				guildConfig[configTable.Name] = table.deepcopy(default)
			else
				guildConfig[configTable.Name] = default
			end
		end
	end
end

function ModuleMetatable:DisableForGuild(guild)
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
		local config = self:GetConfig(guild)
		config._Enabled = false
		self:SaveConfig(guild)

		self:LogInfo(guild, "Module disabled")
		return true
	else
		return false, err
	end
end

function ModuleMetatable:EnableForGuild(guild, ignoreCheck, dontSave)
	if (not ignoreCheck and self:IsEnabledForGuild(guild)) then
		return true
	end

	local stopwatch = discordia.Stopwatch()

	local success, ret
	if (self.OnEnable) then
		local success, retOrErr, err = Bot:CallModuleFunction(self, "OnEnable", guild)
		if (not success) then
			return false, retOrErr
		end

		if (not retOrErr) then
			return false, err or "OnEnable hook returned false"
		end
	end

	local guildData = self:GetGuildData(guild.id)
	guildData._Ready = true
	guildData.Config._Enabled = true

	if (not dontSave) then
		self:SaveConfig(guild)
	end

	self:LogInfo(guild, "Module enabled (%.3fs)", stopwatch.milliseconds / 1000)
	return true
end

function ModuleMetatable:ForEachGuild(callback, evenDisabled, evenNonReady)
	for guildId, data in pairs(self._Guilds) do
		if ((evenNonReady or data._Ready) and (evenDisabled or data.Config._Enabled)) then
			callback(guildId, data.Config, data.Data, data.PersistentData)
		end
	end
end

function ModuleMetatable:GetConfig(guild, noCreate)
	local guildData = self:GetGuildData(guild.id, noCreate)
	if (not guildData) then
		return nil
	end

	return guildData.Config
end

function ModuleMetatable:GetData(guild, noCreate)
	local guildData = self:GetGuildData(guild.id, noCreate)
	if (not guildData) then
		return nil
	end

	return guildData.Data
end

function ModuleMetatable:GetGuildData(guildId, noCreate)
	local guildData = self._Guilds[guildId]
	if (not guildData and not noCreate) then
		guildData = {}
		guildData.Config = {}
		guildData.Data = {}
		guildData.PersistentData = {}
		guildData._Ready = false

		self:_PrepareConfig(guildId, guildData.Config)

		self._Guilds[guildId] = guildData
	end

	return guildData
end

function ModuleMetatable:GetPersistentData(guild, noCreate)
	local guildData = self:GetGuildData(guild.id, noCreate)
	if (not guildData) then
		return nil
	end

	return guildData.PersistentData
end

function ModuleMetatable:IsEnabledForGuild(guild)
	local config = self:GetConfig(guild, true)
	return config and config._Enabled or false
end

-- Log functions (LogError, LogInfo, LogWarning)
for k, func in pairs({"error", "info", "warning"}) do
	ModuleMetatable["Log" .. string.UpperizeFirst(func)] = function (moduleTable, guild, ...)
		if (type(guild) == "string") then
			Bot.Client[func](Bot.Client, "[%s][%s] %s", "<*>", moduleTable.Name, string.format(guild, ...))
		else
			Bot.Client[func](Bot.Client, "[%s][%s] %s", guild and guild.name or "<Invalid guild>", moduleTable.Name, string.format(...))
		end
	end
end

function ModuleMetatable:Save(guild)
	self:SaveConfig(guild)
	self:SavePersistentData(guild)
end

function ModuleMetatable:SaveConfig(guild)
	local save = function (guildId, guildConfig)
		local filepath = string.format("data/module_%s/guild_%s/config.json", self.Name, guildId)
		local success, err = Bot:SerializeToFile(filepath, guildConfig, true)
		if (not success) then
			self:LogWarning(guild, "Failed to save persistent data: %s", err)
		end
	end

	if (guild) then
		local guildConfig = self:GetConfig(guild, true)
		if (guildConfig) then
			save(guild.id, guildConfig)
		end
	else
		self:ForEachGuild(function (guildId, config, data, persistentData)
			save(guildId, config)
		end)
	end
end

function ModuleMetatable:SavePersistentData(guild)
	local save = function (guildId, persistentData)
		local filepath = string.format("data/module_%s/guild_%s/persistentdata.json", self.Name, guildId)
		local success, err = Bot:SerializeToFile(filepath, persistentData)
		if (not success) then
			self:LogWarning(guild, "Failed to save persistent data: %s", err)
		end
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

function Bot:CallModuleFunction(moduleTable, functionName, ...)
	return self:ProtectedCall(string.format("Module (%s) function (%s)", moduleTable.Name, functionName), moduleTable[functionName], moduleTable, ...)
end

function Bot:CallOnReady(moduleTable)
	if (moduleTable.OnReady) then
		wrap(function () self:CallModuleFunction(moduleTable, "OnReady") end)()
	end
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

function Bot:LoadModule(moduleTable)
	self:UnloadModule(moduleTable.Name)

	local stopwatch = discordia.Stopwatch()

	-- Load config
	local config
	if (moduleTable.GetConfigTable) then
		local success, ret = self:CallModuleFunction(moduleTable, "GetConfigTable")
		if (not success) then
			return false, "Failed to load config: " .. ret
		end

		if (type(ret) ~= "table") then
			return false, "Invalid config"
		end
		config = ret

		-- Validate config
		local validConfigOptions = {
			["Array"] = {"boolean", false, false},
			["Default"] = {"any", false},
			["Description"] = {"string", true},
			["Global"] = {"boolean", false, false},
			["Optional"] = {"boolean", false, false},
			["Name"] = {"string", true},
			["Type"] = {"number", true}
		}

		for optionIndex, configTable in pairs(config) do
			for configName, configValue in pairs(configTable) do
				local expectedType = validConfigOptions[configName][1]
				if (not expectedType) then
					return false, string.format("Option #%s has invalid key \"%s\"", optionIndex, configName)
				end

				if (expectedType ~= "any" and type(configValue) ~= expectedType) then
					return false, string.format("Option #%s has key \"%s\" which has invalid type %s (expected %s)", optionIndex, configName, type(configValue), expectedType)
				end
			end

			for key, value in pairs(validConfigOptions) do
				local mandatory = value[2]
				if (mandatory) then
					if (not configTable[key]) then
						return false, string.format("Option #%s has no \"%s\" key", optionIndex, key)
					end
				else
					if (configTable[key] == nil) then
						local defaultValue = value[3]
						configTable[key] = defaultValue
					end
				end
			end

			if (not configTable.Default and not configTable.Optional) then
				return false, string.format("Option #%s is not optional and has no default value", optionIndex)
			end
		end
	else
		config = {}
	end
	moduleTable._Config = config

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

	setmetatable(moduleTable, ModuleMetatable)

	-- Load module persistent data from disk
	self:LoadModuleData(moduleTable)

	moduleTable:ForEachGuild(function (guildId, config, data, persistentData)
		moduleTable:_PrepareConfig(guildId, config)
	end, true, true)

	-- Loading finished, call callback
	self.Modules[moduleTable.Name] = moduleTable
	
	if (moduleTable.OnLoaded) then
		local success, err = self:CallModuleFunction(moduleTable, "OnLoaded")
		if (not success or not err) then
			self.Modules[moduleTable.Name] = nil

			err = err or "OnLoaded hook returned false"
			return false, err
		end
	end

	local loadTime = stopwatch.milliseconds / 1000
	self.Client:info("[<*>][%s] Loaded module (%.3fs)", moduleTable.Name, stopwatch.milliseconds / 1000)

	if (isReady) then
		self:CallOnReady(moduleTable)
		self:MakeModuleReady(moduleTable)
	end

	return moduleTable
end

function Bot:LoadModuleFile(fileName)
	local sandbox = setmetatable({ }, { __index = _G })
	sandbox.Bot = self
	sandbox.Client = self.Client
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
			if (entry.type == "directory") then
				local guildId = entry.name:match("guild_(%d+)")
				if (guildId) then
					local guildData = moduleTable:GetGuildData(guildId)

					local config, err = self:UnserializeFromFile(dataFolder .. "/" .. entry.name .. "/config.json")
					if (config) then
						guildData.Config = config
					else
						self.Client:error("Failed to load config of guild %s (%s module): %s", guildId, moduleTable.Name, err)
					end

					local persistentData, err = self:UnserializeFromFile(dataFolder .. "/" .. entry.name .. "/persistentdata.json")
					if (config) then
						guildData.PersistentData = persistentData
					else
						self.Client:error("Failed to load persistent data of guild %s (%s module): %s", guildId, moduleTable.Name, err)
					end
				end
			end
		end
	end
end

function Bot:MakeModuleReady(moduleTable)
	moduleTable:ForEachGuild(function (guildId, config, data, persistentData)
		moduleTable:EnableForGuild(self.Client:getGuild(guildId), true, true)
	end, true, true)

	for eventName,eventData in pairs(moduleTable._Events) do
		local eventTable = self.Events[eventName]
		if (not eventTable) then
			eventTable = {}
			self.Client:onSync(eventName, function (...)
				local eventGuild = discordiaEvents[eventName](..., self.Client)
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

		self.Client:info("[<*>][%s] Unloaded module", moduleTable.Name)
		return true
	end
	
	return false
end

Bot.Client:onSync("ready", function ()
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
