-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local http = require("coro-http")
local json = require("json")
local querystring = require("querystring")
local timer = require("timer")

local decode, encode = json.decode, json.encode
local insert = table.insert
local max, random = math.max, math.random
local ipairs = ipairs
local request = http.request
local resume = coroutine.resume
local running = coroutine.running
local setTimeout = timer.setTimeout
local sleep = timer.sleep
local tostring = tostring
local urlencode = querystring.urlencode
local yield = coroutine.yield

local endpoints = {
	GetGames   = "https://api.twitch.tv/helix/games",
	GetUsers   = "https://api.twitch.tv/helix/users",
	WebhookSub = "https://api.twitch.tv/helix/webhooks/hub"
}


function tprint (tbl, indent)
  if not indent then indent = 0 end
  for k, v in pairs(tbl) do
    formatting = string.rep("  ", indent) .. k .. ": "
    if type(v) == "table" then
      print(formatting)
      tprint(v, indent+1)
    elseif type(v) == 'boolean' then
      print(formatting .. tostring(v))
    else
      print(formatting .. v)
    end
  end
end

local TwitchApi = {}
TwitchApi.__index = TwitchApi

function TwitchApi:__init(discordia, client, appId, appSecret)
	self._client = client
	self._discordia = discordia
	self._clientId = appId
	self._clientSecret = appSecret
	self._isRequesting = false
	self._waitingCoroutines = {}
end

function TwitchApi:Authenticate()
	local parameters = {
		client_id = self._clientId,
		client_secret = self._clientSecret,
		grant_type = "client_credentials"
	}

	local success, headerOrErr, body = pcall(http.request, "POST", "https://id.twitch.tv/oauth2/token", {{"Content-Type", "application/x-www-form-urlencoded"}}, querystring.stringify(parameters))
	if (not success) then
		print("Failed to request Twitch Token (is network down?): " .. headerOrErr)
		return false, "NetworkError"
	end

	if (headerOrErr.code < 200 or headerOrErr.code > 299) then
		p(body)
		print("Failed to request Twitch Token (are credentials still valid?) (code " .. headerOrErr.code .. ")")
		return false, body
	end

	local tokenData = assert(json.decode(body))

	self.token = {
		accessToken = tokenData.access_token,
		expirationTime = os.time() + tonumber(tokenData.expires_in),
		tokenType = tokenData.token_type
	}

	-- Twitch, vous êtes des baltringues nucléaires
	self.token.tokenType = self.token.tokenType:sub(1, 1):upper() .. self.token.tokenType:sub(2)

	return true
end

function TwitchApi:Commit(method, url, headers, body, retries, forceAuth)
	if (forceAuth or not self.token or os.time() > self.token.expirationTime) then
		local success, err = self:Authenticate()
		if (not success) then
			error("Twitch authentication failed: " .. err)
		end
	end

	headers = headers or {}
	-- Discard authorization header if any
	for k, header in pairs(headers) do
		if (header[1]:lower() == "authorization") then
			headers[k] = nil
		end
	end
	insert(headers, {"Authorization", self.token.tokenType .. " " .. self.token.accessToken})

	local success, res, msg = pcall(request, method, url, headers, body)
	if (not success) then
		self._client:error("Request failed : %s %s", method, url)
		return nil, res, 100
	end

	for i, v in ipairs(res) do
		res[string.lower(v[1])] = v[2]
		res[i] = nil
	end

	local reset = res["ratelimit-reset"]
	local remaining = res["ratelimit-remaining"]

	local delay = 0 -- ?
	if (reset and remaining == "0") then
		local dt = os.difftime(reset, self._discordia.Date.parseHeader(res["date"]))
		delay = max(dt * 1000, delay)
	end

	local contentType = res["content-type"]
	local data = (contentType and contentType:find("application/json")) and decode(msg) or msg

	if (res.code < 300) then
		self._client:info("%i - %s : %s %s", res.code, res.reason, method, url)
		return data, nil, delay
	else
		local maxRetries = 5
		local retry
		if (res.code == 429) then -- Too Many Requests
			retry = retries < maxRetries
		elseif (res.code >= 500) then -- Server error
			delay = delay + random(2000)
			retry = retries < maxRetries
		elseif (res.code == 401) then -- Token error
			delay = 100
			retry = retries < maxRetries
			forceAuth = true
		end

		if (retry) then
			self._client:warning("%i - %s : retrying after %i ms : %s %s", res.code, res.reason, delay, method, url)
			sleep(delay)
			return self:Commit(method, url, headers, body, retries + 1, forceAuth)
		end

		self._client:error('%i - %s : %s %s', res.code, res.reason, method, url)
		return nil, msg, delay
	end
end

function TwitchApi:Request(method, endpoint, parameters, headers)
	headers = headers or {}

	local body
	if (parameters and not table.empty(parameters)) then
		if (method == "GET") then
			local url = {endpoint}
			for k, v in pairs(parameters) do
				insert(url, #url == 1 and '?' or '&')
				insert(url, urlencode(k))
				insert(url, '=')
				insert(url, urlencode(v))
			end

			endpoint = table.concat(url)
		elseif (method == "POST") then
			body = encode(parameters)

			insert(headers, {"Content-Type", "application/json; charset=utf-8"})
			insert(headers, {"Content-Length", #body})
		else
			error("Invalid method " .. method)
		end
	end

	self:Lock()

	local succeeded, data, err, delay = pcall(function () return self:Commit(method, endpoint, headers, body, 0) end)

	self:Unlock(delay)

	if (not succeeded) then
		return nil, data
	end

	if (data) then
		return data
	else
		return nil, err
	end
end

function TwitchApi:Lock()
	if (self._isRequesting) then
		local co = running()
		insert(self._waitingCoroutines, co)
		yield(co)
	end

	self._isRequesting = true
end

function TwitchApi:Unlock()
	if (#self._waitingCoroutines > 0) then
		local co = table.remove(self._waitingCoroutines, 1)
		assert(resume(co))
	else
		self._isRequesting = false
	end
end

local unlock = TwitchApi.Unlock
function TwitchApi:UnlockAfter(delay)
	setTimeout(delay, unlock, self)
end

function TwitchApi:GetGameById(gameId)
	local body, err = self:Request("GET", endpoints.GetGames, {id = gameId})
	if (body and body.data) then
		return body.data[1]
	else
		return nil, err
	end
end

function TwitchApi:GetUserById(userId)
	local body, err = self:Request("GET", endpoints.GetUsers, {id = userId})
	if (body and body.data) then
		return body.data[1]
	else
		return nil, err
	end
end

function TwitchApi:GetUserByName(userName)
	local body, err = self:Request("GET", endpoints.GetUsers, {login = userName})
	if (body and body.data) then
		return body.data[1]
	else
		return nil, err
	end
end

function TwitchApi:SubscribeTo(topic, callback, duration, secret)
	local parameters = {
		["hub.callback"] = callback,
		["hub.mode"] = "subscribe",
		["hub.topic"] = topic,
		["hub.lease_seconds"] = tostring(duration),
		["hub.secret"] = secret
	}

	return self:Request("POST", endpoints.WebhookSub, parameters)
end

function TwitchApi:SubscribeToStreamUpDown(userId, callback, duration, secret)
	return self:SubscribeTo("https://api.twitch.tv/helix/streams?user_id=" .. userId, callback, duration, secret)
end

function TwitchApi:UnsubscribeFrom(topic, callback)
	local parameters = {
		["hub.callback"] = callback,
		["hub.mode"] = "unsubscribe",
		["hub.topic"] = topic
	}

	return self:Request("POST", endpoints.WebhookSub, parameters)
end

function TwitchApi:UnsubscribeFromStreamUpDown(userId, callback)
	return self:UnsubscribeFrom("https://api.twitch.tv/helix/streams?user_id=" .. userId, callback)
end

function TwitchApi:__tostring()
	return "TwitchApi"
end

return setmetatable({}, {
	__call = function (self, ...)
		local o = {}
		setmetatable(o, TwitchApi)
		o:__init(...)

		return o
	end,
	__newindex = function (o, key, val)
		error("Writing is prohibited")
	end,
	__tostring = function ()
		return "TwitchApi"
	end
})
