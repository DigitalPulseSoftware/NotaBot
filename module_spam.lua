-- Copyright (C) 2021 Julien Castiaux
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local client = Client
local discordia = Discordia
local bot = Bot
local enums = discordia.enums
local moduleModo = require('module_modo.lua')

Module.Name = "spam"
scoreThreshold = 3


function Module:GetConfigTable()
	return {
		{
			Name = "ShouldAlert",
			Description = "Alert moderators on spam detection (requires module_modo)",
			Type = bot.ConfigType.Boolean,
			Default = true
		},
		{
			Name = "ShouldMute",
			Description = "Mute spammer on spam detection (requires module_modo)",
			Type = bot.ConfigType.Boolean,
			Default = true
		},
		{
			Name = "ShouldDelete",
			Description = "Delete message on spam detection",
			Type = bot.ConfigType.Boolean,
			Default = true
		},
	}
end

function computeSpamScore(message)
	local lowerContent = message.content:lower()
	local spamScore = 0

	local spamWords = {"nitro", "discord", "steam", "free"}
	for i = 1, #spamWords do
		if lowerContent:find(spamWords[i]) then
			spamScore = spamScore + 1
		end
	end

	local spamHints = {"3 month", "away", "gift", "airdrop"}
	for i = 1, #spamWords do
		if lowerContent:find(spamWords[i]) then
			spamScore = spamScore + 1
			break  -- only score once
		end
	end

	return spamScore
end


function Module:OnMessageCreate(message)
	if (not bot:IsPublicChannel(message.channel)) then
		return
	end

	if (message.author.bot) then
		return
	end

	if not message.content:match("https?://([%w%.]+)") then
		return
	end

	for _, roleId in pairs(config.ImmunityRoles) do
		if (messageMember:hasRole(roleId)) then
			return
		end
	end

	local spamScore = computeSpamScore(message)
	if spamScore < scoreThreshold then
		return
	end

	-- Spam detected
	local config = self:GetConfig(guild)

	if config.ShouldAlert then
		moduleModoConfig = moduleModo:GetConfig(guild)
		moduleModo:HandleEmojiAdd(bot, message)
		message.addReaction(moduleModoConfig.Trigger)
	end

	if config.ShouldMute then
		moduleModo:Mute(guild, message.author)
		message.addReaction('mute')
	end

	if config.ShouldDelete then
		message:delete()
	else
		message.addReaction('warning')
	end

	if config.ShouldSummary then
		local summary = "**Spam detection!**"
		if config.ShouldDelete then
			summary = summary + " That link is smelly, **don't click** on it !"
		else
			summary = summary + " The message have been automatically removed."
		end
		if config.ShouldAlert then
			summary = summary + " The moderators have been notified. They'll have a look."
		end
		if ShouldMute then
			summary = summary + " The author have been muted to prevent further spam."
		end
		message.channel:send(summary)
	end
end