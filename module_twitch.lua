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
local timer = require("timer")
local twitchAPI = require('./twitchapi.lua')

function Module:GetConfigTable()
	return {
		{
			Name = "TwitchConfig",
			Description = "List of watched channels with title patterns for messages to post on channel goes up",
			Type = bot.ConfigType.Custom,
			Default = {},
			ValidateConfig = function (value)
				if (type(value) ~= "table" or #value ~= 0) then
					return false, "TwitchConfig must be an object"
				end

				for channelId, notificationData in pairs(value) do
					if (not util.ValidateSnowflake(channelId)) then
						return false, "TwitchConfig keys must be channel snowflakes"
					end

					if (type(notificationData) ~= "table" or #notificationData ~= table.count(notificationData)) then
						return false, "TwitchConfig[" .. channelId .. "] must be an array"
					end

					for i, channelData in pairs(notificationData) do
						local hasChannel = false
						local hasMessage = false

						for fieldName, fieldValue in pairs(channelData) do
							if (fieldName == "AllowedGames") then
								if (type(fieldValue) ~= "table" or #fieldValue ~= table.count(fieldValue)) then
									return false, "TwitchConfig[" .. channelId .. "][" .. i .. "]." .. fieldName .. " must be an array"
								end

								for i, value in pairs(fieldValue) do
									if (type(value) ~= "number" or math.floor(value) ~= value) then
										return false, "TwitchConfig[" .. channelId .. "][" .. i .. "]." .. fieldName .. "[" .. i .. "] is not an integer"
									end
								end
							elseif (fieldName == "Channel") then
								if (not util.ValidateSnowflake(fieldValue)) then
									return false, "TwitchConfig[" .. channelId .. "][" .. i .. "]." .. fieldName .. " must be a channel snowflake"
								end

								hasChannel = true
							elseif (fieldName == "Message") then
								if (type(fieldValue) ~= "string") then
									return false, "TwitchConfig[" .. channelId .. "][" .. i .. "]." .. fieldName .. " must be a string"
								end

								hasMessage = true
							elseif (fieldName == "TitlePattern") then
								if (type(fieldValue) ~= "string") then
									return false, "TwitchConfig[" .. channelId .. "][" .. i .. "]." .. fieldName .. " must be a string"
								end
							elseif (fieldName == "ShouldCreateDiscordEvent") then
								if (type(fieldValue) ~= "boolean") then
									return false, "TwitchConfig[" .. channelId .. "][" .. i .. "]." .. fieldName .. " must be a boolean"
								end
							elseif (fieldName == "CreateDiscordEventDuration") then
								if (type(fieldValue) ~= "number") then
									return false, "TwitchConfig[" .. channelId .. "][" .. i .. "]." .. fieldName .. " must be a number"
								end
							else
								return false, "TwitchConfig[" .. channelId .. "][" .. i .. "]." .. fieldName .. " is not a valid field"
							end
						end

						if (not hasChannel) then
							return false, "TwitchConfig[" .. channelId .. "][" .. i .. "] is lacking a Channel field"
						end

						if (not hasMessage) then
							return false, "TwitchConfig[" .. channelId .. "][" .. i .. "] is lacking a Message field"
						end
					end
				end
		
				return true
			end
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

	for channelId, channelData in pairs(self:GetWatchedChannels()) do
		channelData.WaitingForConfirm = false
	end

	self.Clock = discordia.Clock()
	self.Clock:on("sec", function ()
		local watchedChannels = self:GetWatchedChannels()

		local now = os.time()
		for channelId, channelData in pairs(watchedChannels) do
			if (channelData.RenewTime <= now and not channelData.Subscribed) then
				local channelAlerts = self.ChannelAlerts[channelId]
				if (channelAlerts and not table.empty(channelAlerts)) then
					channelData.RenewTime = now + 30 -- Retry in 30 seconds if twitch didn't answer or subscribing failed
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

		Help = "Query twitch informations about a ongoing stream",
		Func = function (commandMessage, channel)
			local channelData, err
			if (channel:match("^%d+$")) then
				channelData, err = self.API:GetStreamByUserId(channel)
			else
				channelData, err = self.API:GetStreamByUserName(channel)
			end

			if (channelData) then
				bot:CallModuleFunction(self, "SendChannelNotification", commandMessage.guild, commandMessage.channel, "", channelData)
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
	local config = self:GetConfig(guild)
	self:HandleConfig(guild, config)

	return true
end

function Module:HandleConfig(guild, config)
	local watchedChannels = self:GetWatchedChannels()

	-- Remove all alerts for this guild before reapplying them
	for channelId, channelAlerts in pairs(self.ChannelAlerts) do
		channelAlerts[guild.id] = nil
	end

	for channelId,channelData in pairs(config.TwitchConfig) do
		local watchedData = watchedChannels[channelId]
		if (not watchedData) then
			watchedData = {
				LastAlert = 0,
				RenewTime = os.time(),
				Subscribed = false,
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
end

function Module:HandleConfigUpdate(guild, config, configName)
	if (not configName or configName == "TwitchConfig") then
		self:HandleConfig(guild, config)
	end
end

function Module:OnDisable(guild)
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
		encoder = httpCodec.encoder,
		decoder = httpCodec.decoder,
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
		local headers = {}
		for _, keyvalue in ipairs(head) do
			local key, value = unpack(keyvalue)
			headers[key:lower()] = value
		end

		local messageType = headers["twitch-eventsub-message-type"]
		local headerSignature = headers["twitch-eventsub-message-signature"]
		local subscriptionType = headers["twitch-eventsub-subscription-type"]

		-- Check signature to ensure it's coming from twitch
		if (not messageType) then
			self:LogError("Twitch Server: no message type")
			return Forbidden()
		end

		if (not headerSignature) then
			self:LogError("Twitch Server: no message signature")
			return Forbidden()
		end

		-- Check hash
		local hash, hashValue = string.match(headerSignature, "(%w+)=(%w+)")
		if (not hash or not hashValue or hash ~= "sha256") then
			self:LogError("Twitch server: Invalid header signature %s", headerSignature)
			return Forbidden()
		end

		local payload = json.decode(body)

		-- Retrieve user id from subscription data
		local userId = assert(payload.subscription.condition.broadcaster_user_id)

		local watchedChannels = self:GetWatchedChannels()
		local channelData = watchedChannels[userId]
		if (not channelData) then
			self:LogError("%s is not a watched channel, ignoring...", userId)
			return Forbidden()
		end

		local hmacMessage = assert(headers["twitch-eventsub-message-id"])
						 .. assert(headers["twitch-eventsub-message-timestamp"])
						 .. body

		assert(channelData.Secret)
		local signature = sha256.hmac_sha256(channelData.Secret, hmacMessage)
		if (hashValue ~= signature) then
			self:LogError("Hash doesn't match")
			return Forbidden()
		end

		-- Okay message is from Twitch, handle it
		if (messageType == "notification") then
			self:LogInfo("Twitch server: Received %s notification for channel %s", subscriptionType, userId)
			coroutine.wrap(function()
				bot:CallModuleFunction(self, "HandleChannelNotification", userId, channelData, subscriptionType, payload.event)
			end)()
		elseif (messageType == "webhook_callback_verification") then
			self:LogInfo("Twitch server: Subscribed to %s for channel %s", subscriptionType, userId)

			if (not channelData.WaitingForConfirm) then
				self:LogError("Twitch server: Channel \"%s\" is not waiting for Twitch confirmation", tostring(userId))
				return Forbidden()
			end

			channelData.Subscribed = true
			channelData.WaitingForConfirm = false

			local challenge = payload.challenge

			local header = {
				code = 200,
				{"Content-Type", "charset=utf-8"},
				{"Content-Length", #challenge}
			}

			return header, challenge
		elseif (messageType == "revocation") then
			self:LogInfo("Twitch server: Unsubscribed from %s for channel %s", subscriptionType, channelId)
			channelData.RenewTime = os.time()
			channelData.Subscribed = false
			channelData.WaitingForConfirm = false
			channelData.ChannelUpEventId = nil
		else
			self:LogError("Twitch server: Unknown messageType %s", messageType)
			return ServerError()
		end

		return Ok()
	end)
end

function Module:HandleChannelNotification(channelId, channelData, type, eventData)
	if (type == "stream.online") then
		local channelAlerts = self.ChannelAlerts[channelId]
		if (not channelAlerts) then
			self:LogError("%s has no active alerts, ignoring...", channelId)
			return
		end
	
		local now = os.time()
		if (now - channelData.LastAlert < self.GlobalConfig.SilenceDuration) then
			self:LogInfo("Dismissed alert event because last one occured %s ago", util.FormatTime(now - channelData.LastAlert))
			return
		end
	
		local startDate = discordia.Date.parseISO(eventData.started_at)
		if (channelData.LastAlert > startDate) then
			self:LogInfo("Dismissed alert event because last one occured while the stream was active (%s ago)", util.FormatTime(now - channelData.LastAlert))
			return
		end

		-- There may be a race condition between Twitch notifying a stream started and stream info fetching, try multiple times with a small delay
		local streamData, err
		for i=1,10 do
			self:LogInfo("trying to retrieve stream info for %s (attempt %d/10)", channelId, i)
			streamData, err = self.API:GetStreamByUserId(channelId)
			if (streamData) then
				break
			else
				if (err) then
					self:LogError("couldn't retrieve stream info for %s: %s", channelId, err.msg)
				end
				timer.sleep(1000)
			end
		end

		if (not streamData) then
			return
		end
	
		channelData.LastAlert = now

		local title = streamData.title
		local gameId = streamData.game_id

		for guildId, guildPatterns in pairs(channelAlerts) do
			local guild = client:getGuild(guildId)
			if (guild) then
				local function CheckPattern(pattern)
					if (pattern.TitlePattern) then
						if (not title:match(pattern.TitlePattern)) then
							return false
						end
					end
	
					local function tablesearchstr(tab, val)
						for k,v in pairs(tab) do
							if (tostring(v) == val) then
								return true
							end
						end
	
						return false
					end
	
					if (pattern.AllowedGames) then
						if (not tablesearchstr(pattern.AllowedGames, gameId)) then
							return false
						end
					elseif (pattern.ForbiddenGames) then
						if (tablesearchstr(pattern.ForbiddenGames, gameId)) then
							return false
						end
					end
	
					return true
				end

				if(pattern.ShouldCreateDiscordEvent) then
					local duration = pattern.CreateDiscordEventDuration or 3600

					guild:createScheduledEvents({
						entity_type = enums.scheduledEventsEntityTypes.external,
						entity_metadata = {
							location = string.format("https://twitch.tv/%s", channelId)
						},
						name = title,
						privacy_level = enums.scheduledEventsPrivacyLevel.guild_only,
						scheduled_start_time = os.date("!%Y-%m-%dT%TZ", os.time() + 1),
						scheduled_end_time = os.date("!%Y-%m-%dT%TZ", os.time() + duration),
					})
				end

				for _, pattern in pairs(guildPatterns) do
					if (CheckPattern(pattern)) then
						local channel = guild:getChannel(pattern.Channel)
						if (channel) then
							bot:CallModuleFunction(self, "SendChannelNotification", guild, channel, pattern.Message, streamData)
						else
							self:LogError(guild, "Channel %s doesn't exist", pattern.Channel)
						end
	
						break
					end
				end
			end
		end
	else
		self:LogWarning("unexpected event %s for channel %s", type, channelId)
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
		self:LogError("Failed to query user %s info: %s", channelData.user_id, err.msg)
		return
	end

	local gameData, err = self:GetGameData(channelData.game_id)
	if (not gameData) then
		self:LogError("Failed to query game info about game %s: %s", channelData.game_id, err.msg)
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

	message = message:gsub("{([%w_]+)}", {
		display_name = profileData.DisplayName,
		game_name = gameName,
		title = channelData.title
	})

	local channelUrl = "https://www.twitch.tv/" .. profileData.Name
	local thumbnail = channelData.thumbnail_url .. "?" .. os.time() -- Bypass Discord image caching
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
		value = util.DiscordRelativeTimestamp(startDate)
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

	if (channelData.ChannelUpEventId) then
		self:UnsubscribeFromTwitch(channelId)
	end

	channelData.WaitingForConfirm = true

	channelData.Secret = self:GenerateSecret(32)

	local succeeded, ret, err = pcall(function () return self.API:SubscribeToStreamUp(channelId, self.GlobalConfig.CallbackEndpoint, channelData.Secret) end)

	if (not succeeded or not ret) then
		channelData.WaitingForConfirm = false
		if (err.code == 409) then -- conflict, this subscription already exists
			self:LogInfo("subscription already exist")
			-- Try to remove subscription
			local subscriptions, err = self.API:ListSubscriptions()
			if (not subscriptions) then
				self:LogError("failed to list current subscriptions: %s", err.msg)
				return false, err.msg
			end

			for _, subscription in pairs(subscriptions.data) do
				if (subscription.condition.broadcaster_user_id == channelId) then
					self.API:Unsubscribe(subscription.id)
					break
				end
			end

			-- Try again
			return
		end

		self:LogError("An error occurred: %s", err.msg)
		return false, err.msg
	end

	channelData.ChannelUpEventId = ret.data.id

	return ret, err
end

function Module:UnsubscribeFromTwitch(channelId)
	local channelData = watchedChannels[channelId]
	if (channelData and channelData.ChannelUpEventId) then
		self:LogInfo("Unsubscribing from channel %s", channelId)

		return self.API:Unsubscribe(channelData.ChannelUpEventId)
	end
end
