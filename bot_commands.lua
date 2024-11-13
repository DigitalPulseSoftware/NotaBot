-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local client = Bot.Client
local config = Config
local enums = discordia.enums

local MAX_NUMBER_OF_EMBED_FIELDS = 25

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
		Silent = values.Silent ~= nil and values.Silent,
		BotAware = values.BotAware ~= nil and values.BotAware
	}

	self.Commands[name] = command
end

function Bot:UnregisterCommand(commandName)
	self.Commands[commandName:lower()] = nil
end

local prefixes = {
	function (content, guild)
		local prefix = Config.Prefix
		if guild then
			local serverconfig = Bot:GetModuleForGuild(guild, "serverconfig")
			if serverconfig then
				local config = serverconfig:GetConfig(guild)
				if config then
					prefix = config.Prefix
				end
			end
		end

		return content:startswith(prefix, true) and content:sub(#prefix + 1) or nil
	end,
	function (content)
		local userPing, rest = content:match("<@!?(%d+)>%s*(.+)")
		return userPing and userPing == client.user.id and rest or nil
	end
}

client:on('messageCreate', function(message)
	if (not Bot:IsPublicChannel(message.channel)) then
		return
	end

	local content

	for _, func in pairs(prefixes) do
		content = func(message.content, message.guild)
		if (content) then
			break
		end
	end

	if (not content) then
		return
	end

	local commandName, args = content:match("^(%w+)%s*(.*)")
	if (not commandName) then
		return
	end

	commandName = commandName:lower()

	local commandTable = Bot.Commands[commandName]
	if (not commandTable) then
		return
	end

	if (not commandTable.BotAware and message.author.bot) then
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

local function getCommands(member)
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

	local commandsFields = {}
	for _, commandTable in pairs(commands) do
		local helpStr = commandTable.Help or "<none>"
		if(type(helpStr) == "function") then -- localization
			helpStr = commandTable.Help(member.guild)
		end

		table.insert(commandsFields, {
			name = string.format("**Command: %s**", commandTable.Name),
			value = string.format("**Description:** %s\n**Usage:** %s %s", helpStr, commandTable.Name, Bot:BuildUsage(commandTable))
		})
	end

	return commandsFields
end

local function getHelpButtonsComponent(guild, selectedPage, nbPages)
	local components = {}
	local actionButtons = {
		{
			type = enums.componentType.button,
			custom_id = "help_button_previous_page_" .. selectedPage - 1,
			style = enums.buttonStyle.primary,
			label = Bot:Format(guild, "BOT_HELP_PREV_BUTTON_LABEL"),
			disabled = (selectedPage - 1) < 1 and true or false
		},
		{
			type = enums.componentType.button,
			custom_id = "help_button_next_page_" .. selectedPage + 1,
			style = enums.buttonStyle.primary,
			label = Bot:Format(guild, "BOT_HELP_NEXT_BUTTON_LABEL"),
			disabled = (selectedPage + 1) > nbPages and true or false
		}
	}

	table.insert(components, {
		type = enums.componentType.actionRow,
		components = actionButtons
	})

	return components
end

client:on("interactionCreate", function (interaction)
	local guild = interaction.guild
	if (not guild) then
		return
	end

	local member = interaction.member
	local interactionId = interaction.data.custom_id
	if (not string.match(interactionId, "^help_button")) then
		return
	end

	local commandsFields = getCommands(member)
	local nbPages = math.floor((#commandsFields - 1) / MAX_NUMBER_OF_EMBED_FIELDS) + 1
	local selectedPage = tonumber(string.match(interactionId, "(%d+)$")) or 1

	if (selectedPage < 1 or selectedPage > nbPages) then
		return
	end

	local page = {
		table.unpack(
			commandsFields,
			((selectedPage - 1) * MAX_NUMBER_OF_EMBED_FIELDS) + 1,
			selectedPage * MAX_NUMBER_OF_EMBED_FIELDS
		)
	}

	interaction.message:update({
		components = getHelpButtonsComponent(guild, selectedPage, nbPages),
		embed = {
			fields = page,
			footer = { text = string.format("Page %s/%s", selectedPage, nbPages) }
		}
	})

	interaction:respond({
		type = enums.interactionResponseType.updateMessage
	})
end)

Bot:RegisterCommand({
	Name = "help",
	Args = {
		{ Name = "command", Type = Bot.ConfigType.String, Optional = true }
	},
	Silent = false,

	Help = function (guild) return Bot:Format(guild, "BOT_HELP_HELP") end,
	Func = function (message, commandName)
		local member = message.member
		local guild = message.guild
		local commandsFields = {}

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
					print(string.format("%s tried to access command %s via help on guild %s", message.author.tag, commandName, guild.name))
					return
				end
			end

			local helpStr = commandTable.Help or "<none>"
			if(type(helpStr) == "function") then -- localization
				helpStr = commandTable.Help(guild)
			end

			table.insert(commandsFields, {
					name = string.format("**Command: %s**", commandName),
					value = string.format("**Description:** %s\n**Usage:** %s %s", helpStr, commandName, Bot:BuildUsage(commandTable))
			})
		else
			commandsFields = getCommands(member)
		end

		-- pagination
		local components = {}
		if (#commandsFields > MAX_NUMBER_OF_EMBED_FIELDS) then
			local nbPages = math.floor((#commandsFields - 1) / MAX_NUMBER_OF_EMBED_FIELDS) + 1
			local selectedPage = 1

			commandsFields = { table.unpack(commandsFields, 1, MAX_NUMBER_OF_EMBED_FIELDS) }
			components = getHelpButtonsComponent(guild, selectedPage, nbPages)

			local footer = { text = string.format("Page %s/%s", selectedPage, nbPages) }
		end

		message:reply({
			embed = {
				fields = commandsFields,
				footer = footer or null
			},
			components = components
		})
	end
})
