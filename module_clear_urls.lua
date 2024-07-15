local bot = Bot
local client = Client
local discordia = Discordia
local enums = discordia.enums


Module.Name = "clear_urls"


function Module:GetConfigTable()
    return {
        {
            Name = "AutoClearUrls",
            Description = "Should clear urls when an user posts a message link (when not using clear command)",
            Type = bot.ConfigType.Boolean,
            Default = true
        },
        {
            Name = "DeleteInvokationOnAutoClearUrls",
            Description = "Deletes the message that invoked the clear urls when auto-clearing urls",
            Type = bot.ConfigType.Boolean,
            Default = true
        },
        {
            Name = "DeleteInvokationOnManualClearUrls",
            Description = "Deletes the message that invoked the clear urls when clearing urls via command",
            Type = bot.ConfigType.Boolean,
            Default = true
        },
        {
            Name = "WebhooksMappings",
            Description = "The webhook id to use for clearing urls",
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
            Description = "The rules to use for clearing urls",
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
        }
    }
end

local function hasRegExpChar(str)
    local regExpChar = "[%\\%^%$%.%*%+%?%(%)%[%]{}%|]"
    return string.find(str, regExpChar) ~= nil
end

local function escapeRegex(str)
    if not str or #str == 0 then return "" end
    if hasRegExpChar(str) then
        return str:gsub("([%\\%^%$%.%*%+%?%(%)%[%]{}%|])", "%%%1")
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
    "sr@amazon.*",
    "ie@amazon.*",
    "node@amazon.*",
    "qid@amazon.*",
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
        local pattern = "^" .. escapeRegex(splitRule[1]):gsub("%*", ".+?") .. "$"

        if not splitRule[2] then
            table.insert(self.UniversalRules, pattern)
        else
            local hostPattern = "^(w*%.?)" .. escapeRegex(splitRule[2])
                :gsub("\\%.", "\\.")
                :gsub("^%*%.", "(.+?%.)?")
                :gsub("%%%*", ".-") .. "$"

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
        local pattern = "^" .. escapeRegex(splitRule[1]):gsub("%*", ".+?") .. "$"

        if not splitRule[2] then
            table.insert(universalRules, pattern)
        else
            local hostPattern = "^(w*%.?)" .. escapeRegex(splitRule[2])
                :gsub("\\%.", "\\.")
                :gsub("^%*%.", "(.+?%.)?")
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

local function removeParam(rule, param, queryParams)
    if param == rule or string.match(param, rule) then
        queryParams[param] = nil
    end
end

function Module:Replacer(match, config)
    local protocol, host, path, queryString = match:match("^(https?://)([^/]+)(/[^?]*)?(.*)$")
    if not protocol then
        return match
    end

    if queryString == "" or queryString == "?" then
        return match
    end

    local wl = config.Whitelist

    for _, rule in ipairs(wl) do
        if host:match(rule) then
            return match
        end
    end

    -- Parsing query string into table
    local queryParams = {}
    for key, value in queryString:gmatch("([^&=]+)=([^&]*)") do
        queryParams[key] = value
    end

    -- Check all universal rules
    for _, rule in ipairs(self.UniversalRules) do
        for param, _ in pairs(queryParams) do
            removeParam(rule, param, queryParams)
        end
    end

    -- Check all universal guild rules
    for _, rule in ipairs(self.GuildUniversalRules[guild.id]) do
        for param, _ in pairs(queryParams) do
            removeParam(rule, param, queryParams)
        end
    end

    -- Check rules for each host that matches
    for hostRuleName, regex in pairs(self.HostRules) do
        if host:match(regex) then
            for _, rule in ipairs(self.RulesByHost[hostRuleName]) do
                for param, _ in pairs(queryParams) do
                    removeParam(rule, param, queryParams)
                end
            end
        end
    end

    -- Check rules for each host that matches
    for hostRuleName, regex in pairs(self.GuildHostRules[guild.id]) do
        if host:match(regex) then
            for _, rule in ipairs(self.GuildRulesByHost[guild.id][hostRuleName]) do
                for param, _ in pairs(queryParams) do
                    removeParam(rule, param, queryParams)
                end
            end
        end
    end

    -- Reconstructing the query string
    local newQueryString = {}
    for key, value in pairs(queryParams) do
        table.insert(newQueryString, key .. "=" .. value)
    end

    local concatedQueryString = table.concat(newQueryString, "&")

    -- Reconstructing the URL
    local newUrl = protocol .. host .. (path or "") .. (concatedQueryString ~= "" and "?" .. concatedQueryString or "")

    -- Check if the new URL is the same as the old one
    local same = newUrl == match
    return newUrl, same
end

function Module:OnLoaded()
    self:CreateRules()

    self:RegisterCommand({
        Name = "clear",
        Args = {
            { "string",  "url",              "The URL to clear" },
            { "boolean", "deleteInvokation", "Delete the message that invoked the command", Optional = true }
        },
        Func = function(cmd, url, deleteInvokation)
            local replaced = self:Replacer(url, cmd.guild)
            if replaced then
                cmd:reply(replaced)
            end

            -- if deleteInvokation then
            --     cmd.message:delete()
            -- end
        end

    })

    return true
end

function Module:ClearMessage(message, config)
    if message.content:find("http[s]?://") then
        return message.content:gsub("(https?://[^%s<]+[^<.,:;\"'>)|%]%s])", function(match)
            local replaced, same = self:Replacer(match, config)

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

    if not config.AutoClearUrls then
        return
    end

    local replaced = self:ClearMessage(message, config)

    if replaced == message.content then
        return
    end


    if config.DeleteInvokationOnAutoClearUrls then
        message:delete()
    end

    -- Get webhook (to mimic the user)
    local webhook = self:GetWebhook(message.guild, message.channel)

    client._api:executeWebhook(webhook.id, webhook.token, {
        avatar_url = message.author.avatarURL,
        username = message.author.globalName or message.author.username,
        content = replaced
    })
end

function Module:OnEnable(guild)
    local config = self:GetConfig(guild)

    if #config.Rules == 0 then
        return true
    end

    self:CreateGuildRules(config, guild.id)

    return true
end

function Module:GetWebhook(guild, channel)
    local config = self:GetConfig(guild)

    local webhookId = config.WebhooksMappings[channel.id]

    if not webhookId then
        local webhook = channel:createWebhook("Clear URLs")
        config.WebhooksMappings[channel.id] = webhook.id
        self:SaveGuildConfig(guild)
        return webhook
    end

    return client:getWebhook(webhookId)
end
