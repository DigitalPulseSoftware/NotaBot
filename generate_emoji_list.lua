local http = require("coro-http")
local json = require("json")

local function InsertIfNotPresent(t, value, p)
    for k, v in pairs(t) do
        if (v == value) then
            return false
        end
    end

    if (p) then
        table.insert(t, p, value)
    else
        table.insert(t, value)
    end
    return true
end

local function SetToTable(s)
    local t = {}
    for v, _ in pairs(s) do
        table.insert(t, v)
    end

    table.sort(t)

    return t
end

coroutine.wrap(function ()
    local res, body = http.request("GET", "https://static.emzi0767.com/misc/discordEmojiMap.json")
    if (res.code ~= 200) then
        error("failed to download discord emoji map")
    end

    local emojiMap, err = json.decode(body)
    if (not emojiMap) then
        error("failed to decode discord json: " .. err)
    end

    local emojis = {}
    local emojiByName = {}

    local function RegisterEmoji(primaryName, name, code)
        local emojiData = emojiByName[primaryName]
        if (not emojiData) then
            emojiData = {
                primaryName = primaryName,
                names = {},
                codes = {}
            }
            emojiByName[primaryName] = emojiData
            table.insert(emojis, emojiData)
        end

        if (type(name) == "table") then
            for _, n in pairs(name) do
                emojiData.names[n] = true
            end
        else
            emojiData.names[name] = true
        end

        -- Preserve code order (new code comes first)
        if (type(code) == "table") then
            for i, c in pairs(code) do
                InsertIfNotPresent(emojiData.codes, c, i)
            end
        else
            InsertIfNotPresent(emojiData.codes, code, 1)
        end
    end

    -- Fill with previous data
    local currentEmojiData = require("./data_emoji.lua")
    for name, emojiData in pairs(currentEmojiData) do
        RegisterEmoji(name, emojiData.names, emojiData.codes)
    end

    for _, emojiData in pairs(emojiMap.emojiDefinitions) do
        local names = {}

        for _, emojiName in pairs(emojiData.namesWithColons) do
            local name = emojiName:match("^:([%w_]+):$")
            if (name) then
                table.insert(names, name)
            end
        end

        RegisterEmoji(emojiData.primaryName, names, emojiData.surrogates)
    end

    table.sort(emojis, function (a, b) return a.primaryName < b.primaryName end)

    local file = io.open("data_emoji.lua", "w+")
    assert(file, "failed to open file")

    file:write("return {\n")

    for _, emojiData in ipairs(emojis) do
        local lines = {}

        table.insert(lines, string.format("\t[\"%s\"] = {", emojiData.primaryName))

        table.insert(lines, "\t\tnames = {")
        for _, name in pairs(SetToTable(emojiData.names)) do
            table.insert(lines, "\t\t\t\"" .. name .. "\",")
        end
        table.insert(lines, "\t\t},")

        table.insert(lines, "\t\tcodes = {")
        for _, code in pairs(emojiData.codes) do
            local u = {}
            for i = 1, #code do
                table.insert(u, string.format("\\x%02X", code:byte(i, i)))
            end

            table.insert(lines, "\t\t\t\"" .. table.concat(u) .. "\", -- " .. code)
        end
        table.insert(lines, "\t\t},")
        table.insert(lines, "\t},\n")

        file:write(table.concat(lines, "\n"))
    end

    file:write("\n}")
end)()

