# Not a Bot

A modular Discord bot written in Lua using [Discordia](https://github.com/SinisterRectus/Discordia).  
Originally made for the french programming Discord server NaN (Not a Name): https://discord.gg/zcWp9sC

---

## Table of Contents

- [Installation](#installation)
- [Configuration](#configuration)
- [How Commands Work](#how-commands-work)
- [Modules](#modules)
  - [serverconfig](#serverconfig)
  - [ban](#ban)
  - [kick](#kick)
  - [mute](#mute)
  - [warn](#warn)
  - [raid](#raid)
  - [modmail](#modmail)
  - [poll](#poll)
  - [prune](#prune)
  - [purge](#purge)
  - [pin](#pin)
  - [quote](#quote)
  - [clean_urls](#clean_urls)
  - [message](#message)
  - [channels](#channels)
  - [userinfo](#userinfo)
  - [roleinfo](#roleinfo)
  - [nickname](#nickname)
  - [voice](#voice)
  - [welcome](#welcome)
  - [logs](#logs)
  - [sentry](#sentry)
  - [stats](#stats)
  - [twitch](#twitch)
  - [pm](#pm)
  - [mention](#mention)
  - [game](#game)

---

## Installation

1. Install [Luvit](https://luvit.io/) and the required dependencies (see the `deps/` folder).
2. Copy `config.lua.default` to `config.lua` and fill in:
   - `Token` — your bot token
   - `OwnerUserId` — your Discord user ID
   - `Prefix` — command prefix (default: `!`)
   - `AutoloadModules` — list of modules to load on startup
3. Run the bot with:
   ```
   luvit bot.lua
   ```

---

## Configuration

Each module has its own configuration, managed per-guild via the `serverconfig` module. The bot stores all configuration and persistent data automatically.

The global `config.lua` sets:
- `Token` — bot token
- `OwnerUserId` — owner user ID
- `Prefix` — default command prefix
- `AutoloadModules` — modules to load at startup

---

## How Commands Work

Commands are triggered by:
- A prefix (configurable per server, default `!`), e.g. `!ban @user`
- Or a direct mention of the bot, e.g. `@NotaBot ban @user`

**Built-in command:**
- `help` — lists all commands you have access to. Use `help <command>` for details on a specific command. Results are paginated with Previous/Next buttons.

**Argument syntax:**
- Required arguments: `<arg>`
- Optional arguments: `[arg]`

Most moderation commands are **silent** — they delete your invoking message after running.

**Permission checks** are per-command. Users without the required role or Discord permission may be rejected.

---

## Modules

### serverconfig

Configures per-server settings.

| Setting | Description | Default |
|---|---|---|
| `Language` | Bot language (`en` or `fr`) | `fr` |
| `Prefix` | Command prefix | `!` |

---

### ban

Bans, unbans, and manages ban durations. Requires the **Ban Members** Discord permission.

| Command | Usage | Description |
|---|---|---|
| `ban` | `ban <user> [duration] [reason]` | Bans a user. Optionally sends them a DM with the reason. |
| `unban` | `unban <user> [reason]` | Unbans a user. |
| `updatebanduration` | `updatebanduration <user> <duration>` | Updates how long a ban lasts. |

**Configuration:**

| Setting | Description | Default |
|---|---|---|
| `DefaultBanDuration` | Default ban duration if none is given | 24 hours |
| `SendPrivateMessage` | DM the user before banning | `true` |

**Notes:**
- Bans are tracked with expiration times. The bot automatically unbans when the duration expires.
- You cannot ban someone with a higher or equal role than yours, nor an admin.
- Bans made manually (outside the bot) are picked up from the audit log.

---

### kick

Kicks members. Requires the **Kick Members** permission or a configured authorized role.

| Command | Usage | Description |
|---|---|---|
| `kick` | `kick <member> [reason]` | Kicks a member. Optionally sends them a DM. |

**Configuration:**

| Setting | Description | Default |
|---|---|---|
| `PrivateMessage` | DM template before kick. Variables: `{guild}`, `{user}`, `{reason}` | `"You have been kicked from {guild} by {user}: {reason}"` |
| `AuthorizedRoles` | Roles allowed to kick | `[]` |

---

### mute

Mutes and unmutes members via a mute role. Requires admin or a configured authorized role.

| Command | Usage | Description |
|---|---|---|
| `mute` | `mute <member> [duration] [reason]` | Applies the mute role to a member. |
| `unmute` | `unmute <user> [reason]` | Removes the mute role. |

**Configuration:**

| Setting | Description | Default |
|---|---|---|
| `AuthorizedRoles` | Roles allowed to mute | `[]` |
| `DefaultMuteDuration` | Default mute duration | 10 minutes |
| `SendPrivateMessage` | DM the user when muted | `true` |
| `MuteRole` | The role to apply for mutes | *(required)* |

**Notes:**
- The bot automatically sets the mute role permissions on all text and voice channels (denies send messages, add reactions, speak).
- If a muted user leaves and rejoins the guild, the mute role is reapplied.
- Mutes persist across restarts.

---

### warn

Issues, lists, and clears warnings for users. Requires the **Ban Members** Discord permission.

| Command | Usage | Description |
|---|---|---|
| `warn` | `warn <user> [reason]` | Issues a warning. Optionally DMs the user. |
| `warnlist` | `warnlist <user>` | Lists all warnings for a user. |
| `clearwarns` | `clearwarns <user>` | Clears all warnings for a user. |

**Configuration:**

| Setting | Description | Default |
|---|---|---|
| `Sanctions` | Enable automatic sanctions | `true` |
| `WarnAmountToMute` | Warns needed to trigger a mute | 3 |
| `WarnAmountToBan` | Warns needed to post a ban notice | 9 |
| `DefaultMuteDuration` | Duration of auto-mute (multiplied per mute threshold reached) | 1 hour |
| `BanInformationChannel` | Channel to post ban notices in | *(required)* |
| `SendPrivateMessage` | DM the user when warned | `true` |

**Notes:**
- When a user hits a mute threshold (`WarnAmountToMute`, `2×`, `3×`, etc.), they are automatically muted and the duration scales up.
- When a user hits a ban threshold (`WarnAmountToBan`, `2×`, etc.), a message is posted in `BanInformationChannel` for moderators to act.
- Requires the `mute` module to apply auto-mutes.

---

### raid

Anti-raid protection with automatic detection, server lockdown, and join/spam rules. Requires admin or a configured authorized role for lock commands; admin only for rule management.

#### Automatic Protections

**Join spam detection:**
- Tracks a rolling window of recent joins.
- If more than `JoinCountThreshold` members join within `JoinTimeThreshold` seconds, the server is auto-locked and all members in the join chain are kicked.
- Default: 10 joins in 5 seconds triggers a 10-minute lock.

**Spam score detection:**
- Messages are scored based on content. If the score exceeds `SpamCountThreshold` within `SpamTimeThreshold` seconds, the member is auto-muted (or banned if mute is unavailable).

**New member message auto-ban:**
- If a member sends any message within `SendMessageThreshold` seconds of joining, they are auto-banned (bot detection).
- Default: 3 seconds.

#### Server Lock Behavior

When locked:
- New joins are auto-kicked unless they match an `authorize` rule.
- Server verification level is raised to `LockServerVerificationLevel` (default: `high`).
- An alert is posted to `LockAlertChannel`.
- On unlock: verification level is restored.
- Lock expires automatically after `DefaultLockDuration`.

#### Commands

| Command | Usage | Description |
|---|---|---|
| `lockserver` | `lockserver [duration] [reason]` | Manually locks the server. |
| `unlockserver` | `unlockserver [reason]` | Manually unlocks the server. |
| `rulehelp` | `rulehelp` | Lists all available rules and effects. |
| `addrule` | `addrule <effect> <rule> <param>` | Adds a join rule. |
| `delrule` | `delrule <index>` | Removes a rule by index. |
| `listrules` | `listrules` | Lists all active rules. |
| `clearrules` | `clearrules` | Removes all rules. |

#### Join Rules

Rules evaluate each joining member and apply an effect.

**Effects:**
- `authorize` — allows the user to join even during a lockdown
- `ban` — bans the user on join
- `kick` — kicks the user on join (even without a lock)

**Rule conditions:**

| Rule | Parameter | Description |
|---|---|---|
| `nitro` | `true`/`false` | Has Nitro subscription |
| `hypesquad` | `true`/`false` | Registered for HypeSquad |
| `discordEmployee` | `true`/`false` | Discord employee badge |
| `discordPartner` | `true`/`false` | Discord partner badge |
| `earlySupporter` | `true`/`false` | Early supporter badge |
| `verifiedBotDeveloper` | `true`/`false` | Verified bot developer badge |
| `newerThan` | ISO 8601 date | Account created after this date |
| `olderThan` | ISO 8601 date | Account created before this date |
| `createdBetween` | `<date> => <date>` | Account created in this range |
| `nicknameContains` | string (prefix with `p:` for pattern) | Username contains this text |

**Configuration:**

| Setting | Description | Default |
|---|---|---|
| `LockAuthorizedRoles` | Roles allowed to lock/unlock | `[]` |
| `AlertChannel` | Channel for spam mute alerts | *(optional)* |
| `LockAlertChannel` | Channel for lock/unlock alerts | *(optional)* |
| `RuleAlertChannel` | Channel for rule match alerts | *(optional)* |
| `LockServerVerificationLevel` | Verification level during lock | `high` |
| `SendMessageThreshold` | Seconds after join before messaging is allowed | 3 |
| `DefaultLockDuration` | Auto-lock duration | 10 minutes |
| `JoinCountThreshold` | Joins before auto-lock triggers | 10 |
| `JoinTimeThreshold` | Window for join counting (seconds) | 5 |
| `SpamCountThreshold` | Spam score before action | 7 |
| `SpamTimeThreshold` | Spam scoring window (seconds) | 10 |
| `SpamMute` | Mute instead of ban on spam | `true` |
| `SpamImmunity` | Roles immune to spam detection | `[]` |
| `JoinWhitelist` | Users always allowed to join during lock | `[]` |

---

### modmail

Ticket-based modmail system. Members can open tickets that create private channels.

| Command | Usage | Description |
|---|---|---|
| `newticket` | `newticket [message]` | Opens a modmail ticket. |
| `modticket` | `modticket <member> [message]` | Opens a moderation ticket for a member where they cannot respond (staff only). |
| `closeticket` | `closeticket [reason]` | Closes the current ticket. |
| `createticketform` | `createticketform <channel>` | Posts a button in a channel that members can click to open a ticket. |

**Configuration:**

| Setting | Description | Default |
|---|---|---|
| `Category` | Category where ticket channels are created | *(required)* |
| `ArchiveCategory` | Category where closed tickets are moved | *(optional)* |
| `LogChannel` | Channel where ticket logs are stored | *(optional)* |
| `TicketHandlingRoles` | Roles allowed to close tickets and open them for others | `[]` |
| `ForbiddenRoles` | Roles not allowed to open tickets | `[]` |
| `AllowedRoles` | Roles allowed to open tickets (empty = everyone) | `[]` |
| `MaxConcurrentChannels` | Maximum open tickets at once | 10 |
| `DeleteDuration` | Time before a closed ticket channel is deleted | 24 hours |
| `SaveTicketContent` | Save ticket messages to a log on close | `true` |
| `MemberCloseOwnTickets` | Allow members to close their own tickets | `true` |

---

### poll

Creates and manages polls with emoji reactions.

**Workflow:**
1. `createpoll "My question"` — starts poll setup
2. `poll add :emoji: Choice text` — adds a choice (up to 20)
3. `poll send` — posts the poll to the configured channel
4. When the duration expires, results are automatically posted with vote counts or progress bars.

| Command | Usage | Description |
|---|---|---|
| `createpoll` | `createpoll <title> [channel] [duration]` | Starts a new poll. |
| `poll` | `poll <action> [emoji] [text]` | Manages the pending poll. Actions: `add`, `remove`, `update`, `title`, `send`. |
| `cancelpoll` | `cancelpoll` | Cancels the pending poll. |

**Configuration:**

| Setting | Description | Default |
|---|---|---|
| `AllowedRoles` | Roles allowed to create polls | `[]` |
| `SpecifyChannelAllowedRoles` | Roles allowed to specify a channel for a poll | `[]` |
| `DefaultPollChannel` | Default poll destination channel | *(optional)* |
| `DefaultPollDuration` | Default poll duration | 24 hours |
| `DeletePollOnExpiration` | Delete the original poll message when it ends | `true` |
| `UseProgressBars` | Show results as progress bars | `true` |
| `MostVotedRelative` | Scale progress bars to the most voted choice | `false` |

---

### prune

Bulk deletes messages in a channel. Requires **Manage Messages**.

| Command | Usage | Description |
|---|---|---|
| `prune` | `prune <count>` | Deletes the last N messages (no older than 14 days). |
| `prunefrom` | `prunefrom <messageId>` | Deletes all messages from a given message ID up to the current message. |

---

### purge

Kicks or strips roles from members who have been inactive for a given duration. Requires **Administrator**.

| Command | Usage | Description |
|---|---|---|
| `drypurge` | `drypurge <duration>` | Shows how many inactive members would be affected. |
| `purgeroles` | `purgeroles <duration>` | Removes all roles from members inactive for the given duration. |
| `purgekick` | `purgekick <duration>` | Kicks members inactive for the given duration. |

**Notes:**
- Activity is tracked via messages sent, reactions added, and joins.
- Members are DMed before being kicked.
- Duration format examples: `30d`, `7d`, `1h`.

---

### pin

Pins messages via command or by emoji vote.

| Command | Usage | Description |
|---|---|---|
| `pin` | `pin <messageId>` | Pins a message. Requires Manage Messages or channel ownership. |
| `unpin` | `unpin <messageId>` | Unpins a message. Requires the same permission as `pin`. |

**Auto-pin:** When a message receives enough pin emoji reactions (default: 📌 × 10), it is automatically pinned and optionally posted to an alert channel.

**Configuration:**

| Setting | Description | Default |
|---|---|---|
| `Trigger` | Emoji that triggers auto-pin | `pushpin` (📌) |
| `DisabledChannels` | Channels where auto-pin is disabled | `[]` |
| `PinThreshold` | Reactions needed to auto-pin | 10 |
| `AlertChannel` | Channel to notify when a message is auto-pinned | *(optional)* |

---

### quote

Quotes messages as rich embeds.

| Command | Usage | Description |
|---|---|---|
| `quote` | `quote <messageId or link> [deleteInvokation]` | Quotes a message as an embed. |

**Auto-quote:** When a user posts a Discord message link, the bot automatically embeds the quoted message.

**Configuration:**

| Setting | Description | Default |
|---|---|---|
| `AutoQuote` | Auto-embed message links | `true` |
| `BigAvatar` | Use large author avatar in quote | `false` |
| `DeleteInvokationOnAutoQuote` | Delete the original message on auto-quote | `false` |
| `DeleteInvokationOnManualQuote` | Delete the invoking message on manual quote | `false` |

**Notes:**
- Users can only quote messages they have permission to read.

---

### clean_urls

Strips tracking parameters from URLs. Can work automatically or via command.

| Command | Usage | Description |
|---|---|---|
| `cleanurl` | `cleanurl <url> [deleteInvokation]` | Cleans a URL and posts the result. |
| `addcleanrule` | `addcleanrule <rule>` | Adds a cleaning rule. |
| `addcleanrules` | `addcleanrules <rule1,rule2,...>` | Adds multiple rules at once. |
| `removecleanrule` | `removecleanrule <rule>` | Removes a cleaning rule. |
| `listcleanrules` | `listcleanrules` | Lists all active rules. |
| `clearcleanrules` | `clearcleanrules` | Removes all rules. |

**Configuration:**

| Setting | Description | Default |
|---|---|---|
| `AutoCleanUrls` | Automatically clean URLs in messages | `true` |
| `DeleteInvokationOnAutoCleanUrls` | Delete original message on auto-clean | `true` |
| `DeleteInvokationOnManualCleanUrls` | Delete invoking message on manual clean | `true` |
| `WebhooksMappings` | Channel → webhook ID mapping for impersonation | `{}` |
| `Rules` | List of cleaning rules | `[]` |
| `Whitelist` | URL hosts to never clean | `[]` |
| `ButtonTimeout` | Milliseconds before the delete button disappears | — |

**Notes:**
- Uses webhooks to re-post messages as the original user with the cleaned URL.
- The module detects and handles link shorteners automatically.

---

### message

Manages bot-sent messages, auto-replies, and aliases.

| Command | Usage | Description |
|---|---|---|
| `sendmessage` | `sendmessage [channel] [content]` | Sends a message as the bot. |
| `editmessage` | `editmessage <message> [content]` | Edits a bot message. |
| `rawmessage` | `rawmessage <message>` | Shows the raw JSON of a bot message. |
| `addreply` | `addreply <trigger> [content]` | Adds an auto-reply triggered by a keyword. |
| `removereply` | `removereply <trigger>` | Removes an auto-reply. |
| `editreply` | `editreply <trigger> [content]` | Edits an existing auto-reply. |
| `listreplies` | `listreplies` | Lists all auto-replies. |
| `addalias` | `addalias <alias> <trigger>` | Adds an alias for a trigger. |
| `removealias` | `removealias <alias>` | Removes an alias. |
| `savechannelmessages` | `savechannelmessages [channel] [afterMessage] [limit] [fromFirstMessage]` | Exports channel messages to a file. |

**Configuration:**

| Setting | Description |
|---|---|
| `AuthorizedRoles` | Roles allowed to use message commands |
| `Replies` | Map of triggers to reply content (supports embeds) |
| `Aliases` | Map of aliases to trigger names |
| `DeleteInvokation` | Whether invoking messages are deleted |
| `MaxActionMessage` | Maximum number of action messages |

---

### channels

Reaction role system — assign or remove roles when members react to messages.

| Command | Usage | Description |
|---|---|---|
| `channelconfig` | `channelconfig [configMessage]` | Shows or posts the reaction-role configuration. |
| `updatechannelconfig` | `updatechannelconfig <message> <emoji> <action> [value]` | Updates a reaction-role mapping. |

**Configuration:**

| Setting | Description |
|---|---|
| `ReactionActions` | Map of channel → message → emoji → role actions. Configured via `channelconfig`. |

---

### userinfo

Displays information about a member or user.

| Command | Usage | Description |
|---|---|---|
| `userinfo` | `userinfo [user]` | Shows account creation date, join date, roles, join order, and presence status (if `guildPresences` intent is enabled). Defaults to yourself if no target is given. |

---

### roleinfo

Displays information about a role.

| Command | Usage | Description |
|---|---|---|
| `roleinfo` | `roleinfo <rolename>` | Shows details about a role. |

---

### nickname

Manages custom nicknames server-wide.

| Command | Usage | Description |
|---|---|---|
| `managenicknames` | `managenicknames` | Shows a paginated interactive list of all members with custom nicknames, with buttons to reset them. |
| `drynukerename` | `drynukerename` | Shows how many members have custom nicknames. |
| `nukerename` | `nukerename` | Resets all custom nicknames on the server. |

Requires the **Manage Nicknames** permission.

---

### voice

Private voice channel system. Members can create temporary private voice channels and invite others.

**How it works:**
1. Configure a `TriggerChannel` — a voice channel members join to create a private channel.
2. When a member joins the trigger channel, a new private voice channel is created in the same category, named after the member.
3. Only the owner (and `AuthorizedRoles`) can connect by default.
4. The owner can invite others via a user-select dropdown posted in the private channel.
5. When the owner disconnects, the channel is automatically deleted.

**Configuration:**

| Setting | Description |
|---|---|
| `TriggerChannel` | Voice channel members join to create a private channel *(required)* |
| `AuthorizedRoles` | Roles always allowed to join private channels |

---

### welcome

Posts messages when members join, leave, or are banned/unbanned. Can also assign roles on join.

**Configuration:**

| Setting | Description | Default |
|---|---|---|
| `WelcomeChannel` | Channel for join/leave messages | *(optional)* |
| `BanChannel` | Channel for ban/unban messages | *(optional)* |
| `JoinMessage` | Message on join. Variables: `{userMention}`, `{userTag}` | `"Welcome to {userMention}!"` |
| `JoinRoles` | Roles to assign to new members (up to 10) | `[]` |
| `LeaveMessage` | Message on leave. Variables: `{userTag}`, `{duration}` | `"Farewell {userTag}. :wave:"` |
| `BanMessage` | Message on ban. Variables: `{userTag}` | `"{userTag} has been banned. :hammer:"` |
| `UnbanMessage` | Message on unban. Variables: `{userTag}` | `"{userTag} has been unbanned."` |

---

### logs

Logs server events to designated channels.

**Configuration:**

| Setting | Description |
|---|---|
| `ChannelManagementLogChannel` | Channel for channel create/update/delete events |
| `DeletedMessageChannel` | Channel for deleted message logs |
| `NicknameChangedLogChannel` | Channel for nickname change logs |
| `IgnoredDeletedMessageChannels` | Channels excluded from deleted message logging |
| `PersistentMessageCacheSize` | How many recent messages per channel to cache in memory (global setting, default: 50) |

---

### sentry

Monitors specific users for joins or messages and sends alerts.

**Configuration:**

| Setting | Description | Default |
|---|---|---|
| `SentryChannel` | Channel where sentry alerts are posted | *(optional)* |
| `JoinAlert` | Alert message on monitored user join. Variables: `{userMention}`, `{userTag}`, `{userId}` | *(built-in default)* |
| `MessageAlert` | Alert message on monitored user message. Variables: `{userMention}`, `{userTag}`, `{userId}`, `{message}` | *(built-in default)* |
| `MonitoredJoins` | Users to watch for joins | `[]` |
| `MonitoredMessages` | Map of user ID → keyword list to watch for in messages (empty list = alert on any message) | `{}` |

---

### stats

Tracks message and activity statistics per server. Exposes stats data for optional external graphing.

**Configuration:**

| Setting | Description |
|---|---|
| `LogChannel` | Channel where stats logs are posted |
| `ShowActiveUsers` | Whether to include active user counts in stats |

---

### twitch

Sends notifications when Twitch channels go live. Watches configured channels and posts to specified Discord channels based on title patterns.

**Configuration:**

| Setting | Description |
|---|---|
| `TwitchConfig` | Object mapping Discord channel IDs to arrays of `{ channel, message, [titlePattern] }` entries |

---

### pm

Logs private messages sent to the bot to a channel, and allows staff to reply from that channel.

**How it works:**
- When a user DMs the bot, the message is forwarded as an embed to `TargetChannel`.
- Staff can reply to that embed (using Discord's reply feature) to send a message back to the original user.

**Configuration (global):**

| Setting | Description |
|---|---|
| `TargetChannel` | Channel where DMs are logged |
| `BlockedUsers` | Users not allowed to contact the bot |

---

### mention

Reacts with an emoji when the bot is mentioned (or `@everyone`/`@here` is used).

**Configuration:**

| Setting | Description | Default |
|---|---|---|
| `Emoji` | Reaction emoji | `mention` |
| `ReactOnEveryoneOrHere` | Also react to `@everyone` and `@here` | `true` |

---

### game

Rotates the bot's Discord activity status from a configured list, changing every 3 minutes.

**Configuration (global):**

| Setting | Description |
|---|---|
| `GameList` | List of activity strings to rotate through |

---

## License

Copyright (C) 2018 Jérôme Leclercq. See [LICENSE](LICENSE) for details.
