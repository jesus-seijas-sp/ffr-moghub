-- What the Bestiary needs from FINAL FANTASY RESONANCE beyond MogHub's kit.game: the save's per-unit records, enemy
-- scan data, its strings and the game widgets the screen reuses. A game patch should only touch this file.
-- Verified on the full game v1.0.1.0 (Steam build 24250053), 24 Oct 2026. See RECON.md.
local data = require("bestiary_data")
local M = {}

M.valid = kit.valid
M.saveData = kit.game.saveData
M.load = kit.game.load
M.text = kit.game.text
M.itemName = kit.game.itemName

-- per-unit records from the save (SaveId, IsAnalyzed, defeatNum, analyzedElments), keyed by SaveId (= unit id for
-- enemies)
function M.records(sd)
    local out = {}
    kit.ue.each(sd.unitList, function(r) out[r.SaveId] = r end)
    return out
end

-- enemy unit ids currently in battle (nil when no battle)
function M.battleEnemies()
    if not kit.game.inBattle() then return nil end
    local ids = {}
    for _, u in ipairs(kit.game.battleSide(kit.game.ENEMY)) do ids[#ids + 1] = u.id end
    return ids
end

-- a unit's scan data from the mod's data file (tools/export_data.py "stats"), shaped like the game's FUnitParameter
-- fields the screen reads. Plain Lua values only: the game's own GetUnitParameterById comes back from UE4SS as
-- wrappers into memory that is freed after the call, and reading them later crashed the game.
local paramCache = {}
function M.unitParam(id)
    if paramCache[id] then return paramCache[id] end
    local d = data.stats[tostring(id)]
    if not d then return nil end
    local function str(ref) return ref and M.text(ref[1], ref[2]) end
    local p = { Name = str(d.name), Level = d.lv, MaxHitPoint = d.hp, Race = d.race, Traits = {},
                ElementResistanceList = {}, StatusConditionResistanceList = {},
                DropNormalItem = d.drop[1], DropRareItem = d.drop[2], StealNormalItem = d.drop[3], StealRareItem = d.drop[4],
                Rates = d.rate }                          -- drop / rare drop / steal divisors (1 in rate)
    for _, ref in ipairs(d.traits) do p.Traits[#p.Traits + 1] = str(ref) end
    for k, v in pairs(d.el) do p.ElementResistanceList[tonumber(k)] = v end
    for k, v in pairs(d.st) do p.StatusConditionResistanceList[tonumber(k)] = v end
    paramCache[id] = p
    return p
end

function M.libra(key) return M.text("/Game/Datatable/Strings/UI/UI_Common/ST_UI_Libra.ST_UI_Libra", key) end

-- battle damage words (Weak / Resisted / Immune / Absorbed)
function M.battleWord(key) return M.text("/Game/Datatable/Strings/UI/UI_Common/ST_UI_BattleDamageProp.ST_UI_BattleDamageProp", key) end

-- the scan panel's widgets, reused so the detail panel looks like it
M.ELEMENT_ICONS = "/Game/UI/Common/Icon/Element/WBP_ElementIconList"                 -- SetElementList(eElement[])
M.CONDITION_ICONS = "/Game/UI/Battle/Libra/Widget/Entry/WBP_BtlLibra_ConditionIconList" -- SetConditionList(...)
M.ITEM_ENTRY = "/Game/UI/Battle/Libra/Widget/Entry/WBP_BtlLibraEntry_Item"            -- SetContentId(item): icon + name

-- eRace values (mucha_enums.hpp) -> ST_UI_Libra keys
M.RACE_KEY = { [0] = "None", "Animal", "Avian", "Aquatic", "Demon", "Human", "Machina", "Dragon", "Fairy", "Insect",
               "Stone", "Plantoid", "Reaper", "Chocobo", "Vision", "Beast" }

return M
