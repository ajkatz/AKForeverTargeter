# Marketplace listing text (copy / paste)

**Name:** AKForeverTargeter
**Category:** Quests & Leveling (second: Boss Encounters)
**Game version:** World of Warcraft: Forever (1.60.1)
**License:** MIT
**Summary (one line):** A "Targets of interest" panel beside the quest tracker: one secure button per quest mob, dungeon boss and rare - target it, mark it, in and out of combat.

## Description

*Part of a small family of addons built for the WoW: Forever game mode, with one mission: minimalistic UI additions that bring out the utility
Blizzard's UI does not give - minimal in nature, no Lua errors, always smooth.*

Quest targeting for World of Warcraft: Forever (Interface 16001): a small "Targets of interest" panel beside the quest
tracker, with one row for every mob your tracked quests want - and, in a dungeon, its bosses and rares. Click a row and
Blizzard's own secure code targets it - and, with marking on, puts that raid marker on it - in and out of combat.

### What it does

- **Targets of interest.** One row per mob of a kill objective (`0/14 Venture Co. Worker slain` names its mob, in any
  language the client speaks), per mob learned for a collect objective, and - for a quest ready to turn in - the NPC to
  bring it back to, remembered as you accepted the quest. Each row shows its marker, the name and the count (`3/10`).
  Optionally the zone's flight master (`/akt flightmaster on`), learned when you open the taxi map.
- **No mob database.** For a collect objective the addon learns the mob the first time you mouse over or target one
  whose tooltip shows that objective. A bounty or a trophy quest gets a guessed row from its title until the mob is met.
  A quest whose tooltips never name the mob can be told by hand (`/akt hint add 99-Year-Old Port = Mad Magglish`).
- **In a dungeon: the bosses and the rare spawns.** Zone in and the instance's bosses appear on top of the panel, in
  order, with the known rares after them - the same secure buttons, with markers. Forever does not load the Adventure
  Guide, so the addon carries the list (every Classic dungeon and raid, and Forever's own: Excavation Site: Wetlands,
  Ruins of Lordaeron, Hall of Thanes, City of Dalaran), and what your group meets corrects and extends it. A boss that
  dies is crossed off, so the panel doubles as "what is left". Inside, only the dungeon's own quests get rows.
- **A type-in box** at the bottom of the panel: a name, Enter, and it has a row on top - the beginning of a name will
  do, so `Defias` finds the nearest Defias of any kind. `/akt add <name>` does the same.
- **One key for any of them** (Key Bindings > AddOns > AKForeverTargeter): targets the first name on the panel that is
  around, in the panel's order, and marks it with its row's marker unless it already carries one. Quest givers come
  last and are never marked.
- **A marker menu.** Hold the modifier and a 3 x 3 grid appears at the mouse - the eight markers around a clear button
  - for your current target. Left-click a cell to mark, right-click any cell to clear. A lone Alt, Ctrl or Shift is
  everybody's combo key, so it can be a pair: `/akt menu mod alt-shift`. Out of combat the menu stays until you pick or
  click elsewhere; in combat Blizzard's state driver shows it while you hold the keys, at its own spot.
- **Not now.** Right-click a row to hide it, Shift + right-click to put it last; the note beside the title counts what
  is hidden, and a right-click on the panel brings every hidden row back.
- **Only what is here.** A tracked quest whose business is on another map takes no row; the note says how many are
  waiting elsewhere (`/akt zone off` shows them all). Twelve rows fit: the quest you picked in the tracker keeps its
  rows, then the nearest. Tracked quests only; drag the panel by its title.

### Commands

`/akt` lists them: `on`, `off`, `mark on|off`, `menu` (`menu mod`, `menu sticky`, `menu spot`), `zone on|off`,
`flightmaster on|off`, `dungeon on|off|list`, `add <name>`, `remove <name>`, `typed`, `typein on|off`,
`hint add|list|remove`, `hidden`, `unhide [n]`, `reset`, `status`, `forget`, `diag`. `/akt diag` writes a report into
the settings file for bug reports (then `/reload`).

### How it stays out of Blizzard's way

Targeting and marking are protected actions, and this client compiles no secure snippets - so every target and mark is
done by Blizzard's own secure code: the rows and the menu's cells are secure buttons running a macro (`/targetexact`,
`/tm`, `/target` for a typed name). Nothing of Blizzard's is re-parented, hidden or unregistered; protected frames are
only ever anchored to the screen and to the panel itself, and are created, placed and shown only out of combat. In a
fight only what is not protected changes: the counts and names on the rows, and a finished objective's row goes dim.
Event-driven, no timers. Settings and what was learned are saved per character.

### Source and bug reports

MIT licensed. Code, issues and the changelog: https://github.com/ajkatz/AKForeverTargeter

## Logo and screenshots

Logo (400 x 400): `..\ForeverBranding\out\AKForeverTargeter\logo-400.png` (master: `logo-1024.png`).
Screenshots to take in game: the panel beside the tracker with a few quest rows; the panel inside a dungeon with the bosses on top; the marker menu.
