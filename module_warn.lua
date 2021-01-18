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

local function GetWarnAmount(history, memberId)
    local member = FindMember(history, memberId)
    return table.length(member.Warns)
end

local function SendWarnMessage(commandMessage, targetMember, reason)
    if not reason then
        commandMessage:reply(string.format("**%s** has warned **%s**.", commandMessage.member.tag, targetMember.tag))
    else
        commandMessage:reply(string.format("**%s** has warned **%s** for the following reason:\n**%s**.", commandMessage.member.tag, targetMember.tag, reason))
    end
end

--------------------------------

function Module:CheckPermissions(member)
    return member:hasPermission(enums.permission.banMembers)
end

function Module:GetConfigTable()

    return {
        {
            Name = "Sactions",
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
            Name = "MuteRole",
            Description = "(MUTE NOT YET IMPLEMENTED) Mute role to be applied (no need to configure its permissions)\n /!\\ The role must be the same as the role used in the Mute module. The Mute module must be enabled too.",
            Type = bot.ConfigType.Role,
            Default = ""
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
    local data = self:GetPersistentData(guild)
    data = data or {}

    local config = self:GetConfig(guild)

    local banInfo = config.BanInformationChannel and guild:getChannel(config.BanInformationChannel) or nil
    if not banInfo then
        return false, "Invalid ban information channel, check your configuration."
    end

    local muteRole = config.MuteRole and guild:getRole(config.MuteRole) or nil
    if not muteRole then
        return false, "Invalid mute role, check your configuration."
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
        PrivilegeCheck = function (member) return self:CheckPermissions(member) end,

        Help = "Warns a member",
        Silent = true,
        Func = function (commandMessage, targetUser, reason)
            local guild = commandMessage.guild
            local config = self:GetConfig(guild)
            local history = self:GetPersistentData(guild)
            history = history or {}
            
            local targetMember = guild:getMember(targetUser)
            local moderator = commandMessage.member
            
            -- Permission check
            if targetMember then
                local bannedByRole = moderator.highestRole
                local targetRole = targetMember.highestRole
                if targetRole.position >= bannedByRole.position then
                    commandMessage:reply("You cannot warn this user due to your lower permissions.")
                    return
                end
            end

            -- Adding warn to the user
            local targetId = targetUser.id
            local moderatorId = commandMessage.member.id
            
            AddWarn(history, targetId, moderatorId, reason)


            if config.SendPrivateMessage then
                local privateChannel = targetUser:getPrivateChannel()
                if privateChannel then
                    if reason then
                        privateChannel:send(string.format("You have been warned on %s for the following reason:\n **%s**", guild.name, reason))
                    else
                        privateChannel:send(string.format("You have been warned on %s", guild.name))
                    end
                end
            end

            -- Updating member state
            SendWarnMessage(commandMessage, targetMember, reason)
            
            if config.Sactions then
                local banAmount = config.WarnAmountToBan
                local muteAmount = config.WarnAmountToMute
                local warnAmount = GetWarnAmount(history, targetId)

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
                    
                    if mute_module:IsEnabledForGuild(guild) then
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
        PrivilegeCheck = function (member) return self:CheckPermissions(member) end,

        Help = "Shows all the warns of a member.",
        Silent = true,
        Func = function(commandMessage, targetUser)
            local guild = commandMessage.guild
            local history = self:GetPersistentData(guild)
            local targetMember = guild:getMember(targetUser)

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
        PrivilegeCheck = function (member) return self:CheckPermissions(member) end,

        Help = "Clears all the warns of a specified user.",
        Silent = true,
        Func = function (commandMessage, targetUser)
            local guild = commandMessage.guild
            local history = self:GetPersistentData(guild)
            local targetMember = guild:getMember(targetUser)

            local memberHistory = FindMember(history, targetMember.id)
            if not memberHistory then
                commandMessage:reply(string.format("The member **%s** (%d) already have zero warns.", targetMember.tag, targetMember.id))
            else
                memberHistory.Warns = {}
                commandMessage:reply(string.format("Cleared **%s** (%d) warns, saving.", targetMember.tag, targetMember.id))
                bot:Save()
            end
        end
    })

    return true
end