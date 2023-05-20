-- Copyright (C) 2020 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local client = Client
local discordia = Discordia
local bot = Bot
local enums = discordia.enums
local band, bor, bnot = bit.band, bit.bor, bit.bnot

Module.Name = "raid"

local hypesquadFlags = bor(enums.userFlag.hypesquadEvents, enums.userFlag.houseBravery, enums.userFlag.houseBrilliance, enums.userFlag.houseBalance)

local rules = {
	nitro = {
		Description = "checks if the user account has nitro",
		Parameters = "<bool>",
		Type = Bot.ConfigType.Boolean,
		Check = function (member)
			return member.premiumType == enums.premiumType.nitroClassic or
			       member.premiumType == enums.premiumType.nitro
		end
	},
	hypesquad = {
		Description = "checks if the user is registered for the hypesquad",
		Parameters = "<bool>",
		Type = Bot.ConfigType.Boolean,
		Check = function (member)
			local flags = member.user.publicFlags or 0
			return band(flags, hypesquadFlags) ~= 0
		end
	},
	discordEmployee = {
		Description = "checks if the user is a Discord employee",
		Parameters = "<bool>",
		Type = Bot.ConfigType.Boolean,
		Check = function (member)
			local flags = member.user.publicFlags or 0
			return band(flags, enums.userFlag.discordEmployee) ~= 0
		end
	},
	discordPartner = {
		Description = "checks if the user is a Discord partner",
		Parameters = "<bool>",
		Type = Bot.ConfigType.Boolean,
		Check = function (member)
			local flags = member.user.publicFlags or 0
			return band(flags, enums.userFlag.discordPartner) ~= 0
		end
	},
	earlySupporter = {
		Description = "checks if the user is a Discord early supporter",
		Parameters = "<bool>",
		Type = Bot.ConfigType.Boolean,
		Check = function (member)
			local flags = member.user.publicFlags or 0
			return band(flags, enums.userFlag.earlySupporter) ~= 0
		end
	},
	verifiedBotDeveloper = {
		Description = "checks if the user is a verified Discord developer",
		Parameters = "<bool>",
		Type = Bot.ConfigType.Boolean,
		Check = function (member)
			local flags = member.user.publicFlags or 0
			return band(flags, enums.userFlag.verifiedBotDeveloper) ~= 0
		end
	},
	createdBetween = {
		Description = "checks if the user was created in a date range",
		Parameters = "<ISO 8601 from date> => <ISO 8601 to date>",
		Parse = function (param)
			local from, to = param:match("^(.+)%s*=>%s*(.+)$")
			if (not from) then
				return nil, "please set two dates in ISO 8601 separated by a => (from => to)"
			end

			local fromTime = discordia.Date.parseISO(from)
			local toTime = discordia.Date.parseISO(to)
			return { from = fromTime, to = toTime }
		end,
		ToString = function (config)
			return discordia.Date(config.from):toISO() .. " => " .. discordia.Date(config.to):toISO()
		end,
		Check = function (member, config)
			local user = member.user
			local creationDate = user:getDate():toSeconds()

			return creationDate >= config.from and creationDate <= config.to
		end
	},
	olderThan = {
		Description = "checks if the user was created before a specific date",
		Parameters = "<ISO 8601 date>",
		Parse = function (param)
			local time = discordia.Date.parseISO(param)
			if (not time) then
				return nil, "invalid date, please write it in ISO 8601 format"
			end

			return time
		end,
		ToString = function (config)
			return discordia.Date(config):toISO()
		end,
		Check = function (member, config)
			local user = member.user
			local creationDate = user:getDate():toSeconds()

			return creationDate <= config
		end
	},
	newerThan = {
		Description = "checks if the user was created after a specific date",
		Parameters = "<ISO 8601 date>",
		Parse = function (param)
			local time = discordia.Date.parseISO(param)
			if (not time) then
				return nil, "invalid date, please write it in ISO 8601 format"
			end

			return time
		end,
		ToString = function (config)
			return discordia.Date(config):toISO()
		end,
		Check = function (member, config)
			local user = member.user
			local creationDate = user:getDate():toSeconds()

			return creationDate >= config
		end
	},
	nicknameContains = {
		Description = "checks if the user nickname contains something (case-insensitive)",
		Parameters = "<nickname>",
		Parse = function (param)
			if (not param or #param == 0) then
				return nil, "invalid nickname"
			end

			if (param:sub(1, 2) == "p:") then
				return {p = true, str = param:sub(3)}
			else
				return {p = false, str = param}
			end
		end,
		ToString = function (config)
			return (config.p and "pattern: " or "") .. config.str
		end,
		Check = function (member, config)
			local name = member.user.name:lower()
			if (config.p) then
				return name:match(config.str) and true or false
			else
				return name:find(config.str, true) and true or false
			end
		end
	}
}

for ruleName, rule in pairs(rules) do
	if (rule.Type) then
		rule.Parse = Bot.ConfigTypeParameter[rule.Type]
		rule.ToString = Bot.ConfigTypeToString[rule.Type]
	end

	assert(rule.Parse, "missing Parse for rule " .. ruleName)
	assert(rule.ToString, "missing ToString for rule " .. ruleName)
end

local effects = {
	authorize = "Allow the user to join the server if it's locked.",
	ban = "Bans the user on join.",
	kick = "Prevents the user from joining (even if the server isn't locked)."
}


function Module:GetConfigTable()
	return {
		{
			Array = true,
			Name = "LockAuthorizedRoles",
			Description = "Roles allowed to lock and unlock server",
			Type = bot.ConfigType.Role,
			Default = {}
		},
		{
			Name = "AlertChannel",
			Description = "Channel where a message will be posted (if set) in case someone gets muted for spamming",
			Type = bot.ConfigType.Channel,
			Optional = true
		},
		{
			Name = "LockAlertChannel",
			Description = "Channel where a message will be posted (if set) in case of server locking",
			Type = bot.ConfigType.Channel,
			Optional = true
		},
		{
			Name = "LockServerVerificationLevel",
			Description = "If server verification level is lower than this, it will be raised for the lock duration",
			Type = bot.ConfigType.Integer,
			Default = enums.verificationLevel.high
		},
		{
			Name = "SendMessageThreshold",
			Description = "If a new member sends a message before this duration, they will be auto-banned (0 to disable)",
			Type = bot.ConfigType.Duration,
			Default = 3
		},
		{
			Name = "DefaultLockDuration",
			Description = "For how many time should the server be locked in case of join spam",
			Type = bot.ConfigType.Duration,
			Default = 10 * 60
		},
		{
			Name = "JoinCountThreshold",
			Description = "How many members are allowed to join the server in the join window before triggering an automatic lock",
			Type = bot.ConfigType.Integer,
			Default = 10
		},
		{
			Name = "JoinTimeThreshold",
			Description = "For how many time should the join window be open",
			Type = bot.ConfigType.Integer,
			Default = 5
		},
		{
			Name = "SpamCountThreshold",
			Description = "How much \"spam score\" is allowed in the spam window before the bot bans/mute the member (1 message = 1 score, but some keywords, links, pings and such increase it)",
			Type = bot.ConfigType.Integer,
			Default = 7
		},
		{
			Name = "SpamTimeThreshold",
			Description = "For how many time should the spam window be open",
			Type = bot.ConfigType.Integer,
			Default = 10
		},
		{
			Name = "SpamMute",
			Description = "Should the bot mute a member exceeding the spam window instead of banning them? (require the mute module)",
			Type = bot.ConfigType.Boolean,
			Default = true
		},
		{
			Array = true,
			Name = "SpamImmunity",
			Description = "Roles that will never be auto-banned/muted for spam",
			Type = bot.ConfigType.Role,
			Default = {}
		},
		{
			Name = "JoinWhitelist",
			Description = "List of members allowed to join the server while it's locked",
			Type = bot.ConfigType.User,
			Array = true,
			Default = {}
		},
		{
			Name = "RuleAlertChannel",
			Description = "Channel where a message will be posted (if set) when a rule applies",
			Type = bot.ConfigType.Channel,
			Optional = true
		},
	}
end

function Module:CheckLockPermissions(member)
	local config = self:GetConfig(member.guild)
	if (util.MemberHasAnyRole(member, config.LockAuthorizedRoles)) then
		return true
	end

	if (member:hasPermission(enums.permission.administrator)) then
		return true
	end

	return false
end

function Module:CheckRulePermissions(member)
	return member:hasPermission(enums.permission.administrator)
end

function Module:OnLoaded()
	self:RegisterCommand({
		Name = "lockserver",
		Args = {
			{Name = "duration", Type = Bot.ConfigType.Duration, Optional = true},
			{Name = "reason", Type = Bot.ConfigType.String, Optional = true},
		},
		PrivilegeCheck = function (member) return self:CheckLockPermissions(member) end,

		Help = function (guild) return bot:Format(guild, "RAID_LOCKSERVER_HELP") end,
		Silent = true,
		Func = function (commandMessage, duration, reason)
			local guild = commandMessage.guild
			local config = self:GetConfig(guild)
			local lockedBy = commandMessage.member

			if (self:IsServerLocked(guild)) then
				commandMessage:reply(bot:Format(guild, "RAID_LOCKSERVER_ALREADY_LOCKED"))
				return
			end

			-- Duration
			if (not duration) then
				duration = config.DefaultLockDuration
			end

			-- Reason
			local reasonStart = bot:Format(guild, "RAID_LOCKSERVER_LOCKED_BY", lockedBy.mentionString)
			if (reason) then
				reason = reasonStart .. ": " .. reason
			else
				reason = reasonStart
			end

			self:LockServer(guild, duration, reason)
		end
	})

	self:RegisterCommand({
		Name = "unlockserver",
		Args = {
			{Name = "reason", Type = Bot.ConfigType.String, Optional = true},
		},
		PrivilegeCheck = function (member) return self:CheckLockPermissions(member) end,

		Help = function (guild) return bot:Format(guild, "RAID_UNLOCKSERVER_HELP") end,
		Silent = true,
		Func = function (commandMessage, reason)
			local guild = commandMessage.guild
			local lockedBy = commandMessage.member

			if (not self:IsServerLocked(guild)) then
				commandMessage:reply(bot:Format(guild, "RAID_UNLOCKSERVER_NOT_LOCKED"))
				return
			end

			-- Reason
			local reasonStart = bot:Format(guild, "RAID_UNLOCKSERVER_LOCKED_BY", lockedBy.mentionString)
			if (reason) then
				reason = reasonStart .. ": " .. reason
			else
				reason = reasonStart
			end

			self:UnlockServer(guild, reason)
		end
	})

	self:RegisterCommand({
		Name = "rulehelp",
		Args = {},
		PrivilegeCheck = function (member) return self:CheckRulePermissions(member) end,

		Help = function (guild) return bot:Format(guild, "RAID_RULEHELP_HELP") end,
		Silent = true,
		Func = function (commandMessage)
			local guild = commandMessage.guild
			local fields = {}
			for fieldName, ruleData in pairs(rules) do
				table.insert(fields, {
					name = fieldName,
					value = bot:Format(guild, "RAID_RULEHELP_FIELDS_VALUE", ruleData.Description, ruleData.Parameters)
				})
			end
			table.sort(fields, function (a, b)
				return a.name < b.name
			end)

			local effectList = {}
			for effect, desc in pairs(effects) do
				table.insert(effectList, { name = effect, desc = desc })
			end
			table.sort(effectList, function (a, b) return a.name < b.name end)

			local effectDescription = {}
			for _, effectList in ipairs(effectList) do
				table.insert(effectDescription, string.format(" - **%s**: %s", effectList.name, effectList.desc))
			end
			effectDescription = table.concat(effectDescription, "\n")

			commandMessage:reply({
				embed = {
					title = bot:Format(guild, "RAID_RULEHELP_TITLE"),
					description = bot:Format(guild, "RAID_RULEHELP_DESCRIPTION", effectDescription),
					fields = fields
				}
			})
		end
	})

	self:RegisterCommand({
		Name = "addrule",
		Args = {
			{Name = "effect", Type = Bot.ConfigType.String},
			{Name = "rule", Type = Bot.ConfigType.String},
			{Name = "param", Type = Bot.ConfigType.String},
		},
		PrivilegeCheck = function (member) return self:CheckRulePermissions(member) end,

		Help = function (guild) return bot:Format(guild, "RAID_ADDRULE_HELP") end,
		Func = function (commandMessage, effect, rule, param)
			local guild = commandMessage.guild
			local persistentData = self:GetPersistentData(guild)

			if (not effects[effect]) then
				local effectList = {}
				for effect, _ in ipairs(effects) do
					table.insert(effectList, effect)
				end
				table.sort(effectList)

				commandMessage:reply(bot:Format(guild, "RAID_ADDRULE_INVALID_EFFECT", table.concat(effectList, ", ")))
				return
			end

			local ruleData = rules[rule]
			if (not ruleData) then
				commandMessage:reply(bot:Format(guild, "RAID_ADDRULE_INVALID_RULE"))
				return
			end

			local ruleConfig, err = ruleData.Parse(param)
			if (not ruleConfig) then
				commandMessage:reply(bot:Format(guild, "RAID_ADDRULE_INVALID_RULE_PARAMETERS", err))
				return
			end

			table.insert(persistentData.rules, {
				effect = effect,
				rule = rule,
				ruleConfig = ruleConfig
			})
			self:SavePersistentData(guild)

			commandMessage:reply(bot:Format(guild, "RAID_ADDRULE_ADDED", #persistentData.rules))
		end
	})

	self:RegisterCommand({
		Name = "clearrules",
		Args = {},
		PrivilegeCheck = function (member) return self:CheckRulePermissions(member) end,

		Help = function (guild) return bot:Format(guild, "RAID_CLEARRULES_HELP") end,
		Func = function (commandMessage)
			local guild = commandMessage.guild
			local persistentData = self:GetPersistentData(guild)
			persistentData.rules = {}
			self:SavePersistentData(guild)

			commandMessage:reply(bot:Format(guild, "RAID_CLEARRULES_DONE"))
		end
	})

	self:RegisterCommand({
		Name = "delrule",
		Args = {
			{Name = "ruleIndex", Type = Bot.ConfigType.Number},
		},
		PrivilegeCheck = function (member) return self:CheckRulePermissions(member) end,

		Help = function (guild) return bot:Format(guild, "RAID_DELRULE_HELP") end,
		Func = function (commandMessage, ruleIndex)
			local guild = commandMessage.guild
			local persistentData = self:GetPersistentData(guild)
			if (ruleIndex < 1 or ruleIndex > #persistentData.rules) then
				commandMessage:reply(bot:Format(guild, "RAID_DELRULE_OUTOFRANGE"))
				return
			end
			table.remove(persistentData.rules, ruleIndex)

			self:SavePersistentData(guild)

			commandMessage:reply(bot:Format(guild, "RAID_DELRULE_DONE", ruleIndex))
		end
	})

	self:RegisterCommand({
		Name = "listrules",
		Args = {},
		PrivilegeCheck = function (member) return self:CheckRulePermissions(member) end,

		Help = function (guild) return bot:Format(guild, "RAID_LISTRULES_HELP") end,
		Func = function (commandMessage, ruleIndex)
			local guild = commandMessage.guild
			local persistentData = self:GetPersistentData(guild)

			local fields = {}
			for i, ruleData in pairs(persistentData.rules) do
				local configStr = rules[ruleData.rule].ToString(ruleData.ruleConfig)

				table.insert(fields, {
					name = bot:Format(guild, "RAID_LISTRULES_RULE_TITLE", i),
					value = bot:Format(guild, "RAID_LISTRULES_RULE_DETAIL", ruleData.rule, configStr, ruleData.effect)
				})
			end

			commandMessage:reply({
				embed = {
					title = bot:Format(guild, "RAID_LISTRULES_TITLE"),
					fields = fields
				}
			})
		end
	})

	return true
end

function Module:OnEnable(guild)
	local data = self:GetData(guild)
	local persistentData = self:GetPersistentData(guild)
	persistentData.lockedUntil = persistentData.lockedUntil or 0
	persistentData.rules = persistentData.rules or {}

	local now = os.time()
	if (persistentData.lockedUntil > now) then
		self:StartLockTimer(guild, persistentData.lockedUntil)
		data.locked = true
	else
		data.locked = false
	end

	data.joinChain = {}
	data.spamChain = {}

	return true
end

function Module:OnDisable(guild)
	local data = self:GetData(guild)

	if (data.lockTimer) then
		data.lockTimer:Stop()
		data.lockTimer = nil
	end

	local data = self:GetData(guild)
	data.joinChain = {}

	return true
end

function Module:AutoLockServer(guild, reason)
	local config = self:GetConfig(guild)
	local duration = config.DefaultLockDuration

	self:LockServer(guild, duration, reason)
end

function Module:StartLockTimer(guild, unlockTimestamp)
	local data = self:GetData(guild)

	if (unlockTimestamp < math.huge) then
		local guildId = guild.id
		data.lockTimer = bot:ScheduleTimer(unlockTimestamp, function ()
			local guild = client:getGuild(guildId)
			if (guild) then
				local persistentData = self:GetPersistentData(guild)
				if (os.time() >= persistentData.lockedUntil) then
					self:UnlockServer(guild, bot:Format(guild, "RAID_LOCK_EXPIRATION"))
				end
			end
		end)
	else
		data.lockTimer = nil
	end
end

function Module:LockServer(guild, duration, reason)
	local config = self:GetConfig(guild)
	local data = self:GetData(guild)
	local persistentData = self:GetPersistentData(guild)

	data.locked = true
	if (duration > 0) then
		persistentData.lockedUntil = os.time() + duration
	else
		persistentData.lockedUntil = math.huge
	end

	local desiredVerificationLevel = math.clamp(config.LockServerVerificationLevel, enums.verificationLevel.none, enums.verificationLevel.veryHigh)

	local currentVerificationLevel = guild.verificationLevel
	persistentData.previousVerificationLevel = nil
	if (desiredVerificationLevel > currentVerificationLevel) then
		local success, err = guild:setVerificationLevel(desiredVerificationLevel)
		if (success) then
			persistentData.previousVerificationLevel = currentVerificationLevel
		else
			self:LogWarning(guild, "Failed to raise guild verification level: %s", err)
		end
	end

	self:StartLockTimer(guild, persistentData.lockedUntil)

	if (config.LockAlertChannel) then
		local durationStr = duration > 0 and util.DiscordRelativeTime(duration) or ""

		local alertChannel = guild:getChannel(config.LockAlertChannel)
		if (alertChannel) then
			alertChannel:send({
				embed = {
					color = 16711680,
					description = bot:Format(guild, "RAID_ALERT_SERVER_LOCKED_UNITL", durationStr, reason),
					timestamp = discordia.Date():toISO('T', 'Z')
				}
			})
		end
	end
end

function Module:IsServerLocked(guild)
	local data = self:GetData(guild)
	return data.locked
end

function Module:UnlockServer(guild, reason)
	local config = self:GetConfig(guild)
	local data = self:GetData(guild)
	local persistentData = self:GetPersistentData(guild)

	if (data.locked) then
		data.locked = false

		if (persistentData.previousVerificationLevel) then
			local success, err = guild:setVerificationLevel(persistentData.previousVerificationLevel)
			if (not success) then
				self:LogWarning(guild, "Failed to reset guild verification level: %s", err)
			end
		end

		if (config.LockAlertChannel) then
			local alertChannel = guild:getChannel(config.LockAlertChannel)
			if (alertChannel) then
				alertChannel:send({
					embed = {
						color = 65280,
						description = bot:Format(guild, "RAID_ALERT_SERVER_UNLOCKED", reason),
						timestamp = discordia.Date():toISO('T', 'Z')
					}
				})
			end
		end
	end
end

function Module:HandleRules(member)
	local guild = member.guild
	local config = self:GetConfig(guild)

	local whitelist = table.search(config.JoinWhitelist, member.id)
	if (whitelist) then
		return true, bot:Format(guild, "RAID_HANDLERULE_WHITELIST", member.mentionString)
	end

	local persistentData = self:GetPersistentData(guild)
	for i, ruleData in ipairs(persistentData.rules) do
		if (rules[ruleData.rule].Check(member, ruleData.ruleConfig)) then
			local ruleStr = bot:Format(guild, "RAID_HANDLERULE_RULE", i, ruleData.rule, rules[ruleData.rule].ToString(ruleData.ruleConfig))

			if (ruleData.effect == "authorize") then
				return true, bot:Format(guild, "RAID_HANDLERULE_AUTHORIZE", member.mentionString, ruleStr)
			elseif (ruleData.effect == "ban") then
				member:ban(bot:Format(guild, "RAID_HANDLERULE_BAN_MSG", ruleStr), 0)
				return false, bot:Format(guild, "RAID_HANDLERULE_BAN_LOG", member.mentionString, ruleStr)
			elseif (ruleData.effect == "kick") then
				member:kick(bot:Format(guild, "RAID_HANDLERULE_KICK_MSG", ruleStr))
				return false, bot:Format(guild, "RAID_HANDLERULE_KICK_LOG", member.mentionString, ruleStr)
			end
		end
	end
end

function Module:OnMemberJoin(member)
	local guild = member.guild
	local config = self:GetConfig(guild)
	local data = self:GetData(guild)

	local allowed, msg = self:HandleRules(member)
	if (allowed) then
		if (msg and data.locked) then
			local ruleAlertChannel = guild:getChannel(config.RuleAlertChannel)
			if (ruleAlertChannel) then
				ruleAlertChannel:send(msg)
			end
		end

		return -- no more check
	elseif (allowed == false) then
		if (msg) then
			local ruleAlertChannel = guild:getChannel(config.RuleAlertChannel)
			if (ruleAlertChannel) then
				ruleAlertChannel:send(msg)
			end
		end

		return
	end

	if (data.locked) then
		member:kick(bot:Format(guild, "RAID_AUTOKICK_REASON"))
	else
		local now = os.time()

		local joinCountThreshold = config.JoinCountThreshold
		local timeThreshold = config.JoinTimeThreshold

		while (#data.joinChain > 0 and (now - data.joinChain[1].at > timeThreshold)) do
			table.remove(data.joinChain, 1)
		end

		table.insert(data.joinChain, {
			at = now,
			memberId = member.id
		})

		if (#data.joinChain > joinCountThreshold) then
			self:AutoLockServer(guild, bot:Format(guild, "RAID_AUTOLOCK_REASON"))

			local membersToKick = {}
			for _, joinData in pairs(data.joinChain) do
				table.insert(membersToKick, joinData.memberId)
			end

			for _, memberId in pairs(membersToKick) do
				local member = guild:getMember(memberId)
				if (member) then
					member:kick(bot:Format(guild, "RAID_AUTOKICK_REASON"))
				end
			end
		end
	end
end

-- Thanks to DrLazor for his help with this function
local spamWords = {"100k", "$100k", "crypto", "currency", "cs:go", "discord", "earn", "exchange", "free", "market", "nitro", "onlyfans", "subscription", "steam", "trading"}
local spamHints = {"3 month", "3 months", "airdrop", "away", "bitcoin", "gift", "hot", "pay", "sex", "web3", "whatsapp" }

local discordDomains = {
	["discord.com"] = true,
	["discord.media"] = true,
	["discordapp.com"] = true,
	["cdn.discordapp.com"] = true,
	["discordapp.net"] = true,
	["media.discordapp.net"] = true,
	-- public test build
	["ptb.discord.com"] = true,
	["ptb.discordapp.com"] = true,
	-- canary
	["canary.discord.com"] = true,
	["canary.discordapp.com"] = true,
}

function Module:ComputeMessageSpamScore(content)
	local score = 1 -- base score

	-- +1 for each spamword
	for _, spamWord in ipairs(spamWords) do
		if content:find(spamWord) then
			score = score + 1
		end
	end

	-- +1 if at least one spam hint if found
	for _, spamHint in ipairs(spamHints) do
		if content:find(spamHint) then
			score = score + 1
			break
		end
	end

	-- add 1 to score for every unique member ping
	local uniquePings = {}
	for ping in content:gmatch("<@!?(%d+)>") do
		if not uniquePings[ping] then
			score = score + 1
			uniquePings[ping] = true
		end
	end

	-- double score for messages containing pings (@everyone/@here or @role)
	if content:find("@everyone") or content:find("@here") or content:match("<@&%d+>") then
		score = score * 2
	end

	-- double score for messages containing links
	local hasLinks = false
	for link in content:gmatch("https?://([%w%.%%_/]+)") do
		-- ignore discord links
		local domain, guildId, channelId, messageId = link:match("https?://([%w%.]+)/channels/(%d+)/(%d+)/(%d+)(>?)")
		if (not domain or not discordDomains[domain]) then
			hasLinks = true
			break
		end
	end

	if hasLinks then
		score = score * 2
	end

	return score
end

function Module:OnMessageCreate(message)
	if (not bot:IsPublicChannel(message.channel)) then
		return
	end

	if (message.author.bot) then
		return
	end

	local guild = message.guild
	local member = message.member
	local data = self:GetData(guild)

	local config = self:GetConfig(guild)

	-- Check if message happens right after joining
	if (message.type ~= enums.messageType.memberJoin) then
		local duration = discordia.Date() - discordia.Date.fromISO(member.joinedAt)
		if (duration:toSeconds() < config.SendMessageThreshold) then
			local success, err = member:ban(bot:Format("RAID_AUTOBAN_BOT_REASON"), 1)
			if (not success) then
				self:LogWarning(guild, "Failed to autoban potential bot %s (%s)", member.tag, err)
			end

			return
		end
	end

	-- Check immunity
	if (util.MemberHasAnyRole(member, config.SpamImmunity)) then
		return
	end

	-- Remember previous messages and try to identify spam
	local spamChain = data.spamChain[member.id]
	if (not spamChain) then
		spamChain = {}
		data.spamChain[member.id] = spamChain
	end

	local now = os.time()
	local countThreshold = config.SpamCountThreshold
	local timeThreshold = config.SpamTimeThreshold

	-- Remove messages outside spam window
	while (#spamChain > 0 and (now - spamChain[1].at > timeThreshold)) do
		table.remove(spamChain, 1)
	end

	-- Compute message score and remember it
	local lowerContent = string.RemoveNonLatinChars(message.content):lower()
	local score = self:ComputeMessageSpamScore(lowerContent)

	table.insert(spamChain, {
		at = now,
		channelId = message.channel.id,
		content = lowerContent,
		realContent = message.content,
		messageId = message.id,
		score = score
	})

	local lastChannel
	local seenContent = {}
	local totalScore = 0
	for _, spam in ipairs(spamChain) do
		-- Increase score everytime a channel switch occurs
		if lastChannel and lastChannel ~= spam.channelId then
			totalScore = totalScore + 1
			lastChannel = spam.channelId
		end

		-- Increase score every time this content appears in the spam chain (+1 first time, +2 second time, etc.)
		local seenScore = seenContent[spam.content]
		if seenScore then
			totalScore = totalScore + seenScore
			seenContent[spam.content] = seenScore + 1
		else
			seenContent[spam.content] = 1
		end

		totalScore = totalScore + spam.score
	end

	if (totalScore > countThreshold) then
		if (config.SpamMute) then
			local muteModule, err = bot:GetModuleForGuild(guild, "mute")
			if (muteModule) then
				local success, err = muteModule:Mute(guild, member.id, 0)
				if (success) then
					-- Send an alert
					local alertChannel = config.AlertChannel and guild:getChannel(config.AlertChannel)
					if (alertChannel) then
						local channelList = {}
						for _, spam in ipairs(spamChain) do
							local channel = guild:getChannel(spam.channelId)
							if channel then
								table.insert(channelList, channel.mentionString)
							else
								table.insert(channelList, "#deleted_channel")
							end
						end

						local fields = {}
						for _, spam in ipairs(spamChain) do
							local value = string.sub(spam.realContent, 1, 1000) -- This is limited to 1024 chars
							if string.len(value) ~= string.len(spam.realContent) then
								value = value .. "... (truncated)"
							end

							table.insert(fields, {
								name = "Message",
								value = value
							})
						end

						alertChannel:send({
							embed = {
								color = 16776960,
								description = bot:Format(guild, "RAID_AUTOMUTE_SPAM_REASON", member.mentionString, table.concat(channelList, ", ")),
								fields = fields,
								timestamp = discordia.Date():toISO('T', 'Z')
							}
						})
					end

					-- Delete messages
					local messagesToDelete = {}
					for _, messageData in pairs(spamChain) do
						table.insert(messagesToDelete, messageData)
					end
					data.spamChain[member.id] = nil

					for _, messageData in pairs(messagesToDelete) do
						local channel = guild:getChannel(messageData.channelId)
						if (channel) then
							local message = channel:getMessage(messageData.messageId)
							if (message) then
								message:delete()
							end
						end
					end
				else
					self:LogWarning(guild, "Failed to mute potential bot %s: %s", member.tag, err)
				end
			else
				self:LogWarning(guild, "Failed to mute potential bot %s: %s", member.tag, err)
			end
		else
			local success, err = member:ban(bot:Format("RAID_AUTOBAN_BOT_REASON"), 1)
			if (not success) then
				self:LogWarning(guild, "Failed to autoban potential bot %s (%s)", member.tag, err)
			end
		end
	end
end
