-- MogHub (UE4SS): the "Mods" menu for FINAL FANTASY RESONANCE and the API its plugins are written against.
-- Plugins are folders in ue4ss/Mods with a moghub.lua; the kit runs them (see docs/MODDING.md).
local DIR = (function()
    local ok, info = pcall(function() return debug.getinfo(1, "S") end)
    local src = ((ok and info and info.source) or ""):gsub("^@", ""):gsub("\\", "/")
    return src:match("^(.*)/Scripts/[^/]+$") or "ue4ss/Mods/MogHub"
end)()
package.path = DIR .. "/Scripts/?.lua;" .. package.path

local kit = require("kit.core")
local ok, err = pcall(kit.start, DIR)
if not ok then print("[MogHub] failed to start: " .. tostring(err) .. "\n") end
