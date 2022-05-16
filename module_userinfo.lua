-- Copyright (C) 2022 Mjöllnir#3515
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

Module.Name = "userinfo"

-- We have to precede special chars with an \ to prevent discord from replacing them with the corresponding emoji :<color>_circle:
local discordStatus = { online = "\\🟢 Online", dnd = "\\🔴 Do Not Disturb", idle = "\\🟡 Idle", offline = "\\⚪ Offline" }
local ISO8601_PATTERN = "(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)%.*"
local DEFAULT_COLOR = 0 -- Default color value, 0 == black

-- Join datetime is provided in ISO format, but a timestamp is needed to use the Discord Timestamps
local function getMemberJoinTimestamp(member)
    local y, m, d, h, mn, s = member.joinedAt:match(ISO8601_PATTERN)

    return os.time({year = y, month = m, day = d, hour = h, min = mn, sec = s})
end

-- The highest role with color ~= black defines the color of the username
local function getMemberColor(sortedRoles)
    for i, v in ipairs(sortedRoles) do
        if v.color ~= DEFAULT_COLOR then
            return v.color
        end
    end

    return DEFAULT_COLOR
end

local function buildUserEmbed(user)
    local fullName = user.tag
    local createdAt = tostring(user.createdAt):match("(%d+)%.")

    local description = string.format("__Fullname:__ %s\n__Created at:__ <t:%s:f>",
        fullName, createdAt)

    return {
        title = string.format("%s (%s)", user.tag, user.id),
        description = description
    }
end

local function buildMemberEmbed(member)
    local fullName = member.user.tag
    local presence = discordStatus[member.status]
    local createdAt = tostring(member.user.createdAt):match("(%d+)%.")
    local joinedAt = getMemberJoinTimestamp(member)

    local description =
        string.format("__`Fullname:`__ %s\n__`Nickname:`__ %s\n__`Presence:`__ %s\n__`Created at:`__ <t:%s:f>\n__`Joined  at:`__ <t:%s:f>\n",
            fullName, member.name, presence, createdAt, joinedAt)

    local roles = member.roles:toArray() -- cannot choose the sort order with the build-in method of Iterable
    table.sort(roles, function (a, b) return a.position > b.position end)

    local role_names = {}
    for k,v in pairs(roles) do
        table.insert(role_names, string.format("`%s`", v.name))
    end

    local guildMembers = member.guild.members:toArray()
    table.sort(guildMembers, function (a, b) return a.joinedAt < b.joinedAt end)

    local members = {}
    for k, v in pairs(guildMembers) do
        if member.id == v.id then
            table.insert(members, string.format("%s.\t> %s", k, v.user.tag))
        else
            table.insert(members, string.format("%s.\t  %s", k, v.user.tag))
        end
    end

    return {
        title = string.format("%s (%s)", fullName, member.id),
        thumbnail = { url = member.user.avatarURL },
        description = description,
        fields = {
            { name = "Roles", value = table.concat(role_names, ", ") },
            { name = "Join order", value = string.format("```markdown\n%s\n```", table.concat(members, "\n")) }
        },
        color = getMemberColor(roles)
    }
end

function Module:OnLoaded()
    self:RegisterCommand({
        Name = "userinfo",
        Args = {
            { Name = "target", Type = Bot.ConfigType.String, Optional = true },
        },
        Help = "Prints user/member info",

        Func = function (commandMessage, targetUserId)
            if not targetUserId then
                return commandMessage:reply({ embed = buildMemberEmbed(commandMessage.member) })
            end

            local guild = commandMessage.guild
            local targetMember, err = Bot:DecodeMember(guild, targetUserId)

            if targetMember then
                return commandMessage:reply({ embed = buildMemberEmbed(targetMember) })
            elseif err == "Invalid user id" then
                return commandMessage:reply(err)
            else
                -- Not a member of this guild, trying to get info of the user
                local targetUser, err = Bot:DecodeUser(targetUserId)

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
