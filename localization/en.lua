return {
	FormatTime = util.FormatTime,
	NiceConcat = util.NiceConcat,
	Locs = {
		MODMAIL_CLOSETICKET = "Close ticket",
		MODMAIL_TICKETCLOSE_MESSAGE = "%s has closed the ticket, this channel will automatically be deleted %s",
		MODMAIL_TICKETOPENING_MESSAGE = "Hello %s, use this private channel to communicate with **%s** staff.",
		MODMAIL_TICKETOPENING_MESSAGE_MODERATION = "Hello %s, **%s** staff wants to communicate with you.",
		MODMAIL_TICKETMESSAGE = "Ticket message:",
		MODMAIL_LEFTSERVER = "%s left the server",
		MODMAIL_NOTACTIVETICKET = "You can only do this in an active ticket channel, %s.",
		MODMAIL_NOTAUTHORIZED = "You are not authorized to do that %s.",
		MODMAIL_TICKETCLOSED_CONFIRMATION = "✅ Ticket closed.",
		MODMAIL_OPENTICKET_BUTTON_LABEL = "Open a modmail ticket...",
		MODMAIL_FORM_TITLE = "Open a channel with the server staff",
		MODMAIL_FORM_DESCRIPTION_LABEL = "Please describe your issue in a few words:",
		MODMAIL_OPENTICKET_FORBIDDEN = "You are forbidden to open a ticket on this server",
		MODMAIL_OPENTICKET_NOTALLOWED = "You do not have the permission to open a ticket on this server",
		MODMAIL_OPENTICKET_NOTALLOWED_OTHERMEMBER = "You do not have the permission to open a ticket for someone else",
		MODMAIL_TICKEDOPENED = "✅ A modmail ticket has been created: %s.",

		MUTE_ERROR_NOT_PART_OF_GUILD = "%s is not on the server",
		MUTE_GUILD_MESSAGE = "%s has muted %s%s%s",
		MUTE_MUTE_FAILED = "❌ failed to mute %s: %s",
		MUTE_NOTAUTHORIZED = "❌ You cannot mute that user due to your lower permissions",
		MUTE_PRIVATE_MESSAGE = "You have been muted from **%s** by %s%s%s",
		MUTE_REASON = "for the following reason: %s",
		MUTE_THEY_WILL_BE_UNMUTED_IN = "They will be unmuted %s",
		MUTE_UNMUTE_FAILED = "❌ failed to unmute %s: %s",
		MUTE_UNMUTE_GUILD_MESSAGE = "%s has unmuted %s%s",
		MUTE_UNMUTE_MESSAGE = "You have been unmuted from **%s** by %s%s",
		MUTE_YOU_WILL_BE_UNMUTED_IN = "You will be unmuted %s",

		RAID_LOCKSERVER_HELP = "Locks the server, preventing people to join",
		RAID_LOCKSERVER_ALREADY_LOCKED = "The server is already locked",
		RAID_LOCKSERVER_LOCKED_BY = "locked by %s",
		RAID_UNLOCKSERVER_HELP = "Unlocks the server",
		RAID_UNLOCKSERVER_NOT_LOCKED = "The server is not locked",
		RAID_UNLOCKSERVER_LOCKED_BY = "unlocked by %s",
		RAID_RULEHELP_HELP = "List the differents available rules",
		RAID_RULEHELP_FIELDS_VALUE = "**Description:** %s\n**Parameter:** %s",
		RAID_RULEHELP_TITLE = "Available raid rule list",
		RAID_RULEHELP_DESCRIPTION = "Here's a list of the available rules for the raid module.\n\nUse them with `!addrule <effect> <rule> <param>`.\n\nEffect lists:\n%s",
		RAID_ADDRULE_HELP = "Adds a new rule for incoming members",
		RAID_ADDRULE_INVALID_EFFECT = "Invalid effect (possible values are %s)",
		RAID_ADDRULE_INVALID_RULE = "Invalid rule (use `!rulehelp` to see valid rules)",
		RAID_ADDRULE_INVALID_RULE_PARAMETERS = "Invalid rule parameters: %s",
		RAID_ADDRULE_ADDED = "Rule has been added as rule #%s",
		RAID_ALERT_SERVER_LOCKED_UNITL = "🔒 The server has been locked and will be unlocked %s (%s)",
		RAID_ALERT_SERVER_UNLOCKED = "🔓 The server has been unlocked (%s)",
		RAID_LOCK_EXPIRATION = "lock duration expired",
		RAID_CLEARRULES_HELP = "Clear all raid rules",
		RAID_CLEARRULES_DONE = "Rules have been cleared",
		RAID_DELRULE_HELP = "Removes a rule by its index",
		RAID_DELRULE_OUTOFRANGE = "Rule index out of range",
		RAID_DELRULE_DONE = "Rule #%s has been removed",
		RAID_LISTRULES_HELP = "List current raid rules",
		RAID_LISTRULES_RULE_TITLE = "Rule #%s",
		RAID_LISTRULES_RULE_DETAIL = "**Rule:** %s**\nRule config: %s**\n**Effect:** %s",
		RAID_LISTRULES_TITLE = "Guild current rules",
		RAID_HANDLERULE_WHITELIST = "%s has been allowed to join (whitelisted)",
		RAID_HANDLERULE_RULE = "rule %d - %s(%s)",
		RAID_HANDLERULE_AUTHORIZE = "%s has been allowed to join due to %s",
		RAID_HANDLERULE_BAN_MSG = "auto-ban due to %s",
		RAID_HANDLERULE_BAN_LOG = "%s has been banned due to %s",
		RAID_HANDLERULE_KICK_MSG = "auto-kick due to %s",
		RAID_HANDLERULE_KICK_LOG = "%s has been kicked due to %s",
		RAID_AUTOKICK_REASON = "server is locked",
		RAID_AUTOLOCK_REASON = "auto-lock by anti-raid system",
		RAID_AUTOBAN_BOT_REASON = "auto-ban for bot suspicion",
		RAID_AUTOMUTE_SPAM_REASON = "🙊 %s has been auto-muted because of spam in %s",

		PRUNEFROM_HELP = string.format("%s\n%s\n\t%s",
			"Delete all messages from the one whose identifier has been given in parameter.",
			"Arguments:",
			"messageId: The message id"
		),
		PRUNE_CANNOT_DELETE = "ℹ️ Some messages could not be deleted.",
		PRUNE_BAD_MESSAGE_ID = "❌ No message with the specified ID was found.",
		PRUNE_HELP = string.format("%s\n%s\n\t%s",
			"Delete the nth last messages.",
			"Arguments:",
			"nbMessages: Number of messages to delete"
		),
		PRUNE_RESULT = "🧹 %d messages have been deleted.",
	}
}
