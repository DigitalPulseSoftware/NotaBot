-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local client = Client
local discordia = Discordia
local bot = Bot
local enums = discordia.enums

Module.Name = "roleinfo"

function Module:OnLoaded()
	self:RegisterCommand({
		Name = "roleinfo",
		Args = {
			{Name = "rolename", Type = Bot.ConfigType.String}
		},
		PrivilegeCheck = function (member) return member:hasPermission(enums.permission.administrator) end,

		Help = "Prints role info",
		Func = function (commandMessage, rolename)
			rolename = rolename:lower()

			local roleregex
			if (rolename:startswith("p:", true)) then
				roleregex = rolename:sub(3)
			end

			local messages = {}
			local ProcessRole = function (role)
				local properties = {}
				table.insert(properties, {"ID", role.id})
				table.insert(properties, {"Name", role.mentionString})
				table.insert(properties, {"Created", os.date("%d/%m/%Y at %H:%M", role.createdAt)})
				table.insert(properties, {"Color", role:getColor():toHex()})
				table.insert(properties, {"Managed by integration", role.managed})
				table.insert(properties, {"Member count", table.count(role.members)})
				table.insert(properties, {"Mentionable", role.mentionable})
				table.insert(properties, {"Priority", role.position})
				table.insert(properties, {"Shown separate", role.hoisted})

				-- Build value string
				local fields = {}
				for _, property in pairs(properties) do
					table.insert(fields, {
						name = property[1],
						value = property[2],
						inline = true
					})
				end

				table.insert(messages, {
					content = {
						embed = {
							color = role.color,
							fields = fields,
							image = {url = string.format("https://dummyimage.com/320x80/36393f/%s.png&text=%s", role:getColor():toHex():sub(2), role.name)},
						},
					},
					order = role.position
				})
			end

			if (roleregex) then
				for _, role in pairs(commandmessage:getGuild().roles) do
					if (role.name:lower():match(roleregex)) then
						ProcessRole(role)
					end
				end
			else
				for _, role in pairs(commandmessage:getGuild().roles) do
					if (role.name:lower() == rolename) then
						ProcessRole(role)
					end
				end
			end

			table.sort(messages, function (a, b) return a.order > b.order end)

			if (#messages > 0) then
				for _, data in pairs(messages) do
					commandMessage:reply(data.content)
				end
			else
				commandMessage:reply("No role found.")
			end
		end
	})

	return true
end
