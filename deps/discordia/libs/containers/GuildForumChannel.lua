--[=[
@c GuildForumChannel x GuildChannel
@d Represents a forum in a Discord guild, used to create exclusively threads
]=]

local GuildChannel = require('containers/abstract/GuildChannel')
local FilteredIterable = require('iterables/FilteredIterable')
local enums = require('enums')

local channelType = enums.channelType

local GuildForumChannel, get = require('class')('GuildForumChannel', GuildChannel)

function GuildForumChannel:__init(data, parent)
	GuildChannel.__init(self, data, parent)
end

return GuildForumChannel
