# Contributing

Thanks for helping out. A few ground rules keep PoisonSlot small and safe to run:

- **Keep the scope.** Poison selection, per-hand favorites, quick-apply and quiet reminders. Poison bars, restocking, crafting helpers and sounds are out of scope (see "Non-goals" in [docs/HANDOFF.md](docs/HANDOFF.md)).
- **Secure actions only.** Applying a poison must come from a real click on a secure button. No protected calls from insecure Lua, no simulated clicks, no auto-confirming popups.
- **No taint.** Test in and out of combat with `/console taintLog 1` and make sure there's no `ADDON_ACTION_FORBIDDEN`.
- **Test in game.** Say in your PR what you tested, on which client build, and what you couldn't verify.
- **No copied code** from addons with incompatible licenses.
- Use tabs for indentation in Lua.
