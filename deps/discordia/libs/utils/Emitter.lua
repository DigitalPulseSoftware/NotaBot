local class = require('../class')
local typing = require('../typing')
local helpers = require('../helpers')

local wrap, yield, running = coroutine.wrap, coroutine.yield, coroutine.running
local insert, remove = table.insert, table.remove
local setTimeout, clearTimer = helpers.setTimeout, helpers.clearTimer
local checkType = typing.checkType
local checkNumber = typing.checkNumber
local assertResume = helpers.assertResume

local Emitter = class('Emitter')

local meta = {
	__index = function(self, k)
		self[k] = {}
		return self[k]
	end
}

local function mark(listeners, i)
	listeners[i] = false
	listeners.marked = true
end

local function clean(listeners)
	for i = #listeners, 1, -1 do
		if not listeners[i] then
			remove(listeners, i)
		end
	end
	listeners.marked = nil
end

function Emitter:__init()
	self._listeners = setmetatable({}, meta)
end

function Emitter:on(name, fn, err)
	insert(self._listeners[checkType('string', name)], {
		fn = checkType('function', fn),
		err = err and checkType('function', err),
	})
	return fn
end

function Emitter:once(name, fn, err)
	insert(self._listeners[checkType('string', name)], {
		fn = checkType('function', fn),
		err = err and checkType('function', err),
		once = true
	})
	return fn
end

function Emitter:emit(name, ...)
	local listeners = self._listeners[checkType('string', name)]
	for i = 1, #listeners do
		local listener = listeners[i]
		if listener then
			if listener.once then
				mark(listeners, i)
			end
			if listener.err then
				local success, err = pcall(wrap(listener.fn), ...)
				if not success then
					wrap(listener.err)(err, ...)
				end
			else
				wrap(listener.fn)(...)
			end
		end
	end
	if listeners.marked then
		clean(listeners)
	end
end

function Emitter:getListeners(name)
	local listeners = self._listeners[checkType('string', name)]
	local i = 0
	return function()
		while i < #listeners do
			i = i + 1
			if listeners[i] then
				return listeners[i].fn
			end
		end
	end
end

function Emitter:getListenerCount(name)
	local listeners = self._listeners[checkType('string', name)]
	local n = 0
	for _, listener in ipairs(listeners) do
		if listener then
			n = n + 1
		end
	end
	return n
end

function Emitter:removeListener(name, fn)
	local listeners = self._listeners[checkType('string', name)]
	for i, listener in ipairs(listeners) do
		if listener and listener.fn == fn then
			mark(listeners, i)
			break
		end
	end
end

function Emitter:removeAllListeners(name)
	if name then
		self._listeners[checkType('string', name)] = nil
	else
		for k in pairs(self._listeners) do
			self._listeners[k] = nil
		end
	end
end

function Emitter:waitFor(name, timeout, predicate)

	name = checkType('string', name)
	predicate = predicate and checkType('function', predicate)

	local t, fn
	local thread = running()

	local function complete(success, ...)
		if t then
			clearTimer(t)
			t = nil
		end
		if fn then
			self:removeListener(name, fn)
			fn = nil
			return assertResume(thread, success, ...)
		end
	end

	fn = self:on(name, function(...)
		if not predicate or predicate(...) then
			return complete(true, ...)
		end
	end)

	if timeout then
		t = setTimeout(checkNumber(timeout, 10, 0), complete, false)
	end

	return yield()

end

return Emitter
