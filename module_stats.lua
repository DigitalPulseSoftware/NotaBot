-- Copyright (C) 2018 Jérôme Leclercq
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

Module.Name = "stats"

function Module:GetConfigTable()
	return {
		{
			Name = "LogChannel",
			Description = "Channel where stats will be posted each day",
			Type = bot.ConfigType.Channel,
			Optional = true
		}
	}
end

function Module:OnLoaded()
	self.Clock = discordia.Clock()
	self.Clock:on("day", function ()
		self:ForEachGuild(function (guildId, config, data, persistentData)
			local guild = client:getGuild(guildId)
			assert(guild)

			local stats = persistentData.Stats
			self:SaveStats(self:GetStatsFilename(guild, stats.Date), stats)
			persistentData.Stats = self:ResetStats(guild)

			if (config.LogChannel) then
				local channel = guild:getChannel(config.LogChannel)
				if (channel) then
					self:PrintStats(channel, stats)
				end
			end
		end)
	end)

	bot:RegisterCommand("resetstats", "Reset stats", function (commandMessage)
		if (not commandMessage.member:hasPermission(enums.permission.administrator)) then
			print(tostring(message.member.name) .. " tried to use !resetstats")
			return
		end

		local data = self:GetPersistentData(commandMessage.guild)
		data.Stats = self:ResetStats()
		commandMessage:reply("Stats reset successfully")
	end)

	bot:RegisterCommand("serverstats", "Print stats", function (commandMessage, date)
		local stats
		if (date) then
			if (not date:match("^%d%d%d%d%-%d%d%-%d%d$")) then
				commandMessage:reply("Invalid date format, please write it as YYYY-MM-DD")
				return
			end

			stats = self:LoadStats(commandMessage.guild, self:GetStatsFilename(commandMessage.guild, date))
			if (not stats) then
				commandMessage:reply("We have no stats for that date")
				return
			end
		else
			local data = self:GetPersistentData(commandMessage.guild)
			stats = data.Stats
		end

		self:PrintStats(commandMessage.channel, stats)
	end)

	return true
end

function Module:OnEnable(guild)
	local data = self:GetPersistentData(guild)
	if (not data.Stats) then
		self:LogInfo(guild, "No previous stats found, resetting...")
		data.Stats = self:ResetStats(guild)
	else
		local currentDate = os.date("%Y-%m-%d")
		local statsDate = os.date("%Y-%m-%d", data.Stats.Date)
		if (currentDate ~= statsDate) then
			self:LogInfo(guild, "Previous stats data has been found but date does not match (%s), saving and resetting", statsDate)
			self:SaveStats(self:GetStatsFilename(guild, data.Stats.Date), data.Stats)
			data.Stats = self:ResetStats(guild)
		else
			self:LogInfo(guild, "Previous stats data has been found and date does match, continuing...")
		end
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

	bot:UnregisterCommand("resetstats")
	bot:UnregisterCommand("serverstats")
end

function Module:LoadStats(guild, filepath)
	local stats, err = bot:UnserializeFromFile(filepath)
	if (not stats) then
		self:LogError(guild, "Failed to load stats: %s", err)
		return
	end

	return stats
end

function Module:GetStatsFilename(guild, time)
	return string.format("stats/guild_%s/stats_%s.json", guild.id, (type(time) == "number") and os.date("%Y-%m-%d", time) or time)
end

function Module:PrintStats(channel, stats)	
	local guild = channel.guild
	
	local mostAddedReaction = {}
	for reactionName, reactionStats in pairs(stats.Reactions) do
		table.insert(mostAddedReaction, { name = reactionName, count = reactionStats.ReactionCount })
	end
	table.sort(mostAddedReaction, function (a, b) return a.count > b.count end)

	local addedReactionList = ""
	for i = 1, 5 do
		if (i > #mostAddedReaction) then
			break
		end

		local reactionData = mostAddedReaction[i]

		local emojiData = bot:GetEmojiData(guild, reactionData.name)
		addedReactionList = addedReactionList .. string.format("%s %s\n", reactionData.count, emojiData.MentionString or "<bot error>")
	end

	local mostActiveChannels = {}
	for channelId, channelStats in pairs(stats.Channels) do
		table.insert(mostActiveChannels, { id = channelId, messageCount = channelStats.MessageCount })
	end
	table.sort(mostActiveChannels, function (a, b) return a.messageCount > b.messageCount end)

	local activeChannelList = ""
	for i = 1, 5 do
		if (i > #mostActiveChannels) then
			break
		end

		local channelData = mostActiveChannels[i]
		local channel = guild:getChannel(channelData.id)
		activeChannelList = activeChannelList .. string.format("%d m. in %s\n", channelData.messageCount, channel and channel.mentionString or "<deleted channel>")
	end

	local fields = {
		{
			name = "Member count", value = stats.MemberCount or "<Not logged>", inline = true
		},
		{
			name = "New members", value = stats.MemberJoined, inline = true
		},
		{
			name = "Lost members", value = stats.MemberLeft, inline = true
		},
		{
			name = "Messages posted", value = stats.MessageCount, inline = true
		},
		{
			name = "Active members", value = table.count(stats.Users), inline = true
		},
		{
			name = "Active channels", value = table.count(stats.Channels), inline = true
		},
		{
			name = "Total reactions added", value = stats.ReactionAdded, inline = true
		},
		{
			name = "Most added reactions", value = #addedReactionList > 0 and addedReactionList or "<None>", inline = true
		},
		{
			name = "Most active channels", value = #activeChannelList > 0 and activeChannelList or "<None>", inline = true
		}
	}

	local resetTime = os.difftime(os.time(), stats.Date)
	local title = string.format("Server stats - %s, started %s ago", os.date("%d-%m-%Y", stats.Date), util.FormatTime(resetTime, 2))
	
	channel:send({
		embed = {
			title = title,
			fields = fields,
			timestamp = discordia.Date(stats.Date):toISO('T', 'Z')
		}
	})
end

function Module:ResetStats(guild)
	local stats = {}
	stats.Date = os.time()
	stats.Channels = {}
	stats.Reactions = {}
	stats.Users = {}
	stats.MemberCount = guild.totalMemberCount
	stats.MemberLeft = 0
	stats.MemberJoined = 0
	stats.MessageCount = 0
	stats.ReactionAdded = 0
	stats.ReactionRemoved = 0

	return stats
end

function Module:SaveStats(filename, stats)
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

	local success, err = outputFile:write(json.encode(stats))
	if (not success) then
		self:LogError("Failed to open %s", err)
		return
	end

	outputFile:close()
end

function Module:GetChannelStats(guild, channelId)
	local data = self:GetPersistentData(guild)

	local channels = data.Stats.Channels
	local channelStats = channels[channelId]
	if (not channelStats) then
		channelStats = {}
		channelStats.MessageCount = 0
		channelStats.ReactionCount = 0

		channels[channelId] = channelStats
	end

	return channelStats
end

function Module:GetReactionStats(guild, reactionName)
	local data = self:GetPersistentData(guild)

	local reactions = data.Stats.Reactions
	local reactionStats = reactions[reactionName]
	if (not reactionStats) then
		reactionStats = {}
		reactionStats.ReactionCount = 0

		reactions[reactionName] = reactionStats
	end

	return reactionStats
end

function Module:GetUserStats(guild, userId)
	local data = self:GetPersistentData(guild)

	local users = data.Stats.Users
	local userStats = users[userId]
	if (not userStats) then
		userStats = {}
		userStats.MessageCount = 0
		userStats.ReactionCount = 0

		users[userId] = userStats
	end

	return userStats
end

function Module:OnMessageCreate(message)
	if (message.channel.type ~= enums.channelType.text) then
		return
	end

	if (message.author.bot) then
		return
	end

	local data = self:GetPersistentData(message.guild)
	data.Stats.MessageCount = data.Stats.MessageCount + 1
	
	-- Channels
	local channelStats = self:GetChannelStats(message.guild, message.channel.id)
	channelStats.MessageCount = channelStats.MessageCount + 1
	
	-- Members
	local userStats = self:GetUserStats(message.guild, message.author.id)
	userStats.MessageCount = userStats.MessageCount + 1
end

function Module:OnMemberJoin(member)
	if (member.user.bot) then
		return
	end

	local data = self:GetPersistentData(member.guild)
	data.Stats.MemberJoined = data.Stats.MemberJoined + 1
	data.Stats.MemberCount = data.Stats.MemberCount + 1
end

function Module:OnMemberLeave(member)
	if (member.user.bot) then
		return
	end

	local data = self:GetPersistentData(member.guild)
	data.Stats.MemberLeft = data.Stats.MemberLeft + 1
	data.Stats.MemberCount = data.Stats.MemberCount - 1
end

function Module:OnReactionAdd(reaction, userId)
	if (reaction.message.channel.type ~= enums.channelType.text) then
		return
	end

	local data = self:GetPersistentData(reaction.message.guild)
	data.Stats.ReactionAdded = data.Stats.ReactionAdded + 1

	local channelStats = self:GetChannelStats(reaction.message.guild, reaction.message.channel.id)
	channelStats.ReactionCount = channelStats.ReactionCount + 1

	local reactionStats = self:GetReactionStats(reaction.message.guild, reaction.emojiName)
	reactionStats.ReactionCount = reactionStats.ReactionCount + 1

	local userStats = self:GetUserStats(reaction.message.guild, userId)
	userStats.ReactionCount = userStats.ReactionCount + 1
end

function Module:OnReactionAddUncached(channel, messageId, reactionIdorName, userId)
	if (channel.type ~= enums.channelType.text) then
		return
	end

	local emojiData = bot:GetEmojiData(channel.guild, reactionIdorName)
	if (not emojiData) then
		self:LogWarning(channel.guild, "Emoji %s was used but not found in guild", reactionIdorName)
		return
	end

	local data = self:GetPersistentData(channel.guild)
	data.Stats.ReactionAdded = data.Stats.ReactionAdded + 1

	local channelStats = self:GetChannelStats(channel.guild, channel.id)
	channelStats.ReactionCount = channelStats.ReactionCount + 1

	local reactionStats = self:GetReactionStats(channel.guild, emojiData.Name)
	reactionStats.ReactionCount = reactionStats.ReactionCount + 1

	local userStats = self:GetUserStats(channel.guild, userId)
	userStats.ReactionCount = userStats.ReactionCount + 1
end

function Module:OnReactionRemove(reaction, userId)
	if (reaction.message.channel.type ~= enums.channelType.text) then
		return
	end

	local data = self:GetPersistentData(reaction.message.guild)
	data.Stats.ReactionRemoved = data.Stats.ReactionRemoved + 1

	local reactionStats = self:GetReactionStats(reaction.message.guild, reaction.emojiName)
	reactionStats.ReactionCount = math.max(reactionStats.ReactionCount - 1, 0)
end

function Module:OnReactionRemoveUncached(channel, messageId, reactionIdorName, userId)
	if (channel.type ~= enums.channelType.text) then
		return
	end

	local emojiData = bot:GetEmojiData(channel.guild, reactionIdorName)
	if (not emojiData) then
		self:LogWarning(channel.guild, "Emoji %s was used but not found in guild", reactionIdorName)
		return
	end

	local data = self:GetPersistentData(channel.guild)
	data.Stats.ReactionRemoved = data.Stats.ReactionRemoved + 1

	local reactionStats = self:GetReactionStats(channel.guild, emojiData.Name)
	reactionStats.ReactionCount = math.max(reactionStats.ReactionCount - 1, 0)
end
