-- Copyright (C) 2022 Mjöllnir#3515
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

Module.Name = "userinfo"

function Module:OnLoaded()
    self:RegisterCommand({
        Name = "userinfo",
        Args = {
            {Name = "target", Type = Bot.ConfigType.Member}
        },
        Help = "Prints member info",

        Func = function (commandMessage, targetMember)

-- TODO

        end
    })

    return true
end
