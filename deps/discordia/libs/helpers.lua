local uv = require('uv')

local hrtime = uv.hrtime
local insert = table.insert
local format, byte, gsub = string.format, string.byte, string.gsub
local resume, yield, running = coroutine.resume, coroutine.yield, coroutine.running

local function toPercent(char)
	return format('%%%02X', byte(char))
end

local function urlEncode(obj)
	return (gsub(tostring(obj), '%W', toPercent))
end

local function attachQuery(url, query)
	local first = true
	for k, v in pairs(query) do
		insert(url, first and '?' or '&')
		insert(url, urlEncode(k))
		insert(url, '=')
		insert(url, urlEncode(v))
		first = false
	end
end

local function benchmark(n, fn, ...)

	local _ = {}

	collectgarbage()
	collectgarbage()
	local m1 = collectgarbage('count')
	local t1 = hrtime()

	for i = 1, n do
		_[i] = fn(...)
	end

	collectgarbage()
	collectgarbage()
	local m2 = collectgarbage('count')
	local t2 = hrtime()

	return (m2 - m1) / n, (t2 - t1) / n

end

local function str2int(str, base)

	local i = 1
	local n = 0ULL
	local neg = false
	base = base or 10

	str = str:match('^%s*(.-)%s*$')

	if str:sub(i, i) == '-' then
		neg = true
		i = i + 1
	elseif str:sub(i, i) == '+' then
		i = i + 1
	end

	local s = #str
	repeat
		local digit = tonumber(str:sub(i, i), base)
		if not digit then
			return nil
		end
		n = n * base + digit
		i = i + 1
	until i > s

	return neg and -n or n

end

local function readOnly(tbl)
	tbl = tbl or {}
	return setmetatable({}, {
		__index = function(_, k)
			local v = rawget(tbl, k)
			if type(v) == 'table' then
				return readOnly(v)
			else
				return v
			end
		end,
		__pairs = function()
			local k, v
			return function()
				k, v = next(tbl, k)
				if type(v) == 'table' then
					return k, readOnly(v)
				else
					return k, v
				end
			end
		end,
	})
end

local function assertResume(thread, ...)
	local success, err = resume(thread, ...)
	if not success then
		error(debug.traceback(thread, err), 0)
	end
end

local function sleep(ms)
	local thread = running()
	local timer = uv.new_timer()
	timer:start(ms, 0, function()
		timer:close()
		return assertResume(thread)
	end)
	return yield()
end

local function setTimeout(ms, callback, ...)
	local timer = uv.new_timer()
	local args = {...}
	timer:start(ms, 0, function()
		timer:close()
		return callback(unpack(args))
	end)
	return timer
end

local function setInterval(ms, callback, ...)
	local timer = uv.new_timer()
	local args = {...}
	timer:start(ms, ms, function()
		return callback(unpack(args))
	end)
	return timer
end

local function clearTimer(timer)
	timer:stop()
	timer:close()
end

return {
	urlEncode = urlEncode,
	attachQuery = attachQuery,
	benchmark = benchmark,
	str2int = str2int,
	readOnly = readOnly,
	assertResume = assertResume,
	sleep = sleep,
	setTimeout = setTimeout,
	setInterval = setInterval,
	clearTimer = clearTimer,
}
