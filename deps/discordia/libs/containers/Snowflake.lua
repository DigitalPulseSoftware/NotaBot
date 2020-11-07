local Container = require('./Container')
local Date = require('../utils/Date')

local class = require('../class')

local Snowflake, get = class('Snowflake', Container)

function Snowflake:__init(data, client)
	Container.__init(self, client)
	self._id = data.id
end

function Snowflake:__eq(other)
	return self.id == other.id
end

function Snowflake:getDate()
	return Date.fromSnowflake(self.id)
end

function get:id()
	return self._id
end

return Snowflake
