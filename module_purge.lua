-- Copyright (C) 2019-2020 Axel "Elanis" Soupé
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local bot = Bot
local client = Client
local config = Config
local discordia = Discordia
local enums = discordia.enums
local fs = require("coro-fs")
local json = require("json")
local path = require("path")

Module.Name = "purge"

function Module:OnLoaded()
	self.Clock = discordia.Clock()
	self.Clock:on("day", function ()
		self:ForEachGuild(function (guildId, config, data, persistentData)
			local guild = client:getGuild(guildId)
			if (guild) then
				local purgeData = persistentData.Purge
				self:SavePurgeData(self:GetPurgeFilename(guild), purgeData)
				persistentData.Purge = {}
			end
		end)
	end)

	self:RegisterCommand({
		Name = "dryPurgeRoles",
		Args = {
			{Name = "time", Type = bot.ConfigType.Duration}
		},
		PrivilegeCheck = function (member) return member:hasPermission(enums.permission.administrator) end,

		Help = "Count inactive people. Use: !dryPurgeRoles 30d to count inactive people for 30 days or more.",
		Func = function (commandMessage, time)
			local durationStr = util.FormatTime(time, 3)

			local userList = self:BuildInactiveUsersList(commandMessage.guild, time)

			if table.empty(userList) then
				commandMessage:reply("No user enought inactive to be purged")
			else 
				commandMessage:reply("Purging peoples inactive for " .. durationStr .. " on Discord will remove all roles on ".. table.length(userList) .." peoples. Are you sure ? (type !purgeRoles " .. time .. " to apply purge)")
			end
		end
	})

	self:RegisterCommand({
		Name = "purgeRoles",
		Args = {
			{Name = "time", Type = bot.ConfigType.Duration}
		},
		PrivilegeCheck = function (member) return member:hasPermission(enums.permission.administrator) end,

		Help = "Clear roles on inactive people to make them avaiable to purge. Use: !purgeRoles 30d to remove all roles on people inactive for 30 days or more.",
		Func = function (commandMessage, time)
			local durationStr = util.FormatTime(time, 3)

			local userList = self:BuildInactiveUsersList(commandMessage.guild, time)

			if table.empty(userList) then
				commandMessage:reply("No user enought inactive to be purged")
			else 
				self:PurgeRoles(commandMessage.guild, userList)

				commandMessage:reply("Purged peoples inactive for " .. durationStr .. " on Discord, removed all roles on ".. table.length(userList) .." peoples.")
			end
		end
	})

	return true
end

function Module:OnEnable(guild)
	local data = self:GetPersistentData(guild)
	if (not data.Purge) then
		self:LogInfo(guild, "No previous purge data found, resetting...")
		data.Purge = {}
	else
		self:LogInfo(guild, "Previous purge data data has been found, continuing...")
	end

	return true
end

function Module:OnReady()
	self.Clock:start()
end

function Module:OnUnload()
	if (self.Clock) then
		self.Clock:stop()
	end
end

function Module:GetPurgeFilename(guild)
	return string.format("purge/%s.json", guild.id)
end

function Module:LoadPurgeData(guild, filepath)
	local purgeData, err = bot:UnserializeFromFile(filepath)
	if (not purgeData) then
		self:LogError(guild, "Failed to load purge data: %s", err)
		return
	end

	return purgeData
end

function Module:SavePurgeData(filename, purgeData)
	filename = filename

	local dirname = path.dirname(filename)
	if (dirname ~= "." and not fs.mkdirp(dirname)) then
		self:LogError("Failed to create directory %s", dirname)
		return
	end

	local outputFile = io.open(filename, "w+")
	if (not outputFile) then
		self:LogError("Failed to open %s", filename)
		return
	end

	local success, err = outputFile:write(json.encode(purgeData))
	if (not success) then
		self:LogError("Failed to write %s: %s", filename, err)
		return
	end

	outputFile:close()
end

function Module:BuildInactiveUsersList(guild, time)
	local userList = {}

	local persistentData = self:GetPersistentData(guild)
	local purgeData = persistentData.Purge

	for userId, userData in pairs(guild.members) do
		if purgeData[userId] ~= nil then
			if purgeData[userId] + time < os.time() then
				self:LogInfo(guild, "Inactive User: %s", userData.name)
				userList[userId] = true
			end
		end
	end

	return userList
end

function Module:PurgeRoles(guild, userList)
	if table.empty(userList) then
		return
	end

	self:LogInfo(guild, "Begining role purge")

	for _, user in pairs(guild.members) do
		if userList[user.id] then
			self:LogInfo(guild, "Purging roles for %s", user.name)

			for _, role in pairs(user.roles) do
				if not role.managed then -- You can't remove managed roles, they are for example unique bot roles, discord will send a 403 if you try
					user:removeRole(role.id)
				end
			end
		end
	end

	self:LogInfo(guild, "Role purge ended !")
end

function Module:OnMessageCreate(message)
	if (message.channel.type ~= enums.channelType.text) then
		return
	end

	local data = self:GetPersistentData(message.guild)
	data.Purge[message.author.id] = os.time()
end

function Module:OnMemberJoin(member)
	local data = self:GetPersistentData(member.guild)
	data.Purge[member.user.id] = os.time()
end

function Module:OnReactionAdd(reaction, userId)
	if (reaction.message.channel.type ~= enums.channelType.text) then
		return
	end

	local data = self:GetPersistentData(reaction.message.guild)
	data.Purge[userId] = os.time()
end

function Module:OnReactionAddUncached(channel, messageId, reactionIdorName, userId)
	if (channel.type ~= enums.channelType.text) then
		return
	end

	local data = self:GetPersistentData(channel.guild)
	data.Purge[userId] = os.time()
end

function Module:OnReactionRemove(reaction, userId)
	if (reaction.message.channel.type ~= enums.channelType.text) then
		return
	end

	local data = self:GetPersistentData(reaction.message.guild)
	data.Purge[userId] = os.time()
end

function Module:OnReactionRemoveUncached(channel, messageId, reactionIdorName, userId)
	if (channel.type ~= enums.channelType.text) then
		return
	end

	local data = self:GetPersistentData(channel.guild)
	data.Purge[userId] = os.time()
end