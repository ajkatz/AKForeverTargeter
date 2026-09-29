-- Read model: which mobs does a tracked quest objective want?
--
-- Three sources, no ID tables:
--   * the objective's own text - a kill objective names its mob ("Kobold Vermin slain: 3/10", or in the
--     modern wording "3/10 Kobold Vermin slain"). The words around the name come from the client's own
--     format string, so this is not tied to English;
--   * what Learn.lua has seen: a mob whose tooltip carries one of our objectives ("Gold Dust: 2/10" on a
--     Kobold Miner) is remembered for that objective - the game never says who drops what, the tooltip does;
--   * the quest giver: remembered as the quest is accepted (the NPC in front of you), and - for a quest that
--     is ready to turn in - every name in its "Return to Chief Hawkwind in Camp Narache." line.
local _, ns = ...

local Quests = {}
ns.Quests = Quests

-- " slain" - whatever follows the name in the client's kill-objective format ("%s slain: %d/%d")
local function slainSuffix()
    local template = type(QUEST_MONSTERS_KILLED) == "string" and QUEST_MONSTERS_KILLED or "%s slain: %d/%d"
    local suffix = string.match(template, "%%s([^%%:]*)")
    suffix = suffix and string.gsub(suffix, "%s+$", "") or ""
    if suffix == "" then
        return " slain"
    end
    return suffix
end

-- An objective's text without its progress numbers and list dash: what a tooltip line and a tracker line
-- of the same objective have in common.
function Quests.CoreText(text)
    if type(text) ~= "string" or ns.IsSecret(text) then
        return nil
    end
    local core = string.gsub(text, "^[%s%-]+", "")
    core = string.match(core, "^%d+/%d+%s+(.+)$") or string.match(core, "^(.-)%s*:%s*%d+/%d+$") or core
    core = string.gsub(core, "%s+$", "")
    if core == "" then
        return nil
    end
    return core
end

-- The mob a kill objective names - nil when the text is not the stock "... slain" wording (a quest with
-- its own objective text, "Prisoners rescued: 0/5", names no mob we could target).
function Quests.MobFromText(text, objectiveType)
    if objectiveType ~= "monster" then
        return nil
    end
    local core = Quests.CoreText(text)
    if not core then
        return nil
    end
    local suffix = slainSuffix()
    if #core > #suffix and string.sub(core, -#suffix) == suffix then
        return string.sub(core, 1, #core - #suffix)
    end
    return nil
end

-- The objectives of one quest as plain data: { { index, text, type, finished, numFulfilled, numRequired } ... }
-- - or nil when the client would not say (secret, error, not in the log).
function Quests:Objectives(questID)
    if type(C_QuestLog) ~= "table" then
        return nil
    end
    local answer = ns.Readable(C_QuestLog.GetQuestObjectives, questID)
    local list = answer and answer[1]
    if type(list) ~= "table" then
        return nil
    end
    local objectives = {}
    for index, objective in ipairs(list) do
        if type(objective) == "table" and not ns.AnySecret(objective.text, objective.type, objective.finished) then
            local entry = {
                index = index,
                text = objective.text,
                type = objective.type,
                finished = objective.finished and true or false,
            }
            if not ns.AnySecret(objective.numFulfilled, objective.numRequired) then
                entry.numFulfilled, entry.numRequired = objective.numFulfilled, objective.numRequired
            end
            objectives[#objectives + 1] = entry
        end
    end
    return objectives
end

-- WHICH QUESTS ARE HERE. The first try was GetInfo().isOnMap, and in game it turned out to mean "on the
-- map the client is showing" - standing in Durotar with Kalimdor on screen, Barrens quests counted as
-- here. So the precise question is asked instead: the map the PLAYER is in, and the quests the client
-- places on it. The answer is a set, worked out once per pass rather than per quest.
-- nil: this client would not say, and then every quest keeps its row.
-- A CITY IS NOT A ZONE OF ITS OWN as far as quests go. Orgrimmar's map carries no quest POIs at all, so
-- asking what is "on" it gives an empty list - and reading that as "the client would not say" is how a
-- Southsea Brigand from the Barrens ended up on the panel in Orgrimmar. An empty list is an ANSWER.
-- Every map that is still a zone or finer also counts the map it sits inside, so standing in Orgrimmar
-- shows Durotar's business. The walk stops at the continent: Kalimdor would bring the Barrens back.
local CONTINENT = 2 -- C_Map mapType: 0 cosmic, 1 world, 2 continent, 3 zone, and finer above that
local DUNGEON = 4
local MAX_HOPS = 3

local function mapsAround(map)
    local maps, current = { map }, map
    for _ = 1, MAX_HOPS do
        local info = ns.Readable(C_Map.GetMapInfo, current)
        info = info and info[1]
        if type(info) ~= "table" then
            break
        end
        if info.mapType == DUNGEON then
            break -- a dungeon's map stands alone: the zone around its entrance is not where you are
        end
        local parent = info.parentMapID
        local parentInfo = type(parent) == "number" and parent > 0 and ns.Readable(C_Map.GetMapInfo, parent)
        parentInfo = parentInfo and parentInfo[1]
        -- only step up while the next one is still a zone: a continent holds every zone on it
        if type(parentInfo) ~= "table" or type(parentInfo.mapType) ~= "number" or parentInfo.mapType <= CONTINENT then
            break
        end
        maps[#maps + 1] = parent
        current = parent
    end
    return maps
end

function Quests:MapQuests()
    if type(C_Map) ~= "table" or type(C_QuestLog) ~= "table" or type(C_QuestLog.GetQuestsOnMap) ~= "function" then
        return nil, "this client has no C_Map / GetQuestsOnMap"
    end
    local map = ns.Readable(C_Map.GetBestMapForUnit, "player")
    map = map and map[1]
    if type(map) ~= "number" then
        return nil, "the client would not say which map you are in"
    end

    local set, count, asked, answered = {}, 0, {}, false
    for _, uiMapID in ipairs(mapsAround(map)) do
        local answer = ns.Readable(C_QuestLog.GetQuestsOnMap, uiMapID)
        local list = answer and answer[1]
        asked[#asked + 1] = tostring(uiMapID)
        if type(list) == "table" then
            answered = true -- it spoke, even if it had nothing to say
            for _, entry in ipairs(list) do
                local id = type(entry) == "table" and entry.questID or entry
                if type(id) == "number" and not ns.IsSecret(id) and not set[id] then
                    set[id], count = true, count + 1
                end
            end
        end
    end
    if not answered then
        return nil, "the client would not say what is on map " .. map
    end
    set.map, set.count = map, count
    return set, "map " .. table.concat(asked, "+") .. ", " .. count .. " quest(s)"
end

-- Is this quest's business where you are standing? `set` is what MapQuests gave; without one, yes -
-- a row too many is better than a row missing.
--
-- A quest READY TO TURN IN is always "here": the client does not reliably place a finished quest on the
-- map you are in (measured 2026-09-22 - a turn-in at Thrall was not on the Valley of Wisdom's map), and a
-- turn-in is the one row you most want the moment you walk in.
function Quests:IsHere(questID, set)
    if Quests:ReadyForTurnIn(questID) then
        return true, "ready to turn in"
    end
    if set == nil then
        set = (Quests:MapQuests())
    end
    if type(set) ~= "table" then
        return true, "the client would not say"
    end
    if set[questID] then
        return true, "on your map"
    end
    return false, "elsewhere"
end

-- Is this a dungeon or raid quest? The client's own tag says (Enum.QuestTag, read in this build's
-- QuestLogDocumentation: Raid 62, Dungeon 81, Heroic 85, Raid10 88, Raid25 89). It is what decides inside
-- an instance, where this client will not say which map you are on. No tag, no answer, a secret: no.
local DUNGEON_TAGS = { [62] = true, [81] = true, [85] = true, [88] = true, [89] = true }

function Quests:IsDungeonQuest(questID)
    if type(C_QuestLog) ~= "table" then
        return false, "this client has no quest tags"
    end
    local answer = ns.Readable(C_QuestLog.GetQuestTagInfo, questID)
    local info = answer and answer[1]
    if type(info) ~= "table" then
        return false, "no tag"
    end
    local id, name = info.tagID, info.tagName
    if ns.IsSecret(id) or ns.IsSecret(name) then
        return false, "the client would not say"
    end
    if DUNGEON_TAGS[id] then
        return true, tostring(name)
    end
    return false, tostring(name)
end

function Quests:Title(questID)
    if type(C_QuestLog) ~= "table" then
        return nil
    end
    local answer = ns.Readable(C_QuestLog.GetTitleForQuestID, questID)
    local title = answer and answer[1]
    return type(title) == "string" and title or nil
end

-- Ready to turn in? (C_QuestLog.ReadyForTurnIn on this client; IsComplete elsewhere.) Unreadable: no.
function Quests:ReadyForTurnIn(questID)
    if type(C_QuestLog) ~= "table" then
        return false
    end
    local fn = C_QuestLog.ReadyForTurnIn or C_QuestLog.IsComplete
    local answer = ns.Readable(fn, questID)
    return answer ~= nil and answer[1] == true
end

-- The quests in the objective tracker (the tracked, "watched" ones).
function Quests:Tracked()
    local tracked = {}
    if type(C_QuestLog) ~= "table" then
        return tracked
    end
    local count = ns.Readable(C_QuestLog.GetNumQuestWatches)
    for watchIndex = 1, (count and tonumber(count[1])) or 0 do
        local id = ns.Readable(C_QuestLog.GetQuestIDForQuestWatchIndex, watchIndex)
        if id and type(id[1]) == "number" then
            tracked[#tracked + 1] = id[1]
        end
    end
    return tracked
end

------------------------------------------------------------------------
-- Learned names: db.learned[questID][objectiveIndex] = { ["Kobold Miner"] = true }
------------------------------------------------------------------------
local function learnedFor(questID, objectiveIndex, create)
    local db = ns.db
    if not db then
        return nil
    end
    if create then
        db.learned = db.learned or {}
        db.learned[questID] = db.learned[questID] or {}
        db.learned[questID][objectiveIndex] = db.learned[questID][objectiveIndex] or {}
    end
    local byQuest = db.learned and db.learned[questID]
    return byQuest and byQuest[objectiveIndex]
end

-- true when this was news
function Quests:Learn(questID, objectiveIndex, mobName)
    if type(mobName) ~= "string" or mobName == "" then
        return false
    end
    local names = learnedFor(questID, objectiveIndex, true)
    if not names or names[mobName] then
        return false
    end
    names[mobName] = true
    ns:Log("learned", { quest = questID, objective = objectiveIndex, mob = mobName })
    ns:Fire("TARGETS_CHANGED")
    return true
end

function Quests:Forget(questID)
    local db = ns.db
    if not (db and db.learned) then
        return
    end
    if questID then
        db.learned[questID] = nil
    else
        db.learned = {}
    end
    ns:Fire("TARGETS_CHANGED")
end

------------------------------------------------------------------------
-- Hints: the mobs of quests whose tooltips never say. Mad Magglish holds the 99-Year-Old Port and stands
-- stealthed in the Wailing Caverns cave; no mouseover will ever show that objective on him. A small
-- built-in list by quest title, and '/akt hint add <quest title> = <mob>' for the ones you find yourself
-- (db.hints[title] = { names }).
------------------------------------------------------------------------
-- Keyed by the quest's TITLE or by an OBJECTIVE's own text (what the tracker shows: the item's name) -
-- people call a quest by either. The port quest is "Trouble at the Docks" (read from a saved report,
-- 2026-09-28); the bottle is its one objective.
local QUEST_HINTS = {
    ["Trouble at the Docks"] = { "Mad Magglish" },
    ["99-Year-Old Port"] = { "Mad Magglish" },
}
Quests.QUEST_HINTS = QUEST_HINTS

function Quests:Hints(title)
    if type(title) ~= "string" then
        return nil
    end
    local names = {}
    for _, name in ipairs(QUEST_HINTS[title] or {}) do
        names[#names + 1] = name
    end
    local taught = ns.db and ns.db.hints and ns.db.hints[title]
    for _, name in ipairs(type(taught) == "table" and taught or {}) do
        names[#names + 1] = name
    end
    return #names > 0 and names or nil
end

function Quests:Teach(title, mobName)
    if type(title) ~= "string" or title == "" or type(mobName) ~= "string" or mobName == "" or not ns.db then
        return false
    end
    ns.db.hints = ns.db.hints or {}
    ns.db.hints[title] = ns.db.hints[title] or {}
    for _, name in ipairs(ns.db.hints[title]) do
        if name == mobName then
            return true
        end
    end
    table.insert(ns.db.hints[title], mobName)
    ns:Log("hint", { title = title, name = mobName })
    return true
end

function Quests:Unteach(title)
    if ns.db and ns.db.hints and title then
        ns.db.hints[title] = nil
    end
end

-- The mob names to try for one objective, the text's own name first, then the learned ones in
-- alphabetical order (a stable order keeps the macro text - and so the button - unchanged), then the hints.
-- nil: nothing to target.
function Quests:Names(questID, objectiveIndex, objective)
    if not objective or objective.finished then
        return nil
    end
    local names, seen = {}, {}
    local fromText = Quests.MobFromText(objective.text, objective.type)
    if fromText then
        names[1], seen[fromText] = fromText, true
    end
    local learned = learnedFor(questID, objectiveIndex)
    if learned then
        local sorted = {}
        for name in pairs(learned) do
            if not seen[name] then
                sorted[#sorted + 1] = name
            end
        end
        table.sort(sorted)
        for _, name in ipairs(sorted) do
            names[#names + 1], seen[name] = name, true
        end
    end
    -- hints: by the quest's title, and by this objective's own text ("or false" keeps the list whole)
    for _, key in ipairs({ self:Title(questID) or false, Quests.CoreText(objective.text) or false }) do
        for _, name in ipairs(key and self:Hints(key) or {}) do
            if not seen[name] then
                names[#names + 1], seen[name] = name, true
            end
        end
    end
    if #names == 0 then
        return nil
    end
    return names
end

ns:RegisterCommand("hint", "'/akt hint add 99-Year-Old Port = Mad Magglish' names the mob of a quest whose tooltips never will - by the quest's title or by the objective as the tracker shows it; '/akt hint list'; '/akt hint remove <title or objective>'", function(rest)
    local mode, args = string.match(rest or "", "^(%S*)%s*(.-)%s*$")
    mode = string.lower(mode or "")
    if mode == "add" then
        local title, mob = string.match(args, "^(.-)%s*=%s*(.-)$")
        if not (title and mob and title ~= "" and mob ~= "") then
            ns:Print("usage: /akt hint add <quest title or objective> = <mob name>")
            return
        end
        Quests:Teach(title, mob)
        ns:Print("hint: " .. title .. " -> " .. mob)
        if ns.Panel then
            ns.Panel:Sync()
        end
    elseif mode == "remove" then
        Quests:Unteach(args)
        ns:Print("hint removed for: " .. tostring(args))
        if ns.Panel then
            ns.Panel:Sync()
        end
    else
        local count = 0
        for title, names in pairs(QUEST_HINTS) do
            print("   " .. title .. " -> " .. table.concat(names, ", ") .. " (built in)")
            count = count + 1
        end
        for title, names in pairs(ns.db and ns.db.hints or {}) do
            print("   " .. title .. " -> " .. table.concat(names, ", "))
            count = count + 1
        end
        ns:Print(count .. " hint(s).")
    end
end)

------------------------------------------------------------------------
-- The quest giver: db.givers[questID] = "Chief Hawkwind"
------------------------------------------------------------------------
local CONNECTORS = { the = true, of = true, de = true, du = true, von = true, van = true, der = true, la = true, le = true }
local NAMES_MAX = 6

-- The proper names in a sentence: the runs of capitalised words ("Speak with Holt Thunderhorn on Hunter
-- Rise in Thunder Bluff." -> Holt Thunderhorn, Hunter Rise, Thunder Bluff). A first word on its own is
-- the verb ("Return", "Speak") and is left out. Every one becomes a "/targetexact": a place name finds
-- nobody and costs nothing.
function Quests.NamesFromText(text)
    local names, seen = {}, {}
    if type(text) ~= "string" or ns.IsSecret(text) then
        return names
    end
    local run, first = {}, true
    local function flush()
        while #run > 0 and CONNECTORS[string.lower(run[#run])] do
            table.remove(run)
        end
        if #run > 0 then
            local name = table.concat(run, " ")
            if not seen[name] and not (first and #run == 1) and #names < NAMES_MAX then
                names[#names + 1], seen[name] = name, true
            end
            first = false
        end
        run = {}
    end
    for word in string.gmatch(text, "%S+") do
        local clean = string.gsub(word, "^[\"%(%[]+", "")
        clean = string.gsub(clean, "[%.,;:!%?\"%)%]]+$", "")
        if string.match(clean, "^%u") then
            run[#run + 1] = clean
        elseif #run > 0 and CONNECTORS[string.lower(clean)] then
            run[#run + 1] = clean
        else
            flush()
            first = false
        end
        if string.match(word, "[%.,;:!%?]$") then
            flush()
        end
    end
    flush()
    return names
end

function Quests:RememberGiver(questID, name)
    local db = ns.db
    if not db or type(questID) ~= "number" or type(name) ~= "string" or name == "" then
        return false
    end
    db.givers = db.givers or {}
    if db.givers[questID] == name then
        return false
    end
    db.givers[questID] = name
    ns:Log("giver", { quest = questID, npc = name })
    return true
end

-- The names to try for a quest that is ready to turn in: the giver we remember, then the names in the
-- completion text. nil: nobody to target.
function Quests:GiverNames(questID)
    local names, seen = {}, {}
    local giver = ns.db and ns.db.givers and ns.db.givers[questID]
    if type(giver) == "string" and giver ~= "" then
        names[1], seen[giver] = giver, true
    end
    if type(C_QuestLog) == "table" and type(GetQuestLogCompletionText) == "function" then
        local index = ns.Readable(C_QuestLog.GetLogIndexForQuestID, questID)
        index = index and index[1]
        if type(index) == "number" then
            local text = ns.Readable(GetQuestLogCompletionText, index)
            for _, name in ipairs(Quests.NamesFromText(text and text[1])) do
                if not seen[name] then
                    names[#names + 1], seen[name] = name, true
                end
            end
        end
    end
    if #names == 0 then
        return nil
    end
    return names
end

-- Whoever is talking to you about a quest is worth remembering: the one who gave it is usually the one to
-- bring it back to, and the one you are handing it to certainly is. "questnpc" is the unit the quest
-- frame itself uses.
local function rememberWhoIsTalking(questID)
    if type(questID) ~= "number" or ns.IsSecret(questID) then
        return
    end
    for _, unit in ipairs({ "questnpc", "npc", "target" }) do
        local name = ns.Readable(UnitName, unit)
        if name and type(name[1]) == "string" and name[1] ~= "" then
            if Quests:RememberGiver(questID, name[1]) then
                ns:Fire("TARGETS_CHANGED")
            end
            return
        end
    end
end

ns:On("QUEST_ACCEPTED", function(_, questID)
    rememberWhoIsTalking(questID)
end)

-- the turn-in dialog, the "what have you got for me" page, the offer page: the quest id comes from the
-- frame's own GetQuestID on this client
for _, event in ipairs({ "QUEST_COMPLETE", "QUEST_PROGRESS", "QUEST_DETAIL" }) do
    ns:On(event, function()
        local id = ns.Readable(GetQuestID)
        rememberWhoIsTalking(id and id[1])
    end)
end

-- a quest that left the log takes what we learned for it along
ns:On("QUEST_REMOVED", function(_, questID)
    if type(questID) == "number" and not ns.IsSecret(questID) then
        if ns.db and ns.db.givers then
            ns.db.givers[questID] = nil
        end
        Quests:Forget(questID)
    end
end)

ns:RegisterCommand("forget", "forget the mobs and quest givers learned for your quests", function()
    if ns.db then
        ns.db.givers = {}
    end
    Quests:Forget()
    ns:Print("forgot every learned mob and quest giver.")
end)
