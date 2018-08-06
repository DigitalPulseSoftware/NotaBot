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

function Module:OnLoaded()
	self.Clock = discordia.Clock()
	self.Clock:on("day", function ()
		local stats = self.Stats
		self:SaveStats(os.date("stats/stats_%Y-%m-%d.json", stats.Date or os.time()))
		self.Stats = self:ResetStats()

		if (config.StatsModuleLogChannel) then
			local guild = client:getGuild(config.Guild)
			local channel = guild:getChannel(config.StatsModuleLogChannel)
			if (channel) then
				self:PrintStats(channel, stats)
			end
		end
	end)

	self.SaveCounter = 0
	self.Clock:on("min", function ()
		self.SaveCounter = self.SaveCounter + 1
		if (self.SaveCounter >= 5) then
			self:SaveStats()
			self.SaveCounter = 0
		end
	end)

	self.Clock:start()

	self.Stats = self:LoadStats()
	if (self.Stats) then
		print("Successfully reloaded stats from file")
	else
		print("Failed to load stats, resetting...")
		self.Stats = self:ResetStats()
	end

	bot:RegisterCommand("resetstats", "Reset stats", function (commandMessage)
		if (not commandMessage.member:hasPermission(enums.permission.administrator)) then
			print(tostring(message.member.name) .. " tried to use !resetstats")
			return
		end

		self.Stats = self:ResetStats()
		commandMessage:reply("Stats reset successfully")
	end)

	bot:RegisterCommand("serverstats", "Print stats", function (commandMessage, date)
		local stats
		if (date) then
			if (not date:match("^%d%d%d%d%-%d%d%-%d%d$")) then
				commandMessage:reply("Invalid date format, please write it as YYYY-MM-DD")
				return
			end

			stats = self:LoadStats(string.format("stats/stats_%s.json", date))
			if (not stats) then
				commandMessage:reply("We have no stats for that date")
				return
			end
		else
			stats = self.Stats
		end

		self:PrintStats(commandMessage.channel, stats)
	end)

	bot:RegisterCommand("savestats", "Saves message stats to the disk", function (commandMessage)
		if (not commandMessage.member:hasPermission(enums.permission.administrator)) then
			print(tostring(message.member.name) .. " tried to use !savestats")
			return
		end

		self:SaveStats()
		self.SaveCounter = 0
		commandMessage:reply("Stats saved successfully")
	end)

	return true
end

function Module:OnUnload()
	self:SaveStats()

	if (self.Clock) then
		self.Clock:stop()
	end

	bot:UnregisterCommand("resetstats")
	bot:UnregisterCommand("savestats")
	bot:UnregisterCommand("serverstats")
end

function Module:LoadStats(filename)
	filename = filename or "stats.json"

	local saveFile = io.open(filename, "r")
	if (not saveFile) then
		print("Failed to open " .. filename)
		return
	end

	local content = saveFile:read("*a")
	if (not content) then
		print("Failed to read stats from file: " .. tostring(err))
		return
	end
	saveFile:close()

	local success, contentOrErr = pcall(json.decode, content)
	if (not success) then
		print("Failed to decode stats json: " .. tostring(contentOrErr))
		return
	end

	return contentOrErr
end

function Module:PrintStats(channel, stats)	
	local guild = channel.guild
	
	local fields = {}
	table.insert(fields, {
		name = "Member count", value = stats.MemberCount or "<Not logged>", inline = true
	})

	table.insert(fields, {
		name = "New members", value = stats.MemberJoined, inline = true
	})

	table.insert(fields, {
		name = "Lost members", value = stats.MemberLeft, inline = true
	})

	table.insert(fields, {
		name = "Messages posted", value = stats.MessageCount, inline = true
	})

	table.insert(fields, {
		name = "Active members", value = table.count(stats.Users), inline = true
	})

	table.insert(fields, {
		name = "Active channels", value = table.count(stats.Channels), inline = true
	})

	table.insert(fields, {
		name = "Total reactions added", value = stats.ReactionAdded or 0, inline = true
	})

	local mostAddedReaction = {}
	for reactionName, reactionStats in pairs(stats.Reactions or {}) do
		table.insert(mostAddedReaction, { name = reactionName, count = reactionStats.ReactionCount })
	end
	table.sort(mostAddedReaction, function (a, b) return a.count > b.count end)

	local addedReactionList = ""
	for i = 1, 5 do
		if (i > #mostAddedReaction) then
			break
		end

		local reactionData = mostAddedReaction[i]
		addedReactionList = addedReactionList .. string.format("%s %s\n", reactionData.count, bot:GetEmojiData(guild, reactionData.name).MentionString)
	end

	table.insert(fields, {
		name = "Most added reactions", value = #addedReactionList > 0 and addedReactionList or "<None>", inline = true
	})

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
		activeChannelList = activeChannelList .. string.format("%s messages in %s\n", channelData.messageCount, channel and channel.mentionString or "<deleted channel>")
	end

	table.insert(fields, {
		name = "Most active channels", value = #activeChannelList > 0 and activeChannelList or "<None>", inline = true
	})


	local resetTime = os.difftime(os.time(), stats.Date or os.time())
	local resetStr
	if (resetTime > 3600) then
		local hourCount = math.floor(resetTime / 3600)
		resetStr = string.format("%s hour%s", hourCount, hourCount > 1 and "s" or "")
	elseif (resetTime > 60) then
		local minuteCount = math.floor(resetTime / 60)
		resetStr = string.format("%s minute%s", minuteCount, minuteCount > 1 and "s" or "")
	else
		local secondCount = math.floor(resetTime)
		resetStr = string.format("%s second%s", secondCount, secondCount > 1 and "s" or "")
	end

	local title = string.format("Server stats - %s, started %s ago", os.date("%d-%m-%Y", stats.Date), resetStr)
	
	channel:send({
		embed = {
			title = title,
			fields = fields,
			timestamp = discordia.Date():toISO('T', 'Z')
		}
	})
end

function Module:ResetStats()
	local guild = client:getGuild(config.Guild)

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

function Module:SaveStats(filename)
	filename = filename or "stats.json"

	local dirname = path.dirname(filename)
	if (dirname ~= "." and not fs.mkdirp(dirname)) then
		print("Failed to create directory " .. dirname)
		return
	end

	local outputFile = io.open(filename, "w+")
	if (not outputFile) then
		print("Failed to open " .. filename)
		return
	end

	local success, err = outputFile:write(json.encode(self.Stats))
	if (not success) then
		print("Failed to write stats to file: " .. tostring(err))
		return
	end

	outputFile:close()
end

function Module:GetChannelStats(channelId)
	local channelStats = self.Stats.Channels[channelId]
	if (not channelStats) then
		channelStats = {}
		channelStats.MessageCount = 0
		channelStats.ReactionCount = 0
		self.Stats.Channels[channelId] = channelStats
	end

	return channelStats
end

function Module:GetReactionStats(reactionName)
	local reactions = self.Stats.Reactions
	if (not reactions) then
		reactions = {}
		self.Stats.Reactions = reactions
	end

	local reactionStats = reactions[reactionName]
	if (not reactionStats) then
		reactionStats = {}
		reactionStats.ReactionCount = 0
		self.Stats.Reactions[reactionName] = reactionStats
	end

	return reactionStats
end

function Module:GetUserStats(userId)
	local userStats = self.Stats.Users[userId]
	if (not userStats) then
		userStats = {}
		userStats.MessageCount = 0
		userStats.ReactionCount = 0
		self.Stats.Users[userId] = userStats
	end

	return userStats
end

function Module:OnMessageCreate(message)
	if (message.author.bot) then
		return
	end

	self.Stats.MessageCount = self.Stats.MessageCount + 1
	
	-- Channels
	local channelStats = self:GetChannelStats(message.channel.id)
	channelStats.MessageCount = channelStats.MessageCount + 1
	
	-- Members
	local userStats = self:GetUserStats(message.author.id)
	userStats.MessageCount = userStats.MessageCount + 1
end

function Module:OnMemberJoin(member)
	if (member.user.bot) then
		return
	end

	self.Stats.MemberJoined = self.Stats.MemberJoined + 1
	self.Stats.MemberCount = self.Stats.MemberCount + 1
end

function Module:OnMemberLeave(member)
	if (member.user.bot) then
		return
	end

	self.Stats.MemberLeft = self.Stats.MemberLeft + 1
	self.Stats.MemberCount = self.Stats.MemberCount - 1
end

function Module:OnReactionAdd(reaction, userId)
	if (reaction.message.channel.type ~= enums.channelType.text) then
		return
	end

	self.Stats.ReactionAdded = (self.Stats.ReactionAdded or 0) + 1

	local channelStats = self:GetChannelStats(reaction.message.channel.id)
	channelStats.ReactionCount = (channelStats.ReactionCount or 0) + 1

	local reactionStats = self:GetReactionStats(reaction.emojiName)
	reactionStats.ReactionCount = (reactionStats.ReactionCount or 0) + 1

	local userStats = self:GetUserStats(userId)
	userStats.ReactionCount = (userStats.ReactionCount or 0) + 1
end

function Module:OnReactionAddUncached(channel, messageId, reactionIdorName, userId)
	if (channel.type ~= enums.channelType.text) then
		return
	end

	self.Stats.ReactionAdded = (self.Stats.ReactionAdded or 0) + 1

	local channelStats = self:GetChannelStats(channel.id)
	channelStats.ReactionCount = (channelStats.ReactionCount or 0) + 1

	local reactionStats = self:GetReactionStats(bot:GetEmojiData(channel.guild, reactionIdorName).Name)
	reactionStats.ReactionCount = (reactionStats.ReactionCount or 0) + 1

	local userStats = self:GetUserStats(userId)
	userStats.ReactionCount = (userStats.ReactionCount or 0) + 1
end

function Module:OnReactionRemove(reaction, userId)
	if (reaction.message.channel.type ~= enums.channelType.text) then
		return
	end

	self.Stats.ReactionRemoved = (self.Stats.ReactionRemoved or 0) + 1

	local reactionStats = self:GetReactionStats(reaction.emojiName)
	reactionStats.ReactionCount = math.max((reactionStats.ReactionCount or 0) - 1, 0)
end

function Module:OnReactionRemoveUncached(channel, messageId, reactionIdorName, userId)
	if (channel.type ~= enums.channelType.text) then
		return
	end

	self.Stats.ReactionRemoved = (self.Stats.ReactionRemoved or 0) + 1

	local reactionStats = self:GetReactionStats(bot:GetEmojiData(channel.guild, reactionIdorName).Name)
	reactionStats.ReactionCount = math.max((reactionStats.ReactionCount or 0) - 1, 0)
end
