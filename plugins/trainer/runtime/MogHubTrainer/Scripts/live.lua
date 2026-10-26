-- The FFR Save Editor's quick actions, done to the game being played instead of a save file: each goes through the
-- game's own save-data functions (CPP_BFL_SaveData*), so menus, shops and battles see it at once, and the game's
-- next save keeps it. Item, enemy and map lists come from the editor's catalogs (tools/export_data.py).
local data = require("game_data")

local M = {}
local kit, game

local SYNCHRO, AWAKENING, each

function M.init(k)
    kit, game = k, k.game
    SYNCHRO, AWAKENING = game.enum.VisionMastery.Synchro, game.enum.VisionMastery.Awakening
    each = kit.ue.each
end

-- Each action runs with a game loaded (the Trainer wraps them in mod:action{ game = true }) and returns its message.

-- the playable characters' unit ids
local function characters(sd)
    local ids = {}
    each(sd.unitParameterList, function(p) ids[#ids + 1] = p.UnitId end)
    return ids
end

-- every character's HP and MP to full, knocked-out ones included (their maximums from the game's own parameters)
function M.healParty()
    local sd = game.saveData()
    local unit = game.lib("CPP_BFL_Unit")
    local n = 0
    for _, id in ipairs(characters(sd)) do
        local ok = pcall(function()
            local p = unit:GetPlayableUnitParameterObj(id)
            unit:SetPlayableUnitHitPoint(id, p:GetMaxHitPoint())
            unit:SetPlayableUnitMagicPoint(id, p:GetMaxMagicPoint())
        end)
        if ok then n = n + 1 end
    end
    return mod:t("healDone", "{1} characters healed", n)
end

function M.maxGil()
    local lib = game.lib("CPP_BFL_SaveDataPlayer")
    local max = lib:GetMaxNumMoney()
    lib:SetCurrentMoney(max, true, false)
    return mod:t("maxGilDone", "Gil: {1}", max)
end

-- every character to at least `level` (the EXP that level needs, through the game's own level-up)
function M.raiseLevels(level)
    local sd = game.saveData()
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
    return mod:t("raiseDone", "{1} characters raised to Lv {2}", n, level)
end

-- every consumable to `count` (also the ones not owned yet), within each item's own maximum
function M.stockConsumables(count)
    local inv, item = game.lib("CPP_BFL_SaveDataInventory"), game.lib("CPP_BFL_Item")
    local n = 0
    for _, id in ipairs(data.consumables) do
        local want = math.min(count, item:GetMaxItemNumById(id))
        if want > 0 and inv:FindInventory(id) ~= want then inv:SetInventoryItem(id, want); n = n + 1 end
    end
    return mod:t("stockDone", "{1} consumables set to {2}", n, count)
end

function M.allArtifacts()
    local inv = game.lib("CPP_BFL_SaveDataInventory")
    local n = 0
    for _, id in ipairs(data.artifacts) do
        if inv:FindInventory(id) < 1 then inv:AddInventory(id, 1); n = n + 1 end
    end
    return mod:t("artifactsDone", "{1} artifacts added", n)
end

-- The rewards of each Mastery Rank (synchro mastery level), from the game's table (DT_VisionSynchroMasteryData): what
-- the game hands a character on reaching the level in battle. Base parameter bonuses (EquipCost = the AP to equip
-- abilities, HP, stats...) and master skills belong to the character; a level's active and passive skills come with
-- the level itself, so setting the points is enough for those.
local BASE_PARAMETER, MASTER_SKILL = 5, 4              -- eVisionMasteryParameterType
local synchroRewards                                   -- [vision id][level] = { { type, a, b }, ... }
local function rewardsOf(visionId)
    if not synchroRewards then
        synchroRewards = {}
        kit.tables.rows("VISION_MASTERY_DATA", function(row, _, t)
            if not t.path:find("Synchro") then return end
            local list = {}
            each(row.detailData, function(d)
                local typ = kit.ue.enum(d.parameterType)
                if typ == BASE_PARAMETER or typ == MASTER_SKILL then
                    local p = kit.ue.values(d.params)
                    list[#list + 1] = { typ, p[1], p[2] }
                end
            end)
            synchroRewards[row.ID] = synchroRewards[row.ID] or {}
            synchroRewards[row.ID][row.Level] = list
        end)
    end
    return synchroRewards[visionId] or {}
end

-- a character's master skills (all three kinds), as a set; nil when the lists can't be read
local function masterSkills(saved, unit)
    local have, read = {}, 0
    for _, get in ipairs({ "GetMasterActiveSkillList", "GetMasterCommandSkillList", "GetMasterPassiveSkillList" }) do
        local ok = pcall(function()
            local out = {}
            saved[get](saved, out, unit)
            for _, id in ipairs(kit.ue.values(out)) do have[id] = true end
        end)
        if ok then read = read + 1 end
    end
    return read == 3 and have or nil
end

-- Mastery Rank (each character's synchro with each vision) to the maximum, with the rewards of every level skipped:
-- the base parameter bonuses and master skills a battle would have given. Characters already at max rank get any
-- master skill they are missing (an earlier version of this action didn't hand them out).
function M.maxMastery()
    local sd = game.saveData()
    local vision, saved = game.lib("CPP_BFL_Vision"), game.lib("CPP_BFL_SaveDataUnit")
    local units, n, rewards = characters(sd), 0, 0
    each(sd.visionList, function(v)
        local id = v.ID
        local max = vision:GetMaxMasteryPoint(id, SYNCHRO)
        local maxLevel = vision:GetMaxLevel(id, SYNCHRO)
        if max <= 0 then return end
        local byLevel = rewardsOf(id)
        for _, unit in ipairs(units) do
            local from = vision:GetSynchroMasteryLevel(id, unit)
            if vision:GetSynchroMasteryPoint(id, unit) < max then
                vision:SetSynchroMasteryPoint(id, unit, max)
                n = n + 1
            end
            local have
            for level = 1, maxLevel do
                for _, r in ipairs(byLevel[level] or {}) do
                    if r[1] == BASE_PARAMETER and level > from and r[2] and r[2] > 0 and r[3] then
                        saved:AddBaseParameter(unit, r[2], r[3])
                        rewards = rewards + 1
                    elseif r[1] == MASTER_SKILL and r[2] and r[2] > 0 then
                        if have == nil then have = masterSkills(saved, unit) or false end
                        if have and not have[r[2]] then              -- unreadable lists: no blind adds
                            saved:AddMasterSkill(unit, r[2])
                            have[r[2]] = true
                            rewards = rewards + 1
                        end
                    end
                end
            end
        end
    end)
    return mod:t("masteryDone", "{1} vision / character pairs at max rank ({2} rank rewards given)", n, rewards)
end

function M.maxAwakening()
    local sd = game.saveData()
    local vision = game.lib("CPP_BFL_Vision")
    local n = 0
    each(sd.visionList, function(v)
        local id = v.ID
        local max = vision:GetMaxMasteryPoint(id, AWAKENING)
        if max > 0 and vision:GetAwakeningMasteryPoint(id) < max then vision:SetAwakeningMasteryPoint(id, max); n = n + 1 end
    end)
    return mod:t("awakeningDone", "{1} visions fully awakened", n)
end

-- every vision the game has (its VISION_ITEM_DATA table: visions are items), through the game's own inventory
-- function, which files them in the vision list as finding one does
function M.allVisions()
    local inv = game.lib("CPP_BFL_SaveDataInventory")
    local owned = function()
        local have, n = {}, 0
        each(game.saveData().visionList, function(v) have[v.ID] = true; n = n + 1 end)
        return have, n
    end
    local have, before = owned()
    kit.tables.rows("VISION_ITEM_DATA", function(row)
        local id = row.ID
        if id and id > 0 and not have[id] then inv:AddInventory(id, 1); have[id] = true end
    end)
    local _, after = owned()
    return mod:t("visionsDone", "{1} visions added", after - before)
end

-- Tablet Shards (one item) up to 99, the number the princess's last chest asks for
local TABLET_SHARD, SHARDS_ALL = 25004, 99
function M.tabletShards()
    local inv = game.lib("CPP_BFL_SaveDataInventory")
    local have = inv:FindInventory(TABLET_SHARD)
    if have < SHARDS_ALL then inv:SetInventoryItem(TABLET_SHARD, SHARDS_ALL) end
    return mod:t("shardsDone", "Tablet Shards: {1}", math.max(have, SHARDS_ALL))
end

-- Libra on these enemies (unit ids): the save's scan flag and every element reaction, as a scan in battle does.
-- Returns how many weren't scanned yet.
function M.scan(ids)
    local sd = game.saveData()
    if not sd then return 0 end
    local unit = game.lib("CPP_BFL_SaveDataUnit")
    local want, n = {}, 0
    for _, id in ipairs(ids) do want[id] = true end
    for id in pairs(want) do
        if not unit:IsAnalyzed(id) then unit:SetAnalyze(id, true); n = n + 1 end
    end
    each(sd.unitList, function(r)
        if want[r.SaveId] then
            pcall(function() r.analyzedElments:ForEach(function(_, v) if not v:get() then v:set(true) end end) end)
        end
    end)
    return n
end

-- every enemy the game has a record of (met at least once), weaknesses included
function M.libraAll()
    local sd = game.saveData()
    local known = {}
    each(sd.unitList, function(r) known[#known + 1] = r.SaveId end)
    local enemy = {}
    for _, id in ipairs(data.enemies) do enemy[id] = true end
    local ids = {}
    for _, id in ipairs(known) do if enemy[id] then ids[#ids + 1] = id end end
    return mod:t("libraDone", "{1} enemies scanned with Libra", M.scan(ids))
end

-- consumable item ids, as a set
function M.consumables()
    local set = {}
    for _, id in ipairs(data.consumables) do set[id] = true end
    return set
end

-- the limited stock of every shop back to full
function M.restockShops()
    local sd = game.saveData()
    local n = 0
    each(sd.shop, function(s)
        if s.CurrentBuyNum > 0 then s.CurrentBuyNum = 0; n = n + 1 end
    end)
    return mod:t("restockDone", "{1} shop items restocked", n)
end

-- every area on the map screen (event stages left out)
function M.revealMaps()
    local maps = game.lib("CPP_BFL_SaveData_PerMap")
    local n = 0
    for _, id in ipairs(data.maps) do
        if not maps:IsKnown(id) then maps:AddKnownMap(id); n = n + 1 end
    end
    return mod:t("mapsDone", "{1} maps revealed", n)
end

return M
