# AKForeverTargeter

## 0.2.1

- **The living come first.** A name whose nearest bearer is a corpse no longer counts as found: a row and
  the any-target key let go of it (`/cleartarget [dead]`) and try the next name, so a dead mob at your feet
  does not stand in the way of a living one further down the list - and a corpse is never left targeted
  in place of something alive. What no macro can do is pass over a corpse for a living mob of the *same*
  name: `/targetexact` takes the nearest one.
- **A typed name is a `/target`**: the beginning of a name will do. `Defias` in the type-in box finds the
  nearest Defias of any kind; a full name still finds exactly that mob. Everything the addon works out
  itself - a quest's mob, a boss, somebody to hand a quest in to - is still asked for by its exact name.
- **Settings follow the character again.** Client build 1.60.1.70170 (Oct 1 2026) moved a character's
  surname into the realm slot of `UnitName`, so every character started a fresh, empty profile. The profile
  is now keyed by the full name and the realm (`Purrdee Bubson - ClassicBetaPvE`, the spelling the older
  builds saved under) and bound at PLAYER_LOGIN, when the client knows the name for sure, so a cold login no
  longer lands in an `Unknown` profile. Profiles saved under the other spellings are folded into it the
  first time each character logs in: the long-standing profile keeps its values, the others fill its gaps,
  and `/akt diag` says what was adopted.
- The same client build reads saved settings back again, so the saved-settings bridge
  (`tools/Install-SavedStateBridge.ps1`) is no longer needed and `-Remove` takes it out.

## 0.2.0

- **In a dungeon or raid, the bosses and the rare spawns are rows** the moment you zone in, **on top of
  the panel**: a built-in list of the instances with their bosses in order and their known rares
  (`/akt dungeon list` prints it, `/akt dungeon off` turns it off). Inside, the panel is about the
  dungeon and nothing else: of your quests only the dungeon's own get a row, below the bosses - what its
  map carries, or what the client tags as a dungeon or raid quest, since this client will not say which
  map you are on in there. A quest ready to turn in waits outside with its NPC, and a quest after a boss
  takes no second row. Twenty rows fit instead of twelve; `/akt zone off` shows everything. Forever does not load the Adventure Guide, so the client has no list to
  ask; what your group meets corrects and extends it - a rare or a skull-level boss seen on your target,
  under the mouse or on a party member's target is remembered for that instance. A boss that dies is
  crossed off - a line through its name, dimmed, sorted last - so the panel doubles as "what is left";
  heard from the client's encounter events and from a dead boss on anybody's target. A `/reload` keeps
  the marks, walking in afresh clears them. Bosses and rares are marked like quest mobs and join the any-target key after them;
  the markers go to the quest mobs first, and the dead give theirs back.
- **The cave in front of an instance** has rare spawns of its own - Trigore the Lasher and Boahn before
  the Wailing Caverns portal, Marisa du'Paige and the Brainwashed Noble in the mine before the Deadmines,
  Digmaster Shovelphlange in the dig before Uldaman. Out in the world, where the subzone carries the
  instance's name, they are rows after the quest rows.
- The instance is recognised three ways (`IsInInstance`, the instance's own type, a dungeon's world map by
  a listed name); `/akt dungeon list` says which one knew, or - out of any instance - what the client says
  about where you are.
- The end of a flight re-reads the map. In the air the zone events fire at the borders, but landing fires
  none, so the rows of the zone you took off from stayed until the next quest event.
- **Quest hints** for the mobs no tooltip will ever name: Mad Magglish, stealthed in the Wailing Caverns
  cave with the 99-Year-Old Port (the quest is "Trouble at the Docks"), is built in;
  `/akt hint add <quest title or objective> = <mob>` teaches more.
- **A row before you have met him.** A bounty names its mob in the title (`WANTED: Bruuz`) and a trophy
  names its owner (`Besseleth's Fang`; `Serena's Head` in the quest "Serena Bloodfeather"). An objective
  that names nobody gets that name as a guess - the row's tooltip says so - until the mob's own tooltip
  has taught the real one.
- **When more rows want in than fit**, the ones that wait are no longer simply the last in the tracker:
  the quest you picked in the tracker always keeps its rows, the nearest quests stay where the client
  gives distances, and somebody to turn in to gives way before a mob does. The note beside the title
  counts them (`+3 more`).
- **The quest you picked in the tracker is here**, wherever the map puts it.
- **A type-in box at the bottom of the panel**: a name, Enter, and it has a row - on top, marked,
  never cut, wherever you are. Right-click the row to take it off; `/akt add`, `/akt remove`, `/akt typed`,
  `/akt typein off`.
- `/akt diag`: the report you asked for is kept (the one taken at logout, with the world already coming
  down, goes beside it), and it carries the panel's last pass quest by quest - here or not and why, what
  each objective names, which rows did not fit.

## 0.1.0 - first public release

For **World of Warcraft: Forever** (1.60.1, Interface 16001).

A small "Targets of interest" panel beside the quest tracker: one row for every mob your tracked quests
want, each a secure button that targets it - and, with marking on, marks it - in and out of combat.

- Rows for the mobs of your **kill objectives** (from the objective's own wording, in any language the
  client speaks), the mobs **learned from tooltips** for collect objectives, and - for a quest ready to
  turn in - its **quest giver**, remembered as you accepted the quest. Optionally the zone's **flight
  master** (`/akt flightmaster on`), learned when you open the taxi map.
- **One key** (Key Bindings > AddOns > AKForeverTargeter) targets whichever of them is around, in the
  panel's order, skull then cross.
- A **marker menu** at the mouse on a secure key, respecting your own keybinding; `/akt mark off` if
  the rows should only target.
- **Right-click a row** to hide it, Shift + right-click to put it last; a right-click on the panel
  brings every hidden row back. A note beside the title counts what is hidden or waiting in another
  zone (`/akt zone off` shows them all).
- The panel wears Blizzard's own tooltip backdrop, is dragged by its title, and remembers its place -
  through the saved-settings bridge this beta client needs.
- Nothing of Blizzard's is re-parented, hidden or unregistered; protected frames are only ever anchored
  to the screen and to our own panel, which is what this client allows.
- `/akt` lists the commands; `/akt diag` writes a report for bug reports.
