local bot = Bot
local client = Client
---@type discordia
local discordia = Discordia
local prefix = Config.Prefix
local enums = discordia.enums
local http = require("coro-http")
local linkShorteners = require("./data_linkshorteners")
local os = require("os")
local timer = require("timer")
local setTimeout, sleep = timer.setTimeout, timer.sleep
local wrap = coroutine.wrap

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
            Type = bot.ConfigType.Integer,
            Default = 10000
        }
    }
end

local regExpChars = "[%\\%^%$%.%*%+%-%?%(%)%[%]{}%|]"

local function hasRegExpChar(str)
    return string.find(str, regExpChars) ~= nil
end

---Checks if a string has any regex characters and escapes them.
---@param str string
---@return string
local function escapeRegex(str)
    if not str or #str == 0 then return "" end
    if hasRegExpChar(str) then
        local replaced = str:gsub(regExpChars, "%%%1")
        return replaced
    else
        return str
    end
end


Module.DefaultRules = {
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
    "pd_rd_*@amazon.*",
    "_encoding@amazon.*",
    "psc@amazon.*",
    "tag@amazon.*",
    "ref_@amazon.*",
    "pf_rd_*@amazon.*",
    "pf@amazon.*",
    "crid@amazon.*",
    "keywords@amazon.*",
    "sprefix@amazon.*",
    "smid@amazon.*",
    "creative*@amazon.*",
    "th@amazon.*",
    "linkCode@amazon.*",
    "sr@amazon.*",
    "ie@amazon.*",
    "node@amazon.*",
    "qid@amazon.*",
    "dib@amazon.*",
    "dib_tag@amazon.*",
    "ref@amazon.*",
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

Module.FixServices = {
    ["bsky.app"] = "bskyx.app",
    -- Currently broken
    -- ["deviantart.com"] = "fxdeviantart.com",
    ["instagram.com"] = "ddinstagram.com",
    ["pixiv.net"] = "ppxiv.net",
    ["reddit.com"] = "rxddit.com",
    -- Currently broken
    -- ["threads.net"] = "vxthreads.net",
    ["tiktok.com"] = "tnktok.com",
    ["tumblr.com"] = "tpmblr.com",
    ["twitch.tv"] = "fxtwitch.tv",
    -- Use vxtwitter instead of fxtwitter since it includes greedy analytics
    ["twitter.com"] = "vxtwitter.com",
    ["x.com"] = "fixvx.com",
}

---@type table<string, boolean>
Module.UsersHanging = {} -- Table of users that have a message hanging with a delete button. (Otherwise an error would be thrown)

Module.UniversalRules = {}
Module.HostRules = {}
Module.RulesByHost = {}

function Module:CreateRules()
    -- Can be extended with a config option in the future
    local rules = self.DefaultRules


    for _, rule in ipairs(rules) do
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

---@param config table<string, any>
---@param data table<string, any>
function Module:CreateGuildRules(config, data)
    ---@type string[]
    local rules = config.Rules

    local universalRules = data.GuildUniversalRules or {}
    local hostRules = data.GuildHostRules or {}
    local rulesByHost = data.GuildRulesByHost or {}

    for _, rule in ipairs(rules) do
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

    data.GuildUniversalRules = universalRules
    data.GuildHostRules = hostRules
    data.GuildRulesByHost = rulesByHost

    bot:Save()
end

function Module:ClearGuildRules(config, data)
    data.GuildUniversalRules = nil
    data.GuildHostRules = nil
    data.GuildRulesByHost = nil

    bot:Save()
end

local function removeParam(rule, param, queryParams)
    if param == rule or string.match(param, rule) then
        queryParams[param] = nil
    end
end

---@param url string
---@return string?
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

---@param match string
---@param config table<string, any>
---@param data table<string, any>
---@return string
function Module:Replacer(match, config, data)
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
    --             return location
    --         end
    --     end
    -- end

    if self.FixServices[host] then
        local fix = self.FixServices[host]
        local newHost = host:gsub(host, fix)
        return protocol .. newHost .. path .. queryString
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

    for _, rule in ipairs(data.GuildUniversalRules or {}) do
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

    for hostRuleName, regex in pairs(data.GuildHostRules or {}) do
        if host:match(regex) then
            for _, rule in ipairs(data.GuildRulesByHost[hostRuleName] or {}) do
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

    return newUrl
end

---@param rules string[]
---@param guild Guild
function Module:AddRules(rules, guild)
    local guildData = self:GetGuildData(guild.id)
    local config = guildData.Config
    local data = guildData.Data

    for _, rule in ipairs(rules) do
        table.insert(config.Rules, rule)
    end

    self:CreateGuildRules(config, data)
    self:SaveGuildConfig(guild)
end

---@type table<string, table<string, table>>
local _attachments = {}

local ansiColoursForeground = {
    black = 30,
    red = 31,
    green = 32,
    yellow = 33,
    blue = 34,
    magenta = 35,
    cyan = 36,
    white = 37,
}

---@param rule string
---@return string
local function formatRule(rule)
    local splitRule = rule:split("@")

    if not splitRule[2] then
        return string.format("\x1b[%dm%s\x1b[0m", ansiColoursForeground.green, splitRule[1])
    end

    local colour = splitRule[1] == "*" and ansiColoursForeground.cyan or ansiColoursForeground.green

    local splitted = splitRule[2]:split("%.")

    return string.format("\x1b[%dm%s\x1b[0m\x1b[%dm@\x1b[0m\x1b[%dm%s\x1b[0m\x1b[%dm.\x1b[0m\x1b[%dm%s\x1b[0m", colour,
        splitRule[1], ansiColoursForeground.magenta, ansiColoursForeground.yellow, splitted[1],
        ansiColoursForeground.blue,
        ansiColoursForeground.red, splitted[2])
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
            local data = self:GetData(cmd.guild)
            local replaced = self:Replacer(url, config, data)

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
                return cmd:reply(Bot:Format(cmd.guild, 'CLEAN_URLS_NO_RULES_PROVIDED'))
            end

            local splittedRules = rules:split(",")
            self:AddRules(splittedRules, cmd.guild)
            cmd:reply(Bot:Format(cmd.guild, 'CLEAN_URLS_RULES_ADDED'))
        end
    })

    self:RegisterCommand({
        Name = "addcleanrule",
        Args = {
            { Name = "rule", Description = "The rule to add", Type = bot.ConfigType.String, }
        },
        Func = function(cmd, rule)
            if not rule then
                return cmd:reply(Bot:Format(cmd.guild, 'CLEAN_URLS_NO_RULE_PROVIDED'))
            end

            self:AddRules({ rule }, cmd.guild)
            cmd:reply(Bot:Format(cmd.guild, 'CLEAN_URLS_RULE_ADDED', rule))
        end
    })

    self:RegisterCommand({
        Name = "removecleanrule",
        Args = {
            { Name = "rule", Description = "The rule to remove", Type = bot.ConfigType.String, }
        },
        Func = function(cmd, rule)
            if not rule then
                return cmd:reply(Bot:Format(cmd.guild, 'CLEAN_URLS_NO_RULE_PROVIDED'))
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
            cmd:reply(Bot:Format(cmd.guild, 'CLEAN_URLS_RULE_REMOVED', rule))
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
            cmd:reply(Bot:Format(cmd.guild, 'CLEAN_URLS_RULES_CLEARED'))
        end
    })

    self:RegisterCommand({
        Name = "listcleanrules",
        Args = {},
        Func = function(cmd)
            local config = self:GetConfig(cmd.guild)
            local rules = config.Rules

            if #rules == 0 then
                return cmd:reply(Bot:Format(cmd.guild, 'CLEAN_URLS_NO_RULES'))
            end

            local result = string.format("## %s\n```ansi\n", Bot:Format(cmd.guild, 'CLEAN_URLS_RULES_HEADER'))

            for i, rule in ipairs(rules) do
                result = result .. i .. ". " .. formatRule(rule) .. "\n"
            end

            result = result .. "```"

            cmd:reply(result)
        end
    })

    return true
end

---comment
---@param message Message
---@param config table<string, any>
---@param data table<string, any>
function Module:CleanMessage(message, config, data)
    if (not bot:IsPublicChannel(message.channel)) then
        return
    end

    if (message.content:startswith(prefix, true)) then
        return
    end
    if message.content:find("http[s]?://") then
        return message.content:gsub("(https?://[^%s<]+[^<.,:;\"'>)|%]%s])", function(match)
            local replaced = self:Replacer(match, config, data)
            local same = match == replaced

            if not same then
                return replaced
            end

            return match
        end)
    end
end

---@param message Message
function Module:OnMessageCreate(message)
    if not message.channel.type == enums.channelType.text and not message.guild then
        return
    end

    ---@type GuildTextChannel
    ---@diagnostic disable-next-line: assign-type-mismatch
    local realChannel = (message.channel.isThread) and
        (message.client:getChannel(message.channel._parent_id)) or
        message.channel

    local config = self:GetConfig(message.guild)
    local data = self:GetData(message.guild)

    if message.author.bot or message.webhookId then
        return
    end

    if not config.AutoCleanUrls then
        return
    end

    local replaced = self:CleanMessage(message, config, data)

    if replaced == message.content or not replaced then
        return
    end

    if message.attachment then
        local attachments = {}

        for _, attachment in pairs(message.attachments) do
            local _, d = http.request("GET", attachment.url)
            if d then
                table.insert(attachments, { attachment.filename, d })
            end
        end

        _attachments[message.id] = attachments
    end


    if config.DeleteInvokationOnAutoCleanUrls then
        pcall(message.delete, message)
    end

    local webhook = self:GetWebhook(message.guild, realChannel)

    local components = {
        {
            type = enums.componentType.actionRow,
            components = {
                {
                    type = enums.componentType.button,
                    style = enums.buttonStyle.danger,
                    label = Bot:Format(message.guild, "CLEAN_URLS_DELETE_BUTTON_LABEL"),
                    custom_id = "delete_" .. message.author.id,
                }
            }
        }
    }

    local threadId = realChannel.id ~= message.channel.id and message.channel.id or nil

    local newAttachments = _attachments[message.id] or {}

    local msg = client._api:executeWebhook(webhook.id, webhook.token, {
            avatar_url = message.author.avatarURL,
            username = message.author.globalName or message.author.username,
            content = replaced,
            components = components,
        },
        { wait = true, thread_id = threadId },
        newAttachments
    )

    _attachments[message.id] = nil

    self.UsersHanging[message.author.id] = true

    local deleteTimeout = (config.ButtonTimeout or 10000)

    Bot:ScheduleAction(os.time() + deleteTimeout, function()
        if self.UsersHanging[message.author.id] then
            client._api:editWebhookMessage(webhook.id, webhook.token, msg.id, {
                components = {}
            }, { thread_id = threadId })
            self.UsersHanging[message.author.id] = nil
        end
    end)
end

---@param guild Guild
---@return boolean
function Module:OnEnable(guild)
    local config = self:GetConfig(guild)
    local data = self:GetData(guild)

    if #config.Rules == 0 then
        return true
    end

    self:CreateGuildRules(config, data)

    return true
end

---@param interaction Interaction
function Module:OnInteractionCreate(interaction)
    local customId = interaction.data.custom_id
    local guild = interaction.guild

    local authorId = customId:match("delete_(%d+)")
    if not authorId then
        return
    end

    local interactionAuthorId = interaction.member.user.id

    if authorId ~= interactionAuthorId or interaction.member:hasPermission(interaction.channel, 'manageMessages') then
        return interaction:respond({
            type = enums.interactionResponseType.channelMessageWithSource,
            data = {
                flags = enums.interactionResponseFlag.ephemeral,
                content = Bot:Format(guild, "CLEAN_URLS_WRONG_USER_BUTTON")
            }
        })
    end

    if interaction.message then
        pcall(interaction.message.delete, interaction.message)
    end

    interaction:respond({
        type = enums.interactionResponseType.channelMessageWithSource,
        data = {
            flags = enums.interactionResponseFlag.ephemeral,
            content = Bot:Format(guild, "CLEAN_URLS_DELETED_MESSAGE"),
        }
    })

    self.UsersHanging[authorId] = nil
end

---@param guild Guild
---@param channel GuildTextChannel
---@return Webhook
function Module:GetWebhook(guild, channel)
    local config = self:GetConfig(guild)

    local webhookId = config.WebhooksMappings[channel.id]

    if not webhookId then
        local webhook = channel:createWebhook(Bot:Format(guild, "CLEAN_URLS_AUDITLOG"))
        config.WebhooksMappings[channel.id] = webhook.id
        self:SaveGuildConfig(guild)
        return webhook
    end

    return client:getWebhook(webhookId)
end
