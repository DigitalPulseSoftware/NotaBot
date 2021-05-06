local client = Client
local discordia = Discordia
local bot = Bot

Module.Name = "sentry"

local function ValidateString(str)
	if (type(str) ~= "string") then
		return false, " must be a string"
	end

	if (#str == 0) then
		return false, " cannot be empty"
	end

	return true
end

function Module:GetConfigTable()
	return {
		{
			Name = "SentryChannel",
			Description = "Channel where sentry news (monitored users joins and messages) will be posted",
			Type = bot.ConfigType.Channel,
			Optional = true
		},
		{
			Name = "JoinAlert",
			Description = "Message to be posted when a monitored user joins the server (`{userMention}` will be replaced by the user mention, `{userTag}` will be replaced by the user name, `{userId}` will be replaced by the user id)",
			Type = bot.ConfigType.String,
			Default = "The monitored user {userTag} ({userId}) has joined the server",
		},
		{
			Name = "MessageAlert",
			Description = "Message to be posted when a monitored user sends a message which contains one of optionally keywords (`{userMention}` will be replaced by the user mention, `{userTag}` will be replaced by the user name, `{userId}` will be replaced by the user id, `{message}` will be replaced by the message link)",
			Type = bot.ConfigType.String,
			Default = "The monitored user {userTag} ({userId}) has sent a message : {message}",
		},
		{
			Name = "MonitoredJoins",
			Description = "The users that the bot should monitor. Alert when a monitored user joins the server.",
			Type = bot.ConfigType.User,
			Default = {},
			Array = true,
		},
		{
			Name = "MonitoredMessages",
			Description = "The users that the bot should monitor. Alert when a monitored user sends a message. Map associating a user with keywords.",
			Type = bot.ConfigType.Custom,
			ValidateConfig = function (value)
				if (type(value) ~= "table" or #value ~= 0) then
					return false, "MonitoredMessages must be an object"
				end

				for userId, keywords in pairs(value) do
					if (not util.ValidateSnowflake(userId)) then
						return false, "MonitoredMessages keys must be user snowflakes"
					end

					if (type(keywords) ~= "table") then
						return false, "MonitoredMessages[" .. userId .. "] must be an array"
					end

					for i, keyword in pairs(keywords) do
						local success, err = ValidateString(keyword)
						if (not success) then
							return false, "MonitoredMessages[" .. userId .. "][" .. i .. "] (" .. tostring(keyword) .. " " .. err .. ")"
						end
					end
				end

				return true
			end,
			Default = {},
		}
	}
end

function Module:OnMemberJoin(member)
	local guild = member.guild
	local config = self:GetConfig(guild)
	if (not config.SentryChannel or not table.search(config.MonitoredJoins, member.id)) then
		return
	end

	local channel = client:getChannel(config.SentryChannel)
	if (not channel) then
		return
	end

	local alert = self:CommonMessageGsub(config.JoinAlert, member)
	channel:send(alert)
end

function Module:OnMessageCreate(message)
	if (message.author.bot) then
		return
	end

	if (not bot:IsPublicChannel(message.channel)) then
		return
	end

	local guild = message.guild
	local member = message.member
	local config = self:GetConfig(guild)
	
	local keywords = config.MonitoredMessages[member.id]
	if (not keywords or not config.SentryChannel) then
		return
	end

	local channel = client:getChannel(config.SentryChannel)
	if (not channel) then
		return
	end

	if (#keywords ~= 0) then
		local content = message.content:lower()
		for _, keyword in pairs(keywords) do
			if (content:find(keyword:lower())) then
				goto continue
			end
		end

		return
	end

	::continue::
	local alert = self:CommonMessageGsub(config.MessageAlert, member)
	alert = alert:gsub("{message}", Bot:GenerateMessageLink(message))

	local success, err = channel:send(alert)
	if (not success) then
		self:LogError(guild, "Failed to alert: %s", err)
	end
end

function Module:CommonMessageGsub(message, user)
	message = message:gsub("{userMention}", user.mentionString)
	message = message:gsub("{userTag}", user.tag)
	message = message:gsub("{userId}", user.id)
	return message
end
