-- The smallest useful MogHub plugin. Copy this folder into ue4ss/Mods, rename it, and start editing.
local mod, kit = ...

local cfg = mod:settings{
    { header = "Hello" },
    { key = "Greet", label = "Greet after battles", type = "toggle", default = true,
      help = "Shows a message when a battle ends." },
    { key = "Times", label = "Battles won", type = "number", min = 0, max = 9999, step = 1, default = 0, keep = true },
    { label = "Say hello", type = "action", button = "Run", run = function() mod:notice("Hello!", "on") end },
    { key = "HelloKey", type = "value", default = "CTRL+F9" },     -- in config.ini only
}

mod:on("battleEnd", function()
    cfg:set("Times", cfg.Times + 1)
    if cfg.Greet then mod:notice(string.format("Battle %d won", cfg.Times), "on") end
end)

mod:key(cfg.HelloKey, function() mod:notice("Hello from the keyboard", "on") end)
mod:log("ready")
