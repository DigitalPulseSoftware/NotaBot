local utf8str = require("deps/utf8-string-extensions")

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
		AltNames = {"u"},
		NameSingular = "age of the Universe",
		NamePlural = "ages of the Universe",
		Seconds = 13800000 * millenniumSecond
	})

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

function string.GetArguments(text, limit)
    local args = {}

    local e = 0
    while true do
        local b = e+1
        b = text:find("%S", b)
        if b == nil then 
            break
        end
        
        if limit and #args >= limit - 1 then
            table.insert(args, text:sub(b))
            break
        end

        local k = false -- should keep delimiter
        local c = text:sub(b, b)
        if c == "`" then
            k = true
            if text:sub(b, b + 2) == "```" then
                e = text:find("```", b + 3)
				if e ~= nil then
					e = e + 3
				end
            else
                e = text:find("`", b + 1)
            end
        elseif c == "'" or c == '"' then
            e = text:find(c, b + 1)
            if e ~= nil then
                b = b+1
            end
        else
            e = text:find("%s", b+1)
        end
        if e == nil then
            e = #text+1
        end

        table.insert(args, text:sub(b, k and e or e - 1))
    end

	return args
end

local nonLatinToLatinEquivalent = {
	["[ꝚƧ]"] = "2",
	["[ꞫȜƷꝪ]"] = "3",
	["[Ƽ]"] = "5",
	["[ȣȢ]"] = "8",
	["[Ꝯ]"] = "9",
	["[ǃ]"] = "!",
	["[ʔɁ]"] = "?",
	["[ꞏ]"] = "·",
	["[ꞌ]"] = "'",
	["[ꝸ]"] = "&",
	["[ꟷ]"] = "ー",
	["[⍺ａ𝐚𝑎𝒂𝒶𝓪𝔞𝕒𝖆𝖺𝗮𝘢𝙖𝚊ɑα𝛂𝛼𝜶𝝰𝞪аàáâãăäåāąа]"] = "a",
	["[ÀÁÂÃÄÅАＡ𝐀𝐴𝑨𝒜𝓐𝔄𝔸𝕬𝖠𝗔𝘈𝘼𝙰Α𝚨𝛢𝜜𝝖𝞐АᎪᗅꓮ𖽀𐊠]"] = "A",
	["[𝐛𝑏𝒃𝒷𝓫𝔟𝕓𝖇𝖻𝗯𝘣𝙗𝚋ƄЬᏏᑲᖯ]"] = "b",
	["[ВвＢℬ𝐁𝐵𝑩𝓑𝔅𝔹𝕭𝖡𝗕𝘉𝘽𝙱ꞴΒ𝚩𝛣𝜝𝝗𝞑ВᏴᗷꓐ𐊂𐊡𐌁вᏼ]"] = "B",
	["[çčċсｃⅽ𝐜𝑐𝒄𝒸𝓬𝔠𝕔𝖈𝖼𝗰𝘤𝙘𝚌ᴄϲⲥсꮯ𐐽]"] = "c",
	["[СҪС🝌𑣲𑣩ＣⅭℂℭ𝐂𝐶𝑪𝒞𝓒𝕮𝖢𝗖𝘊𝘾𝙲ϹⲤСᏟꓚ𐊢𐌂𐐕𐔜]"] = "C",
	["[đⅾⅆ𝐝𝑑𝒅𝒹𝓭𝔡𝕕𝖉𝖽𝗱𝘥𝙙𝚍ԁᏧᑯꓒꝺ]"] = "d",
	["[Ⅾⅅ𝐃𝐷𝑫𝒟𝓓𝔇𝔻𝕯𝖣𝗗𝘋𝘿𝙳Ꭰᗞᗪꓓꭰ]"] = "D",
	["[е́ё́е℮ｅℯⅇ𝐞𝑒𝒆𝓮𝔢𝕖𝖊𝖾𝗲𝘦𝙚𝚎ꬲеҽ⋴ɛεϵ𝛆𝛜𝜀𝜖𝜺𝝐𝝴𝞊𝞮𝟄ⲉєԑꮛ𑣎𐐩ě]"] = "e",
	["[ÈÉÊËЕЁ́ꭼĚ⋿Ｅℰ𝐄𝐸𝑬𝓔𝔈𝔼𝕰𝖤𝗘𝘌𝙀𝙴Ε𝚬𝛦𝜠𝝚𝞔ЕⴹᎬꓰ𑢦𑢮𐊆𝈡ℇԐᏋ𖼭𐐁]"] = "E",
	["[𝐟𝑓𝒇𝒻𝓯𝔣𝕗𝖋𝖿𝗳𝘧𝙛𝚏ꬵꞙſẝք]"] = "f",
	["[ғҒ𝈓ℱ𝐅𝐹𝑭𝓕𝔉𝔽𝕱𝖥𝗙𝘍𝙁𝙵ꞘϜ𝟊ᖴꓝ𑣂𑢢𐊇𐊥𐔥]"] = "F",
	["[ǵǧｇℊ𝐠𝑔𝒈𝓰𝔤𝕘𝖌𝗀𝗴𝘨𝙜𝚐ɡᶃƍց]"] = "g",
	["[ԍꮐᏻǦ𝐆𝐺𝑮𝒢𝓖𝔊𝔾𝕲𝖦𝗚𝘎𝙂𝙶ԌᏀᏳꓖ]"] = "G",
	["[ꞕｈℎ𝐡𝒉𝒽𝓱𝔥𝕙𝖍𝗁𝗵𝘩𝙝𝚑һհᏂ]"] = "h",
	["[ңҢНнԊнꮋＨℋℌℍ𝐇𝐻𝑯𝓗𝕳𝖧𝗛𝘏𝙃𝙷Η𝚮𝛨𝜢𝝜𝞖ⲎНᎻᕼꓧ𐋏]"] = "H",
	["[ǐ˛⍳ｉⅰℹⅈ𝐢𝑖𝒊𝒾𝓲𝔦𝕚𝖎𝗂𝗶𝘪𝙞𝚒ı𝚤ɪɩιιͺ𝛊𝜄𝜾𝝸𝞲іꙇӏꭵᎥ𑣃]"] = "i",
	["[ǏΙ𝚰𝛪𝜤𝝞𝞘ⲒІӀ𝙸]"] = "I",
	["[ｊⅉ𝐣𝑗𝒋𝒿𝓳𝔧𝕛𝖏𝗃𝗷𝘫𝙟𝚓ϳј]"] = "j",
	["[ꭻ𝚥յＪ𝐉𝐽𝑱𝒥𝓙𝔍𝕁𝕵𝖩𝗝𝘑𝙅𝙹ꞲͿЈᎫᒍꓙ]"] = "J",
	["[𝐤𝑘𝒌𝓀𝓴𝔨𝕜𝖐𝗄𝗸𝘬𝙠𝚔]"] = "k",
	["[ЌҞҚКᴋќҟқкκϰ𝛋𝛞𝜅𝜘𝜿𝝒𝝹𝞌𝞳𝟆ⲕкꮶKＫ𝐊𝐾𝑲𝒦𝓚𝔎𝕂𝕶𝖪𝗞𝘒𝙆𝙺Κ𝚱𝛫𝜥𝝟𝞙ⲔКᏦᛕꓗ𐔘]"] = "K",
	["[׀|∣⏽￨1١۱𐌠𞣇𝟏𝟙𝟣𝟭𝟷🯱ＩⅠℐℑ𝐈𝐼𝑰𝓘𝕀𝕴𝖨𝗜𝘐𝙄Ɩｌⅼℓ𝐥𝑙𝒍𝓁𝓵𝔩𝕝𝖑𝗅𝗹𝘭𝙡𝚕ǀⵏᛁꓲ𖼨𐊊𐌉]"] = "l",
	["[ⳑꮮ𐑃𝈪Ⅼℒ𝐋𝐿𝑳𝓛𝔏𝕃𝕷𝖫𝗟𝘓𝙇𝙻ⳐᏞᒪꓡ𖼖𑢣𑢲𐐛𐔦]"] = "L",
	["[ＭмМⅯℳ𝐌𝑀𝑴𝓜𝔐𝕄𝕸𝖬𝗠𝘔𝙈𝙼Μ𝚳𝛭𝜧𝝡𝞛ϺⲘМᎷᗰᛖꓟ𐊰𐌑]"] = "M",
	["[ʍᴍмꮇṃꭑ]"] = "m",
	["[ñŉɲņ𝐧𝑛𝒏𝓃𝓷𝔫𝕟𝖓𝗇𝗻𝘯𝙣𝚗ոռ]"] = "n",
	["[ͷи𐑍Ｎℕ𝐍𝑁𝑵𝒩𝓝𝔑𝕹𝖭𝗡𝘕𝙉𝙽Ν𝚴𝛮𝜨𝝢𝞜Ⲛꓠ𐔓]"] = "N",
	["[óòôőо́о̑o҅o҆оǒంಂംං०੦૦௦౦೦൦๐໐၀٥۵ｏℴ𝐨𝑜𝒐𝓸𝔬𝕠𝖔𝗈𝗼𝘰𝙤𝚘ᴏᴑꬽο𝛐𝜊𝝄𝝾𝞸σ𝛔𝜎𝝈𝞂𝞼ⲟоჿօഠဝ𐓪𑣈𑣗𐐬]"] = "o",
	["[ОÒÔÖО́ОŐǑŎÖ0߀০୦〇𑓐𑣠𝟎𝟘𝟢𝟬𝟶🯰Ｏ𝐎𝑂𝑶𝒪𝓞𝔒𝕆𝕺𝖮𝗢𝘖𝙊𝙾Ο𝚶𝛰𝜪𝝤𝞞ⲞОՕⵔዐଠ𐓂ꓳ𑢵𐊒𐊫𐐄𐔖]"] = "O",
	["[р́ҏр̌р⍴ｐ𝐩𝑝𝒑𝓅𝓹𝔭𝕡𝖕𝗉𝗽𝘱𝙥𝚙ρϱ𝛒𝛠𝜌𝜚𝝆𝝔𝞀𝞎𝞺𝟈ⲣр]"] = "p",
	["[Р́ҎР̌РᴩꮲＰℙ𝐏𝑃𝑷𝒫𝓟𝔓𝕻𝖯𝗣𝘗𝙋𝙿Ρ𝚸𝛲𝜬𝝦𝞠ⲢРᏢᑭꓑ𐊕]"] = "P",
	["[ɋᶐ𝐪𝑞𝒒𝓆𝓺𝔮𝕢𝖖𝗊𝗾𝘲𝙦𝚚ԛգզ]"] = "q",
	["[ℚ𝐐𝑄𝑸𝒬𝓠𝔔𝕼𝖰𝗤𝘘𝙌𝚀ⵕ]"] = "Q",
	["[𝐫𝑟𝒓𝓇𝓻𝔯𝕣𝖗𝗋𝗿𝘳𝙧𝚛ꭇꭈᴦⲅгꮁ]"] = "r",
	["[яᴙꭱʀꮢ𝈖ℛℜℝ𝐑𝑅𝑹𝓡𝕽𝖱𝗥𝘙𝙍𝚁ƦᎡᏒ𐒴ᖇꓣ𖼵]"] = "R",
	["[ѕｓ𝐬𝑠𝒔𝓈𝓼𝔰𝕤𝖘𝗌𝘀𝘴𝙨𝚜ꜱƽѕꮪ𑣁𐑈]"] = "s",
	["[ЅＳ𝐒𝑆𝑺𝒮𝓢𝔖𝕊𝕾𝖲𝗦𝘚𝙎𝚂ЅՏᏕᏚꓢ𖼺𐊖𐐠]"] = "S",
	["[ţțƫᎿ𝐭𝑡𝒕𝓉𝓽𝔱𝕥𝖙𝗍𝘁𝘵𝙩𝚝]"] = "t",
	["[ТҬҭТтᴛτ𝛕𝜏𝝉𝞃𝞽тꭲȚŢ⊤⟙🝨Ｔ𝐓𝑇𝑻𝒯𝓣𝔗𝕋𝕿𝖳𝗧𝘛𝙏𝚃Τ𝚻𝛵𝜯𝝩𝞣ⲦТᎢꓔ𖼊𑢼𐊗𐊱𐌕]"] = "T",
	["[ùŭǔ𝐮𝑢𝒖𝓊𝓾𝔲𝕦𝖚𝗎𝘂𝘶𝙪𝚞ꞟᴜꭎꭒʋυ𝛖𝜐𝝊𝞄𝞾ս𐓶𑣘]"] = "u",
	["[ŬǓ∪⋃𝐔𝑈𝑼𝒰𝓤𝔘𝕌𝖀𝖴𝗨𝘜𝙐𝚄Սሀ𐓎ᑌꓴ𖽂𑢸]"] = "U",
	["[∨⋁ｖⅴ𝐯𝑣𝒗𝓋𝓿𝔳𝕧𝖛𝗏𝘃𝘷𝙫𝚟ᴠν𝛎𝜈𝝂𝝼𝞶ѵט𑜆ꮩ𑣀]"] = "v",
	["[𝈍٧۷Ⅴ𝐕𝑉𝑽𝒱𝓥𝔙𝕍𝖁𝖵𝗩𝘝𝙑𝚅ѴⴸᏙᐯꛟꓦ𖼈𑢠𐔝]"] = "V",
	["[ɯ𝐰𝑤𝒘𝓌𝔀𝔴𝕨𝖜𝗐𝘄𝘸𝙬𝚠ᴡѡԝա𑜊𑜎𑜏ꮃ]"] = "w",
	["[𑣯𑣦𝐖𝑊𝑾𝒲𝓦𝔚𝕎𝖂𝖶𝗪𝘞𝙒𝚆ԜᎳᏔꓪ]"] = "W",
	["[х᙮×⤫⤬⨯ｘⅹ𝐱𝑥𝒙𝓍𝔁𝔵𝕩𝖝𝗑𝘅𝘹𝙭𝚡хᕁᕽ]"] = "x",
	["[ҲҳХ᙭╳𐌢𑣬ＸⅩ𝐗𝑋𝑿𝒳𝓧𝔛𝕏𝖃𝖷𝗫𝘟𝙓𝚇ꞳΧ𝚾𝛸𝜲𝝬𝞦ⲬХⵝᚷꓫ𐊐𐊴𐌗𐔧]"] = "X",
	["[у́ɣᶌｙ𝐲𝑦𝒚𝓎𝔂𝔶𝕪𝖞𝗒𝘆𝘺𝙮𝚢ʏỿꭚγℽ𝛄𝛾𝜸𝝲𝞬уүყ𑣜]"] = "y",
	["[ұУ́ҰＹ𝐘𝑌𝒀𝒴𝓨𝔜𝕐𝖄𝖸𝗬𝘠𝙔𝚈Υϒ𝚼𝛶𝜰𝝪𝞤ⲨУҮᎩᎽꓬ𖽃𑢤𐊲]"] = "Y",
	["[𝐳𝑧𝒛𝓏𝔃𝔷𝕫𝖟𝗓𝘇𝘻𝙯𝚣ᴢꮓ𑣄]"] = "z",
	["[𐋵𑣥Ｚℤℨ𝐙𝑍𝒁𝒵𝓩𝖅𝖹𝗭𝘡𝙕𝚉Ζ𝚭𝛧𝜡𝝛𝞕Ꮓꓜ𑢩]"] = "Z",
}

function string.RemoveNonLatinChars(str)
	for k,v in pairs(nonLatinToLatinEquivalent) do
		str = utf8str.gsub(str, k, v)
	end

	return str
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

local discordMaxTimestamp = 4294962947295 -- found by rigourous testing

function util.DiscordTime(timestamp)
	if timestamp < discordMaxTimestamp then
		return string.format("<t:%d>", timestamp)
	else
		return util.FormatTime(timestamp, 3)
	end
end

function util.DiscordRelativeTime(duration)
	return util.DiscordRelativeTimestamp(os.time() + duration)
end

function util.DiscordRelativeTimestamp(timestamp)
	if timestamp < discordMaxTimestamp then
		return string.format("<t:%d:R>", timestamp)
	else
		local now = os.time()
		if timestamp > now then
			return "in " .. util.FormatTime(timestamp - now, 3)
		else
			return util.FormatTime(now - timestamp, 3) .. " ago"
		end
	end
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

function table.wrap(value)
	if type(value) ~= "table" then
		return { value }
	end

	return value
end