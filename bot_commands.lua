-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local client = Bot.Client
local config = Config
local enums = discordia.enums

local MAX_NUMBER_OF_EMBED_FIELDS = 25

local applicationId
client:onceSync("ready", function ()
	local info = client:getApplicationInformation()
	applicationId = info and info.id or client.user.id
end)

function Bot:BuildUsage(commandTable)
	local usage = {}
	for k,v in ipairs(commandTable.Args) do
		if (v.Optional) then
			table.insert(usage, string.format("[%s]", v.Name))
		else
			table.insert(usage, string.format("<%s>", v.Name))
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
			return false,
				string.format("Invalid value for argument %d (%s)%s", argIndex, argData.Name, err and ": " .. err or "")
		end
	end

	return values
end

function Bot:RegisterCommand(values)
	local name = string.lower(values.Name)
	if (self.Commands[name]) then
		error("Command \"" .. name .. " already exists")
	end

	local subcommands
	if (values.Subcommands) then
		subcommands = {}
		for _, sub in ipairs(values.Subcommands) do
			subcommands[sub.Name:lower()] = {
				Name = sub.Name:lower(),
				Description = sub.Description,
				Args = sub.Args or {},
				PrivilegeCheck = sub.PrivilegeCheck,
				Func = sub.Func
			}
		end
	end

	local command = {
		Args = values.Args,
		Function = values.Func,
		Help = values.Help,
		Name = name,
		PrivilegeCheck = values.PrivilegeCheck,
		Silent = values.Silent ~= nil and values.Silent,
		BotAware = values.BotAware ~= nil and values.BotAware,
		Slash = values.Slash,
		ContextMenu = values.ContextMenu,
		Subcommands = subcommands,
		SlashFunc = values.Slash and values.Slash.Func or values.Func,
		ContextMenuFunc = values.ContextMenu and values.ContextMenu.Func or values.Func
	}

	self.Commands[name] = command
end

function Bot:UnregisterCommand(commandName)
	self.Commands[commandName:lower()] = nil
end

Bot.ApplicationCommandIds = {}

local function buildOptionsFromArgs(argsList)
	local options = {}
	for _, argData in ipairs(argsList or {}) do
		table.insert(options, {
			name = argData.Name:lower(),
			description = argData.Description or argData.Name,
			type = Bot.ConfigTypeToCommandOptionType[argData.Type],
			required = not argData.Optional,
			autocomplete = argData.Autocomplete ~= nil or nil
		})
	end
	return options
end

function Bot:SyncApplicationCommandsForGuild(guild, commandNames)
	for _, name in ipairs(commandNames) do
		local commandTable = self.Commands[name]
		if (commandTable) then
			if (commandTable.Subcommands) then
				local options = {}
				for _, sub in pairs(commandTable.Subcommands) do
					local subOptions = buildOptionsFromArgs(sub.Args)
					table.insert(options, {
						name = sub.Name,
						description = sub.Description or sub.Name,
						type = 1,
						options = #subOptions > 0 and subOptions or nil
					})
				end
				local payload = {
					name = name,
					description = type(commandTable.Help) == "function" and commandTable.Help(guild) or commandTable.Help
						or name,
					type = 1,
					options = options
				}
				local cmd, err = client._api:createGuildApplicationCommand(applicationId, guild.id, payload)
				if (cmd) then
					self.ApplicationCommandIds[guild.id .. ":slash:" .. name] = cmd.id
				else
					self.Client:error("Failed to register slash command %s: %s", name, err)
				end
			elseif (commandTable.Slash) then
				local options = buildOptionsFromArgs(commandTable.Args)
				local description = commandTable.Slash.Description
				if (type(commandTable.Help) == "function") then
					description = description or commandTable.Help(guild)
				else
					description = description or commandTable.Help
				end
				local payload = { name = name, description = description, type = 1, options = #options > 0 and options
					or nil }
				local cmd, err = client._api:createGuildApplicationCommand(applicationId, guild.id, payload)
				if (cmd) then
					self.ApplicationCommandIds[guild.id .. ":slash:" .. name] = cmd.id
				else
					self.Client:error("Failed to register slash command %s: %s", name, err)
				end
			end
			if (commandTable.ContextMenu) then
				local menuType = commandTable.ContextMenu.Type == "message" and 3 or 2
				local payload = { name = name, type = menuType }
				local cmd, err = client._api:createGuildApplicationCommand(applicationId, guild.id, payload)
				if (cmd) then
					self.ApplicationCommandIds[guild.id .. ":context:" .. name] = cmd.id
				else
					self.Client:error("Failed to register context menu command %s: %s", name, err)
				end
			end
				end
			end
		end

function Bot:UnsyncApplicationCommandsForGuild(guild, commandNames)
	for _, name in ipairs(commandNames) do
		for _, kind in ipairs({ "slash", "context" }) do
			local key = guild.id .. ":" .. kind .. ":" .. name
			local id = self.ApplicationCommandIds[key]
			if (id) then
				client._api:deleteGuildApplicationCommand(applicationId, guild.id, id)
				self.ApplicationCommandIds[key] = nil
			end
		end
	end
end

local prefixes = {
	function (content, guild)
		local prefix = Bot:GetGuildPrefix(guild)
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
		local success, ret = Bot:ProtectedCall(
			"Command " .. commandName .. " privilege check", commandTable.PrivilegeCheck, message.member
		)
	 	if (not success) then
	 		message:reply("An error occurred")
	 		return
	 	end

	 	if (not ret) then
			print(
				string.format(
					"%s tried to use command %s on guild %s", message.author.tag, commandName, message.guild.name
				)
			)
			return
		end
	end

	local args, err = Bot:ParseCommandArgs(
		message.member, commandTable.Args, string.GetArguments(args, #commandTable.Args)
	)
	if (not args) then
		message:reply(err)
		return
	end

	Bot:ProtectedCall(
		"Command " .. commandName, commandTable.Function, message, table.unpack(args, 1, #commandTable.Args)
	)

	if (commandTable.Silent) then
		message:delete()
	end
end)

local function getCommands(member)
	local commands = {}

	for commandName, commandTable in pairs(Bot.Commands) do
		local visible = true
		if (commandTable.PrivilegeCheck) then
			local success, ret = Bot:ProtectedCall(
				"Command " .. commandName .. " privilege check", commandTable.PrivilegeCheck, member
			)
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

		if commandTable.Args ~= nil then
		table.insert(commandsFields, {
			name = string.format("**Command: %s**", commandTable.Name),
				value = string.format(
					"**Description:** %s\n**Usage:** %s %s", helpStr, commandTable.Name, Bot:BuildUsage(commandTable)
				)
		})
	end
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

local function resolveArgsFromOptions(guild, argsList, options)
	local optionsByName = {}
	for _, opt in ipairs(options or {}) do
		optionsByName[opt.name:lower()] = opt.value
	end

	local args = {}
	for i, argData in ipairs(argsList) do
		local raw = optionsByName[argData.Name:lower()]
		if (raw == nil) then
			if (not argData.Optional) then
				return nil, "Missing required argument: " .. argData.Name
			end
		elseif (argData.Type == Bot.ConfigType.Member) then
			args[i] = guild:getMember(raw)
		elseif (argData.Type == Bot.ConfigType.User) then
			args[i] = Bot:DecodeUser(raw)
		elseif (argData.Type == Bot.ConfigType.Duration) then
			args[i] = Bot.ConfigTypeParameter[Bot.ConfigType.Duration](tostring(raw), guild)
		elseif (argData.Type == Bot.ConfigType.Channel or argData.Type == Bot.ConfigType.Category) then
			args[i] = guild:getChannel(raw)
		elseif (argData.Type == Bot.ConfigType.Role) then
			args[i] = guild:getRole(raw)
		else
			args[i] = raw
		end
	end
	return args
end

function Bot:DispatchApplicationCommand(interaction)
	local guild = interaction.guild
	if (not guild) then
		return interaction:respond({
			type = enums.interactionResponseType.channelMessageWithSource,
			data = {
				content = "This command can only be used in a server.",
				flags = enums.interactionResponseFlag.ephemeral
			}
		})
	end

	local data = interaction.data
	local commandTable = self.Commands[data.name:lower()]
	if (not commandTable) then return end

	local member = interaction.member
	if (commandTable.PrivilegeCheck) then
		local success, ret = self:ProtectedCall(
			"Command " .. data.name .. " privilege check", commandTable.PrivilegeCheck, member
		)
		if (not success or not ret) then
			return interaction:respond({
				type = enums.interactionResponseType.channelMessageWithSource,
				data = {
					content = "You are not authorized to use this command.",
					flags = enums.interactionResponseFlag.ephemeral
				}
			})
		end
	end

	if (commandTable.Subcommands) then
		local subOption = data.options and data.options[1]
		local sub = subOption and commandTable.Subcommands[subOption.name:lower()]
		if (not sub) then return end

		if (sub.PrivilegeCheck) then
			local success, ret = self:ProtectedCall(
				"Command " .. data.name .. " " .. sub.Name .. " privilege check", sub.PrivilegeCheck, member
			)
			if (not success or not ret) then
				return interaction:respond({
					type = enums.interactionResponseType.channelMessageWithSource,
					data = {
						content = "You are not authorized to use this command.",
						flags = enums.interactionResponseFlag.ephemeral
					}
				})
			end
		end

		local args, err = resolveArgsFromOptions(guild, sub.Args, subOption.options)
		if (not args) then
			return interaction:respond({
				type = enums.interactionResponseType.channelMessageWithSource,
				data = {
					content = err,
					flags = enums.interactionResponseFlag.ephemeral
				}
			})
		end

		return self:ProtectedCall(
			"Command " .. data.name .. " " .. sub.Name, sub.Func, interaction, table.unpack(args, 1, #sub.Args)
		)
	end

	local args, func
	if (data.target_id) then
		if (commandTable.ContextMenu and commandTable.ContextMenu.Type == "message") then
			local targetMessage = interaction.channel and interaction.channel:getMessage(data.target_id)
			if (not targetMessage) then
				return interaction:respond({
					type = enums.interactionResponseType.channelMessageWithSource,
					data = {
						content = "Target message not found.",
						flags = enums.interactionResponseFlag.ephemeral
					}
				})
			end
			args = { targetMessage }
		else
			local targetMember = guild:getMember(data.target_id)
			if (not targetMember) then
				return interaction:respond({
					type = enums.interactionResponseType.channelMessageWithSource,
					data = {
						content = "Target is not a member of this server.",
						flags = enums.interactionResponseFlag.ephemeral
					}
				})
			end
			args = { targetMember }
		end
		func = commandTable.ContextMenuFunc
	else
		local err
		args, err = resolveArgsFromOptions(guild, commandTable.Args, data.options)
		if (not args) then
			return interaction:respond({
				type = enums.interactionResponseType.channelMessageWithSource,
				data = {
					content = err,
					flags = enums.interactionResponseFlag.ephemeral
				}
			})
		end
		func = commandTable.SlashFunc
	end

	self:ProtectedCall("Command " .. data.name, func, interaction, table.unpack(args, 1, #commandTable.Args))
end

function Bot:DispatchApplicationCommandAutocomplete(interaction)
	local guild = interaction.guild
	local data = interaction.data
	local commandTable = self.Commands[data.name:lower()]

	local focused
	for _, opt in ipairs(data.options or {}) do
		if (opt.focused) then
			focused = opt
		end
	end

	local choices = {}
	if (guild and commandTable and focused) then
		local argData
		for _, a in ipairs(commandTable.Args or {}) do
			if (a.Name:lower() == focused.name:lower()) then
				argData = a
				break
			end
		end

		if (argData and argData.Autocomplete) then
			local success, ret = self:ProtectedCall(
				"Autocomplete " .. data.name, argData.Autocomplete, guild, interaction.member, focused.value or ""
			)
			if (success and type(ret) == "table") then
				choices = ret
				if (#choices > 25) then
					local clipped = {}
					for i = 1, 25 do
						clipped[i] = choices[i]
					end
					choices = clipped
				end
			end
		end
	end

	interaction:respond({
		type = enums.interactionResponseType.applicationCommandAutocompleteResult,
		data = { choices = choices }
	})
end

client:on("interactionCreate", function (interaction)
	if (interaction.type == enums.interactionRequestType.applicationCommand) then
		return Bot:DispatchApplicationCommand(interaction)
	end

	if (interaction.type == enums.interactionRequestType.applicationCommandAutocomplete) then
		return Bot:DispatchApplicationCommandAutocomplete(interaction)
	end

	local guild = interaction.guild
	if (not guild) then
		return
	end

	local member = interaction.member
	local interactionId = interaction.data.custom_id
	if (not interactionId or not string.match(interactionId, "^help_button")) then
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
			commandsFields, ((selectedPage - 1) * MAX_NUMBER_OF_EMBED_FIELDS) + 1,
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
				local success, ret = Bot:ProtectedCall(
					"Command " .. commandName .. " privilege check", commandTable.PrivilegeCheck, member
				)
			 	if (not success) then
			 		message:reply("An error occurred")
			 		return
			 	end

			 	if (not ret) then
					print(
						string.format(
							"%s tried to access command %s via help on guild %s", message.author.tag, commandName,
							guild.name
						)
					)
					return
				end
			end

			local helpStr = commandTable.Help or "<none>"
			if(type(helpStr) == "function") then -- localization
				helpStr = commandTable.Help(guild)
			end

			table.insert(commandsFields, {
					name = string.format("**Command: %s**", commandName),
				value = string.format(
					"**Description:** %s\n**Usage:** %s %s", helpStr, commandName, Bot:BuildUsage(commandTable)
				)
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
