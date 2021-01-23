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
--  [
--      {
--          UserId: memberId,
--          Warns: {
--              {From: moderatorId, Reason: "...."},
--              ...
--          }
--      },
--      ...
--  ]

local function FindMember(history, memberId)
    local result = nil
    for _idx, userHistory in ipairs(history) do
        if userHistory.UserId == memberId then
            result = userHistory
            break
        end
    end
    return result
end

local function AddWarn(history, memberId, moderatorId, reason)
    local member = FindMember(history, memberId)
    if (not member) then
        table.insert(history, {
            UserId = memberId,
            Warns = {
                {
                    From = moderatorId,
                    Reason = reason,
                }
            }
        })
    else
        table.insert(member.Warns, {
            From = moderatorId,
            Reason = reason,
        })
    end
end

local function SendWarnMessage(commandMessage, targetMember, reason)
    if not reason then
        commandMessage:reply(string.format("**%s** has warned **%s**.", commandMessage.member.tag, targetMember.tag))
    else
        commandMessage:reply(string.format("**%s** has warned **%s** for the following reason:\n**%s**.", commandMessage.member.tag, targetMember.tag, reason))
    end
end

local function generateLogEmbed(title, target, message, timestamp)
    local result = {
        content = "",
        embed = {
            title = title,
            author = {
                name = target.tag,
                icon_url = target.avatarURL
            },
            fields = {
                {
                    name = "Reason",
                    value = message,
                    inline = false
                }
            },
            timestamp = timestamp
        }
    }
    return result
end

--------------------------------

function Module:LogWarn(guild, moderator, target, message, timestamp)
    local config = self:GetConfig(guild)
    local logChannel = guild:getChannel(config.WarnLogChannel)
    local success, errMessage = logChannel:send(generateLogEmbed(
        string.format("**%s** warned **%s**", moderator.tag, target.tag),
        target,
        message,
        timestamp
    ))
    if not success then
        self:LogError(errMessage)
    end
end

function Module:LogWarnModification(guild, moderator, target, message, timestamp)
    local config = self:GetConfig(guild)
    local logChannel = guild:getChannel(config.WarnLogChannel)

    logChannel:send(generateLogEmbed(
        string.format("**%s** made a modification upon **%s** warns", moderator.tag, target.tag),
        target,
        message,
        timestamp
    ))
end

function Module:GetWarnAmount(history, memberId)
    local member = FindMember(history, memberId)
    return #member.Warns
end

function Module:HasWarnRole(member)
    local config = self:GetConfig(member.guild)
    local warnRole = (member.guild):getRole(config.MinimalWarnRole)
    local memberRole = member.highestRole

    return memberRole.position >= warnRole.position
end

function Module:HasUnwarnRole(member)
    local config = self:GetConfig(member.guild)
    local unwarnRole = (member.guild):getRole(config.MinimalUnwarnRole)
    local memberRole = member.highestRole

    return memberRole.position >= unwarnRole.position
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
            Name = "MinimalWarnRole",
            Description = "Minimal role to warn members and see history",
            Type = bot.ConfigType.Role,
            Default = ""
        },
        {
            Name = "MinimalUnwarnRole",
            Description = "Minimal role to unwarn (remove last warn) of a member",
            Type = bot.ConfigType.Role,
            Default = "",
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
            Description = "Channel where all the ban-able members are listed.",
            Type = bot.ConfigType.Channel,
            Default = ""
        },
        {
            Name = "WarnLogChannel",
            Description = "Channel where all the warns, unwarns, ... are logged.",
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
    local data = self:GetPersistentData(guild)
    data = data or {}

    local config = self:GetConfig(guild)

    local banInfo = config.BanInformationChannel and guild:getChannel(config.BanInformationChannel) or nil
    if not banInfo then
        return false, "Invalid BanInformationChannel, check your configuration."
    end

    local logChan = config.WarnLogChannel and guild:getChannel(config.WarnLogChannel) or nil
    if not logChan then
        return false, "Invalid WarnLogChannel, check your configuration."
    end

    local warnRole = config.MinimalWarnRole and guild:getRole(config.MinimalWarnRole) or nil
    if not warnRole then
        return false, "Invalid MinimalWarnRole setting, check your configuration."
    end

    local unwarnRole = config.MinimalUnwarnRole and guild:getRole(config.MinimalUnwarnRole) or nil
    if not unwarnRole then
        return false, "Invalid MinimalUnwarnRole setting, check your configuration."
    end

    return true
end

function Module:OnLoaded()

    --
    --  warn command
    --
    self:RegisterCommand({
        Name = "warn",
        Args = {
            {Name = "target", Type = bot.ConfigType.User},
            {Name = "reason", Type = bot.ConfigType.String, Optional = true}
        },
        PrivilegeCheck = function (member)
            return self:HasWarnRole(member)
        end,

        Help = "Warns a member",
        Silent = true,
        Func = function (commandMessage, targetUser, reason)
            local guild = commandMessage.guild
            local config = self:GetConfig(guild)
            local history = self:GetPersistentData(guild)
            history = history or {}
            
            local targetMember = guild:getMember(targetUser)
            local moderator = commandMessage.member
            
            if not targetMember then
                commandMessage:reply("The given member does not exists or is invalid.")
                return
            end

            -- Permission check
            local bannedByRole = moderator.highestRole
            local targetRole = targetMember.highestRole
            if targetRole.position >= bannedByRole.position then
                commandMessage:reply("You cannot warn this user due to your lower permissions.")
                return
            end
            
            -- Adding warn to the user
            local targetId = targetUser.id
            local moderatorId = commandMessage.member.id
            
            AddWarn(history, targetId, moderatorId, reason)
            
            if reason then
                self:LogWarn(guild, moderator, targetMember, reason, commandMessage.timestamp)
            else
                self:LogWarn(
                    guild, 
                    moderator, 
                    targetMember,
                    "No reason provided.", 
                    commandMessage.timestamp)
            end

            if config.SendPrivateMessage then
                local privateChannel = targetUser:getPrivateChannel()
                if privateChannel then
                    if reason then
                        privateChannel:send(string.format("You have been warned on %s for the following reason:\n **%s**", guild.name, reason))
                    else
                        privateChannel:send(string.format("You have been warned on %s, no reason provided.", guild.name))
                    end
                end
            end

            -- Updating member state
            SendWarnMessage(commandMessage, targetMember, reason)
            
            if config.Sanctions then
                local banAmount = config.WarnAmountToBan
                local muteAmount = config.WarnAmountToMute
                local warnAmount = self:GetWarnAmount(history, targetId)

                if warnAmount % banAmount == 0 then
                    -- BAN
                    local channel = guild:getChannel(config.BanInformationChannel)
                    if channel then
                        channel:send(string.format("The member **%s** ( %d ) has enough warns to be banned (%d warns).",
                            targetMember.tag,
                            targetMember.id,
                            warnAmount
                        ))
                    end

                elseif warnAmount % muteAmount == 0 then
                    -- MUTE
                    local duration = config.DefaultMuteDuration * (warnAmount / muteAmount)
                    local durationStr = util.FormatTime(duration, 3)
                    local mute_module = bot:GetModuleForGuild(guild, "mute")
                    
                    if mute_module then
                        local channel = guild:getChannel(config.BanInformationChannel)
                        if channel then
                            channel:send(string.format("The member **%s** ( %d ) has enough warns to be muted (%d warns) for %s.",
                                targetMember.tag,
                                targetMember.id,
                                warnAmount,
                                durationStr
                            ))
                        end
                        bot:CallModuleFunction(mute_module, "Mute", guild, targetMember.id, duration)
                    end
                end
            end
        end
    })

    --
    --  warnlist command
    --
    self:RegisterCommand({
        Name = "warnlist",
        Args = {
            {Name = "targetUser", Type = bot.ConfigType.User}
        },
        PrivilegeCheck = function (member) 
            return self:HasWarnRole(member)
        end,

        Help = "Shows all the warns of a member.",
        Silent = true,
        Func = function(commandMessage, targetUser)
            local guild = commandMessage.guild
            local history = self:GetPersistentData(guild)
            local targetMember = guild:getMember(targetUser)

            if not targetMember then
                commandMessage:reply("The given member does not exists or is invalid.")
                return
            end

            local memberHistory = FindMember(history, targetMember.id)
            if not memberHistory then
                commandMessage:reply(string.format("The member **%s** (%d) doesn't have any warns.", targetMember.tag, targetMember.id))
            else
                local message = string.format("Warns of **%s** (%d)\n", targetMember.tag, targetMember.id)
                local warns = memberHistory.Warns
                for _idx, warn in ipairs(warns) do
                    local moderator = guild:getMember(warn.From)
                    local reason = warn.Reason or "No reason provided"
                    message = message .. string.format("Warned by : **%s** for the reason:\n\t**%s**\n", moderator.tag, reason)
                end
                commandMessage:reply(message)
            end
        end
    })

    --
    --  clearwarns command
    --
    self:RegisterCommand({
        Name = "clearwarns",
        Args = {
            {Name = "targetUser", Type = bot.ConfigType.User}
        },
        PrivilegeCheck = function (member) 
            return self:HasUnwarnRole(member)
        end,

        Help = "Clears all the warns of a specified user.",
        Silent = true,
        Func = function (commandMessage, targetUser)
            local guild = commandMessage.guild
            local history = self:GetPersistentData(guild)
            local targetMember = guild:getMember(targetUser)
            local moderator = commandMessage.author

            if not targetMember then
                commandMessage:reply("The given member does not exists or is invalid.")
                return
            end

            local memberHistory = FindMember(history, targetMember.id)
            if not memberHistory then
                commandMessage:reply(string.format("The member **%s** (%d) already have zero warns.", targetMember.tag, targetMember.id))
            else
                for _i, warn in ipairs(memberHistory.Warns) do
                    self:LogWarnModification(
                        guild, 
                        moderator, 
                        targetMember, 
                        string.format("**%s** cleared the following warn of **%s** (%d).\nIt was: **%s**\n\t*From: %s*", 
                            moderator.tag, 
                            targetMember.tag,
                            targetMember.id,
                            warn.Reason,
                            guild:getMember(warn.From).tag
                        )
                    )
                end
                
                self:LogWarnModification(
                    guild, 
                    moderator, 
                    targetMember, 
                    string.format("**%s** cleared %d warns of **%s** (%d).", 
                        moderator.tag, 
                        #memberHistory.Warns,
                        targetMember.tag,
                        targetMember.id
                    )
                )

                memberHistory.Warns = {}

                commandMessage:reply(string.format("Cleared **%s** (%d) warns, saving.", targetMember.tag, targetMember.id))
                bot:Save()
            end
        end
    })

    --
    --  popwarn command
    --
    self:RegisterCommand({
        Name = "popwarn",
        Args = {
            {Name = "targetUser", Type = bot.ConfigType.User}
        },
        PrivilegeCheck = function (member)
            return self:HasUnwarnRole(member)
        end,

        Help = "Removes the last warn of the given user.",
        Silent = true,
        Func = function (commandMessage, targetUser)
            local guild = commandMessage.guild
            local history = self:GetPersistentData(guild)
            local targetMember = guild:getMember(targetUser)
            local moderator = commandMessage.author
            
            if not targetMember then
                commandMessage:reply("The given member does not exists or is invalid.")
                return
            end

            local memberHistory = FindMember(history, targetMember.id)
            if not memberHistory then
                commandMessage:reply(string.format("The member **%s** (%d) already have zero warns.", targetMember.tag, targetMember.id))
            else
                local lastWarn = table.remove(memberHistory.Warns)
                local lastWarnReason = lastWarn.Reason
                if not lastWarnReason then
                    lastWarnReason = "No reason provided."
                end
                self:LogWarnModification(
                    guild, 
                    moderator, 
                    targetMember, 
                    string.format("**%s** removed the last warn of **%s** (%d).\nIt was: **%s**\n\t*From: %s*", 
                        moderator.tag, 
                        targetMember.tag,
                        targetMember.id,
                        lastWarnReason,
                        guild:getMember(lastWarn.From).tag
                    )
                )
            end
        end
    })

    return true
end
