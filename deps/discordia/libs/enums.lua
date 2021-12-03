local function enum(tbl)
	local call = {}
	for k, v in pairs(tbl) do
		if call[v] then
			return error(string.format('enum clash for %q and %q', k, call[v]))
		end
		call[v] = k
	end
	return setmetatable({}, {
		__call = function(_, k)
			if call[k] then
				return call[k]
			else
				return error('invalid enumeration: ' .. tostring(k))
			end
		end,
		__index = function(_, k)
			if tbl[k] then
				return tbl[k]
			else
				return error('invalid enumeration: ' .. tostring(k))
			end
		end,
		__pairs = function()
			return next, tbl
		end,
		__newindex = function()
			return error('cannot overwrite enumeration')
		end,
	})
end

local enums = {enum = enum}

local function flag(n)
	return tonumber(tostring(bit.lshift(1, n)):match('%d*'))
end

enums.defaultAvatar = enum {
	blurple = 0,
	gray    = 1,
	green   = 2,
	orange  = 3,
	red     = 4,
}

enums.notificationSetting = enum {
	allMessages  = 0,
	onlyMentions = 1,
}

enums.channelType = enum {
	text           = 0,
	private        = 1,
	voice          = 2,
	group          = 3,
	category       = 4,
	news           = 5,
	news_thread    = 10,
	public_thread  = 11,
	private_thread = 12,
}

enums.webhookType = enum {
	incoming        = 1,
	channelFollower = 2,
}

enums.messageType = enum {
	default                                 = 0,
	recipientAdd                            = 1,
	recipientRemove                         = 2,
	call                                    = 3,
	channelNameChange                       = 4,
	channelIconchange                       = 5,
	pinnedMessage                           = 6,
	memberJoin                              = 7,
	premiumGuildSubscription                = 8,
	premiumGuildSubscriptionTier1           = 9,
	premiumGuildSubscriptionTier2           = 10,
	premiumGuildSubscriptionTier3           = 11,
	channelFollowAdd                        = 12,
	guildDiscoveryDisqualified              = 14,
	guildDiscoveryRequalified               = 15,
	guildDiscoveryGracePeriodInitialWarning = 16,
	guildDiscoveryGracePeriodFinalWarning   = 17,
	threadCreated                           = 18,
	reply                                   = 19,
	chatInputCommand                        = 20,
	threadStarterMessage                    = 21,
	guildInviteReminder                     = 22,
	contextMenuCommand                      = 23
}

enums.relationshipType = enum {
	none            = 0,
	friend          = 1,
	blocked         = 2,
	pendingIncoming = 3,
	pendingOutgoing = 4,
}

enums.activityType = enum {
	default   = 0,
	streaming = 1,
	listening = 2,
	custom    = 4,
}

enums.activityFlag = enum {
	instance    = flag(0),
	join        = flag(1),
	spectate    = flag(2),
	joinRequest = flag(3),
	sync        = flag(4),
	play        = flag(5),
}

enums.status = enum {
	online = 'online',
	idle = 'idle',
	doNotDisturb = 'dnd',
	invisible = 'invisible',
}

enums.gameType = enum { -- NOTE: deprecated; use activityType
	default   = 0,
	streaming = 1,
	listening = 2,
	custom    = 4,
}

enums.verificationLevel = enum {
	none     = 0,
	low      = 1,
	medium   = 2,
	high     = 3, -- (╯°□°）╯︵ ┻━┻
	veryHigh = 4, -- ┻━┻ ﾐヽ(ಠ益ಠ)ノ彡┻━┻
}

enums.explicitContentLevel = enum {
	none   = 0,
	medium = 1,
	high   = 2,
}

enums.premiumTier = enum {
	none  = 0,
	tier1 = 1,
	tier2 = 2,
	tier3 = 3,
}

enums.permission = enum {
	createInstantInvite = flag(0),
	kickMembers         = flag(1),
	banMembers          = flag(2),
	administrator       = flag(3),
	manageChannels      = flag(4),
	manageGuild         = flag(5),
	addReactions        = flag(6),
	viewAuditLog        = flag(7),
	prioritySpeaker     = flag(8),
	stream              = flag(9),
	viewChannel         = flag(10),
	sendMessages        = flag(11),
	sendTextToSpeech    = flag(12),
	manageMessages      = flag(13),
	embedLinks          = flag(14),
	attachFiles         = flag(15),
	readMessageHistory  = flag(16),
	mentionEveryone     = flag(17),
	useExternalEmojis   = flag(18),
	viewGuildInsights   = flag(19),
	connect             = flag(20),
	speak               = flag(21),
	muteMembers         = flag(22),
	deafenMembers       = flag(23),
	moveMembers         = flag(24),
	useVoiceActivity    = flag(25),
	changeNickname      = flag(26),
	manageNicknames     = flag(27),
	manageRoles         = flag(28),
	manageWebhooks      = flag(29),
	manageEmojis        = flag(30),
	useSlashCommands    = flag(31),
	requestToSpeak      = flag(32),
	manageEvents        = flag(33),
	manageThreads       = flag(34),
	usePublicThreads    = flag(35),
	usePrivateThreads   = flag(36),
}

enums.messageFlag = enum {
	crossposted          = flag(0),
	isCrosspost          = flag(1),
	suppressEmbeds       = flag(2),
	sourceMessageDeleted = flag(3),
	urgent               = flag(4),
}

enums.actionType = enum {
	guildUpdate            = 1,
	channelCreate          = 10,
	channelUpdate          = 11,
	channelDelete          = 12,
	channelOverwriteCreate = 13,
	channelOverwriteUpdate = 14,
	channelOverwriteDelete = 15,
	memberKick             = 20,
	memberPrune            = 21,
	memberBanAdd           = 22,
	memberBanRemove        = 23,
	memberUpdate           = 24,
	memberRoleUpdate       = 25,
	memberMove             = 26,
	memberDisconnect       = 27,
	botAdd                 = 28,
	roleCreate             = 30,
	roleUpdate             = 31,
	roleDelete             = 32,
	inviteCreate           = 40,
	inviteUpdate           = 41,
	inviteDelete           = 42,
	webhookCreate          = 50,
	webhookUpdate          = 51,
	webhookDelete          = 52,
	emojiCreate            = 60,
	emojiUpdate            = 61,
	emojiDelete            = 62,
	messageDelete          = 72,
	messageBulkDelete      = 73,
	messagePin             = 74,
	messageUnpin           = 75,
	integrationCreate      = 80,
	integrationUpdate      = 81,
	integrationDelete      = 82,
	stageInstanceCreate    = 83,
	stageInstanceUpdate    = 84,
	stageInstanceDelete    = 85,
}

enums.logLevel = enum {
	none    = 0,
	error   = 1,
	warning = 2,
	info    = 3,
	debug   = 4,
}

-- Backported from dev
enums.userFlag = enum {
	discordEmployee      = flag(0),
	discordPartner       = flag(1),
	hypesquadEvents      = flag(2),
	bugHunterLevel1      = flag(3),
	-- unused            = flag(4),
	-- unused            = flag(5),
	houseBravery         = flag(6),
	houseBrilliance      = flag(7),
	houseBalance         = flag(8),
	earlySupporter       = flag(9),
	teamUser             = flag(10),
	-- unused            = flag(11),
	system               = flag(12),
	-- unused            = flag(13),
	bugHunterLevel2      = flag(14),
	-- unused            = flag(15),
	verifiedBot          = flag(16),
	verifiedBotDeveloper = flag(17),
	certifiedModerator   = flag(18),
}

enums.gatewayIntent = enum {
	guilds                = flag(0),
	guildMembers          = flag(1),
	guildBans             = flag(2),
	guildEmojis           = flag(3),
	guildIntegrations     = flag(4),
	guildWebhooks         = flag(5),
	guildInvites          = flag(6),
	guildVoiceStates      = flag(7),
	guildPresences        = flag(8),
	guildMessages         = flag(9),
	guildMessageReactions = flag(10),
	guildMessageTyping    = flag(11),
	directMessage         = flag(12),
	directMessageRections = flag(13),
	directMessageTyping   = flag(14),
}

enums.premiumType = enum {
	none = 0,
	nitroClassic = 1,
	nitro = 2
}

enums.commandOptionType = enum {
	subCommand      = 1,
	subCommandGroup = 2,
	string          = 3,
	integer         = 4,
	boolean         = 5,
	user            = 6,
	channel         = 7,
	role            = 8,
	mentionable     = 9,
	number          = 10,
}

enums.commandPermissionType = enum {
	role = 1,
	user = 2,
}

enums.interactionRequestType = enum {
	ping               = 1,
	applicationCommand = 2,
	messageComponent   = 3,
}

enums.interactionResponseType = enum {
	pong                                 = 1,
	-- unused (acknowledge)              = 2,
	-- unused (channelMessage)           = 3,
	channelMessageWithSource             = 4,
	deferredChannelMessageWithSource     = 5,
	deferredUpdateMessage                = 6,
	updateMessage                        = 7,
	applicationCommandAutocompleteResult = 8
}

enums.componentType = enum {
	actionRow  = 1,
	button     = 2,
	selectMenu = 3,
}

enums.buttonStyle = enum {
	primary   = 1, -- blurple
	secondary = 2, -- green
	success   = 3, -- grey
	danger    = 4, -- red
	link      = 5, -- grey with link icon
}

enums.interactionResponseFlag = enum {
	ephemeral = flag(6),
}

enums.applicationFlag = enum {
	gatewayPresence               = flag(12),
	gatewayPresenceLimited        = flag(13),
	gatewayGuildMembers           = flag(14),
	gatewayGuildMembersLimited    = flag(15),
	verificationPendingGuildLimit = flag(16),
	embedded                      = flag(17),
}

return enums
