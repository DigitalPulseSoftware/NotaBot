"""
test_bot.py — sends NotaBot commands and checks for responses
Usage: python3 test_bot.py

Fill in the CONFIG section below or set environment variables.
"""

import asyncio
import os
import discord

# ── CONFIG ────────────────────────────────────────────────────────────────────

TOKEN       = os.getenv("TEST_BOT_TOKEN")  or ""   # token of your test bot app
TARGET_BOT  = os.getenv("TARGET_BOT_ID")  or ""   # user ID of the NotaBot instance
GUILD_ID    = int(os.getenv("TEST_GUILD_ID")   or "0")  # your server ID
CHANNEL_ID  = int(os.getenv("TEST_CHANNEL_ID") or "0")  # test channel ID
TARGET_USER = os.getenv("TEST_USER_ID")   or ""   # a member ID to use as moderation target
PREFIX      = os.getenv("BOT_PREFIX")     or "!"

RESPONSE_TIMEOUT = 6    # seconds to wait for NotaBot to reply
DELAY_BETWEEN    = 2.5  # seconds between commands

# ── Results ───────────────────────────────────────────────────────────────────

results = []  # (name, passed, response)

# ── Client ────────────────────────────────────────────────────────────────────

intents = discord.Intents.default()
intents.message_content = True
client = discord.Client(intents=intents)

def u(user_id):
    return f"<@{user_id}>"

async def send_and_wait(channel, name, cmd):
    """Send a prefixed command and wait for NotaBot to reply."""
    text = PREFIX + cmd

    future = asyncio.get_event_loop().create_future()

    def check(msg):
        return (
            msg.channel.id == CHANNEL_ID
            and str(msg.author.id) == TARGET_BOT
            and not future.done()
        )

    async def listener(msg):
        if check(msg):
            future.set_result(msg.content)

    client.event(listener)  # register under 'on_message' would conflict; use wait_for instead

    await channel.send(text)

    try:
        response = await asyncio.wait_for(
            client.wait_for("message", check=check),
            timeout=RESPONSE_TIMEOUT
        )
        content = response.content
        passed  = True
    except asyncio.TimeoutError:
        content = None
        passed  = False

    results.append((name, passed, content))

    status = "PASS" if passed else "FAIL"
    snippet = (content or "(no response)")[:80]
    print(f"[{status}] {name:<38} → {snippet}")

    return content

async def run_tests(channel):
    s = lambda name, cmd: send_and_wait(channel, name, cmd)

    # help
    await s("help",               "help")
    await asyncio.sleep(DELAY_BETWEEN)
    await s("help ban",           "help ban")
    await asyncio.sleep(DELAY_BETWEEN)

    # userinfo
    await s("userinfo (self)",    "userinfo")
    await asyncio.sleep(DELAY_BETWEEN)
    await s("userinfo @user",     f"userinfo {u(TARGET_USER)}")
    await asyncio.sleep(DELAY_BETWEEN)

    # roleinfo — adjust role name to one that exists on your server
    await s("roleinfo",           "roleinfo @everyone")
    await asyncio.sleep(DELAY_BETWEEN)

    # warn
    await s("warn @user",         f"warn {u(TARGET_USER)} test warning")
    await asyncio.sleep(DELAY_BETWEEN)
    await s("warnlist @user",     f"warnlist {u(TARGET_USER)}")
    await asyncio.sleep(DELAY_BETWEEN)
    await s("clearwarns @user",   f"clearwarns {u(TARGET_USER)}")
    await asyncio.sleep(DELAY_BETWEEN)

    # mute / unmute
    await s("mute @user",         f"mute {u(TARGET_USER)} 1m test")
    await asyncio.sleep(DELAY_BETWEEN)
    await s("unmute @user",       f"unmute {u(TARGET_USER)}")
    await asyncio.sleep(DELAY_BETWEEN)

    # raid
    await s("rulehelp",           "rulehelp")
    await asyncio.sleep(DELAY_BETWEEN)
    await s("listrules",          "listrules")
    await asyncio.sleep(DELAY_BETWEEN)
    await s("addrule",            "addrule kick newerThan 2000-01-01")
    await asyncio.sleep(DELAY_BETWEEN)
    await s("delrule 1",          "delrule 1")
    await asyncio.sleep(DELAY_BETWEEN)
    await s("clearrules",         "clearrules")
    await asyncio.sleep(DELAY_BETWEEN)

    # prune
    await s("prune 2",            "prune 2")
    await asyncio.sleep(DELAY_BETWEEN)

    # purge (dry run only)
    await s("drypurge 999d",      "drypurge 999d")
    await asyncio.sleep(DELAY_BETWEEN)

    # clean_urls
    await s("listcleanrules",     "listcleanrules")
    await asyncio.sleep(DELAY_BETWEEN)
    await s("addcleanrule",       "addcleanrule utm_source")
    await asyncio.sleep(DELAY_BETWEEN)
    await s("addcleanrules",      "addcleanrules utm_medium,fbclid")
    await asyncio.sleep(DELAY_BETWEEN)
    await s("cleanurl",           "cleanurl https://example.com?utm_source=test&utm_medium=email")
    await asyncio.sleep(DELAY_BETWEEN)
    await s("removecleanrule",    "removecleanrule utm_source")
    await asyncio.sleep(DELAY_BETWEEN)
    await s("clearcleanrules",    "clearcleanrules")
    await asyncio.sleep(DELAY_BETWEEN)

    # message
    await s("sendmessage",        "sendmessage Hello from test bot!")
    await asyncio.sleep(DELAY_BETWEEN)
    await s("addreply",           "addreply testping testpong")
    await asyncio.sleep(DELAY_BETWEEN)
    await s("listreplies",        "listreplies")
    await asyncio.sleep(DELAY_BETWEEN)
    await s("editreply",          "editreply testping testpong2")
    await asyncio.sleep(DELAY_BETWEEN)
    await s("addalias",           "addalias tp testping")
    await asyncio.sleep(DELAY_BETWEEN)
    await s("removealias",        "removealias tp")
    await asyncio.sleep(DELAY_BETWEEN)
    await s("removereply",        "removereply testping")
    await asyncio.sleep(DELAY_BETWEEN)

    # channels
    await s("channelconfig",      "channelconfig")
    await asyncio.sleep(DELAY_BETWEEN)

    # nickname
    await s("drynukerename",      "drynukerename")
    await asyncio.sleep(DELAY_BETWEEN)
    await s("managenicknames",    "managenicknames")
    await asyncio.sleep(DELAY_BETWEEN)

    # poll
    await s("createpoll",         f'createpoll "Test Poll?" 1m')
    await asyncio.sleep(DELAY_BETWEEN)
    await s("poll add :one:",     "poll add :one: Choice A")
    await asyncio.sleep(DELAY_BETWEEN)
    await s("poll add :two:",     "poll add :two: Choice B")
    await asyncio.sleep(DELAY_BETWEEN)
    await s("cancelpoll",         "cancelpoll")
    await asyncio.sleep(DELAY_BETWEEN)

    # modmail
    await s("newticket",          "newticket automated test ticket")
    await asyncio.sleep(DELAY_BETWEEN)
    await s("closeticket",        "closeticket test done")
    await asyncio.sleep(DELAY_BETWEEN)

    # ── Summary ───────────────────────────────────────────────────────────────
    passed = sum(1 for _, p, _ in results if p)
    failed = len(results) - passed

    print("\n" + "─" * 65)
    print(f"{'COMMAND':<40} {'RESULT':<8} RESPONSE")
    print("─" * 65)
    for name, p, resp in results:
        label   = "PASS" if p else "FAIL"
        snippet = (resp or "(no response)")[:40]
        print(f"{name:<40} {label:<8} {snippet}")
    print("─" * 65)
    print(f"Total: {passed} passed, {failed} failed / {len(results)}")

    await client.close()

@client.event
async def on_ready():
    print(f"Test bot logged in as {client.user}")
    guild   = client.get_guild(GUILD_ID)
    if not guild:
        print(f"[FATAL] Guild {GUILD_ID} not found")
        await client.close()
        return
    channel = guild.get_channel(CHANNEL_ID)
    if not channel:
        print(f"[FATAL] Channel {CHANNEL_ID} not found")
        await client.close()
        return

    print(f"Running tests in #{channel.name} ...\n")
    await asyncio.sleep(2)
    await run_tests(channel)

client.run(TOKEN)
