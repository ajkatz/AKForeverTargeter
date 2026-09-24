-- Scenario tests for AKForeverTargeter:  lua tests/run.lua   (from the addon's folder)
-- Every scenario also fails when the addon raised a Lua error, wrote onto one of Blizzard's frames, or
-- touched a protected frame during combat.
package.path = "./tests/?.lua;" .. package.path
local Mock = require("wowmock")

local passed, failures = 0, {}

local function check(condition, message)
    if not condition then
        error((message or "check failed"), 2)
    end
end

local function equal(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "values differ", tostring(expected), tostring(actual)), 2)
    end
end

local function scenario(name, fn)
    local ok, err = pcall(fn)
    local problems = {}
    if not ok then
        problems[#problems + 1] = tostring(err)
    end
    for _, text in ipairs(Mock.errors or {}) do
        problems[#problems + 1] = "Lua error in the addon: " .. text
    end
    for _, text in ipairs(Mock.taintViolations or {}) do
        problems[#problems + 1] = "taint: " .. text
    end
    for _, text in ipairs(Mock.forbiddenCalls or {}) do
        problems[#problems + 1] = "blocked in combat: " .. text
    end
    if #problems == 0 then
        passed = passed + 1
        Mock.realPrint("  ok    " .. name)
    else
        failures[#failures + 1] = name
        Mock.realPrint("  FAIL  " .. name)
        for _, text in ipairs(problems) do
            Mock.realPrint("          " .. text)
        end
    end
end

------------------------------------------------------------------------
-- Fixtures
------------------------------------------------------------------------
local KOBOLDS, DUST, BANDANAS, TURNIN = 7, 47, 214, 300
local QUEST_TITLE, QUEST_OBJECTIVE, QUEST_PLAYER = 17, 8, 18

local function quests()
    return {
        [KOBOLDS] = { title = "Kobold Camp Cleanup", objectives = {
            { text = "Kobold Vermin slain: 3/10", type = "monster", fulfilled = 3, required = 10 },
            { text = "Kobold Worker slain: 0/8", type = "monster", fulfilled = 0, required = 8 },
        } },
        [DUST] = { title = "Gold Dust Exchange", objectives = {
            { text = "Gold Dust: 2/10", type = "item", fulfilled = 2, required = 10 },
        } },
        [BANDANAS] = { title = "Red Linen Goods", objectives = {
            { text = "Red Linen Bandana: 0/6", type = "item", fulfilled = 0, required = 6 },
        } },
        [TURNIN] = { title = "The Hunter's Way", objectives = {
            { text = "Flatland Prowler Claw: 4/4", type = "item", finished = true, fulfilled = 4, required = 4 },
        }, complete = true, completionText = "Speak with Holt Thunderhorn on Hunter Rise in Thunder Bluff." },
    }
end

local function start(options, setup)
    options = options or {}
    local ns, state = Mock.install(options)
    state.quests = quests()
    state.watched = { KOBOLDS }
    if setup then
        setup(state)
    end
    Mock.login()
    Mock.nextFrame()
    return ns, state
end

local function rowFor(ns, key)
    for _, entry in ipairs(ns.Panel:Describe().inUse) do
        if entry.key == key then
            return entry
        end
    end
end

-- Hold a marker-menu combination. Nothing sets one by default any more - the key you bound is what
-- opens the menu - so a scenario that wants a modifier asks for one first.
local function wantModifier()
    SlashCmdList.AKFOREVERTARGETER("menu mod alt-shift")
end

local function holdMenu(down)
    Mock.setModifier("alt", down)
    Mock.setModifier("shift", down)
end

local function frameFor(key)
    for index = 1, 40 do
        local frame = _G["AKForeverTargeterRow" .. index]
        if not frame then
            return nil
        end
        if frame.key == key then
            return frame
        end
    end
end

local function rowCount(ns)
    return #ns.Panel:Describe().inUse
end

------------------------------------------------------------------------
Mock.realPrint("AKForeverTargeter scenarios")

scenario("a kill objective names its mob - in the classic and in the modern wording, and in another language", function()
    local ns = start()
    local Quests = ns.Quests
    equal(Quests.MobFromText("Kobold Vermin slain: 3/10", "monster"), "Kobold Vermin")
    equal(Quests.MobFromText("3/10 Kobold Vermin slain", "monster"), "Kobold Vermin")
    equal(Quests.MobFromText("- Kobold Vermin slain: 3/10", "monster"), "Kobold Vermin", "a tooltip's list dash")
    equal(Quests.MobFromText("Prisoners rescued: 0/5", "monster"), nil, "a quest's own wording names no mob")
    equal(Quests.MobFromText("Gold Dust: 2/10", "item"), nil, "an item is no mob")
    equal(Quests.MobFromText(Mock.SECRET, "monster"), nil, "a secret text is not looked at")
    equal(Quests.CoreText("Gold Dust: 2/10"), "Gold Dust")
    equal(Quests.CoreText(" - 2/10 Gold Dust"), "Gold Dust")

    ns = start({ killFormat = "%s getötet: %d/%d" })
    equal(ns.Quests.MobFromText("Kobold Vermin getötet: 3/10", "monster"), "Kobold Vermin", "the client's own format string decides")
end)

scenario("a tracked kill quest: one row per objective in OUR panel - secure macro buttons, skull then cross, name and numbers", function()
    local ns = start()
    local panel = AKForeverTargeterPanel
    check(panel and panel:IsShown(), "the panel is there")
    local point, relativeTo, relativePoint, x, y = panel:GetPoint(1)
    equal(point, "RIGHT"); equal(relativeTo, UIParent); equal(relativePoint, "RIGHT"); equal(x, -30); equal(y, 0)
    equal(panel:GetHeight(), 18 + 2 * 20 + 6, "the title and two rows")

    local vermin, worker = rowFor(ns, KOBOLDS .. ":1"), rowFor(ns, KOBOLDS .. ":2")
    check(vermin and worker, "one row per objective that names a mob")
    equal(vermin.slot, 1); equal(worker.slot, 2)
    equal(vermin.names[1], "Kobold Vermin")
    equal(vermin.text, "Kobold Vermin"); equal(vermin.progress, "3/10")
    equal(vermin.marker, 8, "the first gets the skull")
    equal(worker.marker, 7, "the second the cross")
    equal(vermin.macro, "/cleartarget\n/targetexact Kobold Vermin\n/tm [exists,nodead] !8\n/targetlasttarget [noexists]")

    local frame = frameFor(KOBOLDS .. ":1")
    equal(frame:GetParent(), panel, "a child of OUR panel")
    equal(select(2, frame:GetPoint(1)), panel, "anchored inside it - to nothing of Blizzard's")
    check(frame:IsShown() and frame:GetAlpha() == 1)
    equal(frame:GetAttribute("type"), "macro")
    equal(frame.icon.__texture, "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
    equal(ns.Panel.state, "2 target(s) of interest")
    for _, any in ipairs(Mock.frames) do
        check(any.__attributes._onclick == nil and any.__attributes._onstate == nil, "no snippet anywhere: this beta compiles none")
    end
end)

scenario("a click targets the mob and marks it; with no such mob around nothing changes", function()
    local ns, state = start()
    local vermin = { name = "Kobold Vermin" }
    local boar = { name = "Stonetusk Boar" }
    state.mobs = { vermin, boar }
    state.target = boar

    Mock.click(frameFor(KOBOLDS .. ":1"))
    equal(state.target, vermin, "targeted")
    equal(vermin.marker, 8, "and marked with the row's skull")

    Mock.click(frameFor(KOBOLDS .. ":1"))
    equal(vermin.marker, 8, "a second click does not toggle the marker off")

    -- the Kobold Worker is not around: the target stays, and no marker moves
    Mock.click(frameFor(KOBOLDS .. ":2"))
    equal(state.target, vermin, "the target we had is back")
    equal(vermin.marker, 8, "its marker untouched")
    equal(boar.marker, nil)

    -- a corpse is targeted (the game does that) but not marked
    local worker = { name = "Kobold Worker", dead = true }
    state.mobs[#state.mobs + 1] = worker
    Mock.click(frameFor(KOBOLDS .. ":2"))
    equal(state.target, worker)
    equal(worker.marker, nil, "no marker on a corpse")

    local clicks = 0
    for _, entry in ipairs(ns.sessionLog) do
        if entry.k == "click" then
            clicks = clicks + 1
        end
    end
    equal(clicks, 4, "every click is in the log, once")
end)

scenario("either ActionButtonUseKeyDown setting works", function()
    for _, useKeyDown in ipairs({ true, false }) do
        local _, state = start({ useKeyDown = useKeyDown })
        local vermin = { name = "Kobold Vermin" }
        state.mobs = { vermin }
        Mock.click(frameFor(KOBOLDS .. ":1"))
        equal(state.target, vermin)

        -- the menu, held open by a modifier the player asked for, marks with either setting too
        wantModifier()
        holdMenu(true)
        Mock.click(AKForeverTargeterMenuCell1)
        equal(vermin.marker, 8, "the skull, top left, picked from the menu (key down: " .. tostring(useKeyDown) .. ")")
        holdMenu(false)
        check(not AKForeverTargeterMenu:IsShown())
    end
end)

scenario("a collect objective gets its row once a mob's tooltip has shown that objective", function()
    local ns, state = start({}, function(s) s.watched = { KOBOLDS, DUST } end)
    equal(rowFor(ns, DUST .. ":1"), nil, "nobody said who drops Gold Dust")

    state.units.mouseover = { name = "Kobold Miner", tooltip = {
        { QUEST_TITLE, "Gold Dust Exchange" }, { QUEST_OBJECTIVE, " - Gold Dust: 2/10" },
    } }
    Mock.fire("UPDATE_MOUSEOVER_UNIT")
    local dust = rowFor(ns, DUST .. ":1")
    check(dust, "learned from the tooltip")
    equal(dust.names[1], "Kobold Miner")
    equal(dust.text, "Kobold Miner"); equal(dust.progress, "2/10")
    equal(dust.marker, 6, "the next free marker")

    state.units.mouseover = { name = "Kobold Tunneler", tooltip = {
        { QUEST_TITLE, "Gold Dust Exchange" }, { QUEST_OBJECTIVE, "2/10 Gold Dust" },
    } }
    Mock.fire("UPDATE_MOUSEOVER_UNIT")
    dust = rowFor(ns, DUST .. ":1")
    equal(table.concat(dust.names, ","), "Kobold Miner,Kobold Tunneler", "every dropper is tried, in a stable order")
    check(dust.macro:find("/targetexact Kobold Miner\n/targetexact Kobold Tunneler", 1, true))
    equal(dust.marker, 6, "and the marker stays the same")

    -- a kill objective's mob seen under another name (the quest text said "Kobold Vermin")
    state.units.target = { name = "Kobold Vermin", tooltip = {
        { QUEST_TITLE, "Kobold Camp Cleanup" }, { QUEST_OBJECTIVE, "Kobold Vermin slain: 3/10" },
    } }
    Mock.fire("PLAYER_TARGET_CHANGED")
    equal(#rowFor(ns, KOBOLDS .. ":1").names, 1, "the same name is not added twice")
end)

scenario("what is NOT learned: untracked quests, another quest's line, a party member's progress, players", function()
    local ns, state = start({}, function(s) s.watched = { KOBOLDS, DUST } end)
    state.units.mouseover = { name = "Defias Pathstalker", tooltip = {
        { QUEST_TITLE, "Red Linen Goods" }, { QUEST_OBJECTIVE, "Red Linen Bandana: 0/6" }, -- not tracked
    } }
    Mock.fire("UPDATE_MOUSEOVER_UNIT")
    state.units.mouseover = { name = "Kobold Geomancer", tooltip = {
        { QUEST_TITLE, "Gold Dust Exchange" }, { QUEST_PLAYER, "Someoneelse" }, { QUEST_OBJECTIVE, "Gold Dust: 0/10" },
    } }
    Mock.fire("UPDATE_MOUSEOVER_UNIT")
    state.units.mouseover = { name = "Goldshire Rogue", isPlayer = true, tooltip = {
        { QUEST_TITLE, "Gold Dust Exchange" }, { QUEST_OBJECTIVE, "Gold Dust: 2/10" },
    } }
    Mock.fire("UPDATE_MOUSEOVER_UNIT")
    state.units.mouseover = { name = "Rabbit" } -- nothing to do with any quest
    Mock.fire("UPDATE_MOUSEOVER_UNIT")
    equal(rowFor(ns, DUST .. ":1"), nil)
    equal(next(ns.db.learned or {}), nil, "nothing was learned")

    -- our own line under our own name counts
    state.units.mouseover = { name = "Kobold Miner", tooltip = {
        { QUEST_TITLE, "Gold Dust Exchange" }, { QUEST_PLAYER, "Purrdee" }, { QUEST_OBJECTIVE, "Gold Dust: 2/10" },
    } }
    Mock.fire("UPDATE_MOUSEOVER_UNIT")
    check(rowFor(ns, DUST .. ":1"), "our own progress line teaches")

    -- two tracked quests want the same thing: the tooltip's quest title says whose mob this is
    local MORE_DUST = 48
    state.quests[MORE_DUST] = { title = "More Gold Dust", objectives = { { text = "Gold Dust: 0/5", type = "item", fulfilled = 0, required = 5 } } }
    state.watched = { KOBOLDS, DUST, MORE_DUST }
    Mock.watchListChanged()
    state.units.mouseover = { name = "Kobold Digger", tooltip = {
        { QUEST_TITLE, "More Gold Dust" }, { QUEST_OBJECTIVE, "Gold Dust: 0/5" },
    } }
    Mock.fire("UPDATE_MOUSEOVER_UNIT")
    equal(table.concat(rowFor(ns, MORE_DUST .. ":1").names, ","), "Kobold Digger")
    equal(table.concat(rowFor(ns, DUST .. ":1").names, ","), "Kobold Miner", "the other quest learned nothing from it")
end)

scenario("combat: the quest log changes mid-fight - numbers follow, a finished objective's row goes dim, new rows wait, nothing protected is touched", function()
    -- (the Miner was learned last session: markers go top to bottom from the start, and are then kept)
    local ns, state = start({ db = { learned = { [DUST] = { [1] = { ["Kobold Miner"] = true } } } } },
        function(s) s.watched = { DUST, KOBOLDS } end)
    local dustRow, verminRow, workerRow = frameFor(DUST .. ":1"), frameFor(KOBOLDS .. ":1"), frameFor(KOBOLDS .. ":2")
    check(dustRow and verminRow and workerRow)
    equal(rowFor(ns, DUST .. ":1").marker, 8); equal(rowFor(ns, KOBOLDS .. ":1").marker, 7); equal(rowFor(ns, KOBOLDS .. ":2").marker, 6)

    Mock.setCombat(true)
    state.quests[KOBOLDS].objectives[2].fulfilled = 3 -- three Kobold Workers down
    Mock.questLogChanged()
    equal(workerRow.progress:GetText(), "3/8", "the numbers follow: a text is not protected")
    equal(workerRow:GetAlpha(), 1)

    state.quests[KOBOLDS].objectives[1].fulfilled = 10 -- the last Kobold Vermin dies
    state.quests[KOBOLDS].objectives[1].finished = true
    Mock.questLogChanged()
    equal(verminRow:GetAlpha(), 0.35, "the finished objective's row goes dim at once")
    check(verminRow:IsShown(), "... but stays: a protected frame is not hidden in combat")
    equal(verminRow.progress:GetText(), "done")
    equal(select(5, workerRow:GetPoint(1)), -(18 + 2 * 20), "the row below does not move up: that is not allowed in a fight")

    state.watched = { DUST, KOBOLDS, BANDANAS } -- a quest tracked mid-fight
    ns.Quests:Learn(BANDANAS, 1, "Defias Pathstalker")
    Mock.watchListChanged()
    equal(rowFor(ns, BANDANAS .. ":1"), nil, "no new row during the fight")
    equal(ns.Panel.work.waitedForCombatEnd, 1)
    check(ns.Panel:Describe().pending)

    -- a click in combat still works: that is what secure buttons are for
    local miner = { name = "Kobold Miner" }
    state.mobs = { miner }
    Mock.click(dustRow)
    equal(state.target, miner)
    equal(miner.marker, 8)

    Mock.setCombat(false)
    equal(rowFor(ns, KOBOLDS .. ":1"), nil, "after the fight: the finished objective's row is gone")
    equal(rowFor(ns, KOBOLDS .. ":2").slot, 2, "the rows close up")
    equal(rowFor(ns, KOBOLDS .. ":2").marker, 6, "and keep their markers")
    local bandanas = rowFor(ns, BANDANAS .. ":1")
    check(bandanas, "the new quest has its row")
    equal(bandanas.slot, 3)
    equal(bandanas.marker, 7, "with the marker that became free")
    equal(frameFor(BANDANAS .. ":1"):GetAlpha(), 1)
end)

scenario("/akt off and on, /akt mark off, untracking a quest, turning one in", function()
    local ns, state = start({}, function(s) s.watched = { KOBOLDS, DUST } end)
    ns.Quests:Learn(DUST, 1, "Kobold Miner")
    local slash = SlashCmdList.AKFOREVERTARGETER

    slash("mark off")
    local vermin = rowFor(ns, KOBOLDS .. ":1")
    equal(vermin.marker, nil)
    equal(vermin.macro, "/cleartarget\n/targetexact Kobold Vermin\n/targetlasttarget [noexists]", "targets only")
    equal(frameFor(KOBOLDS .. ":1").icon.__texture, "Interface\\Minimap\\Tracking\\Target")
    slash("mark on")
    equal(rowFor(ns, KOBOLDS .. ":1").marker, 8)

    slash("off")
    equal(rowCount(ns), 0)
    check(not AKForeverTargeterPanel:IsShown(), "no panel at all")
    slash("on")
    equal(rowCount(ns), 3)

    state.watched = { KOBOLDS } -- untracked
    Mock.watchListChanged()
    equal(rowFor(ns, DUST .. ":1"), nil)
    check(ns.db.learned[DUST], "untracking does not forget")

    Mock.fire("QUEST_REMOVED", DUST) -- turned in
    Mock.nextFrame()
    equal(ns.db.learned[DUST], nil, "a quest that left the log takes its learned mobs along")

    state.watched = {}
    Mock.watchListChanged()
    check(not AKForeverTargeterPanel:IsShown(), "nothing to target: no panel")
    equal(ns.Panel.state, "nothing to target")

    slash("forget")
    slash("status")
    slash("")
    check(#Mock.printed > 0)
end)

scenario("always smooth: quest log chatter with nothing new touches no protected frame; ten events in one frame are one update", function()
    local ns = start()
    local before, syncs = Mock.protectedWrites, ns.Panel.work.syncs
    for _ = 1, 10 do
        Mock.fire("QUEST_LOG_UPDATE")
    end
    equal(#Mock.timers, 1, "one update booked for the next frame, not ten")
    Mock.nextFrame()
    equal(ns.Panel.work.syncs, syncs + 1)
    equal(Mock.protectedWrites - before, 0, "no Show, no SetPoint, no SetAttribute: nothing")
    equal(#Mock.timers, 0, "and nothing keeps running: no timer, no polling")
    for _ = 1, 25 do
        Mock.questLogChanged()
    end
    equal(Mock.protectedWrites - before, 0)
    equal(ns.Panel:Describe().made, 2, "and no row is made twice")
end)

scenario("a client without the quest log API: quietly nothing", function()
    local ns = start({ noQuestLog = true })
    equal(ns.Panel.state, "nothing to target")
    check(not AKForeverTargeterPanel:IsShown())
    SlashCmdList.AKFOREVERTARGETER("diag")
end)

scenario("secret values: an unreadable objective, turn-in state or unit means hands off - no error, no row", function()
    local ns, state = start({}, function(s)
        s.watched = { KOBOLDS, DUST, TURNIN }
        s.secretApis.objectiveText = true
        s.secretApis.readyForTurnIn = true
    end)
    equal(rowCount(ns), 0, "secret objective texts and a secret turn-in state")

    state.secretApis.objectiveText = nil
    state.secretApis.numbers = true
    Mock.questLogChanged()
    equal(rowCount(ns), 2, "the mobs are back")
    equal(rowFor(ns, KOBOLDS .. ":1").progress, "", "without numbers that cannot be read")
    equal(rowFor(ns, TURNIN .. ":turnin"), nil, "a quest whose turn-in state is unreadable gets no giver row")
    state.secretApis.readyForTurnIn = nil
    state.secretApis.numbers = nil
    Mock.questLogChanged()
    equal(rowCount(ns), 3)

    state.units.mouseover = { name = "Kobold Miner", tooltip = { { QUEST_TITLE, "Gold Dust Exchange" }, { QUEST_OBJECTIVE, "Gold Dust: 2/10" } } }
    state.secretApis.UnitName = true
    Mock.fire("UPDATE_MOUSEOVER_UNIT")
    state.secretApis.UnitName = nil
    state.secretApis.tooltipText = true
    Mock.fire("UPDATE_MOUSEOVER_UNIT")
    equal(rowFor(ns, DUST .. ":1"), nil, "nothing learned from what could not be read")

    state.secretApis.GetRaidTargetIndex = true
    state.secretApis.tooltipText = nil
    state.mobs = { { name = "Kobold Vermin" } }
    Mock.click(frameFor(KOBOLDS .. ":1")) -- the click log copes with a secret marker
end)

scenario("nothing opens the marker menu but the key you bound to it", function()
    local ns, state = start({ bindingKey = "SHIFT-T" })
    local menu = AKForeverTargeterMenu
    equal(ns:GetOption("menuModifier"), "off", "no modifier unless you ask for one")
    equal(ns.MarkerMenu:Describe().driver, "none", "and so nothing is watching your keys")

    -- every modifier there is, held: the menu stays where it is
    for _, key in ipairs({ "alt", "ctrl", "shift" }) do
        Mock.setModifier(key, true)
        check(not menu:IsShown(), "a held " .. key .. " is yours, not ours")
    end
    for _, key in ipairs({ "alt", "ctrl", "shift" }) do
        Mock.setModifier(key, false)
    end

    -- the binding, though, opens it at the mouse
    Mock.cursor(640, 480)
    AKForeverTargeter_ToggleMenu()
    check(menu:IsShown(), "the key you bound")
    equal(select(4, menu:GetPoint(1)), 640)
    AKForeverTargeter_ToggleMenu()
    check(not menu:IsShown(), "and it toggles")
end)

scenario("a modifier can be asked for as well: held, it opens at the mouse and STAYS - a stray key-up cannot take it away", function()
    local ns, state = start({ bindingKey = "SHIFT-T" })
    wantModifier()
    local menu = AKForeverTargeterMenu
    check(menu and not menu:IsShown(), "built hidden")
    equal(ns.MarkerMenu:Describe().cells, 9)
    equal(ns.MarkerMenu:Describe().driver, "[combat,mod:alt,mod:shift] show; [combat] hide",
        "the driver only has a say in combat - out of combat it can never take the menu away")
    equal(ns.MarkerMenu:Describe().sticky, true)

    local boar = { name = "Stonetusk Boar" }
    -- the vermin already wears the marker we are about to put on the boar, so the "one at a time"
    -- rule has something to take away (cell 9 is the star, bottom right - see MarkerMenu.lua's grid)
    state.mobs = { boar, { name = "Kobold Vermin", marker = 1 } }
    state.target = boar

    Mock.cursor(300, 200)
    holdMenu(true)
    check(menu:IsShown(), "opened by us, at once")
    local point, relativeTo, relativePoint, x, y = menu:GetPoint(1)
    equal(point, "CENTER"); equal(relativeTo, nil); equal(relativePoint, "BOTTOMLEFT"); equal(x, 300); equal(y, 200)

    -- the game hands out a stray key-up for Ctrl / Shift while you hold them; the menu must not care
    holdMenu(false)
    check(menu:IsShown(), "still there: sticky")
    equal(ns.MarkerMenu.work.keptOpen, 2, "two keys released, two strays survived")
    equal(select(4, menu:GetPoint(1)), 300, "and it did not jump anywhere")
    holdMenu(true)
    check(menu:IsShown())

    Mock.click(AKForeverTargeterMenuCell9) -- bottom right: the star
    equal(boar.marker, 1)
    equal(state.mobs[2].marker, nil, "a marker is on one unit at a time")
    check(not menu:IsShown(), "a pick closes it")

    holdMenu(true)
    Mock.click(AKForeverTargeterMenuCell9)
    equal(boar.marker, 1, "picking the marker it already has leaves it on")
    holdMenu(true)
    Mock.click(AKForeverTargeterMenuCell5) -- the middle: clear
    equal(boar.marker, nil)
    holdMenu(true)
    Mock.click(AKForeverTargeterMenuCell2) -- top middle: the cross
    equal(boar.marker, 7)
    holdMenu(true)
    Mock.click(AKForeverTargeterMenuCell7, "RightButton") -- any cell, right button: clear
    equal(boar.marker, nil, "a right-click on any cell clears the target's marker")

    -- a click somewhere else closes it
    holdMenu(true)
    state.mouseOver = menu
    Mock.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
    check(menu:IsShown(), "a click on the menu itself does not")
    state.mouseOver = nil
    Mock.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
    check(not menu:IsShown())
    holdMenu(false)
end)

scenario("the marker menu in combat: Blizzard's state driver shows it while the keys are held, at its spot", function()
    local ns, state = start()
    wantModifier() -- in a fight a modifier is the ONLY way: a binding cannot show a protected frame then
    local menu = AKForeverTargeterMenu
    local boar = { name = "Stonetusk Boar" }
    state.mobs = { boar }
    state.target = boar

    Mock.setCombat(true)
    Mock.cursor(900, 700)
    holdMenu(true)
    check(menu:IsShown(), "shown by the driver in combat")
    equal(select(3, menu:GetPoint(1)), "CENTER", "at its spot, not at the mouse: it cannot be moved in a fight")
    Mock.click(AKForeverTargeterMenuCell1)
    equal(boar.marker, 8, "the skull, in combat")
    check(menu:IsShown(), "a pick does not close it in a fight: hiding is not ours to do")
    Mock.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
    check(menu:IsShown(), "and neither does a click elsewhere")
    holdMenu(false)
    check(not menu:IsShown(), "released: hidden by the driver")
    Mock.setCombat(false)

    -- what the driver left behind is cleared, so the menu opens again out of combat
    holdMenu(true)
    check(menu:IsShown())
    equal(AKForeverTargeterMenu.__attributes.statehidden, nil)
    holdMenu(false)
    Mock.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
end)

scenario("the marker menu: a pair of keys that belongs to nobody else, 'sticky off', and none at all", function()
    local ns = start()
    local menu = AKForeverTargeterMenu
    SlashCmdList.AKFOREVERTARGETER("menu mod alt-shift")
    equal(ns.MarkerMenu:Describe().driver, "[combat,mod:alt,mod:shift] show; [combat] hide")
    Mock.setModifier("alt", true)
    check(not menu:IsShown(), "half the combination is not the combination")
    Mock.setModifier("shift", true)
    check(menu:IsShown(), "both: there it is")
    Mock.setModifier("shift", false)
    check(menu:IsShown(), "sticky")
    Mock.setModifier("alt", false)
    Mock.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
    check(not menu:IsShown())

    SlashCmdList.AKFOREVERTARGETER("menu sticky off")
    equal(ns.MarkerMenu:Describe().sticky, false)
    Mock.setModifier("alt", true); Mock.setModifier("shift", true)
    check(menu:IsShown())
    Mock.setModifier("shift", false)
    check(not menu:IsShown(), "'sticky off': it goes as the keys go")
    Mock.setModifier("alt", false)
    SlashCmdList.AKFOREVERTARGETER("menu sticky on")

    Mock.cursor(1200, 300)
    SlashCmdList.AKFOREVERTARGETER("menu spot")
    equal(ns.cdb.options.menuSpot.x, 1200)
    Mock.setCombat(true)
    Mock.cursor(50, 50)
    Mock.setModifier("alt", true); Mock.setModifier("shift", true)
    equal(select(4, menu:GetPoint(1)), 1200, "in combat it appears at the spot you chose")
    equal(select(5, menu:GetPoint(1)), 300)
    Mock.setModifier("alt", false); Mock.setModifier("shift", false)
    Mock.setCombat(false)
    SlashCmdList.AKFOREVERTARGETER("menu spot reset")
    equal(ns.cdb.options.menuSpot, nil)

    SlashCmdList.AKFOREVERTARGETER("menu mod nonsense")
    check(Mock.printed[#Mock.printed]:find("alt-shift", 1, true), "the usage lists the pairs")
    SlashCmdList.AKFOREVERTARGETER("menu mod off")
    equal(ns.MarkerMenu:Describe().driver, "none")
    equal(#Mock.stateDrivers, 0, "the driver is gone")
    Mock.setModifier("alt", true)
    check(not menu:IsShown())
    Mock.setModifier("alt", false)

    -- a modifier change during a fight waits for its end (registering a driver is protected)
    Mock.setCombat(true)
    SlashCmdList.AKFOREVERTARGETER("menu mod ctrl-shift")
    equal(#Mock.stateDrivers, 0)
    Mock.setCombat(false)
    equal(ns.MarkerMenu:Describe().driver, "[combat,mod:ctrl,mod:shift] show; [combat] hide")
end)

scenario("logged in during a fight: nothing protected is built until it is over", function()
    local ns, state = Mock.install({})
    state.quests, state.watched = quests(), { KOBOLDS }
    state.inCombat = true
    Mock.login()
    Mock.nextFrame()
    equal(AKForeverTargeterMenu, nil)
    equal(AKForeverTargeterPanel, nil)
    Mock.setCombat(false)
    check(AKForeverTargeterMenu, "the menu is built after the fight")
    check(rowFor(ns, KOBOLDS .. ":1"), "and so is the panel")
end)

scenario("the quest giver: the names in a sentence", function()
    local ns = start()
    local names = ns.Quests.NamesFromText
    equal(table.concat(names("Speak with Holt Thunderhorn on Hunter Rise in Thunder Bluff."), "|"), "Holt Thunderhorn|Hunter Rise|Thunder Bluff")
    equal(table.concat(names("Return to Chief Hawkwind in Camp Narache."), "|"), "Chief Hawkwind|Camp Narache")
    equal(table.concat(names("Bring the head to Marshal Dughan."), "|"), "Marshal Dughan")
    equal(table.concat(names("Take the supplies back to the camp."), "|"), "", "no name, no row")
    equal(table.concat(names("Report to Kadrak of the Warsong Outriders, at the lumber camp."), "|"), "Kadrak of the Warsong Outriders")
    equal(#names(Mock.SECRET), 0)
end)

scenario("a quest ready to turn in gets a row for its giver: the NPC remembered when it was accepted, or the names in its line", function()
    local ns, state = start({}, function(s) s.watched = { KOBOLDS, TURNIN } end)
    local giver = rowFor(ns, TURNIN .. ":turnin")
    check(giver, "a row for the quest that is ready")
    equal(giver.kind, "giver")
    equal(giver.slot, 3, "after the quest's objectives... which a finished quest no longer lists")
    equal(rowFor(ns, TURNIN .. ":1"), nil)
    equal(table.concat(giver.names, "|"), "Holt Thunderhorn|Hunter Rise|Thunder Bluff", "every name in the line: a place finds nobody")
    equal(giver.text, "Holt Thunderhorn"); equal(giver.progress, "turn in")
    equal(giver.marker, nil, "a quest giver is never marked")
    equal(giver.macro, "/cleartarget\n/targetexact Holt Thunderhorn\n/targetexact Hunter Rise\n/targetexact Thunder Bluff\n/targetlasttarget [noexists]")
    equal(frameFor(TURNIN .. ":turnin").icon.__atlas, "QuestTurnin", "the turn-in '?'")
    equal(rowFor(ns, KOBOLDS .. ":1").marker, 8, "the mobs keep their markers")

    local holt = { name = "Holt Thunderhorn" }
    state.mobs = { holt }
    Mock.click(frameFor(TURNIN .. ":turnin"))
    equal(state.target, holt)
    equal(holt.marker, nil)

    -- a quest accepted from an NPC remembers him - first in line
    local ANOTHER = 301
    state.quests[ANOTHER] = { title = "Wildmane Totem", objectives = {}, complete = true, completionText = "Return to the camp." }
    Mock.acceptQuest(ANOTHER, "Mull Thunderhorn")
    equal(ns.db.givers[ANOTHER], "Mull Thunderhorn")
    state.watched = { KOBOLDS, TURNIN, ANOTHER }
    Mock.watchListChanged()
    equal(table.concat(rowFor(ns, ANOTHER .. ":turnin").names, "|"), "Mull Thunderhorn", "the line names nobody, the giver is known anyway")
    Mock.acceptQuest(TURNIN, "Holt Thunderhorn")
    equal(table.concat(rowFor(ns, TURNIN .. ":turnin").names, "|"), "Holt Thunderhorn|Hunter Rise|Thunder Bluff", "known and named: once")

    Mock.fire("QUEST_REMOVED", ANOTHER)
    Mock.nextFrame()
    equal(ns.db.givers[ANOTHER], nil, "turned in: forgotten")
    SlashCmdList.AKFOREVERTARGETER("forget")
    equal(next(ns.db.givers), nil)
end)

scenario("one key for any of them: the first mob on the list that is around is targeted and marked with its own marker; a giver last, unmarked", function()
    local ns, state = start({ anyKey = "T" }, function(s) s.watched = { KOBOLDS, DUST, TURNIN } end)
    ns.Quests:Learn(DUST, 1, "Kobold Miner")
    equal(_G["BINDING_NAME_CLICK AKForeverTargeterAnyButton:LeftButton"], "Target any of them (the first around)")
    local any = AKForeverTargeterAnyButton
    check(any and any:IsVisible() and any:GetAlpha() == 0, "an invisible secure button the key clicks")
    equal(ns.Panel:Describe().any.boundTo, "T")
    equal(any:GetAttribute("macrotext"), "/cleartarget\n/targetexact [noexists] Kobold Vermin\n/tm [exists,nodead] ~8\n"
        .. "/targetexact [noexists] Kobold Worker\n/tm [exists,nodead] ~7\n/targetexact [noexists] Kobold Miner\n/tm [exists,nodead] ~6\n"
        .. "/targetexact [noexists] Holt Thunderhorn\n/targetexact [noexists] Hunter Rise\n/targetexact [noexists] Thunder Bluff\n/targetlasttarget [noexists]")

    local boar, vermin, worker = { name = "Stonetusk Boar" }, { name = "Kobold Vermin" }, { name = "Kobold Worker" }
    local miner, holt = { name = "Kobold Miner" }, { name = "Holt Thunderhorn" }
    state.target = boar
    state.mobs = { boar }
    Mock.click(any)
    equal(state.target, boar, "nobody of interest around: the target stays")

    state.mobs = { boar, worker, vermin }
    Mock.click(any)
    equal(state.target, vermin, "the first on the list that is around")
    equal(vermin.marker, 8); equal(worker.marker, nil, "only the one targeted is marked")

    state.mobs = { worker, miner }
    Mock.click(any)
    equal(state.target, worker); equal(worker.marker, 7)
    state.mobs = { miner }
    Mock.click(any)
    equal(state.target, miner); equal(miner.marker, 6)

    state.mobs = { holt }
    Mock.click(any)
    equal(state.target, holt, "the quest giver, when no mob is around")
    equal(holt.marker, nil, "and never marked")

    vermin.marker = 1
    state.mobs = { vermin }
    Mock.click(any)
    equal(vermin.marker, 1, "a mob that already carries a marker keeps it")

    -- the key's macro follows the list - after a fight, not during
    Mock.setCombat(true)
    state.watched = { KOBOLDS, DUST, TURNIN, BANDANAS }
    ns.Quests:Learn(BANDANAS, 1, "Defias Pathstalker")
    Mock.watchListChanged()
    check(not any:GetAttribute("macrotext"):find("Pathstalker", 1, true), "waits for the fight to end")
    Mock.setCombat(false)
    check(any:GetAttribute("macrotext"):find("/targetexact [noexists] Defias Pathstalker", 1, true))
    SlashCmdList.AKFOREVERTARGETER("mark off")
    check(not any:GetAttribute("macrotext"):find("/tm", 1, true), "marking off: the key only targets")
    SlashCmdList.AKFOREVERTARGETER("status")
    check(Mock.printed[#Mock.printed]:find("T (Key Bindings", 1, true), "status tells the key")
end)

scenario("hide a row with a right-click, lower its priority with Shift + right-click; both wait for a fight to end", function()
    local ns, state = start({}, function(s) s.watched = { KOBOLDS, DUST } end)
    ns.Quests:Learn(DUST, 1, "Kobold Miner")
    local boar = { name = "Stonetusk Boar" }
    state.mobs = { boar, { name = "Kobold Vermin" } }
    state.target = boar

    Mock.rightClick(frameFor(KOBOLDS .. ":1"))
    equal(state.target, boar, "a right-click runs no secure action")
    equal(rowFor(ns, KOBOLDS .. ":1"), nil, "the row is hidden")
    equal(ns.db.hidden[KOBOLDS .. ":1"], true)
    equal(rowFor(ns, KOBOLDS .. ":2").slot, 1, "the rows close up")
    equal(rowFor(ns, KOBOLDS .. ":2").marker, 7, "and keep their markers")
    check(not AKForeverTargeterAnyButton:GetAttribute("macrotext"):find("Kobold Vermin", 1, true), "the any key skips it too")
    equal(ns.Panel.state, "2 target(s) of interest, 1 hidden")
    equal(AKForeverTargeterPanel.__children[2].__text, "Targets of interest (1 hidden)", "the title counts it")
    SlashCmdList.AKFOREVERTARGETER("hidden")
    check(Mock.printed[#Mock.printed]:find("1|r  Kobold Vermin  (Kobold Camp Cleanup)", 1, true), "the list names it")
    SlashCmdList.AKFOREVERTARGETER("unhide 7")
    check(Mock.printed[#Mock.printed]:find("no hidden row number 7", 1, true))
    Mock.rightClick(frameFor(KOBOLDS .. ":2")) -- a second one hidden
    equal(ns.Panel.state, "1 target(s) of interest, 2 hidden")
    SlashCmdList.AKFOREVERTARGETER("unhide 2")
    equal(ns.Panel.state, "2 target(s) of interest, 1 hidden", "one back, the other still hidden")
    check(rowFor(ns, KOBOLDS .. ":2") and not rowFor(ns, KOBOLDS .. ":1"), "the second on the list, not the first")
    equal(rowFor(ns, KOBOLDS .. ":2").marker, 8, "(markers are given afresh to a row that comes back)")
    SlashCmdList.AKFOREVERTARGETER("unhide 1")
    equal(rowFor(ns, KOBOLDS .. ":1").slot, 1, "back on top")
    equal(rowFor(ns, KOBOLDS .. ":1").marker, 7)
    equal(AKForeverTargeterPanel.__children[2].__text, "Targets of interest")

    -- a right-click on the panel itself brings everything back
    Mock.rightClick(frameFor(KOBOLDS .. ":1"))
    Mock.rightClick(frameFor(KOBOLDS .. ":2"))
    equal(ns.Panel.state, "1 target(s) of interest, 2 hidden")
    Mock.runScript(AKForeverTargeterPanel, "OnMouseUp", "LeftButton")
    equal(ns.Panel.state, "1 target(s) of interest, 2 hidden", "a left-click on the panel does nothing")
    Mock.runScript(AKForeverTargeterPanel, "OnMouseUp", "RightButton")
    equal(rowCount(ns), 3, "all back")
    SlashCmdList.AKFOREVERTARGETER("hidden")
    check(Mock.printed[#Mock.printed]:find("nothing is hidden", 1, true))
    SlashCmdList.AKFOREVERTARGETER("unhide")

    Mock.rightClick(frameFor(KOBOLDS .. ":1"), true) -- Shift: lower its priority
    equal(ns.db.deprio[KOBOLDS .. ":1"], true)
    equal(rowFor(ns, KOBOLDS .. ":1").slot, 3, "last")
    equal(rowFor(ns, KOBOLDS .. ":2").slot, 1); equal(rowFor(ns, DUST .. ":1").slot, 2)
    local macro = AKForeverTargeterAnyButton:GetAttribute("macrotext")
    check(macro:find("Kobold Worker", 1, true) < macro:find("Kobold Vermin", 1, true), "the any key tries it last")
    Mock.rightClick(frameFor(KOBOLDS .. ":1"), true) -- and back
    equal(rowFor(ns, KOBOLDS .. ":1").slot, 1)
    equal(ns.db.deprio[KOBOLDS .. ":1"], nil)

    -- in a fight nothing protected moves: the hidden row dims, the lowered one stays put - until it is over
    Mock.setCombat(true)
    Mock.rightClick(frameFor(KOBOLDS .. ":1"))
    check(frameFor(KOBOLDS .. ":1"):IsShown(), "still shown")
    equal(frameFor(KOBOLDS .. ":1"):GetAlpha(), 0.35, "but dim")
    equal(frameFor(KOBOLDS .. ":1").progress:GetText(), "hidden")
    equal(AKForeverTargeterPanel.__children[2].__text, "Targets of interest (1 hidden)", "the title follows in a fight: a text is not protected")
    Mock.runScript(AKForeverTargeterPanel, "OnMouseUp", "RightButton")
    equal(frameFor(KOBOLDS .. ":1"):GetAlpha(), 1, "brought back: the row is bright again, and stays where it is")
    Mock.rightClick(frameFor(KOBOLDS .. ":1"))
    Mock.rightClick(frameFor(KOBOLDS .. ":2"), true)
    equal(rowFor(ns, KOBOLDS .. ":2").slot, 2, "not moved in a fight")
    Mock.setCombat(false)
    equal(rowFor(ns, KOBOLDS .. ":1"), nil)
    equal(rowFor(ns, DUST .. ":1").slot, 1)
    equal(rowFor(ns, KOBOLDS .. ":2").slot, 2, "lowered: after the Miner now")

    -- a quest that is turned in takes its flags along
    Mock.fire("QUEST_REMOVED", KOBOLDS)
    Mock.nextFrame()
    equal(ns.db.hidden[KOBOLDS .. ":1"], nil); equal(ns.db.deprio[KOBOLDS .. ":2"], nil)
end)

scenario("only what is here: a quest whose business is in another zone takes no row, and the title says so", function()
    local ns, state = start({}, function(s) s.watched = { KOBOLDS, DUST } end)
    ns.Quests:Learn(DUST, 1, "Kobold Miner")
    equal(rowCount(ns), 3)
    equal(AKForeverTargeterPanel.__children[2].__text, "Targets of interest")

    -- the kobold camp is behind you now
    Mock.setElsewhere(KOBOLDS, true)
    equal(rowCount(ns), 1, "only the quest whose business is here")
    check(rowFor(ns, DUST .. ":1") and not rowFor(ns, KOBOLDS .. ":1"))
    equal(AKForeverTargeterPanel.__children[2].__text, "Targets of interest (1 quest elsewhere)")
    equal(ns.Panel.state, "1 target(s) of interest, 1 quest(s) elsewhere")
    check(ns.Panel:Describe().zoneNote:find("map 1411", 1, true), "the report says which map decided it")
    check(not AKForeverTargeterAnyButton:GetAttribute("macrotext"):find("Kobold Vermin", 1, true),
        "and the any-target key does not reach for them either")

    -- walk back and they are there again
    Mock.setElsewhere(KOBOLDS, false)
    equal(rowCount(ns), 3)
    equal(rowFor(ns, KOBOLDS .. ":1").marker, 8, "with their markers")

    -- or walk to where they are: the panel follows the player, not the quest
    Mock.setElsewhere(KOBOLDS, true)
    Mock.setPlayerMap(1413)
    equal(rowCount(ns), 2, "the kobolds are here now, the gold dust is not")
    check(rowFor(ns, KOBOLDS .. ":1") and not rowFor(ns, DUST .. ":1"))
    Mock.setPlayerMap(1411)
    Mock.setElsewhere(KOBOLDS, false)

    -- switched off, everything tracked gets a row wherever it is
    Mock.setElsewhere(KOBOLDS, true)
    SlashCmdList.AKFOREVERTARGETER("zone off")
    equal(rowCount(ns), 3)
    equal(AKForeverTargeterPanel.__children[2].__text, "Targets of interest")
    SlashCmdList.AKFOREVERTARGETER("zone on")
    equal(rowCount(ns), 1)
    check(Mock.printed[#Mock.printed]:find("1 quest(s) left out", 1, true))
end)

scenario("a mob's tooltip is read once, not every time the cursor crosses it", function()
    local ns, state = start({}, function(s) s.watched = { KOBOLDS } end)

    -- count the expensive call: in the game C_TooltipInfo.GetUnit builds a real tooltip
    local builds, real = 0, C_TooltipInfo.GetUnit
    C_TooltipInfo.GetUnit = function(...)
        builds = builds + 1
        return real(...)
    end

    local function hover(name)
        state.units.mouseover = { name = name, tooltip = {
            { QUEST_TITLE, "Kobold Camp Cleanup" },
            { QUEST_OBJECTIVE, "Kobold Miner slain: 3/8" },
        } }
        Mock.fire("UPDATE_MOUSEOVER_UNIT")
    end

    hover("Kobold Miner")
    equal(builds, 1, "the first look reads it")
    -- (what it LEARNS from a tooltip has scenarios of its own; this one is about how often it looks)

    for _ = 1, 20 do
        hover("Kobold Miner")
    end
    equal(builds, 1, "twenty more passes of the cursor cost nothing")

    hover("Kobold Tunneler")
    equal(builds, 2, "a different mob is still read")

    -- but anything that changes what a tooltip MEANS makes them all worth reading again
    Mock.fire("QUEST_ACCEPTED", 999)
    hover("Kobold Miner")
    equal(builds, 3, "a quest taken: read it again")

    Mock.fire("UNIT_QUEST_LOG_CHANGED", "player")
    hover("Kobold Miner")
    equal(builds, 4, "an objective moving on: again")

    C_TooltipInfo.GetUnit = real
end)

scenario("standing in a city: its own map carries no quests, so the zone it sits in decides", function()
    local ns, state = start({}, function(s) s.watched = { KOBOLDS, DUST } end)
    ns.Quests:Learn(DUST, 1, "Kobold Miner")
    state.quests[KOBOLDS].map = 1411 -- Durotar
    state.quests[DUST].map = 1413    -- the Barrens
    Mock.setPlayerMap(1454)          -- Orgrimmar: nothing is placed on the city map at all

    equal(#(C_QuestLog.GetQuestsOnMap(1454)), 0, "the client really does place nothing here")
    check(ns.Panel:Describe().zoneNote:find("1454+1411", 1, true), "so Durotar was asked as well")
    check(rowFor(ns, KOBOLDS .. ":1"), "Durotar's business shows in Orgrimmar")
    equal(rowFor(ns, DUST .. ":1"), nil, "a Southsea Brigand from the Barrens does NOT")

    -- the walk stops at the continent: Kalimdor would hold every zone on it
    Mock.setPlayerMap(1411)
    check(rowFor(ns, KOBOLDS .. ":1")); equal(rowFor(ns, DUST .. ":1"), nil)
end)

scenario("an empty answer is an answer: nothing here means nothing on the panel", function()
    local ns, state = start({}, function(s) s.watched = { KOBOLDS, DUST } end)
    ns.Quests:Learn(DUST, 1, "Kobold Miner")
    state.quests[KOBOLDS].map = 1413
    state.quests[DUST].map = 1413
    Mock.setPlayerMap(1454) -- a city with nothing of yours in it or around it

    equal(rowCount(ns), 0, "not one row: 'nothing here' is not the same as 'I could not tell'")
    equal(ns.Panel:Describe().elsewhere, 2, "and the title counts them as elsewhere, not as missing")

    -- a client that cannot answer at all is still given the benefit of the doubt
    state.noQuestsOnMap = true
    Mock.watchListChanged()
    check(rowCount(ns) > 0, "unreadable still shows everything")
end)

scenario("a client that will not say which map you are in leaves every row where it is", function()
    local ns, state = start({}, function(s) s.watched = { KOBOLDS, DUST } end)
    ns.Quests:Learn(DUST, 1, "Kobold Miner")
    Mock.setElsewhere(KOBOLDS, true)
    equal(rowCount(ns), 1, "to begin with, the filter works")

    -- the client will not name the player's map
    state.secretApis.playerMap = true
    Mock.watchListChanged()
    equal(rowCount(ns), 3, "so nothing is hidden")
    check(ns.Panel:Describe().zoneNote:find("which map you are in", 1, true))
    state.secretApis.playerMap = nil

    -- it names the map but places nothing on it (an instance, a new map it has no data for)
    state.noQuestsOnMap = true
    Mock.watchListChanged()
    equal(rowCount(ns), 3)
    state.noQuestsOnMap = nil

    -- an older client without the call at all
    local saved = C_QuestLog.GetQuestsOnMap
    C_QuestLog.GetQuestsOnMap = nil
    Mock.watchListChanged()
    equal(rowCount(ns), 3)
    check(ns.Panel:Describe().zoneNote:find("has no C_Map", 1, true))
    C_QuestLog.GetQuestsOnMap = saved

    -- "on the map the client is showing" is NOT what decides it: that flag is true for the Barrens too
    Mock.watchListChanged()
    equal(rowCount(ns), 1, "the player's own map decides")
end)

scenario("a quest ready to turn in is never hidden by the zone: it is the row you most want when you walk in", function()
    local ns, state = start({}, function(s)
        s.quests[TURNIN] = { title = "The Hunter's Way", objectives = {}, complete = true,
            completionText = "Speak with Holt Thunderhorn on Hunter Rise in Thunder Bluff." }
        s.watched = { KOBOLDS, TURNIN }
    end)
    -- the client does not place the finished quest on the map you are in - as Thrall's did not
    Mock.setElsewhere(TURNIN, true)
    Mock.setElsewhere(KOBOLDS, true)
    equal(rowCount(ns), 1, "the kobolds go, the turn-in stays")
    check(rowFor(ns, TURNIN .. ":turnin"))
    equal(select(2, ns.Quests:IsHere(TURNIN)), "ready to turn in")
end)

scenario("the quest giver is learned from any dialog you open, not only from accepting", function()
    local ns, state = start({}, function(s)
        s.quests[TURNIN] = { title = "Hidden Enemies", objectives = {}, complete = true } -- no completion text at all
        s.watched = { TURNIN }
    end)
    equal(ns.Quests:GiverNames(TURNIN), nil, "nothing to go on: no row")
    equal(rowCount(ns), 0)

    -- you found him yourself and opened the turn-in
    Mock.questDialog("QUEST_COMPLETE", TURNIN, "Thrall")
    equal(ns.db.givers[TURNIN], "Thrall")
    equal(table.concat(ns.Quests:GiverNames(TURNIN), "|"), "Thrall")
    equal(rowCount(ns), 1, "and from now on the panel points you at him")
    equal(rowFor(ns, TURNIN .. ":turnin").text, "Thrall")

    -- the offer page and the progress page count too
    local OTHER = 777
    state.quests[OTHER] = { title = "Another", objectives = {}, complete = true }
    state.watched = { TURNIN, OTHER }
    Mock.questDialog("QUEST_PROGRESS", OTHER, "Gazlowe")
    equal(ns.db.givers[OTHER], "Gazlowe")
end)

scenario("mousing over somebody whose tooltip names a quest you have finished remembers them", function()
    local ns, state = start({}, function(s)
        s.quests[TURNIN] = { title = "Hidden Enemies", objectives = {}, complete = true }
        s.watched = { TURNIN }
    end)
    equal(rowCount(ns), 0)

    state.units.mouseover = { name = "Thrall", tooltip = { { QUEST_TITLE, "Hidden Enemies" } } }
    Mock.fire("UPDATE_MOUSEOVER_UNIT")
    equal((ns.db.givers or {})[TURNIN], "Thrall", "the one waiting for it")
    equal(rowCount(ns), 1)

    -- somebody whose tooltip names a quest that is NOT finished is not the one waiting for it
    state.quests[BANDANAS] = { title = "Red Linen Goods", objectives = { { text = "Red Linen Bandana: 0/6", type = "item" } } }
    state.watched = { TURNIN, BANDANAS }
    Mock.watchListChanged()
    state.units.mouseover = { name = "Defias Pathstalker", tooltip = { { QUEST_TITLE, "Red Linen Goods" } } }
    Mock.fire("UPDATE_MOUSEOVER_UNIT")
    equal((ns.db.givers or {})[BANDANAS], nil)
end)

scenario("the panel is dragged by its title: the place is saved and comes back next session; /akt reset", function()
    local ns = start()
    Mock.dragPanel(400, 300)
    local saved = ns.cdb.options.panel
    check(saved and saved.point == "TOPLEFT" and saved.x == 400 and saved.y == 300, "saved where it was dropped")
    equal(AKForeverTargeterPanel.__userPlaced, false, "the client's own layout cache is told to stay out of it")

    local again = start({ db = ns.db })
    local point, relativeTo, relativePoint, x, y = AKForeverTargeterPanel:GetPoint(1)
    equal(point, "TOPLEFT"); equal(relativeTo, UIParent); equal(relativePoint, "BOTTOMLEFT"); equal(x, 400); equal(y, 300)

    Mock.setCombat(true)
    Mock.dragPanel(10, 10)
    equal(select(4, AKForeverTargeterPanel:GetPoint(1)), 400, "not in a fight")
    SlashCmdList.AKFOREVERTARGETER("reset")
    equal(select(4, AKForeverTargeterPanel:GetPoint(1)), 400, "not in a fight either")
    Mock.setCombat(false)
    SlashCmdList.AKFOREVERTARGETER("reset")
    equal(select(1, AKForeverTargeterPanel:GetPoint(1)), "RIGHT")
    equal(again.cdb.options.panel, nil)
end)

scenario("diagnostics and logout run; the report is SavedVariables-safe and holds no frame", function()
    local ns, state = start({}, function(s) s.watched = { KOBOLDS, DUST, TURNIN } end)
    state.units.mouseover = { name = "Kobold Miner", tooltip = { { QUEST_TITLE, "Gold Dust Exchange" }, { QUEST_OBJECTIVE, "Gold Dust: 2/10" } } }
    Mock.fire("UPDATE_MOUSEOVER_UNIT")
    Mock.acceptQuest(TURNIN, "Holt Thunderhorn")
    Mock.fire("ADDON_ACTION_BLOCKED", "SomeOtherAddon", "ObjectiveTrackerFrame:SetPoint()")
    SlashCmdList.AKFOREVERTARGETER("diag")
    Mock.fire("PLAYER_LOGOUT")

    local report = AKForeverTargeterDB.diag
    equal(report.addonVersion, "0.1.0-test")
    equal(report.quests[1].objectives[1].mobFromText, "Kobold Vermin")
    equal(report.quests[1].objectives[1].numbers, "3/10")
    equal(report.quests[3].readyForTurnIn, true)
    equal(report.quests[3].giverNames[1], "Holt Thunderhorn")
    equal(report.givers[TURNIN], "Holt Thunderhorn")
    equal(report.tooltipSamples[1].mob, "Kobold Miner")
    equal(#report.panel.inUse, 4)
    equal(report.panel.inUse[4].kind, "giver")
    equal(report.markerMenu.modifier, "off", "the key you bound is the way in, not a modifier")
    equal(report.blockedActions[1].addon, "SomeOtherAddon", "blocked actions of OTHER addons are kept too")
    equal(report.blockedActions[1].ours, false)

    local function walk(value, path)
        local kind = type(value)
        check(kind == "table" or kind == "string" or kind == "number" or kind == "boolean", path .. " holds a " .. kind)
        if kind == "table" then
            check(rawget(value, "__kind") == nil, path .. " is a frame")
            for k, v in pairs(value) do
                walk(v, path .. "." .. tostring(k))
            end
        end
    end
    walk(AKForeverTargeterDB, "AKForeverTargeterDB")
end)

scenario("the version: the packager's stamp, a working copy, a release tag", function()
    equal(start().version, "0.1.0-test", "the version the packager stamped into the TOC")
    equal(start({ version = "@project-version@" }).version, "dev", "a working copy: the TOC still holds the packager's token")
    equal(start({ version = "v0.1.0" }).version, "0.1.0", "a release tag: printed as v0.1.0, not vv0.1.0")
end)

Mock.realPrint(string.format("\n%d passed, %d failed", passed, #failures))
os.exit(#failures == 0 and 0 or 1)
