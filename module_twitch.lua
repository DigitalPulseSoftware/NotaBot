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
Module.ProfileCache = {}

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
			Name = "TwitchClientId",
			Description = "Twitch application client id",
			Type = bot.ConfigType.String,
			Default = "",
			Sensitive = true
		},
		{
			Global = true,
			Name = "TwitchClientSecret",
			Description = "Twitch application secret",
			Type = bot.ConfigType.String,
			Default = "",
			Sensitive = true
		}
	}
end

function Module:GetWatchedChannels()
	local persistentData = self:GetPersistentData(nil)
	persistentData.watchedChannels = persistentData.watchedChannels or {}

	return persistentData.watchedChannels
end

function Module:OnLoaded()
	self.API = twitchAPI(discordia, client, self.GlobalConfig.TwitchClientId, self.GlobalConfig.TwitchClientSecret)

	local secretLifespan = 24 * 60 * 60

	self.ChannelAlerts = {}
	self.Secret = self:GenerateSecret(128)
	self.SecretTimeout = os.time() + secretLifespan

	for channelId, channelData in pairs(self:GetWatchedChannels()) do
		channelData.Guilds = nil -- Was removed in a previous version (replaced by self.ChannelAlerts)
		channelData.Subscribing = false
		channelData.WaitingForConfirm = false
	end

	self.Clock = discordia.Clock()
	self.Clock:on("sec", function ()
		local watchedChannels = self:GetWatchedChannels()

		local now = os.time()
		if (now >= self.SecretTimeout) then
			self.Secret = self:GenerateSecret(128)
			self.SecretTimeout = now + secretLifespan
		end

		for channelId, channelData in pairs(watchedChannels) do
			if (channelData.RenewTime <= now and not channelData.Subscribing) then
				local channelAlerts = self.ChannelAlerts[channelId]
				if (channelAlerts and not table.empty(channelAlerts)) then
					channelData.RenewTime = now + 2*60 -- Retry in two minutes if twitch didn't answer or subscribing failed
					wrap(function () bot:CallModuleFunction(self, "SubscribeToTwitch", channelId) end)()
				else
					watchedChannels[channelId] = nil
					self.ChannelAlerts[channelId] = nil
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
			local profileData, err
			if (channel:match("^%d+$")) then
				profileData, err = self.API:GetUserById(channel)
			else
				profileData, err = self.API:GetUserByName(channel)
			end

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

	self:RegisterCommand({
		Name = "twitchgameinfo",
		Args = {
			{Name = "channel", Type = Bot.ConfigType.String}
		},
		PrivilegeCheck = function (member) return member:hasPermission(enums.permission.administrator) end,

		Help = "Query twitch informations about a game",
		Func = function (commandMessage, channel)
			local gameData, err
			if (channel:match("^%d+$")) then
				gameData, err = self.API:GetGameById(channel)
			else
				gameData, err = self.API:GetGameByName(channel)
			end

			if (gameData) then
				local thumbnail = gameData.box_art_url
				thumbnail = thumbnail:gsub("{width}", 285)
				thumbnail = thumbnail:gsub("{height}", 380)

				commandMessage:reply({
					embed = {
						title = gameData.name,
						image = {
							url = thumbnail
						},
						footer = {
							text = "ID: " .. gameData.id
						}
					}
				})
			else
				if (err) then
					commandMessage:reply(string.format("An error occurred: %s", err))
				else
					commandMessage:reply(string.format("Game `%s` not found", channel))
				end
			end
		end
	})

	self:RegisterCommand({
		Name = "twitchstream",
		Args = {
			{Name = "channel", Type = Bot.ConfigType.String}
		},
		PrivilegeCheck = function (member) return member:hasPermission(enums.permission.administrator) end,

		Help = "Query twitch informations about a game",
		Func = function (commandMessage, channel)
			local channelData, err
			if (channel:match("^%d+$")) then
				channelData, err = self.API:GetStreamByUserId(channel)
			else
				channelData, err = self.API:GetStreamByUserName(channel)
			end

			if (channelData) then
				bot:CallModuleFunction(self, "SendChannelNotification", commandMessage.guild, channel, "", channelData)
			else
				if (err) then
					commandMessage:reply(string.format("An error occurred: %s", err))
				else
					commandMessage:reply(string.format("Stream `%s` not found", channel))
				end
			end
		end
	})

	return true
end

function Module:OnEnable(guild)
	local watchedChannels = self:GetWatchedChannels()

	local config = self:GetConfig(guild)
	for channelId,channelData in pairs(config.TwitchConfig) do
		local watchedData = watchedChannels[channelId]
		if (not watchedData) then
			watchedData = {
				LastAlert = 0,
				RenewTime = os.time(),
				Subscribed = false,
				Subscribing = false,
				WaitingForConfirm = false
			}
			watchedChannels[channelId] = watchedData
		end

		local channelAlerts = self.ChannelAlerts[channelId]
		if (not channelAlerts) then
			channelAlerts = {}
			self.ChannelAlerts[channelId] = channelAlerts
		end

		channelAlerts[guild.id] = channelData
	end

	return true
end

function Module:OnDisable(guild)
	local watchedChannels = self:GetWatchedChannels()

	local config = self:GetConfig(guild)
	for channelId,channelData in pairs(config.TwitchConfig) do
		local channelAlerts = self.ChannelAlerts[channelId]
		if (channelAlerts) then
			channelAlerts[guild.id] = nil
		end
	end
end

function Module:OnUnload()
	if (self.Clock) then
		self.Clock:stop()
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

		-- If we have a signature, then a channel came up, else it's twitch checking
		if (headerSignature) then
			local hash, hashValue = string.match(headerSignature, "(%w+)=(%w+)")
			if (hash and hashValue and hash == "sha256") then
				headerSignature = hashValue
			else
				self:LogError("Twitch server: Invalid header signature %s", headerSignature)
				return Forbidden()
			end

			local payload = json.decode(body)
			if (payload and payload.data) then
				local channelData = payload.data[1]
				if (channelData) then
					-- Channel up
					self:LogInfo("Twitch server: Channel %s went up", channelData.user_id)
					bot:CallModuleFunction(self, "HandleChannelUp", channelData, headerSignature, body)
				else
					-- Channel down
					self:LogInfo("Twitch server: A channel went down") -- And ... we have have no idea which channel is concerned, ty twitch
				end
			end
	
			return Ok()
		else
			-- Decode path
			local query = head.path:match("^[^?]*%??(.*)")
			if (query) then
				local parameters = querystring.parse(query)

				local mode = parameters["hub.mode"]
				local twitchTopic = parameters["hub.topic"]
				local token = parameters["hub.challenge"]
				if (not mode or not twitchTopic or not token) then
					self:LogError("Twitch server: Invalid parameters (mode=%s, topic=%s, challenge=%s)", tostring(mode), tostring(twitchTopic), tostring(token))
					return Forbidden()
				end

				local channelId = twitchTopic:match("https://api%.twitch%.tv/helix/streams%?user_id=(%d+)")
				if (not channelId) then
					self:LogError("Twitch server: Invalid topic \"%s\"", tostring(twitchTopic))
					return Forbidden()
				end

				local watchedChannels = self:GetWatchedChannels()

				local channelData = watchedChannels[channelId]
				if (not channelData or not channelData.WaitingForConfirm) then
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
	end)
end

function Module:HandleChannelUp(channelData, headerSignature, body)
	local channelId = channelData.user_id
	local title = channelData.title
	local gameId = channelData.game_id

	local watchedChannels = self:GetWatchedChannels()

	local watchedData = watchedChannels[channelId]
	if (not watchedData) then
		self:LogError("%s is not a watched channel, ignoring...", channelId)
		return
	end

	local channelAlerts = self.ChannelAlerts[channelId]
	if (not channelAlerts) then
		self:LogError("%s has no active alerts, ignoring...", channelId)
		return
	end

	-- Ensure Twitch has sent this
	if (headerSignature) then
		assert(watchedData.Secret)
		local signature = sha256.hmac_sha256(watchedData.Secret, body)
		if (headerSignature ~= signature) then
			self:LogError("Header signature doesn't match")
			return
		end
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

	watchedData.LastAlert = now

	for guildId, guildPatterns in pairs(channelAlerts) do
		local guild = client:getGuild(guildId)
		if (guild) then
			local function CheckPattern(pattern)
				if (pattern.TitlePattern) then
					if (not title:match(pattern.TitlePattern)) then
						return false
					end
				end

				if (pattern.AllowedGames) then
					if (not table.search(pattern.AllowedGames, gameId)) then
						return false
					end
				elseif (pattern.ForbiddenGames) then
					if (table.search(pattern.ForbiddenGames, gameId)) then
						return false
					end
				end

				return true
			end

			for _, pattern in pairs(guildPatterns) do
				if (CheckPattern(pattern)) then
					local channel = guild:getChannel(pattern.Channel)
					if (channel) then
						bot:CallModuleFunction(self, "SendChannelNotification", guild, channel, pattern.Message, channelData)
					else
						self:LogError(guild, "Channel %s doesn't exist", pattern.Channel)
					end

					break
				end
			end
		end
	end
end

function Module:GetProfileData(userId)
	local now = os.time()

	local profileData = self.ProfileCache[userId]
	if (not profileData or now - profileData.CachedAt > 3600) then
		local userInfo, err = self.API:GetUserById(userId)
		if (err) then
			return nil, err
		end

		profileData = {}
		if (userInfo) then
			profileData.CachedAt = now
			profileData.DisplayName = userInfo.display_name
			profileData.Name = userInfo.login
			profileData.Image = userInfo.profile_image_url
		end

		self.ProfileCache[userId] = profileData
	end

	return profileData
end

function Module:GetGameData(gameId)
	local now = os.time()

	local gameData = self.GameCache[gameId]
	if (not gameData or now - gameData.CachedAt > 3600) then
		local gameInfo, err = self.API:GetGameById(gameId)
		if (err) then
			return nil, err
		end

		gameData = {}
		if (gameInfo) then
			gameData.CachedAt = now
			gameData.Id = gameInfo.id
			gameData.Image = gameInfo.box_art_url
			gameData.Name = gameInfo.name
		end

		self.GameCache[gameId] = gameData
	end

	return gameData
end

function Module:SendChannelNotification(guild, channel, message, channelData)
	local profileData, err = self:GetProfileData(channelData.user_id)
	if (not profileData) then
		self:LogError("Failed to query user %s info: %s", channelData.user_id, err)
		return
	end

	local gameData, err = self:GetGameData(channelData.game_id)
	if (not gameData) then
		self:LogError("Failed to query game info about game %s: %s", channelData.game_id, err)
	end

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
		display_name = profileData.DisplayName,
		game_name = gameName,
		title = channelData.title
	}

	message = message:gsub("{(%w+)}", fields)

	local channelUrl = "https://www.twitch.tv/" .. profileData.Name
	local thumbnail = channelData.thumbnail_url .. "?" .. os.time() -- Prevent Discord cache
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

	local now = os.time()
	local startDate = discordia.Date.parseISO(channelData.started_at)

	table.insert(fields, {
		name = "Started",
		value = util.FormatTime(now - startDate, 1) .. " ago"
	})

	local success, err = channel:send({
		content = message,
		embed = {
			title = channelData.title,
			url = channelUrl,
			author = {
				name = profileData.Name,
				url = channelUrl,
				icon_url = profileData.Image
			},
			thumbnail = {
				url = profileData.Image
			},
			fields = fields,
			image = {
				url = thumbnail
			},
			timestamp = channelData.started_at
		}
	})

	if (not success) then
		self:LogError(guild, "Failed to send twitch notification message: %s", err)
	end

	for roleId, role in pairs(nonMentionableRoles) do
		local success, err = role:disableMentioning()
		if (not success) then
			self:LogWarning(guild, "Failed to re-disable mentioning on role %s (%s): %s", roleId, role.name, err)
		end
	end
end

function Module:SubscribeToTwitch(channelId)
	self:LogInfo("Subscribing to channel %s", channelId)

	local watchedChannels = self:GetWatchedChannels()

	local channelData = watchedChannels[channelId]
	assert(channelData)

	channelData.Subscribing = true
	channelData.WaitingForConfirm = true

	local secret = self.Secret
	channelData.Secret = secret

	local succeeded, ret, err = pcall(function () self.API:SubscribeToStreamUpDown(channelId, self.GlobalConfig.CallbackEndpoint, self.GlobalConfig.SubscribeDuration, secret) end)

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
