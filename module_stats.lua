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

local dayPerMonth = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
local function DayPerMonth(month, year)
	if (month == 2) then
		if ((year % 4 == 0 and year % 100 ~= 0) or year % 400 == 0) then
			return 29
		else
			return 28
		end
	else
		return dayPerMonth[month]
	end
end

local function numcmp(left, right)
	if (left == right) then
		return 0
	elseif (left < right) then
		return -1
	else
		return 1
	end
end

local function CompareDates(day1, month1, year1, day2, month2, year2)
	if (year1 == year2) then
		if (month1 == month2) then
			return numcmp(day1, day2)
		else
			return numcmp(month1, month2)
		end
	else
		return numcmp(year1, year2)
	end
end

local AccumulateArray
AccumulateArray = function(dstArray, srcArray)
	for k,v in pairs(srcArray) do
		if (type(v) == "number") then
			local refValue = dstArray[k]
			if (refValue == nil) then
				dstArray[k] = v
			else
				assert(type(refValue) == "number")
				dstArray[k] = refValue + v
			end
		else
			assert(type(v) == "table")
			local refValue = dstArray[k]
			if (refValue == nil) then
				refValue = {}
				dstArray[k] = refValue
			end

			AccumulateArray(refValue, v)
		end
	end
end

local function AccumulateStats(stats, dateStats)
	stats.MemberLeft = stats.MemberLeft + dateStats.MemberLeft
	stats.MemberJoined = stats.MemberJoined + dateStats.MemberJoined
	stats.MessageCount = stats.MessageCount + dateStats.MessageCount
	stats.ReactionAdded = stats.ReactionAdded + dateStats.ReactionAdded
	stats.ReactionRemoved = stats.ReactionRemoved + dateStats.ReactionRemoved
	stats.MemberCount = dateStats.MemberCount
	table.insert(stats.MemberCountHistory, dateStats.MemberCount)

	AccumulateArray(stats.Channels, dateStats.Channels)
	AccumulateArray(stats.Reactions, dateStats.Reactions)
	AccumulateArray(stats.Users, dateStats.Users)
end

local function AccumulateUserStatsPerMonth(stats, dateStats, userId)
	if(dateStats.Users and dateStats.Users[userId]) then
		stats[os.date("%Y-%m", dateStats.Date)] = dateStats.Users[userId].MessageCount
	end
end

function Module:GetConfigTable()
	return {
		{
			Name = "LogChannel",
			Description = "Channel where stats will be posted each day",
			Type = bot.ConfigType.Channel,
			Optional = true
		},
		{
			Name = "ShowActiveUsers",
			Description = "Allows most active users stats to be shown",
			Type = bot.ConfigType.Boolean,
			Default = false
		}
	}
end

function Module:OnLoaded()
	self.Clock = discordia.Clock()
	self.Clock:on("day", function ()
		self:ForEachGuild(function (guildId, config, data, persistentData)
			local guild = client:getGuild(guildId)
			if (guild) then
				local stats = persistentData.Stats
				self:SaveStats(self:GetStatsFilename(guild, stats.Date), stats)
				persistentData.Stats = self:BuildStats(guild)

				if (config.LogChannel) then
					local channel = guild:getChannel(config.LogChannel)
					if (channel) then
						coroutine.wrap(function() self:PrintStats(channel, stats) end)()
					end
				end
			end
		end)
	end)

	self:RegisterCommand({
		Name = "resetstats",
		Args = {},
		PrivilegeCheck = function (member) return member:hasPermission(enums.permission.administrator) end,

		Help = "Resets stats of the day",
		Func = function (commandMessage)
			local data = self:GetPersistentData(commandMessage.guild)
			data.Stats = self:BuildStats()
			commandMessage:reply("Stats reset successfully")
		end
	})

	self:RegisterCommand({
		Name = "serverstats",
		Args = {
			{Name = "date/from", Type = Bot.ConfigType.String, Optional = true},
			{Name = "to", Type = Bot.ConfigType.String, Optional = true}
		},

		Help = "Prints stats",
		Func = function (commandMessage, from, to)
			if (from and to and from ~= to) then
				local fromY, fromM, fromD = from:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
				if (not fromY) then
					commandMessage:reply("Invalid date format for `from` parameter, please write it as YYYY-MM-DD")
					return
				end

				local toY, toM, toD = to:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
				if (not toY) then
					commandMessage:reply("Invalid date format for `to` parameter, please write it as YYYY-MM-DD")
					return
				end

				if (CompareDates(fromD, fromM, fromY, toD, toM, toY) >= 0) then
					commandMessage:reply("`from` date must be earlier than `to` date")
					return
				end

				commandMessage.channel:broadcastTyping()

				-- Check available dates
				local guildStatsFolder = self:GetStatsFolder(commandMessage.guild)

				local availableStats = {}
				for file in fs.scandir(guildStatsFolder) do
					if (file.type == "file") then
						local year, month, day = file.name:match("^stats_(%d%d%d%d)-(%d%d)-(%d%d).json$")
						if (year) then
							table.insert(availableStats, { d = day, m = month, y = year })
						end
					end
				end

				local compareDateFunc = function (left, right)
					return CompareDates(left.d, left.m, left.y, right.d, right.m, right.y)
				end

				table.sort(availableStats, function (left, right) return compareDateFunc(left, right) < 0 end)

				local fromDate = { d = fromD, m = fromM, y = fromY }
				if (compareDateFunc(fromDate, availableStats[1]) < 0) then
					fromDate = availableStats[1]
				end

				local toDate = { d = toD, m = toM, y = toY }
				if (compareDateFunc(toDate, availableStats[#availableStats]) > 0) then
					toDate = availableStats[#availableStats]
				end

				local _, firstIndex = table.binsearch(availableStats, fromDate, compareDateFunc)
				local _, lastIndex = table.binsearch(availableStats, toDate, compareDateFunc)

				local accumulatedStats = self:BuildStats(commandMessage.guild)
				accumulatedStats.MemberCount = nil
				accumulatedStats.MemberCountHistory = {}

				for i = firstIndex, lastIndex do
					local v = availableStats[i]
					local fileName = string.format("%s/stats_%s-%s-%s.json", guildStatsFolder, v.y, v.m, v.d)
					local stats, err = self:LoadStats(commandMessage.guild, fileName)
					if (not stats) then
						commandMessage:reply("Failed to load some stats")
						return
					end

					AccumulateStats(accumulatedStats, stats)
				end

				self:PrintStats(commandMessage.channel, accumulatedStats, string.format("%s-%s-%s", fromDate.d, fromDate.m, fromDate.y), string.format("%s-%s-%s", toDate.d, toDate.m, toDate.y), lastIndex - firstIndex + 1)
			elseif (from) then
				if (not from:match("^%d%d%d%d%-%d%d%-%d%d$")) then
					commandMessage:reply("Invalid date format, please write it as YYYY-MM-DD")
					return
				end

				local stats = self:LoadStats(commandMessage.guild, self:GetStatsFilename(commandMessage.guild, from))
				if (not stats) then
					commandMessage:reply("We have no stats for that date")
					return
				end

				self:PrintStats(commandMessage.channel, stats)
			else
				local data = self:GetPersistentData(commandMessage.guild)
				self:PrintStats(commandMessage.channel, data.Stats)
			end
		end
	})

	return true
end

function Module:OnEnable(guild)
	local data = self:GetPersistentData(guild)
	if (not data.Stats) then
		self:LogInfo(guild, "No previous stats found, resetting...")
		data.Stats = self:BuildStats(guild)
	else
		local currentDate = os.date("%Y-%m-%d")
		local statsDate = os.date("%Y-%m-%d", data.Stats.Date)
		if (currentDate ~= statsDate) then
			self:LogInfo(guild, "Previous stats data has been found but date does not match (%s), saving and resetting", statsDate)
			self:SaveStats(self:GetStatsFilename(guild, data.Stats.Date), data.Stats)
			data.Stats = self:BuildStats(guild)
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
	return string.format("%s/stats_%s.json", self:GetStatsFolder(guild), (type(time) == "number") and os.date("%Y-%m-%d", time) or time)
end

function Module:GetStatsFolder(guild)
	return string.format("stats/guild_%s", guild.id)
end

function Module:PrintStats(channel, stats, fromDate, toDate, dayCount)
	local guild = channel.guild
	local config = self:GetConfig(guild)

	local memberCount
	local valueFunc
	if (dayCount) then
		local memberCountHistory = stats.MemberCountHistory
		if (#memberCountHistory > 0) then
			local firstMemberCount = memberCountHistory[1]
			local lastMemberCount = memberCountHistory[#memberCountHistory]
			if (lastMemberCount > firstMemberCount) then
				memberCount = string.format("%u (+ %u)", lastMemberCount, lastMemberCount - firstMemberCount)
			elseif (lastMemberCount < firstMemberCount) then
				memberCount = string.format("%u (- %u)", lastMemberCount, firstMemberCount - lastMemberCount)
			else
				memberCount = string.format("%u (=)", lastMemberCount)
			end
		end

		valueFunc = function (value, msg)
			if (value) then
				return string.format("%s (%s avg.)", value, math.floor(value / dayCount))
			else
				return msg or 0
			end
		end
	else
		valueFunc = function (value, msg)
			if (value) then
				return tostring(value)
			else
				return msg or 0
			end
		end
	end

	if (not memberCount) then
		memberCount = stats.MemberCount or "<No logs>"
	end

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
		if (not emojiData) then
			self:LogError("Most added reaction %s is not found", reactionData.name)
		end

		addedReactionList = addedReactionList .. string.format("%s %s\n", valueFunc(reactionData.count), emojiData and emojiData.MentionString or string.format("<bot error on %s>", reactionData.name))
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
		activeChannelList = activeChannelList .. string.format("%s: %s m.\n", channel and channel.mentionString or "<deleted channel>", valueFunc(channelData.messageCount))
	end

	local activeMemberList
	if (config.ShowActiveUsers) then
		local mostActiveMembers = {}
		for userId, userStats in pairs(stats.Users) do
			table.insert(mostActiveMembers, { id = userId, messageCount = userStats.MessageCount })
		end
		table.sort(mostActiveMembers, function (a, b) return a.messageCount > b.messageCount end)

		activeMemberList = ""
		for i = 1, 5 do
			if (i > #mostActiveMembers) then
				break
			end
	
			local memberData = mostActiveMembers[i]
			activeMemberList = activeMemberList .. string.format("%s: %s m.\n", "<@" .. memberData.id .. ">", valueFunc(memberData.messageCount))
		end
	end

	local fields = {
		{
			name = "Member count", value = memberCount, inline = true
		},
		{
			name = "New members", value = valueFunc(stats.MemberJoined), inline = true
		},
		{
			name = "Lost members", value = valueFunc(stats.MemberLeft), inline = true
		},
		{
			name = "Messages posted", value = valueFunc(stats.MessageCount), inline = true
		},
		{
			name = "Active members", value = table.count(stats.Users), inline = true
		},
		{
			name = "Active channels", value = table.count(stats.Channels), inline = true
		},
		{
			name = "Total reactions added", value = valueFunc(stats.ReactionAdded), inline = true
		},
		{
			name = "Most added reactions", value = #addedReactionList > 0 and addedReactionList or "<None>", inline = true
		},
		{
			name = "Most active channels", value = #activeChannelList > 0 and activeChannelList or "<None>", inline = true
		}
	}

	if (activeMemberList) then
		table.insert(fields, 
		{
			name = "Most active members", value = #activeMemberList > 0 and activeMemberList or "<None>", inline = true
		})
	end

	local title
	if (not fromDate) then
		local resetTime = os.difftime(os.time(), stats.Date)
		title = string.format("Server stats - %s, started %s ago", os.date("%d-%m-%Y", stats.Date), util.FormatTime(resetTime, 2))
	else
		title = string.format("Server stats - from %s to %s", fromDate, toDate)
	end

	channel:send({
		embed = {
			title = title,
			fields = fields,
			timestamp = discordia.Date(stats.Date):toISO('T', 'Z')
		}
	})
end

function Module:BuildStats(guild)
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
		self:LogError("Failed to write %s: %s", filename, err)
		return
	end

	outputFile:close()
end

function Module:GetChannelStats(guild, channel)
	local channelId
	if (channel.isThread) then
		channelId = channel._parent_id
	else
		channelId = channel.id
	end

	if (type(channelId) ~= "string") then
		self:LogError("expected string as channel id, got " .. type(channelId))
		return { MessageCount = 0, ReactionCount = 0 } -- dummy temporary table
	end

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
	if (type(reactionName) ~= "string") then
		self:LogError("expected string as reaction name, got " .. type(reactionName))
		return { ReactionCount = 0 } -- dummy temporary table
	end

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
	if (type(userId) ~= "string") then
		self:LogError("expected string as user id, got " .. type(userId))
		return { MessageCount = 0, ReactionCount = 0 } -- dummy temporary table
	end

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

function Module:GetUserStatsHistory(guild, userId)
	local guildStatsFolder = self:GetStatsFolder(guild)
	local files = fs.scandir(guildStatsFolder)

	local accumulatedStats = self:BuildStats(guild)
	accumulatedStats.MemberCount = nil
	accumulatedStats.MemberCountHistory = {}

	local perTimeAccumulatedUserStats = {}

	for file in files do
		if (file.type == "file") then
			local fileName = string.format("%s/%s", guildStatsFolder, file.name);
			local stats, err = self:LoadStats(guild, fileName)
			if (not stats) then
				self:LogWarning(nil, "Failed to load stats file: %s", err)
				return {}
			end

			AccumulateStats(accumulatedStats, stats)
			AccumulateUserStatsPerMonth(perTimeAccumulatedUserStats, stats, userId)
		end
	end

	local users = accumulatedStats.Users
	local userStats = users[userId]
	if (not userStats) then
		userStats = {}
		userStats.MessageCount = 0
		userStats.ReactionCount = 0
	end

	userStats.perTimeAccumulatedUserStats = perTimeAccumulatedUserStats

	return userStats
end

function Module:OnMessageCreate(message)
	if (not bot:IsPublicChannel(message.channel)) then
		return
	end

	if (message.author.bot) then
		return
	end

	local data = self:GetPersistentData(message.guild)
	data.Stats.MessageCount = data.Stats.MessageCount + 1

	-- Channels
	local channelStats = self:GetChannelStats(message.guild, message.channel)
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
	if (not bot:IsPublicChannel(reaction.message.channel)) then
		return
	end

	local emojiData = bot:GetEmojiData(reaction.message.guild, reaction.emojiId or reaction.emojiName)
	if (not emojiData) then
		return
	end

	local data = self:GetPersistentData(reaction.message.guild)
	data.Stats.ReactionAdded = data.Stats.ReactionAdded + 1

	local channelStats = self:GetChannelStats(reaction.message.guild, reaction.message.channel)
	channelStats.ReactionCount = channelStats.ReactionCount + 1

	local reactionStats = self:GetReactionStats(reaction.message.guild, emojiData.Name)
	reactionStats.ReactionCount = reactionStats.ReactionCount + 1

	local userStats = self:GetUserStats(reaction.message.guild, userId)
	userStats.ReactionCount = userStats.ReactionCount + 1
end

function Module:OnReactionAddUncached(channel, messageId, reactionIdorName, userId)
	if (not bot:IsPublicChannel(channel)) then
		return
	end

	local emojiData = bot:GetEmojiData(channel.guild, reactionIdorName)
	if (not emojiData) then
		return
	end

	local data = self:GetPersistentData(channel.guild)
	data.Stats.ReactionAdded = data.Stats.ReactionAdded + 1

	local channelStats = self:GetChannelStats(channel.guild, channel)
	channelStats.ReactionCount = channelStats.ReactionCount + 1

	local reactionStats = self:GetReactionStats(channel.guild, emojiData.Name)
	reactionStats.ReactionCount = reactionStats.ReactionCount + 1

	local userStats = self:GetUserStats(channel.guild, userId)
	userStats.ReactionCount = userStats.ReactionCount + 1
end

function Module:OnReactionRemove(reaction, userId)
	if (not bot:IsPublicChannel(reaction.message.channel)) then
		return
	end

	local data = self:GetPersistentData(reaction.message.guild)
	data.Stats.ReactionRemoved = data.Stats.ReactionRemoved + 1

	local reactionStats = self:GetReactionStats(reaction.message.guild, reaction.emojiId or reaction.emojiName)
	reactionStats.ReactionCount = math.max(reactionStats.ReactionCount - 1, 0)
end

function Module:OnReactionRemoveUncached(channel, messageId, reactionIdorName, userId)
	if (not bot:IsPublicChannel(channel)) then
		return
	end

	local emojiData = bot:GetEmojiData(channel.guild, reactionIdorName)
	if (not emojiData) then
		return
	end

	local data = self:GetPersistentData(channel.guild)
	data.Stats.ReactionRemoved = data.Stats.ReactionRemoved + 1

	local reactionStats = self:GetReactionStats(channel.guild, emojiData.Name)
	reactionStats.ReactionCount = math.max(reactionStats.ReactionCount - 1, 0)
end
