-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local client = Client
local config = Config
local discordia = Discordia
local bot = Bot
local enums = discordia.enums
local wrap = coroutine.wrap

Module.Name = "twitch"

Module.GameCache = {}

discordia.extensions()

local httpCodec = require('http-codec')
local net = require('coro-net')
local json = require('json')
local sha256 = require('sha256')
local querystring = require('querystring')
local twitchAPI = require('./twitchapi.lua')

function Module:GetConfigTable()
	return {
		{
			Name = "TwitchConfig",
			Description = "List of watched channels with title patterns for messages to post on channel goes up",
			Type = bot.ConfigType.Custom,
			Default = {}
		},
		{
			Global = true,
			Name = "CallbackEndpoint",
			Description = "URI which will be sent to Twitch for channel events",
			Type = bot.ConfigType.String,
			Default = ""
		},
		{
			Global = true,
			Name = "ListenPort",
			Description = "Port on which internal server listens",
			Type = bot.ConfigType.Integer,
			Default = 14793
		},
		{
			Global = true,
			Name = "SilenceDuration",
			Description = "Duration during which a stream won't trigger other notifications after a notification",
			Type = bot.ConfigType.Duration,
			Default = 30 * 60
		},
		{
			Global = true,
			Name = "SubscribeDuration",
			Description = "How long should subscriptions to a channel last before being renewed",
			Type = bot.ConfigType.Duration,
			Default = 60 * 60
		},
		{
			Global = true,
			Name = "TwitchToken",
			Description = "Twitch application token",
			Type = bot.ConfigType.String,
			Default = "",
			Sensitive = true
		}
	}
end

function Module:OnLoaded()
	-- Regenerate secret
	self.API = twitchAPI(discordia, client, self.GlobalConfig.TwitchToken)
	self.Secret = self:GenerateSecret(128)
	self.WatchedChannels = {}

	self.Clock = discordia.Clock()
	self.Clock:on("sec", function ()
		local now = os.time()
		for channelId, channelData in pairs(self.WatchedChannels) do
			if (channelData.RenewTime <= now and not channelData.Subscribing) then
				if (not table.empty(channelData.Guilds)) then
					channelData.RenewTime = now + 2*60 -- Retry in two minutes if twitch didn't answer or subscribing failed
					wrap(function () bot:CallModuleFunction(self, "SubscribeToTwitch", channelId) end)()
				else
					self.WatchedChannels[channelId] = nil
				end
			end
		end
	end)

	self.Server = self:SetupServer()
	if (not self.Server) then
		return false, "Failed to setup server"
	end

	self.Clock:start()

	self:RegisterCommand({
		Name = "twitchinfo",
		Args = {
			{Name = "channel", Type = Bot.ConfigType.String}
		},
		PrivilegeCheck = function (member) return member:hasPermission(enums.permission.administrator) end,

		Help = "Query twitch informations about a channel",
		Func = function (commandMessage, channel)
			local profileData, err = self.API:GetUserByName(channel)

			if (profileData) then
				local channelUrl = "https://www.twitch.tv/" .. profileData.login
				commandMessage:reply({
					embed = {
						title = profileData.display_name,
						description = profileData.description,
						url = channelUrl,
						author = {
							name = profileData.login,
							url = channelUrl,
							icon_url = profileData.profile_image_url
						},
						thumbnail = {
							url = profileData.profile_image_url
						},
						fields = {
							{
								name = "View count",
								value = profileData.view_count
							},
							{
								name = "Type",
								value = #profileData.broadcaster_type > 0 and profileData.broadcaster_type or "regular"
							}
						},
						image = {
							url = profileData.offline_image_url
						},
						footer = {
							text = "ID: " .. profileData.id
						}
					}
				})
			else
				if (err) then
					commandMessage:reply(string.format("An error occurred: %s", err))
				else
					commandMessage:reply(string.format("Profile `%s` not found", channel))
				end
			end
		end
	})

	return true
end

function Module:OnEnable(guild)
	local config = self:GetConfig(guild)
	for channelId,channelData in pairs(config.TwitchConfig) do
		local watchedData = self.WatchedChannels[channelId]
		if (not watchedData) then
			watchedData = {
				Guilds = {},
				LastAlert = 0,
				RenewTime = os.time(),
				Subscribed = false,
				Subscribing = false,
				WaitingForConfirm = false
			}
			self.WatchedChannels[channelId] = watchedData
		end

		watchedData.Guilds[guild.id] = channelData
	end

	return true
end

function Module:OnDisable(guild)
	local config = self:GetConfig(guild)
	for channelId,channelData in pairs(config.TwitchConfig) do
		local watchedData = self.WatchedChannels[channelId]
		if (watchedData) then
			watchedData.Guilds[guild.id] = nil
		end
	end
end

function Module:OnUnload()
	if (self.Clock) then
		self.Clock:stop()
	end

	for channelId, channelData in pairs(self.WatchedChannels) do
		if (channelData.Subscribed or channelData.WaitingForConfirm) then
			self:UnsubscribeFromTwitch(channelId)
		end
	end

	self.Server:close()
end

function Module:CreateServer(host, port, onConnect)
	return net.createServer({
    	host = host,
    	port = port,
    	encode = httpCodec.encoder(),
    	decode = httpCodec.decoder(),
  	}, function (read, write, socket)
		for head in read do
			local parts = {}
			for part in read do
				if #part > 0 then
					parts[#parts + 1] = part
				else
					break
				end
			end

			local body = table.concat(parts)
			local head, body = onConnect(head, body, socket)
			write(head)
			if body then write(body) end
			write("")
			if not head.keepAlive then break end
		end
		write() --FIXME: This should be done by coro-net
 	end)
end

local charset = {}  do -- [0-9a-zA-Z]
    for c = 48, 57  do table.insert(charset, string.char(c)) end
    for c = 65, 90  do table.insert(charset, string.char(c)) end
    for c = 97, 122 do table.insert(charset, string.char(c)) end
end

function Module:GenerateSecret(length)
	local res = ""
	for i = 1, length do
		res = res .. charset[math.random(1, #charset)]
	end

	return res
end

function Module:SetupServer()
	return self:CreateServer("127.0.0.1", self.GlobalConfig.ListenPort, function (head, body, socket)
		local Forbidden = function()
			self:LogWarning("Twitch server: Access forbidden")

			local header = {
				code = 403,
				{"Content-Type", "charset=utf-8"},
				{"Content-Length", 0}
			}

			return header, ""
		end

		local Ok = function ()
			local header = {
				code = 200,
				reason = "OK",
				{"Content-Type", "charset=utf-8"},
				{"Content-Length", 0}
			}

			return header, ""
		end

		local ServerError = function ()
			self:LogWarning("Twitch server: Server error")

			local header = {
				code = 500,
				{"Content-Type", "charset=utf-8"},
				{"Content-Length", 0}
			}

			return header, ""
		end

		-- Check signature
		local headerSignature
		for _, keyvalue in ipairs(head) do
			local key, value = unpack(keyvalue)
			if (key:lower() == "x-hub-signature") then
				headerSignature = value
				break
			end
		end

		local hasSignature = false
		if (headerSignature) then
			local hash, hashValue = string.match(headerSignature, "(%w+)=(%w+)")
			if (hash and hashValue and hash == "sha256") then
				local signature = sha256.hmac_sha256(self.Secret, body)
				if (hashValue == signature) then
					hasSignature = true
				else
					self:LogError("Twitch server: Header signature doesn't match")
					return Forbidden()
				end
			else
				self:LogError("Twitch server: Invalid header signature %s", headerSignature)
				return Forbidden()
			end
		end

		if (not hasSignature) then
			-- Decode path
			local query = head.path:match("^[^?]*%??(.*)")
			if (query) then
				local parameters = querystring.parse(query)

				local mode = parameters["hub.mode"]
				local twitchTopic = parameters["hub.topic"]
				local token = parameters["hub.challenge"]
				if (not mode or not twitchTopic or not token) then
					self:LogError("Twitch server: Invalid parameters (mode=%s, topic=%s, challenge=%s)", tostring(mode), tostring(topic), tostring(challenge))
					return Forbidden()
				end

				local channelId = twitchTopic:match("https://api%.twitch%.tv/helix/streams%?user_id=(%d+)")
				if (not channelId) then
					self:LogError("Twitch server: Invalid topic \"%s\"", tostring(twitchTopic))
					return Forbidden()
				end

				local channelData = self.WatchedChannels[channelId]
				if (not channelData) then
					-- May occurs when reloading
					if (mode == "unsubscribe") then
						return Ok()
					end

					self:LogError("Twitch server: Channel \"%s\" is not watched", tostring(channelId))
					return Forbidden()
				end

				if (mode == "subscribe") then
					local subscribeTime = parameters["hub.lease_seconds"]
					if (not subscribeTime) then
						self:LogError("Twitch server: Invalid parameter hub.lease_seconds (%s)", tostring(subscribeTime))
						return Forbidden()
					end

					self:LogInfo("Twitch server: Subscribed to %s for %s", channelId, subscribeTime)

					if (channelData.Subscribed) then
						self:LogWarning("Double subscription to %s detected", channelId)
					end

					channelData.RenewTime = os.time() + subscribeTime
					channelData.Subscribed = true
					channelData.WaitingForConfirm = false
				elseif (mode == "unsubscribe") then
					self:LogInfo("Twitch server: Unsubscribed from %s", channelId)
					channelData.RenewTime = os.time()
					channelData.Subscribed = false
					channelData.WaitingForConfirm = false
				else
					self:LogError("Twitch server: Unknown mode %s", mode)
					return ServerError()
				end

				local header = {
					code = 200,
					{"Content-Type", "charset=utf-8"},
					{"Content-Length", #token}
				}

				return header, token
			end

			return Forbidden()
		end

		local payload = json.decode(body)
		if (payload and payload.data) then
			local channelData = payload.data[1]
			if (channelData) then
				-- Channel up
				self:LogInfo("Twitch server: Channel %s went up", channelData.user_id)
				bot:CallModuleFunction(self, "HandleChannelUp", channelData)
			else
				-- Channel down
				self:LogInfo("Twitch server: A channel went down") -- And ... we have have no idea which channel is concerned, ty twitch
			end
		end

		return Ok()
	end)
end

function Module:HandleChannelUp(channelData)
	local userId = channelData.user_id
	self:LogInfo("Channel %s went up", userId)

	local watchedData = self.WatchedChannels[userId]
	if (not watchedData) then
		self:LogError("%s is not a watched channel, ignoring", userId)
		return
	end

	local now = os.time()
	if (now - watchedData.LastAlert < self.GlobalConfig.SilenceDuration) then
		self:LogInfo("Dismissed alert event because last one occured %s ago", util.FormatTime(now - watchedData.LastAlert))
		return
	end

	local startDate = discordia.Date.parseISO(channelData.started_at)
	if (watchedData.LastAlert > startDate) then
		self:LogInfo("Dismissed alert event because last one occured while the stream was active (%s ago)", util.FormatTime(now - watchedData.LastAlert))
		return
	end

	local profileData, err = self.API:GetUserById(userId)
	if (not profileData) then
		self:LogError("Failed to query user %s info: %s", userId, msg)
		return
	end

	local gameData, err = self:GetGameData(channelData.game_id)
	if (not gameData) then
		self:LogError("Failed to query game info about game %s: %s", channelData.game_id, err)
	end

	watchedData.LastAlert = now

	local title = channelData.title
	for guildId, guildPatterns in pairs(watchedData.Guilds) do
		local guild = client:getGuild(guildId)
		if (guild) then
			for _, pattern in pairs(guildPatterns) do
				if (not pattern.TitlePattern or title:match(pattern.TitlePattern)) then
					local channel = guild:getChannel(pattern.Channel)
					if (channel) then
						local message = pattern.Message
						local nonMentionableRoles = {}
						for roleId in message:gmatch("<@&(%d+)>") do
							local role = guild:getRole(roleId)
							if (role) then
								if (not role.mentionable) then
									nonMentionableRoles[roleId] = role
								end
							else
								self:LogWarning(guild, "Role %s doesn't exist", roleId)
							end
						end

						local gameName = gameData and gameData.Name or string.format("<game %s>", channelData.game_id)

						local fields = {
							display_name = profileData.display_name,
							game_name = gameName,
							title = channelData.title
						}

						message = message:gsub("{(%w+)}", fields)

						local channelUrl = "https://www.twitch.tv/" .. profileData.login
						local thumbnail = channelData.thumbnail_url .. "?" .. os.time() -- Prevent cache
						thumbnail = thumbnail:gsub("{width}", 320)
						thumbnail = thumbnail:gsub("{height}", 180)

						for roleId, role in pairs(nonMentionableRoles) do
							local success, err = role:enableMentioning()
							if (not success) then
								self:LogWarning(guild, "Failed to enable mentioning on role %s (%s): %s", roleId, role.name, err)
							end
						end

						local fields = {nil, nil, nil}
						if (gameData) then
							table.insert(fields, {
								name = "Game",
								value = gameName
							})
						end

						if (channelData.viewer_count > 0) then
							table.insert(fields, {
								name = "Viewers",
								value = channelData.viewer_count
							})
						end

						table.insert(fields, {
							name = "Started",
							value = util.FormatTime(now - startDate, 1) .. " ago"
						})

						channel:send({
							content = message,
							embed = {
								title = channelData.title,
								url = channelUrl,
								author = {
									name = profileData.login,
									url = channelUrl,
									icon_url = profileData.profile_image_url
								},
								thumbnail = {
									url = profileData.profile_image_url
								},
								fields = fields,
								image = {
									url = thumbnail
								},
								timestamp = channelData.started_at
							}
						})

						for roleId, role in pairs(nonMentionableRoles) do
							local success, err = role:disableMentioning()
							if (not success) then
								self:LogWarning(guild, "Failed to re-disable mentioning on role %s (%s): %s", roleId, role.name, err)
							end
						end
					else
						self:LogError(guild, "Channel %s doesn't exist", pattern.Channel)
					end

					break
				end
			end
		end
	end
end

function Module:GetGameData(gameId)
	local gameData = self.GameCache[gameId]
	if (not gameData) then
		local gameInfo, err = self.API:GetGameById(gameId)
		if (err) then
			return nil, err
		end

		gameData = {}
		if (gameInfo) then
			gameData.Id = gameInfo.id
			gameData.Image = gameInfo.box_art_url
			gameData.Name = gameInfo.name
		end

		self.GameCache[gameId] = gameData
	end

	return gameData
end

function Module:SubscribeToTwitch(channelId)
	self:LogInfo("Subscribing to channel %s", channelId)

	local channelData = self.WatchedChannels[channelId]
	assert(channelData)

	channelData.Subscribing = true
	channelData.WaitingForConfirm = true

	local succeeded, ret, err = pcall(function () self.API:SubscribeToStreamUpDown(channelId, self.GlobalConfig.CallbackEndpoint, self.GlobalConfig.SubscribeDuration, self.Secret) end)

	channelData.Subscribing = false

	if (not succeeded) then
		channelData.WaitingForConfirm = false
		self:LogError("An error occurred: %s", ret)
		return false, ret
	end

	return ret, err
end

function Module:UnsubscribeFromTwitch(channelId)
	self:LogInfo("Unsubscribing to channel %s", channelId)

	return self.API:UnsubscribeFromStreamUpDown(channelId, self.GlobalConfig.CallbackEndpoint)
end
