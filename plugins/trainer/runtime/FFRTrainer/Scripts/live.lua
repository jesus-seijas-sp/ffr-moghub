-- The FFR Save Editor's quick actions, done to the game being played instead of a save file: each goes through the
-- game's own save-data functions (CPP_BFL_SaveData*), so menus, shops and battles see it at once, and the game's
-- next save keeps it. Item, enemy and map lists come from the editor's catalogs (tools/export_data.py).
local data = require("game_data")

local M = {}
local kit, game

local SYNCHRO, AWAKENING = 1, 0          -- eVisionMasteryType

function M.init(k) kit, game = k, k.game end

-- the loaded game's save object, or nil (with the reason) on the title screen
local function save()
    local sd = game.saveData()
    if not sd then return nil, "load a game first" end
    return sd
end

-- each element of a TArray of structs
local function each(arr, fn)
    for i = 1, #arr do fn(arr[i], i) end
end

-- the playable characters' unit ids
local function characters(sd)
    local ids = {}
    each(sd.unitParameterList, function(p) ids[#ids + 1] = p.UnitId end)
    return ids
end

function M.maxGil()
    if not save() then return nil, "load a game first" end
    local lib = game.lib("CPP_BFL_SaveDataPlayer")
    local max = lib:GetMaxNumMoney()
    lib:SetCurrentMoney(max, true, false)
    return string.format("Gil: %d", max)
end

-- every character to at least `level` (the EXP that level needs, through the game's own level-up)
function M.raiseLevels(level)
    local sd, err = save()
    if not sd then return nil, err end
    local unit, saved = game.lib("CPP_BFL_Unit"), game.lib("CPP_BFL_SaveDataUnit")
    level = math.min(level, unit:GetMaxLevel())
    local n = 0
    for _, id in ipairs(characters(sd)) do
        local need = unit:GetExpForReachLevel(id, level)
        if need and need > saved:GetSaveDataUnitExperience(id) then
            unit:SetPlayableUnitExperience(id, need, true)
            n = n + 1
        end
    end
    return string.format("%d characters raised to Lv %d", n, level)
end

-- every consumable to `count` (also the ones not owned yet), within each item's own maximum
function M.stockConsumables(count)
    if not save() then return nil, "load a game first" end
    local inv, item = game.lib("CPP_BFL_SaveDataInventory"), game.lib("CPP_BFL_Item")
    local n = 0
    for _, id in ipairs(data.consumables) do
        local want = math.min(count, item:GetMaxItemNumById(id))
        if want > 0 and inv:FindInventory(id) ~= want then inv:SetInventoryItem(id, want); n = n + 1 end
    end
    return string.format("%d consumables set to %d", n, count)
end

function M.allArtifacts()
    if not save() then return nil, "load a game first" end
    local inv = game.lib("CPP_BFL_SaveDataInventory")
    local n = 0
    for _, id in ipairs(data.artifacts) do
        if inv:FindInventory(id) < 1 then inv:AddInventory(id, 1); n = n + 1 end
    end
    return string.format("%d artifacts added", n)
end

-- Mastery Rank (each character's synchro with each vision) to the maximum
function M.maxMastery()
    local sd, err = save()
    if not sd then return nil, err end
    local vision = game.lib("CPP_BFL_Vision")
    local units, n = characters(sd), 0
    each(sd.visionList, function(v)
        local id = v.ID
        local max = vision:GetMaxMasteryPoint(id, SYNCHRO)
        for _, unit in ipairs(units) do
            if max > 0 and vision:GetSynchroMasteryPoint(id, unit) < max then
                vision:SetSynchroMasteryPoint(id, unit, max)
                n = n + 1
            end
        end
    end)
    return string.format("%d vision / character pairs at max rank", n)
end

function M.maxAwakening()
    local sd, err = save()
    if not sd then return nil, err end
    local vision = game.lib("CPP_BFL_Vision")
    local n = 0
    each(sd.visionList, function(v)
        local id = v.ID
        local max = vision:GetMaxMasteryPoint(id, AWAKENING)
        if max > 0 and vision:GetAwakeningMasteryPoint(id) < max then vision:SetAwakeningMasteryPoint(id, max); n = n + 1 end
    end)
    return string.format("%d visions fully awakened", n)
end

-- every enemy the game has a record of (met at least once), weaknesses included
function M.libraAll()
    local sd, err = save()
    if not sd then return nil, err end
    local unit = game.lib("CPP_BFL_SaveDataUnit")
    local enemy = {}
    for _, id in ipairs(data.enemies) do enemy[id] = true end
    local n = 0
    each(sd.unitList, function(r)
        local id = r.SaveId
        if not enemy[id] then return end
        if not unit:IsAnalyzed(id) then unit:SetAnalyze(id, true); n = n + 1 end
        pcall(function() r.analyzedElments:ForEach(function(_, v) if not v:get() then v:set(true) end end) end)
    end)
    return string.format("%d enemies scanned with Libra", n)
end

-- the limited stock of every shop back to full
function M.restockShops()
    local sd, err = save()
    if not sd then return nil, err end
    local n = 0
    each(sd.shop, function(s)
        if s.CurrentBuyNum > 0 then s.CurrentBuyNum = 0; n = n + 1 end
    end)
    return string.format("%d shop items restocked", n)
end

-- every area on the map screen (event stages left out)
function M.revealMaps()
    if not save() then return nil, "load a game first" end
    local maps = game.lib("CPP_BFL_SaveData_PerMap")
    local n = 0
    for _, id in ipairs(data.maps) do
        if not maps:IsKnown(id) then maps:AddKnownMap(id); n = n + 1 end
    end
    return string.format("%d maps revealed", n)
end

return M
