# FFR MogHub

**MogHub** is a mod framework for **FINAL FANTASY RESONANCE** (Steam, PC), and this repository holds it together
with the mods built on it.

MogHub is a [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) Lua mod. It adds a **Mods** entry to the game's main
menu (and the title screen) and runs plugins: small Lua mods that use its API instead of talking to UE4SS directly.
Plugins get a settings page in the game's own style, config files, timers, game events, reversible data-table edits,
per-save storage, and even a main-menu entry of their own, without shipping a pak. Each plugin can be switched on or
off from the Mods menu while the game runs.

MogHub and its plugins speak the game's eight languages (English, French, German, Spanish, Japanese, Korean,
Simplified and Traditional Chinese), following the game's text language and using its official terms.

## What's here

| Folder | What it is |
|---|---|
| [`moghub/`](moghub) | The framework: the UE4SS mod (`runtime/MogHub`), the menu pak and the tools that build it, the plugin author guide ([`docs/MODDING.md`](moghub/docs/MODDING.md)) and an example plugin |
| [`plugins/trainer/`](plugins/trainer) | **FFR Trainer**: battle, reward and field cheats, plus the [FFR Save Editor](https://github.com/jesus-seijas-sp/ffr-save-editor)'s quick actions done to the running game |
| [`plugins/bestiary/`](plugins/bestiary) | **FFR Bestiary**: every enemy you have met, by area, with its scan data and sprite. A fork of [Law19902's FFR Bestiary](https://github.com/Law19902/ffr-bestiary), with its history |
| [`tools/`](tools) | Development scripts for the whole repository |

## Installing (players)

1. Install UE4SS once: the `UE4SS_v3...` zip (not `zDEV`) from
   [experimental-latest](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental-latest), extracted into
   `FFRS\Binaries\Win64`; then in `ue4ss\UE4SS-settings.ini`, under `[EngineVersionOverride]`, set
   `MajorVersion = 5` and `MinorVersion = 6`.
2. Extract the MogHub zip into the game folder. It adds `ue4ss\Mods\MogHub` and the menu pak
   `FFRS\Content\Paks\~mods\zzz_MogHub_P.*`.
3. Extract the plugins you want into the game folder. Each adds one folder in `ue4ss\Mods`.

Made for game version 1.0.1.0 (Steam build 24250053). Release zips are not published yet.

## Development

- `tools/deploy.sh [game folder]` installs MogHub, its pak and every plugin into the game.
- `moghub/tools/build_pak.sh` rebuilds the menu pak (after a game patch); it needs retoc, UAssetAPI and a
  `Mappings.usmap` (see the script).
- A plugin is a folder `plugins/<name>/runtime/<Folder>` with `moghub.ini`, `moghub.lua` and optional `Scripts/`.
  See [`moghub/docs/MODDING.md`](moghub/docs/MODDING.md).

## Licence

MIT ([LICENSE](LICENSE)). Parts of MogHub are adapted from FFR Bestiary by Law19902 (MIT); `plugins/bestiary`
keeps its own licence. FINAL FANTASY RESONANCE is © SQUARE ENIX. This is an unofficial fan project, not affiliated
with or endorsed by Square Enix.
