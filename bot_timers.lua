-- Copyright (C) 2020 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local timer = {}
timer.__index = timer

function timer:Execute()
	if (not self.Callback) then
		return
	end

	self.Callback()

	local repeatTimer = false
	if (self.Repetition > 0) then
		self.Repetition = self.Repetition - 1
		if (self.Repetition > 0) then
			repeatTimer = true
		end
	elseif (self.Repetition < 0) then
		repeatTimer = true
	end

	if (repeatTimer) then
		Bot:ScheduleAction(os.time() + self.Interval, function () self:Execute() end)
	end
end

function timer:Stop()
	self.Callback = nil
end

Bot.ScheduledActions = {}

function Bot:CreateRepeatTimer(interval, repetition, callback)
	local nextTrigger = os.time() + interval
	local timer = setmetatable({
		Interval = interval,
		Repetition = repetition,
		Callback = callback
	}, timer)

	self:ScheduleAction(nextTrigger, function() timer:Execute() end)

	return timer
end

function Bot:ScheduleTimer(timestamp, callback)
	local timer = setmetatable({
		Repetition = 0,
		Callback = callback
	}, timer)

	self:ScheduleAction(timestamp, function() timer:Execute() end)

	return timer
end

function Bot:ScheduleAction(timestamp, callback)
	assert(timestamp, callback)

	local actions = self.ScheduledActions

	local index = #actions + 1
	for i,a in pairs(actions) do
		if (a.time > timestamp) then
			index = i
			break
		end
	end

	table.insert(actions, index, { time = timestamp, cb = callback })
end

Bot.Clock:on("sec", function ()
	local timestamp = os.time()
	local actions = Bot.ScheduledActions

	local executedAction = 0
	for _, action in pairs(actions) do
		if (action.time > timestamp) then
			break
		end

		Bot:ProtectedCall("Scheduled action", action.cb)
		executedAction = executedAction + 1
	end

	for i = 1, executedAction do
		table.remove(actions, 1)
	end
end)
