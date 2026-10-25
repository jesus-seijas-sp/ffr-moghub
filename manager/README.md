# MogHub Manager

A desktop mod manager for **FINAL FANTASY RESONANCE** (Steam, PC and Steam Deck): every installed mod in one list -
UE4SS, [MogHub](https://github.com/jesus-seijas-sp/ffr-moghub) and its plugins, other UE4SS mods and pak mods - with
their versions, switched on or off with a click; and a curated list of mods to install and keep up to date.

It lives in the MogHub repository but ships apart from MogHub: MogHub and its plugins are Lua files the game loads and
stay free of programs (Nexus Mods quarantines archives with executables), while this is a desktop program, released on
GitHub.

## What it does (0.1)
- Finds the game through Steam (Windows, Linux, Flatpak and Snap Steam), or a folder you choose.
- **Installed:** UE4SS and MogHub with their versions; MogHub plugins, UE4SS mods and pak mods, each with an On / Off
  switch and an "update available" badge. Changes take effect the next time the game starts; pak and UE4SS mods are
  switched with the game closed. The rules are the same as MogHub's own list in the game, so both always agree.
- **Available:** the mods in the [catalog](https://github.com/jesus-seijas-sp/ffr-moghub/tree/main/catalog) - a list
  kept in the ffr-moghub repository with each mod's source and latest version. Mods from GitHub (UE4SS, MogHub, FFR
  Trainer, MogHub Bestiary) install, update and uninstall with one click, with what they need installed first (the trainer
  needs MogHub, MogHub needs UE4SS); the player's settings and saves are never overwritten. Mods from Nexus Mods are
  listed with their page.
- What the manager installed is recorded in `moghub-manager.json` in the game folder, so an uninstall removes exactly
  those files.

## Coming next
- Installing catalog mods that come from Nexus Mods (with the player's Nexus account).
- Warnings when two pak mods change the same game data.

## Running from source
Requires [Node.js](https://nodejs.org/) 20 or newer. From the `manager` folder:
```sh
npm install
node node_modules/electron/install.js   # if npm blocked Electron's download script
npm start
npm test
npm run dist                            # Windows portable / zip and Linux AppImage / tar.gz into dist/
```

## Licence
MIT ([LICENSE](LICENSE)). FINAL FANTASY RESONANCE is © SQUARE ENIX. Unofficial fan tool, not affiliated with Square
Enix or Nexus Mods.
