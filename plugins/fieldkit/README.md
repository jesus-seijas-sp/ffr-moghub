# MogHub Field Kit

A [MogHub](../../README.md) plugin for **FINAL FANTASY RESONANCE**: field and HUD comforts, each one a switch in the
Mods menu (main menu > Mods > MogHub Field Kit) or in `config.ini`.

## Features

- **HUD:** hide the minimap, the quest tracker or the key guide; hide the whole field HUD (Ctrl+F7).
- **Encounter meter:** how far you are from the next random battle, under the minimap (Ctrl+F8).
- **Save anywhere:** Save in the system menu (Esc) works everywhere, not only at save points; never in battles or
  story scenes.
- **Quieter battle voices:** silence the turn-start lines, the menu lines, or also the battle start and victory lines.
- **Escape rewards:** fleeing after defeating at least one enemy still gives the defeated enemies' EXP and Gil.
- **Skip intro logos:** the start-up logos go by at once.

Every switch puts the game back as it was when turned off (or when the plugin is switched off).

## Install

Download it from [Nexus Mods](https://www.nexusmods.com/finalfantasyresonance/mods/115). Install
[MogHub](https://www.nexusmods.com/finalfantasyresonance/mods/110), then extract the Field Kit into the game folder: it adds
`FFRS\Binaries\Win64\ue4ss\Mods\MogHubFieldKit`.

## Hide Key Guide (standalone pak)

For players who want only the hidden key guide, without UE4SS or MogHub: `HideKeyGuide-<version>.zip` (an optional
file on the Nexus page) holds `zzz_HideKeyGuide_P.*` for `FFRS\Content\Paks\~mods`. It is always on; delete the three
files to get the key guide back. `tools/build_hidekeyguide.sh` builds it (`tools/hide-pak` sets the key guide widget's
inner overlay and button grid to Collapsed); rerun it after a game patch.
