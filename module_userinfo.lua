-- Copyright (C) 2022 Mjöllnir#3515
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

Module.Name = "userinfo"


-- We have to precede special chars with an \ to prevent discord
-- from replacing them with the corresponding emoji :<color>_circle:
local discordStatus = {
	online = "\\🟢 Online", dnd = "\\🔴 Do Not Disturb", idle = "\\🟡 Idle", offline = "\\⚪ Offline"
}
local DEFAULT_COLOR = 0 -- Default color value, 0 == black
local JOIN_ORDER_WINDOW = 7 -- Number of members to show in "Join order" field
local Date = Discordia.Date
local intents = Discordia.enums.gatewayIntent
-- Privileged intent, must be checked before use
local has_guild_presences_intent = (bit.band(Bot.Client:getIntents(), intents.guildPresences) ~= 0)

-- The highest role with color ~= black defines the color of the username
local function getMemberColor(sortedRoles)
	for _, v in ipairs(sortedRoles) do
		if v.color ~= DEFAULT_COLOR then
			return v.color
		end
	end

	return DEFAULT_COLOR
end

local function buildUserEmbed(user)
	local fullName = user.tag
	local createdAt = Date.fromSeconds(user.createdAt):toParts()

	local description = string.format("__Fullname:__ `%s`\n__Created at:__ <t:%s:f>",
		fullName, createdAt)

	return {
		title = string.format("%s (%s)", user.tag, user.id),
		description = description
	}
end

local function buildMemberEmbed(member)
	local fullName = member.user.tag
	local createdAt = Date.fromSeconds(member.user.createdAt):toParts()
	local joinedAt = Date.fromISO(member.joinedAt):toParts()

	local description
	if has_guild_presences_intent then
		local presence = discordStatus[member.status]
		description =
			string.format([[
				__`Fullname:`__ `%s`
				__`Nickname:`__ `%s`
				__`Presence:`__ %s
				__`Created at:`__ <t:%s:f>
				__`Joined  at:`__ <t:%s:f>
				]],
				fullName, member.name, presence, createdAt, joinedAt)
	else
		description =
			string.format([[
				__`Fullname:`__ `%s`
				__`Nickname:`__ `%s`
				__`Created at:`__ <t:%s:f>
				__`Joined  at:`__ <t:%s:f>
				]],
				fullName, member.name, createdAt, joinedAt)
	end

	local fields = {}

	local roles = member.roles:toArray() -- cannot choose the sort order with the build-in method of Iterable
	if next(roles) ~= nil then
		table.sort(roles, function (a, b) return a.position > b.position end)

		local roleNames = {}
		for _, v in pairs(roles) do
			table.insert(roleNames, string.format("`%s`", v.name))
		end

		table.insert(fields, { name = "Roles", value = table.concat(roleNames, ", ") })
	end

	local guildMembers = member.guild.members:toArray()
	table.sort(guildMembers, function (a, b) return a.joinedAt < b.joinedAt end)

	local members = {}
	local position = 0
	for k, v in pairs(guildMembers) do
		if member.id == v.id then
			table.insert(members, string.format("%s.\t> %s", k, v.user.tag))
			position = k
		else
			table.insert(members, string.format("%s.\t  %s", k, v.user.tag))
		end
	end

	if #members > JOIN_ORDER_WINDOW then
		local first = math.floor(JOIN_ORDER_WINDOW / 2 - 0.5)
		local last = math.floor(JOIN_ORDER_WINDOW / 2 - 0.5)

		if position - first < 1 then
			first = 0
		end

		members = table.move(members, position - first, position + last, 1, {})
	end

	table.insert(fields, { name = "Join order", value = string.format("```text\n%s\n```", table.concat(members, "\n")) })

	return {
		title = string.format("%s (%s)", fullName, member.id),
		thumbnail = { url = member.user.avatarURL },
		description = description,
		fields = fields,
		color = getMemberColor(roles)
	}
end

function Module:OnLoaded()
	self:RegisterCommand({
		Name = "userinfo",
		Args = {
			{ Name = "target", Type = Bot.ConfigType.String, Optional = true }
		},
		Help = "Prints user/member info",

		Func = function (commandMessage, targetUserId)
			if not targetUserId then
				return commandMessage:reply({ embed = buildMemberEmbed(commandMessage.member) })
			end

			local targetMember, targetUser
			local err
			local guild = commandMessage.guild

			targetMember, err = Bot:DecodeMember(guild, targetUserId)

			if targetMember then
				return commandMessage:reply({ embed = buildMemberEmbed(targetMember) })
			elseif err == "Invalid user id" then
				return commandMessage:reply(err)
			else
				-- Not a member of this guild, trying to get info of the user
				targetUser, err = Bot:DecodeUser(targetUserId)

				if targetUser then
					return commandMessage:reply({ embed = buildUserEmbed(targetUser) })
				else
					return commandMessage:reply(err)
				end
			end
		end
	})

	return true
end
