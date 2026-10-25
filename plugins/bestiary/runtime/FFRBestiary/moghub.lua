-- FFR Bestiary, as a MogHub plugin: MogHub gives it its main-menu entry (one of MogHub's spare scene rows, so no
-- pak of its own), the screen's widgets and list (kit.ui, kit.list), per-save storage and the game's events.
local mod, kit = ...
require("store")                      -- progress: read and written with the game's saves
local tracker = require("tracker")
local ui = require("ui")

-- development keys (F7 show all, F3 focus log, F8 / F9 sprite review), only with a dev.txt in this plugin's folder
local DEV = kit.exists(mod.dir .. "/dev.txt")
local devAll = false

local cfg = mod:settings{
    { key = "ShowAll", label = "Show all monsters", type = "toggle", default = false,
      help = "List every monster under all the areas it appears in, also the ones you haven't met yet (dimmed, with "
          .. "their scan data hidden until you scan them or switch Libra on for them). The Encountered and Scanned "
          .. "counts stay what you really met." },
    { key = "AreaLevels", label = "Area enemy levels", type = "toggle", default = true,
      help = "The level range of an area's random encounters (bosses left out), in its panel in the Bestiary. Towns, "
          .. "and caves whose enemies wait on the map, have none." },
    { header = "Libra" },
    { key = "LibraPlus", label = "Libra+", type = "toggle", default = true,
      help = "Exact numbers the game's scan leaves out: how much a monster resists each status, and the chance of "
          .. "each drop and of a steal working." },
    { key = "LibraAll", label = "Libra on every monster", type = "toggle", default = false,
      help = "Every monster's scan data shows, as if you had scanned it with Libra, without changing your save. "
          .. "A monster you switched off by hand (confirm on it in the Bestiary) stays off." },
    { label = "Libra by hand", type = "action", button = "Forget all",
      help = "In the Bestiary, confirm on a monster switches its Libra (scan data) on or off, whatever the game says. "
          .. "This forgets every such choice.",
      run = function() require("libra").clear() end, done = "Libra choices forgotten" },
}

local leftRight = kit.game.leftRight()
local screen = mod:screen{
    title = "Bestiary",
    opened = function(host, u)
        ui.showAll, ui.libraAll = cfg.ShowAll or devAll, cfg.LibraAll or devAll
        ui.libraPlus, ui.areaLevels = cfg.LibraPlus, cfg.AreaLevels
        ui.open(host, u)
    end,
    poll = function()
        ui.showAll, ui.libraAll = cfg.ShowAll or devAll, cfg.LibraAll or devAll
        ui.poll()
        local dir = leftRight()                           -- Left / Right: the shown monster's forms
        if dir ~= 0 then ui.queueForm(dir) end
    end,
    closed = function() ui.close() end,
    confirm = function() ui.confirm() end,
}
if not screen then mod:log("no free main-menu entry: the Bestiary can't be opened") end

-- seen tracking: the enemies of each battle and the area
mod:every(1000, tracker.poll, "tracker")

mod:key("Q", function() ui.queueForm(-1) end)
mod:key("E", function() ui.queueForm(1) end)
if DEV then
    mod:key("F7", function()
        devAll = not devAll                               -- everything seen and scanned, whatever the settings
        mod:log("showAll " .. tostring(devAll))
    end)
    mod:key("F3", function() ui.debugFocus() end)
    mod:key("F8", function() ui.queueDevNext() end)
    mod:key("F9", function() ui.toggleMeasure() end)
end
