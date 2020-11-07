local package = require('../package')

return {
	NS_PER_US = 1000,
	US_PER_MS = 1000,
	MS_PER_S = 1000,
	S_PER_MIN = 60,
	MIN_PER_HOUR = 60,
	HOUR_PER_DAY = 24,
	DAY_PER_WEEK = 7,
	DEFAULT_AVATARS = 5,
	DISCORD_EPOCH = 1420070400000,
	GATEWAY_VERSION = 8,
	GATEWAY_ENCODING = 'json',
	JSON_CONTENT_TYPE = 'application/json',
	USER_AGENT = ('DiscordBot (%s, %s)'):format(package.homepage, package.version),
	USER_PATTERN = '<@!?(%d+)>',
	ROLE_PATTERN = '<@&(%d+)>',
	CHANNEL_PATTERN = '<#(%d+)>',
	EMOJI_PATTERN = '<a?:[%w_]+:(%d+)>',
	JUMP_LINK_FMT = "https://discord.com/channels/%s/%s/%s",
	CDN_BASE_URL = "https://cdn.discordapp.com",
	API_BASE_URL = "https://discord.com/api/v8",
}
