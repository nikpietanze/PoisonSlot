# PoisonSlot

A small World of Warcraft: Forever addon for Rogues. It puts a tiny poison icon on the main-hand and off-hand weapon slots of the character panel.

- **Left-click** a hand's icon to see the poisons in your bags and apply one to that weapon.
- **Star** a poison in that menu to make it the favorite for that hand. Main hand and off hand keep separate favorites.
- **Right-click** a hand's icon to apply its favorite. With no favorite set, right-click does nothing.
- A small optional reminder shows when a weapon's poison is missing or about to expire, even with the character panel closed.

No poison bar, no extra windows, no sounds, no chat spam, no automation. Every application is one real click from you.

## Status

Early development. Applying a poison to a weapon is a protected action, so the first milestone is an in-game proof that secure buttons can do it with one click per hand. Nothing beyond that is promised until it works on a live client. The full spec is in [docs/HANDOFF.md](docs/HANDOFF.md).

Target client: WoW Forever, Interface `16001`.

## Install

Until there is a release, clone the repo into your AddOns folder so the folder is named `PoisonSlot`:

```
World of Warcraft/_forever_/Interface/AddOns/PoisonSlot/PoisonSlot.toc
```

Type `/pslot` in game to check it loaded.

## Bugs and ideas

Open an [issue](https://github.com/nikpietanze/PoisonSlot/issues). For bugs, include your client build (`/dump GetBuildInfo()`) and any Lua error text (BugSack makes this easy). Pull requests are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. See [LICENSE](LICENSE).
