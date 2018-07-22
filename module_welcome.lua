local client = Client
local config = Config
local discordia = Discordia

local alertChannel = "428569760872136705"
local joinText = "Bienvenue {user} ! Merci d'aller lire les <#358924179954860033> et pense à rejoindre les canaux qui t'intéressent dans <#440592843489280011>."
local leaveText = "{user} a quitté le serveur. :wave:"
local banText = "{user} a été banni du serveur. :hammer:"
local unbanText = "{user} a été débanni du serveur."

Module.Name = "welcome"

function Module:OnMemberJoin(member)
	local alertChannel = client:getChannel(alertChannel)
	local message = joinText
	message = message:gsub("{user}", member.user.mentionString)
	
	alertChannel:send(message)
end

function Module:OnMemberLeave(member)
	local alertChannel = client:getChannel(alertChannel)
	local message = leaveText
	message = message:gsub("{user}", member.user.fullname)
	
	alertChannel:send(message)
end

function Module:OnUserBan(user, guild)
	local alertChannel = client:getChannel(alertChannel)
	local message = banText
	message = message:gsub("{user}", user.fullname)
	
	alertChannel:send(message)
end

function Module:OnUserUnban(user, guild)
	local alertChannel = client:getChannel(alertChannel)
	local message = unbanText
	message = message:gsub("{user}", user.fullname)

	alertChannel:send(message)
end