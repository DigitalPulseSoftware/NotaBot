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
		NameSingular = "âge de l'Univers",
		NamePlural = "âges de l'Univers",
		Seconds = 13800000 * millenniumSecond
	})

	table.insert(timeUnits, {
		AltNames = {"mi"},
		NameSingular = "millénaire",
		NamePlural = "millénaires",
		Seconds = millenniumSecond,
        One = "un"
	})

	table.insert(timeUnits, {
		AltNames = {"c"},
		NameSingular = "siècle",
		NamePlural = "siècles",
		Seconds = centurySecond,
        One = "un"
	})

	table.insert(timeUnits, {
		AltNames = {"y"},
		NameSingular = "an",
		NamePlural = "ans",
		Seconds = yearSecond,
        One = "un"
	})

	table.insert(timeUnits, {
		AltNames = {"M"},
		NamePlural = "mois",
		Seconds = monthSecond,
        One = "un"
	})

	table.insert(timeUnits, {
		AltNames = {"w"},
		NameSingular = "semaine",
		NamePlural = "semaines",
		Seconds = weekSecond,
        One = "une"
	})

	table.insert(timeUnits, {
		AltNames = {"d"},
		NameSingular = "jour",
		NamePlural = "jours",
		Seconds = daySecond,
        One = "un"
	})

	table.insert(timeUnits, {
		AltNames = {"h"},
		NameSingular = "heure",
		NamePlural = "heures",
		Seconds = hourSecond,
        One = "une"
	})

	table.insert(timeUnits, {
		AltNames = {"m", "min"},
		NameSingular = "minute",
		NamePlural = "minutes",
		Seconds = minuteSecond,
        One = "une"
	})

	table.insert(timeUnits, {
		AltNames = {"s", "sec"},
		NameSingular = "seconde",
		NamePlural = "secondes",
		Seconds = 1,
        One = "une"
	})

	-- Processing
	for _, data in pairs(timeUnits) do
		local function registerUnit(unit)
			if (timeUnitByUnit[unit] ~= nil) then
				error("TimeUnit name " .. unit .. " is already registered")
			end

			timeUnitByUnit[unit] = data
		end

		if data.NameSingular then
			registerUnit(data.NameSingular)
		end

		if data.NamePlural then
			registerUnit(data.NamePlural)
		end

		for _, name in pairs(data.AltNames) do
			registerUnit(name)
		end
	end
end

local function NiceConcat(tab)
	if (#tab > 1) then
		return table.concat(tab, ", ", 1, #tab - 1) .. " et " .. tab[#tab]
	elseif (#tab == 1) then
		return tab[1]
	else
		return ""
	end
end

local function FormatTime(seconds, depth)
	if (type(seconds) ~= "number") then
		return seconds
	end

	local units = timeUnits
	local lastUnit = units[#units]
	if (seconds < lastUnit.Seconds) then
		return "zéro " .. (lastUnit.NameSingular or lastUnit.NamePlural)
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
				table.insert(txt, v.One .. " " .. (v.NameSingular or v.NamePlural))
			end

			if (depth > 0) then
				depth = depth - 1
				if (depth < 1) then
					break
				end
			end
		end
	end

	return NiceConcat(txt)
end

return {
    FormatTime = FormatTime,
    NiceConcat = NiceConcat,
    Locs = {
        MODMAIL_CLOSETICKET = "Fermer le ticket",
        MODMAIL_TICKETCLOSE_MESSAGE = "%s a fermé le ticket, ce canal sera automatiquement supprimé %s",
        MODMAIL_TICKETOPENING_MESSAGE = "Bonjour %s, vous pouvez communiquer avec la modération de **%s** via ce canal privé.",
        MODMAIL_TICKETOPENING_MESSAGE_MODERATION = "Bonjour %s, la modération de **%s** souhaite s'entretenir avec vous.",
        MODMAIL_TICKETMESSAGE = "Message associé :",
        MODMAIL_LEFTSERVER = "%s a quitté le serveur",
        MODMAIL_NOTACTIVETICKET = "Vous ne pouvez effectuer cette action que dans un ticket actif, %s.",
        MODMAIL_NOTAUTHORIZED = "Vous n'avez pas la permission de faire ça, %s.",
        MODMAIL_TICKETCLOSED_CONFIRMATION = "✅ Ticket fermé.",
        MODMAIL_OPENTICKET_BUTTON_LABEL = "Ouvrir un ticket avec la modération...",
        MODMAIL_FORM_TITLE = "Ouvrir un ticket avec la modération",
        MODMAIL_FORM_DESCRIPTION_LABEL = "Décrivez en quelques mots votre demande :",
        MODMAIL_OPENTICKET_FORBIDDEN = "Ouvrir un ticket sur ce serveur vous est interdit.",
        MODMAIL_OPENTICKET_NOTALLOWED = "Vous n'avez pas la permission d'ouvrir un ticket sur ce serveur.",
        MODMAIL_OPENTICKET_NOTALLOWED_OTHERMEMBER = "Vous n'avez pas la permission d'ouvrir un ticket pour un autre membre sur ce serveur.",
        MODMAIL_TICKEDOPENED = "✅ Un ticket de modération a bien été ouvert : %s.",

		MUTE_ERROR_NOT_PART_OF_GUILD = "%s n'est pas sur le serveur",
        MUTE_GUILD_MESSAGE = "%s a rendu muet %s%s%s",
        MUTE_MUTE_FAILED = "❌ impossible de rendre muet %s : %s",
        MUTE_NOTAUTHORIZED = "❌ Vous ne pouvez rendre ce membre muet à cause de vos permissions",
        MUTE_PRIVATE_MESSAGE = "Vous avez été rendu muet sur **%s** par %s%s%s",
        MUTE_REASON = "pour la raison suivante : %s",
        MUTE_THEY_WILL_BE_UNMUTED_IN = "Ce membre pourra reparler %s",
        MUTE_UNMUTE_FAILED = "❌ impossible de rendre la parole à %s : %s",
        MUTE_UNMUTE_GUILD_MESSAGE = "%s a rendu la parole à %s%s",
        MUTE_UNMUTE_MESSAGE = "La parole vous a été rendue sur **%s** par %s%s",
        MUTE_YOU_WILL_BE_UNMUTED_IN = "La parole vous sera rendue %s",

        RAID_LOCKSERVER_HELP = "Verrouille le serveur afin d'empecher les gens de rejoindre", 
        RAID_LOCKSERVER_ALREADY_LOCKED = "Le serveur est déjà verrouillé",
        RAID_LOCKSERVER_LOCKED_BY = "verrouillé par %s",
        RAID_UNLOCKSERVER_HELP = "Déverouille le serveur",
        RAID_UNLOCKSERVER_NOT_LOCKED = "Le serveur n'est pas verrouillé",
        RAID_UNLOCKSERVER_LOCKED_BY = "déverrouillé par %s",
        RAID_ALERT_SERVER_LOCKED_UNITL = "🔒 Le seveur a été verrouillé et sera déverrouillé %s (%s)",
        RAID_ALERT_SERVER_UNLOCKED = "🔓 Le serveur a été deverrouillé (%s)",
        RAID_LOCK_EXPIRATION = "verrouillage expiré"
    }
}
