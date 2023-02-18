-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local bot = Bot
local client = Client
local discordia = Discordia

Module.Name = "game"
Module.Global = true

function Module:GetConfigTable()
	return {
		{
			Array = true,
			Global = true,
			Name = "GameList",
			Description = "List of activities",
			Type = bot.ConfigType.String,
			Default = {},
			Sensitive = true
		},
	}
end

function Module:OnLoaded()
	self.UpdateTimer = Bot:CreateRepeatTimer(3 * 60, -1, function ()
		self:UpdateActivity()
	end)

	self:UpdateActivity()
	return true
end

function Module:OnUnload()
	self.UpdateTimer:Stop()
end

function Module:UpdateActivity()
	local games = self.GlobalConfig.GameList
	local newGame = games[math.random(1, #games)]
	if (type(newGame) == "function") then
		newGame = newGame()
	end

	client:setActivity(newGame)
end