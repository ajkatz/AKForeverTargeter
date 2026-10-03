-- AKForeverTargeter core: namespace, safe calls, event dispatch, message bus, saved variables,
-- session log and slash commands.
--
-- The mission of this addon family, built for the WoW: Forever game mode: minimalistic UI additions that bring out the utility Blizzard's UI does
-- not give - minimal in nature, no Lua errors, always smooth. So: nothing runs on a timer, every entry
-- point goes through ns.SafeCall, and every error or blocked action is kept for /akt diag.
--
-- House rules for this addon - targeting and marking are protected actions, and the quest tracker is
-- Blizzard's:
--   * a unit is only ever targeted or marked by Blizzard's own secure code: our buttons are secure action
--     buttons running "/targetexact ..." and "/tm ..." macros. No protected function is called from here.
--   * a protected frame of ours is only created, shown, hidden, moved or given attributes OUT of combat;
--     what changes during a fight waits for its end (the marker menu is moved by its own secure snippet).
--   * on Blizzard's frames only getters are called and fields are only READ; no field is ever written on
--     them, no script is set or hooked on them. hooksecurefunc post-hooks are the one way in.
--   * whatever a getter or a game API returns may be a secret value: it is checked with ns.IsSecret
--     before it is looked at, and "unreadable" always means "hands off".
local ADDON_NAME, ns = ...

ns.name = ADDON_NAME

local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.version = (getMetadata and getMetadata(ADDON_NAME, "Version")) or "dev"
if string.find(ns.version, "@", 1, true) then
    ns.version = "dev" -- a working copy: the packager has not replaced the @project-version@ token
end
ns.version = (string.gsub(ns.version, "^v", "")) -- release tags are "v0.2.0"; we print the "v" ourselves

local PRINT_PREFIX = "|cffe8c45aAKForeverTargeter|r: "

function ns:Print(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring((select(i, ...)))
    end
    print(PRINT_PREFIX .. table.concat(parts, " "))
end

------------------------------------------------------------------------
-- Secret values. WoW: Forever runs the Midnight-era API, where some
-- values handed to addons may be held but not inspected.
------------------------------------------------------------------------
local issecret = type(issecretvalue) == "function" and issecretvalue or nil

function ns.IsSecret(value)
    if issecret then
        return issecret(value) and true or false
    end
    return false
end

function ns.AnySecret(...)
    for i = 1, select("#", ...) do
        if ns.IsSecret((select(i, ...))) then
            return true
        end
    end
    return false
end

-- The results of a getter as a list - or nil when the call failed or any result is secret.
function ns.Readable(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, a, b, c, d, e = pcall(fn, ...)
    if not ok or ns.AnySecret(a, b, c, d, e) then
        return nil
    end
    return { a, b, c, d, e }
end

------------------------------------------------------------------------
-- Safe calls: every distinct error is kept for /akt diag.
------------------------------------------------------------------------
ns.errors = {}

local function onError(err)
    err = tostring(err)
    local seen = ns.errors[err]
    ns.errors[err] = (seen or 0) + 1
    if not seen then
        local handler = geterrorhandler and geterrorhandler()
        if handler then
            handler(err)
        end
    end
    return err
end

function ns.SafeCall(fn, ...)
    return xpcall(fn, onError, ...)
end

------------------------------------------------------------------------
-- Session log (ring buffer), saved with /akt diag and on logout
------------------------------------------------------------------------
local LOG_MAX = 60
ns.sessionLog = {}

function ns:Log(kind, data)
    local log = ns.sessionLog
    log[#log + 1] = {
        t = math.floor(GetTime() * 1000) / 1000,
        k = kind,
        c = InCombatLockdown() and 1 or nil,
        d = data,
    }
    if #log > LOG_MAX then
        table.remove(log, 1)
    end
end

------------------------------------------------------------------------
-- Internal message bus
------------------------------------------------------------------------
local listeners = {}

function ns:Listen(message, fn)
    listeners[message] = listeners[message] or {}
    table.insert(listeners[message], fn)
end

function ns:Fire(message, ...)
    local list = listeners[message]
    if not list then
        return
    end
    for i = 1, #list do
        ns.SafeCall(list[i], message, ...)
    end
end

------------------------------------------------------------------------
-- Game events. Registration is pcall'd so an event that a future client
-- drops shows up in /akt diag instead of breaking the addon at load.
------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local eventHandlers = {}
ns.unknownEvents = {}

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = eventHandlers[event]
    if not list then
        return
    end
    for i = 1, #list do
        ns.SafeCall(list[i], event, ...)
    end
end)

function ns:On(event, fn)
    if not eventHandlers[event] then
        eventHandlers[event] = {}
        if not pcall(eventFrame.RegisterEvent, eventFrame, event) then
            ns.unknownEvents[event] = true
        end
    end
    table.insert(eventHandlers[event], fn)
end

------------------------------------------------------------------------
-- Blocked actions: the client stops the call without a Lua error and shows the "has been blocked"
-- dialog. These events name the function; kept so /akt diag can say exactly what it was.
------------------------------------------------------------------------
ns.blockedActions = {}

local function onActionBlocked(event, addonName, functionName)
    local entry = {
        event = event,
        addon = tostring(addonName),
        ours = addonName == ADDON_NAME,
        fn = tostring(functionName),
        combat = InCombatLockdown() and true or false,
    }
    if #ns.blockedActions >= 40 then
        return
    end
    ns.blockedActions[#ns.blockedActions + 1] = entry
    ns:Log("action_blocked", entry)
end

ns:On("ADDON_ACTION_FORBIDDEN", onActionBlocked)
ns:On("ADDON_ACTION_BLOCKED", onActionBlocked)

------------------------------------------------------------------------
-- Saved variables: ONE account-wide table, per-character data under db.chars["First Last - Realm"].
-- The account-wide part is bound at ADDON_LOADED, the character's profile at PLAYER_LOGIN, when the
-- client knows the character's name for sure (bindProfile).
------------------------------------------------------------------------
local OPTION_DEFAULTS = {
    tracker = true,       -- a target button next to each tracked quest objective that names (or taught us) a mob
    mark = true,          -- ... which also puts a raid target marker on the mob it targets
    -- OFF. The marker menu opens on the key YOU bound to it (Key Bindings -> AddOns), and that is the
    -- only thing that opens it unless you ask for more. A modifier can be set as well - it is the one way
    -- to get the menu up during a fight, because a protected frame can only be shown in combat by one of
    -- Blizzard's state drivers and those know nothing about key bindings. But it is an extra, not a
    -- default: a modifier held down is a second keybind competing with the one you chose.
    menuModifier = "off",
    menuSticky = true,    -- out of combat the menu stays open until you pick a marker or click elsewhere
    zoneOnly = true,      -- only quests whose business is on the map you are standing in get a row
    flightmaster = false, -- add the local flight master to the panel (learned from opening the taxi map)
    dungeon = true,       -- in a dungeon or raid: rows for its bosses and rare spawns (Dungeons.lua)
    typein = true,        -- a type-in box at the bottom of the panel: a name, Enter, and it has a row
}

-- Realm names are squeezed ("Classic Beta PvE" -> "ClassicBetaPvE"): GetRealmName() gives the spaced
-- display name, GetNormalizedRealmName() the squeezed one.
local function squeezeRealm(realm)
    return (string.gsub(realm, "[%s%-]", ""))
end

-- A string the addon may look at: not nil, not empty, not a secret value.
local function readable(value)
    if type(value) ~= "string" or value == "" or ns.IsSecret(value) then
        return nil
    end
    return value
end

local function realmName()
    local realm = GetNormalizedRealmName and readable(GetNormalizedRealmName())
    if not realm and GetRealmName then
        realm = readable(GetRealmName())
        realm = realm and squeezeRealm(realm)
    end
    return realm
end

-- "First Last - Realm": the character's full name and realm - or nil while the client does not know the
-- name yet (a cold login's ADDON_LOADED). Since client build 1.60.1.70170 (Oct 1 2026) WoW: Forever puts
-- the SURNAME where the realm used to be: UnitFullName("player") answers "Purrdee", "Bubson" where earlier
-- builds said "Purrdee Bubson", "ClassicBetaPvE". So whatever sits in the realm slot and is not the realm
-- is the surname, and both builds end up with the key the profiles were saved under all along.
local function characterKey()
    local name, slot
    if UnitFullName then
        name, slot = UnitFullName("player")
    end
    name = readable(name) or (UnitName and readable((UnitName("player"))))
    if not name then
        return nil
    end
    local realm = realmName()
    slot = readable(slot)
    if slot and realm and squeezeRealm(slot) ~= realm then
        name = name .. " " .. slot
    elseif slot and not realm then
        realm = squeezeRealm(slot)
    end
    if not realm then
        return nil
    end
    return name .. " - " .. realm
end

-- Missing values in `target` are filled from `source`, down into nested tables. Nothing that is already
-- in `target` is overwritten.
local function fillGaps(target, source)
    for field, value in pairs(source) do
        local existing = target[field]
        if existing == nil then
            target[field] = value
        elseif type(existing) == "table" and type(value) == "table" then
            fillGaps(existing, value)
        end
    end
end

-- The spellings earlier versions saved the same character under, best first:
--   "First - Last"               build 70170 before this version: the surname was taken for the realm;
--   "First Last - Spaced Realm"  an unsqueezed realm;
--   "Unknown - Realm"            a cold login, the name not known yet when the addon loaded. Every character
--                                that logged in cold shares it, so it goes to the first one to log in after
--                                the update, to fill gaps only.
local function olderSpellings(chars, key)
    local name, realm = string.match(key, "^(.-) %- (.+)$")
    local found = {}
    local first, last = string.match(name, "^(%S+) (%S+)$")
    if first and type(chars[first .. " - " .. last]) == "table" then
        found[#found + 1] = first .. " - " .. last
    end
    local unsqueezed = {}
    for other in pairs(chars) do
        local otherName, otherRealm = string.match(other, "^(.-) %- (.+)$")
        if other ~= key and type(chars[other]) == "table" and otherName == name and otherRealm and squeezeRealm(otherRealm) == realm then
            unsqueezed[#unsqueezed + 1] = other
        end
    end
    table.sort(unsqueezed)
    for _, other in ipairs(unsqueezed) do
        found[#found + 1] = other
    end
    if type(chars["Unknown - " .. realm]) == "table" then
        found[#found + 1] = "Unknown - " .. realm
    end
    return found
end

-- The profile of the character logging in, bound at PLAYER_LOGIN: at ADDON_LOADED a cold login does not
-- know the name yet (that is where the "Unknown - Realm" profiles came from). Until then the stand-in from
-- initDB takes any early write; it is folded in here. A profile saved under an older spelling is adopted
-- once: this profile keeps what it has, the older ones fill its gaps and are removed.
local function bindProfile()
    local key = characterKey()
    if not key then
        ns:Log("profile", { key = false, note = "the client did not give the character's name at login" })
        return
    end
    local chars = ns.db.chars
    local adopted = olderSpellings(chars, key)
    local cdb = chars[key]
    if type(cdb) ~= "table" then
        cdb = {}
        chars[key] = cdb
    end
    for _, old in ipairs(adopted) do
        fillGaps(cdb, chars[old])
        chars[old] = nil
    end
    if ns.cdb and ns.cdb ~= cdb then
        fillGaps(cdb, ns.cdb)
    end
    cdb.options = cdb.options or {}
    ns.characterKey, ns.cdb = key, cdb
    if #adopted > 0 then
        ns:Log("profile", { key = key, adopted = adopted })
    end
end

local function initDB()
    local bridge = AKForeverTargeter_SavedStateBridge
    if type(AKForeverTargeterDB) ~= "table" then
        AKForeverTargeterDB = {}
        ns.savedStateSource = "none (first run, or the client did not load it)"
    elseif type(bridge) == "table" and bridge.table == AKForeverTargeterDB then
        ns.savedStateSource = "bridge addon"
    else
        ns.savedStateSource = "client"
    end
    local db = AKForeverTargeterDB

    db.schema = db.schema or 1
    db.loads = (db.loads or 0) + 1
    db.chars = db.chars or {}

    ns.db = db
    ns.cdb = { options = {} } -- a stand-in until bindProfile, at PLAYER_LOGIN
end

function ns:GetOption(key)
    local options = ns.cdb and ns.cdb.options
    local value = options and options[key]
    if value == nil then
        return OPTION_DEFAULTS[key]
    end
    return value
end

function ns:SetOption(key, value)
    ns.cdb.options[key] = value
    ns:Fire("OPTION_CHANGED", key, value)
end

------------------------------------------------------------------------
-- Slash commands: modules register their own sub-commands
------------------------------------------------------------------------
local commands, commandOrder = {}, {}

function ns:RegisterCommand(name, help, fn)
    commands[name] = { help = help, fn = fn }
    commandOrder[#commandOrder + 1] = name
end

SLASH_AKFOREVERTARGETER1 = "/akforevertargeter"
SLASH_AKFOREVERTARGETER2 = "/akt"
SlashCmdList["AKFOREVERTARGETER"] = function(message)
    local name, rest = string.match(message or "", "^%s*(%S*)%s*(.-)%s*$")
    local command = commands[string.lower(name or "")]
    if command then
        ns.SafeCall(command.fn, rest or "")
        return
    end
    ns:Print("v" .. ns.version .. " commands:")
    for _, commandName in ipairs(commandOrder) do
        print("   |cffffd100/akt " .. commandName .. "|r - " .. commands[commandName].help)
    end
end

------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------
ns:On("ADDON_LOADED", function(_, addonName)
    if addonName ~= ADDON_NAME then
        return
    end
    initDB()
end)

ns:On("PLAYER_LOGIN", function()
    bindProfile()
    ns:Log("login", {
        version = ns.version,
        character = ns.characterKey,
        loads = ns.db and ns.db.loads,
        savedState = ns.savedStateSource,
    })
    ns:Fire("LOGIN")
end)

ns:On("PLAYER_REGEN_ENABLED", function()
    ns:Fire("COMBAT_END")
end)
