-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local client = Client
local config = Config
local discordia = Discordia
local bot = Bot
local enums = discordia.enums

Module.Name = "mention"

function Module:OnMessageCreate(message)
	if (message.channel.type ~= enums.channelType.text) then
		return
	end

	local mention = false

	if (message.mentionsEveryone) then
		mention = true
	else
		for _, user in pairs(message.mentionedUsers) do
			if (user.id == client.user.id) then
				mention = true
				break
			end
		end
	end

	if (mention) then
		local mentionEmoji = bot:GetEmojiData("mention")
		if (not mentionEmoji or not mentionEmoji.Emoji) then
			return
		end

		message:addReaction(mentionEmoji.Emoji)
	end
end
