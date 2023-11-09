-- Copyright (C) 2021 Lezenn
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local client = Client
local config = Config
local discordia = Discordia
local bot = Bot
local enums = discordia.enums

Module.Name = "warn"

--  Storage Model
--
--  {
--		"Warns": {
--			"<UserId>": [ { "WarnedBy": "<ModeratorId>", "Reason": "..." }, ... ],
--			...
-- 		}
--	}

local function AddWarn(history, memberId, moderatorId, reason)
	if history.Warns[memberId] == nil then
		history.Warns[memberId] = {}
	end

	table.insert(history.Warns[memberId], { WarnedBy = moderatorId, Reason = reason })
end

-- TODO delete this
local function ConvertDataFormat(guildId, config, data, persistentData)
	-- Check the format, Warns is in the new but not in the old
	if persistentData.Warns ~= nil then
		return
	end

	persistentData.Warns = {}
	while #persistentData > 0 do
		for _, warn in ipairs(persistentData[1].Warns) do
			persistentData.Warns[persistentData[1].UserId] = {}
			table.insert(persistentData.Warns[persistentData[1].UserId], { WarnedBy = warn.From, Reason = warn.Reason })
		end
		table.remove(persistentData, 1)
	end
end

--------------------------------

function Module:CheckPermissions(member)
	return member:hasPermission(enums.permission.banMembers)
end

function Module:GetConfigTable()

	return {
		{
			Name = "Sanctions",
			Description = "Enable sanctions over members.",
			Type = bot.ConfigType.Boolean,
			Default = true
		},
		{
			Name = "WarnAmountToMute",
			Description = "Number of warns needed to mute the member.",
			Type = bot.ConfigType.Integer,
			Default = 3
		},
		{
			Name = "WarnAmountToBan",
			Description = "Number of warns needed to tempban the member.",
			Type = bot.ConfigType.Integer,
			Default = 9,
		},
		{
			Name = "DefaultMuteDuration",
			Description = "Default mute duration when reached enough warns.",
			Type = bot.ConfigType.Duration,
			Default = 60 * 60
		},
		{
			Name = "BanInformationChannel",
			Description = "Default channel where all the ban-able members are listed.",
			Type = bot.ConfigType.Channel,
			Default = ""
		},
		{
			Name = "SendPrivateMessage",
			Description = "Sends the warning to the user in private message.",
			Type = bot.ConfigType.Boolean,
			Default = true
		}
	}

end

function Module:OnEnable(guild)
	local config = self:GetConfig(guild)

	local banInfo = config.BanInformationChannel and guild:getChannel(config.BanInformationChannel)
	if not banInfo then
		return false, "Invalid ban information channel, check your configuration."
	end

	return true
end

function Module:OnLoaded()

	-- TODO delete this
	self:ForEachGuild(ConvertDataFormat, true, true, true)

	self:RegisterCommand({
		Name = "warn",
		Args = {
			{ Name = "target", Type = bot.ConfigType.User },
			{ Name = "reason", Type = bot.ConfigType.String, Optional = true }
		},
		PrivilegeCheck = function (member) return self:CheckPermissions(member) end,

		Help = function (guild) return Bot:Format(guild, "WARN_WARN_HELP") end,
		Silent = true,
		Func = function (commandMessage, targetUser, reason)
			local guild = commandMessage.guild
			local config = self:GetConfig(guild)
			local history = self:GetPersistentData(guild) or {}
			local reason = reason or Bot:Format(guild, "GLOBAL_DEFAULT_REASON")
			local infoChannel = guild:getChannel(config.BanInformationChannel)

			local targetMember = guild:getMember(targetUser)
			local moderator = commandMessage.member

			-- Permission check
			if targetMember then
				local bannedByRole = moderator.highestRole
				local targetRole = targetMember.highestRole
				if targetRole.position >= bannedByRole.position then
					commandMessage:reply(Bot:Format(guild, "WARN_WARN_PERMISSION_DENIED"))
					return
				end
			end

			-- Add warn to the user
			local targetId = targetUser.id
			local moderatorId = commandMessage.member.id
			AddWarn(history, targetId, moderatorId, reason)

			if config.SendPrivateMessage then
				local privateChannel = targetUser:getPrivateChannel()
				if privateChannel then
					privateChannel:send(Bot:Format(guild, "WARN_WARN_PM", guild.name, reason))
				end
			end

			local warnAmount = #history.Warns[targetId]
			commandMessage:reply(Bot:Format(guild, "WARN_WARN_MSG", commandMessage.member.tag, targetMember.tag, warnAmount, reason))

			if config.Sanctions then
				local banThreshold = config.WarnAmountToBan
				local muteThreshold = config.WarnAmountToMute

				if warnAmount % banThreshold == 0 then
					infoChannel:send(Bot:Format(guild, "WARN_WARN_BAN_REACHED",
						targetMember.tag, targetMember.id, warnAmount))

					return
				end

				if warnAmount % muteThreshold == 0 then
					local duration = config.DefaultMuteDuration * (warnAmount / muteThreshold)
					infoChannel:send(Bot:Format(guild, "WARN_WARN_MUTE_REACHED",
						targetMember.tag, targetMember.id, warnAmount, duration))

					local muteModule = bot:GetModuleForGuild(guild, "mute")
					if muteModule then
						bot:CallModuleFunction(muteModule, "Mute", guild, targetMember.id, duration)
					end
				end
			end
		end
	})

	self:RegisterCommand({
		Name = "warnlist",
		Args = {
			{ Name = "targetUser", Type = bot.ConfigType.User }
		},
		PrivilegeCheck = function (member) return self:CheckPermissions(member) end,

		Help = function (guild) return Bot:Format(guild, "WARN_WARNLIST_HELP") end,
		Silent = true,
		Func = function(commandMessage, targetUser)
			local guild = commandMessage.guild
			local history = self:GetPersistentData(guild)
			local warns = history.Warns[targetUser.id]

			if warns == nil then
				commandMessage:reply(Bot:Format(guild, "WARN_NO_WARNS", targetUser.tag, targetUser.id))
			else
				local message = Bot:Format(guild, "WARN_WARNLIST_LIST", targetUser.tag, targetUser.id)
				for _, warn in ipairs(warns) do
					local warnedBy = client:getUser(warn.WarnedBy)
					local reason = warn.Reason or Bot:Format(guild, "GLOBAL_DEFAULT_REASON") -- TODO this line may be deleted when timers will be implemented
					message = message .. Bot:Format(guild, "WARN_WARNLIST_ITEM", warnedBy.tag, reason)
				end
				commandMessage:reply(message)
			end
		end
	})

	self:RegisterCommand({
		Name = "clearwarns",
		Args = {
			{ Name = "targetUser", Type = bot.ConfigType.User }
		},
		PrivilegeCheck = function (member) return self:CheckPermissions(member) end,

		Help = function (guild) return Bot:Format(guild, "WARN_CLEARWARNS_HELP") end,
		Silent = true,
		Func = function (commandMessage, targetUser)
			local guild = commandMessage.guild
			local history = self:GetPersistentData(guild)

			if history.Warns[targetUser.id] == nil then
				commandMessage:reply(Bot:Format(guild, "WARN_NO_WARNS", targetUser.tag, targetUser.id))
			else
				history.Warns[targetUser.id] = nil
				commandMessage:reply(Bot:Format(guild, "WARN_CLEARWARNS_CLEARED", targetUser.tag, targetUser.id))
				bot:Save()
			end
		end
	})

	return true
end
