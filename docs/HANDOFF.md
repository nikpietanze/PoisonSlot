# Engineering Handoff: Rogue Poison Slot Addon for WoW Forever

**Status:** Implementation-ready specification; API-dependent mechanics require an in-game technical spike  
**Target:** World of Warcraft: Forever (1.60.1 / Interface 16001; verify against installed client)  
**Platform:** WoW addon (Lua + optional XML), no external executable or dependencies required  
**Working name:** PoisonSlot (temporary; rename before release)  
**Design principle:** *No additional action bar, no separate permanent window. Weapon-slot controls that feel native to Blizzard's character panel, plus optional minimal reminders.*

## 1. Mission

Create a lightweight, open-source Rogue addon for WoW Forever that adds a small clickable poison icon to the **main-hand** and **off-hand** weapon slots in the default Character/Equipment panel.

The user should be able to:

1. **Left-click the small icon** for a particular hand to open a menu of poisons **actually in their bags**.
2. **Left-click a poison entry** to apply that poison to the clicked weapon, if the game's secure-action API permits a true one-click operation.
3. **Click a star on a poison entry** to favorite that poison **for the selected hand**; MH and OH favorites must be independent.
4. **Right-click that hand's small icon** to immediately apply the favorite poison for that hand, using one real user click and a secure action where permitted.
5. Receive an **unobtrusive warning** when a weapon's poison is missing or near expiration, even with the character panel closed (optional, configurable HUD reminders).

**Avoid** implementing a floating poison bar, intrusive sound notifications, unrelated Rogue utilities, crafting/restocking workflows, or background automation.

## 2. Primary UX contract — non-negotiable

| User interaction | Expected result |
|---|---|
| Left-click small poison icon on MH slot | Open MH-specific poison dropdown anchored to MH weapon slot |
| Left-click small poison icon on OH slot | Open OH-specific poison dropdown anchored to OH weapon slot |
| Left-click a poison entry | Apply that exact poison to the chosen hand through an authorized player-initiated action; close menu on success |
| Click the star next to a poison | Set or unset **that hand's** preferred poison family; reflect the star immediately |
| Right-click MH icon | Apply MH favorite to **main hand only** |
| Right-click OH icon | Apply OH favorite to **off hand only** |
| Right-click when no favorite exists | **Do absolutely nothing** — no dropdown, no tooltip, no message, no sound, and no poison action |
| Favorite is missing from bags | Do **not** substitute a different poison type; show a small message/tooltip and optionally open menu |
| Weapon slot empty, item ineligible, or user not Rogue | Hide or disable appropriately; never cast on a different slot |
| Poison expired/missing | Display subtle warning for that hand (if reminder mode enabled) |

**Distinct click regions:** The small poison button is separate from Blizzard's underlying equipment-slot click handling. Clicking elsewhere on the weapon slot retains stock equipment interactions. The star is a distinct hit target inside the dropdown, not another way to apply the poison.

### Favorite semantics

- Persist **one favorite poison family per hand** (e.g., `Instant Poison` for MH, `Crippling Poison` for OH), rather than saving an unstable bag slot.
- If a family has several ranks, **use the highest usable rank currently in the bags by default** for quick-apply. Clearly show which rank will be used in the tooltip/menu; manual selection of a specific rank should be possible in the dropdown.
- If a favorite rank/family cannot currently be used (level requirement, out of stock, incompatible weapon), don't apply a different family. Show an actionable, concise reason.
- Favoriting a new family for a hand replaces only that hand's favorite. Star-clicking the already-favorited family removes the favorite.
- Persist data per character through SavedVariables. Do not couple favorites to item instance IDs or bag positions.
- Right-click with **no favorite configured for the clicked hand** must be a true, silent no-op (no dropdown, tooltip, toast, sound, error text, or application attempt). A favorite on the other hand does not count.
- Right-click does **not** bypass casting times, item requirements, replacement confirmations, or protected gameplay rules.

## 3. Proposed UI

### 3.1 Weapon-slot overlays

Add a **small 16–20 px poison-vial icon** anchored to a corner of each weapon's equipment slot (suggest bottom-right initially; test against existing enchant overlays, durability overlays, item levels, and other addons). It should be visible only on Rogue characters with an eligible equipped weapon.

**Visual states** (favor readability and native UI appearance):

- Normal: muted vial icon, minimal background.
- Favorite present: tiny star accent or favorite poison icon; tooltip identifies the family and resolved rank.
- Active poison healthy: small unobtrusive status cue; no constant animation.
- Poison missing: amber/red border or small dot on that hand.
- Poison expiring soon: amber dot or subtle countdown; no flashing by default.
- Unavailable favorite: muted icon with tooltip, no misleading success feedback.

Do not obscure the actual weapon icon, quality border, or tooltip. The icon is a **control**, not a second equipment-slot-sized button.

### 3.2 Dropdown menu

A compact menu beside the clicked weapon slot, using client-native visual language:

```text
Main Hand — Poisons
──────────────────────────────
[icon] Instant Poison IV      ×12  ★
[icon] Deadly Poison II        ×8  ☆
[icon] Crippling Poison        ×5  ☆
──────────────────────────────
Right-click the corner icon to apply ★ (no favorite = no action)
```

- The list shows **craftable poison items in bags, not poison recipes or reagents**. Items the character has crafted or otherwise acquired are eligible; there is no need to verify provenance.
- Scan bags, consolidate stack counts, group by poison family, display highest eligible rank by default; allow rank selection if multiple ranks are carried.
- Each row shows icon, full localized name/rank, quantity, and a clickable star region. No permanent screen element outside the character pane.
- Invalid/incompatible items should be hidden or clearly disabled with a reason; do not imply they will work.
- Left-click outside, Escape, and switching panels close the dropdown normally.
- Correctly anchor near either weapon slot without going off-screen at unusual UI scales.

### 3.3 Minimal reminders with character panel CLOSED

Provide **two tiny independent hand indicators**, defaulting to **only visible when missing or expiring**, and configurable through `/pslot` or addon options:

- Label with `MH` / `OH` or a small hand-specific overlay to prevent ambiguity.
- Missing = red/amber small vial; near expiry = amber vial with time tooltip.
- Default expiry threshold: 5 minutes, configurable (e.g., 1, 3, 5, 10 minutes).
- Ideally anchored near a small neutral HUD location; user can unlock and drag them, or disable them altogether.
- **No full floating poison bar, no spammy chat notices, no flashing or sounds by default.**
- If the game cannot distinguish types reliably, avoid inventing precise labels; use accurate available status and explain limitations.
- Reminder clicks may optionally open the character panel, but must not silently cast or auto-apply.

### 3.4 Settings: minimal

Expose only core settings initially:

- Reminders: off / missing only / missing + expiring (**default**).
- Expiration threshold in minutes.
- Move/reset the small reminder indicators.
- Optional hide poison controls when no eligible weapon is equipped.

Do not build a settings framework before the core interactions function.

## 4. Expected behavior in common scenarios

1. **MH Instant, OH Crippling:** Open menu on MH, star Instant. Open menu on OH, star Crippling. Right-click MH and OH icons separately to coat their respective weapons.
2. **No favorite:** Right-click is a silent no-op: no menu, prompt, notification, or item use. Left-click remains the only way to open the dropdown and set a favorite.
3. **No inventory:** Menu shows `No poisons in bags`; favorites remain saved; quick apply does nothing except provide feedback.
4. **Favorite depleted:** Saved preference stays, but the icon indicates unavailable. It should work again automatically once the user obtains that poison.
5. **New rank learned:** Favorite family remains stable; quick-apply resolves to the best eligible rank currently carried. The dropdown identifies that rank.
6. **Weapon changed:** Re-read that hand's equipment/enchant state. Favorite selection should persist; no auto-application.
7. **Weapon unequipped:** Suppress that hand's apply action and avoid a misleading expired-poison reminder.
8. **Manual poison applied outside addon:** Status should update correctly by reading current weapon state, not assuming only addon actions affect it.
9. **Expired while panel closed:** Show warning for the affected hand. Never automatically apply, even if a favorite exists.
10. **Other addons / custom UI:** Do not replace Blizzard's PaperDoll frame, remove another addon’s overlays, or globally replace its click handlers. If character frame is replaced, degrade gracefully.
11. **Combat:** Follow client secure-action restrictions. If updates to secure attributes are prohibited, preserve prepared actions and defer changes; state limitations explicitly. Never attempt protected calls from insecure Lua.
12. **Poison already active:** Quick-apply may prompt/replace according to game rules; prevent unexpected repeated use if possible without violating secure-action requirements. No automatic confirmation of popups.

## 5. Technical architecture

Proposed modules (names illustrative):

```text
PoisonSlot/
  PoisonSlot.toc
  Core.lua                -- initialization, class gate, events, saved variables
  Inventory.lua           -- bag discovery, counts, rank/family resolution
  Equipment.lua           -- slot/enchant state, eligibility, reminders
  SecureActions.lua       -- secure item-use buttons and target-slot configuration
  WeaponSlotUI.lua        -- corner icons attached to PaperDoll slots
  Dropdown.lua            -- inventory-aware list + independent star buttons
  ReminderUI.lua          -- optional tiny HUD warning elements
  Settings.lua            -- slash commands, user preferences
  README.md
  LICENSE
```

**Favor a small codebase** and shared testable state logic, not a big addon framework. Use character-scoped SavedVariables for favorites and user preferences, with migration-safe defaults.

### 5.1 Client compatibility (high priority)

WoW Forever uses a modern/Mainline-derived UI API surface despite the `1.60.1` game version. Do **not** blindly use Classic-era APIs or retail version-number tests. For current client behavior, check `/dump select(4, GetBuildInfo())` and consult the installed client or a recent Forever UI source export.

Relevant inventory slots: **16 main hand**, **17 off hand**. Verify actual named PaperDoll frame and slot globals in the currently installed client; do not hardcode assumptions from an older FrameXML build without inspection.

### 5.2 Bag discovery

- Scan currently accessible bags on relevant bag/inventory events (and login), using client-supported `C_Container`/`C_Item` APIs verified in the current client.
- Include only real poison consumable items found in the player's bags; whitelist by verified item IDs, item spell metadata, or an accurate classification mechanism. Avoid matching on English-only item-name substrings.
- Support localization and asynchronously unavailable item info.
- Track stack count, itemID, current bag/slot, usability, and poison family/rank.
- Recompute secure action targets when bags change, only when permitted by the protected UI environment.
- Do not query bank contents as if available for applying poisons.

### 5.3 Temporary weapon coatings / reminder states

Investigate `C_Item.GetWeaponEnchantInfo(weaponSlot)` in the Forever client (documentation indicates `weaponSlot`: 0=main hand, 1=off hand, 2=ranged) and verify behavior in-game. Cross-check `GetWeaponEnchantInfo()` or other current API only if available. Forever may report **multiple temporary weapon coating types per weapon**; verify poison-vs-stone distinctions and do not mistake an active stone for an active poison.

- Track presence, remaining duration, and charges when actually exposed.
- Distinguish `unknown` from `missing` if item/enchant data is not yet available.
- If using a local countdown, resynchronize against game state regularly but efficiently, avoiding per-frame full bag scans.
- Avoid secret-value operations / taint-sensitive comparisons in combat.

### 5.4 Secure application (most important proof of concept)

**This must be proven on a real Forever client before building most of the UI.** Applying consumable poisons to an equipped weapon is a protected interaction. Insecure `PickupInventoryItem()` calls from addon hooks can produce `ADDON_ACTION_FORBIDDEN`.

Current community API notes describe a viable pattern using a `SecureActionButtonTemplate` with an item action, a bag-slot item reference, and a `target-slot` inventory attribute. For a user's click on a securely prepared button, `target-slot=16` should address MH; `target-slot=17` should address OH. **Validate these mechanics, attributes, click registrations, and practical one-click poisoning on the installed 1.60.1 build.** Do not treat an example on a community wiki as an acceptance test.

Design implications:

- A true **right-click quick-apply** must be a **secure hardware-initiated action**, not an insecure click handler that programmatically starts an item use.
- If the same corner icon both left-clicks to show a menu and right-clicks to apply, test that distinct mouse-button action types work with secure button attributes without taint.
- Dropdown poison rows also require real user-initiated secure clicks for application; a menu item executing normal Lua that calls a protected action is not acceptable.
- Changes to secure attributes, target bags, target slots, and/or buttons may be forbidden in combat. Prepare actions out of combat; ensure no surprise behavior when inventory changes mid-combat. If needed, defer changes until `PLAYER_REGEN_ENABLED`.
- Never simulate user clicks, bypass casting, silently confirm overwrite popups, or promise autonomous application.
- If a truly secure **single-click menu selection** is not viable with dynamic bags, document the shortest legal fallback workflow and seek product review before shipping a different experience.

### 5.5 Events and lifecycle

Listen only to relevant events, including character login/world entry, bag changes, equipment changes, weapon enchant/timer changes (where exposed), combat enter/leave, and panel show/hide. Verify available event names against current client API. Throttle/batch repeated updates. No idle heavy `OnUpdate` loops.

## 6. Implementation plan and gates

### Phase 0 — Feasibility spike (do this first)

- Confirm client build and exact relevant frame/API names.
- Make a tiny prototype that puts a clickable button in the MH weapon-slot corner.
- Prove an item from a real bag can be applied to **MH with one user click**, then OH with a separate click, via secure actions.
- Prove left-click opens a dropdown while **right-click executes the favorite's secure item use**, without taint or intercepting ordinary equipment-slot clicks.
- Prove whether dropdown rows can directly apply varying bag items, and test what works in and out of combat.
- Verify poison status reporting for MH and OH independently, including worn-off status and any simultaneous stone/poison effects.
- Create a short feasibility report: `verified`, `not verified`, `unsupported`, and alternate designs if any blockers appear.

**Gate:** Do not mark the promised click UX feasible on documentation alone. If the secure interaction cannot be achieved, stop and report before proceeding.

### Phase 1 — Functional MVP

- Rogues only; stable corner icons on both weapon slots.
- Bag-aware dropdown, correct quantities, manual apply to selected hand.
- Separate star favorites and persisted saved variables.
- Right-click quick-apply for each hand.
- Proper empty/no-favorite/unavailable behavior.
- Accurate minimal status inside character panel.

### Phase 2 — Reminders and polish

- Minimal optionally draggable MH/OH warning icons when panel is closed.
- Configurable threshold and off mode; no unsolicited audio/chat spam.
- Responsive anchoring, UI scale support, clean tooltips, localization-ready strings.
- Graceful recovery after swapping weapons, using poison manually, reloading UI, or moving bags.

### Phase 3 — Compatibility and release

- Combat and secure taint audit; UI conflict tests; profiling.
- README with install, controls, supported build, limitations, screenshots, and troubleshooting.
- Open-source license, changelog, clean release ZIP, and optional CurseForge/Wago metadata.

## 7. Acceptance tests (record actual in-game outcomes)

| Test | Pass criteria |
|---|---|
| Icon overlays | MH and OH corners display correctly on Blizzard character panel without blocking normal slot behavior |
| Distinct menus | Each left-click menu targets the correct hand |
| Inventory scan | Only available bag poisons; correct types, ranks, and stack totals |
| Stars | Changing MH favorite does not change OH favorite; persists across `/reload` and relog |
| Right-click MH | One deliberate click applies the correct resolved MH favorite to slot 16; never touches OH |
| Right-click OH | One deliberate click applies the correct resolved OH favorite to slot 17; never touches MH |
| Right-click with no favorite | Absolutely no change, UI opening, notification, sound, or secure item use; independent for MH and OH |
| Manual selection | Each poison-row click applies to the selected weapon (or a documented approved fallback is demonstrated) |
| Out of stock | Favorite remains saved; no wrong poison applies; user gets useful feedback |
| Wrong/empty weapon | No unintended casting; clear disabled state |
| Expiration | Correct hand gets warning when poison disappears or threshold is reached |
| Manual changes | Display updates if player applies poison outside the addon |
| UI privacy | No chat messages, networking, telemetry, or external dependencies |
| Combat | No `ADDON_ACTION_FORBIDDEN`, Lua errors, or tainted protected interactions; limitations documented |
| UI coexistence | No interference with default character panel, bags, action bars, or other addons |
| Performance | Minimal idle overhead; no per-frame inventory scan; events drive state refresh |

**Artifacts required from engineering:** source repo, installable addon folder/ZIP, README, screenshots or a short capture of both interactions, supported-build notes, a list of verified/unverified mechanics, test checklist/results, and an explanation of any deviations.

## 8. Non-goals

- Automated poison application without a click.
- Crafting poisons, buying reagents, maintaining inventory targets, and tracking market prices.
- Support for non-Rogue coatings at launch.
- Permanent floating poison bars or replacing the character/equipment panel.
- Extra audio effects and notifications by default.
- Supporting every custom character-frame replacement at launch.

## 9. Suggested engineering workstreams

- **Lead / integrator:** Verify secure design, decide feasibility at Phase 0, review PRs for taint, own integration/tests.
- **Secure-action engineer:** Prototype correct MH/OH secure use, dropdown secure row mechanics, combat constraints.
- **State/data engineer:** Poison classification, bag scan, family/rank resolution, enchant status.
- **UI engineer:** Tiny corner icons, dropdown, star controls, warning indicator, tooltips, minimal settings.
- **QA engineer:** In-game reproducible tests, profiling, conflicts with stock UI/addons, regression notes.

Do not parallelize UI work that relies on unverified protected action mechanics without first defining an approved fallback.

## 10. Useful references for engineering validation

These are research aids, **not** proof that a particular API works in this user's installed build:

- WoW Forever exported Blizzard UI code (recent Forever build): https://github.com/reckhou/WoWBlzCode
- Forever++ API notes, including protected item-to-weapon use: https://github.com/xIGBClutchIx/ForeverPlusPlus/blob/main/docs/forever-api.md
- WoW Forever addon API overview: https://wowforeveraddons.com/articles/wow-forever-addon-api
- Rogue Assistant (one-button-per-weapon UX reference; **All Rights Reserved — do not copy code**): https://www.curseforge.com/wow/addons/rogue-assistant
- Nightlock (alternate per-weapon preferred poison/quick-apply interaction for comparison; review licensing): https://www.curseforge.com/wow/addons/nightlock
- PoisonUP Forever (bag-aware poison types and ranks reference; review licensing): https://www.curseforge.com/wow/addons/poisonup-forever

## 11. First instructions to the lead agent

> Implement the addon defined in this handoff, starting with a narrowly scoped in-game secure-action proof of concept. Preserve the primary UX exactly: left-click a tiny icon anchored to a weapon slot to choose an available poison; star a poison separately for MH and OH; right-click that hand's icon to apply its favorite; warn subtly when poison expires. Treat WoW Forever as a Mainline-derived API with strict secure-action/combat limitations, not Classic-era Lua. Check the current Blizzard UI code and validate on the actual client. Do not claim features work without reproducing them in game. Keep the addon very small, native-looking, entirely local, and open-source-ready. Raise concrete API blockers with evidence rather than silently redesigning the interaction.
