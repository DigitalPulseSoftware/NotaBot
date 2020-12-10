-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local enums = discordia.enums
local fs = require("coro-fs")
local http = require("coro-http")
local json = require("json")
local wrap = coroutine.wrap

local isReady = false

local function code(str)
	return string.format('```\n%s```', str)
end

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

local botModuleEvents = {
	["disable"] = true,
	["enable"] = true,
	["loaded"] = true,
	["ready"] = true,
	["unload"] = true
}

local ConfigMetatable = {}
function ConfigMetatable:__newindex(key, value)
	print(debug.traceback())
	error("Invalid config key " .. tostring(key) .. " for writing")
end

local ModuleMetatable = {}
ModuleMetatable["__index"] = ModuleMetatable

function ModuleMetatable:HandleConfigUpdate(guild, config, configName)
end

-- Config validation

local configTypeValidation = {
	[Bot.ConfigType.Boolean] = function (value)
		if (type(value) ~= "boolean") then
			return false, "boolean expected"
		end

		return true
	end,
	[Bot.ConfigType.Category] = util.ValidateSnowflake,
	[Bot.ConfigType.Channel] = util.ValidateSnowflake,
	[Bot.ConfigType.Custom] = function (value, configTable)
		local customCheck = configTable.ValidateConfig
		if (customCheck) then
			return customCheck(value)
		end

		return true 
	end,
	[Bot.ConfigType.Duration] = function (value)
		if (type(value) ~= "number") then
			return false, "number expected"
		end

		return true
	end,
	[Bot.ConfigType.Emoji] = function (value)
		if (type(value) ~= "string") then
			return false, "string expected"
		end

		return true
	end,
	[Bot.ConfigType.Integer] = function (value)
		if (type(value) ~= "number") then
			return false, "number expected"
		end

		if (math.floor(value) ~= value) then
			return false, "integer expected"
		end

		return true
	end,
	[Bot.ConfigType.Number] = function (value)
		if (type(value) ~= "number") then
			return false, "number expected"
		end

		return true
	end,
	[Bot.ConfigType.Role] = util.ValidateSnowflake,
	[Bot.ConfigType.String] = function (value)
		if (type(value) ~= "string") then
			return false, "string expected"
		end

		return true
	end,
	[Bot.ConfigType.User] = util.ValidateSnowflake,
}

local validateConfigType = function (configTable, value)
	local validator = configTypeValidation[configTable.Type]
	assert(validator)

	if (configTable.Array) then
		if (type(value) ~= "table") then
			return false, "expected a table, got a " .. type(value)
		end

		if (#value ~= table.count(value)) then
			return false, "expected an array, got an object"
		end

		for _, arrayValue in pairs(value) do
			local success, err = validator(arrayValue, configTable)
			if (not success) then
				return false, err
			end
		end

		return true
	else
		return validator(value, configTable)
	end
end

function ModuleMetatable:_PrepareConfig(context, config, values, global)
	for optionIndex, configTable in pairs(config) do
		local reset = false
		local value = rawget(values, configTable.Name)
		if (value == nil) then
			reset = true
		else
			local success, err = validateConfigType(configTable, value)
			if (not success) then
				self:LogWarning("%s has invalid value (%s) for option %s (%s), resetting...", context, tostring(value), configTable.Name, err or "<unknown error>")
				reset = true
			end
		end

		if (reset) then
			local default = configTable.Default
			if (type(default) == "table") then
				rawset(values, configTable.Name, table.deepcopy(default))
			else
				rawset(values, configTable.Name, default)
			end
		end
	end
end

function ModuleMetatable:_PrepareGlobalConfig()
	if (not self.GlobalConfig) then
		self.GlobalConfig = {}
	end

	setmetatable(self.GlobalConfig, ConfigMetatable)

	return self:_PrepareConfig("Global config", self._GlobalConfig, self.GlobalConfig, true)
end

function ModuleMetatable:_PrepareGuildConfig(guildId, guildConfig)
	setmetatable(guildConfig, ConfigMetatable)

	return self:_PrepareConfig("Guild " .. guildId, self._GuildConfig, guildConfig, false)
end

function ModuleMetatable:DisableForGuild(guild, dontSave)
	if (not self:IsEnabledForGuild(guild)) then
		return true
	end

	local success, err
	if (self.OnDisable) then
		success, err = Bot:CallModuleFunction(self, "OnDisable", guild)
	else
		success = true
	end

	if (success) then
		local config = self:GetConfig(guild)
		config._Enabled = false
		if (not dontSave) then
			self:SaveGuildConfig(guild)
		end

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
		self:SaveGuildConfig(guild)
	end

	self:LogInfo(guild, "Module enabled (%.3fs)", stopwatch.milliseconds / 1000)
	return true
end

function ModuleMetatable:ForEachGuild(callback, evenDisabled, evenNonReady, evenNonLoaded)
	for guildId, data in pairs(self._Guilds) do
		local guild = Bot.Client:getGuild(guildId)

		if ((guild or evenNonLoaded) and (evenNonReady or data._Ready) and (evenDisabled or data.Config._Enabled)) then
			callback(guildId, data.Config, data.Data, data.PersistentData, guild)
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
		guildData.Config = {
			_Enabled = false
		}
		guildData.Data = {}
		guildData.PersistentData = {}
		guildData._Ready = false

		self:_PrepareGuildConfig(guildId, guildData.Config)

		self._Guilds[guildId] = guildData
	end

	return guildData
end

function ModuleMetatable:GetPersistentData(guild, noCreate)
	if (not guild) then
		if (not self.GlobalPersistentData) then
			self.GlobalPersistentData = {}
		end

		return self.GlobalPersistentData
	end
	
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

function ModuleMetatable:RegisterCommand(values)
	local privilegeCheck = values.PrivilegeCheck
	if (privilegeCheck) then
		values.PrivilegeCheck = function (member)
			if (not self:IsEnabledForGuild(member.guild)) then
				return false
			end

			return privilegeCheck(member) 
		end
	else
		values.PrivilegeCheck = function (member) 
			return self:IsEnabledForGuild(member.guild)
		end
	end

	table.insert(self._Commands, values.Name)

	return Bot:RegisterCommand(values)
end

function ModuleMetatable:Save(guild)
	self:SaveGuildConfig(guild)
	self:SavePersistentData(guild)
end

function ModuleMetatable:SaveGlobalConfig()
	local filepath = string.format("data/module_%s/global_config.json", self.Name)
	local success, err = Bot:SerializeToFile(filepath, self.GlobalConfig, true)
	if (not success) then
		self:LogWarning(nil, "Failed to save global config: %s", err)
	end
end

function ModuleMetatable:SaveGlobalPersistentData()
	if (not self.GlobalPersistentData) then
		return
	end

	local filepath = string.format("data/module_%s/global_data.json", self.Name)
	local success, err = Bot:SerializeToFile(filepath, self.GlobalPersistentData, true)
	if (not success) then
		self:LogWarning(nil, "Failed to save global data: %s", err)
	end
end


function ModuleMetatable:LoadGuildConfig(guild)
	local guildData = self:GetGuildData(guild.id)

	local config, err = Bot:UnserializeFromFile(string.format("data/module_%s/guild_%s/config.json", self.Name, guild.id))
	if (config) then
		self:_PrepareGuildConfig(guild.id, config)

		guildData.Config = config
		if (self:IsEnabledForGuild(guild)) then
			self:HandleConfigUpdate(guild, config, nil)
		end

		return true
	else
		self:LogError(guild, "Failed to load config: %s", err)
		return false, err
	end
end

function ModuleMetatable:SaveGuildConfig(guild)
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
		self:SaveGlobalPersistentData()
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
		if (not moduleTable:IsEnabledForGuild(guild)) then
			return false, "Module is already disabled on this server"
		end

		return moduleTable:DisableForGuild(guild)
	end
	
	return false, "Module not loaded"
end

function Bot:EnableModule(moduleName, guild)
	local moduleTable = self.Modules[moduleName]
	if (moduleTable) then
		if (moduleTable:IsEnabledForGuild(guild)) then
			return false, "Module is already enabled on this server"
		end

		return moduleTable:EnableForGuild(guild)
	end
	
	return false, "Module not loaded"
end

function Bot:LoadModule(moduleTable)
	self:UnloadModule(moduleTable.Name)

	local stopwatch = discordia.Stopwatch()

	-- Load config
	local guildConfig = {}
	local globalConfig = {}
	if (moduleTable.GetConfigTable) then
		local success, ret = self:CallModuleFunction(moduleTable, "GetConfigTable")

		if (not success) then
			return false, "Failed to load config: " .. ret
		end

		if (type(ret) ~= "table") then
			return false, "Invalid config"
		end
		local config = ret

		-- Validate config
		local validConfigOptions = {
			-- Field = {type, mandatory, default}
			["Array"] = {"boolean", false, false},
			["Default"] = {"any", false},
			["Description"] = {"string", true},
			["Global"] = {"boolean", false, false},
			["Optional"] = {"boolean", false, false},
			["Name"] = {"string", true},
			["Sensitive"] = {"boolean", false, false},
			["Type"] = {"number", true},
			["ValidateConfig"] = {"function", false}
		}

		for optionIndex, configTable in pairs(config) do
			for configName, configValue in pairs(configTable) do
				local option = validConfigOptions[configName]
				if (not option) then
					return false, string.format("[%s] Option #%s has invalid key \"%s\"", configTable.Name, optionIndex, configName)
				end

				local expectedType = option[1]
				if (expectedType ~= "any" and type(configValue) ~= expectedType) then
					return false, string.format("[%s] Option #%s has key \"%s\" which has invalid type %s (expected %s)", configTable.Name, optionIndex, configName, type(configValue), expectedType)
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

			if (configTable.Default == nil and not configTable.Optional) then
				return false, string.format("[%s] Option #%s is not optional and has no default value", configTable.Name, optionIndex)
			end

			if (configTable.Global) then
				table.insert(globalConfig, configTable)
			else
				table.insert(guildConfig, configTable)
			end
		end
	end
	moduleTable._GlobalConfig = globalConfig
	moduleTable._GuildConfig = guildConfig

	-- Parse events
	local moduleEvents = {}
	for key,func in pairs(moduleTable) do
		if (key:startswith("On") and type(func) == "function") then
			local eventName = key:sub(3, 3):lower() .. key:sub(4)
			if (not botModuleEvents[eventName]) then
				if (not discordiaEvents[eventName]) then
					return false, "Module tried to bind hook \"" .. eventName .. "\" which doesn't exist"
				end

				moduleEvents[eventName] = {Module = moduleTable, Callback = function (moduleTable, ...) self:CallModuleFunction(moduleTable, key, ...) end}
			end
		end
	end
	moduleTable._Events = moduleEvents

	moduleTable._Commands = {}
	moduleTable._Guilds = {}

	setmetatable(moduleTable, ModuleMetatable)

	-- Load module persistent data from disk
	self:LoadModuleData(moduleTable)

	moduleTable:_PrepareGlobalConfig()

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
			local path = dataFolder .. "/" .. entry.name
			if (entry.type == "directory") then
				local guildId = entry.name:match("guild_(%d+)")
				if (guildId) then
					local guildData = moduleTable:GetGuildData(guildId)

					local config, err = self:UnserializeFromFile(path .. "/config.json")
					if (config) then
						guildData.Config = config
						moduleTable:_PrepareGuildConfig(guildId, guildData.Config)
					else
						self.Client:error("Failed to load config of guild %s (%s module): %s", guildId, moduleTable.Name, err)
					end

					local persistentData, err = self:UnserializeFromFile(path .. "/persistentdata.json")
					if (persistentData) then
						guildData.PersistentData = persistentData
					else
						self.Client:error("Failed to load persistent data of guild %s (%s module): %s", guildId, moduleTable.Name, err)
					end
				end
			elseif (entry.type == "file") then
				if (entry.name == "global_config.json") then
					local config, err = self:UnserializeFromFile(path)
					if (config) then
						moduleTable.GlobalConfig = config
						self.Client:info("Global config of module %s has been loaded", moduleTable.Name)
					else
						self.Client:error("Failed to load global config module %s: %s", moduleTable.Name, err)
					end
				elseif (entry.name == "global_data.json") then
					local data, err = self:UnserializeFromFile(path)
					if (data) then
						moduleTable.GlobalPersistentData = data
						self.Client:info("Global data of module %s has been loaded", moduleTable.Name)
					else
						self.Client:error("Failed to load global config module %s: %s", moduleTable.Name, err)
					end
				end
			end
		end
	end
end

function Bot:MakeModuleReady(moduleTable)
	moduleTable:ForEachGuild(function (guildId, config, data, persistentData, guild)
		moduleTable:EnableForGuild(guild, true, true)
	end, false, true)

	for eventName,eventData in pairs(moduleTable._Events) do
		local eventTable = self.Events[eventName]
		if (not eventTable) then
			eventTable = {}
			self.Client:onSync(eventName, function (...)
				local parameters = {...}
				table.insert(parameters, self.Client)

				local eventGuild = discordiaEvents[eventName](table.unpack(parameters))
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

function Bot:GetModuleForGuild(guild, moduleName)
	local moduleTable = self.Modules[moduleName]
	if (not moduleTable) then
		return nil, "module is not loaded"
	end

	if (not moduleTable:IsEnabledForGuild(guild)) then
		return nil, "module is not enabled"
	end

	return moduleTable
end

function Bot:UnloadModule(moduleName)
	local moduleTable = self.Modules[moduleName]
	if (moduleTable) then
		moduleTable:ForEachGuild(function (guildId, config, data, persistentData, guild)
			moduleTable:DisableForGuild(guild, true)
		end, false, true)

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

		for _, commandName in pairs(moduleTable._Commands) do
			Bot:UnregisterCommand(commandName)
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


Bot:RegisterCommand({
	Name = "modulelist",
	Args = {},
	PrivilegeCheck = function (member) return member:hasPermission(enums.permission.administrator) end,

	Help = "Configures a module",
	Func = function (message)
		local moduleList = {}
		for moduleName, moduleTable in pairs(Bot.Modules) do
			table.insert(moduleList, moduleTable)
		end
		table.sort(moduleList, function (a, b) return a.Name < b.Name end)

		local moduleListStr = {}
		for _, moduleTable in pairs(moduleList) do
			local enabledEmoji
			if (moduleTable.Global) then
				enabledEmoji = ":globe_with_meridians:"
			elseif (moduleTable:IsEnabledForGuild(message.guild)) then
				enabledEmoji = ":white_check_mark:"
			else
				enabledEmoji = ":x:"
			end

			table.insert(moduleListStr, string.format("%s **%s**", enabledEmoji, moduleTable.Name))
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
	end
})

local StringifyConfigValue = function (guild, configTable, value)
	if (value ~= nil) then
		local valueToString = Bot.ConfigTypeToString[configTable.Type]
		if (configTable.Array) then
			local valueStr = {}
			for _, value in pairs(value) do
				table.insert(valueStr, valueToString(value, guild))
			end

			return table.concat(valueStr, ", ")
		else
			return valueToString(value, guild)
		end
	else
		if (not configTable.Optional) then
			error("Config " .. configTable.Name .. " has no value but is not optional")
		end

		return "<None>"
	end
end

local GenerateField = function (guild, configTable, value, allowSensitive)
	local valueStr
	if (not configTable.Sensitive or allowSensitive) then
		valueStr = StringifyConfigValue(guild, configTable, value)
	else
		valueStr = "*<sensitive>*"
	end

	local fieldType = Bot.ConfigTypeString[configTable.Type]
	if (configTable.Array) then
		fieldType = fieldType .. " array"
	end

	return {
		name = string.format("%s:gear: %s", configTable.Global and ":globe_with_meridians: " or "", configTable.Name),
		value = string.format("**Description:** %s\n**Value (%s):** %s", configTable.Description, fieldType, valueStr)
	}
end

Bot:RegisterCommand({
	Name = "config",
	Args = {
		{Name = "module", Type = Bot.ConfigType.String},
		{Name = "action", Type = Bot.ConfigType.String, Optional = true},
		{Name = "key", Type = Bot.ConfigType.String, Optional = true},
		{Name = "value", Type = Bot.ConfigType.String, Optional = true}
	},
	PrivilegeCheck = function (member) return member:hasPermission(enums.permission.administrator) end,

	Help = "Configures a module",
	Func = function (message, moduleName, action, key, value)
		moduleName = moduleName:lower()

		local moduleTable = Bot.Modules[moduleName]
		if (not moduleTable) then
			message:reply("Invalid module \"" .. moduleName .. "\"")
			return
		end

		action = action and action:lower() or "list"

		local globalConfig = moduleTable.GlobalConfig
		local guild = message.guild
		local guildConfig = moduleTable:GetConfig(guild)

		local GetConfigByKey = function (key)
			for k,configData in pairs(moduleTable._GuildConfig) do
				if (configData.Name == key) then
					return configData
				end
			end

			if (message.member.id == Config.OwnerUserId) then
				for k,configData in pairs(moduleTable._GlobalConfig) do
					if (configData.Name == key) then
						return configData
					end
				end
			end
		end

		if (action == "list") then
			local fields = {}
			local globalFields = {}
			for k,configTable in pairs(moduleTable._GuildConfig) do
				table.insert(fields, GenerateField(guild, configTable, rawget(guildConfig, configTable.Name)))
			end

			if (message.member.id == Config.OwnerUserId) then
				for k,configTable in pairs(moduleTable._GlobalConfig) do
					table.insert(fields, GenerateField(guild, configTable, rawget(moduleTable.GlobalConfig, configTable.Name)))
				end
			end

			local enabledText
			if (moduleTable.Global) then
				enabledText = ":globe_with_meridians: This module is global and cannot be enabled nor disabled on a guild basis"
			elseif (moduleTable:IsEnabledForGuild(guild)) then
				enabledText = ":white_check_mark: Module **enabled** (use `!disable " .. moduleTable.Name .. "` to disable it)"
			else
				enabledText = ":x: Module **disabled** (use `!enable " .. moduleTable.Name .. "` to enable it)"
			end

			message:reply({
				embed = {
					title = "Configuration for " .. moduleTable.Name .. " module",
					description = string.format("%s\n\nConfiguration list:", enabledText, moduleTable.Name),
					fields = fields,
					footer = {text = string.format("Use `!config %s add/remove/reset/set/show ConfigName <value>` to change configuration settings.", moduleTable.Name)}
				}
			})
		elseif (action == "show") then
			local configTable = GetConfigByKey(key)
			if (not configTable) then
				message:reply(string.format("Module %s has no config key \"%s\"", moduleTable.Name, key))
				return
			end

			local config = configTable.Global and globalConfig or guildConfig

			message:reply({
				embed = {
					title = "Configuration of " .. moduleTable.Name .. " module",
					fields = {
						GenerateField(guild, configTable, rawget(config, configTable.Name), true)
					},
					timestamp = discordia.Date():toISO('T', 'Z')
				}
			})
		elseif (action == "add" or action == "remove" or action == "reset" or action == "set") then
			if (not key) then
				message:reply("Missing config key name")
				return
			end

			local configTable = GetConfigByKey(key)
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

			local config
			local configGuild
			if (configTable.Global) then
				config = globalConfig
			else
				config = guildConfig
				configGuild = guild
			end

			if (action == "add") then
				assert(configTable.Array)
				-- Insert value (if not present)
				local found = false
				local values = rawget(config, configTable.Name)
				if (not values) then
					assert(configTable.Optional)

					values = {}
					rawset(config, configTable.Name, values)
				end

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
				local values = rawget(config, configTable.Name)
				if (values) then
					for i = 1, #values do
						if (values[i] == newValue) then
							table.remove(values, i)
							wasModified = true
							break
						end
					end
				else
					assert(configTable.Optional)
				end
			elseif (action == "reset" or action == "set") then
				-- Replace value
				if (configTable.Array and action ~= "reset") then
					rawset(config, configTable.Name, {newValue})
				else
					rawset(config, configTable.Name, newValue)
				end

				wasModified = true
			end

			if (wasModified) then
				moduleTable:HandleConfigUpdate(configGuild, config, configTable.Name)

				if (configTable.Global) then
					moduleTable:SaveGlobalConfig()
				else
					moduleTable:SaveGuildConfig(guild)
				end
			end

			message:reply({
				embed = {
					title = "Configuration update for " .. moduleTable.Name .. " module",
					fields = {
						GenerateField(guild, configTable, config[configTable.Name], false, wasModified)
					},
					timestamp = discordia.Date():toISO('T', 'Z')
				}
			})
		else
			message:reply("Invalid action \"" .. action .. "\" (valid actions are *add*, *remove*, *reset*, *set* or *show*)")
		end
	end
})

Bot:RegisterCommand({
	Name = "configraw",
	Args = {
		{Name = "module", Type = Bot.ConfigType.String},
		{Name = "action", Type = Bot.ConfigType.String, Optional = true},
		{Name = "content", Type = Bot.ConfigType.String, Optional = true}
		{Name = "global", Type = Bot.ConfigType.Boolean, Optional = true}
	},
	PrivilegeCheck = function (member) return member:hasPermission(enums.permission.administrator) end,

	Help = "Configures a module using JSon",
	Func = function (message, moduleName, action, content, global)
		moduleName = moduleName:lower()

		local moduleTable = Bot.Modules[moduleName]
		if (not moduleTable) then
			message:reply("Invalid module \"" .. moduleName .. "\"")
			return
		end

		action = action and action:lower() or "get"

		local globalConfig = moduleTable.GlobalConfig
		local guild = message.guild
		local guildConfig = moduleTable:GetConfig(guild)

		if (action == "get") then
			local fields = {}
			for _,configTable in pairs(moduleTable._GuildConfig) do
				fields[configTable.Name] = rawget(guildConfig, configTable.Name)
			end

			if (global and message.member.id == Config.OwnerUserId) then
				for _,configTable in pairs(moduleTable._GlobalConfig) do
					fields[configTable.Name] = rawget(moduleTable.GlobalConfig, configTable.Name)
				end
			end

			local fieldJson = json.encode(fields, { indent = 1})
			if (#fieldJson > 1800) then
				message:reply({
					embed = {
						title = "Configuration for " .. moduleTable.Name .. " module",
						description = "Configuration was too big and has been sent as a file",
						footer = {text = string.format("Use `!configraw %s update` to change configuration.", moduleTable.Name)}
					}
				})
				message:reply({ file = {"config.json", fieldJson} })
			else
				message:reply({
					embed = {
						title = "Configuration for " .. moduleTable.Name .. " module",
						description = string.format("```json\n%s```:", json.encode(fields, { indent = 1 })),
						footer = {text = string.format("Use `!configraw %s update` to change configuration.", moduleTable.Name)}
					}
				})
			end
		elseif (action == "update") then
			local code
			if (message.attachments) then
				if (#message.attachments ~= 1) then
					message:reply("You must send only one file to update a module config!")
					return
				end

				local attachment = message.attachments[1]
				if (not attachment.filename:match(".json$")) then
					message:reply("You must send a .json file to update a module config")
					return
				end

				if (attachment.size >= 1024 * 1024) then
					message:reply("This file is too big!")
					return
				end

				local res, body = http.request("GET", attachment.url)
				if (res.code ~= 200) then
					message:reply(string.format("Failed to download file (%d): ", res.code, body))
					return
				end

				code = body
			else
				local language
				language, code = content:match("^```(%w*)\n(.+)```$")
				if (language) then
					if (#language > 0 and language ~= "json") then
						message:reply(string.format("Expected a json code, got %s", language))
						return
					end
				else
					code = content
				end
			end

			local updateFields, idx, err = json.decode(code)
			if (not updateFields) then
				message:reply(string.format("Expected a valid json code, parsing failed at %d: %s", idx, err))
				return
			end

			local wasGuildConfigModified = false
			local wasGlobalConfigModified = false

			local fieldDescriptions = {}

			local fieldUpdate = {}
			local errorFields = {}
			local ignoredFields = {}
			for fieldName, fieldValue in pairs(updateFields) do
				for _, configTable in pairs(moduleTable._GuildConfig) do
					if (configTable.Name == fieldName) then
						local success, err = validateConfigType(configTable, fieldValue)
						if (success) then
							table.insert(fieldUpdate, function ()
								rawset(guildConfig, fieldName, fieldValue)
								moduleTable:HandleConfigUpdate(guild, guildConfig, fieldName)

								wasGuildConfigModified = true
								table.insert(fieldDescriptions, GenerateField(guild, configTable, fieldValue, false))
							end)
						else
							errorFields[fieldName] = err
						end

						goto continue
					end
				end

				if (message.member.id == Config.OwnerUserId) then
					for _, configTable in pairs(moduleTable._GlobalConfig) do
						if (configTable.Name == fieldName) then
							local success, err = validateConfigType(configTable, fieldValue)
							if (success) then
								table.insert(fieldUpdate, function ()
									rawset(globalConfig, fieldName, fieldValue)
									moduleTable:HandleConfigUpdate(nil, globalConfig, fieldName)

									wasGlobalConfigModified = true
									table.insert(fieldDescriptions, GenerateField(guild, configTable, fieldValue, false))
								end)
							else
								errorFields[fieldName] = err
							end
	
							goto continue
						end
					end
				end

				table.insert(ignoredFields, fieldName)

				::continue::
			end

			if (next(errorFields) or #ignoredFields > 0) then
				local msg = {}
				table.insert(msg, "Field errors detected, please check their value (no configuration has been updated)")

				if (#ignoredFields > 0) then
					table.insert(msg, " - Ignored field (not matching a configuration): " .. table.concat(ignoredFields, ", "))
				end

				if (next(errorFields)) then
					table.insert(msg, " - Fields having an invalid value:")
					for fieldName, err in pairs(errorFields) do
						table.insert(msg, "   - " .. fieldName .. ": " .. err)
					end
				end

				message:reply(table.concat(msg, "\n"))
				return
			end

			if (#fieldUpdate > 0) then
				for _, func in pairs(fieldUpdate) do
					func()
				end

				if (wasGuildConfigModified) then
					moduleTable:SaveGuildConfig(guild)
				end

				if (wasGlobalConfigModified) then
					moduleTable:SaveGlobalConfig()
				end

				message:reply({
					embed = {
						title = "Configuration update for " .. moduleTable.Name .. " module",
						fields = fieldDescriptions,
						timestamp = discordia.Date():toISO('T', 'Z')
					}
				})
			else
				message:reply("No update required (no field were set)")
			end
		else
			message:reply("Invalid action \"" .. action .. "\" (valid actions are *get* or *update*)")
		end
	end
})

Bot:RegisterCommand({
	Name = "load",
	Args = {
		{Name = "modulefile", Type = Bot.ConfigType.String}
	},
	PrivilegeCheck = function (member) return member.id == Config.OwnerUserId end,

	Help = "(Re)loads a module",
	Func = function (message, moduleFile)
		local moduleTable, err, codeErr = Bot:LoadModuleFile(moduleFile)
		if (moduleTable) then
			message:reply("Module **" .. moduleTable.Name .. "** loaded")
		else
			local errorMessage = err
			if (codeErr) then
				errorMessage = errorMessage .. "\n" .. code(codeErr)
			end

			message:reply("Failed to load module: " .. errorMessage)
		end
	end
})

Bot:RegisterCommand({
	Name = "disable",
	Args = {
		{Name = "module", Type = Bot.ConfigType.String}
	},
	PrivilegeCheck = function (member) return member:hasPermission(enums.permission.administrator) end,

	Help = "Disables a module",
	Func = function (message, moduleName)
		local success, err = Bot:DisableModule(moduleName, message.guild)
		if (success) then
			message:reply("Module **" .. moduleName .. "** disabled")
		else
			message:reply("Failed to disable **" .. moduleName .. "** module: " .. err)
		end
	end
})

Bot:RegisterCommand({
	Name = "enable",
	Args = {
		{Name = "module", Type = Bot.ConfigType.String}
	},
	PrivilegeCheck = function (member) return member:hasPermission(enums.permission.administrator) end,

	Help = "Enables a module",
	Func = function (message, moduleName)
		local success, err = Bot:EnableModule(moduleName, message.guild)
		if (success) then
			message:reply("Module **" .. moduleName .. "** enabled")
		else
			message:reply("Failed to enable **" .. moduleName .. "** module: " .. tostring(err))
		end
	end
})

Bot:RegisterCommand({
	Name = "reload",
	Args = {
		{Name = "module", Type = Bot.ConfigType.String}
	},
	PrivilegeCheck = function (member) return member:hasPermission(enums.permission.administrator) end,

	Help = "Reloads a module (as disable/enable would do)",
	Func = function (message, moduleName)
		local moduleTable = Bot.Modules[moduleName]
		if (not moduleTable) then
			message:reply("Module **" .. moduleName .. "** doesn't exist")
			return
		end

		if (not moduleTable:IsEnabledForGuild(message.guild)) then
			message:reply("Module **" .. moduleName .. "** is not enabled")
			return
		end

		local success, err = moduleTable:DisableForGuild(message.guild, true)
		if (success) then
			local success, err = moduleTable:EnableForGuild(message.guild, false, true)
			if (success) then
				message:reply("Module **" .. moduleName .. "** reloaded")
			else
				message:reply("Failed to re-enable **" .. moduleName .. "** module: " .. err)
			end
		else
			message:reply("Failed to disable **" .. moduleName .. "** module: " .. err)
		end
	end
})

Bot:RegisterCommand({
	Name = "unload",
	Args = {
		{Name = "module", Type = Bot.ConfigType.String}
	},
	PrivilegeCheck = function (member) return member.id == Config.OwnerUserId end,

	Help = "Unloads a module",
	Func = function (message, moduleName)
		if (Bot:UnloadModule(moduleName)) then
			message:reply("Module **" .. moduleName .. "** unloaded.")
		else
			message:reply("Module **" .. moduleName .. "** not found.")
		end
	end
})

Bot:RegisterCommand({
	Name = "reloadconfig",
	Args = {
		{Name = "modulename", Type = Bot.ConfigType.String}
	},
	PrivilegeCheck = function (member) return member.id == Config.OwnerUserId end,

	Help = "(Re)loads a module's config from file on a guild",
	Func = function (message, moduleName)
		local moduleTable = Bot.Modules[moduleName]
		if (not moduleTable) then
			message:reply("Module **" .. moduleName .. "** doesn't exist")
			return
		end

		local success, err = moduleTable:LoadGuildConfig(message.guild)
		if (success) then
			message:reply("Module **" .. moduleName .. "** configuration reloaded")
		else
			message:reply("Failed to reload **" .. moduleName .. "** configuration: " .. err)
		end
	end
})
