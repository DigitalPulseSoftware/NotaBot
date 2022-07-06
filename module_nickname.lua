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

Module.Name = "nickname"

function Module:OnLoaded()
	self:RegisterCommand({
		Name = "drynukerename",
		Args = {},
		PrivilegeCheck = function (member) return member:hasPermission(enums.permission.administrator) end,

		Help = "Count every nickname of every user on the server.",
		Func = function (commandMessage, time)
			local userList = self:BuildRenamedUserList(commandMessage.guild)

			if #userList == 0 then
				commandMessage:reply("No renamed user")
			else 
				commandMessage:reply("This will remove custom nickname for ".. #userList .." members. Are you sure ? Type !nukerename to apply.")
			end
		end
	})

	self:RegisterCommand({
		Name = "nukerename",
		Args = {},
		PrivilegeCheck = function (member) return member:hasPermission(enums.permission.administrator) end,

		Help = "Remove every nickname of every user on the server.",
		Func = function (commandMessage, time)
			local userList = self:BuildRenamedUserList(commandMessage.guild)

			if #userList == 0 then
				commandMessage:reply("No renamed user")
			else 
				self:RemoveNicknames(commandMessage.guild, userList);
				commandMessage:reply("Removing custom nickname for ".. #userList .." members.")
			end
		end
	})

	return true
end

function Module:OnEnable(guild)
	return true
end

function Module:BuildRenamedUserList(guild, time)
	local userList = {}

	local persistentData = self:GetPersistentData(guild)
	local purgeData = persistentData.Purge

	for userId, user in pairs(guild.members) do
		if(user.nickname ~= nil and not user:hasPermission(enums.permission.administrator)) then
			table.insert(userList, user)
		end
	end

	return userList
end

function Module:RemoveNicknames(guild, userList)
	if #userList == 0 then
		return
	end

	self:LogInfo(guild, "Begining nickname nuke ...")

	for _, user in pairs(userList) do
		self:LogInfo(guild, "Renaming %s", user.name)

		user:setNickname('')
	end

	self:LogInfo(guild, "Nickname nuke ended !")
end
