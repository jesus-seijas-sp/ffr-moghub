# MogHub

The framework itself. See the [repository README](../README.md) for what MogHub is and how to install it.

| Path | What it is |
|---|---|
| `runtime/MogHub` | The UE4SS mod: `Scripts/main.lua` starts `Scripts/kit/core.lua`, which loads the plugins; `config.ini` holds MogHub's own settings and which plugins are switched off |
| `runtime/MogHub/Scripts/kit` | The API plugins get as `kit` (game access, data tables, settings, store, events, widgets, list, menu, translations), the Mods screen (`hub.lua`) and the other mods it lists and switches (`others.lua`) |
| `docs/MODDING.md` | The plugin author guide |
| `examples/FFRHello` | A small plugin to start from |
| `tools/build_pak.sh`, `tools/menu-pak` | Build the menu pak `zzz_MogHub_9_P`: the game's main-menu table with MogHub's rows (Mods, and three spare entries plugins claim at run time), extracted with [retoc](https://github.com/trumank/retoc) and edited with [UAssetAPI](https://github.com/atenfyr/UAssetAPI). Rerun after a game patch |

The pak tools need `tools/downloads` (retoc, UAssetAPI) and `extracted/Mappings.usmap` (from UE4SS's DumpUSMAP),
none of which is committed.
