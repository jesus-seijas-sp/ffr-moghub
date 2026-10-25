# FFR Trainer

A [MogHub](../../README.md) plugin for **FINAL FANTASY RESONANCE**: cheats and boosters, set from the game's own
menu (main menu > Mods > FFR Trainer) or from `config.ini`.

## Features

- **Battle:** god mode, infinite HP / MP, full Limit Break, no MP cost, one-hit kills, damage and enemy multipliers,
  always escape, heal after battle, auto battle (with auto-confirmed results), battle speed and turbo.
- **Rewards:** EXP, Gil, MRP, AP and drop rate multipliers; always drop rare items; steals that always work and
  give the rare item; add Gil.
- **Field:** random encounters on / off, encounter rate, walking speed.
- **Your game:** the [FFR Save Editor](https://github.com/jesus-seijas-sp/ffr-save-editor)'s quick actions done to
  the running game: max Gil, raise every character to a level, stock every consumable, every artifact, max Mastery
  Rank and awakening, Libra on every enemy met, restock shops, reveal every map.
- **Hotkeys** (in `config.ini`): Ctrl+F1 god mode, Ctrl+F2 auto battle, Ctrl+F3 encounters, Ctrl+F4 walking speed,
  Ctrl+F5 one-hit kills, Ctrl+F6 turbo.

The cheats are reversible: the game's own values are kept, and put back when a setting returns to normal or the
trainer is switched off. **Your game** is different: those buttons change your progress through the game's own
functions, and the game's next save keeps the change (load without saving to undo it).

When FFRS-QoL is installed, the settings it also handles are left to it.

## Install

Install MogHub, then extract the trainer into the game folder: it adds `FFRS\Binaries\Win64\ue4ss\Mods\FFRTrainer`.

## Development

- `runtime/FFRTrainer/moghub.lua`: the settings and cheats; `Scripts/live.lua`: the **Your game** actions.
- `Scripts/game_data.lua` (item, enemy and map lists) is generated from the FFR Save Editor's catalogs by
  `tools/export_data.py` (by default from an `ffr-save-editor` checkout next to this repository).
