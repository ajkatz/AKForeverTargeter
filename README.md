# AKForeverTargeter

Quest targeting for **World of Warcraft: Forever** (Interface `16001`).

*Part of a small family of addons built for the WoW: Forever game mode, with one mission: minimalistic UI
additions that bring out the utility Blizzard's UI does not give - minimal in nature, no Lua errors, always
smooth.*

- **Targets of interest:** a small panel with one row per mob your tracked quests are after - the kill
  objectives' mobs, the mobs learned for the collect objectives - and, for a quest that is ready to turn in,
  the NPC to bring it back to. Each row shows the marker it will use, the name and the count (`3/10`).
  Click a row: target it (`/targetexact`) and, with marking on, put that raid target marker on it.
- **No mob database.** A kill objective names its mob (`0/14 Venture Co. Worker slain`). For a collect
  objective (`0/4 Flatland Prowler Claw`) the addon learns the mob the first time you mouse over or target
  one whose tooltip shows that objective. The quest giver is remembered as you accept the quest, and the
  names in a finished quest's "Return to ..." line are tried as well.
- **A marker menu:** hold the modifier and a 3 x 3 grid appears at the mouse - the eight markers around a
  clear button - for your current target. Left-click a cell to mark, right-click any cell to clear.
  **Out of combat the menu stays** until you pick a marker or click elsewhere, so a stray key-up cannot take
  it away (`/akt menu sticky off` if you prefer it to go with the keys). **In combat** Blizzard's state
  driver shows it while you hold the keys, at its spot (`/akt menu spot`).
  `/akt menu mod alt-shift` - a lone Alt, Ctrl or Shift is everybody's combo key, so you can hold a **pair**
  instead: `alt`, `ctrl`, `shift`, `alt-shift`, `alt-ctrl`, `ctrl-shift`, `off`. A key binding (Key Bindings >
  AddOns > AKForeverTargeter) toggles it at the mouse out of combat.
- **One key for any of them** (Key Bindings > AddOns > AKForeverTargeter, or `/click AKForeverTargeterAnyButton`
  in a macro of yours): targets the first name on the panel that is around, and marks it with its own row's
  marker unless it already carries one. Quest givers come last and are never marked.
- **Not now:** right-click a row to hide it; the title counts the hidden rows, a right-click on the panel
  brings them all back (`/akt hidden` lists them, `/akt unhide 2` brings one back). Shift + right-click a row
  to put it last on the panel and last for the any-target key - and first again.
- **Only what is here:** a tracked quest whose business is on another map takes no row - the title says how
  many are waiting elsewhere. `/akt zone off` shows them all. It asks the map you are standing in
  (`C_Map.GetBestMapForUnit`) and which quests the client puts there (`C_QuestLog.GetQuestsOnMap`), so no
  zone names are matched; a client that will not say leaves every row where it is. (`GetInfo().isOnMap`
  looked right and was not: standing in Durotar with Kalimdor on screen, Barrens quests counted as here.)
  The end of a flight re-reads the map (`PLAYER_CONTROL_GAINED`): in the air the zone events fire at the
  borders, the landing itself fires none.
- **A row before you have met him:** an objective that names nobody - a trophy, as bounties have them -
  gets a guess. A bounty names its mob in the title (`WANTED: Bruuz`), a trophy names its owner
  (`Besseleth's Fang`; `Serena's Head` in the quest "Serena Bloodfeather", where the title has the whole
  name). The row's tooltip says it is a guess; the mob's own tooltip replaces it with the real name. Only a
  single trophy counts (`0/1`), and a guess that fits nobody targets nobody.
- **Twelve rows fit. When more want in**, the quest you picked in the tracker keeps its rows, then the
  nearest quests where the client gives distances (`C_QuestLog.GetDistanceSqToQuest`); a mob nobody knows
  the distance to counts as near, somebody to turn in to as far, and what you lowered waits first. The rows
  that stay keep the tracker's order, and the note beside the title counts the rest (`+3 more`).
- **The quest you picked in the tracker is here**, wherever the map puts it (`C_SuperTrack`).
- **A type-in box at the bottom of the panel:** a name, Enter, and it has a row - on top, marked,
  never cut, wherever you are (`/akt add <name>` does the same). A typed name is a `/target`, not a
  `/targetexact`: the beginning of a name will do, so `Defias` finds the nearest Defias of any kind.
  Right-click the row to take it off
  (`/akt remove <name>`, `/akt typed` lists them). The box keeps the panel up with nothing to target;
  `/akt typein off` takes it away.
- Tracked quests only: what is in your quest tracker is what gets rows. Drag the panel by its title.

`/akt` lists the commands: `on`, `off`, `mark on|off`, `menu`, `zone on|off`, `flightmaster on|off` (a row for the
zone's flight master, learned when you open the taxi map; off by default), `hidden`, `unhide`, `reset`, `status`, `forget`, `diag`.

## In a dungeon: the bosses and the rare spawns (0.2.0)

Zone into a dungeon or raid and its bosses appear as rows **on top of the panel**, in order, with the known
rare spawns after them - each the same secure `/targetexact` button as a quest row, with a marker, and part
of the any-target key after the quest mobs. Forever does not load the Adventure Guide, so the client has no list to ask; the
addon carries one (`Dungeons.lua`: the instances by map id, with the name as fallback), and what your group
actually meets corrects and extends it: a rare (`UnitClassification` rare / rareelite) or a skull-level boss
seen on your target, under the mouse or on a party member's target is remembered for that instance. A
5-man boss with an ordinary level looks like elite trash to an addon, which is why the list exists. A boss that
dies is **crossed off** - a line through its name, the row dimmed and sorted last - so the panel doubles as
"what is left". The death is heard from the client's own encounter events (`ENCOUNTER_END`, `BOSS_KILL`)
and from a dead boss on your target, under your mouse or on a party member's target; a `/reload` keeps
the marks, walking in afresh clears them. `/akt dungeon list` prints what is known about where you are, `/akt dungeon
off` turns the rows off.

Inside, the panel is about the dungeon and nothing else: its bosses and rares first, the mobs of the
dungeon's own quests below them, the dead below those. A quest is the dungeon's own when the dungeon's map
carries it or - this client will not say which map you are on in there, measured in the Wailing Caverns -
when the client tags it as a dungeon or raid quest (`C_QuestLog.GetQuestTagInfo`). Every other quest counts
as elsewhere, and so does a quest ready to turn in: its NPC is outside. A quest that is after a boss takes
no second row. Twenty rows fit (twelve out in the world); `/akt zone off` shows everything, in here too.
Markers go to the quest mobs first (the trash you pull), then to the bosses in order; the dead give theirs
back.

The instance is recognised three ways, because a beta client need not agree with itself: `IsInInstance()`,
the instance's own type from `GetInstanceInfo()`, and the world map under your feet (a dungeon's map by a
name on the list). `/akt dungeon list` says which one knew; out of any instance it prints what the client
says about where you are, and the same goes into the log (`dungeon_where`) whenever the answer changes.

**The cave in front of an instance** is not the instance, and has rare spawns of its own: Trigore the
Lasher and Boahn before the Wailing Caverns portal, Marisa du'Paige and the Brainwashed Noble in the mine
before the Deadmines, Digmaster Shovelphlange in the dig before Uldaman. Out in the world, where the subzone
carries the instance's name, they are rows after the quest rows.

**Quest hints** are for the mobs no tooltip will ever name: Mad Magglish, who holds the 99-Year-Old Port,
stands stealthed in the Wailing Caverns cave. The quest is "Trouble at the Docks" and the bottle its one
objective; a hint is found by either, so `/akt hint add 99-Year-Old Port = Mad Magglish` - built in - is
what it looks like. `/akt hint add <quest title or objective> = <mob>` teaches more, `/akt hint list` and
`/akt hint remove <title or objective>` manage them.

## How it stays out of Blizzard's way

Targeting and marking are protected actions, and this client compiles no secure snippets.

- Every target / mark is done by **Blizzard's own secure code**: the rows and the menu's cells are secure
  action buttons running a macro (`/cleartarget`, `/targetexact <name>`, `/tm [exists,nodead] !8`,
  `/targetlasttarget [noexists]`). The current target is put aside first and taken back when nobody of that
  name was found, so a click with no such mob around changes nothing and a marker can only land on a mob
  we asked for. `!` keeps a second click from toggling the marker off.
- **Nothing of Blizzard's is touched.** The rows come from the quest log API (the tracked quests, their
  objectives, who is ready to turn in) and live in our own panel. The first design put buttons into the
  quest tracker itself; this client refuses to anchor a protected frame to the tracker's lines (`Cannot
  anchor protected frames to regions`, seen in game on 2026-09-21), and buttons placed at the lines' screen
  positions could not follow them in a fight - hence the panel.
- Protected frames (the rows, the panel, the menu) are created, placed, shown, hidden and given their macro
  **only out of combat**. In a fight only what is not protected changes: the counts and names on the rows,
  and a row whose objective is done goes dim; a row for something new waits for the end of the fight.
- **The marker menu** is ours out of combat (Lua may show, hide and move a protected frame there) and
  Blizzard's **state driver** in combat - the one snippet-free way to show a protected frame in a fight.
  Its condition carries `[combat]` on both halves (`[combat,mod:alt] show; [combat] hide`), so out of combat
  the driver decides nothing and can never take the menu away while we hold it open.
- **The right mouse button is ours**: each row's `type2` is Blizzard's `ATTRIBUTE_NOOP`, so a right-click runs
  no secure action and the addon's own click handler hides or lowers the row instead. In a fight a hidden row
  only goes dim (hiding a protected frame waits for the end of the fight), a lowered row moves afterwards.
- **The any-target key** is a plain key binding that clicks an invisible secure button of ours - a hardware
  click is all a secure button needs. Its macro tries every name on the panel with `/targetexact [noexists]`,
  so the first one found stays the target, and marks with `/tm ~N` (only a mob without a marker gets one).
- Event-driven: the quest log's events book one update on the next frame, however many fire at once. No
  timers, no polling.

## Tests

```powershell
lua tests/run.lua
```

`tests/wowmock.lua` is a strict stand-in for the client: it fails a scenario on any Lua error, on a field
written onto one of Blizzard's frames, on any protected frame of ours touched in combat, and it refuses
what the client refuses (no secure snippets, no anchoring of protected frames to unprotected ones). The
four macro commands and the state driver are modelled *as we understand them* - passing tests prove the
logic, not those assumptions. Those are what the next section is for.

## Open questions to test in the beta (experiment 2)

Run through these, then `/akt diag`, `/reload`, and the report is in
`WTF/Account/<account>/SavedVariables/AKForeverTargeter.lua` (`AKForeverTargeterDB.diag`).

1. Does the panel appear (right edge, middle) with a row per kill objective, name and count? Drag it by its
   title: does it stay where you dropped it after `/reload`?
2. Click a row: is the mob targeted and marked? With no such mob around, does your target stay?
   (`click` entries in `diag.log`.)
3. Kill quest mobs in combat: do the counts on the rows follow? When an objective finishes mid-fight, does
   its row go dim and vanish after the fight? Any "action blocked" popup? (`diag.blockedActions`.)
4. Mouse over a mob that drops a quest item: does its objective get a row? (`diag.tooltipSamples`.)
5. Accept a quest from an NPC, finish it: is there a row with the "?" for him (`diag.givers`)? For a quest
   accepted before this version: does its "Return to ..." line give a usable name (`diag.quests[].giverNames`)?
6. Hold Alt: does the menu appear at the mouse, mark, and go on release - and in combat at the screen's
   centre? Does a click on a cell with Alt held mark the target? Does the key binding toggle it out of combat?
7. Bind "Target any of them": with two quest mobs around, does it target the one higher on the panel and
   mark it with that row's marker? With none around, does your target stay?
8. Right-click a row: does it vanish without targeting anything? Shift + right-click: does it go last?
9. Walk out of a zone whose quest you are tracking: does its row go, and does the title say "1 quest
   elsewhere"? Walk back: does it return with its marker? (`diag.quests[].here` says what the client thinks.)

## Saved settings on the Forever beta

Learned mobs, givers and the dungeon lists are account-wide; the panel's place and the switches are saved
per character, under the character's full name and realm, and come back on your next login. Client build
1.60.1.70170 (Oct 1 2026) reads addon settings back again; it also moved a character's surname into the
realm slot of `UnitName`, which split profiles for a day. Profiles saved under either spelling, and those
of a cold login, are folded into one the first time each character logs in (`/akt diag` says what was
adopted). The saved-settings bridge of the earlier beta builds (`tools/Install-SavedStateBridge.ps1`) is
no longer needed: run it with `-Remove`.
