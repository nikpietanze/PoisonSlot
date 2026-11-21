# Changelog

## 1.0.2

- Clicking a reminder now reapplies the last poison you put on that weapon, however you applied it (bags, action bar or PoisonSlot). Until a weapon has been poisoned once, it still uses that hand's favorite. Right-clicking a vial still applies the favorite.
- `/pslot status` shows each hand's last poison.

## 1.0.1

- Shift-right-click a reminder to silence it until you poison that weapon again or log out. Handy when you're out of poisons.
- Reminder countdowns no longer get a second number from OmniCC-style cooldown text addons like OmniCC or ClassicCooldownCount.

## 1.0.0

First release.

- Poison vial on each weapon slot of the Character panel. Left-click it for a tray of the poisons in your bags, and click one to apply it to that hand.
- One favorite per hand, set with the star on each poison. Right-click the vial to apply the favorite.
- Reminder tiles for each hand. They count down the last 10 seconds of a poison (red with tenths at the end), then glow until you fix it. A single tile is centered, and two spread out evenly around the middle. Left-click a tile to apply that hand's favorite; right-click snoozes it until the next loading screen.
- Blizzard Edit Mode support for moving and sizing the reminders, with positions saved per Edit Mode layout.
- Addon compartment entry: left-click for options, right-click to preview.
- Reminders stay quiet in rested areas, while dead and on flight paths.
- Native options panel where nearly every feature is a setting: reminders on or off, each hand, the countdown, click-to-apply, quiet in towns, hide in combat, a run-out sound (with SharedMedia sounds), icon size, spacing, layout, missing glow style, status text, hand badges, the weapon-slot vials and their right-click, animations and tooltips. Preview, Move and Reset buttons included.
- `/pslot status` prints details for bug reports.
