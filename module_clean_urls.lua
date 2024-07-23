local bot = Bot
local client = Client
local discordia = Discordia
local prefix = Config.Prefix
local enums = discordia.enums
local http = require("coro-http")
local linkShorteners = require("./data_linkshorteners")

--[[
    This module is used to clean URLs from unwanted tracking (or, depending of guild configuration, any) query parameters.
    It will replace the URL with a cleaned version, and optionally delete the message that invoked the command.
    To preserve the flow of an happening conversation, a webhook is used to mimic the user that initially posted the message.
]]


Module.Name = "clean_urls"


function Module:GetConfigTable()
    return {
        {
            Name = "AutoCleanUrls",
            Description = "Should clean urls when an user posts a message link (when not using clean command)",
            Type = bot.ConfigType.Boolean,
            Default = true
        },
        {
            Name = "DeleteInvokationOnAutoCleanUrls",
            Description = "Deletes the message that invoked the clean urls when auto-cleaning urls",
            Type = bot.ConfigType.Boolean,
            Default = true
        },
        {
            Name = "DeleteInvokationOnManualCleanUrls",
            Description = "Deletes the message that invoked the clean urls when cleaning urls via command",
            Type = bot.ConfigType.Boolean,
            Default = true
        },
        {
            Name = "WebhooksMappings",
            Description = "The webhook id to use for cleaning urls",
            Type = bot.ConfigType.Custom,
            Default = {},
            ValidateConfig = function(value, guildId)
                if (type(value) ~= "table") then
                    return false, "Value must be a table"
                end

                for channelId, webhookId in pairs(value) do
                    if type(channelId) ~= "string" or type(webhookId) ~= "string" then
                        return false, "Value must be a table with string keys and string values"
                    end
                end

                return true
            end
        },
        {
            Name = "Rules",
            Description = "The rules to use for cleaning urls",
            Type = bot.ConfigType.String,
            Default = {},
            Array = true
        },
        {
            Name = "Whitelist",
            Description = "List of URL hosts to whitelist, e.g google.com",
            Type = bot.ConfigType.String,
            Default = {},
            Array = true
        },
        {
            Name = "ButtonTimeout",
            Description = "The time, in milliseconds after which the delete button will disappear",
            Type = bot.ConfigType.Number,
            Default = 10000
        }
    }
end

local regExpChars = "[%\\%^%$%.%*%+%-%?%(%)%[%]{}%|]"

local function hasRegExpChar(str)
    return string.find(str, regExpChars) ~= nil
end

local function escapeRegex(str)
    if not str or #str == 0 then return "" end
    if hasRegExpChar(str) then
        return str:gsub(regExpChars, "%%%1")
    else
        return str
    end
end


local defaultRules = {
    "action_object_map",
    "action_type_map",
    "action_ref_map",
    "spm@*.aliexpress.com",
    "scm@*.aliexpress.com",
    "aff_platform",
    "aff_trace_key",
    "algo_expid@*.aliexpress.*",
    "algo_pvid@*.aliexpress.*",
    "btsid",
    "ws_ab_test",
    "*@amazon.*",
    "callback@bilibili.com",
    "cvid@bing.com",
    "form@bing.com",
    "sk@bing.com",
    "sp@bing.com",
    "sc@bing.com",
    "qs@bing.com",
    "pq@bing.com",
    "sc_cid",
    "mkt_tok",
    "trk",
    "trkCampaign",
    "ga_*",
    "gclid",
    "gclsrc",
    "hmb_campaign",
    "hmb_medium",
    "hmb_source",
    "spReportId",
    "spJobID",
    "spUserID",
    "spMailingID",
    "itm_*",
    "s_cid",
    "elqTrackId",
    "elqTrack",
    "assetType",
    "assetId",
    "recipientId",
    "campaignId",
    "siteId",
    "mc_cid",
    "mc_eid",
    "pk_*",
    "sc_campaign",
    "sc_channel",
    "sc_content",
    "sc_medium",
    "sc_outcome",
    "sc_geo",
    "sc_country",
    "nr_email_referer",
    "vero_conv",
    "vero_id",
    "yclid",
    "_openstat",
    "mbid",
    "cmpid",
    "cid",
    "c_id",
    "campaign_id",
    "Campaign",
    "hash@ebay.*",
    "fb_action_ids",
    "fb_action_types",
    "fb_ref",
    "fb_source",
    "fbclid",
    "refsrc@facebook.com",
    "hrc@facebook.com",
    "gs_l",
    "gs_lcp@google.*",
    "ved@google.*",
    "ei@google.*",
    "sei@google.*",
    "gws_rd@google.*",
    "gs_gbg@google.*",
    "gs_mss@google.*",
    "gs_rn@google.*",
    "_hsenc",
    "_hsmi",
    "__hssc",
    "__hstc",
    "hsCtaTracking",
    "source@sourceforge.net",
    "position@sourceforge.net",
    "t@*.twitter.com",
    "s@*.twitter.com",
    "ref_*@*.twitter.com",
    "t@*.x.com",
    "s@*.x.com",
    "ref_*@*.x.com",
    "t@*.fixupx.com",
    "s@*.fixupx.com",
    "ref_*@*.fixupx.com",
    "t@*.fxtwitter.com",
    "s@*.fxtwitter.com",
    "ref_*@*.fxtwitter.com",
    "t@*.twittpr.com",
    "s@*.twittpr.com",
    "ref_*@*.twittpr.com",
    "t@*.fixvx.com",
    "s@*.fixvx.com",
    "ref_*@*.fixvx.com",
    "tt_medium",
    "tt_content",
    "lr@yandex.*",
    "redircnt@yandex.*",
    "feature@*.youtube.com",
    "kw@*.youtube.com",
    "si@*.youtube.com",
    "pp@*.youtube.com",
    "si@*.youtu.be",
    "wt_zmc",
    "utm_source",
    "utm_content",
    "utm_medium",
    "utm_campaign",
    "utm_term",
    "si@open.spotify.com",
    "igshid",
    "igsh",
    "share_id@reddit.com",
}

local fixServices = {
    ["bsky.app"] = "bskyx.app",
    ["deviantart.com"] = "fxdeviantart.com",
    ["instagram.com"] = "ddinstagram.com",
    ["pixiv.net"] = "ppxiv.net",
    ["reddit.com"] = "rxddit.com",
    -- Currently broken
    -- ["threads.net"] = "vxthreads.net",
    ["tiktok.com"] = "tiktxk.com",
    ["tumblr.com"] = "tpmblr.com",
    ["twitch.tv"] = "fxtwitch.tv",
    -- Use vxtwitter instead of fxtwitter since it includes greedy analytics
    ["twitter.com"] = "vxtwitter.com",
    ["x.com"] = "fixvx.com",
}

Module.UsersHanging = {}

Module.UniversalRules = {}
Module.HostRules = {}
Module.RulesByHost = {}
Module.GuildUniversalRules = {}
Module.GuildHostRules = {}
Module.GuildRulesByHost = {}

function Module:CreateRules()
    -- Can be extended with a config option in the future
    local rules = defaultRules


    for _, rule in ipairs(rules) do
        ---@diagnostic disable-next-line: undefined-field
        local splitRule = rule:split("@")
        local pattern = "^" .. escapeRegex(splitRule[1]):gsub("%%%*", ".-") .. "$"

        if not splitRule[2] then
            table.insert(self.UniversalRules, pattern)
        else
            local hostPattern = "^(w*%.?)" .. "(" .. escapeRegex(splitRule[2])
                :gsub("\\%.", "\\.")
                :gsub("^%%%*%.", "(.-%.)?")
                :gsub("%%%*", ".-") .. ")" .. "$"

            local hostPatternIndex = hostPattern

            self.HostRules[hostPatternIndex] = hostPattern

            if not self.RulesByHost[hostPatternIndex] then
                self.RulesByHost[hostPatternIndex] = {}
            end

            table.insert(self.RulesByHost[hostPatternIndex], pattern)
        end
    end

    return self.UniversalRules, self.HostRules, self.RulesByHost
end

function Module:CreateGuildRules(config, guildId)
    local rules = config.Rules

    local universalRules = self.GuildUniversalRules[guildId] or {}
    local hostRules = self.GuildHostRules[guildId] or {}
    local rulesByHost = self.GuildRulesByHost[guildId] or {}

    for _, rule in ipairs(rules) do
        ---@diagnostic disable-next-line: undefined-field
        local splitRule = rule:split("@")
        local pattern = "^" .. escapeRegex(splitRule[1]):gsub("%%%*", ".-") .. "$"

        if not splitRule[2] then
            table.insert(universalRules, pattern)
        else
            local hostPattern = "^(w*%.?)" .. escapeRegex(splitRule[2])
                :gsub("\\%.", "\\.")
                :gsub("^%%%*%.", "(.-%.)?")
                :gsub("%%%*", ".-") .. "$"

            local hostPatternIndex = hostPattern

            hostRules[hostPatternIndex] = hostPattern

            if not rulesByHost[hostPatternIndex] then
                rulesByHost[hostPatternIndex] = {}
            end

            table.insert(rulesByHost[hostPatternIndex], pattern)
        end
    end

    self.GuildUniversalRules[guildId] = universalRules
    self.GuildHostRules[guildId] = hostRules
    self.GuildRulesByHost[guildId] = rulesByHost
end

function Module:ClearGuildRules(config, guildId)
    self.GuildUniversalRules[guildId] = nil
    self.GuildHostRules[guildId] = nil
    self.GuildRulesByHost[guildId] = nil
end

local function removeParam(rule, param, queryParams)
    if param == rule or string.match(param, rule) then
        queryParams[param] = nil
    end
end

local function resolveLocation(url)
    if not url then return end

    local headers, body = http.request("GET", url)
    ---@diagnostic disable-next-line: param-type-mismatch
    local loc = (headers or {}):find(function(header) return header[1]:lower() == "location" end)
    if headers and loc then
        return loc[2]
    end

    if body then
        local location = body:match("<meta%s+http%-equiv=\"refresh\"%s+content=\"0;%s*url=([^%s]+)\"")
        if location then
            return location
        end
    end

    return url
end

function Module:Replacer(match, config, guildId)
    local protocol, host, path, queryString = match:match("^(https?://)([^/]+)(/[^?]*)(.-)$")
    if not protocol then
        return match
    end


    local wl = config.Whitelist

    for _, rule in ipairs(wl) do
        if host:match(rule) then
            return match
        end
    end

    -- for _, shortener in ipairs(linkShorteners.linkShorteners) do
    --     if host:match(shortener) then
    --         local location = resolveLocation(match)
    --         if location then
    --             return location, false
    --         end
    --     end
    -- end

    for service, fix in pairs(fixServices) do
        if host:match(service) then
            local newHost = host:gsub(service, fix)
            return protocol .. newHost .. path .. queryString, false
        end
    end

    if not queryString or #queryString == 0 or queryString == "?" then
        return match
    end

    local queryParams = {}
    for key, value in queryString:sub(2):gmatch("([^&=]+)=([^&]*)") do
        queryParams[key] = value
    end

    for _, rule in ipairs(self.UniversalRules) do
        for param, _ in pairs(queryParams) do
            removeParam(rule, param, queryParams)
        end
    end

    for _, rule in ipairs(self.GuildUniversalRules[guildId] or {}) do
        for param, _ in pairs(queryParams) do
            removeParam(rule, param, queryParams)
        end
    end

    for hostRuleName, regex in pairs(self.HostRules) do
        if host:match(regex) then
            for _, rule in ipairs(self.RulesByHost[hostRuleName]) do
                for param, _ in pairs(queryParams) do
                    removeParam(rule, param, queryParams)
                end
            end
        end
    end

    for hostRuleName, regex in pairs(self.GuildHostRules[guildId] or {}) do
        if host:match(regex) then
            for _, rule in ipairs(self.GuildRulesByHost[guildId][hostRuleName] or {}) do
                for param, _ in pairs(queryParams) do
                    removeParam(rule, param, queryParams)
                end
            end
        end
    end

    local newQueryString = {}
    for key, value in pairs(queryParams) do
        table.insert(newQueryString, key .. "=" .. value)
    end

    local concatedQueryString = table.concat(newQueryString, "&")

    local newUrl = protocol .. host .. (path or "") .. (concatedQueryString ~= "" and "?" .. concatedQueryString or "")

    local same = newUrl == match
    return newUrl, same
end

function Module:AddRules(rules, guild)
    local config = self:GetConfig(guild)

    for _, rule in ipairs(rules) do
        table.insert(config.Rules, rule)
    end

    self:CreateGuildRules(config, guild.id)
    self:SaveGuildConfig(guild)
end

function Module:OnLoaded()
    self:CreateRules()

    self:RegisterCommand({
        Name = "cleanurl",
        Args = {
            { Name = "url",              Description = "The URL to clean",                            Type = bot.ConfigType.String },
            { Name = "deleteInvokation", Description = "Delete the message that invoked the command", Type = bot.ConfigType.Boolean, Optional = true }
        },
        Func = function(cmd, url, deleteInvokation)
            local config = self:GetConfig(cmd.guild)
            local replaced = self:Replacer(url, config, cmd.guild.id)
            if replaced then
                cmd:reply(replaced)
            end

            if deleteInvokation then
                cmd.message:delete()
            end
        end

    })

    self:RegisterCommand({
        Name = "addcleanrules",
        Args = {
            { Name = "rules", Description = "The rules to add, separated by commas", Type = bot.ConfigType.String }
        },
        Func = function(cmd, rules)
            if not rules then
                return cmd:reply("No rules provided")
            end

            local rules = rules:split(",")
            self:AddRules(rules, cmd.guild)
            cmd:reply("Added rules")
        end
    })

    self:RegisterCommand({
        Name = "addcleanrule",
        Args = {
            { Name = "rule", Description = "The rule to add", Type = bot.ConfigType.String, }
        },
        Func = function(cmd, rule)
            if not rule then
                return cmd:reply("No rule provided")
            end

            self:AddRules({ rule }, cmd.guild)
            cmd:reply("Added rule")
        end
    })

    self:RegisterCommand({
        Name = "removecleanrule",
        Args = {
            { Name = "rule", Description = "The rule to remove", Type = bot.ConfigType.String, }
        },
        Func = function(cmd, rule)
            if not rule then
                return cmd:reply("No rule provided")
            end

            local config = self:GetConfig(cmd.guild)
            local rules = config.Rules

            for i, r in ipairs(rules) do
                if r == rule then
                    table.remove(rules, i)
                    break
                end
            end

            self:CreateGuildRules(config, cmd.guild.id)
            self:SaveGuildConfig(cmd.guild)
            cmd:reply("Removed rule")
        end
    })

    self:RegisterCommand({
        Name = "clearcleanrules",
        Args = {},
        Func = function(cmd)
            local config = self:GetConfig(cmd.guild)
            config.Rules = {}
            self:ClearGuildRules(config, cmd.guild.id)
            self:SaveGuildConfig(cmd.guild)
            cmd:reply("Cleared rules")
        end
    })

    self:RegisterCommand({
        Name = "listcleanrules",
        Args = {},
        Func = function(cmd)
            local config = self:GetConfig(cmd.guild)
            local rules = config.Rules

            if #rules == 0 then
                return cmd:reply("No rules")
            end

            local result = "## Rules\n```yaml\n"

            for i, rule in ipairs(rules) do
                result = result .. i .. ". " .. rule .. "\n"
            end

            result = result .. "```"

            cmd:reply(result)
        end
    })

    return true
end

function Module:CleanMessage(message, config)
    if (not bot:IsPublicChannel(message.channel)) then
        return
    end

    if (message.content:startswith(prefix, true)) then
        return
    end
    if message.content:find("http[s]?://") then
        return message.content:gsub("(https?://[^%s<]+[^<.,:;\"'>)|%]%s])", function(match)
            local replaced, same = self:Replacer(match, config, message.guild.id)

            if not same then
                return replaced
            end

            return match
        end)
    end
end

function Module:OnMessageCreate(message)
    if not message.channel.type == enums.channelType.text and not message.guild then
        return
    end

    local config = self:GetConfig(message.guild)

    if message.author.bot or message.webhookId then
        return
    end

    if not config.AutoCleanUrls then
        return
    end

    local replaced = self:CleanMessage(message, config)

    if replaced == message.content or not replaced then
        return
    end


    if config.DeleteInvokationOnAutoCleanUrls then
        message:delete()
    end

    local webhook = self:GetWebhook(message.guild, message.channel)

    local components = {
        {
            type = 1,
            components = {
                {
                    type = 2,
                    style = 4,
                    label = "Delete",
                    custom_id = "delete_" .. message.author.id,
                }
            }
        }
    }

    local msg = client._api:executeWebhook(webhook.id, webhook.token, {
            avatar_url = message.author.avatarURL,
            username = message.author.globalName or message.author.username,
            content = replaced,
            components = components
        },
        { wait = true }
    )

    self.UsersHanging[message.author.id] = true

    bot:ScheduleTimer(config.ButtonTimeout or 10000, function()
        if self.UsersHanging[message.author.id] then
            client._api:editWebhookMessage(webhook.id, webhook.token, msg.id, {
                components = {}
            })
            self.UsersHanging[message.author.id] = nil
        end
    end)
end

function Module:OnEnable(guild)
    local config = self:GetConfig(guild)

    if #config.Rules == 0 then
        return true
    end

    self:CreateGuildRules(config, guild.id)

    return true
end

function Module:OnInteractionCreate(interaction)
    local customId = interaction.data.custom_id

    local authorId = customId:match("delete_(%d+)")
    if not authorId then
        return
    end

    local interactionAuthorId = interaction.member.user.id

    if authorId ~= interactionAuthorId then
        return interaction:respond({
            type = 4,
            data = {
                flags = 64,
                content = "This button isn't for you!",
            }
        })
    end

    -- Because apparently, there's no channel.id or channel_id??
    client._api:deleteMessage(interaction._channel.id or interaction.message.channel_id, interaction.message.id)

    interaction:respond({
        type = 4,
        data = {
            flags = 64,
            content = "Deleted message",
        }
    })

    self.UsersHanging[authorId] = nil
end

function Module:GetWebhook(guild, channel)
    local config = self:GetConfig(guild)

    local webhookId = config.WebhooksMappings[channel.id]

    if not webhookId then
        local webhook = channel:createWebhook("Clean URLs")
        config.WebhooksMappings[channel.id] = webhook.id
        self:SaveGuildConfig(guild)
        return webhook
    end

    return client:getWebhook(webhookId)
end
