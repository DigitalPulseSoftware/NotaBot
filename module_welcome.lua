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
			Description = "Message to be posted when a user joins the server (`{userMention}` will be replaced by the user mention string)",
			Type = bot.ConfigType.String,
			Default = "Welcome to {userMention}!",
			Optional = true
		},
		{
			Name = "JoinRoles",
			Description = "Roles to give to new members (up to 10)",
			Type = bot.ConfigType.Role,
			Optional = true,
			Array = true,
			ArrayMaxSize = 10
		},
		{
			Name = "LeaveMessage",
			Description = "Message to be posted when a user leaves the server (`{userTag}` will be replaced by the user name)",
			Type = bot.ConfigType.String,
			Default = "Farewell {userTag}. :wave:",
			Optional = true
		},
		{
			Name = "BanMessage",
			Description = "Message to be posted when a user is banned from the server (`{userTag}` will be replaced by the user name)",
			Type = bot.ConfigType.String,
			Default = "{userTag} has been banned. :hammer:",
			Optional = true
		},
		{
			Name = "UnbanMessage",
			Description = "Message to be posted when a user is unbanned from the server (`{userTag}` will be replaced by the user name)",
			Type = bot.ConfigType.String,
			Default = "{userTag} has been unbanned.",
			Optional = true
		}
	}
end

function Module:OnMemberJoin(member)
	local guild = member.guild
	local config = self:GetConfig(guild)
	if (config.WelcomeChannel) then
		local channel = client:getChannel(config.WelcomeChannel)
		local message = config.JoinMessage
		if (channel and message) then
			message = self:CommonMessageGsub(message, member.user)
			message = message:gsub("{user}", member.user.mentionString)
			
			channel:send(message)
		end

		if (config.JoinRoles) then
			for _, roleId in ipairs(config.JoinRoles) do
				local role = guild:getRole(roleId)
				if (role) then
					local success, err = member:addRole(role, true)
					if (not success) then
						self:LogError(guild, "Failed to add role %s to member %s: %s", role.name, member.user.tag or "<invalid>", err)
					end
				else
					self:LogError(guild, "Invalid role %s", roleId)
				end
			end
		end
	end
end

function Module:OnMemberLeave(member)
	local config = self:GetConfig(member.guild)
	if (config.WelcomeChannel) then
		local channel = client:getChannel(config.WelcomeChannel)
		local message = config.LeaveMessage
		if (channel and message) then
			message = self:CommonMessageGsub(message, member.user)
			message = message:gsub("{user}", member.user.tag)
			if (member.joinedAt) then
				local duration = Discordia.Date() - Discordia.Date.fromISO(member.joinedAt)
				message = message:gsub("{duration}", bot:FormatDuration(member.guild, duration:toSeconds(), 2))
			else
				message = message:gsub("{duration}", "<unavailable>")
			end

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
			message = self:CommonMessageGsub(message, user)
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
			message = self:CommonMessageGsub(message, user)
			message = message:gsub("{user}", user.tag)
			
			channel:send(message)
		end
	end
end

function Module:CommonMessageGsub(message, user)
	message = message:gsub("{userTag}", user.tag)
	message = message:gsub("{userMention}", user.mentionString)
	return message
end
