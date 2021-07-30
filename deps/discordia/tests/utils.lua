local helpers = require('../libs/helpers')

local f = string.format

local function assertEqual(a, b)
	if a ~= b then
		return error(f('%s ~= %s', a, b))
	end
end

local function assertTrue(v)
	return assertEqual(v, true)
end

local function assertFalse(v)
	return assertEqual(v, false)
end

local function assertNil(v)
	return assertEqual(v, nil)
end

local function assertError(fn, expected)
	local success, received = pcall(fn)
	if success then
		return error(f('expected: %q, received: success', expected))
	end
	local n = #received - #expected + 1
	if received:find(expected, n, true) ~= n then
		return error(f('expected: %q, received: %q', expected, received))
	end
end

return {
	sleep = helpers.sleep,
	assertEqual = assertEqual,
	assertTrue = assertTrue,
	assertFalse = assertFalse,
	assertNil = assertNil,
	assertError = assertError,
}
