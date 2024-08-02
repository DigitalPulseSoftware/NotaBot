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

local function flag(n, as64bits)
	return bit.lshift(as64bits and 1ULL or 1, n)
end

local function flag64(n, as64bits)
	return bit.lshift(1ULL, n)
end

enums.defaultAvatar = enum {
	blurple = 0,
	gray    = 1,
	green   = 2,
	orange  = 3,
	red     = 4,
	pink    = 5,
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
	newsThread     = 10,
	publicThread   = 11,
	privateThread  = 12,
	stageVoice     = 13,
	directory      = 14,
	forum          = 15
}

enums.webhookType = enum {
	incoming        = 1,
	channelFollower = 2,
	application     = 3,
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
	contextMenuCommand                      = 23,
	autoModerationAction                    = 24,
	roleSubscriptionPurchase                = 25,
	interactionPremiumUpsell                = 26,
	stageStart                              = 27,
	stageEnd                                = 28,
	stageSpeaker                            = 29,
--  unused                                  = 30,
	stageTopic                              = 31,
	applicationPremiumSubscription          = 32,
--  unused                                  = 33,
--  unused                                  = 34,
--  unused                                  = 35,
	guildIncidentAlertModeEnabled           = 36,
	guildIncidentAlertModeDisabled          = 37,
	guildIncidentReportRaid                 = 38,
	guildIncidentReportFalseAlarm           = 39,
--  unused                                  = 40,
--  unused                                  = 41,
--  unused                                  = 42,
--  unused                                  = 43,
	purchaseNotification                    = 44,
}

enums.relationshipType = enum {
	none            = 0,
	friend          = 1,
	blocked         = 2,
	pendingIncoming = 3,
	pendingOutgoing = 4,
	implicit        = 5,
}

enums.activityType = enum {
	default   = 0,
	streaming = 1,
	listening = 2,
	watching  = 3,
	custom    = 4,
	competing = 5,
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
	online       = 'online',
	idle         = 'idle',
	doNotDisturb = 'dnd',
	invisible    = 'invisible', -- only sent?
	offline      = 'offline', -- only received?
}

enums.gameType = enum { -- NOTE: deprecated; use activityType
	default   = 0,
	streaming = 1,
	listening = 2,
	watching  = 3,
	custom    = 4,
	competing = 5,
}

-- https://discord.com/developers/docs/resources/guild#guild-object-verification-level
enums.verificationLevel = enum {
	none     = 0,
	low      = 1,
	medium   = 2,
	high     = 3, -- (╯°□°）╯︵ ┻━┻
	veryHigh = 4, -- ┻━┻ ﾐヽ(ಠ益ಠ)ノ彡┻━┻
}

-- https://discord.com/developers/docs/resources/guild#guild-object-explicit-content-filter-level
enums.explicitContentLevel = enum {
	disabled            = 0,
	membersWithoutRoles = 1,
	allmembers          = 2,
}

-- https://discord.com/developers/docs/resources/guild#guild-object-premium-tier
enums.premiumTier = enum {
	none  = 0,
	tier1 = 1,
	tier2 = 2,
	tier3 = 3,
}

-- https://discord.com/developers/docs/topics/permissions#permissions-bitwise-permission-flags
enums.permission = enum {
	createInstantInvite              = flag64(0),
	kickMembers                      = flag64(1),
	banMembers                       = flag64(2),
	administrator                    = flag64(3),
	manageChannels                   = flag64(4),
	manageGuild                      = flag64(5),
	addReactions                     = flag64(6),
	viewAuditLog                     = flag64(7),
	prioritySpeaker                  = flag64(8),
	stream                           = flag64(9),
	viewChannel                      = flag64(10),
	sendMessages                     = flag64(11),
	sendTextToSpeech                 = flag64(12),
	manageMessages                   = flag64(13),
	embedLinks                       = flag64(14),
	attachFiles                      = flag64(15),
	readMessageHistory               = flag64(16),
	mentionEveryone                  = flag64(17),
	useExternalEmojis                = flag64(18),
	viewGuildInsights                = flag64(19),
	connect                          = flag64(20),
	speak                            = flag64(21),
	muteMembers                      = flag64(22),
	deafenMembers                    = flag64(23),
	moveMembers                      = flag64(24),
	useVoiceActivity                 = flag64(25),
	changeNickname                   = flag64(26),
	manageNicknames                  = flag64(27),
	manageRoles                      = flag64(28),
	manageWebhooks                   = flag64(29),
	manageEmojis                     = flag64(30),
	useSlashCommands                 = flag64(31),
	requestToSpeak                   = flag64(32),
	manageEvents                     = flag64(33),
	manageThreads                    = flag64(34),
	usePublicThreads                 = flag64(35),
	usePrivateThreads                = flag64(36),
	useExternalStickers              = flag64(37),
	sendMessagesInThreads            = flag64(38),
	startEmbeddedActivities          = flag64(39),
	moderateMembers                  = flag64(40),
	viewCreatorMonetizationAnalitics = flag64(41),
	useSoundBoard                    = flag64(42),
	createGuildExpressions           = flag64(43),
	createEvents                     = flag64(44),
	useExternalSounds                = flag64(45),
	sendVoiceMessages                = flag64(46),
--  unused                           = flag64(47),
	setVoiceChannelStatus            = flag64(48),
	sendPolls                        = flag64(49),
	useExternalApps                  = flag64(50),
}

enums.messageFlag = enum {
	crossposted                = flag(0),
	isCrosspost                = flag(1),
	suppressEmbeds             = flag(2),
	sourceMessageDeleted       = flag(3),
	urgent                     = flag(4),
	hasThread                  = flag(5),
	ephemeral                  = flag(6),
	loading                    = flag(7),
	threadFailedToMentionRoles = flag(8),
--  unused                     = flag(9),
--  unused                     = flag(10),
--  unused                     = flag(11),
	suppressNotification       = flag(12),
	isVoiceMessage             = flag(13),
}

-- https://discord.com/developers/docs/topics/gateway#list-of-intents
-- https://discord.com/developers/docs/topics/gateway#privileged-intents
enums.gatewayIntent = enum {
	guilds                = flag(0),
	guildMembers          = flag(1), -- privileged
	guildModeration       = flag(2),
	guildEmojis           = flag(3),
	guildIntegrations     = flag(4),
	guildWebhooks         = flag(5),
	guildInvites          = flag(6),
	guildVoiceStates      = flag(7),
	guildPresences        = flag(8), -- privileged
	guildMessages         = flag(9),
	guildMessageReactions = flag(10),
	guildMessageTyping    = flag(11),
	directMessage         = flag(12),
	directMessageRections = flag(13),
	directMessageTyping   = flag(14),
	messageContent        = flag(15), -- privileged
	guildScheduledEvents  = flag(16),
	-- unused             = flag(17),
	-- unused             = flag(18),
	-- unused             = flag(19),
	autoModConfiguration  = flag(20),
	autoModExecution      = flag(21),
	guildMessagePolls     = flag(24),
	directMessagePolls    = flag(25),
}

-- https://discord.com/developers/docs/resources/audit-log#audit-log-entry-object-audit-log-events
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
	stickerCreate          = 90,
	stickerUpdate          = 91,
	stickerDelete          = 92,
	eventCreate            = 100,
	eventUpdate            = 101,
	eventDelete            = 102,
	threadCreate           = 110,
	threadUpdate           = 111,
	threadDelete           = 112,
	autoModRuleCreate      = 140,
	autoModRuleUpdate      = 141,
	autoModRuleDelete      = 142,
	autoModMessageBlock    = 143,
	autoModMessageFlag     = 144,
	autoModUserTimeout     = 145,
	creatorMonetizationRequestCreated = 150,
	creatorMonetizationTermsAccepted  = 151,
	onboardingPromptCreated  = 163,
	onboardingPromptUpdated  = 164,
	onboardingPromptDeleted  = 165,
	onboardingCreate         = 166,
	onboardingUpdate         = 167,
	homeSettingsCreate       = 190,
	homeSettingsUpdate       = 191,
	voiceChannelStatusUpdate = 192,
	voiceChannelStatusDelete = 193,
}

enums.logLevel = enum {
	none    = 0,
	error   = 1,
	warning = 2,
	info    = 3,
	debug   = 4,
}

-- https://discord.com/developers/docs/resources/user#user-object-user-flags
enums.userFlag = enum {
	discordEmployee      = flag(0),
	discordPartner       = flag(1),
	hypesquadEvents      = flag(2),
	bugHunterLevel1      = flag(3),
--  unused               = flag(4),
--  unused               = flag(5),
	houseBravery         = flag(6),
	houseBrilliance      = flag(7),
	houseBalance         = flag(8),
	earlySupporter       = flag(9),
	teamUser             = flag(10),
--  unused               = flag(11),
	system               = flag(12),
--  unused               = flag(13),
	bugHunterLevel2      = flag(14),
--  unused               = flag(15),
	verifiedBot          = flag(16),
	verifiedBotDeveloper = flag(17),
	certifiedModerator   = flag(18),
	botHttpInteractions  = flag(19),
--  unused               = flag(20),
--  unused               = flag(21),
	activeDeveloper      = flag(22),
}

-- https://discord.com/developers/docs/resources/user#connection-object-visibility-types
enums.visibilityType = enum {
	none     = 0,
	everyone = 1,
}

-- https://discord.com/developers/docs/resources/user#user-object-premium-types
enums.premiumType = enum {
	none         = 0,
	nitroClassic = 1,
	nitro        = 2,
	nitroBasic   = 3,
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
	applicationCommandAutocompleteResult = 8,
	modal                                = 9
}

-- https://discord.com/developers/docs/interactions/message-components#component-object-component-types
enums.componentType = enum {
	actionRow         = 1,
	button            = 2,
	stringSelect      = 3,
	textInput         = 4,
	userSelect        = 5,
	roleSelect        = 6,
	mentionableSelect = 7,
	channelSelect     = 8,
}

-- https://discord.com/developers/docs/interactions/message-components#button-object-button-styles
enums.buttonStyle = enum {
	primary   = 1, -- blurple
	secondary = 2, -- green
	success   = 3, -- grey
	danger    = 4, -- red
	link      = 5, -- grey with link icon
	premium   = 6, -- blurple + shop icon + SKU name + SKU price
}

-- https://discord.com/developers/docs/interactions/message-components#text-input-object-text-input-styles
enums.textInputStyle = enum {
	short     = 1,
	paragraph = 2,
}

-- https://discord.com/developers/docs/interactions/receiving-and-responding#interaction-response-object-messages
enums.interactionResponseFlag = enum {
	suppressEmbeds        = flag(2),
	ephemeral             = flag(6),
	suppressNotifications = flag(12),
}

-- https://discord.com/developers/docs/resources/application#application-object-application-flags
enums.applicationFlag = enum {
	applicationAutoModRuleCreateBadge = flag(6),
	gatewayPresence                   = flag(12),
	gatewayPresenceLimited            = flag(13),
	gatewayGuildMembers               = flag(14),
	gatewayGuildMembersLimited        = flag(15),
	verificationPendingGuildLimit     = flag(16),
	embedded                          = flag(17),
	gatewayMessageContent             = flag(18),
	gatewayMessageContentLimited      = flag(19),
	applicationCommandBadge           = flag(23),
}

-- https://discord.com/developers/docs/resources/guild-scheduled-event#guild-scheduled-event-object-guild-scheduled-event-privacy-level
enums.scheduledEventsPrivacyLevel = enum {
	guild_only = 2,
}

-- https://discord.com/developers/docs/resources/guild-scheduled-event#guild-scheduled-event-object-guild-scheduled-event-entity-types
enums.scheduledEventsEntityTypes = enum {
	stage_instance = 1,
	voice          = 2,
	external       = 3,
}

return enums
