-- Dungeons: the bosses and rare spawns of the instance you are in, as rows of the panel - there the moment
-- you zone in, each a secure /targetexact button like a quest row, with a marker.
--
-- WHERE THE NAMES COME FROM. Forever does not load the Adventure Guide, so the client has no boss list to
-- ask. A built-in list covers the dungeons and raids (keyed by the instance's map id, with its name as the
-- fallback), and what your group actually meets corrects and extends it: a rare (UnitClassification rare /
-- rareelite) or a skull-level boss seen on your target, under the mouse or on a party member's target is
-- remembered for that instance. A 5-man boss with an ordinary level looks like elite trash to an addon, so
-- new dungeons fill in their rares by themselves and their bosses through '/akt hint' or the next list.
--
-- DEAD. A listed mob seen dead - targeted, moused over, or on a group member's target, which is all the
-- client lets an addon see - is marked killed for this visit: its row goes dim and sorts last, so the panel
-- doubles as "what is left". A /reload keeps the marks; walking in afresh clears them.
--
-- WHERE YOU ARE is asked three ways, because a beta client need not agree with itself: IsInInstance(), the
-- instance's own type from GetInstanceInfo(), and the world map under your feet (a DUNGEON's map by a name
-- on the list). What the client said is logged whenever the answer changes (dungeon_where), and
-- '/akt dungeon list' prints it when the answer is "nowhere".
--
-- THE CAVE IN FRONT of an instance is not the instance: out in the world, where the subzone carries the
-- instance's name, its own rare spawns are rows - after the quest rows, as extras.
--
-- Rules as everywhere in this addon: only reads on units, every answer through the secret check, nothing
-- protected touched here (Panel.lua places the rows, out of combat).
local _, ns = ...

local Dungeons = {}
ns.Dungeons = Dungeons

-- instance map id -> what lives there. Names are the client's English names, exact: /targetexact needs them.
local INSTANCES = {
    [389] = { name = "Ragefire Chasm",
        bosses = { "Oggleflint", "Taragaman the Hungerer", "Jergosh the Invoker", "Bazzalan" }, rares = {} },
    [43] = { name = "Wailing Caverns",
        bosses = { "Lady Anacondra", "Lord Cobrahn", "Kresh", "Lord Pythas", "Skum", "Lord Serpentis", "Verdan the Everliving", "Mutanus the Devourer" },
        rares = { "Deviate Faerie Dragon" } },
    [36] = { name = "The Deadmines",
        bosses = { "Rhahk'Zor", "Sneed's Shredder", "Sneed", "Gilnid", "Mr. Smite", "Captain Greenskin", "Edwin VanCleef", "Cookie" },
        rares = { "Miner Johnson" } },
    [33] = { name = "Shadowfang Keep",
        bosses = { "Rethilgore", "Razorclaw the Butcher", "Baron Silverlaine", "Commander Springvale", "Odo the Blindwatcher", "Fenrus the Devourer", "Wolf Master Nandos", "Archmage Arugal" },
        rares = { "Deathsworn Captain" } },
    [48] = { name = "Blackfathom Deeps",
        bosses = { "Ghamoo-ra", "Lady Sarevess", "Gelihast", "Lorgus Jett", "Baron Aquanis", "Twilight Lord Kelris", "Old Serra'kis", "Aku'mai" }, rares = {} },
    [34] = { name = "The Stockade",
        bosses = { "Targorr the Dread", "Kam Deepfury", "Hamhock", "Bazil Thredd", "Dextren Ward" }, rares = { "Bruegal Ironknuckle" } },
    [90] = { name = "Gnomeregan",
        bosses = { "Grubbis", "Viscous Fallout", "Electrocutioner 6000", "Crowd Pummeler 9-60", "Mekgineer Thermaplugg" }, rares = { "Dark Iron Ambassador" } },
    [47] = { name = "Razorfen Kraul",
        bosses = { "Roogug", "Aggem Thorncurse", "Death Speaker Jargba", "Overlord Ramtusk", "Agathelos the Raging", "Charlga Razorflank" },
        rares = { "Blind Hunter", "Earthcaller Halmgar" } },
    [189] = { name = "Scarlet Monastery",
        bosses = { "Interrogator Vishas", "Bloodmage Thalnos", "Houndmaster Loksey", "Arcanist Doan", "Herod", "High Inquisitor Fairbanks", "Scarlet Commander Mograine", "High Inquisitor Whitemane" },
        rares = { "Ironspine", "Azshir the Sleepless", "Fallen Champion" } },
    [129] = { name = "Razorfen Downs",
        bosses = { "Tuten'kash", "Mordresh Fire Eye", "Glutton", "Plaguemaw the Rotting", "Amnennar the Coldbringer" }, rares = { "Ragglesnout" } },
    [70] = { name = "Uldaman",
        bosses = { "Revelosh", "Baelog", 'Eric "The Swift"', "Olaf", "Ironaya", "Obsidian Sentinel", "Ancient Stone Keeper", "Galgann Firehammer", "Grimlok", "Archaedas" },
        rares = {} },
    [209] = { name = "Zul'Farrak",
        bosses = { "Antu'sul", "Theka the Martyr", "Witch Doctor Zum'rah", "Nekrum Gutchewer", "Shadowpriest Sezz'ziz", "Sergeant Bly", "Hydromancer Velratha", "Gahz'rilla", "Chief Ukorz Sandscalp", "Ruuzlu" },
        rares = { "Dustwraith", "Zerillis", "Sandarr Dunereaver" } },
    [349] = { name = "Maraudon",
        bosses = { "Noxxion", "Razorlash", "Lord Vyletongue", "Celebras the Cursed", "Landslide", "Tinkerer Gizlock", "Rotgrip", "Princess Theradras" },
        rares = { "Meshlok the Harvester" } },
    [109] = { name = "The Temple of Atal'Hakkar",
        bosses = { "Atal'alarion", "Dreamscythe", "Weaver", "Jammal'an the Prophet", "Ogom the Wretched", "Morphaz", "Hazzas", "Avatar of Hakkar", "Shade of Eranikus",
            "Zolo", "Gasher", "Loro", "Hukku", "Zul'Lor", "Mijan" }, rares = {} },
    [230] = { name = "Blackrock Depths",
        bosses = { "Lord Roccor", "High Interrogator Gerstahn", "Houndmaster Grebmar", "Bael'Gar", "Lord Incendius", "Fineous Darkvire", "Warder Stilgiss", "Verek",
            "Pyromancer Loregrain", "General Angerforge", "Golem Lord Argelmach", "Hurley Blackbreath", "Phalanx", "Ribbly Screwspigot", "Plugger Spazzring",
            "Ambassador Flamelash", "Magmus", "Emperor Dagran Thaurissan", "Princess Moira Bronzebeard" },
        rares = { "Panzor the Invincible" } },
    [229] = { name = "Blackrock Spire",
        bosses = { "Highlord Omokk", "Shadow Hunter Vosh'gajin", "War Master Voone", "Mother Smolderweb", "Urok Doomhowl", "Quartermaster Zigris", "Halycon",
            "Gizrul the Slavener", "Overlord Wyrmthalak", "Pyroguard Emberseer", "Solakar Flamewreath", "Goraluk Anvilcrack", "Warchief Rend Blackhand", "Gyth",
            "The Beast", "General Drakkisath" },
        rares = { "Bannok Grimaxe", "Crystal Fang", "Ghok Bashguud", "Spirestone Butcher", "Spirestone Battle Lord", "Spirestone Lord Magus", "Burning Felguard", "Jed Runewatcher" } },
    [429] = { name = "Dire Maul",
        bosses = { "Pusillin", "Zevrim Thornhoof", "Hydrospawn", "Lethtendris", "Alzzin the Wildshaper", "Tendris Warpwood", "Illyanna Ravenoak", "Magister Kalendris",
            "Immol'thar", "Prince Tortheldrin", "Guard Mol'dar", "Stomper Kreeg", "Guard Fengus", "Guard Slip'kik", "Captain Kromcrush", "Cho'Rush the Observer", "King Gordok" },
        rares = { "Tsu'zee", "Skarr the Unbreakable", "Lord Hel'nurath", "Isalien" } },
    [289] = { name = "Scholomance",
        bosses = { "Kirtonos the Herald", "Jandice Barov", "Rattlegore", "Marduk Blackpool", "Vectus", "Ras Frostwhisper", "Instructor Malicia", "Doctor Theolen Krastinov",
            "Lorekeeper Polkelt", "The Ravenian", "Lord Alexei Barov", "Lady Illucia Barov", "Darkmaster Gandling" },
        rares = { "Kormok" } },
    [329] = { name = "Stratholme",
        bosses = { "The Unforgiven", "Timmy the Cruel", "Malor the Zealous", "Cannon Master Willey", "Archivist Galford", "Balnazzar", "Baroness Anastari", "Nerub'enkan",
            "Maleki the Pallid", "Magistrate Barthilas", "Ramstein the Gorger", "Baron Rivendare" },
        rares = { "Skul", "Stonespine", "Hearthsinger Forresten", "Postmaster Malown", "Black Guard Swordsmith" } },
    -- raids
    [249] = { name = "Onyxia's Lair", bosses = { "Onyxia" }, rares = {} },
    [409] = { name = "Molten Core",
        bosses = { "Lucifron", "Magmadar", "Gehennas", "Garr", "Baron Geddon", "Shazzrah", "Sulfuron Harbinger", "Golemagg the Incinerator", "Majordomo Executus", "Ragnaros" }, rares = {} },
    [469] = { name = "Blackwing Lair",
        bosses = { "Razorgore the Untamed", "Vaelastrasz the Corrupt", "Broodlord Lashlayer", "Firemaw", "Ebonroc", "Flamegor", "Chromaggus", "Nefarian" }, rares = {} },
    [309] = { name = "Zul'Gurub",
        bosses = { "High Priestess Jeklik", "High Priest Venoxis", "High Priestess Mar'li", "Bloodlord Mandokir", "Gri'lek", "Hazza'rah", "Renataki", "Wushoolay",
            "Gahz'ranka", "High Priest Thekal", "High Priestess Arlokk", "Jin'do the Hexxer", "Hakkar" }, rares = {} },
    [509] = { name = "Ruins of Ahn'Qiraj",
        bosses = { "Kurinnaxx", "General Rajaxx", "Moam", "Buru the Gorger", "Ayamiss the Hunter", "Ossirian the Unscarred" }, rares = {} },
    [531] = { name = "Temple of Ahn'Qiraj",
        bosses = { "The Prophet Skeram", "Vem", "Lord Kri", "Princess Yauj", "Battleguard Sartura", "Fankriss the Unyielding", "Viscidus", "Princess Huhuran",
            "Emperor Vek'lor", "Emperor Vek'nilash", "Ouro", "C'Thun" }, rares = {} },
    [533] = { name = "Naxxramas",
        bosses = { "Anub'Rekhan", "Grand Widow Faerlina", "Maexxna", "Noth the Plaguebringer", "Heigan the Unclean", "Loatheb", "Instructor Razuvious", "Gothik the Harvester",
            "Thane Korth'azz", "Lady Blaumeux", "Highlord Mograine", "Sir Zeliek", "Patchwerk", "Grobbulus", "Gluth", "Thaddius", "Sapphiron", "Kel'Thuzad" }, rares = {} },
}
Dungeons.INSTANCES = INSTANCES

-- The caves in FRONT of an instance, keyed by the subzone's name. (In the first 0.2.0 these rares sat in
-- the instance's list, where nobody could ever meet them: Trigore the Lasher and Boahn live before the
-- Wailing Caverns portal, not behind it.)
local OUTSIDE = {
    ["Wailing Caverns"] = { name = "Wailing Caverns, outside", bosses = {}, rares = { "Trigore the Lasher", "Boahn" } },
    ["The Deadmines"] = { name = "The Deadmines, outside", bosses = {}, rares = { "Marisa du'Paige", "Brainwashed Noble" } },
    ["Uldaman"] = { name = "Uldaman, outside", bosses = {}, rares = { "Digmaster Shovelphlange" } },
}
Dungeons.OUTSIDE = OUTSIDE

local BY_NAME = {} -- the instance's name is the fallback key, should this client number its maps differently
for _, data in pairs(INSTANCES) do
    BY_NAME[data.name] = data
end

-- a client call that may not exist, may error, and may answer with a secret: all its results as a list, or
-- nil. (The game's Lua is 5.1: no table.unpack, no table.pack - hence the varargs.)
local function collect(ok, ...)
    if not ok then
        return nil
    end
    local out = {}
    for i = 1, select("#", ...) do
        local value = (select(i, ...))
        if ns.IsSecret(value) then
            return nil
        end
        out[i] = value
    end
    return out
end

local function many(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    return collect(pcall(fn, ...))
end

local function readable(fn, ...)
    local results = many(fn, ...)
    return results and results[1] or nil
end

local function store(key)
    ns.db.dungeons = ns.db.dungeons or {}
    local entry = ns.db.dungeons[key]
    if type(entry) ~= "table" or type(entry.learned) ~= "table" or type(entry.killed) ~= "table" then
        entry = { learned = {}, killed = {} }
        ns.db.dungeons[key] = entry
    end
    return entry
end

------------------------------------------------------------------------
-- Where you are
------------------------------------------------------------------------
local DUNGEON_MAP = (type(Enum) == "table" and type(Enum.UIMapType) == "table" and Enum.UIMapType.Dungeon) or 4

local function plain(value)
    if ns.IsSecret(value) then
        return nil
    end
    return value
end

-- Everything the client will say about where you are - readable values only, nothing but strings, numbers
-- and booleans (it goes into the log as it is).
function Dungeons:Where()
    local inInstance = many(IsInInstance)
    local info = many(GetInstanceInfo)
    local facts = {
        inInstance = inInstance and inInstance[1] or false,
        kind = inInstance and inInstance[2] or nil,
        name = info and info[1] or nil,
        infoKind = info and info[2] or nil,
        mapID = info and info[8] or nil,
        zone = readable(GetRealZoneText),
        subzone = readable(GetSubZoneText),
        minimap = readable(GetMinimapZoneText),
    }
    if type(C_Map) == "table" then
        local uiMap = readable(C_Map.GetBestMapForUnit, "player")
        if type(uiMap) == "number" then
            facts.uiMap = uiMap
            local mapInfo = readable(C_Map.GetMapInfo, uiMap)
            if type(mapInfo) == "table" then
                facts.mapName, facts.mapType = plain(mapInfo.name), plain(mapInfo.mapType)
            end
        end
    end
    return facts
end

-- { key, name, kind = "party" | "raid" | "outside", data, how } for a dungeon, a raid or the cave in front
-- of one; nil anywhere else (or when the client will not say). `how` names what decided.
function Dungeons:Current(facts)
    facts = facts or self:Where()
    local kind, how
    if facts.inInstance == true and (facts.kind == "party" or facts.kind == "raid") then
        kind, how = facts.kind, "IsInInstance"
    elseif facts.infoKind == "party" or facts.infoKind == "raid" then
        kind, how = facts.infoKind, "GetInstanceInfo" -- IsInInstance said no (or nothing); the instance's own type says yes
    end
    if kind then
        local name, mapID = facts.name, facts.mapID
        local data = (type(mapID) == "number" and INSTANCES[mapID]) or (type(name) == "string" and BY_NAME[name]) or nil
        local key = (type(mapID) == "number" and mapID ~= 0 and tostring(mapID)) or (type(name) == "string" and name ~= "" and name) or nil
        if key then
            return { key = key, name = (data and data.name) or name or ("instance " .. key), kind = kind, data = data, how = how }
        end
    end
    -- neither would say so: a DUNGEON's map under your feet, by a name on the list, is one all the same
    -- (a listed name only - an unlisted map of that type could be anything)
    if facts.mapType == DUNGEON_MAP and type(facts.mapName) == "string" and BY_NAME[facts.mapName] then
        local data = BY_NAME[facts.mapName]
        return { key = data.name, name = data.name, kind = "party", data = data, how = "the map" }
    end
    -- out in the world, in the cave in front of one
    for _, field in ipairs({ "subzone", "minimap" }) do
        local text = facts[field]
        local data = type(text) == "string" and OUTSIDE[text] or nil
        if data then
            return { key = "out:" .. text, name = data.name, kind = "outside", data = data, how = "the " .. field }
        end
    end
    return nil
end

local function listed(current, name)
    if not (current and current.data) then
        return nil
    end
    for _, boss in ipairs(current.data.bosses or {}) do
        if boss == name then
            return "boss"
        end
    end
    for _, rare in ipairs(current.data.rares or {}) do
        if rare == name then
            return "rare"
        end
    end
    return nil
end

------------------------------------------------------------------------
-- The rows: { { name, kind = "boss" | "rare", done, source = "list" | "learned" } ... }, current
------------------------------------------------------------------------
function Dungeons:Rows()
    if ns:GetOption("dungeon") == false or not ns.db then
        return nil
    end
    local current = self:Current()
    if not current then
        return nil
    end
    local entry = store(current.key)
    local list, seen = {}, {}
    local function add(name, kind, source)
        if seen[name] then
            return
        end
        seen[name] = true
        list[#list + 1] = { name = name, kind = kind, done = entry.killed[name] and true or false, source = source }
    end
    if current.data then
        for _, name in ipairs(current.data.bosses or {}) do
            add(name, "boss", "list")
        end
        for _, name in ipairs(current.data.rares or {}) do
            add(name, "rare", "list")
        end
    end
    -- what was met here: bosses first, then rares, alphabetical (a stable order keeps the macros unchanged)
    local names = {}
    for name in pairs(entry.learned) do
        names[#names + 1] = name
    end
    table.sort(names)
    for _, kind in ipairs({ "boss", "rare" }) do
        for _, name in ipairs(names) do
            if entry.learned[name] == kind then
                add(name, kind, "learned")
            end
        end
    end
    return list, current
end

------------------------------------------------------------------------
-- Learning, and the dead
------------------------------------------------------------------------
-- What the unit is, from what the client will say: "boss" (a raid boss, or skull level), "rare", or nil.
local function kindOf(unit)
    local classification = readable(UnitClassification, unit)
    if classification == "worldboss" then
        return "boss"
    elseif classification == "rareelite" or classification == "rare" then
        return "rare"
    end
    local level = readable(UnitLevel, unit)
    if level == -1 then
        return "boss"
    end
    return nil
end

function Dungeons:Observe(unit)
    if not ns.db or ns:GetOption("dungeon") == false then
        return
    end
    local current = self.current
    if not current then
        return
    end
    if readable(UnitExists, unit) ~= true or readable(UnitIsPlayer, unit) == true then
        return
    end
    local name = readable(UnitName, unit)
    if type(name) ~= "string" or name == "" then
        return
    end
    local entry = store(current.key)
    local known = listed(current, name) or entry.learned[name]
    local changed = false
    if not known then
        local kind = kindOf(unit)
        if kind == "boss" and current.kind == "outside" then
            kind = nil -- out in the world a skull level is just somebody bigger than you
        end
        if kind then
            entry.learned[name] = kind
            known = kind
            changed = true
            ns:Log("dungeon_learned", { key = current.key, name = name, kind = kind })
        end
    end
    if known and not entry.killed[name] and readable(UnitIsDeadOrGhost, unit) == true then
        entry.killed[name] = true
        changed = true
        ns:Log("dungeon_dead", { key = current.key, name = name })
    end
    if changed and ns.Panel then
        ns.Panel:Sync()
    end
end

-- The client says so itself when a boss goes down: ENCOUNTER_END (success 1) and BOSS_KILL carry the
-- encounter's name, whoever was targeting what. A listed or learned name that matches is crossed off.
function Dungeons:EncounterEnded(encounterName, success)
    if not ns.db or ns:GetOption("dungeon") == false then
        return
    end
    local current = self.current
    if not current or type(encounterName) ~= "string" or encounterName == "" then
        return
    end
    if success ~= nil and success ~= 1 and success ~= true then
        return -- a wipe: nobody is dead but us
    end
    local entry = store(current.key)
    local known = listed(current, encounterName) or entry.learned[encounterName]
    if known and not entry.killed[encounterName] then
        entry.killed[encounterName] = true
        ns:Log("dungeon_dead", { key = current.key, name = encounterName, how = "encounter" })
        if ns.Panel then
            ns.Panel:Sync()
        end
    elseif not known then
        ns:Log("dungeon_encounter_unlisted", { key = current.key, name = encounterName })
    end
end

-- Walking into an instance starts a visit: the kill marks of the last one are cleared. A /reload or a
-- fresh login inside keeps them.
local function enteredWorld(event, isInitialLogin, isReloadingUi)
    local facts = Dungeons:Where()
    local current = Dungeons:Current(facts)
    local key = current and current.key or nil
    local moved = key ~= Dungeons.visitKey
    if moved then
        Dungeons.visitKey = key
        if key and not isInitialLogin and not isReloadingUi and ns.db then
            store(key).killed = {}
            ns:Log("dungeon_entered", { key = key, name = current.name, kind = current.kind, listed = current.data ~= nil, how = current.how })
        end
    end
    -- what the client said at the moment it mattered: the report's own look is taken at logout, with the
    -- world already coming down (it said "Eastern Kingdoms" in Orgrimmar, 2026-09-28)
    if moved or event == "PLAYER_ENTERING_WORLD" then
        ns:Log("dungeon_where", facts)
    end
    Dungeons.current = current
    -- a subzone changes every few steps: the panel is only asked when that changed the answer
    if ns.Panel and (moved or event ~= "ZONE_CHANGED") then
        ns.Panel:Sync()
    end
end

ns:On("PLAYER_ENTERING_WORLD", enteredWorld)
ns:On("ZONE_CHANGED_NEW_AREA", function()
    enteredWorld("ZONE_CHANGED_NEW_AREA", false, false)
end)
-- the cave in front of an instance is a subzone: walking in and out of it fires these
for _, event in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }) do
    ns:On(event, function()
        enteredWorld("ZONE_CHANGED", false, false)
    end)
end

ns:On("UPDATE_MOUSEOVER_UNIT", function()
    Dungeons:Observe("mouseover")
end)
ns:On("PLAYER_TARGET_CHANGED", function()
    Dungeons:Observe("target")
end)
for _, event in ipairs({ "UNIT_HEALTH", "UNIT_FLAGS" }) do
    ns:On(event, function(_, unit)
        if unit == "target" then
            Dungeons:Observe("target")
        end
    end)
end
ns:On("UNIT_TARGET", function(_, unit)
    if type(unit) == "string" and (string.find(unit, "^party%d$") or string.find(unit, "^raid%d+$")) then
        Dungeons:Observe(unit .. "target")
    end
end)
ns:On("ENCOUNTER_END", function(_, _, encounterName, _, _, success)
    Dungeons:EncounterEnded(encounterName, success)
end)
ns:On("BOSS_KILL", function(_, _, encounterName)
    Dungeons:EncounterEnded(encounterName, 1)
end)

function Dungeons:Describe()
    local current = self:Current()
    local entry = current and ns.db and ns.db.dungeons and ns.db.dungeons[current.key] or nil
    local learned, killed = {}, {}
    for name, kind in pairs(entry and entry.learned or {}) do
        learned[#learned + 1] = name .. " (" .. kind .. ")"
    end
    for name in pairs(entry and entry.killed or {}) do
        killed[#killed + 1] = name
    end
    table.sort(learned)
    table.sort(killed)
    local info = many(GetInstanceInfo)
    return {
        option = ns:GetOption("dungeon") ~= false,
        current = current and { key = current.key, name = current.name, kind = current.kind, listed = current.data ~= nil, how = current.how } or "not in an instance",
        where = self:Where(), -- (taken at logout, this is the world coming down: the log's dungeon_where entries are the ones to trust)
        instanceInfo = info and { name = info[1], type = info[2], difficultyID = info[3], mapID = info[8] } or "unreadable",
        learned = learned,
        killed = killed,
        known = 0,
        -- what else this client might offer one day
        encounterJournal = type(C_EncounterJournal) == "table" and "C_EncounterJournal present" or "none",
        vignettes = type(C_VignetteInfo) == "table" and "C_VignetteInfo present" or "none",
    }
end

ns:RegisterCommand("dungeon", "'/akt dungeon off': no rows for the instance's bosses and rares, '/akt dungeon on' (default); '/akt dungeon list': what is known about where you are", function(rest)
    local mode = string.lower(rest or "")
    if mode == "on" or mode == "off" then
        ns:SetOption("dungeon", mode == "on")
        ns:Print("dungeon rows", mode == "on" and "on." or "off.")
        if ns.Panel then
            ns.Panel:Sync()
        end
        return
    end
    local rows, current = Dungeons:Rows()
    if not current then
        current = Dungeons:Current()
    end
    if not current then
        -- what the client says, to be read out in a bug report
        local facts = Dungeons:Where()
        ns:Print("not in a dungeon or raid. The client says: in an instance = " .. tostring(facts.inInstance) .. " (" .. tostring(facts.kind)
            .. "); instance '" .. tostring(facts.name) .. "' (" .. tostring(facts.infoKind) .. ", map " .. tostring(facts.mapID)
            .. "); zone '" .. tostring(facts.zone) .. "' / '" .. tostring(facts.subzone)
            .. "'; world map " .. tostring(facts.uiMap) .. " '" .. tostring(facts.mapName) .. "' (type " .. tostring(facts.mapType) .. ").")
        return
    end
    ns:Print(current.name .. (current.data and "" or " (not in the built-in list: what you meet is remembered)")
        .. " - known by " .. tostring(current.how) .. ":")
    for _, row in ipairs(rows or {}) do
        print("   " .. row.name .. " - " .. row.kind .. (row.source == "learned" and ", learned" or "") .. (row.done and ", dead" or ""))
    end
end)
