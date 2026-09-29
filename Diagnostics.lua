-- /akt diag: a report of what this client says about your quests and what the panel made of it, saved with the settings
-- (AKForeverTargeterDB.diag) so that it can be read from the SavedVariables file after a /reload or logout.
-- Read-only on Blizzard's side; nothing here looks at a value before ns.IsSecret cleared it.
local _, ns = ...

local Diagnostics = {}
ns.Diagnostics = Diagnostics

local function sanitize(value, depth)
    depth = depth or 0
    if ns.IsSecret(value) then
        return "<secret>"
    end
    local kind = type(value)
    if kind == "table" then
        if depth >= 7 then
            return "<too deep>"
        end
        local copy = {}
        for k, v in pairs(value) do
            local key = k
            if ns.IsSecret(k) then
                key = "<secret key>"
            elseif type(k) ~= "string" and type(k) ~= "number" then
                key = tostring(k)
            end
            copy[key] = sanitize(v, depth + 1)
        end
        return copy
    elseif kind == "string" or kind == "number" or kind == "boolean" then
        return value
    elseif kind == "nil" then
        return nil
    end
    return "<" .. kind .. ">"
end

-- One getter's results - "<secret>", "n/a" (no such method) or "error: ..." instead of a surprise.
local function ask(fn, ...)
    if type(fn) ~= "function" then
        return "n/a"
    end
    local ok, first, second = pcall(fn, ...)
    if not ok then
        return "error: " .. tostring(first)
    end
    if second ~= nil then
        return sanitize({ first, second })
    end
    return sanitize(first)
end

local function isFrame(object)
    return type(object) == "table" and type(object.GetObjectType) == "function"
end

-- What the CLIENT says this addon costs. Only asked when a report is made.
function Diagnostics:Performance()
    local result = {}
    if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
        pcall(UpdateAddOnMemoryUsage)
        result.memoryKB = ask(GetAddOnMemoryUsage, ns.name)
    end
    local profiler, metrics = C_AddOnProfiler, Enum and Enum.AddOnProfilerMetric
    if type(profiler) == "table" and type(profiler.GetAddOnMetric) == "function" and type(metrics) == "table" then
        result.profilerEnabled = ask(profiler.IsEnabled)
        result.metricsMs = {}
        for name, id in pairs(metrics) do
            if type(name) == "string" then
                result.metricsMs[name] = ask(profiler.GetAddOnMetric, ns.name, id)
            end
        end
    else
        result.profiler = "this client has no C_AddOnProfiler"
    end
    return result
end

-- The tracked quests as the client reports them - and what we make of each objective.
local function describeQuests()
    local quests = {}
    for _, questID in ipairs(ns.Quests:Tracked()) do
        local entry = {
            id = questID,
            title = type(C_QuestLog) == "table" and ask(C_QuestLog.GetTitleForQuestID, questID) or "n/a",
            readyForTurnIn = ns.Quests:ReadyForTurnIn(questID),
            here = sanitize({ ns.Quests:IsHere(questID) }),
            dungeonQuest = sanitize({ ns.Quests:IsDungeonQuest(questID) }),
            tag = type(C_QuestLog) == "table" and ask(C_QuestLog.GetQuestTagInfo, questID) or "n/a",
            onMapFlag = type(C_QuestLog) == "table" and ask(C_QuestLog.GetInfo,
                (select(1, (ns.Readable(C_QuestLog.GetLogIndexForQuestID, questID) or {})[1])) or 0) or "n/a",
            giverNames = ns.Quests:GiverNames(questID),
            objectives = {},
        }
        for _, objective in ipairs(ns.Quests:Objectives(questID) or {}) do
            entry.objectives[#entry.objectives + 1] = {
                index = objective.index,
                text = objective.text,
                type = objective.type,
                finished = objective.finished,
                numbers = tostring(objective.numFulfilled) .. "/" .. tostring(objective.numRequired),
                mobFromText = ns.Quests.MobFromText(objective.text, objective.type),
                names = ns.Quests:Names(questID, objective.index, objective),
            }
        end
        quests[#quests + 1] = entry
    end
    return quests
end

function Diagnostics:Collect()
    local report = {
        capturedAt = date and date("%Y-%m-%d %H:%M:%S") or "?",
        addonVersion = ns.version,
        character = ns.characterKey,
        savedStateSource = ns.savedStateSource,
        savedVariableLoads = ns.db and ns.db.loads,
        inCombat = InCombatLockdown() and true or false,
        options = { tracker = ns:GetOption("tracker"), mark = ns:GetOption("mark"),
            menuModifier = ns:GetOption("menuModifier"), menuSticky = ns:GetOption("menuSticky"),
            zoneOnly = ns:GetOption("zoneOnly") },
        -- the performance promise, measured: our own gauge, the addon's memory, and the client's profiler
        work = ns.Panel.work,
        performance = Diagnostics:Performance(),
        panel = ns.Panel:Describe(),
        quests = describeQuests(),
        learned = ns.db and ns.db.learned,
        givers = ns.db and ns.db.givers,
        tooltipSamples = ns.Learn.samples,
        markerMenu = ns.MarkerMenu:Describe(),
        dungeon = ns.Dungeons and ns.Dungeons:Describe() or "no module",
        hints = ns.db and ns.db.hints or {},
        inGroup = ask(IsInGroup),
        errors = {},
        blockedActions = ns.blockedActions,
        unknownEvents = ns.unknownEvents,
        log = ns.sessionLog,
    }
    if GetBuildInfo then
        local version, build, buildDate, toc = GetBuildInfo()
        report.build = { version = version, build = build, date = buildDate, toc = toc }
    end
    for message, count in pairs(ns.errors) do
        report.errors[#report.errors + 1] = { message = message, count = count }
    end
    return sanitize(report)
end

-- A report asked for with '/akt diag' is taken while the world is there; the one at logout is not (no
-- objectives, no map - every report since 2026-09-28 shows it). So the one you asked for is kept, and
-- the logout's goes beside it. Either way `panel.decisions` is the panel's last full pass, taken live.
function Diagnostics:Save(asked)
    if not ns.db then
        return
    end
    local report = self:Collect()
    if asked then
        report.asked = true
        ns.db.diag = report
        Diagnostics.asked = true
    elseif Diagnostics.asked then
        ns.db.diagAtLogout = report
    else
        ns.db.diag = report
        ns.db.diagAtLogout = nil
    end
end

ns:RegisterCommand("diag", "save a report into the settings file (then /reload, so that it is written to disk)", function()
    Diagnostics:Save(true)
    ns:Print("report saved - /reload (or log out) writes it to disk. Panel:", ns.Panel.state)
end)

ns:On("PLAYER_LOGOUT", function()
    Diagnostics:Save()
end)
