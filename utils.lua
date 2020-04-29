util = util or {}

local timeUnits = {}

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
		NameSingle = "mi",
		NameSingular = "millennium",
		NamePlural = "millennia",
		Seconds = millenniumSecond
	})

	table.insert(timeUnits, {
		NameSingle = "c",
		NameSingular = "century",
		NamePlural = "centuries",
		Seconds = centurySecond
	})

	table.insert(timeUnits, {
		NameSingle = "y",
		NameSingular = "year",
		NamePlural = "years",
		Seconds = yearSecond
	})

	table.insert(timeUnits, {
		NameSingle = "M",
		NameSingular = "month",
		NamePlural = "months",
		Seconds = monthSecond
	})

	table.insert(timeUnits, {
		NameSingle = "w",
		NameSingular = "week",
		NamePlural = "weeks",
		Seconds = weekSecond
	})

	table.insert(timeUnits, {
		NameSingle = "d",
		NameSingular = "day",
		NamePlural = "days",
		Seconds = daySecond
	})

	table.insert(timeUnits, {
		NameSingle = "h",
		NameSingular = "hour",
		NamePlural = "hours",
		Seconds = hourSecond
	})

	table.insert(timeUnits, {
		NameSingle = "m",
		NameSingular = "minute",
		NamePlural = "minutes",
		Seconds = minuteSecond
	})

	table.insert(timeUnits, {
		NameSingle = "s",
		NameSingular = "second",
		NamePlural = "seconds",
		Seconds = 1
	})
end

function string.ConvertToTime(str)
	local seconds = tonumber(str)
	if (seconds) then
		return seconds
	end

	seconds = 0

	local units = timeUnits
	local valid = false
	for unit, timeUnit in string.gmatch(str, "([%d-]+)%s*(%a+)") do
		unit = tonumber(unit)
		if (not unit) then
			return -- Not valid
		end

		for k,v in pairs(units) do
			if (timeUnit == v.NameSingle or timeUnit == v.NameSingular or timeUnit == v.NamePlural) then
				valid = true
				seconds = seconds + unit * v.Seconds
			end
		end

		if (not valid) then
			return
		end
	end

	if (not valid) then
		return
	end

	return seconds
end

function string.GetArguments(txt, limit)
	local args = {}
	for k,v in pairs(string.Explode('"', txt)) do
		if (k % 2 == 0) then
			table.insert(args, v)
		else
			for k,v in pairs(string.Explode(" ", v)) do
				if (#v > 0) then
					table.insert(args, v)
				end
			end
		end
	end

	if (limit and #args > limit) then
		args[limit] = table.concat(args, " ", limit)
		for i = limit + 1, #args do
			args[i] = nil
		end
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
