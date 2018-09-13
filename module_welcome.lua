local client = Client
local discordia = Discordia
local bot = Bot

Module.Name = "welcome"

function Module:GetConfigTable()
	return {
		{
			Name = "WelcomeChannel",
			Description = "Channel where join/leave will be posted",
			Type = bot.ConfigType.Channel,
			Optional = true
		},
		{
			Name = "BanChannel",
			Description = "Channel where ban/unban will be posted",
			Type = bot.ConfigType.Channel,
			Optional = true
		},
		{
			Name = "JoinMessage",
			Description = "Message to be posted when a user joins the server (`{user}` will be replaced by the user mention string)",
			Type = bot.ConfigType.String,
			Default = "Welcome to {user}!",
			Optional = true
		},
		{
			Name = "LeaveMessage",
			Description = "Message to be posted when a user leaves the server (`{user}` will be replaced by the user name)",
			Type = bot.ConfigType.String,
			Default = "Farewell {user}. :wave:",
			Optional = true
		},
		{
			Name = "BanMessage",
			Description = "Message to be posted when a user is banned from the server (`{user}` will be replaced by the user name)",
			Type = bot.ConfigType.String,
			Default = "{user} has been banned. :hammer:",
			Optional = true
		},
		{
			Name = "UnbanMessage",
			Description = "Message to be posted when a user is unbanned from the server (`{user}` will be replaced by the user name)",
			Type = bot.ConfigType.String,
			Default = "{user} has been unbanned.",
			Optional = true
		}
	}
end

function Module:OnMemberJoin(member)
	local config = self:GetConfig(member.guild)
	if (config.WelcomeChannel) then
		local channel = client:getChannel(config.WelcomeChannel)
		local message = config.JoinMessage
		if (channel and message) then
			message = message:gsub("{user}", member.user.mentionString)
			
			channel:send(message)
		end
	end
end

function Module:OnMemberLeave(member)
	local config = self:GetConfig(member.guild)
	if (config.WelcomeChannel) then
		local channel = client:getChannel(config.WelcomeChannel)
		local message = config.LeaveMessage
		if (channel and message) then
			message = message:gsub("{user}", member.user.tag)
			
			channel:send(message)
		end
	end
end

function Module:OnUserBan(user, guild)
	local config = self:GetConfig(guild)
	if (config.BanChannel) then
		local channel = client:getChannel(config.BanChannel)
		local message = config.BanMessage
		if (channel and message) then
			message = message:gsub("{user}", user.tag)

			channel:send(message)
		end
	end
end

function Module:OnUserUnban(user, guild)
	local config = self:GetConfig(guild)
	if (config.BanChannel) then
		local channel = client:getChannel(config.BanChannel)
		local message = config.UnbanMessage
		if (channel and message) then
			message = message:gsub("{user}", user.tag)
			
			channel:send(message)
		end
	end
end
