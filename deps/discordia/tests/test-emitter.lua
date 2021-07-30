local Emitter = require('../libs/utils/Emitter')
local utils = require('./utils')

local assertTrue = utils.assertTrue
local assertFalse = utils.assertFalse
local assertEqual = utils.assertEqual
local assertError = utils.assertError

local em = Emitter()

local name = 'test'

local listener1 = em:on(name, print)
assertEqual(#em:getListeners(name), 1)

local listener2 = em:on(name, print)
assertEqual(#em:getListeners(name), 2)

em:removeListener(name, listener1)
assertEqual(#em:getListeners(name), 1)

em:removeListener(name, listener2)
assertEqual(#em:getListeners(name), 0)

local listener3 = em:on(name, print)
assertEqual(#em:getListeners(name), 1)

listener3:unregister()
assertEqual(#em:getListeners(name), 0)

em:on(name, print)
em:on(name, tostring)
assertEqual(#em:getListeners(name), 2)

em:removeAllListeners(name)
assertEqual(#em:getListeners(name), 0)

em:once(name, function() end)
assertEqual(#em:getListeners(name), 1)

em:emit(name)
assertEqual(#em:getListeners(name), 0)

coroutine.wrap(function()
	assertTrue(em:waitFor(name))
end)()
em:emit(name)

coroutine.wrap(function()
	assertTrue(em:waitFor(name, 0, function(a) return a == 1 end))
end)()
em:emit(name, 1)

coroutine.wrap(function()
	assertFalse(em:waitFor(name, 0, function(a) return a == 1 end))
end)()
em:emit(name, 2)

coroutine.wrap(function()
	assertFalse(em:waitFor(name, 0))
end)()

assertError(function() return em:on() end, 'expected string, received nil')
assertError(function() return em:on(1) end, 'expected string, received number')
assertError(function() return em:on('test') end, 'expected callable, received nil')
assertError(function() return em:on('test', function() end, 'test') end, 'expected callable, received string')

assertError(function() return em:once() end, 'expected string, received nil')
assertError(function() return em:once(1) end, 'expected string, received number')
assertError(function() return em:once('test') end, 'expected callable, received nil')
assertError(function() return em:once('test', function() end, 'test') end, 'expected callable, received string')

assertError(function() return em:emit() end, 'expected string, received nil')
assertError(function() return em:emit(1) end, 'expected string, received number')

assertError(function() return em:getListeners() end, 'expected string, received nil')
assertError(function() return em:getListeners(1) end, 'expected string, received number')

assertError(function() return em:removeListener() end, 'expected string, received nil')
assertError(function() return em:removeListener(1) end, 'expected string, received number')

assertError(function() return em:removeAllListeners(1) end, 'expected string, received number')

assertError(function() return em:waitFor() end, 'expected string, received nil')
assertError(function() return em:waitFor(1) end, 'expected string, received number')
assertError(function() return em:waitFor('test', -1) end, 'expected minimum 0, received -1')
assertError(function() return em:waitFor('test', nil, 1) end, 'expected function, received number')
