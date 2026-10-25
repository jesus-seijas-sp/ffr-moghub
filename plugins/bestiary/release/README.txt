MogHub Bestiary 0.2.0 - a bestiary for FINAL FANTASY RESONANCE (Steam, PC)
=====================================================================

Adds "Bestiary" to the main menu (above System): every enemy you have met, grouped by area, with the game's own
scan (Libra) details once you have scanned it, its animated battle sprite, and where it can be found.

Made for game version 1.0.1.0. This is a MogHub plugin: it needs MogHub, which provides its menu entry.


REQUIREMENT: MogHub
  Install MogHub first (it comes with its own instructions, including the one-time UE4SS setup).

INSTALL
  Extract this zip into your game folder (the FINAL FANTASY RESONANCE folder that contains FFRS). It adds
    FFRS\Binaries\Win64\ue4ss\Mods\MogHubBestiary\
  Start the game and open the main menu: Bestiary is above System.
  The original FFR Bestiary (0.1.x, with its own zzz_FFRBestiary_P pak) must not be installed alongside: delete its
  three FFRS\Content\Paks\~mods\zzz_FFRBestiary_P files. Its progress files work with this version.

UNINSTALL
  Delete FFRS\Binaries\Win64\ue4ss\Mods\MogHubBestiary, or switch it off in the main menu > Mods.
  Your bestiary progress is in ...\Mods\MogHubBestiary\saves: copy it somewhere first if you want to keep it.

UPDATING
  Extract the new version over the old one. Progress (the saves folder) is kept.

SETTINGS (main menu > Mods > MogHub Bestiary)
  Show all monsters   lists every monster under all the areas it appears in, also the ones you haven't met
                      (dimmed). The Encountered and Scanned counts stay what you really met.
  Area enemy levels   each area's level range of random encounters (bosses left out), in its panel.
  Libra+              the exact numbers the scan leaves out: status resistances (%), drop and steal chances.
  Libra on every      shows every monster's scan data, as if scanned, without changing your save. A monster
  monster             you switched off by hand stays off.
  Forget all          forgets every Libra choice made by hand (see below).

CONTROLS IN THE BESTIARY
  Up/Down: move.  Confirm on an area: open/close it.
  Confirm on an enemy: switch its Libra (scan data) on or off, whatever your save says.
  Left/Right (or Q/E on a keyboard): next form, for enemies with several forms or phases.

GOOD TO KNOW
  - Your game saves are never written. Bestiary progress is kept in its own files next to the mod, one per save
    slot, written when the game saves and read when you load. Steam Cloud doesn't sync those files.
  - Installing part-way through the game: the enemies your save already records as defeated or scanned, and the
    areas it marks as visited, are picked up when you load. Where you met those enemies isn't recorded by the game,
    so their locations show ??? until you meet them again.

Original FFR Bestiary by Law19902: https://github.com/Law19902/ffr-bestiary (MIT licence).
MogHub port by jesus-seijas-sp.
FINAL FANTASY RESONANCE is (c) SQUARE ENIX. Unofficial fan mod, not affiliated with or endorsed by Square Enix.
