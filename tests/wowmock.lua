-- Strict stand-in for the WoW client, enough to run AKForeverTargeter under a plain Lua interpreter.
-- Same design as the other addons' mocks. What it models of Blizzard's side:
--
--  * the quest log as the addon reads it: C_QuestLog.GetNumQuestWatches / GetQuestIDForQuestWatchIndex /
--    GetTitleForQuestID / GetQuestObjectives / ReadyForTurnIn / GetLogIndexForQuestID /
--    UnitIsRelatedToActiveQuest, GetQuestLogCompletionText - and its events;
--  * units and their tooltips (C_TooltipInfo.GetUnit), the mobs around the player, the target, raid markers -
--    and the four macro commands the rows use, as we UNDERSTAND them: /cleartarget, /targetexact,
--    /tm [exists,nodead] !N, /targetlasttarget [noexists]. Passing tests prove the logic, not the assumptions;
--  * taint: a field written onto one of Blizzard's frames, a script set or hooked on one - recorded, and
--    the test runner fails the scenario;
--  * combat: a protected frame of ours (a secure template) - and any frame of ours that has one as a child -
--    may not be shown, hidden, moved, sized, re-parented or given attributes by addon code. The real client
--    blocks such a call; here it is recorded and fails the scenario. A protected frame may not be anchored
--    to a frame that is not protected itself (the client's rule, seen in game on 2026-09-21);
--  * NO secure snippets: this beta compiles none (RestrictedExecution.lua:79, loadstring_untainted = nil -
--    seen in the user's own trace), so a SecureHandler template cannot even be created here. What the beta
--    does offer is modelled instead: state drivers ("[mod:alt] show; hide", run by Blizzard's secure code
--    on MODIFIER_STATE_CHANGED), the modifier keys, the cursor, and one-shot C_Timer.After callbacks that
--    Mock.nextFrame() runs;
--  * secret values: chosen API answers can be made secret.
--
-- Not loaded by the game (not in the .toc).
local Mock = {}

local REAL_PRINT = print
local ADDON = "AKForeverTargeter"

Mock.SECRET = setmetatable({}, { __tostring = function() return "<SECRET>" end })

------------------------------------------------------------------------
-- Widgets
------------------------------------------------------------------------
local methods = {}
local newWidget

local function violation(text)
    Mock.taintViolations[#Mock.taintViolations + 1] = text
end

local function hasProtectedChild(frame)
    for _, child in ipairs(frame.__children) do
        if child.__protected or hasProtectedChild(child) then
            return true
        end
    end
    return false
end

local function isProtected(frame)
    return frame.__protected or hasProtectedChild(frame)
end

-- a call that CHANGES a frame
local function guard(self, what)
    if Mock.blizzardCode then
        return
    end
    if self.__blizzard then
        violation("addon code called " .. what .. "() on Blizzard's " .. tostring(self.__name))
    elseif Mock.state.inCombat and isProtected(self) then
        Mock.forbiddenCalls[#Mock.forbiddenCalls + 1] = what .. "() on protected " .. tostring(self.__name) .. " in combat"
    end
    if isProtected(self) then
        Mock.protectedWrites = Mock.protectedWrites + 1
    end
end

function methods.GetObjectType(self) return self.__kind end
function methods.SetSize(self, width, height) guard(self, "SetSize"); self.__width, self.__height = width, height end
function methods.SetWidth(self, width) guard(self, "SetWidth"); self.__width = width end
function methods.SetHeight(self, height) guard(self, "SetHeight"); self.__height = height end
function methods.GetWidth(self) return self.__width or 0 end
function methods.GetHeight(self) return self.__height or 0 end
function methods.SetPoint(self, point, relativeTo, relativePoint, x, y)
    guard(self, "SetPoint")
    if type(relativeTo) == "number" then -- SetPoint(point, x, y)
        relativeTo, relativePoint, x, y = self.__parent, point, relativeTo, relativePoint
    end
    -- (relativeTo nil with a relative point: the screen)
    if isProtected(self) and type(relativeTo) == "table" and not Mock.blizzardCode and not isProtected(relativeTo) then
        error("Action[SetPoint] failed because[Cannot anchor protected frames to regions]: attempted from: "
            .. tostring(self.__name) .. ":SetPoint.", 2)
    end
    self.__points[#self.__points + 1] = { point, relativeTo, relativePoint or point, x or 0, y or 0 }
end
function methods.ClearAllPoints(self) guard(self, "ClearAllPoints"); self.__points = {} end
function methods.SetAllPoints(self, target) self.__allPoints = target or self.__parent end
function methods.GetPoint(self, index)
    local point = self.__points[index or 1]
    if point then
        return point[1], point[2], point[3], point[4], point[5]
    end
end
function methods.GetNumPoints(self) return #self.__points end
function methods.Show(self) guard(self, "Show"); self.__shown = true end
function methods.Hide(self) guard(self, "Hide"); self.__shown = false end
function methods.SetShown(self, shown) guard(self, "SetShown"); self.__shown = shown and true or false end
function methods.IsShown(self) return self.__shown end
function methods.IsVisible(self)
    local frame = self
    while frame do
        if not frame.__shown then
            return false
        end
        frame = frame.__parent
    end
    return true
end
function methods.SetAlpha(self, alpha) self.__alpha = alpha end -- (not protected)
function methods.GetAlpha(self) return self.__alpha or 1 end
function methods.SetParent(self, parent) guard(self, "SetParent"); self.__parent = parent end
function methods.GetParent(self) return self.__parent end
function methods.GetName(self) return self.__name end
function methods.SetFrameStrata(self, strata) guard(self, "SetFrameStrata"); self.__strata = strata end
function methods.GetFrameStrata(self) return self.__strata or "MEDIUM" end
function methods.SetFrameLevel(self, level) guard(self, "SetFrameLevel"); self.__level = level end
function methods.GetFrameLevel(self) return self.__level or 1 end
function methods.SetClampedToScreen(self, clamped) guard(self, "SetClampedToScreen"); self.__clamped = clamped end
function methods.SetMovable(self, movable) guard(self, "SetMovable"); self.__movable = movable end
function methods.RegisterForDrag(self, ...) self.__drag = { ... } end
function methods.StartMoving(self) guard(self, "StartMoving"); assert(self.__movable, "StartMoving on a frame that is not movable"); self.__moving = true end
function methods.StopMovingOrSizing(self) guard(self, "StopMovingOrSizing"); self.__moving = nil end
function methods.SetUserPlaced(self, placed) guard(self, "SetUserPlaced"); self.__userPlaced = placed end
function methods.EnableMouse(self, enabled) guard(self, "EnableMouse"); self.__mouse = enabled and true or false end
function methods.IsMouseOver(self) return Mock.state.mouseOver == self end
function methods.GetEffectiveScale(self) return self.__effectiveScale or (self.__parent and self.__parent:GetEffectiveScale()) or 1 end
function methods.SetScale(self, scale) guard(self, "SetScale"); self.__scale = scale end
function methods.GetScale(self) return self.__scale or 1 end
function methods.IsProtected(self)
    local explicit = self.__protected and true or false
    return explicit or hasProtectedChild(self), explicit
end
function methods.SetAttribute(self, key, value)
    guard(self, "SetAttribute")
    self.__attributes[key] = value
end
function methods.GetAttribute(self, key) return self.__attributes[key] end
function methods.RegisterForClicks(self, ...) self.__clicks = { ... } end
function methods.SetScript(self, name, fn)
    if self.__blizzard and not Mock.blizzardCode then
        violation("addon code set a script on Blizzard's " .. tostring(self.__name))
    end
    self.__scripts[name] = fn
end
function methods.HookScript(self, name)
    if self.__blizzard and not Mock.blizzardCode then
        violation("addon code hooked a script on Blizzard's " .. tostring(self.__name))
    end
end
function methods.GetScript(self, name) return self.__scripts[name] end
function methods.RegisterEvent(self, event)
    if Mock.unknownEvents[event] then
        error("Attempt to register unknown event \"" .. event .. "\"")
    end
    self.__events[event] = true
end
function methods.UnregisterEvent(self, event) self.__events[event] = nil end
function methods.CreateTexture(self) return newWidget("Texture", nil, self) end
function methods.CreateFontString(self) return newWidget("FontString", nil, self) end
function methods.SetText(self, text) self.__text = text end
function methods.GetText(self) return self.__text end
function methods.SetTexture(self, texture) self.__texture, self.__atlas = texture, nil end
function methods.GetTexture(self) return self.__texture end
function methods.SetAtlas(self, atlas) self.__atlas, self.__texture = atlas, nil end
function methods.SetTexCoord(self, ...) self.__texCoord = { ... } end
function methods.SetColorTexture(self, r, g, b, a) self.__color = { r, g, b, a } end
function methods.SetHighlightTexture(self, texture) self.__highlight = texture end
function methods.SetJustifyH(self, justify) self.__justify = justify end
function methods.SetTextColor(self, r, g, b) self.__textColor = { r, g, b } end
function methods.SetWordWrap(self, wrap) self.__wordWrap = wrap end
-- BackdropTemplate: Blizzard's mixin puts these on a frame made WITH the template, and on no other -
-- which is what the addon's "does this frame have SetBackdrop?" check relies on.
local backdropMethods = {
    SetBackdrop = function(self, spec) self.__backdrop = spec end,
    SetBackdropColor = function(self, r, g, b, a) self.__backdropColor = { r, g, b, a } end,
    SetBackdropBorderColor = function(self, r, g, b, a) self.__backdropBorderColor = { r, g, b, a } end,
}
-- tooltips (our own one)
function methods.SetOwner(self, owner, anchor) self.__owner, self.__lines = owner, {} end
function methods.AddLine(self, text) self.__lines[#self.__lines + 1] = text end

local widgetMeta = { __index = methods }

function newWidget(kind, name, parent, template)
    local widget = setmetatable({
        __kind = kind, __name = name, __parent = parent, __template = template, __scripts = {}, __events = {},
        __points = {}, __attributes = {}, __children = {}, __shown = true,
    }, widgetMeta)
    if template == "BackdropTemplate" then
        for name, fn in pairs(backdropMethods) do
            rawset(widget, name, fn)
        end
    end
    if type(template) == "string" and template:find("Secure", 1, true) then
        assert(not template:find("SecureHandler", 1, true),
            "RestrictedExecution.lua:79: attempt to call a nil value (upvalue 'loadstring_untainted') - this beta compiles no secure snippets")
        widget.__protected = true
    end
    if parent then
        parent.__children[#parent.__children + 1] = widget
    end
    Mock.frames[#Mock.frames + 1] = widget
    return widget
end

-- One of BLIZZARD's frames: a field written onto it by addon code is how taint spreads.
local function newBlizzardFrame(kind, name, parent)
    local frame = newWidget(kind, name, parent)
    frame.__blizzard = true
    return setmetatable(frame, {
        __index = methods,
        __newindex = function(self, key, value)
            if not Mock.blizzardCode and not (type(key) == "string" and key:sub(1, 2) == "__") then
                violation("wrote field '" .. tostring(key) .. "' on Blizzard's " .. tostring(name))
            end
            rawset(self, key, value)
        end,
    })
end

-- Runs fn as Blizzard's own (secure) code.
function Mock.asBlizzard(fn, ...)
    local before = Mock.blizzardCode
    Mock.blizzardCode = true
    local results = table.pack(pcall(fn, ...))
    Mock.blizzardCode = before
    if not results[1] then
        error(results[2], 0)
    end
    return table.unpack(results, 2, results.n)
end

function Mock.runScript(widget, name, ...)
    local script = widget.__scripts[name]
    if script then
        script(widget, ...)
    end
end

------------------------------------------------------------------------
-- Clicks, modifiers, state drivers, the cursor, one-shot timers, dragging
------------------------------------------------------------------------
-- A hardware click on one of our secure buttons: the secure action (the macro) on the press or on the
-- release, and the addon's PostClick after each.
function Mock.click(button, mouseButton)
    mouseButton = mouseButton or "LeftButton"
    assert(button.__protected, "Mock.click is for secure buttons")
    assert(button:IsVisible(), "the button is not visible: " .. tostring(button.__name))
    local ranAction = false
    for _, down in ipairs({ true, false }) do
        if not button:IsVisible() then
            break -- hidden by its own press: the release never reaches it
        end
        if down == Mock.state.useKeyDown and not ranAction then
            ranAction = true
            -- (SecureButton_GetModifiedAttribute: "type2" is the right button's, "type" everybody's; "" = ATTRIBUTE_NOOP)
            local suffix = mouseButton == "RightButton" and "2" or "1"
            local kind = button.__attributes["type" .. suffix]
            if kind == nil then
                kind = button.__attributes.type
            end
            if kind == "macro" then
                Mock.runMacro(button.__attributes["macrotext" .. suffix] or button.__attributes.macrotext)
            elseif kind ~= "" and kind ~= nil then
                error("secure action the mock does not know: " .. tostring(kind))
            end
        end
        Mock.runScript(button, "PostClick", mouseButton, down)
    end
end

-- A right-click, with or without Shift held.
function Mock.rightClick(button, shift)
    Mock.state.modifiers.shift = shift and true or nil
    Mock.click(button, "RightButton")
    Mock.state.modifiers.shift = nil
end

-- Blizzard's SecureCmdOptionParse, as far as our conditions go: the first clause whose conditions all
-- hold gives its value; none matching gives nil (and the state driver then does nothing at all).
local function parseOptions(text)
    for clause in text:gmatch("[^;]+") do
        local conditions, value = clause:match("^%s*%[(.-)%]%s*(.-)%s*$")
        if not conditions then
            conditions, value = "", clause:match("^%s*(.-)%s*$")
        end
        local pass = true
        for condition in conditions:gmatch("[^,]+") do
            condition = condition:match("^%s*(.-)%s*$")
            if condition == "combat" then
                pass = pass and Mock.state.inCombat
            elseif condition == "nocombat" then
                pass = pass and not Mock.state.inCombat
            else
                local name = condition:match("^mod:(%a+)$") or condition:match("^modifier:(%a+)$")
                assert(name, "macro condition the mock does not know: " .. condition)
                pass = pass and (Mock.state.modifiers[name] and true or false)
            end
        end
        if pass and value ~= "" then
            return value
        end
    end
    return nil
end

-- Blizzard's secure state-driver manager: on a modifier change (and on entering / leaving combat) it
-- evaluates every visibility driver and shows / hides the frame from ITS code - in combat too.
function Mock.applyDrivers()
    for _, driver in ipairs(Mock.stateDrivers) do
        if driver.state == "visibility" then
            local value = parseOptions(driver.conditions)
            if value then
                assert(value == "show" or value == "hide", "state-visibility value the mock does not know: " .. value)
                Mock.asBlizzard(function()
                    if value == "show" then
                        driver.frame:Show()
                        driver.frame.__attributes.statehidden = nil
                    else
                        driver.frame:Hide()
                        driver.frame.__attributes.statehidden = true
                    end
                end)
            end
        end
    end
end

-- A modifier key goes down (or up): the addons hear MODIFIER_STATE_CHANGED first, the driver manager acts
-- on its next update.
function Mock.setModifier(name, down)
    Mock.state.modifiers[name] = down or nil
    Mock.fire("MODIFIER_STATE_CHANGED", "L" .. string.upper(name), down and 1 or 0)
    Mock.applyDrivers()
end

function Mock.cursor(x, y)
    Mock.state.cursor = { x, y }
end

-- The next frame: every C_Timer.After(0, ...) that was booked runs (what it books runs a frame later).
function Mock.nextFrame()
    local due = Mock.timers
    Mock.timers = {}
    for _, fn in ipairs(due) do
        fn()
    end
end

-- The panel is dragged and dropped: the client leaves a moved frame anchored to the screen where it was
-- dropped, then runs OnDragStop.
function Mock.dragPanel(x, y)
    local panel = assert(_G.AKForeverTargeterPanel, "no panel to drag")
    Mock.runScript(panel, "OnDragStart", "LeftButton")
    if panel.__moving then
        panel.__points = { { "TOPLEFT", _G.UIParent, "BOTTOMLEFT", x, y } }
    end
    Mock.runScript(panel, "OnDragStop")
end

------------------------------------------------------------------------
-- The world: mobs around the player, the target, markers - and the macro commands as we understand them
------------------------------------------------------------------------
local function findMob(name)
    for _, mob in ipairs(Mock.state.mobs) do
        if mob.name == name then
            return mob
        end
    end
end

function Mock.runMacro(text)
    assert(type(text) == "string" and #text <= 1023, "macrotext missing or too long")
    local state = Mock.state
    for line in text:gmatch("[^\n]+") do
        local command, rest = line:match("^(/%a+)%s*(.*)$")
        assert(command, "not a macro line: " .. line)
        local conditions, argument = rest:match("^%[(.-)%]%s*(.*)$")
        if not conditions then
            conditions, argument = "", rest
        end
        local pass = true
        for condition in conditions:gmatch("[^,]+") do
            if condition == "exists" then pass = pass and state.target ~= nil
            elseif condition == "noexists" then pass = pass and state.target == nil
            elseif condition == "nodead" then pass = pass and not (state.target and state.target.dead)
            elseif condition == "dead" then pass = pass and (state.target and state.target.dead) and true or false
            else error("macro condition the mock does not know: " .. condition) end
        end
        if pass then
            if command == "/cleartarget" then
                if state.target then
                    state.lastTarget, state.target = state.target, nil
                end
            elseif command == "/targetexact" then
                local mob = findMob(argument)
                if mob then
                    if state.target and state.target ~= mob then
                        state.lastTarget = state.target
                    end
                    state.target = mob
                end
            elseif command == "/targetlasttarget" then
                state.target, state.lastTarget = state.lastTarget, state.target
            elseif command == "/tm" then
                local prefix, index = argument:match("^([!~]?)(%d+)$")
                assert(index, "bad /tm argument: " .. argument)
                index = tonumber(index)
                if state.target then
                    if index == 0 then
                        state.target.marker = nil
                    elseif prefix == "!" and state.target.marker == index then
                        -- stays
                    elseif prefix == "~" and state.target.marker ~= nil then
                        -- "~": only a unit without any marker gets one
                    elseif prefix == "" and state.target.marker == index then
                        state.target.marker = nil -- plain /tm toggles
                    else
                        for _, mob in ipairs(state.mobs) do
                            if mob.marker == index then
                                mob.marker = nil -- a marker is on one unit at a time
                            end
                        end
                        state.target.marker = index
                    end
                end
            else
                error("macro command the mock does not know: " .. command)
            end
        end
    end
end

------------------------------------------------------------------------
-- Events, combat, the quest log's own moments
------------------------------------------------------------------------
function Mock.fire(event, ...)
    for _, frame in ipairs(Mock.frames) do
        if frame.__events[event] and frame.__scripts.OnEvent then
            frame.__scripts.OnEvent(frame, event, ...)
        end
    end
end

function Mock.setCombat(inCombat)
    Mock.state.inCombat = inCombat
    if inCombat then
        Mock.applyDrivers() -- the manager sees [combat] flip before the addons hear the event
        Mock.fire("PLAYER_REGEN_DISABLED")
    else
        Mock.fire("PLAYER_REGEN_ENABLED")
        Mock.applyDrivers()
    end
end

-- Something in the quest log changed (a kill counted, an objective finished): the game says so, and the
-- next frame comes.
function Mock.questLogChanged()
    Mock.fire("QUEST_LOG_UPDATE")
    Mock.fire("UNIT_QUEST_LOG_CHANGED", "player")
    Mock.nextFrame()
end

-- This quest's business is on another map (1413 = the Barrens, say), or back on yours.
function Mock.setElsewhere(questID, elsewhere)
    Mock.state.quests[questID].map = elsewhere and 1413 or nil
    Mock.fire("ZONE_CHANGED_NEW_AREA")
    Mock.nextFrame()
end

-- You walked into another zone.
function Mock.setPlayerMap(uiMapID)
    Mock.state.playerMap = uiMapID
    Mock.fire("ZONE_CHANGED_NEW_AREA")
    Mock.nextFrame()
end

-- The tracker's list of quests changed (tracked, untracked).
function Mock.watchListChanged()
    Mock.fire("QUEST_WATCH_LIST_CHANGED")
    Mock.fire("QUEST_LOG_UPDATE")
    Mock.nextFrame()
end

-- The quest giver's dialog: the quest is accepted with the NPC in front of the player.
function Mock.acceptQuest(questID, npcName)
    Mock.state.units.questnpc = npcName and { name = npcName } or nil
    Mock.fire("QUEST_ACCEPTED", questID)
    Mock.state.units.questnpc = nil
    Mock.nextFrame()
end

-- You opened a quest dialog at an NPC: the offer page, the "have you got it" page, or the turn-in.
function Mock.questDialog(event, questID, npcName)
    Mock.state.units.questnpc = npcName and { name = npcName } or nil
    Mock.state.dialogQuest = questID
    Mock.fire(event)
    Mock.state.units.questnpc, Mock.state.dialogQuest = nil, nil
    Mock.nextFrame()
end

------------------------------------------------------------------------
-- Install globals + load the addon in .toc order
------------------------------------------------------------------------
local function readToc(root)
    local files = {}
    for line in io.lines(root .. "/" .. ADDON .. ".toc") do
        line = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and line:sub(1, 1) ~= "#" then
            files[#files + 1] = (line:gsub("\\", "/"))
        end
    end
    return files
end

function Mock.install(options)
    options = options or {}
    Mock.frames = {}
    Mock.taintViolations = {}
    Mock.forbiddenCalls = {}
    Mock.protectedWrites = 0
    Mock.printed = {}
    Mock.errors = {}
    Mock.timers = {}
    Mock.stateDrivers = {}
    Mock.blizzardCode = false
    Mock.unknownEvents = options.unknownEvents or {}
    Mock.now = 1000
    Mock.state = {
        inCombat = false,
        useKeyDown = options.useKeyDown ~= false,
        playerName = "Purrdee",
        watched = {},        -- quest ids in the tracker, in order
        quests = {},         -- [questID] = { title, objectives = { { text, type, finished, fulfilled, required } }, complete, completionText }
        units = {},          -- [unitToken] = { name, isPlayer, related, tooltip = { { type, leftText } } }
        mobs = {},           -- around the player: { name, dead, marker }
        target = nil, lastTarget = nil,
        secretApis = {},
        mouseOver = nil,
        bindings = { AKFOREVERTARGETER_MENU = options.bindingKey, ["CLICK AKForeverTargeterAnyButton:LeftButton"] = options.anyKey },
        modifiers = {},
        cursor = { 800, 450 },
        playerMap = options.playerMap or 1411, -- Durotar, say
        homeMap = options.playerMap or 1411,   -- where a quest without a map of its own has its business
    }
    local state = Mock.state

    for name in pairs(Mock.globals or {}) do
        _G[name] = nil -- a fresh client: nothing of the last scenario's is left
    end
    local G = {}
    local function global(name, value)
        G[name] = value
        _G[name] = value
    end
    Mock.globals = G

    global("print", function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[i] = tostring((select(i, ...)))
        end
        Mock.printed[#Mock.printed + 1] = table.concat(parts, " ")
    end)
    global("issecretvalue", function(value) return value == Mock.SECRET end)
    global("geterrorhandler", function()
        return function(err) Mock.errors[#Mock.errors + 1] = tostring(err) end
    end)
    global("GetTime", function() return Mock.now end)
    global("debugprofilestop", function() return Mock.now * 1000 end)
    global("date", function() return "2026-09-21 12:00:00" end)
    global("GetBuildInfo", function() return "1.60.1", "69913", "Sep 17 2026", 16001 end)
    global("InCombatLockdown", function() return state.inCombat end)
    global("UnitFullName", function() return state.playerName, "TestRealm" end)
    global("GetRealmName", function() return "Test Realm" end)
    global("IsInGroup", function() return false end)
    global("GetBindingKey", function(command) return state.bindings[command] end)
    global("GetCursorPosition", function() return state.cursor[1], state.cursor[2] end)
    global("IsModifierKeyDown", function() return next(state.modifiers) ~= nil end)
    global("IsAltKeyDown", function() return state.modifiers.alt and true or false end)
    global("IsControlKeyDown", function() return state.modifiers.ctrl and true or false end)
    global("IsShiftKeyDown", function() return state.modifiers.shift and true or false end)
    global("C_Timer", { After = function(delay, fn)
        assert(delay == 0, "the addon runs nothing on a timer: only a next-frame check is allowed")
        Mock.timers[#Mock.timers + 1] = fn
    end })
    global("C_Texture", { GetAtlasInfo = function(name) return name == "QuestTurnin" and { width = 16, height = 16 } or nil end })
    -- a corner of the real map tree: Orgrimmar sits in Durotar, which sits on Kalimdor
    local MAPS = {
        [1454] = { mapID = 1454, name = "Orgrimmar", mapType = 3, parentMapID = 1411 },
        [1411] = { mapID = 1411, name = "Durotar", mapType = 3, parentMapID = 12 },
        [1413] = { mapID = 1413, name = "Northern Barrens", mapType = 3, parentMapID = 12 },
        [12] = { mapID = 12, name = "Kalimdor", mapType = 2, parentMapID = 947 },
    }
    global("C_Map", { GetMapInfo = function(uiMapID)
        if state.secretApis.mapInfo then
            return Mock.SECRET
        end
        return MAPS[uiMapID]
    end, GetBestMapForUnit = function()
        if state.secretApis.playerMap then
            return Mock.SECRET
        end
        return state.playerMap
    end })
    global("SlashCmdList", {})
    global("C_AddOns", { GetAddOnMetadata = function() return options.version or "0.1.0-test" end })
    global("QUEST_MONSTERS_KILLED", options.killFormat or "%s slain: %d/%d")
    global("Enum", { TooltipDataLineType = { QuestObjective = 8, QuestTitle = 17, QuestPlayer = 18, UnitName = 2 } })

    local uiParent = newBlizzardFrame("Frame", "UIParent")
    global("UIParent", uiParent)
    global("BackdropTemplateMixin", (not options.noBackdropTemplate) and {} or nil) -- the client offers the template, unless a scenario says not
    global("CreateFrame", function(kind, name, parent, template)
        assert(kind == "Frame" or kind == "Button" or kind == "GameTooltip", "CreateFrame kind the mock does not know: " .. tostring(kind))
        local frame = newWidget(kind, name, parent, template)
        if name then
            global(name, frame)
        end
        return frame
    end)

    global("hooksecurefunc", function(tableOrName, nameOrHook, maybeHook)
        local container, name, hook = _G, tableOrName, nameOrHook
        if type(tableOrName) == "table" then
            container, name, hook = tableOrName, nameOrHook, maybeHook
        end
        local original = rawget(container, name) or container[name]
        assert(type(original) == "function", "hooksecurefunc: no function " .. tostring(name))
        rawset(container, name, function(...)
            local results = table.pack(original(...))
            local before = Mock.blizzardCode
            Mock.blizzardCode = false -- the hook runs as addon code
            local ok, err = pcall(hook, ...)
            Mock.blizzardCode = before
            if not ok then
                error(err, 0)
            end
            return table.unpack(results, 1, results.n)
        end)
    end)

    -- Blizzard's state drivers
    global("RegisterStateDriver", function(frame, stateName, conditions)
        if state.inCombat and not Mock.blizzardCode then
            Mock.forbiddenCalls[#Mock.forbiddenCalls + 1] = "RegisterStateDriver() in combat"
        end
        for index = #Mock.stateDrivers, 1, -1 do
            if Mock.stateDrivers[index].frame == frame and Mock.stateDrivers[index].state == stateName then
                table.remove(Mock.stateDrivers, index)
            end
        end
        Mock.stateDrivers[#Mock.stateDrivers + 1] = { frame = frame, state = stateName, conditions = conditions }
        Mock.applyDrivers()
    end)
    global("UnregisterStateDriver", function(frame, stateName)
        if state.inCombat and not Mock.blizzardCode then
            Mock.forbiddenCalls[#Mock.forbiddenCalls + 1] = "UnregisterStateDriver() in combat"
        end
        for index = #Mock.stateDrivers, 1, -1 do
            if Mock.stateDrivers[index].frame == frame and Mock.stateDrivers[index].state == stateName then
                table.remove(Mock.stateDrivers, index)
            end
        end
    end)

    -- units
    local function unitApi(name, read)
        global(name, function(unit)
            if state.secretApis[name] then
                return Mock.SECRET
            end
            return read(unit)
        end)
    end
    local function unitOf(token)
        if token == "player" then
            return { name = state.playerName, isPlayer = true }
        elseif token == "target" then
            return state.target or state.units.target
        end
        return state.units[token]
    end
    unitApi("UnitExists", function(unit) return unitOf(unit) ~= nil end)
    unitApi("UnitClassification", function(unit) local u = unitOf(unit) return u and u.classification or "normal" end)
    unitApi("UnitLevel", function(unit) local u = unitOf(unit) return u and u.level or 10 end)
    unitApi("UnitIsDeadOrGhost", function(unit) local u = unitOf(unit) return u and u.dead or false end)
    -- instances: state.instance = { mapID, name, kind = "party" | "raid" }, or nil out in the world
    global("IsInInstance", function()
        if state.secretApis.IsInInstance then
            return Mock.SECRET, Mock.SECRET
        end
        if state.instance then
            return true, state.instance.kind
        end
        return false, "none"
    end)
    global("GetInstanceInfo", function()
        if state.secretApis.GetInstanceInfo then
            return Mock.SECRET
        end
        local i = state.instance
        if not i then
            return "Durotar", "none", 0, "", 0, 0, false, 0, 0, 0
        end
        return i.name, i.kind, 1, "Normal", i.kind == "raid" and 40 or 5, 0, false, i.mapID, 5, 0
    end)
    function Mock.enterInstance(mapID, name, kind) -- nil: back out into the world
        state.instance = mapID and { mapID = mapID, name = name, kind = kind or "party" } or nil
        Mock.fire("PLAYER_ENTERING_WORLD", false, false)
    end
    unitApi("UnitName", function(unit) local u = unitOf(unit) return u and u.name or nil end)
    unitApi("UnitIsPlayer", function(unit) local u = unitOf(unit) return u and u.isPlayer or false end)
    global("GetRaidTargetIndex", function(unit)
        if state.secretApis.GetRaidTargetIndex then
            return Mock.SECRET
        end
        local u = unitOf(unit)
        return u and u.marker or nil
    end)
    global("C_TooltipInfo", { GetUnit = function(unit)
        local u = unitOf(unit)
        if not u then
            return nil
        end
        local lines = { { type = 2, leftText = u.name } }
        for _, line in ipairs(u.tooltip or {}) do
            lines[#lines + 1] = { type = line[1], leftText = state.secretApis.tooltipText and Mock.SECRET or line[2] }
        end
        return { lines = lines }
    end })

    -- the quest log
    if not options.noQuestLog then
        global("C_QuestLog", {
            GetNumQuestWatches = function() return #state.watched end,
            GetQuestIDForQuestWatchIndex = function(index) return state.watched[index] end,
            GetTitleForQuestID = function(questID) return state.quests[questID] and state.quests[questID].title end,
            GetLogIndexForQuestID = function(questID) return state.quests[questID] and questID or nil end, -- (log index = id here)
            GetInfo = function(logIndex)
                local quest = state.quests[logIndex]
                if not quest then
                    return nil
                end
                -- "on the map the client is SHOWING" - which is why this is not what decides a zone:
                -- standing in Durotar with Kalimdor on screen, a Barrens quest is "on map" too.
                return { title = quest.title, questID = logIndex, isOnMap = true, hasLocalPOI = false }
            end,
            -- which quests the client places on a given map
            GetQuestsOnMap = function(uiMapID)
                if state.secretApis.questsOnMap then
                    return Mock.SECRET
                end
                if state.noQuestsOnMap then
                    return nil
                end
                local list = {}
                for questID, quest in pairs(state.quests) do
                    -- a quest without a map of its own sits where you started, not wherever you walk
                    if (quest.map or state.homeMap) == uiMapID then
                        list[#list + 1] = { questID = questID, x = 0.5, y = 0.5 }
                    end
                end
                return list
            end,
            ReadyForTurnIn = function(questID)
                if state.secretApis.readyForTurnIn then
                    return Mock.SECRET
                end
                local quest = state.quests[questID]
                return quest and quest.complete or false
            end,
            GetQuestObjectives = function(questID)
                local quest = state.quests[questID]
                if not quest then
                    return nil
                end
                local list = {}
                for index, objective in ipairs(quest.objectives) do
                    list[index] = {
                        text = state.secretApis.objectiveText and Mock.SECRET or objective.text,
                        type = objective.type, finished = objective.finished and true or false,
                        numFulfilled = state.secretApis.numbers and Mock.SECRET or objective.fulfilled or 0,
                        numRequired = state.secretApis.numbers and Mock.SECRET or objective.required or 1,
                    }
                end
                return list
            end,
            UnitIsRelatedToActiveQuest = function(unit)
                local u = unitOf(unit)
                return u and u.related ~= false and (u.tooltip ~= nil) or false
            end,
        })
        -- the quest frame's own idea of which quest is on screen
    global("GetQuestID", function() return state.dialogQuest or 0 end)
    global("GetQuestLogCompletionText", function(logIndex)
            local quest = state.quests[logIndex]
            return quest and quest.completionText or nil
        end)
    end

    if options.db then
        global("AKForeverTargeterDB", options.db)
    else
        global("AKForeverTargeterDB", nil)
    end

    local ns = {}
    local root = options.root or "."
    for _, file in ipairs(readToc(root)) do
        local chunk = assert(loadfile(root .. "/" .. file))
        chunk(ADDON, ns)
    end
    Mock.ns = ns
    return ns, state
end

function Mock.login()
    Mock.fire("ADDON_LOADED", ADDON)
    Mock.fire("PLAYER_LOGIN")
end

Mock.realPrint = REAL_PRINT
return Mock
