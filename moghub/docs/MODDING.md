# Writing a plugin for MogHub

MogHub is a UE4SS Lua mod for FINAL FANTASY RESONANCE. It adds a **Mods** entry to the main menu (and the
title screen) and runs plugins: small Lua mods that use MogHub's API instead of talking to UE4SS directly. You get
a settings page in the game's own style, a config file, timers, game events, reversible data-table edits and
per-save storage without writing any of that yourself.

A plugin can also have **its own main-menu entry** (FFR Bestiary does): MogHub's pak has three spare scene rows,
so plugins never ship a pak of their own and never fight over the game's menu table.

## A plugin is a folder

```
ue4ss/Mods/
  MogHub/           MogHub itself (the only UE4SS mod that runs)
  MyPlugin/
    moghub.ini        name, version, author, description, order
    moghub.lua        the plugin's code; MogHub runs it
    Scripts/*.lua     optional modules: require("name") finds them
    lang/*.ini        optional translations (see Translations)
    config.ini        written by MogHub from your settings
```

Don't add an `enabled.txt` or a `Scripts/main.lua`: those would make UE4SS run the folder as a mod of its own.
Players install a plugin by extracting it into the game folder and uninstall it by deleting the folder.

### Switched on and off

Players can switch any plugin on or off from the Mods menu, and the change applies right away. While a plugin is
off, none of its timers, events, hooks, keys or menu screens run, its main-menu entry goes away, and its settings
read as their defaults. To undo your changes to the game, apply your settings again:

```lua
mod:onToggle(function(on) apply() end)   -- off: the defaults undo everything; on: the player's values again
```

A plugin that was off when the game started is loaded the first time it is switched on.

`examples/FFRHello` is a complete plugin to start from.

### moghub.ini

```ini
Name = My Plugin
Version = 1.0.0
Author = you
Description = One or two sentences for the Mods menu.
Order = 50          ; position in the Mods menu (lower first)
```

### moghub.lua

The file receives two values: `mod` (your plugin) and `kit` (shared services).

```lua
local mod, kit = ...
```

Plugins all run in MogHub's Lua state. `require` looks in your own folder first (`MyPlugin/name.lua`, then
`MyPlugin/Scripts/name.lua`), with a cache per plugin, so two plugins can both have a `ui.lua`. Your modules see
`mod` and `kit` as globals too, so they don't need them passed in. All UE4SS globals (`FindFirstOf`,
`StaticFindObject`, `FName`, ...) are available as usual.

Errors in anything you register (timers, events, hooks, keys, buttons) are caught and logged once to
`UE4SS.log` as `[MyPlugin] ...`. They never stop MogHub or other plugins. If `moghub.lua` itself fails, the Mods
menu shows your plugin with the error.

## Settings

```lua
local cfg = mod:settings{
    { header = "Battle" },                                    -- a section in the menu and the file
    { key = "GodMode", label = "God mode", type = "toggle", default = false, help = "Shown beside the list." },
    { key = "Exp", label = "EXP", type = "number", min = 0, max = 10, step = 0.5, default = 1, format = "x%g" },
    { key = "Gil", label = "Gil to add", type = "choice", default = 10000,
      choices = { { 1000, "1,000" }, { 10000, "10,000" } } },
    { label = "Add Gil", type = "action", button = "Add", run = function() ... end, done = "Gil added" },
    { key = "TurboKey", type = "value", default = "CTRL+F6" }, -- in config.ini only, not in the menu
}
```

| type     | menu                                              | value            |
|----------|---------------------------------------------------|------------------|
| `toggle` | On / Off; confirm switches it                     | boolean          |
| `number` | `< value >`; Left / Right step, confirm wraps     | number (clamped) |
| `choice` | `< label >`; Left / Right step, confirm wraps     | the choice value |
| `action` | a button; confirm runs `run()`, then shows `done` | none             |
| `value`  | not shown; kept in config.ini                     | string or number |

Other fields: `help` (the text beside the list), `format` (for numbers, a `string.format` pattern), and
`keep = true` (Reset leaves it alone).

Use the result like a table, and listen for changes made from the menu, the ini file or code:

```lua
if cfg.GodMode then ... end
cfg:set("Exp", 2)
cfg:onChange(function(key, value, old) apply() end)
cfg:reset()                      -- every menu setting back to its default
```

Values live in `MyPlugin/config.ini`. It is written when missing, edits by hand are picked up within a second, and
comments and layout are kept when MogHub writes a value.

## Timers, events, hooks, keys

```lua
mod:every(1000, fn, "name")      -- repeating; returns a handle for mod:cancel(handle)
mod:after(1500, fn, "name")      -- once
mod:on("battleEnd", fn)
mod:hook("/Script/mucha.CPP_BtlDelEventCmd:OnExecuteDecideCommand", function(ctx, value) ... end)
mod:key("CTRL+F6", fn, "TurboKey")   -- F1-F12, A-Z, 0-9 with CTRL+ / SHIFT+ / ALT+
mod:notice("Turbo: x2", "on")        -- "on" green, "off" white, "warn" amber; optional duration in ms
mod:log("value %d", n)               -- [MyPlugin] value 3 in UE4SS.log
```

Everything runs on the game thread from one 50 ms tick. Timers wait while a loading screen is up, because objects
are being torn down; pass `{ loading = true }` as the last argument to keep one running anyway.

Events:

| event                        | when                                                          |
|------------------------------|---------------------------------------------------------------|
| `tick`                       | every 50 ms                                                   |
| `loadingBegin`, `loadingEnd` | a loading screen starts / ends                                |
| `battleStart`, `battleEnd`   | a battle's units appear / are gone (checked twice a second)   |
| `saveLoaded (slot, save)`    | a save was loaded or a new game started (`slot` nil: no slot) |
| `saved (slot, save)`         | the game saved to a slot                                      |
| `gameEvent (tag, value)`     | every event of the game's own dispatcher, by gameplay tag     |

`kit.events.battle` is true during a battle, and `kit.events.slot` is the loaded slot.

## Game access: `kit.game`

```lua
kit.game.lib("CPP_BFL_Unit")            -- a function library's default object
kit.game.first("WorldSettings")         -- first live object of a class
kit.game.all("CPP_MapUnit_Playable")    -- every live object (default objects left out)
kit.game.battleSide(kit.game.FRIENDLY)  -- { { unit, param, id }, ... } in battle (ENEMY for enemies)
kit.game.saveData()                     -- the loaded save object, nil on the title screen
kit.game.location()                     -- map id, island
kit.game.text(tableId, key)             -- a string from the game's string tables, in the player's language
kit.game.itemName(id)
kit.game.load(path) / kit.game.class(path)   -- assets and Blueprint classes, loaded if needed
kit.game.keyDown("Gamepad_DPad_Left")   -- raw key state
kit.game.isPaused()
```

## Data tables: `kit.tables`

Edits that undo themselves. The patcher keeps each field's original value, and every write is computed from it:

```lua
local patch = kit.tables.patcher()
local function apply()
    patch:apply("SKILL_DATA", tostring(cfg.NoMPCost), function(row, orig)
        kit.tables.set(row, "Cost", cfg.NoMPCost and 0 or orig("Cost"))
    end)
end
cfg:onChange(apply)
mod:every(2000, apply)   -- the game reloads some tables on map changes; apply() notices and edits them again
```

The first argument is the row struct's name. The second is a state string: rows are only rewritten when it changes
or when the table is reloaded. `kit.tables.find(struct)` lists the tables with that row struct.

## Per-save storage: `mod:store(name)`

```lua
local st = mod:store("progress")          -- MyPlugin/saves/progress_slot<N>.json
st:onLoad(function(data, slot) data.seen = data.seen or {} end)
st.data.seen[id] = true                    -- change it any time; it's written when the game saves
st:onSave(function(data, slot) data.version = 2 end)   -- just before writing: fill in what only exists then
mod:store("progress", { file = "slot%s.json" })         -- a file name of your own in saves/ (%s: the slot)
```

Storage follows the game. It is read when a slot is loaded and written when the game saves to a slot, so
reloading without saving forgets changes, exactly like the game.

## A main-menu entry of your own

```lua
local screen = mod:screen{
    title = "Bestiary",                   -- the entry and the page header
    opened = function(host, ui) end,      -- the page just opened: build it
    poll = function(host) end,            -- every 50 ms while it is open
    closed = function() end,
    confirm = function() end,             -- confirm was pressed on a row of the list
}
```

The entry opens the game's Help layout (`host`, a `WBP_HelpLayout_C`). You rebuild its content with the game's
widgets, as FFR Bestiary does, and the game keeps its frame, header, transitions, back button and input
handling. `nil` comes back when all three spare entries are taken.

### Widgets: `ui`

`opened` receives `ui`, MogHub's widget helpers bound to the page (`kit.ui.on(host)`). They make the game's own
widgets, so the page looks like the other menu pages:

```lua
ui.text("Hello", kit.ui.GREY)         -- body text in the game's style (colors: WHITE, GREY, DIM, GOLD, BLUE)
ui.set(t, "Bye", color)               -- change a text
ui.heading("Section")                 -- a heading with the game's underline (h:SetTitle(FText(...)) changes it)
ui.panel(content, pad)                -- a framed section, like the Equipment page's
ui.sized(content, w, h)               -- a SizeBox; ui.spacer(h, w)
ui.fit(content)                       -- shrinks its content to fit, never enlarges it
ui.image(texture, size)               -- size: a number or { w, h }; ui.check(size): the Quests page's check mark
ui.keyIcon("decide")                  -- the button glyph for the device in use
ui.row(parent, "Label", labelW, valueW)       -- a "Label   value" line; returns the value text
ui.widgetRow(parent, "Label", labelW)         -- the same, plus a box for the game's own icon widgets
ui.new("WrapBox")                     -- any UMG / CommonUI widget; ui.create(path): a game widget Blueprint
ui.find(widget, name)                 -- a widget by name, also inside user widgets
ui.viewportScale()                    -- screen pixels per UI pixel (the UI is laid out for 1920x1080)
```

### The list: `kit.list`

Help's native list, with the game's rows, cursor, scrollbar and Up / Down handling:

```lua
local L = kit.list.attach(host, ui, {
    window = { 1760, 830 }, list = { 640, 670 },   -- sizes; Help's own title is hidden
    lead = 40,                                      -- optional: an image before each row's text
    row = function(e, ui, tree) ... end,            -- optional: add widgets to each row (to e.right)
})
L:setContent(body)                 -- your layout in the window...
L:takeList(column)                 -- ...with the list inside it
L:setRows(#rows, function(i) return rows[i].name end)
local focused = L:poll(function(i, e)              -- every tick, for each visible row
    kit.list.indent(e, 34)                          -- nest it
    kit.list.setValue(e, "x3", kit.ui.GREY)         -- right-aligned value
    kit.list.lead(e, true, L:texture(iconPath))     -- the lead image (textures load in the background)
end)
```

The list recycles row widgets while scrolling, so set every visible row's state on every tick. `e.title` is the
row's text widget. The Mods screen (`kit/hub.lua`) is a short example, and FFR Bestiary (`ui.lua`) a full one: rows
with face icons, counts and check marks beside a detail panel.

## Translations

MogHub follows the game's text language (the player can force one with `Language` in `MogHub/config.ini`). Write
your texts in English in the code; translations are optional files next to your plugin, one per language:
`lang/fr.ini`, `de.ini`, `es.ini`, `ja.ini`, `ko.ini`, `zh-Hans.ini`, `zh-Hant.ini` (the game's official languages).

```ini
; lang/ja.ini
plugin.name = 私のプラグイン
GodMode.label = ゴッドモード
GodMode.help = パーティがダメージを受けなくなります。
header.Battle = バトル
partyHealed = パーティを回復しました
gilAdded = {1}ギルを入手
```

- **Settings** need nothing in the code: each item is looked up as `<key>.label`, `<key>.help`, `<key>.button`,
  `<key>.done` and `<key>.choice.<value>`, where `<key>` is its `key` (or `id`; for an action without either, its
  English label). Headers are `header.<English header>`.
- **Your name and entry:** `plugin.name`, `plugin.description`, and `screen.title` for a main-menu entry.
- **Other texts:** `mod:t("partyHealed", "Party healed")`. `{1}`, `{2}`... take the extra arguments:
  `mod:t("gilAdded", "{1} Gil added", amount)`. A missing translation falls back to your English.
- **The game's own words** come out right in every language: `kit.game.text(table, key)` reads the game's string
  tables (the Bestiary takes enemy names, Libra labels and element words from there).
- `kit.i18n.lang` is the current language; the `languageChanged` event fires when the player changes it. A screen
  that builds its texts once should build them again then (the Bestiary does).

Tools (from the repository root):
- `python moghub/tools/i18n_template.py` writes `lang/en.ini` for MogHub and every plugin: all their English texts,
  the template translators copy. It is never read by MogHub.
- `python moghub/tools/i18n_check.py` checks every translation against it: missing or unknown keys, placeholders and
  line breaks.
- [`docs/GLOSSARY.md`](GLOSSARY.md) lists the game's official terms in the eight languages (Libra is *Acuité* in
  French and *Analyse* in German; Gil is *guiles* in Spanish): use them, so your plugin speaks like the game.

The game's own fonts cover every language, as long as your texts use the game's text style (`ui.text` does).

## Development

- **Debug log:** set `Debug = 1` in `MogHub/config.ini` for more detail in `UE4SS.log`.
- **dev_eval:** with Debug on, a `dev_eval.lua` dropped in `MogHub/` runs once inside the game, with `kit` in
  reach, and what it passes to `out(...)` lands in `dev_eval_out.txt`. Write it as `.tmp` and rename it, so
  MogHub never reads half a file. Keep it light: it runs on the game thread, and a long loop freezes the game.
- **Test outside the game:** MogHub loads under plain Lua 5.4 with stub UE4SS globals, which catches most mistakes
  before a game launch.
