-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local fs = require("fs")

local langtables = {}
Bot.LangTables = langtables

local langFiles = fs.scandirSync("localization")
for filename, filetype in assert(langFiles) do
	if filetype == "file" then
		local lang = filename:match("(%w+)%.lua")
		if lang then
			local data, err = dofile("localization/" .. filename)
			if data then
				langtables[lang] = data
			else
				print("failed to load language data from " .. filename .. ": " .. err)
			end
		end
	end
end

function Bot:Format(guild, str, ...)
	local serverconfig = self:GetModuleForGuild(guild, "serverconfig")
	if serverconfig then
		local config = serverconfig:GetConfig(guild, true)
		if config then
			local langtable = langtables[config.Language]
			if langtable then
				local translation = langtable.Locs[str]
				if translation then
					return string.format(translation, ...)
				end
			end
		end
	end

	return string.format(str, ...)
end

function Bot:FormatDuration(guild, seconds, depth)
	local serverconfig = self:GetModuleForGuild(guild, "serverconfig")
	if serverconfig then
		local config = serverconfig:GetConfig(guild, true)
		if config then
			local langtable = langtables[config.Language]
			if langtable then
				local formatTime = langtable.FormatTime
				if formatTime then
					return formatTime(seconds, depth)
				end
			end
		end
	end

	return util.FormatTime(seconds, depth)
end
