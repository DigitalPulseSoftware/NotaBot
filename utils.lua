util = util or {}

local timeUnits = {}
local timeUnitByUnit = {}

do
	local minuteSecond = 60
	local hourSecond = 60 * minuteSecond
	local daySecond = 24 * hourSecond
	local weekSecond = 7 * daySecond
	local monthSecond = 30 * daySecond -- Prendre 4 semaines n'aurait fait que 28 jours
	local yearSecond = 365 * daySecond -- Prendre 12 mois n'aurait fait que 360 jours
	local centurySecond = 100 * yearSecond
	local millenniumSecond = 10 * centurySecond

	table.insert(timeUnits, {
		AltNames = {"mi"},
		NameSingular = "millennium",
		NamePlural = "millennia",
		Seconds = millenniumSecond
	})

	table.insert(timeUnits, {
		AltNames = {"c"},
		NameSingular = "century",
		NamePlural = "centuries",
		Seconds = centurySecond
	})

	table.insert(timeUnits, {
		AltNames = {"y"},
		NameSingular = "year",
		NamePlural = "years",
		Seconds = yearSecond
	})

	table.insert(timeUnits, {
		AltNames = {"mo"},
		NameSingular = "month",
		NamePlural = "months",
		Seconds = monthSecond
	})

	table.insert(timeUnits, {
		AltNames = {"w"},
		NameSingular = "week",
		NamePlural = "weeks",
		Seconds = weekSecond
	})

	table.insert(timeUnits, {
		AltNames = {"d"},
		NameSingular = "day",
		NamePlural = "days",
		Seconds = daySecond
	})

	table.insert(timeUnits, {
		AltNames = {"h"},
		NameSingular = "hour",
		NamePlural = "hours",
		Seconds = hourSecond
	})

	table.insert(timeUnits, {
		AltNames = {"min"},
		NameSingular = "minute",
		NamePlural = "minutes",
		Seconds = minuteSecond
	})

	table.insert(timeUnits, {
		AltNames = {"s", "sec"},
		NameSingular = "second",
		NamePlural = "seconds",
		Seconds = 1
	})

	-- Processing
	for _, data in pairs(timeUnits) do
		local function registerUnit(unit)
			if (timeUnitByUnit[unit] ~= nil) then
				error("TimeUnit name " .. unit .. " is already registered")
			end

			timeUnitByUnit[unit] = data
		end

		registerUnit(data.NameSingular)
		registerUnit(data.NamePlural)
		for _, name in pairs(data.AltNames) do
			registerUnit(name)
		end
	end
end

function string.ConvertToTime(str)
	local seconds = tonumber(str)
	if (seconds) then
		return seconds
	end

	local isValid = false

	seconds = 0
	for value, timeUnit in string.gmatch(str, "([%d-]+)%s*(%a+)") do
		value = tonumber(value)
		if (not value) then
			return -- Invalid value
		end

		local unit = timeUnitByUnit[timeUnit]
		if (not unit) then
			return -- Invalid unit
		end

		isValid = true
		seconds = seconds + value * unit.Seconds
	end

	if (not isValid) then
		return
	end

	return seconds
end

function string.GetArguments(txt, limit)
	local inCode
	local inQuote
	local args = {}
	local start
	local i = 1
	while i <= #txt and #args < limit - 1 do
		local c = txt:sub(i, i)
		if (inCode) then
			if (c == '`' and txt:sub(i, i + 2) == '```') then
				table.insert(args, txt:sub(start, i + 2))
				i = i + 2
				inCode = false
				start = nil
			end
		elseif (inQuote) then
			if (c == '"') then
				table.insert(args, txt:sub(start, i-1))
				inQuote = false
				start = nil
			end
		elseif (c == '"') then
			inQuote = true
			start = i + 1
		elseif (c == '`' and txt:sub(i):match("```(.*)\r?\n")) then
			inCode = true
			start = i
		elseif (c:match("%s")) then
			if (start and start <= i -1) then
				table.insert(args, txt:sub(start, i-1))
				start = nil
			end
		else
			if (not start) then
				start = i
			end
		end

		i = i + 1
	end

	if (not start) then
		start = txt:find("[^%s]", i)
	end

	if (start and start <= #txt -1) then
		table.insert(args, txt:sub(start))
	end

	return args
end

function string.ToTable(str)
	local tbl = {}

	for i = 1, string.len( str ) do
		tbl[i] = string.sub( str, i, i )
	end

	return tbl
end

local totable = string.ToTable
local string_sub = string.sub
local string_find = string.find
local string_len = string.len
function string.Explode(separator, str, withpattern)
	if ( separator == "" ) then return totable( str ) end
	if ( withpattern == nil ) then withpattern = false end

	local ret = {}
	local current_pos = 1

	for i = 1, string_len( str ) do
		local start_pos, end_pos = string_find( str, separator, current_pos, not withpattern )
		if ( not start_pos ) then break end
		ret[ i ] = string_sub( str, current_pos, start_pos - 1 )
		current_pos = end_pos + 1
	end

	ret[ #ret + 1 ] = string_sub( str, current_pos )

	return ret
end

function string.UpperizeFirst(str)
	return string.upper(str:sub(1,1)) .. str:sub(2)
end

function table.empty(tab)
	for k,v in pairs(tab) do
		return false
	end

	return true
end

function table.NiceConcat(tab)
	if (#tab > 1) then
		return table.concat(tab, ", ", 1, #tab - 1) .. " and " .. tab[#tab]
	elseif (#tab == 1) then
		return tab[1]
	else
		return ""
	end
end

function util.FormatTime(seconds, depth)
	if (type(seconds) ~= "number") then
		return seconds
	end

	local units = timeUnits
	if (seconds < units[#units].Seconds) then
		return "zero " .. units[#units].NameSingular
	end

	depth = depth or 0

	local txt = {}
	for k,v in pairs(units) do
		if (seconds >= v.Seconds) then
			local count = math.floor(seconds/v.Seconds)
			seconds = seconds - count*v.Seconds
			if (count > 1) then
				table.insert(txt, count .. " " .. v.NamePlural)
			else
				table.insert(txt, "one " .. v.NameSingular)
			end

			if (depth > 0) then
				depth = depth - 1
				if (depth < 1) then
					break
				end
			end
		end
	end

	return table.NiceConcat(txt)
end

function util.MemberHasAnyRole(member, roles)
	for _, roleId in pairs(roles) do
		if (member:hasRole(roleId)) then
			return true
		end
	end

	return false
end

function util.MemberHasAllRoles(member, roles)
	if (#roles == 0) then
		return true
	end

	for _, roleId in pairs(roles) do
		if (not member:hasRole(roleId)) then
			return false
		end
	end

	return true
end

function util.ValidateSnowflake(snowflake)
	if (type(snowflake) ~= "string") then
		return false, "not a string"
	end

	if (not string.match(snowflake, "%d+")) then
		return false, "must contain only number"
	end

	return true
end

local sort, concat = table.sort, table.concat
local insert, remove = table.insert, table.remove
local byte, char = string.byte, string.char
local gmatch, match = string.gmatch, string.match
local rep, find, sub = string.rep, string.find, string.sub
local min, max, random = math.min, math.max, math.random
local ceil, floor = math.ceil, math.floor

function table.binsearch( tbl, value, comp )
	local comp = comp or function (a, b)
		if (a == b) then return 0 end
		if (a < b) then return -1 end
		if (a > b) then return 1 end
	end

	local iStart,iEnd,iMid = 1,#tbl,0
	while iStart <= iEnd do
		iMid = math.floor( (iStart+iEnd)/2 )
		local r = comp( value, tbl[iMid] )

		if r == 0 then
			return tbl[iMid], iMid
		elseif r < 0 then
			iEnd = iMid - 1
		else
			iStart = iMid + 1
		end
	end

	return nil, iStart, iEnd
end

function table.length( tbl )
	local count = 0

	for _ in pairs(tbl) do
		count = count + 1
	end
	
	return count
end

function table.count(tbl)
	local n = 0
	for _ in pairs(tbl) do
		n = n + 1
	end
	return n
end

function table.deepcount(tbl)
	local n = 0
	for _, v in pairs(tbl) do
		n = type(v) == 'table' and n + table.deepcount(v) or n + 1
	end
	return n
end

function table.copy(tbl)
	local ret = {}
	for k, v in pairs(tbl) do
		ret[k] = v
	end
	return ret
end

function table.deepcopy(tbl)
	local ret = {}
	for k, v in pairs(tbl) do
		ret[k] = type(v) == 'table' and table.deepcopy(v) or v
	end
	return ret
end

function table.reverse(tbl)
	for i = 1, #tbl do
		insert(tbl, i, remove(tbl))
	end
end

function table.reversed(tbl)
	local ret = {}
	for i = #tbl, 1, -1 do
		insert(ret, tbl[i])
	end
	return ret
end

function table.keys(tbl)
	local ret = {}
	for k in pairs(tbl) do
		insert(ret, k)
	end
	return ret
end

function table.values(tbl)
	local ret = {}
	for _, v in pairs(tbl) do
		insert(ret, v)
	end
	return ret
end

function table.randomipair(tbl)
	local i = random(#tbl)
	return i, tbl[i]
end

function table.randompair(tbl)
	local rand = random(table.count(tbl))
	local n = 0
	for k, v in pairs(tbl) do
		n = n + 1
		if n == rand then
			return k, v
		end
	end
end

function table.sorted(tbl, fn)
	local ret = {}
	for i, v in ipairs(tbl) do
		ret[i] = v
	end
	sort(ret, fn)
	return ret
end

function table.search(tbl, value)
	for k, v in pairs(tbl) do
		if v == value then
			return k
		end
	end
	return nil
end

function table.slice(tbl, start, stop, step)
	local ret = {}
	for i = start or 1, stop or #tbl, step or 1 do
		insert(ret, tbl[i])
	end
	return ret
end

function string.split(str, delim)
	local ret = {}
	if not str then
		return ret
	end
	if not delim or delim == '' then
		for c in gmatch(str, '.') do
			insert(ret, c)
		end
		return ret
	end
	local n = 1
	while true do
		local i, j = find(str, delim, n)
		if not i then break end
		insert(ret, sub(str, n, i - 1))
		n = j + 1
	end
	insert(ret, sub(str, n))
	return ret
end

function string.trim(str)
	return match(str, '^%s*(.-)%s*$')
end

function string.pad(str, len, align, pattern)
	pattern = pattern or ' '
	if align == 'right' then
		return rep(pattern, (len - #str) / #pattern) .. str
	elseif align == 'center' then
		local pad = 0.5 * (len - #str) / #pattern
		return rep(pattern, floor(pad)) .. str .. rep(pattern, ceil(pad))
	else -- left
		return str .. rep(pattern, (len - #str) / #pattern)
	end
end

function string.startswith(str, pattern, plain)
	local start = 1
	return find(str, pattern, start, plain) == start
end

function string.endswith(str, pattern, plain)
	local start = #str - #pattern + 1
	return find(str, pattern, start, plain) == start
end

function string.levenshtein(str1, str2)

	if str1 == str2 then return 0 end

	local len1 = #str1
	local len2 = #str2

	if len1 == 0 then
		return len2
	elseif len2 == 0 then
		return len1
	end

	local matrix = {}
	for i = 0, len1 do
		matrix[i] = {[0] = i}
	end
	for j = 0, len2 do
		matrix[0][j] = j
	end

	for i = 1, len1 do
		for j = 1, len2 do
			local cost = byte(str1, i) == byte(str2, j) and 0 or 1
			matrix[i][j] = min(matrix[i-1][j] + 1, matrix[i][j-1] + 1, matrix[i-1][j-1] + cost)
		end
	end

	return matrix[len1][len2]

end

function string.random(len, mn, mx)
	local ret = {}
	mn = mn or 0
	mx = mx or 255
	for _ = 1, len do
		insert(ret, char(random(mn, mx)))
	end
	return concat(ret)
end

local math = {}

function math.clamp(n, minValue, maxValue)
	return min(max(n, minValue), maxValue)
end

function math.round(n, i)
	local m = 10 ^ (i or 0)
	return floor(n * m + 0.5) / m
end
