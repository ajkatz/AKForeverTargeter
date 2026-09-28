# AKForeverTargeter

## 0.2.0

- **In a dungeon or raid, the bosses and the rare spawns are rows** the moment you zone in: a built-in
  list of the instances with their bosses in order and their known rares (`/akt dungeon list` prints it,
  `/akt dungeon off` turns it off). Forever does not load the Adventure Guide, so the client has no list to
  ask; what your group meets corrects and extends it - a rare or a skull-level boss seen on your target,
  under the mouse or on a party member's target is remembered for that instance. A boss that dies is
  crossed off - a line through its name, dimmed, sorted last - so the panel doubles as "what is left";
  heard from the client's encounter events and from a dead boss on anybody's target. A `/reload` keeps
  the marks, walking in afresh clears them. Bosses and rares are marked like quest mobs and join the any-target key after them.
- **Quest hints** for the mobs no tooltip will ever name: Mad Magglish, stealthed in the Wailing Caverns
  cave with the 99-Year-Old Port, is built in; `/akt hint add <quest title> = <mob>` teaches more.

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
