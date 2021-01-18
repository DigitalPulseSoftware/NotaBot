# Warn Module

Back to the *[Summary](../index.md)*.

*[Sources of the module](../../module_warn.lua)*

The warn module is used to give members warnings about their behaviour in the guild.

After a given amount of warns, the member gets muted __if the mute module is enabled__

## Config


- Sanctions (Boolean) (default = true)
  - Enables sanctions (mute and ban alert) when a member receives a warning.

- WarnAmountToMute (Integer) (default = 3)
  - Number of warns needed to mute a member.

- WarnAmountToBan (Integer) (default = 9)
  - Numbed of warns needed to send the ban alert to the moderators.

- DefaultMuteDuration (Duration) (default = 1 hour)
  - Default mute duration when a member gets enough warnings.
  - The duration increases as the warning amount increases: `duration = default_duration * (warnings / WarnAmountToMute)`

- BanInformationChannel (Channel) (default = nothing)
  - Channel where all the ban notifications are sent when a player has enough warnings
  - This setting is required to enable the module
  - You still have to manually ban the member, the last choice remains to the moderation team.

- SendPrivateMessage (Boolean) (default = true)
  - Enable private messages to inform the member of his warning.

## Commands

Assuming the bot prefix is `!`

- `!warn <target> [reason]`
  - This command gives a warning to the target with the given reason. It also checks if the member should receive a mute or more (only if the option is enabled).
  - If enabled, the member will receive a private message resuming the warning and where it comes from.
  - Example : `!warn @SomePlayer You are a terrible liar`

- `!warnlist <target>`
  - Shows all the warnings that the given user received.
  - Example : `!warnlist @SomePlayer`

- `!clearwarns <target>`
  - Clears all the history of the given member.
  - Example : `!clearwarns @SomePlayer`