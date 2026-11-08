-- The marker menu: a 3 x 3 grid at the mouse - the eight raid markers around a "clear" button. The idea
-- and the design of the menu are DejaMark's - credit where it is due. The mouse button decides:
--   LEFT-click a cell:   that marker goes over your target's head.
--   MIDDLE-click a cell: the same marker on the GROUND - Blizzard's placement circle comes up, click the
--                        ground where it goes.
--   RIGHT-click a cell:  clears - your target's marker, and that cell's ground marker.
-- The middle cell: left clears your target's marker, middle clears every ground marker, right both.
-- Under the grid a row of four PINGS (attack, warning, on my way, assist): at your target, or with no
-- target at the ground under the mouse.
--
--      skull     cross     square
--      moon      CLEAR     triangle
--      diamond   circle    star
--      [attack] [warning] [on my way] [assist]
--
-- World markers are numbered differently from target markers (1 = the blue square ... 8 = the white
-- skull; Forever's own WORLD_RAID_MARKER_ORDER in Blizzard_CompactRaidFrameManager.lua), so a cell
-- translates its icon through WORLD_INDEX. Placing goes through Blizzard's secure "worldmarker" action
-- (PlaceRaidMarker), clearing through "/cwm" (ClearRaidMarker); both need a group - leader or assist in a
-- raid. The middle button is "type3" to Blizzard's secure code, as the right one is "type2".
--
-- Marking goes through Blizzard's own "/tm" command on secure action buttons (the only way an addon may
-- set a marker on this client), so the menu is a protected frame: addon code may not show, hide or move it
-- during a fight - and this beta compiles no secure snippets that could do it for us. So the menu is opened
-- in two different ways, and neither needs a snippet:
--   * OUT OF COMBAT the KEY YOU BOUND opens it at the mouse, and by default that is the only thing
--     that does. A modifier can be held instead or as well, but it is off unless asked for (it is
--     everybody's combo key) and it opens at the mouse. It then STAYS until you pick a marker or click
--     somewhere else ("sticky", the default); '/akt menu sticky off' makes it go as the keys go. The key
--     binding toggles it at the mouse as well.
--   * IN COMBAT Blizzard's state driver does it: "[combat,mod:alt] show; [combat] hide" - there while the
--     keys are held. Out of combat that condition decides nothing, so the driver can never take the menu
--     away while we are holding it open; in combat the menu cannot be moved at all, so it appears at its
--     spot (the screen's centre, or where '/akt menu spot' put it).
local _, ns = ...

local MarkerMenu = {}
ns.MarkerMenu = MarkerMenu

local CELL, GAP, PAD = 30, 3, 7
-- a target marker's icon -> the world marker of the same shape (star 5, circle 6, diamond 3, triangle 2,
-- moon 7, square 1, cross 4, skull 8)
local WORLD_INDEX = { 5, 6, 3, 2, 7, 1, 4, 8 }
local CLEAR_ALL_GROUND = "/cwm 1\n/cwm 2\n/cwm 3\n/cwm 4\n/cwm 5\n/cwm 6\n/cwm 7\n/cwm 8" -- ("/cwm all" is localised)
local MARKER_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
-- the grid, row by row; 0 is the clear button
-- ordered by most-used markers: skull, cross, square on top
local GRID = { 8, 7, 6, 5, 0, 4, 3, 2, 1 }
local NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
-- the ping row: "/ping" words and Blizzard's texture kits (Blizzard_PingUI: Ping_Marker_Icon_<kit>)
local PINGS = {
    { word = "attack", kit = "Attack", label = "Attack" },
    { word = "warning", kit = "Warning", label = "Warning" },
    { word = "onmyway", kit = "OnMyWay", label = "On my way" },
    { word = "assist", kit = "Assist", label = "Assist" },
}

-- What you can hold. NOT A LONE ALT: Alt on its own is self-cast, focus-cast and half of everybody's
-- bindings, so the menu came up every time the player so much as brushed it. The pairs belong to nobody
-- else and cannot go off by accident, which is the whole point of them. Lone Ctrl and Shift are still
-- offered for anyone who wants them, but nothing defaults to a single key.
local MODIFIERS = {
    ["ctrl"] = { "ctrl" },
    ["shift"] = { "shift" },
    ["alt-shift"] = { "alt", "shift" },
    ["alt-ctrl"] = { "alt", "ctrl" },
    ["ctrl-shift"] = { "ctrl", "shift" },
}
local MODIFIER_ORDER = { "off", "alt-shift", "alt-ctrl", "ctrl-shift", "ctrl", "shift" }
-- Settings this addon chose for people rather than being asked for, and what they become - once, with a
-- word about it. A modifier somebody picked on purpose is left alone.
local RETIRED = { alt = "off", ["alt-shift"] = "off" }
local MODIFIER_KEYS = {
    alt = { LALT = true, RALT = true },
    ctrl = { LCTRL = true, RCTRL = true },
    shift = { LSHIFT = true, RSHIFT = true },
}
local IS_DOWN = { alt = "IsAltKeyDown", ctrl = "IsControlKeyDown", shift = "IsShiftKeyDown" }

MarkerMenu.BINDING = "AKFOREVERTARGETER_MENU"
MarkerMenu.state = "not built"
MarkerMenu.work = { opened = 0, closed = 0, keptOpen = 0 }

local menu
local cells = {}
local pings = {}
local driverPending = false
local hintedThisFight = false

local function modifier()
    local name = ns:GetOption("menuModifier")
    return MODIFIERS[name] and name or nil
end

-- Somebody who set a lone Alt before it was retired keeps a working menu, on the nearest thing to it.
local function retireLoneModifiers()
    local saved = ns:GetOption("menuModifier")
    local replacement = RETIRED[saved]
    if not replacement then
        return
    end
    ns:SetOption("menuModifier", replacement)
    ns:Print("the marker menu no longer opens on a held |cffffd100" .. saved .. "|r - that was a second keybind "
        .. "on top of the one you set. Bind it under |cffffd100Key Bindings -> AddOns|r; "
        .. "|cffffd100/akt menu mod alt-shift|r puts a modifier back if you want the menu during a fight.")
end

ns:On("PLAYER_LOGIN", function()
    ns.SafeCall(retireLoneModifiers)
end)

local function sticky()
    return ns:GetOption("menuSticky") ~= false
end

-- Is the WHOLE combination held right now?
local function heldNow()
    local name = modifier()
    if not name then
        return false
    end
    for _, part in ipairs(MODIFIERS[name]) do
        local answer = ns.Readable(_G[IS_DOWN[part]])
        if not (answer and answer[1]) then
            return false
        end
    end
    return true
end

local function anyModifierHeld()
    return type(IsModifierKeyDown) == "function" and IsModifierKeyDown() and true or false
end

-- Blizzard's own conditions. "[combat]" on both halves: out of combat the driver decides nothing, so it
-- can never take the menu away while we are holding it open.
local function conditionFor(name)
    local parts = MODIFIERS[name]
    if not parts then
        return nil
    end
    local conditions = { "combat" }
    for _, part in ipairs(parts) do
        conditions[#conditions + 1] = "mod:" .. part
    end
    return "[" .. table.concat(conditions, ",") .. "] show; [combat] hide"
end

-- Places the menu (out of combat only): at the mouse, or at its combat spot.
local function place(atCursor)
    if not menu or InCombatLockdown() then
        return
    end
    menu:ClearAllPoints()
    local scale = menu:GetEffectiveScale()
    if atCursor and type(GetCursorPosition) == "function" and scale > 0 then
        local x, y = GetCursorPosition()
        menu:SetPoint("CENTER", nil, "BOTTOMLEFT", x / scale, y / scale) -- (nil: the screen)
        return
    end
    local spot = ns.cdb and ns.cdb.options and ns.cdb.options.menuSpot
    if type(spot) == "table" and type(spot.x) == "number" and type(spot.y) == "number" then
        menu:SetPoint("CENTER", nil, "BOTTOMLEFT", spot.x, spot.y)
    else
        menu:SetPoint("CENTER", nil, "CENTER", 0, 0)
    end
end

-- Out of combat the menu is ours to open and close.
local function open()
    if not menu or InCombatLockdown() or menu:IsShown() then
        return
    end
    place(true)
    menu:SetAttribute("statehidden", nil) -- (the driver sets it when it hides the menu in combat)
    menu:Show()
    MarkerMenu.work.opened = MarkerMenu.work.opened + 1
end

local function close()
    if not menu or InCombatLockdown() or not menu:IsShown() then
        return
    end
    menu:Hide()
    MarkerMenu.work.closed = MarkerMenu.work.closed + 1
end

-- The state driver, for combat. Registering is protected too, so this waits for the end of a fight.
local function applyDriver()
    if not menu then
        return
    end
    if InCombatLockdown() then
        driverPending = true
        return
    end
    driverPending = false
    local condition = conditionFor(modifier())
    if menu.driver == condition then
        return
    end
    if type(RegisterStateDriver) ~= "function" or type(UnregisterStateDriver) ~= "function" then
        MarkerMenu.state = "ready (this client has no state drivers: out of combat only)"
        return
    end
    if condition then
        local ok, err = pcall(RegisterStateDriver, menu, "visibility", condition)
        menu.driver = ok and condition or nil
        ns:Log("menu", ok and ("driver: " .. condition) or ("driver failed: " .. tostring(err)))
    else
        pcall(UnregisterStateDriver, menu, "visibility")
        menu.driver = nil
        close()
        ns:Log("menu", "driver off")
    end
end

local function said(fn, ...)
    local answer = ns.Readable(fn, ...)
    if answer == nil then
        return nil -- no such function, or a secret: unknown
    end
    return answer[1] and true or false
end

-- Why a ground marker cannot go down right now, in words - or nil when nothing we can see stands in the
-- way. The game often refuses silently, so without this a middle-click that does nothing tells nobody why.
-- Only plain reads: nothing here is protected, and an unknown answer never blocks.
function MarkerMenu.GroundBlocker()
    if said(IsRaidMarkerSystemEnabled) == false then
        return "this client has ground markers switched off - no addon can place them here."
    end
    if said(IsInGroup) == false then
        return "ground markers need a group - invite somebody first."
    end
    if said(IsInRaid) and said(UnitIsGroupLeader, "player") == false and said(UnitIsGroupAssistant, "player") == false then
        return "in a raid only the leader or an assistant can place ground markers."
    end
    return nil
end

-- After the secure action ran: a middle-click is counted and, when we can see why it did nothing, says so.
local function afterGroundClick(cell)
    local work = MarkerMenu.work
    work.groundClicks = (work.groundClicks or 0) + 1
    local blocker = MarkerMenu.GroundBlocker()
    ns:Log("ground_click", { world = cell.world or "all", blocked = blocker or "no",
        enabled = tostring(said(IsRaidMarkerSystemEnabled)), group = tostring(said(IsInGroup)) })
    if blocker then
        ns:Print(blocker)
    end
end

-- One secure cell, an action per mouse button (Blizzard's secure code reads "typeN" and the rest by the
-- button's number: 2 = right, 3 = middle). Left and right are macros. The MIDDLE button is Blizzard's own
-- "worldmarker" action (SecureTemplates.lua: action "set" -> PlaceRaidMarker(marker), "clear" ->
-- ClearRaidMarker(marker)) - the very call the raid frame's World Markers menu makes. A "/wm N" macro was
-- answered "You can't do that right now" on Forever (2026-11-07) while that menu worked. A pick closes the
-- menu (out of combat; in a fight the driver holds it while the keys are down) - after a middle-click that
-- also gets it out of the way of the placement circle.
local function makeCell(name, marker, left, right, world)
    local cell = CreateFrame("Button", name, menu, "SecureActionButtonTemplate")
    cell:SetSize(CELL, CELL)
    cell:RegisterForClicks("AnyUp", "AnyDown") -- works with either ActionButtonUseKeyDown setting
    cell:SetAttribute("type", "macro")
    cell:SetAttribute("macrotext", left)
    cell:SetAttribute("type2", "macro")
    cell:SetAttribute("macrotext2", right)
    cell:SetAttribute("type3", "worldmarker")
    if world then
        cell:SetAttribute("action3", "set")
        cell:SetAttribute("marker3", world)
    else
        cell:SetAttribute("action3", "clear") -- no marker: ClearRaidMarker(nil) clears them all, as the raid frame does
    end
    cell.marker = marker
    cell:SetScript("PostClick", function(self, mouseButton, down)
        if not down then
            if mouseButton == "MiddleButton" then
                ns.SafeCall(function() afterGroundClick(self) end)
            end
            ns.SafeCall(close)
        end
    end)

    local icon = cell:CreateTexture(nil, "ARTWORK")
    if marker == 0 then
        icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up") -- the red "no" sign
        icon:SetPoint("TOPLEFT", cell, "TOPLEFT", 4, -4)
        icon:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -4, 4)
    else
        icon:SetTexture(MARKER_TEXTURE .. marker)
        icon:SetAllPoints(cell)
    end
    cell:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    return cell
end

-- A cell's left and right macros, and its world marker (nil = the middle cell). "!": picking the marker
-- the target already has leaves it on.
local function actionsFor(marker)
    local world = WORLD_INDEX[marker]
    if not world then -- the middle cell
        return "/tm 0", "/tm 0\n" .. CLEAR_ALL_GROUND, nil
    end
    return "/tm !" .. marker, "/tm 0\n/cwm " .. world, world
end

-- Pings were switched off in the game's options? (the "enablePings" setting; unknown = not off)
local function pingsOff()
    if type(GetCVarBool) ~= "function" then
        return false
    end
    local answer = ns.Readable(GetCVarBool, "enablePings")
    return answer ~= nil and answer[1] == false
end

-- The ping row: Blizzard's own "/ping" (Blizzard_PingManager's SendMacroPing) at your target, or - with no
-- target - "@cursor", which the ping system documents as passing through all UI to the ground beneath.
local function makePing(index, ping, size)
    local button = CreateFrame("Button", "AKForeverTargeterMenuPing" .. index, menu, "SecureActionButtonTemplate")
    button:SetSize(size, size)
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", "/ping [@target,exists] " .. ping.word .. "; [@cursor] " .. ping.word)
    button.ping = ping.word
    button:SetScript("PostClick", function(_, _, down)
        if not down then
            MarkerMenu.work.pings = (MarkerMenu.work.pings or 0) + 1
            if pingsOff() then
                ns:Print("pings are switched off in the game's options (Options > Gameplay > Pings).")
            end
            ns.SafeCall(close)
        end
    end)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    local atlas = "Ping_Marker_Icon_" .. ping.kit
    local known = type(C_Texture) == "table" and type(C_Texture.GetAtlasInfo) == "function"
        and C_Texture.GetAtlasInfo(atlas)
    if known and type(icon.SetAtlas) == "function" then
        icon:SetAtlas(atlas)
    else -- a client without the ping art: a letter will do
        icon:SetColorTexture(0.2, 0.2, 0.25, 0.9)
        local letter = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        letter:SetPoint("CENTER", button, "CENTER", 0, 0)
        letter:SetText(string.sub(ping.label, 1, 1))
    end
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    -- our own tooltip (shared with the panel), never the game's
    button:SetScript("OnEnter", function(self)
        ns.SafeCall(function()
            local tip = ns.Tooltip and ns.Tooltip()
            if tip then
                tip:SetOwner(self, "ANCHOR_BOTTOM")
                tip:AddLine("Ping: " .. ping.label, 1, 0.82, 0)
                tip:AddLine("your target - or, with none, the ground under the mouse", 1, 1, 1)
                tip:Show()
            end
        end)
    end)
    button:SetScript("OnLeave", function()
        local tip = _G.AKForeverTargeterTooltip
        if tip then
            tip:Hide()
        end
    end)
    return button
end

local function build()
    menu = CreateFrame("Frame", "AKForeverTargeterMenu", UIParent)
    local side = CELL * 3 + GAP * 2 + PAD * 2
    local pingSize = (CELL * 3 + GAP * 2 - GAP * (#PINGS - 1)) / #PINGS
    menu:SetSize(side, side + GAP * 2 + pingSize)
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:Hide()

    local background = menu:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(menu)
    background:SetColorTexture(0.04, 0.04, 0.06, 0.88)

    for position, marker in ipairs(GRID) do
        local column, row = (position - 1) % 3, math.floor((position - 1) / 3)
        local cell = makeCell("AKForeverTargeterMenuCell" .. position, marker, actionsFor(marker))
        cell:SetPoint("TOPLEFT", menu, "TOPLEFT", PAD + column * (CELL + GAP), -(PAD + row * (CELL + GAP)))
        cell.world = WORLD_INDEX[marker]
        cells[position] = cell
    end
    -- the ping row under the grid
    for index, ping in ipairs(PINGS) do
        local button = makePing(index, ping, pingSize)
        button:SetPoint("TOPLEFT", menu, "TOPLEFT", PAD + (index - 1) * (pingSize + GAP), -(PAD + 3 * (CELL + GAP) + GAP))
        pings[index] = button
    end
    place(false)
    MarkerMenu.state = "ready"
    applyDriver()
end

-- The key binding (Bindings.xml): toggles the menu at the mouse, out of combat.
function AKForeverTargeter_ToggleMenu()
    if not menu then
        return
    end
    if InCombatLockdown() then
        if not hintedThisFight then
            hintedThisFight = true
            local name = modifier()
            ns:Print(name and ("in combat: hold " .. string.upper(name) .. " for the marker menu.")
                or "in combat the marker menu cannot be opened (set a modifier: /akt menu mod alt-shift).")
        end
        return
    end
    if menu:IsShown() then
        close()
    else
        open()
    end
end

function MarkerMenu:Describe()
    local bound
    if type(GetBindingKey) == "function" then
        local answer = ns.Readable(GetBindingKey, MarkerMenu.BINDING)
        bound = answer and answer[1] or nil
    end
    local spot = ns.cdb and ns.cdb.options and ns.cdb.options.menuSpot
    return {
        state = MarkerMenu.state,
        modifier = modifier() or "off",
        sticky = sticky(),
        driver = menu and menu.driver or "none",
        boundTo = bound or "no key yet",
        shown = menu and menu:IsShown() or false,
        cells = #cells,
        pings = #pings,
        pingsOff = pingsOff(),
        -- does this client run world markers at all? (Blizzard's raid frame asks the same before it offers them)
        groundMarkers = type(IsRaidMarkerSystemEnabled) ~= "function" and "unknown"
            or (ns.Readable(IsRaidMarkerSystemEnabled) or {})[1] and "on" or "off",
        spot = type(spot) == "table" and (tostring(spot.x) .. ", " .. tostring(spot.y)) or "centre",
        work = MarkerMenu.work,
    }
end

ns:Listen("LOGIN", function()
    if InCombatLockdown() then
        MarkerMenu.state = "waiting for the fight to end (logged in during combat)"
        return
    end
    build()
end)

ns:Listen("COMBAT_END", function()
    hintedThisFight = false
    if not menu then
        build()
        return
    end
    if driverPending then
        applyDriver()
    end
    -- the driver hid the menu as the fight ended; leave nothing of its state behind
    if not menu:IsShown() then
        menu:SetAttribute("statehidden", nil)
    end
end)

-- Out of combat the modifier opens the menu. It opens when the WHOLE combination is held, and - unless
-- 'sticky off' - it is NOT closed when the keys go: a stray key-up (Ctrl and Shift get those from the
-- game's own click handling, Alt does not) would otherwise take the menu away mid-hold.
ns:On("MODIFIER_STATE_CHANGED", function(_, key, down)
    local name = modifier()
    if not menu or not name or ns.AnySecret(key, down) or InCombatLockdown() then
        return
    end
    local ours = false
    for _, part in ipairs(MODIFIERS[name]) do
        if MODIFIER_KEYS[part][key] then
            ours = true
        end
    end
    if not ours then
        return
    end
    if heldNow() then
        open()
    elseif menu:IsShown() then
        if sticky() then
            MarkerMenu.work.keptOpen = MarkerMenu.work.keptOpen + 1 -- it stays: a stray key-up costs nothing
        else
            close()
        end
    end
end)

-- out of combat a click anywhere else closes it
ns:On("GLOBAL_MOUSE_DOWN", function()
    if not menu or InCombatLockdown() or not menu:IsShown() then
        return
    end
    if not sticky() and anyModifierHeld() then
        return -- held open: the click is meant for a cell
    end
    if type(menu.IsMouseOver) == "function" and menu:IsMouseOver() then
        return
    end
    close()
end)

ns:Listen("OPTION_CHANGED", function(_, key)
    if key == "menuModifier" then
        applyDriver()
    end
end)

local function modifierList()
    return table.concat(MODIFIER_ORDER, " | ")
end

ns:RegisterCommand("menu", "the marker menu: '/akt menu mod alt-shift' (hold it to open; " .. modifierList()
    .. "), '/akt menu sticky on|off', '/akt menu spot' (its place in combat = the mouse now), '/akt menu spot reset'", function(rest)
    local word, value = string.match(string.lower(rest or ""), "^(%a*)%s*([%a%-]*)")
    if word == "mod" then
        if MODIFIERS[value] or value == "off" then
            ns:SetOption("menuModifier", value)
            ns:Print("hold " .. (value == "off" and "nothing - the marker menu opens by its key only"
                or (string.upper(value) .. " for the marker menu")) .. ".")
        else
            ns:Print("usage: /akt menu mod " .. modifierList())
        end
        return
    elseif word == "sticky" then
        if value == "on" or value == "off" then
            ns:SetOption("menuSticky", value == "on")
        end
        ns:Print(sticky() and "out of combat the menu stays open until you pick a marker or click elsewhere."
            or "out of combat the menu goes the moment you let the keys go.")
        return
    elseif word == "spot" then
        if InCombatLockdown() then
            ns:Print("not in combat.")
            return
        end
        if value == "reset" then
            ns.cdb.options.menuSpot = nil
            ns:Print("the marker menu's combat spot is the screen's centre again.")
        elseif menu and type(GetCursorPosition) == "function" then
            local x, y = GetCursorPosition()
            local scale = menu:GetEffectiveScale()
            ns.cdb.options.menuSpot = { x = math.floor(x / scale + 0.5), y = math.floor(y / scale + 0.5) }
            ns:Print("in combat the marker menu appears where the mouse is now.")
        end
        place(false)
        return
    end
    local info = MarkerMenu:Describe()
    ns:Print("marker menu: " .. info.state .. ". Hold " .. (info.modifier == "off" and "(no modifier)" or string.upper(info.modifier))
        .. " to open it at the mouse; out of combat it "
        .. (info.sticky and "stays until you pick or click elsewhere" or "goes when you let the keys go")
        .. ", in combat it is there while you hold them, at its spot (" .. info.spot .. "). Key: "
        .. tostring(info.boundTo) .. " (out of combat). Left-click a cell: over your target's head. Middle-click: on the ground "
        .. "(then click the ground). Right-click: clears both. The row underneath pings your target "
        .. "(attack, warning, on my way, assist) - with no target, the ground under the mouse"
        .. (info.pingsOff and " - but pings are switched off in the game's options." or "."))
    local blocker = MarkerMenu.GroundBlocker()
    ns:Print("ground markers: " .. info.groundMarkers .. " on this client - "
        .. (blocker or "nothing stands in the way right now (middle-click a cell)."))
end)

MarkerMenu.NAMES = NAMES
