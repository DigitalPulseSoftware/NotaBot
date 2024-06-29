-- Copyright (C) 2020 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local timer = require('timer')

local TimerClass = {}
TimerClass.__index = TimerClass

function TimerClass:Execute()
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

function TimerClass:Stop()
	self.Callback = nil
end

Bot.ScheduledActions = {}
Bot.PendingScheduledActions = {}
Bot.LastTimerExecution = -1

function Bot:CreateRepeatTimer(interval, repetition, callback)
	local nextTrigger = os.time() + interval
	local timer = setmetatable({
		Interval = interval,
		Repetition = repetition,
		Callback = callback
	}, TimerClass)

	self:ScheduleAction(nextTrigger, function() timer:Execute() end)

	return timer
end

function Bot:ScheduleTimer(timestamp, callback)
	local timer = setmetatable({
		Repetition = 0,
		Callback = callback
	}, TimerClass)

	self:ScheduleAction(timestamp, function() timer:Execute() end)

	return timer
end

function Bot:ScheduleAction(timestamp, callback)
	assert(type(timestamp) == "number")
	assert(type(callback) == "function")

	table.insert(self.PendingScheduledActions, { time = timestamp, cb = callback })
end

timer.setInterval(1000, function()
	local timestamp = os.time()

	local actions = Bot.ScheduledActions

	-- Add pending scheduled actions (to prevent adding them while executing timer)
	if #Bot.PendingScheduledActions > 0 then
		for _, actionData in ipairs(Bot.PendingScheduledActions) do
			local index = #actions + 1
			for i, a in ipairs(actions) do
				if a.time > actionData.time then
					index = i
					break
				end
			end

			table.insert(actions, index, actionData)
		end
		Bot.PendingScheduledActions = {}
	end

	local executedAction = 0
	for _, action in pairs(actions) do
		if action.time > timestamp then
			break
		end

		Bot:ProtectedCall("Scheduled action", coroutine.wrap(action.cb))
		executedAction = executedAction + 1
	end

	for i = 1, executedAction do
		table.remove(actions, 1)
	end

	Bot.LastTimerExecution = timestamp
end)
