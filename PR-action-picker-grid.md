# Compact layout (tile grids), trigger icons and names

## What
**Compact layout.** Triggers, Select Action and Settings > Banners can each show a grid of tiles instead of a list. Choose it in Advanced Settings > Layout. List stays the default.
- **Select Action and Banners:** each tile shows an icon over its name. An action that opens another screen has a small chevron. A banner in Enabled is tinted and checked.
- **Triggers:** cards with the icon beside the name. Layout options:
  - Triggers per Row: 2, 3 or 4
  - Compact Sections: Show or Hide (hidden puts every trigger in one grid)
  - Category Bar Lines: 1, 2 or 3

  A trigger with no actions is dimmed. Tap a tile to open it, or long press to run it. Edit, at the top left, adds a star (favorite) and a minus (delete, asked first) to each tile. Favorites can be dragged to reorder.

**Trigger icons.**
- **Button and gesture triggers:** drawn as a tiny phone. The pressed button, or the touched part of the screen, is marked, and the phone's middle shows what happens: 2x, a clock for a hold, + for two buttons.
- **App Launch and App Exit:** show the app's icon, with a green checkmark or a red x at the top right.
- **Category chips and section titles:** each has an icon.
- **Created triggers:** NFC tags, networks and devices get a small letter, so several of one kind can be told apart.
- **Old iOS:** the phone drawings are made in code, so they look the same on every iOS. Newer symbols fall back to older ones on older iOS.

**Trigger names.**
- Created triggers can be renamed from their ••• menu. The default name still shows under the new one. Built-in triggers such as Power Double Click keep their names.
- A new created trigger offers a Name field at the top of its screen.
- Screen Gestures is renamed Status Bar.

**Category bar.**
- Tapping the selected category again goes back to All, and the bar stays where it is.
- In landscape, the grids and the bar keep clear of the Dynamic Island.

**Web UI:** the same names, icons, letters, section icons and app badges. The trigger settings sheet gets Keep Default Action.

## How
- **Tiles:** `RCActionTile` draws a tile and stores the Layout settings. `RCTriggersGrid` is the Triggers collection view, and `RCTriggerIcons` draws the phone pictures.
- **Shared icons:** `iconImageForTrigger:size:` gives a trigger's icon, so other screens can show the same one.
- **Category bar:** `RCCategoryBar` places chips on up to three lines.
- **Names:** a trigger's own name is stored apart from its default and from a created trigger's details, so editing the trigger keeps it. Changing an App Launch or App Exit trigger's apps now keeps its name, settings and favorite.
- **iOS 14 crash fix:** Select Action registers its cells before attaching the category bar. iOS 14 aborted when the grid was laid out before then.

## Tested
iPhone 15 (iOS 17.0, rootless) and iPhone 8 (iOS 14.3, rootful).

| | iPhone 15 | iPhone 8 |
|---|---|---|
| Triggers in List and Compact: 2, 3 and 4 per row, Compact Sections Hide | Works | Works |
| Category bar: 1, 2 and 3 lines; tap the selected category for All | Works | Works |
| Edit: star, minus, drag favorites; long press runs a trigger | Works | Works |
| Icons: phone drawings (incl. Home button and Touch ID), Shake, Watch, categories, app badges | Works | Works |
| Rename a created trigger; Name field on a new one; no Rename on built-in ones | Works | Works |
| Select Action and Banners as tiles | Works | Works (crashed on opening before the fix) |
| Landscape grids | Clear of the Dynamic Island | Nothing cut off |
| Web UI: names, icons, badges, Keep Default Action | Works | Works |
| With all seven open PRs merged: chevrons on Repeat and Set Variable, Rename first in •••, Stop Trigger list, Running page icons | Works | Works |

## Merging
Merges cleanly with every other open PR (#104, #106, #108, #109, #111, #112), in any order: I merged them in all 720 orders, with no conflicts and the same code each time, and the result builds. Rename's line in the ••• menu sits at the end of the menu's code (it still shows first), so it doesn't touch the line #104 changes.

The last commit writes the Triggers list's plain-symbol line the way #106 does, so the two merge without a conflict.

After this and #112 (Find My Sound) are both in, Find My Sound needs adding to the Web UI's Keep Default Action list, with "on" as its default, as in the app. That's a two-line follow-up, not a conflict.
