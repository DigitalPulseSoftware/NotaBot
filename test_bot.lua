-- test_bot.lua
-- Second bot that sends commands to NotaBot and logs responses
-- Usage: luvit test_bot.lua
--
-- Required env vars (or fill in directly below):
--   TEST_BOT_TOKEN    — token for your second bot app
--   TARGET_BOT_ID     — user ID of NotaBot
--   TEST_GUILD_ID     — guild (server) ID to run tests in
--   TEST_CHANNEL_ID   — channel ID to send commands in
--   TEST_USER_ID      — a real user ID to use as target for moderation commands
--   BOT_PREFIX        — command prefix NotaBot uses (default "!")

local discordia = require('discordia')
local enums = discordia.enums

-- ── Configuration ────────────────────────────────────────────────────────────

local TOKEN        = os.getenv("TEST_BOT_TOKEN")    or ""  -- token of your test bot app
local TARGET_BOT   = os.getenv("TARGET_BOT_ID")     or ""  -- user ID of the NotaBot instance
local GUILD_ID     = os.getenv("TEST_GUILD_ID")     or ""  -- your server ID
local CHANNEL_ID   = os.getenv("TEST_CHANNEL_ID")   or ""  -- test channel ID
local TARGET_USER  = os.getenv("TEST_USER_ID")      or ""  -- a member ID to use as moderation target
local PREFIX       = os.getenv("BOT_PREFIX")        or "!"

assert(TOKEN ~= "", "TEST_BOT_TOKEN is required — set the env var or paste it above")

-- ── Helpers ───────────────────────────────────────────────────────────────────

local RESPONSE_TIMEOUT = 5   -- seconds to wait for a response per command
local DELAY_BETWEEN    = 2   -- seconds between commands

local results  = {}  -- { name, sent, response, passed }
local pending  = nil -- { name, resolve }
local queue    = {}  -- list of test functions to run in order

local function p(fmt, ...)
    print(string.format(fmt, ...))
end

local function u(userId)
    return "<@" .. userId .. ">"
end

-- ── Test runner ───────────────────────────────────────────────────────────────

local function runTests(channel)
    local timer = require('timer')

    for _, test in ipairs(queue) do
        local ok, err = pcall(test, channel)
        if not ok then
            p("[ERROR] %s", tostring(err))
        end
        timer.sleep(DELAY_BETWEEN * 1000)
    end

    -- Print summary
    print("\n" .. string.rep("─", 60))
    print(string.format("%-40s %-8s %s", "COMMAND", "RESULT", "RESPONSE"))
    print(string.rep("─", 60))
    local passed, failed = 0, 0
    for _, r in ipairs(results) do
        local label = r.passed and "PASS" or "FAIL"
        local resp  = r.response and r.response:sub(1, 60) or "(no response)"
        print(string.format("%-40s %-8s %s", r.name:sub(1, 40), label, resp))
        if r.passed then passed = passed + 1 else failed = failed + 1 end
    end
    print(string.rep("─", 60))
    print(string.format("Total: %d passed, %d failed / %d", passed, failed, passed + failed))
end

-- ── Client ────────────────────────────────────────────────────────────────────

local client = discordia.Client({
    gatewayIntents = bit.bor(
        enums.gatewayIntent.guilds,
        enums.gatewayIntent.guildMessages,
        enums.gatewayIntent.messageContent
    )
})

-- Send a command and wait up to RESPONSE_TIMEOUT seconds for a reply from NotaBot
local function send(channel, cmdName, cmdText)
    local done     = false
    local response = nil

    -- Set up listener before sending
    local function listener(msg)
        if msg.channel.id == CHANNEL_ID and msg.author.id == TARGET_BOT then
            response = msg.content
            done = true
        end
    end
    client:on('messageCreate', listener)

    channel:send(PREFIX .. cmdText)

    -- Poll for response
    local elapsed = 0
    local interval = 200  -- ms
    while not done and elapsed < RESPONSE_TIMEOUT * 1000 do
        require('timer').sleep(interval)
        elapsed = elapsed + interval
    end

    client:removeListener('messageCreate', listener)

    local passed = done  -- got any response = pass (NotaBot responded)
    table.insert(results, { name = cmdName, sent = PREFIX .. cmdText, response = response, passed = passed })

    if passed then
        p("[PASS] %-35s → %s", cmdName, (response or ""):sub(1, 80))
    else
        p("[FAIL] %-35s → (no response within %ds)", cmdName, RESPONSE_TIMEOUT)
    end

    return response
end

-- ── Test definitions ──────────────────────────────────────────────────────────
-- Each function receives `channel` and calls send()

-- help
table.insert(queue, function(ch) send(ch, "help",            "help") end)
table.insert(queue, function(ch) send(ch, "help ban",        "help ban") end)

-- userinfo / roleinfo (safe, read-only)
table.insert(queue, function(ch) send(ch, "userinfo (self)", "userinfo") end)
table.insert(queue, function(ch) send(ch, "userinfo @user",  "userinfo " .. u(TARGET_USER)) end)

-- warn (requires Ban Members perm on NotaBot)
table.insert(queue, function(ch) send(ch, "warn @user",           "warn " .. u(TARGET_USER) .. " test warning") end)
table.insert(queue, function(ch) send(ch, "warnlist @user",       "warnlist " .. u(TARGET_USER)) end)
table.insert(queue, function(ch) send(ch, "clearwarns @user",     "clearwarns " .. u(TARGET_USER)) end)

-- mute / unmute
table.insert(queue, function(ch) send(ch, "mute @user",      "mute " .. u(TARGET_USER) .. " 1m test") end)
table.insert(queue, function(ch) send(ch, "unmute @user",    "unmute " .. u(TARGET_USER)) end)

-- kick (commented out by default to avoid actually kicking)
-- table.insert(queue, function(ch) send(ch, "kick @user", "kick " .. u(TARGET_USER) .. " test") end)

-- ban / unban (commented out by default — uncomment carefully)
-- table.insert(queue, function(ch) send(ch, "ban @user",   "ban " .. u(TARGET_USER) .. " 1m test ban") end)
-- table.insert(queue, function(ch) send(ch, "unban @user", "unban " .. u(TARGET_USER)) end)

-- raid commands
table.insert(queue, function(ch) send(ch, "rulehelp",     "rulehelp") end)
table.insert(queue, function(ch) send(ch, "listrules",    "listrules") end)
table.insert(queue, function(ch) send(ch, "addrule",      "addrule kick newerThan 2000-01-01") end)
table.insert(queue, function(ch) send(ch, "delrule 1",    "delrule 1") end)
table.insert(queue, function(ch) send(ch, "clearrules",   "clearrules") end)
-- lockserver / unlockserver omitted by default (affects whole server)
-- table.insert(queue, function(ch) send(ch, "lockserver",   "lockserver 1m test lock") end)
-- table.insert(queue, function(ch) send(ch, "unlockserver", "unlockserver") end)

-- prune (will delete messages in the test channel)
table.insert(queue, function(ch) send(ch, "prune 2", "prune 2") end)

-- purge (dry run only — safe)
table.insert(queue, function(ch) send(ch, "drypurge 999d", "drypurge 999d") end)

-- pin / unpin — needs a message ID; we'll pin the help response if one exists
-- Skipped here since we don't know message IDs in advance. Test manually.

-- quote
-- Skipped (needs a known message ID). Test manually.

-- clean_urls
table.insert(queue, function(ch) send(ch, "listcleanrules",                     "listcleanrules") end)
table.insert(queue, function(ch) send(ch, "addcleanrule utm_source",            "addcleanrule utm_source") end)
table.insert(queue, function(ch) send(ch, "addcleanrules utm_medium,fbclid",    "addcleanrules utm_medium,fbclid") end)
table.insert(queue, function(ch) send(ch, "cleanurl",                           "cleanurl https://example.com?utm_source=test&utm_medium=email") end)
table.insert(queue, function(ch) send(ch, "removecleanrule utm_source",         "removecleanrule utm_source") end)
table.insert(queue, function(ch) send(ch, "clearcleanrules",                    "clearcleanrules") end)

-- message
table.insert(queue, function(ch) send(ch, "sendmessage",       "sendmessage Hello from test bot!") end)
table.insert(queue, function(ch) send(ch, "addreply",          "addreply testping testpong") end)
table.insert(queue, function(ch) send(ch, "listreplies",       "listreplies") end)
table.insert(queue, function(ch) send(ch, "editreply",         "editreply testping testpong2") end)
table.insert(queue, function(ch) send(ch, "addalias",          "addalias tp testping") end)
table.insert(queue, function(ch) send(ch, "removealias",       "removealias tp") end)
table.insert(queue, function(ch) send(ch, "removereply",       "removereply testping") end)

-- channels (reaction roles)
table.insert(queue, function(ch) send(ch, "channelconfig",     "channelconfig") end)

-- nickname
table.insert(queue, function(ch) send(ch, "drynukerename",     "drynukerename") end)
table.insert(queue, function(ch) send(ch, "managenicknames",   "managenicknames") end)

-- poll
table.insert(queue, function(ch) send(ch, "createpoll",        'createpoll "Test Poll?" #' .. CHANNEL_ID .. " 1m") end)
table.insert(queue, function(ch) send(ch, "poll add A",        "poll add :one: Choice A") end)
table.insert(queue, function(ch) send(ch, "poll add B",        "poll add :two: Choice B") end)
table.insert(queue, function(ch) send(ch, "cancelpoll",        "cancelpoll") end)

-- modmail
table.insert(queue, function(ch) send(ch, "newticket",         "newticket automated test ticket") end)
table.insert(queue, function(ch) send(ch, "closeticket",       "closeticket test done") end)

-- ── Entry point ───────────────────────────────────────────────────────────────

client:on('ready', function()
    p("Test bot logged in as %s#%s", client.user.username, client.user.discriminator)

    local guild   = client:getGuild(GUILD_ID)
    if not guild then
        p("[FATAL] Guild %s not found — is the test bot invited?", GUILD_ID)
        client:stop()
        return
    end

    local channel = guild:getChannel(CHANNEL_ID)
    if not channel then
        p("[FATAL] Channel %s not found", CHANNEL_ID)
        client:stop()
        return
    end

    p("Running %d tests in #%s ...\n", #queue, channel.name)

    coroutine.wrap(function()
        require('timer').sleep(2000)  -- give the main bot a moment to be ready
        runTests(channel)
        p("\nDone. Disconnecting.")
        client:stop()
    end)()
end)

client:run("Bot " .. TOKEN)
