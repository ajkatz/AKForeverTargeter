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
        rares = { "Deviate Faerie Dragon", "Trigore the Lasher", "Boahn" } },
    [36] = { name = "The Deadmines",
        bosses = { "Rhahk'Zor", "Sneed's Shredder", "Sneed", "Gilnid", "Mr. Smite", "Captain Greenskin", "Edwin VanCleef", "Cookie" },
        rares = { "Miner Johnson", "Brainwashed Noble", "Marisa du'Paige" } },
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
        rares = { "Digmaster Shovelphlange" } },
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
-- { key, name, kind = "party" | "raid", data } for a dungeon or raid, nil anywhere else (or when the client will not say)
function Dungeons:Current()
    local inInstance = many(IsInInstance)
    if not inInstance or not inInstance[1] then
        return nil
    end
    local kind = inInstance[2]
    if kind ~= "party" and kind ~= "raid" then
        return nil
    end
    local info = many(GetInstanceInfo)
    if not info then
        return nil
    end
    local name, mapID = info[1], info[8]
    local data = (type(mapID) == "number" and INSTANCES[mapID]) or (type(name) == "string" and BY_NAME[name]) or nil
    local key = (type(mapID) == "number" and mapID ~= 0 and tostring(mapID)) or (type(name) == "string" and name ~= "" and name) or nil
    if not key then
        return nil
    end
    return { key = key, name = (data and data.name) or name or ("instance " .. key), kind = kind, data = data }
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

-- Walking into an instance starts a visit: the kill marks of the last one are cleared. A /reload or a
-- fresh login inside keeps them.
local function enteredWorld(_, isInitialLogin, isReloadingUi)
    local current = Dungeons:Current()
    local key = current and current.key or nil
    if key ~= Dungeons.visitKey then
        Dungeons.visitKey = key
        if key and not isInitialLogin and not isReloadingUi and ns.db then
            store(key).killed = {}
            ns:Log("dungeon_entered", { key = key, name = current.name, kind = current.kind, listed = current.data ~= nil })
        end
    end
    Dungeons.current = current
    if ns.Panel then
        ns.Panel:Sync()
    end
end

ns:On("PLAYER_ENTERING_WORLD", enteredWorld)
ns:On("ZONE_CHANGED_NEW_AREA", function()
    enteredWorld(nil, false, false)
end)

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
        current = current and { key = current.key, name = current.name, kind = current.kind, listed = current.data ~= nil } or "not in an instance",
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
        ns:Print("not in a dungeon or raid.")
        return
    end
    ns:Print(current.name .. (current.data and "" or " (not in the built-in list: what you meet is remembered)") .. ":")
    for _, row in ipairs(rows or {}) do
        print("   " .. row.name .. " - " .. row.kind .. (row.source == "learned" and ", learned" or "") .. (row.done and ", dead" or ""))
    end
end)
