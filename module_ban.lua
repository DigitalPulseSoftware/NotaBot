-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local client = Client
local discordia = Discordia
local bot = Bot
local enums = discordia.enums

Module.Name = "ban"

function Module:CheckPermissions(member)
	--[[for roleId,_ in pairs(self.Config.AuthorizedRoles) do
		if (member:hasRole(roleId)) then
			return true
		end
	end]]

	return member:hasPermission(enums.permission.banMembers)
end

function Module:GetConfigTable()
	return {
		{
			Name = "DefaultBanDuration",
			Description = "Default ban duration if no duration is set",
			Type = bot.ConfigType.Duration,
			Default = 24 * 60 * 60
		},
		{
			Name = "SendPrivateMessage",
			Description = "Should the bot try to send a private message right before banning someone? (including who banned them and for what)",
			Type = bot.ConfigType.Boolean,
			Default = true
		}
	}
end

function Module:OnLoaded()
	self:RegisterCommand({
		Name = "ban",
		Args = {
			{Name = "target", Type = Bot.ConfigType.User},
			{Name = "duration", Type = Bot.ConfigType.Duration, Optional = true},
			{Name = "reason", Type = Bot.ConfigType.String, Optional = true},
		},
		PrivilegeCheck = function (member) return self:CheckPermissions(member) end,

		Help = "Bans a member",
		Func = function (commandMessage, targetUser, duration, reason)
			local guild = commandMessage.guild
			local config = self:GetConfig(guild)
			local bannedBy = commandMessage.member

			-- Duration
			if (not duration) then
				duration = config.DefaultBanDuration
			end

			local durationStr = util.FormatTime(duration, 3)

			-- Reason
			reason = reason or ""

			local targetMember = guild:getMember(targetUser)
			if (targetMember) then
				local bannedByRole = bannedBy.highestRole
				local targetRole = targetMember.highestRole
				if (targetRole.position > bannedByRole.position) then
					commandMessage:reply("You cannot ban that user due to your lower permissions.")
					return
				end
			end

			if (config.SendPrivateMessage) then
				local privateChannel = targetUser:getPrivateChannel()
				if (privateChannel) then
					local durationText
					if (duration > 0) then
						durationText = string.format("You will be unbanned in %s", duration > 0 and durationStr or "")
					else
						durationText = ""
					end

					privateChannel:send(string.format("You have been banned from **%s** by %s (%s)\n%s", commandMessage.guild.name, bannedBy.user.mentionString, #reason > 0 and ("reason: " .. reason) or "no reason given", durationText))
				end
			end

			local data = self:GetData(commandMessage.guild)
			data.BanInProgress[targetUser.id] = true
			if (guild:banUser(targetUser, reason, 0)) then
				commandMessage:reply(string.format("%s has banned %s (%s)%s", bannedBy.name, targetUser.tag, duration > 0 and ("for " .. durationStr) or "permanent", #reason > 0 and (" for the reason: " .. reason) or ""))

				self:RegisterBan(commandMessage.guild, targetUser.id, commandMessage.author, duration, reason)
			else
				data.BanInProgress[targetUser.id] = nil
				commandMessage:reply(string.format("Failed to ban %s", targetUser.tag))
			end
		end
	})

	self:RegisterCommand({
		Name = "unban",
		Args = {
			{Name = "target", Type = Bot.ConfigType.User},
			{Name = "reason", Type = Bot.ConfigType.String, Optional = true},
		},
		PrivilegeCheck = function (member) return self:CheckPermissions(member) end,

		Help = "Unbans a member",
		Func = function (commandMessage, targetUser, reason)
			local guild = commandMessage.guild
			local config = self:GetConfig(guild)

			-- Reason
			reason = reason or ""

			if (config.SendPrivateMessage) then
				local privateChannel = targetUser:getPrivateChannel()
				if (privateChannel) then
					privateChannel:send(string.format("You have been unbanned from **%s** by %s (%s)", commandMessage.guild.name, commandMessage.member.user.mentionString, #reason > 0 and ("reason: " .. reason) or "no reason given"))
				end
			end

			local data = self:GetData(commandMessage.guild)
			if (guild:unbanUser(targetUser, reason)) then
				commandMessage:reply(string.format("%s has unbanned %s%s", commandMessage.member.name, targetUser.tag, #reason > 0 and (" for the reason: " .. reason) or ""))
			else
				commandMessage:reply(string.format("Failed to unban %s", targetUser.tag))
			end
		end
	})

	self:RegisterCommand({
		Name = "updatebanduration",
		Args = {
			{Name = "target", Type = Bot.ConfigType.User},
			{Name = "new_duration", Type = Bot.ConfigType.Duration},
		},
		PrivilegeCheck = function (member) return self:CheckPermissions(member) end,

		Help = "Updates the ban duration ",
		Func = function (commandMessage, targetUser, newDuration)
			local guild = commandMessage.guild

			local durationStr = util.FormatTime(newDuration, 3)

			if (self:UpdateBanDuration(guild, targetUser.id, newDuration)) then
				commandMessage:reply(string.format("%s has updated %s ban duration (%s)", 
					commandMessage.member.name,
					targetUser.tag,
					newDuration > 0 and ("unbanned in " .. durationStr) or "banned permanently"))
			else
				commandMessage:reply(string.format("%s is not banned", targetUser.tag))
			end
		end
	})
	return true
end

function Module:OnEnable(guild)
	local persistentData = self:GetPersistentData(guild)
	persistentData.BannedUsers = persistentData.BannedUsers or {}

	local data = self:GetData(guild)
	data.BanInProgress = {}
	data.UnbanTable = {}

	self:SyncBans(guild)

	for userId, banData in pairs(persistentData.BannedUsers) do
		local expiration = banData.ExpirationTime
		if (expiration) then
			self:RegisterBanExpiration(guild, userId, expiration)
		end
	end

	return true
end

function Module:OnReady()
	if (not self.UnbanClock) then
		self.UnbanClock = discordia.Clock()
		self.UnbanClock:on("sec", function ()
			local now = discordia.Date():toSeconds()
			self:ForEachGuild(function (guildId, config, data, persistentData)
				local guild = client:getGuild(guildId)
				assert(guild)

				local bannedUsers = persistentData.BannedUsers

				local unbanData = data.UnbanTable[1]
				if (unbanData and now >= unbanData.Time) then
					-- Double check ban info
					local userId = unbanData.UserId
					local banData = bannedUsers[userId]
					if (banData and banData.ExpirationTime and now >= banData.ExpirationTime) then
						local user = client:getUser(unbanData.UserId)
						if (user) then
							self:LogInfo(guild, "Unbanning %s (duration expired)", user and user.tag or unbanData.UserId)

							guild:unbanUser(unbanData.UserId, "Ban duration expired")
						end

						bannedUsers[userId] = nil
					end

					table.remove(data.UnbanTable, 1)
				end
			end)
		end)
		self.UnbanClock:start()
	end
end

function Module:OnUnload()
	if (self.UnbanClock) then
		self.UnbanClock:stop()
		self.UnbanClock = nil
	end
end

function Module:GetBannedUsersTable(guild)
	local persistentData = self:GetPersistentData(guild)
	return persistentData.BannedUsers
end

function Module:RegisterBan(guild, userId, bannedByUser, duration, reason)
	local bannedUsers = self:GetBannedUsersTable(guild)

	local now = discordia.Date()
	local expiration
	if (duration > 0) then
		local expirationDate = now + discordia.Time.fromSeconds(duration)
		expiration = expirationDate:toSeconds()

		self:RegisterBanExpiration(guild, userId, expiration)
	end

	bannedUsers[userId] = {
		BannedAt = now:toSeconds(),
		BannedBy = bannedByUser.id,
		ExpirationTime = expiration,
		Reason = #reason > 0 and reason or nil
	}

	self:SavePersistentData(guild)
end

function Module:UpdateBanData(guild, userId, bannedByUserId, banDate, duration, reason)
	local bannedUsers = self:GetBannedUsersTable(guild)

	local banData = bannedUsers[userId]
	if (banData) then
		local expiration
		if (duration and duration > 0) then
			local expirationDate = banDate + discordia.Time.fromSeconds(duration)
			expiration = expirationDate:toSeconds()
		end

		banData.BannedBy = bannedByUserId

		if (banDate) then
			banData.BannedAt = banDate:toSeconds()
		end

		if (duration) then
			banData.ExpirationTime = expiration

			self:RegisterBanExpiration(guild, userId, expiration)
		end

		if (reason) then
			banData.Reason = reason
		end
	end
end

function Module:UpdateBanDuration(guild, userId, duration)
	local bannedUsers = self:GetBannedUsersTable(guild)
	if (not bannedUsers[userId]) then
		return false
	end

	local expiration
	if (duration > 0) then
		local now = discordia.Date()
		local expirationDate = now + discordia.Time.fromSeconds(duration)
		expiration = expirationDate:toSeconds()

		self:RegisterBanExpiration(guild, userId, expiration)
	end

	local banData = bannedUsers[userId]
	banData.ExpirationTime = expiration

	return true
end

function Module:RegisterBanExpiration(guild, userId, expirationTime)
	local data = self:GetData(guild)
	table.insert(data.UnbanTable, { Time = expirationTime, UserId = userId })
	table.sort(data.UnbanTable, function (a, b)	return a.Time < b.Time end)
end

function Module:SyncBans(guild)
	local bannedUsers = self:GetBannedUsersTable(guild)

	-- Retrieve all banned users in the guild
	local guildBanned = {}
	local missingBanData = {}
	for _, ban in pairs(guild:getBans()) do
		local user = ban.user
		if (not bannedUsers[user.id]) then
			self:LogInfo(guild, "Found banned user %s in guild which is not logged (ban reason: %s)", user.tag, ban.reason or "<none>")

			missingBanData[user.id] = true

			bannedUsers[user.id] = {
				Reason = ban.reason
			}
		end

		guildBanned[user.id] = {}
	end

	-- Check if any user is still logged as banned by user but not by the guild
	local unbannedUsers = {}
	for userId, _ in pairs(bannedUsers) do
		if (not guildBanned[userId]) then
			local user = client:getUser(userId)
			if (user) then
				self:LogWarning(guild, "User %s is logged as banned but is not found in the guild ban list, removing...", user.tag)
			end

			table.insert(unbannedUsers, userId)
		end
	end

	for _, userId in pairs(unbannedUsers) do
		bannedUsers[userId] = nil
	end

	-- Try to recover some ban information from the guild audit logs
	if (not table.empty(missingBanData)) then
		local query = {}
		query.type = enums.actionType.memberBanAdd
		query.limit = 100

		for i = 1, 10 do -- Limit
			local auditLogs = {}
			for k,log in pairs(guild:getAuditLogs(query)) do
				table.insert(auditLogs, log)
			end

			table.sort(auditLogs, function (a, b) return a.createdAt > b.createdAt end)

			for k, log in pairs(auditLogs) do
				local bannedUser = log:getTarget()

				if (bannedUser) then
					if (missingBanData[bannedUser.id]) then
						local bannedBy = log:getMember()
						local date = discordia.Date.fromSnowflake(log.id)

						self:LogInfo(guild, "Found audit log data for %s ban (banned by %s at %s)", bannedUser.tag, bannedBy.tag, date:toHeader())
						self:UpdateBanData(guild, log.targetId, bannedBy.id, date)

						missingBanData[bannedUser.id] = nil
					end
				end
			end

			if (#auditLogs < query.limit or table.empty(missingBanData)) then
				break
			end

			query.before = auditLogs[#auditLogs].id
		end
	end

	if (not table.empty(missingBanData)) then
		self:LogWarning(guild, "%s bans without audit log remains, these will be counted as permanent bans made by unknowns", table.count(missingBanData))
	end

	self:SavePersistentData(guild)
end

function Module:OnUserBan(user, guild)
	local data = self:GetData(guild)
	local bannedUsers = self:GetBannedUsersTable(guild)
	local banData = bannedUsers[user.id]
	if (not data.BanInProgress[user.id]) then
		-- Try to recover some ban information from the guild audit logs
		local query = {}
		query.type = enums.actionType.memberBanAdd
		query.limit = 20

		local guildAuditLogs = guild:getAuditLogs(query)
		if (guildAuditLogs) then
			local auditLogs = {}
			for k,log in pairs(guildAuditLogs) do
				table.insert(auditLogs, log)
			end

			table.sort(auditLogs, function (a, b) return a.createdAt > b.createdAt end)

			for k, log in pairs(auditLogs) do
				if (log.targetId == user.id) then
					local bannedBy = log:getMember()
					local date = discordia.Date.fromSnowflake(log.id)

					self:RegisterBan(guild, user.id, bannedBy.user, 0, log.reason or "")
					self:LogInfo(guild, "Registered manual ban of %s by %s at %s (reason: %s)", log:getTarget().tag, bannedBy.tag, date:toHeader(), log.reason or "<no reason>")

					self:SavePersistentData(guild)
					return
				end
			end
		end

		self:LogWarning(guild, "Failed to retrieve informations about manual ban of %s at %s", user.tag, discordia.Date():toHeader())
	else
		data.BanInProgress[user.id] = nil
	end
end

function Module:OnUserUnban(user, guild)
	local bannedUsers = self:GetBannedUsersTable(guild)
	bannedUsers[user.id] = nil
	self:SavePersistentData(guild)
end
