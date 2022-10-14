local Snowflake = require('containers/abstract/Snowflake')
local json = require('json')

local format = string.format
local null = json.null

local Interaction, get = require('class')('Interaction', Snowflake)

function Interaction:__init(data, parent)
	Snowflake.__init(self, data, parent)

	self._data = data.data
	if data.guild_id then
		self._guild = self.client._guilds:get(data.guild_id)
		if self._guild then
			self._member = self._guild._members:_insert(data.member)
			self._channel = self._guild._text_channels:get(data.channel_id) or self._guild._voice_channels:get(data.channel_id)
		end
	else
		self._user = self.client._users:_insert(data.user)
		self._channel = client._private_channels:get(id) or client._group_channels:get(id)
	end

	if self._channel and data.message then
		self._message = self._channel._messages:_insert(data.message)
	end
end



function Interaction:respond(payload)
	return self.client._api:createInteractionResponse(self.id, self.token, payload)
end

function Interaction:getResponse()
	return self.client._api:getOriginalInteractionResponse(self.applicationId, self.token)
end

function Interaction:editResponse(payload)
	return self.client._api:editOriginalInteractionResponse(self.applicationId, self.token, payload)
end

function Interaction:deleteResponse()
	return self.client._api:deleteOriginalInteractionResponse(self.applicationId, self.token)
end

function Interaction:createFollowup(payload)
	return self.client._api:createFollowupMessage(self.applicationId, self.token, payload)
end

function Interaction:editFollowup(messageId, payload)
	return self.client._api:editFollowupMessage(self.applicationId, self.token, messageId, payload)
end

function Interaction:deleteFollowup(messageId)
	return self.client._api:deleteFollowupMessage(self.applicationId, self.token, messageId)
end

function get:applicationId()
	return self._application_id
end

function get:type()
	return self._type
end

function get:data()
	return self._data
end

function get:guild()
	return self._guild
end

function get:channel()
	return self._channel
end

function get:member()
	return self._member
end

function get:user()
	return self._user
end

function get:token()
	return self._token
end

function get:version()
	return self._version
end

function get:message()
	return self._message
end

return Interaction
