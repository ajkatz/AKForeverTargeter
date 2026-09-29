-- Targets of interest: a small panel of your own with one row per mob (and quest giver) you are after right
-- now - the tracked quests' kill objectives, the mobs learned for their collect objectives, and the NPC to
-- bring a finished quest back to. Click a row: target it - and, with marking on, mark it. One key (Key
-- Bindings > AddOns > AKForeverTargeter) targets whichever of them is around, in the panel's order.
-- Right-click a row to hide it, Shift + right-click to put it last (and first again). A note beside the
-- title counts the hidden rows; a right-click on the panel brings them all back, '/akt unhide <n>' one of them.
--
-- ONLY WHAT IS HERE: a quest whose business is on another map takes no row ('/akt zone off' shows them
-- all again). The map you are standing in is asked for by name - C_Map.GetBestMapForUnit - and the client
-- is asked which quests it puts there, so nothing is guessed from zone names; a client that will not say
-- leaves every row where it is.
--
-- HOW IT STAYS OUT OF BLIZZARD'S WAY
--   * Nothing of Blizzard's is touched. The rows come from the quest log API (the tracked quests, their
--     objectives, who is ready to turn in) and sit in OUR panel - not in the quest tracker, which cannot
--     hold protected frames (this client refuses to anchor them to its lines; seen in game on 2026-09-21).
--   * Rows are secure action buttons running a macro (/targetexact, /tm), so the targeting and the marking
--     are done by Blizzard's own secure code - in combat too.
--   * Rows are protected frames: made, placed, shown, hidden and given their macro OUT of combat only. In a
--     fight only what is not protected changes: the numbers, the names, and a row whose objective is done
--     goes dim; a row for something new waits for the end of the fight.
--   * Event-driven: the quest log's events book ONE update on the next frame, however many fire at once.
--     Never a timer, never polled.
local _, ns = ...

local Panel = {}
ns.Panel = Panel

local WIDTH, ROW, ICON, PAD, TITLE_H = 220, 20, 16, 8, 22

-- Blizzard's own tooltip backdrop: the dark fill and thin border every utility panel in the game wears.
local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}
local MAX_ROWS = 12
local MAX_ROWS_INSIDE = 20 -- in a dungeon or raid: its bosses and rares, and the quest mobs below them
local MARKER_ORDER = { 8, 7, 6, 5, 4, 3, 2, 1 } -- skull first: the classic "kill this" marker
local MARKER_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
local PLAIN_TEXTURE = "Interface\\Minimap\\Tracking\\Target"
local TURNIN_ATLAS = "QuestTurnin" -- the "?" of a quest ready to turn in
local TURNIN_TEXTURE = "Interface\\GossipFrame\\ActiveQuestIcon"
local FLIGHT_TEXTURE = "Interface\\Minimap\\Tracking\\FlightMaster"
local MACRO_LIMIT = 1000 -- a macrotext attribute takes 1023 characters
local DEFAULT_POSITION = { point = "RIGHT", relativePoint = "RIGHT", x = -30, y = 0 }
local DIM = 0.35
local MARKED_KINDS = { mob = true, boss = true, rare = true } -- what gets a raid marker (a quest giver never)
local MARK_FIRST = { "mob", "boss", "rare" } -- who picks a marker first, whatever the order of the rows
local ANY_BUTTON = "AKForeverTargeterAnyButton" -- the key binding clicks it: "CLICK AKForeverTargeterAnyButton:LeftButton"

-- the Key Bindings screen reads this
_G["BINDING_NAME_CLICK " .. ANY_BUTTON .. ":LeftButton"] = "Target any of them (the first around)"

Panel.state = "not started"
Panel.work = { events = 0, syncs = 0, syncMs = 0, slowestSyncMs = 0, placed = 0, waitedForCombatEnd = 0 }

local panel, title, note, anyButton
local rows = {}        -- every row ever made (a pool: protected frames are never thrown away)
local byKey = {}       -- "questID:objectiveIndex" / "questID:turnin" -> row in use
local markerOf = {}    -- "questID:objectiveIndex" -> raid target index, kept while the objective is shown
local pending = false  -- a change waits for the end of the fight
local syncBooked = false
local hiddenCount = 0
local elsewhereCount = 0 -- rows left out because that quest's business is on another map
local cutCount = 0       -- rows that did not fit
local decisions = {}     -- the last pass, quest by quest: here or not and why, what each objective names - for the report
local cutKeys = {}       -- ... and the rows that did not fit
local hiddenList = {} -- what a right-click hid, in the tracker's order: { key, names, title }

------------------------------------------------------------------------
-- Hidden and lowered rows: db.hidden[key] / db.deprio[key], keyed like the rows ("7:1", "300:turnin")
------------------------------------------------------------------------
function Panel.IsHidden(key)
    return ns.db and ns.db.hidden and ns.db.hidden[key] == true
end

function Panel.IsDeprio(key)
    return ns.db and ns.db.deprio and ns.db.deprio[key] == true
end

function Panel:SetHidden(key, hidden)
    if not ns.db then
        return
    end
    ns.db.hidden = ns.db.hidden or {}
    ns.db.hidden[key] = hidden and true or nil
    ns:Log("hide", { key = key, hidden = hidden and true or false })
    Panel:Sync()
end

function Panel:UnhideAll()
    if ns.db then
        ns.db.hidden = {}
    end
    ns:Log("hide", "all back")
    Panel:Sync()
end

-- the hidden rows as a numbered list for '/akt hidden' and '/akt unhide <n>'
function Panel:HiddenList()
    return hiddenList
end

function Panel:SetDeprio(key, deprio)
    if not ns.db then
        return
    end
    ns.db.deprio = ns.db.deprio or {}
    ns.db.deprio[key] = deprio and true or nil
    ns:Log("deprio", { key = key, deprio = deprio and true or false })
    Panel:Sync()
end

------------------------------------------------------------------------
-- The macro
------------------------------------------------------------------------
-- The current target is put aside first and taken back when none of the names was found, so a click with
-- nobody of that name around changes nothing - and the marker can only ever land on a mob we asked for.
function Panel.MacroFor(names, marker)
    local lines = { "/cleartarget" }
    local length = #lines[1]
    for _, name in ipairs(names) do
        local line = "/targetexact " .. name
        if length + #line + 1 > MACRO_LIMIT - 60 then
            break
        end
        lines[#lines + 1] = line
        length = length + #line + 1
    end
    if marker then
        lines[#lines + 1] = "/tm [exists,nodead] !" .. marker -- "!": never toggles an already set marker off
    end
    lines[#lines + 1] = "/targetlasttarget [noexists]"
    return table.concat(lines, "\n")
end

-- One key for all of them: the names are tried in the panel's order, each only while nothing was found
-- yet ("[noexists]"), and the mob found is marked with its own row's marker - unless it already carries
-- one ("~"), so a later row's marker never lands on an earlier row's mob. The quest givers come last,
-- with no marker line after them.
function Panel.AnyMacroFor(list, markers)
    local lines = { "/cleartarget" }
    local length = #lines[1]
    local function add(line)
        if length + #line + 1 > MACRO_LIMIT - 60 then
            return false
        end
        lines[#lines + 1] = line
        length = length + #line + 1
        return true
    end
    for _, kind in ipairs({ "mob", "boss", "rare", "giver", "flightmaster" }) do
        for _, want in ipairs(list) do
            if want.kind == kind and not want.done then -- (a dead boss is not worth a line)
                for _, name in ipairs(want.names) do
                    add("/targetexact [noexists] " .. name)
                end
                local marker = markers and markers[want.key]
                if MARKED_KINDS[kind] and marker then
                    add("/tm [exists,nodead] ~" .. marker)
                end
            end
        end
    end
    lines[#lines + 1] = "/targetlasttarget [noexists]"
    return table.concat(lines, "\n")
end

------------------------------------------------------------------------
-- What you are after right now: { { key, kind, questID, order, index, names, title, progress } ... } - from
-- the quest log, the tracked quests in the order of the tracker.
------------------------------------------------------------------------
-- More rows than fit. What stays: the quest you picked in the tracker; then whatever is nearest, where
-- the client gives distances; a mob nobody knows the distance to counts as near (a row too many is better
-- than a row missing), somebody to turn in to as far - ten turn-ins for people in town must not push the
-- mobs in front of you off the panel. What you lowered goes first of all. Those that stay keep their order.
local function rankOf(entry, position)
    local rank = position * 0.001 -- the tracker's order settles a tie
    if entry.deprio then
        rank = rank + 3e6
    end
    if entry.picked then
        return rank
    end
    if entry.distance then
        return rank + 1 + math.min(entry.distance, 9e5)
    end
    if entry.kind == "giver" or entry.kind == "flightmaster" then
        return rank + 1e6
    end
    return rank + 1
end

local function keepNearest(list, cap)
    local ranked = {}
    for position, entry in ipairs(list) do
        entry.rank = rankOf(entry, position)
        ranked[position] = entry
    end
    table.sort(ranked, function(a, b)
        return a.rank < b.rank
    end)
    local staying = {}
    for position = 1, cap do
        staying[ranked[position]] = true
    end
    local kept = {}
    for _, entry in ipairs(list) do
        if staying[entry] then
            kept[#kept + 1] = entry
        end
    end
    return kept
end

-- record: keep what was decided, quest by quest, for the report (the full pass does; a pass in combat does not)
local function wanted(record)
    local list = {}
    hiddenCount, elsewhereCount, cutCount = 0, 0, 0
    if not ns:GetOption("tracker") then
        return list
    end
    local zoneOnly = ns:GetOption("zoneOnly") ~= false
    local hereSet, whyHere = nil, "not asked"
    if zoneOnly then
        hereSet, whyHere = ns.Quests:MapQuests()
    end
    Panel.zoneNote = whyHere
    hiddenList = {}
    local function add(entry)
        if Panel.IsHidden(entry.key) then
            hiddenCount = hiddenCount + 1
            hiddenList[hiddenCount] = entry
            return false
        end
        entry.deprio = Panel.IsDeprio(entry.key)
        list[#list + 1] = entry
        return true
    end
    -- The instance you are in is asked first: inside one, the panel is about the DUNGEON and nothing
    -- else. Its bosses and rares go on top, and of the quests only the dungeon's own get a row: what the
    -- dungeon's map carries, or - this client will not say which map you are on in there (measured
    -- 2026-09-29 in the Wailing Caverns: every tracked quest counted as here, and twelve rows from
    -- Hillsbrad and the Barrens left no room for a single boss) - what the client tags as a dungeon or
    -- raid quest. A turn-in needs the map: its NPC is outside. '/akt zone off' shows everything, in here too.
    local dungeonRows, dungeon
    if ns.Dungeons then
        dungeonRows, dungeon = ns.Dungeons:Rows()
    end
    local inside = dungeon ~= nil and dungeon.kind ~= "outside"
    local dungeonNames = {}
    for _, entry in ipairs(inside and dungeonRows or {}) do
        dungeonNames[entry.name] = true
    end
    if inside and zoneOnly then
        Panel.zoneNote = "in " .. tostring(dungeon.name) .. ": the dungeon's own only (" .. tostring(whyHere) .. ")"
    end

    local Quests = ns.Quests
    -- The quest you picked in the tracker is the one you are on: here wherever the map puts it, and the
    -- last to give way when the panel is full. (Out in the world; a dungeon is about the dungeon.)
    local picked = (not inside) and Quests:SuperTracked() or nil
    local decided, guessSeen = 0, {}
    for order, questID in ipairs(Quests:Tracked()) do
        local questTitle = Quests:Title(questID)
        local ready = Quests:ReadyForTurnIn(questID)
        local here, why
        if not zoneOnly then
            here, why = true, "the zone filter is off"
        elseif inside then
            if hereSet ~= nil and hereSet[questID] == true then
                here, why = true, "on the dungeon's map"
            elseif ready then
                here, why = false, "a turn-in: its NPC is outside"
            else
                here, why = Quests:IsDungeonQuest(questID)
                why = (here and "a dungeon quest: " or "not the dungeon's: ") .. tostring(why)
            end
        elseif questID == picked then
            here, why = true, "the quest you picked in the tracker"
        elseif hereSet == nil then
            here, why = true, "the client would not say"
        else
            here, why = Quests:IsHere(questID, hereSet)
        end
        -- (not asked in a fight: the rows cannot change there anyway)
        local distance = (here and not inside and not InCombatLockdown()) and Quests:Distance(questID) or nil
        local decision
        if record then
            decided = decided + 1
            decision = decisions[decided]
            if not decision then
                decision = { objectives = {} }
                decisions[decided] = decision
            end
            decision.id, decision.title, decision.here, decision.why = questID, questTitle, here, why
            decision.ready, decision.picked, decision.rows = ready, (questID == picked) or nil, 0
            decision.yards = distance and math.floor(distance + 0.5) or nil
            for index = #decision.objectives, 1, -1 do
                decision.objectives[index] = nil
            end
        end
        if not here then
            elsewhereCount = elsewhereCount + 1
        end
        if here then
        if ready then
            local names = Quests:GiverNames(questID)
            if decision then
                decision.objectives[1] = "turn in -> " .. (names and table.concat(names, ", ") or "nobody known")
            end
            if names then
                -- (inside, with a client that will not say what is on the map: last of all)
                local added = add({ key = questID .. ":turnin", kind = "giver", questID = questID, order = (inside and 900 or 0) + order, index = 0,
                    names = names, title = questTitle, progress = "turn in", distance = distance, picked = questID == picked })
                if added and decision then
                    decision.rows = decision.rows + 1
                end
            end
        else
            for _, objective in ipairs(Quests:Objectives(questID) or {}) do
                if not objective.finished then
                    local names, guessed = Quests:Names(questID, objective.index, objective)
                    if decision then
                        decision.objectives[#decision.objectives + 1] = tostring(objective.text) .. " [" .. tostring(objective.type) .. "] -> "
                            .. (names and table.concat(names, ", ") or "no name") .. (guessed and " (a guess)" or "")
                    end
                    if names and guessed then
                        -- one guess names the quest's mob once, however many nameless objectives it has
                        local seenKey = questID .. ":" .. names[1]
                        if guessSeen[seenKey] then
                            names = nil
                        else
                            guessSeen[seenKey] = true
                        end
                    end
                    if names and inside then
                        -- a quest after a boss: the boss has its row already
                        local others = false
                        for _, name in ipairs(names) do
                            if not dungeonNames[name] then
                                others = true
                            end
                        end
                        if not others then
                            names = nil
                        end
                    end
                    if names then
                        local progress
                        if type(objective.numFulfilled) == "number" and type(objective.numRequired) == "number" and objective.numRequired > 0 then
                            progress = objective.numFulfilled .. "/" .. objective.numRequired
                        end
                        local added = add({ key = questID .. ":" .. objective.index, kind = "mob", questID = questID, order = order,
                            index = objective.index, names = names, title = questTitle, progress = progress,
                            distance = distance, picked = questID == picked, guessed = guessed })
                        if added and decision then
                            decision.rows = decision.rows + 1
                        end
                    end
                end
            end
        end
        end
    end
    if record then
        for index = #decisions, decided + 1, -1 do
            decisions[index] = nil
        end
        for index = #cutKeys, 1, -1 do
            cutKeys[index] = nil
        end
    end
    -- the bosses and rare spawns: on top inside, the dead below the quest mobs; the rares of the cave in
    -- front of an instance come after the quests, as extras
    for index, entry in ipairs(dungeonRows or {}) do
        local order = (entry.done and 800 or 500) + index
        if inside then
            order = (entry.done and 700 or -1000) + index
        end
        add({ key = "dg:" .. dungeon.key .. ":" .. entry.name, kind = entry.kind, questID = 0,
            order = order, index = 0, names = { entry.name }, title = dungeon.name,
            progress = entry.done and "dead" or entry.kind, done = entry.done })
    end
    -- flight master: if we know one for this map, add it at the end
    if ns:GetOption("flightmaster") and ns.db and ns.db.flightmasters then
        local mapID = type(C_Map) == "table" and type(C_Map.GetBestMapForUnit) == "function"
            and C_Map.GetBestMapForUnit("player") or nil
        if mapID and not ns.IsSecret(mapID) then
            local name = ns.db.flightmasters[mapID]
            if name then
                add({ key = "fm:" .. mapID, kind = "flightmaster", questID = 0,
                    order = 999, index = 0, names = { name }, title = "Flight Master", progress = "" })
            end
        end
    end

    -- the tracker's order; what you lowered comes last
    table.sort(list, function(a, b)
        if a.deprio ~= b.deprio then
            return b.deprio
        end
        if a.order ~= b.order then
            return a.order < b.order
        end
        return a.index < b.index
    end)
    local cap = inside and MAX_ROWS_INSIDE or MAX_ROWS
    if #list > cap then
        cutCount = #list - cap
        -- (inside, the order is the rank: the dungeon first, and what does not fit is at the bottom)
        local kept = inside and list or keepNearest(list, cap)
        if record then
            local staying = {}
            for position = 1, cap do
                staying[kept[position]] = true
            end
            for _, entry in ipairs(list) do
                if not staying[entry] then
                    cutKeys[#cutKeys + 1] = entry.key .. " " .. tostring(entry.names[1])
                end
            end
        end
        list = kept
        while #list > cap do
            table.remove(list)
        end
    end
    return list
end

------------------------------------------------------------------------
-- The panel and its rows
------------------------------------------------------------------------
local tooltip

local function showTooltip(row)
    if not tooltip then
        -- our own tooltip: the game's shared one is never touched from here
        tooltip = CreateFrame("GameTooltip", "AKForeverTargeterTooltip", UIParent, "GameTooltipTemplate")
    end
    tooltip:SetOwner(row, "ANCHOR_LEFT")
    tooltip:AddLine(row.questTitle or "", 1, 0.82, 0)
    tooltip:AddLine("Target: " .. table.concat(row.names or {}, ", "), 1, 1, 1)
    if row.kind == "flightmaster" then
        tooltip:AddLine("flight master for this zone", 0.8, 0.8, 0.8)
    elseif row.kind == "giver" then
        tooltip:AddLine("to turn the quest in", 0.8, 0.8, 0.8)
    elseif row.kind == "boss" then
        tooltip:AddLine(row.done and "dungeon boss - dead" or "dungeon boss", 0.8, 0.8, 0.8)
    elseif row.kind == "rare" then
        tooltip:AddLine(row.done and "rare spawn - dead" or "rare spawn", 0.8, 0.8, 0.8)
    end
    if row.guessed then
        tooltip:AddLine("a guess from the quest's wording - his own tooltip will tell", 0.8, 0.8, 0.8)
    end
    if row.marker and row.kind ~= "giver" and row.kind ~= "flightmaster" then
        tooltip:AddLine("and mark it", 0.8, 0.8, 0.8)
    end
    if row.stale then
        tooltip:AddLine("(changes after the fight)", 0.6, 0.6, 0.6)
    end
    tooltip:AddLine("Right-click: hide.  Shift + right-click: " .. (row.deprio and "raise" or "lower") .. " its priority.", 0.6, 0.6, 0.6)
    tooltip:Show()
end

-- The right button is ours: hide the row, or (with Shift) lower / raise its priority.
local function rightClick(row)
    if not row.key then
        return
    end
    if type(IsShiftKeyDown) == "function" and IsShiftKeyDown() then
        Panel:SetDeprio(row.key, not Panel.IsDeprio(row.key))
    else
        Panel:SetHidden(row.key, true)
    end
end

-- What a click did, for /akt diag: did the macro find one of the names, and did the marker land?
-- (Runs after Blizzard's secure click handler; only reads.)
local function afterClick(row)
    local target = ns.Readable(UnitName, "target")
    local targetName = target and target[1] or nil
    local found = false
    for _, name in ipairs(row.names or {}) do
        if name == targetName then
            found = true
        end
    end
    local marker = "n/a"
    if type(GetRaidTargetIndex) == "function" then
        local ok, index = pcall(GetRaidTargetIndex, "target")
        marker = (not ok and "error") or (ns.IsSecret(index) and "<secret>") or index or "none"
    end
    ns:Log("click", { key = row.key, found = found, target = targetName or "<none or unreadable>", markerNow = marker, wanted = row.marker })
end

local function setIcon(row, kind, marker)
    local iconKey = kind .. ":" .. tostring(marker)
    if row.iconKey == iconKey then
        return
    end
    row.iconKey = iconKey
    local icon = row.icon
    if kind == "flightmaster" then
        icon:SetTexture(FLIGHT_TEXTURE)
    elseif kind == "giver" then
        local atlas = type(C_Texture) == "table" and type(C_Texture.GetAtlasInfo) == "function" and C_Texture.GetAtlasInfo(TURNIN_ATLAS)
        if atlas and type(icon.SetAtlas) == "function" then
            icon:SetAtlas(TURNIN_ATLAS)
        else
            icon:SetTexture(TURNIN_TEXTURE)
        end
    else
        icon:SetTexture(marker and (MARKER_TEXTURE .. marker) or PLAIN_TEXTURE)
    end
end

local function updateTitle()
    if not title then
        return
    end
    -- the title never changes; the counts sit in a small dim note beside it, which the title yields to
    local notes = {}
    if cutCount > 0 then
        notes[#notes + 1] = "+" .. cutCount .. " more"
    end
    if hiddenCount > 0 then
        notes[#notes + 1] = hiddenCount .. " hidden"
    end
    if elsewhereCount > 0 then
        notes[#notes + 1] = elsewhereCount .. " elsewhere"
    end
    if note then
        note:SetText(table.concat(notes, ", "))
    end
end

local function savePosition()
    local point, _, relativePoint, x, y = panel:GetPoint(1)
    if type(point) == "string" and type(x) == "number" and type(y) == "number" then
        ns.cdb.options.panel = { point = point, relativePoint = relativePoint or point, x = x, y = y }
    end
end

-- (out of combat) where the panel goes: where you dropped it, or the default place
local function place()
    local saved = ns.cdb and ns.cdb.options and ns.cdb.options.panel
    local position = (type(saved) == "table" and type(saved.x) == "number" and type(saved.y) == "number") and saved or DEFAULT_POSITION
    panel:ClearAllPoints()
    panel:SetPoint(position.point or "RIGHT", UIParent, position.relativePoint or position.point or "RIGHT", position.x, position.y)
end

local function build()
    panel = CreateFrame("Frame", "AKForeverTargeterPanel", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    panel:SetSize(WIDTH, TITLE_H + PAD)
    panel:SetFrameStrata("LOW")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then
            self:StartMoving()
        end
    end)
    panel:SetScript("OnDragStop", function(self)
        if InCombatLockdown() then
            return
        end
        self:StopMovingOrSizing()
        if type(self.SetUserPlaced) == "function" then
            self:SetUserPlaced(false) -- our saved place is the one that counts, not the client's layout cache
        end
        ns.SafeCall(savePosition)
    end)
    panel:Hide()

    if type(panel.SetBackdrop) == "function" then
        panel:SetBackdrop(BACKDROP)
        panel:SetBackdropColor(0.09, 0.09, 0.19, 0.92) -- TOOLTIP_DEFAULT_BACKGROUND_COLOR
        panel:SetBackdropBorderColor(1, 1, 1, 1)
        Panel.look = "Blizzard's tooltip backdrop"
    else
        -- a client without the backdrop template: a plain dark fill rather than nothing
        local background = panel:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints(panel)
        background:SetColorTexture(0.04, 0.04, 0.06, 0.8)
        Panel.look = "flat fill (no BackdropTemplate on this client)"
    end

    -- The counts, small and dim, right-aligned on the title line; the title fills what is left and
    -- truncates rather than leave the box (word wrap off: an ellipsis, never a second line).
    note = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -(PAD - 1))
    note:SetJustifyH("RIGHT")
    note:SetWordWrap(false)
    note:SetText("")

    title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(PAD - 2))
    title:SetPoint("RIGHT", note, "LEFT", -4, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetText("Targets of interest")
    Panel.header = { title = title, note = note } -- (read by the tests)
    -- a right-click on the panel (not on a row) brings every hidden row back
    panel:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton == "RightButton" then
            ns.SafeCall(Panel.UnhideAll, Panel)
        end
    end)
    panel:SetScript("OnEnter", function(self)
        ns.SafeCall(function()
            if not tooltip then
                tooltip = CreateFrame("GameTooltip", "AKForeverTargeterTooltip", UIParent, "GameTooltipTemplate")
            end
            tooltip:SetOwner(self, "ANCHOR_LEFT")
            tooltip:AddLine("Targets of interest", 1, 0.82, 0)
            tooltip:AddLine("Drag to move.", 0.8, 0.8, 0.8)
            if hiddenCount > 0 then
                tooltip:AddLine("Right-click: bring back the " .. hiddenCount .. " hidden row(s).", 0.8, 0.8, 0.8)
            end
            tooltip:Show()
        end)
    end)
    panel:SetScript("OnLeave", function()
        if tooltip then
            tooltip:Hide()
        end
    end)
    place()

    -- the key's button: shown (a hidden button takes no click), a pixel big, invisible, out of the mouse's way
    anyButton = CreateFrame("Button", ANY_BUTTON, UIParent, "SecureActionButtonTemplate")
    anyButton:SetSize(1, 1)
    anyButton:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    anyButton:SetAlpha(0)
    anyButton:EnableMouse(false)
    anyButton:RegisterForClicks("AnyUp", "AnyDown") -- works with either ActionButtonUseKeyDown setting
    anyButton:SetAttribute("type", "macro")
    anyButton.key, anyButton.names = "any", {}
    anyButton:SetScript("PostClick", function(self, _, down)
        if not down then
            ns.SafeCall(afterClick, self)
        end
    end)
end

local function newRow()
    local index = #rows + 1
    local row = CreateFrame("Button", "AKForeverTargeterRow" .. index, panel, "SecureActionButtonTemplate")
    row:SetSize(WIDTH - 2 * PAD, ROW)
    row:RegisterForClicks("AnyUp", "AnyDown") -- works with either ActionButtonUseKeyDown setting
    row:SetAttribute("type", "macro")
    row:SetAttribute("type2", ATTRIBUTE_NOOP or "") -- the right button runs no secure action: it is ours
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON, ICON)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.progress = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.progress:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.progress:SetJustifyH("RIGHT")
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.name:SetPoint("RIGHT", row.progress, "LEFT", -4, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    -- crossed off: a line through the name once the boss is dead
    row.strike = row:CreateTexture(nil, "OVERLAY")
    row.strike:SetHeight(1)
    row.strike:SetPoint("LEFT", row.name, "LEFT", 0, 0)
    row.strike:SetColorTexture(1, 1, 1, 0.8)
    row.strike:Hide()
    row:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    row:SetScript("OnEnter", function(self)
        ns.SafeCall(showTooltip, self)
    end)
    row:SetScript("OnLeave", function()
        if tooltip then
            tooltip:Hide()
        end
    end)
    row:SetScript("PostClick", function(self, mouseButton, down)
        if down then
            return
        end
        if mouseButton == "RightButton" then
            ns.SafeCall(rightClick, self)
        else
            ns.SafeCall(afterClick, self)
        end
    end)
    row:Hide()
    rows[index] = row
    return row
end

local function freeRow()
    for _, row in ipairs(rows) do
        if not row.key then
            return row
        end
    end
    return newRow()
end

local function nextMarker(inUse)
    for _, marker in ipairs(MARKER_ORDER) do
        if not inUse[marker] then
            return marker
        end
    end
    return MARKER_ORDER[1] -- more than eight mobs on the list: the skull is shared
end

-- what a row shows - none of it protected, so this runs in a fight too
local function dress(row, want)
    row.questTitle, row.names, row.deprio, row.done = want.title, want.names, want.deprio, want.done or nil
    row.guessed = want.guessed or nil
    row.name:SetText(want.names[1] or "")
    row.progress:SetText(want.progress or "")
    if row.strike then
        if want.done then
            local width = type(row.name.GetStringWidth) == "function" and row.name:GetStringWidth() or 0
            row.strike:SetWidth(math.max(1, width))
            row.strike:Show()
        else
            row.strike:Hide()
        end
    end
end

------------------------------------------------------------------------
-- Sync: out of combat only
------------------------------------------------------------------------
local function release(row)
    byKey[row.key] = nil
    row.key, row.kind, row.names, row.marker, row.slot, row.stale = nil, nil, nil, nil, nil, nil
    row:Hide()
end

local function fullSync()
    local list = wanted(true)
    Panel.decidedAt = type(date) == "function" and date("%Y-%m-%d %H:%M:%S") or nil
    local keep = {}
    for _, want in ipairs(list) do
        keep[want.key] = true
    end
    for key, row in pairs(byKey) do
        if not keep[key] then
            markerOf[key] = nil
            release(row)
        end
    end

    local marking = ns:GetOption("mark")
    -- Markers go by KIND, whatever the order of the rows: the quest mobs first (the trash you pull), then
    -- the bosses, then the rares. The dead give theirs back; a quest giver is never marked.
    for _, want in ipairs(list) do
        if want.done or not (MARKED_KINDS[want.kind] and marking) then
            markerOf[want.key] = nil
        end
    end
    local inUse = {}
    for _, marker in pairs(markerOf) do
        inUse[marker] = true
    end
    for _, kind in ipairs(MARK_FIRST) do
        for _, want in ipairs(list) do
            if want.kind == kind and marking and not want.done and not markerOf[want.key] then
                markerOf[want.key] = nextMarker(inUse)
                inUse[markerOf[want.key]] = true
            end
        end
    end
    local work = Panel.work
    for slot, want in ipairs(list) do
        local row = byKey[want.key]
        if not row then
            row = freeRow()
            row.key = want.key
            byKey[want.key] = row
        end
        local marker = markerOf[want.key]

        local macro = Panel.MacroFor(want.names, marker)
        if row.macro ~= macro then
            row:SetAttribute("macrotext", macro)
            row.macro = macro
        end
        setIcon(row, want.kind, marker)
        row.kind, row.marker, row.stale = want.kind, marker, nil
        dress(row, want)
        if row.slot ~= slot then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(TITLE_H + (slot - 1) * ROW))
            row.slot = slot
            work.placed = work.placed + 1
        end
        local alpha = want.done and DIM or 1
        if row:GetAlpha() ~= alpha then
            row:SetAlpha(alpha)
        end
        if not row:IsShown() then
            row:Show()
        end
    end

    -- the key's macro follows the list
    local anyMacro = Panel.AnyMacroFor(list, marking and markerOf or nil)
    if anyButton and anyButton.macro ~= anyMacro then
        anyButton:SetAttribute("macrotext", anyMacro)
        anyButton.macro = anyMacro
        local names = {}
        for _, want in ipairs(list) do
            for _, name in ipairs(want.names) do
                names[#names + 1] = name
            end
        end
        anyButton.names = names
    end

    local height = TITLE_H + #list * ROW + PAD
    if panel:GetHeight() ~= height then
        panel:SetHeight(height)
    end
    if panel:IsShown() ~= (#list > 0) then
        panel:SetShown(#list > 0)
    end
    Panel.state = (#list == 0 and "nothing to target" or string.format("%d target(s) of interest", #list))
        .. (cutCount > 0 and string.format(", %d more did not fit", cutCount) or "")
        .. (hiddenCount > 0 and string.format(", %d hidden", hiddenCount) or "")
        .. (elsewhereCount > 0 and string.format(", %d quest(s) elsewhere", elsewhereCount) or "")
    updateTitle()
end

-- In combat a protected frame stays as it is: the rows keep their place and their macro. What is not
-- protected follows - the numbers, the names; a row whose objective is done goes dim.
local function combatPass()
    local stillWanted = {}
    for _, want in ipairs(wanted()) do
        stillWanted[want.key] = want
    end
    for key, row in pairs(byKey) do
        local want = stillWanted[key]
        if want then
            dress(row, want)
            row.stale = (Panel.MacroFor(want.names, row.marker) ~= row.macro) or nil
            row:SetAlpha(want.done and DIM or 1)
        else
            row.progress:SetText(Panel.IsHidden(key) and "hidden" or "done")
            row.stale = true
            row:SetAlpha(DIM)
        end
    end
    updateTitle()
end

function Panel:Sync()
    local work = Panel.work
    if not panel then
        return
    end
    if InCombatLockdown() then
        if not pending then
            pending = true
            work.waitedForCombatEnd = work.waitedForCombatEnd + 1
        end
        combatPass()
        return
    end
    pending = false
    local started = debugprofilestop and debugprofilestop()
    fullSync()
    work.syncs = work.syncs + 1
    if started then
        local ms = debugprofilestop() - started
        work.syncMs = work.syncMs + ms
        work.slowestSyncMs = math.max(work.slowestSyncMs, ms)
    end
    if Panel.loggedState ~= Panel.state then
        Panel.loggedState = Panel.state
        ns:Log("panel", Panel.state)
    end
end

-- The quest log fires several events for one change: one update on the next frame covers them all.
local function bookSync()
    Panel.work.events = Panel.work.events + 1
    if syncBooked then
        return
    end
    if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then
        Panel:Sync()
        return
    end
    syncBooked = true
    C_Timer.After(0, function()
        syncBooked = false
        ns.SafeCall(Panel.Sync, Panel)
    end)
end

function Panel:Describe()
    local list = {}
    for key, row in pairs(byKey) do
        list[#list + 1] = {
            key = key,
            kind = row.kind,
            names = row.names,
            marker = row.marker,
            macro = row.macro,
            slot = row.slot,
            shown = row:IsShown(),
            alpha = row:GetAlpha(),
            stale = row.stale or false,
            deprio = row.deprio or false,
            done = row.done or false,
            text = row.name:GetText(),
            progress = row.progress:GetText(),
        }
    end
    table.sort(list, function(a, b) return (a.slot or 0) < (b.slot or 0) end)
    local bound
    if type(GetBindingKey) == "function" then
        local answer = ns.Readable(GetBindingKey, "CLICK " .. ANY_BUTTON .. ":LeftButton")
        bound = answer and answer[1] or nil
    end
    return {
        state = Panel.state,
        any = { macro = anyButton and anyButton.macro or "none", boundTo = bound or "no key yet" },
        built = panel ~= nil,
        shown = panel and panel:IsShown() or false,
        position = ns.cdb and ns.cdb.options and ns.cdb.options.panel or "default",
        made = #rows,
        inUse = list,
        hidden = hiddenCount,
        elsewhere = elsewhereCount,
        -- the last full pass, taken while the world was there: why each tracked quest has its rows or none
        cut = cutCount,
        cutRows = cutKeys,
        decisions = decisions,
        decidedAt = Panel.decidedAt,
        zoneOnly = ns:GetOption("zoneOnly") ~= false,
        zoneNote = Panel.zoneNote,
        pending = pending,
    }
end

------------------------------------------------------------------------
-- Wiring
------------------------------------------------------------------------
ns:Listen("LOGIN", function()
    if InCombatLockdown() then
        Panel.state = "waiting for the fight to end (logged in during combat)"
        return
    end
    build()
    Panel:Sync()
end)

ns:Listen("COMBAT_END", function()
    if not panel then
        build()
        Panel:Sync()
    elseif pending then
        Panel:Sync()
    end
end)

-- PLAYER_CONTROL_GAINED: the end of a flight. In the air the zone events fire at the borders, while the map
-- underneath is whatever the client makes of the sky; the landing itself fires no zone event, so the rows of
-- the zone you left stayed until the next quest event (seen 2026-09-28). The ride's end is a moment to look.
for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
    "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "PLAYER_CONTROL_GAINED",
    "SUPER_TRACKING_CHANGED" }) do
    ns:On(event, bookSync)
end

-- a quest that leaves the log takes its hidden / lowered flags along
ns:On("QUEST_REMOVED", function(_, questID)
    if type(questID) ~= "number" or ns.IsSecret(questID) or not ns.db then
        return
    end
    local prefix = questID .. ":"
    for _, flags in ipairs({ ns.db.hidden or {}, ns.db.deprio or {} }) do
        for key in pairs(flags) do
            if type(key) == "string" and string.sub(key, 1, #prefix) == prefix then
                flags[key] = nil
            end
        end
    end
end)

ns:On("UNIT_QUEST_LOG_CHANGED", function(_, unit)
    if not ns.IsSecret(unit) and unit == "player" then
        bookSync()
    end
end)

ns:Listen("TARGETS_CHANGED", function()
    Panel:Sync()
end)

ns:Listen("OPTION_CHANGED", function(_, key)
    if key == "tracker" or key == "mark" or key == "flightmaster" then
        Panel:Sync()
    end
end)

-- Learn flight master names from the taxi map: when you open it, the target is the flight master.
ns:On("TAXIMAP_OPENED", function()
    local name = ns.Readable(UnitName, "target")
    name = name and name[1] or nil
    if not name or not ns.db then
        return
    end
    local mapID = type(C_Map) == "table" and type(C_Map.GetBestMapForUnit) == "function"
        and C_Map.GetBestMapForUnit("player") or nil
    if not mapID or ns.IsSecret(mapID) then
        return
    end
    ns.db.flightmasters = ns.db.flightmasters or {}
    if ns.db.flightmasters[mapID] ~= name then
        ns.db.flightmasters[mapID] = name
        ns:Log("learned_flightmaster", { mapID = mapID, name = name })
        bookSync()
    end
end)

ns:RegisterCommand("on", "show the targets of interest panel (default)", function()
    ns:SetOption("tracker", true)
    ns:Print("targets of interest on.")
end)

ns:RegisterCommand("off", "no panel at all", function()
    ns:SetOption("tracker", false)
    ns:Print("targets of interest off" .. (InCombatLockdown() and " - the panel goes when the fight is over." or "."))
end)

ns:RegisterCommand("mark", "'/akt mark off': the rows only target; '/akt mark on': they also mark (default)", function(rest)
    local value = string.lower(rest or "")
    if value == "on" or value == "off" then
        ns:SetOption("mark", value == "on")
    end
    ns:Print("marking is " .. (ns:GetOption("mark") and "on" or "off") .. ".")
end)

ns:RegisterCommand("zone", "'/akt zone off' shows quests from every zone, '/akt zone on' only the ones whose business is here (default)", function(rest)
    local value = string.lower(string.match(rest or "", "^%s*(%a*)"))
    if value == "on" or value == "off" then
        ns:SetOption("zoneOnly", value == "on")
    end
    Panel:Sync()
    ns:Print(ns:GetOption("zoneOnly") ~= false
        and ("only what is here gets a row" .. (elsewhereCount > 0 and (" - " .. elsewhereCount .. " quest(s) left out for now.") or ".")
            .. " (" .. tostring(Panel.zoneNote) .. ")")
        or "every tracked quest gets a row, wherever it is.")
end)

ns:RegisterCommand("flightmaster", "'/akt flightmaster on': add a row for the local flight master (learned when you open the taxi map)", function(rest)
    local value = string.lower(rest or "")
    if value == "on" or value == "off" then
        ns:SetOption("flightmaster", value == "on")
    end
    local on = ns:GetOption("flightmaster")
    local known = ns.db and ns.db.flightmasters and next(ns.db.flightmasters) ~= nil
    ns:Print("flight master targeting is " .. (on and "on" or "off") .. "."
        .. (on and not known and " Open a flight master's taxi map to teach me their name." or ""))
end)

ns:RegisterCommand("hidden", "list the rows you hid with a right-click, numbered for '/akt unhide <number>'", function()
    if #hiddenList == 0 then
        ns:Print("nothing is hidden.")
        return
    end
    ns:Print("hidden (right-click the panel, or '/akt unhide <number>', to bring one back):")
    for number, entry in ipairs(hiddenList) do
        print(string.format("   |cffffd100%d|r  %s  (%s)", number, entry.names[1] or "?", entry.title or "?"))
    end
end)

ns:RegisterCommand("unhide", "'/akt unhide' brings back every hidden row, '/akt unhide 2' the second one on the '/akt hidden' list", function(rest)
    local number = tonumber(string.match(rest or "", "%d+"))
    local after = InCombatLockdown() and " - after the fight." or "."
    if number then
        local entry = hiddenList[number]
        if not entry then
            ns:Print("no hidden row number " .. number .. " - '/akt hidden' lists them.")
            return
        end
        Panel:SetHidden(entry.key, false)
        ns:Print((entry.names[1] or "the row") .. " is back" .. after)
        return
    end
    Panel:UnhideAll()
    ns:Print("every hidden target is back" .. after)
end)

ns:RegisterCommand("reset", "put the panel back at its default place (drag its title to move it)", function()
    if InCombatLockdown() then
        ns:Print("not in combat.")
        return
    end
    ns.cdb.options.panel = nil
    if panel then
        place()
    end
    ns:Print("the panel is back at its default place.")
end)

ns:RegisterCommand("status", "what the addon is doing right now", function()
    ns:Print(Panel.state .. (pending and " (a change is waiting for the fight to end)" or ""))
    ns:Print("one key for any of them: " .. tostring(Panel:Describe().any.boundTo) .. " (Key Bindings > AddOns > AKForeverTargeter).")
end)
