# Not a Bot

Source code of the bot of the french programming discord server NaN (Not a Name).  https://discord.gg/zcWp9sC

## Requirements

- [Luvit](https://luvit.io/) runtime

## Configuration

The bot reads its config from `config.lua`, which is git-ignored (don't commit your token).

1. Copy the default config:

   ```bash
   cp config.lua.default config.lua
   ```

2. Edit `config.lua` and set at minimum:
   - `Token` — your Discord bot token, from the [Discord Developer Portal](https://discord.com/developers/applications) (Bot tab > Reset/Copy Token).
   - `OwnerUserId` — your Discord user ID (enable Developer Mode in Discord, right-click your name, "Copy ID").

For development, create a separate test bot application on the Discord Developer Portal and invite it to a private test server. Use this bot's token in your local `config.lua` file to ensure that no code runs on the production bot or server.

### Gateway intents

The bot requires all gateway intents except for `guildIntegrations` (see `bot.lua`). Two of these are privileged and must be enabled manually on the Developer Portal (under the "Bot" tab) for your application, or the bot won't work:

- **Server Members Intent** (`guildMembers`)
- **Presence Intent** (`guildPresences`)

`AutoloadModules` lists which `module_*.lua` files load at startup — trim it while developing to only the module(s) you're working on, to reduce noise and side effects.

## Running the bot

```bash
luvit bot.lua
```
