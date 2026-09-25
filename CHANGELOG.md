# AKForeverTargeter

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
