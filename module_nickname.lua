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
Module.PageSize = 2

function Module:OnLoaded()
	self:RegisterCommand({
		Name = "drynukerename",
		Args = {},
		PrivilegeCheck = function (member) return self:CheckRoles(member) end,

		Help = "Count every user that have a custom nickname on the server.",
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
		PrivilegeCheck = function (member) return self:CheckRoles(member) end,

		Help = "Remove every custom nickname of every user on the server.",
		Func = function (commandMessage, time)
			local userList = self:BuildRenamedUserList(commandMessage.guild)

			if #userList == 0 then
				commandMessage:reply("No renamed user")
			else 
				self:RemoveNicknames(commandMessage.guild, commandMessage.member, userList)
				commandMessage:reply("Removing custom nickname for ".. #userList .." members.")
			end
		end
	})

	self:RegisterCommand({
		Name = "managenicknames",
		Args = {},
		PrivilegeCheck = function (member) return self:CheckRoles(member) end,

		Help = "Display user nicknames and a button to reset them.",
		Func = function (commandMessage, time)
			local userList = self:BuildRenamedUserList(commandMessage.guild)

			if #userList == 0 then
				commandMessage:reply("No renamed user")
			else 
				commandMessage:reply(self:BuildUserListMessage(commandMessage.guild, userList, 0))
			end
		end
	})

	return true
end

function Module:OnEnable(guild)
	return true
end

function Module:CheckRoles(member)
	return member:hasPermission(enums.permission.manageNicknames)
end

function Module:HasHighestRolesThanTarget(user, target)
	local bannedByRole = user.highestRole
	local targetRole = target.highestRole
	if (targetRole.position >= bannedByRole.position) then
		return false
	end

	return true
end

function Module:OnInteractionCreate(interaction)
	local guild = interaction.guild
	if not guild then
		return
	end

	local member = interaction.member
	if not self:CheckRoles(member) then
		return
	end

	local config = self:GetConfig(guild)

	local interactionType = interaction.data.custom_id
	local custom_id_start_remove = 'nickname_remove_'
	local custom_id_start_page = 'nickname_page_'

	local userList = self:BuildRenamedUserList(guild)

	if #userList == 0 then
		interaction:respond({
			type = enums.interactionResponseType.channelMessageWithSource,
			data = {
				content = "No renamed user",
				flags = enums.interactionResponseFlag.ephemeral
			}
		});
		return
	end

	if string.startsWith(interactionType, custom_id_start_remove) then
		local cmdUserId = string.sub(interactionType, string.len(custom_id_start_remove) + 1, string.len(interactionType))

		for _, user in pairs(userList) do
			if cmdUserId == user.id then
				if not self:HasHighestRolesThanTarget(interaction.member, user) then
					interaction:respond({
						type = enums.interactionResponseType.channelMessageWithSource,
						data = {
							content = "You cannot rename that user due to your lower permissions.",
							flags = enums.interactionResponseFlag.ephemeral
						}
					});
					return
				end

				user:setNickname('')

				break
			end
		end

		interaction:respond({
			type = enums.interactionResponseType.channelMessageWithSource,
			data = {
				content = "Done !",
				flags = enums.interactionResponseFlag.ephemeral
			}
		})
	elseif string.startsWith(interactionType, custom_id_start_page) then
		local page = string.sub(interactionType, string.len(custom_id_start_page) + 1, string.len(interactionType))

		interaction.message:update(self:BuildUserListMessage(guild, userList, tonumber(page)))

		interaction:respond({
			type = enums.interactionResponseType.updateMessage,
		})
	end
end

function Module:BuildRenamedUserList(guild)
	local userList = {}

	for userId, user in pairs(guild.members) do
		if(user.nickname ~= nil) then
			table.insert(userList, user)
		end
	end

	return userList
end

function Module:RemoveNicknames(guild, currentUser, userList)
	if #userList == 0 then
		return
	end

	self:LogInfo(guild, "Begining nickname nuke ...")

	for _, user in pairs(userList) do
		self:LogInfo(guild, "Renaming %s", user.name)

		if self:HasHighestRolesThanTarget(currentUser, user) then
			user:setNickname('')
			return
		end
	end

	self:LogInfo(guild, "Nickname nuke ended !")
end

function Module:BuildUserListMessage(guild, userList, currentPage)
	local components = {}

	table.sort(userList, function(u) return u._user._username end)

	table.insert(components, {
		type = enums.componentType.actionRow,
		components = {
			{
				style = enums.buttonStyle.secondary,
				label = "Real Name",
				custom_id = "row_header_button_0",
				disabled = true,
				type = enums.componentType.button
			},
			{
				style = enums.buttonStyle.secondary,
				label = "Custom Name",
				custom_id = "row_header_button_1",
				disabled = true,
				type = enums.componentType.button
			},
		}
	})

	local i = 0
	for _, user in pairs(userList) do
		if i >= Module.PageSize * currentPage then
			if #components > Module.PageSize then
				break
			end

			table.insert(components, {
				type = enums.componentType.actionRow,
				components = {
					{
						style = enums.buttonStyle.secondary,
						label = user._user._username,
						custom_id = "row_" .. #components .. "_button_0",
						disabled = true,
						type = enums.componentType.button
					},
					{
						style = enums.buttonStyle.secondary,
						label = user.nickname,
						custom_id = "row_" .. #components .. "_button_1",
						disabled = true,
						type = enums.componentType.button
					},
					{
						style = enums.buttonStyle.primary,
						label = "Remove custom username",
						custom_id = "nickname_remove_" .. user.id,
						disabled = false,
						type = enums.componentType.button
					}
				}
			})
		end
		i = i+1
	end

	table.insert(components, {
		type = enums.componentType.actionRow,
		components = {
			{
				style = enums.buttonStyle.primary,
				label = "Prev Page",
				custom_id = "nickname_page_" .. currentPage - 1,
				disabled = currentPage == 0,
				type = enums.componentType.button
			},
			{
				style = enums.buttonStyle.primary,
				label = "Next Page",
				custom_id = "nickname_page_" .. currentPage + 1,
				disabled = #userList <= Module.PageSize * (currentPage + 1),
				type = enums.componentType.button
			},
		}
	})

	return {
		components = components,
		embeds = {
			{
				type = "rich",
				title = "Test",
				description = "",
				color = 0x00FFFF
			}
		}
	}
end