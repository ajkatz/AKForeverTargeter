-- Learns which mobs belong to which tracked quest objective - from the game's own unit tooltip.
--
-- A mob that matters to one of your quests shows that quest in its tooltip: the quest's title, then the
-- objective lines it counts for ("Gold Dust: 2/10"). Matching such a line against our tracked objectives
-- tells us the one thing the quest API will not: who to target for a "collect" objective. Nothing is
-- scanned on a timer: a unit is looked at when the mouse goes over it or when it becomes the target.
local _, ns = ...

local Learn = {}
ns.Learn = Learn

Learn.samples = {} -- the last quest tooltips seen, raw, for /akt diag (what does this client put there?)
local SAMPLES_MAX = 12

local LINE = Enum and Enum.TooltipDataLineType or {}
local QUEST_TITLE, QUEST_OBJECTIVE, QUEST_PLAYER = LINE.QuestTitle or 17, LINE.QuestObjective or 8, LINE.QuestPlayer or 18

local function readable(fn, ...)
    local answer = ns.Readable(fn, ...)
    return answer and answer[1]
end

local function keepSample(mobName, lines)
    local samples = Learn.samples
    for _, sample in ipairs(samples) do
        if sample.mob == mobName then
            return
        end
    end
    samples[#samples + 1] = { mob = mobName, lines = lines }
    if #samples > SAMPLES_MAX then
        table.remove(samples, 1)
    end
end

-- { [questID] = { title = "...", objectives = { ... } } } for the tracked quests
local function trackedObjectives()
    local byQuest = {}
    for _, questID in ipairs(ns.Quests:Tracked()) do
        local objectives = ns.Quests:Objectives(questID)
        if objectives then
            byQuest[questID] = {
                title = type(C_QuestLog.GetTitleForQuestID) == "function" and readable(C_QuestLog.GetTitleForQuestID, questID) or nil,
                objectives = objectives,
            }
        end
    end
    return byQuest
end

-- Mobs we have already read, and when. UPDATE_MOUSEOVER_UNIT fires every time the cursor crosses a
-- unit - in a city, many times a second - and each one used to build a real tooltip (C_TooltipInfo.GetUnit
-- is not a cheap call) and walk the quest log after it. A mob's tooltip does not change while you look at
-- it, so one read stands for a while. Anything that could change what a tooltip MEANS - a quest taken,
-- handed in, or its objectives moving on - empties this, so nothing is ever stale in a way that matters.
local scanned = {}
local scannedCount = 0
local SCAN_AGAIN_AFTER = 8   -- seconds
local SCAN_MEMORY = 60       -- names remembered; past this the oldest go, so a long session cannot grow

function Learn:Forget()
    scanned, scannedCount = {}, 0
end

local function scannedRecently(name, now)
    local at = scanned[name]
    if at and (now - at) < SCAN_AGAIN_AFTER then
        return true
    end
    if not at then
        if scannedCount >= SCAN_MEMORY then
            Learn:Forget() -- cheaper than keeping an order, and it only costs one re-read each
        end
        scannedCount = scannedCount + 1
    end
    scanned[name] = now
    return false
end

function Learn:FromUnit(unit)
    if not ns:GetOption("tracker") then
        return
    end
    if not readable(UnitExists, unit) or readable(UnitIsPlayer, unit) then
        return
    end
    if type(C_QuestLog) == "table" and type(C_QuestLog.UnitIsRelatedToActiveQuest) == "function"
        and readable(C_QuestLog.UnitIsRelatedToActiveQuest, unit) == false then
        return -- the cheap answer: nothing to do with any quest
    end
    local mobName = readable(UnitName, unit)
    if type(mobName) ~= "string" or mobName == "" then
        return
    end
    if scannedRecently(mobName, GetTime()) then
        return -- read this one a moment ago, and nothing has happened since that would change it
    end
    if type(C_TooltipInfo) ~= "table" or type(C_TooltipInfo.GetUnit) ~= "function" then
        return
    end
    local data = readable(C_TooltipInfo.GetUnit, unit)
    if type(data) ~= "table" or type(data.lines) ~= "table" then
        return
    end

    -- the tooltip's quest part: a title line, then that quest's objective lines; in a party a player's
    -- name line introduces somebody else's progress - only our own counts
    local playerName = readable(UnitName, "player")
    local questLines, titles, title, mine = {}, {}, nil, true
    local raw = {}
    for _, line in ipairs(data.lines) do
        if type(line) == "table" and not ns.AnySecret(line.type, line.leftText) then
            if line.type == QUEST_TITLE then
                title, mine = line.leftText, true
                if type(title) == "string" and title ~= "" then
                    titles[#titles + 1] = title
                end
                raw[#raw + 1] = "T|" .. tostring(line.leftText)
            elseif line.type == QUEST_PLAYER then
                mine = (line.leftText == playerName)
                raw[#raw + 1] = "P|" .. tostring(line.leftText)
            elseif line.type == QUEST_OBJECTIVE then
                raw[#raw + 1] = "O|" .. tostring(line.leftText)
                if mine then
                    questLines[#questLines + 1] = { title = title, core = ns.Quests.CoreText(line.leftText) }
                end
            end
        end
    end
    if #raw == 0 then
        return
    end
    keepSample(mobName, raw)

    -- Somebody whose tooltip names a quest you have finished is the one waiting for it: remember them, so
    -- the panel can point you back at them next time (a quest given before this addon knew about it has
    -- nobody on record at all).
    local tracked = #titles > 0 and ns.Quests:Tracked() or nil -- asked once, not once per title
    for _, seen in ipairs(titles) do
        for _, questID in ipairs(tracked) do
            if ns.Quests:Title(questID) == seen and ns.Quests:ReadyForTurnIn(questID) then
                if ns.Quests:RememberGiver(questID, mobName) then
                    ns:Fire("TARGETS_CHANGED")
                end
            end
        end
    end
    if #questLines == 0 then
        return -- a title and nothing else: whoever it is, they are not dropping anything
    end

    local tracked = trackedObjectives()
    for _, questLine in ipairs(questLines) do
        for questID, quest in pairs(tracked) do
            if not questLine.title or not quest.title or questLine.title == quest.title then
                for _, objective in ipairs(quest.objectives) do
                    if not objective.finished and questLine.core and ns.Quests.CoreText(objective.text) == questLine.core then
                        ns.Quests:Learn(questID, objective.index, mobName)
                    end
                end
            end
        end
    end
end

ns:On("UPDATE_MOUSEOVER_UNIT", function()
    Learn:FromUnit("mouseover")
end)

-- Anything that changes what a tooltip means makes every earlier reading worth taking again.
for _, event in ipairs({ "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "UNIT_QUEST_LOG_CHANGED",
    "QUEST_WATCH_LIST_CHANGED", "PLAYER_ENTERING_WORLD" }) do
    ns:On(event, function()
        Learn:Forget()
    end)
end

ns:On("PLAYER_TARGET_CHANGED", function()
    Learn:FromUnit("target")
end)
