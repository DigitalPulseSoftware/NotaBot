-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local client = Client
local discordia = Discordia
local bot = Bot

Module.Name = "serverconfig"
Module.Global = true

function Module:GetConfigTable()
	return {
		{
			Name = "Language",
			Description = "Bot language (en/fr)",
			Type = bot.ConfigType.String,
			Default = "fr"
		},
		{
			Name = "Prefix",
			Description = "Bot command prefix",
			Type = bot.ConfigType.String,
			Default = "!"
		}
	}
end
