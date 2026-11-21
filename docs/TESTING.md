# In-game test checklist

Run through this list before tagging a release. Start out of combat on a Rogue with two eligible weapons and at least two different poisons in your bags. Note your client build from `/pslot status`, and keep BugSack open.

PoisonSlot's logic is covered by a mocked-client test outside the game, but secure actions, animations and layout need a real client.

## Weapon slots

| Check | Expected result |
|---|---|
| Vials | Each eligible weapon slot shows a gold-ringed vial on its top-right corner. The rest of the slot keeps its normal clicks and tooltip. |
| Tray | Left-clicking a vial unfolds the poison tray below it. Clicking a poison applies it to that hand only. |
| Stars | Starring a poison makes it that hand's favorite. Starring it again clears it. Main hand and off hand stay independent across `/reload`. |
| Stand-in star | Star a rank, then remove it from your bags while keeping another rank of the same poison. The tray shows the other rank with a faded star, and its tooltip says it's standing in. Starring it makes it the real favorite. |
| Right-click | Right-clicking a vial applies that hand's favorite. With no favorite, nothing happens at all. |
| Combat | Open the Character panel in combat. The vials stay on the slots, dimmed and gray-ringed, and the tooltip says poisons can't be changed in combat. Clicking them does nothing and raises no errors. An open tray closes when combat starts. |
| Setting | Turning off **Poison buttons on weapon slots** hides both vials. Turning off **Right-click vial to apply favorite** makes right-click do nothing. |

## Reminders

| Check | Expected result |
|---|---|
| Missing | Outside a rested area, a weapon with no poison shows a tile for that hand. It fades in and its glow breathes gently. |
| Countdown | In the last 10 seconds of a poison, the tile shows a swipe and a number counting down. At zero, the glow flares once and the tile switches to **Missing**. |
| Click to apply | With a favorite set, hovering the tile turns it green and shows the poison. Clicking it applies the poison to that hand only. The tile fills green during the cast, then flashes and lifts away. |
| No favorite | Without a favorite, clicking the tile does nothing. |
| Fallback rank | Remove the favorite's exact rank but keep another rank of the same poison. The tile applies that rank. With no rank of that poison left, the tile isn't clickable. |
| Rested | Entering a town or inn hides the tiles. Leaving brings them back right away. |
| Combat | No `ADDON_ACTION_BLOCKED` or `ADDON_ACTION_FORBIDDEN` errors. A tile that appears mid-fight becomes clickable once combat ends. |
| Options | Preview, Move (drag, then Lock or right-click), Reset and the size slider all work. Entering combat while moving locks the tiles. |
| Edit Mode | **Move** opens Edit Mode with both tiles previewed and a blue selection box labeled "PoisonSlot Reminders". Dragging saves. Selecting it opens a dialog with Icon size, Spacing, Layout, Missing glow, Status text, Hand badges, Reset Position and More options. Switching Edit Mode layouts moves the tiles to that layout's spot. |
| Glow | A Missing tile shows the action bar proc glow, looping at the tile's size from the first frame with no oversized burst. Pixel, Soft pulse and None all switch live. |
| Countdown | In the last 5 seconds the number turns red, gets bigger and the icon pulses. Under 3 seconds it shows tenths. |
| Snooze | Right-clicking a tile hides it. It stays hidden until a loading screen, or until that weapon is poisoned and runs out again. Tiles without a favorite still snooze. |
| Silence | Shift-right-clicking a tile hides it through loading screens. It comes back only after that weapon is poisoned and runs out again, or after a `/reload` or logout. The other hand's tile is unaffected. |
| Centering | A lone reminder sits in the middle of the screen. When the second one appears, the two slide apart to sit evenly around the middle, and slide back when one goes away. Vertical layout does the same up and down. |
| Centering in combat | In combat, a tile that's already showing doesn't move. A new one appears right next to it. After combat they slide back to center, and clicking still hits the tile you see. |
| Hide in combat | With it on, the tiles vanish the moment combat starts, with no errors, and come back after. |
| Compartment | The PoisonSlot entry in the minimap addons menu opens options on left-click and previews on right-click. |
| Toggles | Each setting takes effect immediately: Show reminders, Main hand, Off hand, Countdown, Click to apply, Sound, Quiet in towns, Status text, Hand badges, Animations (tiles and tray appear instantly), Tooltips. Children gray out when Show reminders or Poison buttons is off. |
| Sound | With the sound on, a poison wearing off plays one alert. Logging in with no poison, or leaving town, stays silent. |
| Migration | A character saved with the old "Missing only" mode loads with Countdown off; "Off" loads with Show reminders off. |

## Needs confirming on a live client

- Reminder tiles apply poison through a secure `item:<id>` action with `target-slot`. The weapon-slot vials use a bag and slot instead, which has already been tested in game.
- Each reminder tile has a click layer anchored to the reminder frame. That frame stays put during combat.
- Child options use `SetParentInitializer` to gray out under their parent checkbox. If this client's settings list doesn't support it, they stay enabled but still work.
- Built-in sounds play by `SOUNDKIT` key on the Master channel. A key missing on this client plays nothing.
- LibEditMode lists Interface 16001 as supported. If it errors on this client, PoisonSlot falls back to its own mover (`/pslot unlock`).
- The proc glow needs the `UI-HUD-ActionBar-Proc-Loop-Flipbook` atlas. Without it, the glow falls back to the pixel border.
- Reminder left-click uses `type1`/`item1`/`target-slot1`, the same suffix pattern as the vial's right-click, which works in game.
