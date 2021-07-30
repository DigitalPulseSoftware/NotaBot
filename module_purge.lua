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
	self:RegisterCommand({
		Name = "drypurge",
		Args = {
			{Name = "time", Type = bot.ConfigType.Duration}
		},
		PrivilegeCheck = function (member) return member:hasPermission(enums.permission.administrator) end,

		Help = "Count inactive people. Use: !drypurgeroles 30d to count inactive people for 30 days or more.",
		Func = function (commandMessage, time)
			local durationStr = util.FormatTime(time, 3)

			local userList = self:BuildInactiveUsersList(commandmessage:getGuild(), time)

			if table.empty(userList) then
				commandMessage:reply("No user enought inactive to be purged")
			else 
				commandMessage:reply("Purging peoples inactive for " .. durationStr .. " on Discord will remove all roles on (or kick) ".. table.length(userList) .." members. Are you sure ? (type !purgeroles " .. time .. " to apply purge by roles, or !purgekick " .. time .. " to kick all inactives members.)")
			end
		end
	})

	self:RegisterCommand({
		Name = "purgeroles",
		Args = {
			{Name = "time", Type = bot.ConfigType.Duration}
		},
		PrivilegeCheck = function (member) return member:hasPermission(enums.permission.administrator) end,

		Help = "Clear roles on inactive people to make them avaiable to purge. Use: !purgeroles 30d to remove all roles on members inactive for 30 days or more.",
		Func = function (commandMessage, time)
			local durationStr = util.FormatTime(time, 3)

			local userList = self:BuildInactiveUsersList(commandmessage:getGuild(), time)

			if #userList == 0 then
				commandMessage:reply("No member to purge")
			else 
				self:PurgeRoles(commandmessage:getGuild(), userList)

				commandMessage:reply("Purged peoples inactive for " .. durationStr .. " on Discord, removed all roles on ".. #userList .." members.")
			end
		end
	})

	self:RegisterCommand({
		Name = "purgekick",
		Args = {
			{Name = "time", Type = bot.ConfigType.Duration}
		},
		PrivilegeCheck = function (member) return member:hasPermission(enums.permission.administrator) end,

		Help = "Kick inactive people. Use: !purgekick 30d to kick all inactive people for 30 days or more.",
		Func = function (commandMessage, time)
			local durationStr = util.FormatTime(time, 3)

			local userList = self:BuildInactiveUsersList(commandmessage:getGuild(), time)

			if #userList == 0 then
				commandMessage:reply("No member to purge")
			else 
				self:PurgeKick(commandmessage:getGuild(), userList, durationStr)

				commandMessage:reply("Purged peoples inactive for " .. durationStr .. " on this server, kicked ".. #userList .." members.")
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

	self:AddMissingMembersToList(guild)

	return true
end

function Module:BuildInactiveUsersList(guild, time)
	local userList = {}

	local persistentData = self:GetPersistentData(guild)
	local purgeData = persistentData.Purge

	local allowedInactiveTime = os.time() - time
	for userId, user in pairs(guild.members) do
		if purgeData[userId] ~= nil then
			if purgeData[userId] < allowedInactiveTime then
				table.insert(userList, user)
			end
		end
	end

	return userList
end

function Module:PurgeRoles(guild, userList)
	if #userList == 0 then
		return
	end

	self:LogInfo(guild, "Begining role purge")

	for _, user in pairs(userList) do
		self:LogInfo(guild, "Purging roles for %s", user.name)

		for _, role in pairs(user.roles) do
			if not role.managed then -- You can't remove managed roles, they are for example unique bot roles, discord will send a 403 if you try
				user:removeRole(role.id)
			end
		end
	end

	self:LogInfo(guild, "Role purge ended !")
end

function Module:PurgeKick(guild, userList, durationStr)
	if table.empty(userList) then
		return
	end

	local kickPrivateMessage = string.format("You've been kicked by an automatic measure from **%s** because of an inactivity of **%s** or more.", guild.name, durationStr)

	self:LogInfo(guild, "Begining purge")

	for _, user in pairs(userList) do
		self:LogInfo(guild, "Kicking %s", user.name)

		local privateChannel = user:getPrivateChannel()
		if (privateChannel) then
			privateChannel:send(kickPrivateMessage)
		end

		user:kick("Inactive")
	end

	self:LogInfo(guild, "Purge ended !")
end

function Module:AddMissingMembersToList(guild)
	local persistentData = self:GetPersistentData(guild)
	local purgeData = persistentData.Purge

	for userId, userData in pairs(guild.members) do
		if purgeData[userId] == nil then
			purgeData[userId] = os.time()
		end
	end
end

function Module:OnMessageCreate(message)
	if (not bot:IsPublicChannel(message:getChannel())) then
		return
	end

	local data = self:GetPersistentData(message:getGuild())
	data.Purge[message.author.id] = os.time()
end

function Module:OnMemberJoin(member)
	local data = self:GetPersistentData(member:getGuild())
	data.Purge[member.user.id] = os.time()
end

function Module:OnReactionAdd(reaction, userId)
	if (not bot:IsPublicChannel(reaction.message:getChannel())) then
		return
	end

	local data = self:GetPersistentData(reaction.message:getGuild())
	data.Purge[userId] = os.time()
end

function Module:OnReactionAddUncached(channel, messageId, reactionIdorName, userId)
	if (not bot:IsPublicChannel(channel)) then
		return
	end

	local data = self:GetPersistentData(channel:getGuild())
	data.Purge[userId] = os.time()
end

function Module:OnReactionRemove(reaction, userId)
	if (not bot:IsPublicChannel(reaction.message:getChannel())) then
		return
	end

	local data = self:GetPersistentData(reaction.message:getGuild())
	data.Purge[userId] = os.time()
end

function Module:OnReactionRemoveUncached(channel, messageId, reactionIdorName, userId)
	if (not bot:IsPublicChannel(channel)) then
		return
	end

	local data = self:GetPersistentData(channel:getGuild())
	data.Purge[userId] = os.time()
end
