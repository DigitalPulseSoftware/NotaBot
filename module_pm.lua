-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local client = Client
local discordia = Discordia
local bot = Bot
local enums = discordia.enums

Module.Global = true
Module.Name = "pm"

function Module:GetConfigTable()
	return {
		{
			Global = true,
			Name = "TargetGuild",
			Description = "Where private messages should be logged",
			Type = bot.ConfigType.Guild,
			Optional = true
		},
		{
			Global = true,
			Name = "TargetChannel",
			Description = "Where private messages should be logged",
			Type = bot.ConfigType.Channel,
			Optional = true
		}
	}
end

function Module:OnMessageCreate(message)
	local channel = message.channel
	if not channel or channel.type ~= enums.channelType.private then
		return
	end

	if not self.GlobalConfig.TargetGuild or not self.GlobalConfig.TargetChannel then
		return
	end

	local logGuild = client:getGuild(self.GlobalConfig.TargetGuild)
	if not logGuild then
		self:LogError("invalid target guild (%s)", self.GlobalConfig.TargetGuild)
		return
	end

	local logChannel = logGuild:getChannel(self.GlobalConfig.TargetChannel)
	if not logChannel then
		self:LogError("invalid target channel (%s)", self.GlobalConfig.TargetGuild)
		return
	end

	local embed = Bot:BuildQuoteEmbed(message, { bigAvatar = true })

	local success, err = logChannel:send({
		embed = embed
	})
	if not success then
		self:LogError("failed to log private message: %s", err)
	end
end
