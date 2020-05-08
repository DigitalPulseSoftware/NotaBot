-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local config = Config
local enums = discordia.enums

function Bot:BuildUsage(commandTable)
	local usage = {}
	for k,v in ipairs(commandTable.Args) do
		if (v.Optional) then
			table.insert(usage, string.format("[%s]", v.Name))
		else
			table.insert(usage, string.format("%s", v.Name))
		end
	end

	return table.concat(usage, " ")
end

function Bot:ParseCommandArgs(member, expectedArgs, args)	
	local parsers = self.ConfigTypeParameter

	local values = {}
	local argumentIndex = 1
	for argIndex, argData in ipairs(expectedArgs) do
		if (not args[argumentIndex]) then
			if (not argData.Optional) then
				return false, string.format("Missing argument #%d (%s)", argIndex, argData.Name)
			end

			break
		end

		local argValue
		if (argIndex == #expectedArgs and argumentIndex < #args) then
			argValue = table.concat(args, " ", argumentIndex)
		else
			argValue = args[argumentIndex]
		end

		local value, err = parsers[argData.Type](argValue, member.guild, argData.Options)
		if (value ~= nil) then
			values[argIndex] = value
			argumentIndex = argumentIndex + 1
		elseif (argData.Optional) then
			values[argIndex] = nil
			-- Do not increment argumentIndex, try to parse it again as the next parameter
		else
			return false, string.format("Invalid value for argument %d (%s)%s", argIndex, argData.Name, err and ": " .. err or "")
		end
	end

	return values
end

function Bot:RegisterCommand(values)
	local name = string.lower(values.Name)
	if (self.Commands[name]) then
		error("Command \"" .. name .. " already exists")
	end

	local command = {
		Args = values.Args,
		Function = values.Func,
		Help = values.Help,
		Name = name,
		PrivilegeCheck = values.PrivilegeCheck,
		Silent = values.Silent ~= nil and values.Silent
	}

	self.Commands[name] = command
end

function Bot:UnregisterCommand(commandName)
	self.Commands[commandName:lower()] = nil
end

Bot.Client:on('messageCreate', function(message)
	if (message.channel.type ~= enums.channelType.text) then
		return
	end

	local prefix = Config.Prefix
	local content = message.content
	if (not content:startswith(prefix)) then
		return
	end

	local commandName, args = content:match("^.?(%w+)%s*(.*)")
	if (not commandName) then
		return
	end

	commandName = commandName:lower()

	local commandTable = Bot.Commands[commandName]
	if (not commandTable) then
		return
	end

	if (commandTable.PrivilegeCheck) then
	 	local success, ret = Bot:ProtectedCall("Command " .. commandName .. " privilege check", commandTable.PrivilegeCheck, message.member)
	 	if (not success) then
	 		message:reply("An error occurred")
	 		return
	 	end

	 	if (not ret) then
			print(string.format("%s tried to use command %s on guild %s", message.author.tag, commandName, message.guild.name))
			return
		end
	end

	local args, err = Bot:ParseCommandArgs(message.member, commandTable.Args, string.GetArguments(args, #commandTable.Args))
	if (not args) then
		message:reply(err)
		return
	end

	Bot:ProtectedCall("Command " .. commandName, commandTable.Function, message, table.unpack(args, 1, #commandTable.Args))

	if (commandTable.Silent) then
		message:delete()
	end
end)

Bot:RegisterCommand({
	Name = "help",
	Args = {
		{Name = "command", Type = Bot.ConfigType.String, Optional = true}
	},
	Silent = false,

	Help = "Print commands list",
	Func = function (message, commandName)
		local member = message.member
		if (commandName) then
			commandName = commandName:lower()
			local commandTable = Bot.Commands[commandName]
			if (not commandTable) then
				return
			end

			if (commandTable.PrivilegeCheck) then
			 	local success, ret = Bot:ProtectedCall("Command " .. commandName .. " privilege check", commandTable.PrivilegeCheck, member)
			 	if (not success) then
			 		message:reply("An error occurred")
			 		return
			 	end

			 	if (not ret) then
					print(string.format("%s tried to access command %s via help on guild %s", message.author.tag, commandName, message.guild.name))
					return
				end
			end

			message:reply({
				embed = {
					fields = {
						{
							name = string.format("**Command: %s**", commandName),
							value = string.format("**Description:** %s\n**Usage:** %s %s", commandTable.Help or "<none>", commandName, Bot:BuildUsage(commandTable))
						}
					}
				}
			})
		else
			local commands = {}
			for commandName, commandTable in pairs(Bot.Commands) do
				local visible = true
				if (commandTable.PrivilegeCheck) then
				 	local success, ret = Bot:ProtectedCall("Command " .. commandName .. " privilege check", commandTable.PrivilegeCheck, member)
				 	if (not success or not ret) then
				 		visible = false
				 	end
				end

				if (visible) then
					table.insert(commands, commandTable)
				end
			end

			table.sort(commands, function (a, b) return a.Name < b.Name end)

			local fields = {}
			for _, commandTable in pairs(commands) do
				table.insert(fields, {
					name = string.format("**Command: %s**", commandTable.Name),
					value = string.format("**Description:** %s\n**Usage:** %s %s", commandTable.Help or "<none>", commandTable.Name, Bot:BuildUsage(commandTable))
				})
			end

			message:reply({
				embed = {
					fields = fields
				}
			})
		end
	end
})
