local addonName, addon = ...
local L = addon.L
local mod = addon.ChatFilter
if not mod then
    mod = CreateFrame("Frame")
    addon.ChatFilter = mod
end

mod:SetScript("OnEvent", function(self, event, ...) self[event](self, ...) end)
mod:RegisterEvent("ADDON_LOADED")

-- saved variables
ChatFilterDB = {}

-- defaults
local defaults = {
    enabled = true,
    verbose = false,
    words = {"wts", "wtb", "recruiting"}
}
local logs, last = {}, 0

-- cache frequently used globals
local find, lower, format = string.find, string.lower, string.format
local tinsert, tremove = table.insert, table.remove
local UnitIsInMyGuild, UnitInRaid, UnitInParty = UnitIsInMyGuild, UnitInRaid, UnitInParty

-- replace default UnitIsFriend
local GetNumFriends = GetNumFriends
local function UnitIsFriend(name)
    for i = 1, GetNumFriends() do
        if name == GetFriendInfo(i) then
            return true
        end
    end
    return false
end

-- print function
local function Print(msg)
    if msg then
        addon:Print(msg, L["Chat Filter"])
    end
end

-- dumb function to return ON or OFF
local function ChatFilter_StatusMessage(on)
    return on and "|cff00ff00ON|r" or "|cffff0000OFF|r"
end

-- builds the final logs then prints it
local function ChatFilter_PrintLog(num)
    if #logs == 0 then
        Print(L["The message log is empty."])
    else
        local count = (num > #logs) and #logs or num
        Print(L:F("Displaying the last %d messages:", count))
        for i = 1, count do
            print("|cffd3d3d3" .. i .. "|r." .. logs[i])
        end
    end
end

-- slash command handler
local function SlashCommandHandler(msg)
    local cmd, rest = strsplit(" ", msg, 2)

    -- toggle the chat filter.
    if cmd == "toggle" then
        -- toggle verbose mode
        ChatFilterDB.enabled = not ChatFilterDB.enabled
        Print(L:F("filter is now %s", ChatFilter_StatusMessage(ChatFilterDB.enabled)))
    elseif cmd == "verbose" then
        -- list words
        ChatFilterDB.verbose = not ChatFilterDB.verbose
        Print(L:F("notifications are now %s", ChatFilter_StatusMessage(ChatFilterDB.verbose)))
    elseif cmd == "words" or cmd == "list" then
        -- logs of messages that were hidden
        Print(L["filter keywords are:"])
        local words = {}
        for i, word in ipairs(ChatFilterDB.words) do
            words[i] = i .. ".|cff00ffff" .. word .. "|r"
        end
        print(table.concat(words, ", "))
    elseif cmd == "log" or cmd == "logs" then
        -- add a new word to the list
        if rest then
            if not strmatch(rest, "%d") then
                Print(L["Input is not a number"])
            end
            ChatFilter_PrintLog(tonumber(rest))
        else
            ChatFilter_PrintLog(10)
        end
    elseif cmd == "add" and rest then
        -- remove a word from the list
        tinsert(ChatFilterDB.words, rest:trim())
        Print(L:F("the word |cff00ffff%s|r was added successfully.", rest:trim()))
    elseif (cmd == "remove" or cmd == "delete") and rest then
        -- reset or default values
        if not strmatch(rest, "%d") then
            Print(L["Input is not a number"])
            return
        end

        local count = #ChatFilterDB.words
        local index = tonumber(rest)
        if index > count then
            Print(L:F("Index is out of range. Max value is |cff00ffff%d|r.", count))
            return
        end

        local word = ChatFilterDB.words[index]
        tremove(ChatFilterDB.words, index)
        Print(L:F("the word |cff00ffff%s|r was removed successfully.", word))
    elseif cmd == "default" or cmd == "reset" then
        -- anything else will display the help menu
        ChatFilterDB = CopyTable(defaults)
        Print(L["settings were set to default."])

        -- clear logs
        wipe(logs)
        last = 0
    else
        Print(L:F("Acceptable commands for: |caaf49141%s|r", "/cf"))
        print("|cffffd700toggle|r : ", L["Turn filter |cff00ff00ON|r / |cffff0000OFF|r"])
        print("|cffffd700words|r : ", L["View filter keywords (case-insensitive)"])
        print("|cffffd700add|r |cff00ffffword|r : ", L["Adds a |cff00ffffkeyword|r"])
        print("|cffffd700remove|r |cff00ffffpos|r : ", L["Remove keyword by |cff00ffffposition|r"])
        print("|cffffd700verbose|r : ", L["Show or hide filter notifications"])
        print("|cffffd700log|r |cff00ffffn|r : ", L["View the last |cff00ffffn|r filtered messages (up to 20)"])
        print("|cffffd700reset|r : ", L["Resets settings to default"])
    end
end

-- the main filter function
local ChatFilter_Filter
do
    -- adds a filtered message to the logs table.
    local function ChatFilter_AddLog(name, msg)
        if ChatFilterDB.verbose and last + 2 <= GetTime() then
            Print(L:F("filtered a message from |cff00ffff%s|r", name))
            last = GetTime()
        end

        local message = format("|cffd3d3d3[%s]|r: %s", name, msg)
        if not tContains(logs, message) then
            tinsert(logs, 0, message)
        end

        -- remove the last element if we exceed 20
        local i = #logs
        if i > 20 then
            tremove(logs, i)
        end
    end

    function ChatFilter_Filter(self, event, msg, player, ...)
        -- we don't filter messages if the filter is disabled
        -- or the player is from the guild
        -- or the player is a friend
        -- or the player is in a raid or party group
        if
            not ChatFilterDB.enabled or UnitIsInMyGuild(player) or UnitIsFriend(player) or UnitInRaid(player) or
                UnitInParty(player)
         then
            return false
        end

        local temp, count = lower(msg), #ChatFilterDB.words
        for i = 1, count do
            if find(temp, lower(ChatFilterDB.words[i])) then
                ChatFilter_AddLog(player, msg)
                return true
            end
        end
    end
end

function mod:ADDON_LOADED(name)
    if name ~= addonName then
        return
    end
    self:UnregisterEvent("ADDON_LOADED")

    -- prepare our saved variables
    if next(ChatFilterDB) == nil then
        ChatFilterDB = defaults
    end

    -- register our slash commands handler
    SlashCmdList["KPACKCHATFILTER"] = SlashCommandHandler
    _G.SLASH_KPACKCHATFILTER1, _G.SLASH_KPACKCHATFILTER2 = "/chatfilter", "/cf"

    self:RegisterEvent("PLAYER_ENTERING_WORLD")
end

function mod:PLAYER_ENTERING_WORLD()
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", ChatFilter_Filter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SAY", ChatFilter_Filter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_YELL", ChatFilter_Filter)
end