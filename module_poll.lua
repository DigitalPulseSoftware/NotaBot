-- Copyright (C) 2020 Antoine James Tournepiche & Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local client = Client
local discordia = Discordia
local bot = Bot
local enums = discordia.enums

Module.Name = "poll"

function Module:IsAllowedToSpecifyChannel(member, config)
	return member:hasPermission(enums.permission.administrator)
		or (config.SpecifyChannelAllowedRoles ~= nil
			and util.MemberHasAnyRole(member, config.SpecifyChannelAllowedRoles))
end

function Module:FormatChoiceResult(choiceVotes, barScale, totalVotes, asProgressBars)
	-- Pluralization
	local voteText = choiceVotes > 1 and "votes" or "vote"

	-- Configuration says we use progress bars.
	if asProgressBars then
		local progressLength = 20 -- Determines the length (in characters) of the progress bar
		local progressCharacter = '='
		local ratio = 0
		if barScale > 0 then
			ratio = choiceVotes / barScale -- barScale is the number of votes needed to have a full length bar
		end
		local choiceProgressLength = math.floor(ratio * progressLength)

		local progressText = string.rep(progressCharacter, choiceProgressLength) .. string.rep(' ', progressLength - choiceProgressLength)
		local percentage = choiceVotes / totalVotes * 100

		return string.format('`[%s]` **%d**   %s (%d%%)', progressText, choiceVotes, voteText, percentage)
	end

	-- Configuration says we use normal output.
	return string.format('**%d** %s', choiceVotes, voteText)
end

function Module:GetPollFooter(member, duration, isResults)
	local text = "Poll requested by " .. member.tag

	if duration == nil then
		return text
	end

	local verb = isResults and "Lasted" or "Lasts"

	if duration < 60 then
		duration = 60
	end

	text = string.format("%s. %s for %s.", text, verb, util.FormatTime(duration))
	return text
end

function Module:AddEmbedReactions(member, message)
	local data = self:GetData(member.guild)
	local poll = data.Polls[member.id]

	if poll == nil or #poll.choices == 0 then
		return
	end

	for _, choice in ipairs(poll.choices) do
		if choice.emoji ~= nil then
			message:addReaction(choice.emoji.Emoji or choice.emoji.Id)
		end
	end
end

function Module:CheckPermissions(member)
	if member:hasPermission(enums.permission.administrator) then
		return true
	end
	return util.MemberHasAnyRole(member, self:GetConfig(member.guild).AllowedRoles)
end

-- TODO? Ajouter option de cooldown entre 2 sondages pour un même membre
-- TODO? (plus tard) Ajouter option pour changer la couleur (param par défaut et action 'color')
function Module:GetConfigTable()
	return {
		{
			Array = true,
			Name = "AllowedRoles",
			Description = "Roles allowed to create polls",
			Type = bot.ConfigType.Role,
			Default = {}
		},
		{
			Array = true,
			Name = "SpecifyChannelAllowedRoles",
			Description = "Roles allowed to specify where to send a poll",
			Type = bot.ConfigType.Role,
			Default = {}
		},
		{
			Name = "DefaultPollChannel",
			Description = "Where should polls be sent if no channel is set on init",
			Type = bot.ConfigType.Channel,
			Optional = true
		},
		{
			Name = "DefaultPollDuration",
			Description = "Default poll duration if no duration is set on init",
			Type = bot.ConfigType.Duration,
			Default = 24 * 60 * 60
		},
		{
			Name = "DeletePollOnExpiration",
			Description = "Delete original poll message on expiration",
			Type = bot.ConfigType.Boolean,
			Default = true
		},
		{
			Name = "UseProgressBars",
			Description = "Use progress bars to fancy out results",
			Type = bot.ConfigType.Boolean,
			Default = true
		},
		{
			Name = "MostVotedRelative",
			Description = "Make Progress bars relative to the most voted choice, instead of being relative to total votes",
			Type = bot.ConfigType.Boolean,
			Default = false,
		}
	}
end

function Module:OnUnload()
	self.Timer:Stop()
end

function Module:OnEnable(guild)
	local data = self:GetData(guild)
	data.Polls = {}

	return true
end

function Module:OnLoaded()
	self.Timer = Bot:CreateRepeatTimer(1, -1, function ()
		local now = os.time()

		self:ForEachGuild(function(guildId, config, data, persistentData)
			local guild = client:getGuild(guildId)
			local config = self:GetConfig(guild)

			if persistentData.runningPolls == nil then
				return -- This is a callback so return instead of break
			end
			for index, poll in ipairs(persistentData.runningPolls) do
				local pollTime = poll[2]
				local duration = poll[3]

				-- Return if the poll isn't finished.
				if now >= (pollTime + duration) then
					local channel = guild:getChannel(poll[4])
					local member = guild:getMember(poll[1])
					if (not channel or not member) then
						goto remove
					end

					do
						local message = channel:getMessage(poll[5])
						if (not message) then
							goto remove
						end
						
						local totalVotes = 0
						local mostVotedCount = 0
						local map = {}

						local reactions = message.reactions:toArray()
						local fields = message.embed.fields

						local emojiNames = poll[6] -- This is stored in the same order as fields
						for _, reaction in ipairs(reactions) do
							local rEmojiData = Bot:GetEmojiData(guild, reaction.emojiName)
							-- This is nil when it is an extern emoji
							if not rEmojiData then
								break
							end
							local rEmojiName = rEmojiData.Name
							for i, emojiName in ipairs(emojiNames) do
								if rEmojiName == emojiName then
									table.insert(map, {
										count = reaction.count - 1,
										title = fields[i].value
									})

									local choiceVotes = reaction.count - 1

									if choiceVotes > mostVotedCount then
										mostVotedCount = choiceVotes
									end

									totalVotes = totalVotes + choiceVotes
									break
								end
							end
						end

						assert(#fields >= #map)

						if #fields > #map then
							for _, field in ipairs(fields) do
								local wasIn = false
								for _, mapElem in ipairs(map) do
									if mapElem.title == field.value then
										wasIn = true
										break
									end
								end
								if not wasIn then
									table.insert(map, {
										count = 0,
										title = field.value .. " *(**deleted**)*"
									})
								end
							end
						end

						local results = {
							author = {
								name = "Poll results",
								icon_url = member.avatarURL
							},
							title = message.embed.title,
							fields = {},
							footer = {text = self:GetPollFooter(member, duration, true)}
						}

						table.sort(map, function(a, b) return a.count > b.count end)

						local barScale
						if config.MostVotedRelative then
							barScale = mostVotedCount
						else
							barScale = totalVotes
						end

						for _, choice in ipairs(map) do
							table.insert(results.fields, {
								name = choice.title,
								value = self:FormatChoiceResult(choice.count, barScale, totalVotes, config.UseProgressBars)
							})
						end
						if not config.DeletePollOnExpiration then
							results.url = message.link
						end

						channel:send({
							embed = results
						})

						if config.DeletePollOnExpiration then
							local succeed = message:delete()
							if not succeed then
								channel:send("**ERROR** Failed to delete original poll message!")
							end
						end
					end

					::remove::
					table.remove(persistentData.runningPolls, index)
				end
			end
		end)
	end)

	self:RegisterCommand({
		Name = "createpoll",
		Args = {
			{Name = "title", Type = bot.ConfigType.String},
			{Name = "channel", Type = bot.ConfigType.Channel, Optional = true},
			{Name = "duration", Type = bot.ConfigType.Duration, Optional = true}
		},
		PrivilegeCheck = function (member) return self:CheckPermissions(member) end,

		Help = "Creates a poll (title format: \"title\")",
		Func = function (commandMessage, title, channel, duration)
			local member = commandMessage.member
			local guild = member.guild
			local data = self:GetData(guild)
			local polls = data.Polls

			local config = self:GetConfig(member.guild)
			local pollChannel = channel or config.DefaultPollChannel
			local pollDuration = duration or config.DefaultPollDuration

			if pollChannel == nil then
				commandMessage:reply("You need to either specify a channel, or configure one with the `config poll` command.")
				return
			end

			if channel ~= nil and not self:IsAllowedToSpecifyChannel(member, config) then
				commandMessage:reply("You are not allowed to specify a channel.")
				return
			end

			if (not polls[member.id]) then
				polls[member.id] = {
					title = title,
					channel = pollChannel,
					duration = pollDuration,
					choices = {}
				}

				commandMessage:reply('Poll created! Set it up using the `poll` command.')
			else
				commandMessage:reply("You are already setting up a poll.\nUse `cancelpoll` to abort the previous poll.")
			end
		end
	})

	self:RegisterCommand({
		Name = "cancelpoll",
		Args = {},
		PrivilegeCheck = function(member) return self:CheckPermissions(member) end,

		Help = "Cancels your current pending poll",
		Func = function(commandMessage)
			local member = commandMessage.member
			local data = self:GetData(member.guild)
			local polls = data.Polls

			if (polls[member.id]) then
				polls[member.id] = nil
				commandMessage:reply("You can now create a new poll.")
			else
				commandMessage:reply("You don't have a pending poll.")
			end
		end
	})

	self:RegisterCommand({
		Name = "poll",
		Args = {
			{Name = "action", Type = bot.ConfigType.String},
			{Name = "emoji", Type = bot.ConfigType.Emoji, Optional = true},
			{Name = "text", Type = bot.ConfigType.String, Optional = true}
		},
		PrivilegeCheck = function(member) return self:CheckPermissions(member) end,

		Help = "Sets up a poll",
		Func = function(commandMessage, action, emoji, text)
			local member = commandMessage.member
			local guild = member.guild
			local data = self:GetData(member.guild)
			local polls = data.Polls
			local poll = polls[member.id]

			if (not poll) then
				commandMessage:reply("You must create a poll in order to use this command!")
				return
			end

			if action == "add" then
				if #poll.choices >= 20 then
					commandMessage:reply("You can't add more than 20 choices!")
					return
				end

				if text == nil or text == '' then
					commandMessage:reply("You can't add a choice without text!")
					return
				end

				if emoji ~= nil then
					if self:IsAChoice(poll, emoji) then
						commandMessage:reply("This emoji is already used for a choice! Can't add it : use `update` action if you want to update it!\n")
						return
					end

					table.insert(poll.choices, {emoji = emoji, text = text})
				else
					commandMessage:reply("This emoji is unknown. If it is a Discord one, please contact Lynix for him to update the internal emoji list.")
					return
				end

				local message = commandMessage:reply({
					embed = self:FormatPoll(member, {}, nil, true)
				})
				self:AddEmbedReactions(member, message)
				return
			end

			if action == "remove" then
				local function RemoveChoice(emoji)
					local choices = {}
					local wasIn = false

					for _, choice in ipairs(poll.choices) do
						if choice.emoji.Name ~= emoji.Name then
							table.insert(choices, choice)
						else
							wasIn = true
						end
					end

					poll.choices = choices
					return wasIn
				end

				local reply = ""

				if text ~= nil then
					reply = reply .. "**WARN** The specified text is useless and will be ignored!\n"
				end

				if (RemoveChoice(emoji)) then
					reply = reply .. emoji.MentionString .. " has been removed!\n"
				else
					reply = reply .. emoji.MentionString .. " doesn't match any choice. It was not removed.\n"
				end

				local message = commandMessage:reply({
					embed = self:FormatPoll(member, {}, reply, true)
				})
				self:AddEmbedReactions(member, message)
				return
			end

			if action == "update" then
				if text == nil then
					commandMessage:reply("Can't update a choice without text! To remove a choice, use the `remove` action.")
					return
				end

				local reply = emoji.MentionString .. " text update has failed."
				for _, choice in ipairs(poll.choices) do
					if choice.emoji.Name == emoji.Name then
						choice.text = text
						reply = emoji.MentionString .. " text updated successfully."
						break
					end
				end

				local message = commandMessage:reply({
					embed = self:FormatPoll(member, {}, reply, true)
				})
				self:AddEmbedReactions(member, message)
				return
			end

			if action == "title" then
				if text == nil then
					commandMessage:reply("Invalid title! No title set!")
					return
				end

				polls[member.id].title = text
				commandMessage:reply("Title set to `" .. text .. "`")
				return
			end

			if action == "send" then
				if #polls[member.id].choices < 2 then
					commandMessage:reply("You can't send a poll without at least 2 choices! Set some using the `add` action!")
					return
				end

				local channel = guild:getChannel(poll.channel)
				local data = self:GetPersistentData(guild)
				local message = channel:send({
					embed = self:FormatPoll(member, {}, nil, false)
				})
				self:AddEmbedReactions(member, message)

				data.runningPolls = data.runningPolls or {}
				-- TODO? Ajouter option pour empêcher un membre de faire un sondage s'il en a déjà un en cours
				local emojiNames = {}
				for i, choice in ipairs(poll.choices) do
					emojiNames[i] = choice.emoji.Name
				end

				table.insert(data.runningPolls, {member.id, os.time(), poll.duration, channel.id, message.id, emojiNames})

				polls[member.id] = nil

				commandMessage:reply(string.format("Poll successfully sent to %s (#%s).", channel.mentionString, channel.name))
				return
			end

			commandMessage:reply("Invalid action. It can only be `add`, `remove`, `update`, `title` or `send`.")
		end
	})

	return true
end

function Module:IsAChoice(poll, emoji)
	for _, choice in ipairs(poll.choices) do
		if choice.emoji.Id == emoji.Id then
			return true
		end
	end

	return false
end

-- TODO Respect limitations : https://birdie0.github.io/discord-webhooks-guide/other/field_limits.html
function Module:FormatPoll(member, embed, footer, preview)
	local guild = member.guild
	local data = self:GetData(guild)

	local fields = {}
	local poll = data.Polls[member.id]
	local title = preview and "[Preview] " .. poll.title or poll.title

	for i, choice in ipairs(poll.choices) do
		if Bot:GetEmojiData(guild, choice.emoji.Name) ~= nil then
			table.insert(fields, {
				name = "Choice n°" .. i,
				value = string.format("%s  %s", choice.emoji.MentionString, choice.text)
			})
		else
			-- Deinit the poll
			data.Polls[member.id] = nil
			client:info("An emoji was deleted during the configuration of a poll that was using it.")

			return {
				title = "An emoji is broken.",
				fields = {
					{
						name = "This is not a bot error.",
						value = "This happens when an emoji in the poll is deleted during its configuration."
					},
					{
						name = "How to fix it?",
						value = "You can't! Your poll has been cancelled."
					},
					{
						name = "What to do now?",
						value = "Just use the command `createpoll` and redo everything."
					}
				}
			}
		end
	end

	-- TODO? Add expiration date to the footer OR add launch time!
	embed.title = title
	embed.fields = fields

	if footer ~= nil then
		embed.footer = { text = footer }
	else
		embed.footer = { text = self:GetPollFooter(member, poll.duration) }
	end

	return embed
end
