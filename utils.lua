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
		AltNames = {"M"},
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
		AltNames = {"m", "min"},
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
