-- MogHub Trainer: rewards, battle and field cheats for FINAL FANTASY RESONANCE. A MogHub plugin: its settings
-- are in MogHub's Mods menu and in config.ini. The cheats are reversible: the game's own values are kept and put
-- back when a setting returns to normal. "Your game" holds the FFR Save Editor's quick actions, done to the game
-- being played (see Scripts/live.lua); those are changes to your progress, kept when the game saves.
local mod, kit = ...
local game, tables = kit.game, kit.tables
local live = require("live")
live.init(kit)

-- a quick action from live.lua (with a game loaded): its result, or why it couldn't run, on screen
local function act(fn) return mod:action(fn, { game = true }) end
local valid = kit.valid

local x = "x%g"
local function mult(key, label, min, max, step, help)
    return { key = key, label = label, type = "number", min = min, max = max, step = step, default = 1, format = x, help = help }
end

local cfg
local actions = {}
cfg = mod:settings{
    { header = "Battle" },
    { key = "GodMode", label = "God mode", type = "toggle", default = false,
      help = "Party HP and MP stay full and the damage they take is 0. Hotkey: Ctrl+F1." },
    { key = "InfiniteHP", label = "Infinite HP", type = "toggle", default = false, help = "The party's HP is refilled during battle." },
    { key = "InfiniteMP", label = "Infinite MP", type = "toggle", default = false, help = "The party's MP is refilled during battle." },
    { key = "FullLimitBreak", label = "Full Limit Burst", type = "toggle", default = false, help = "The Limit Burst gauge stays full." },
    mult("LBGainMultiplier", "Limit Burst gain", 0, 5, 0.5, "How fast the Limit Burst gauge fills."),
    { key = "KeepLimitBurst", label = "Keep Limit Burst", type = "toggle", default = false,
      help = "Each character's Limit Burst gauge carries over from one battle to the next." },
    { key = "MPCostPercent", label = "MP cost", type = "number", min = 0, max = 100, step = 10, default = 100, format = "%g%%",
      help = "Skill MP costs, in percent of normal (rounded up, so only 0% makes them free)." },
    { key = "OneHitKill", label = "One-hit kills", type = "toggle", default = false, help = "Enemies go down in one hit. Hotkey: Ctrl+F5." },
    { key = "Preset", label = "Difficulty preset", type = "choice", default = "custom",
      choices = { { "custom", "Custom" }, { "normal", "Normal" }, { "hard", "Hard" }, { "veryhard", "Very hard" },
                  { "nightmare", "Nightmare" } },
      help = "Sets the five values below at once, on top of the game's own difficulty: Hard falls between Normal and "
          .. "Expert, Nightmare goes well beyond Expert. Changing one of the five makes it Custom." },
    mult("DamageDealtMultiplier", "Damage dealt", 0, 10, 0.1),
    mult("DamageTakenMultiplier", "Damage taken", 0, 5, 0.1),
    mult("EnemyHPMultiplier", "Enemy HP", 0.1, 5, 0.1),
    mult("EnemySpeedMultiplier", "Enemy speed", 0.1, 3, 0.1),
    mult("EnemyBreakMultiplier", "Enemy break gauge", 0.1, 5, 0.1, "How much break gauge enemies have."),
    { key = "AlwaysEscape", label = "Always escape", type = "toggle", default = false,
      help = "Running away always works, except in battles that can't be escaped." },
    { key = "HealAfterBattle", label = "Heal after battle", type = "toggle", default = false,
      help = "The party's HP and MP are refilled when a battle ends." },
    { key = "AutoBattle", label = "Auto battle", type = "toggle", default = false,
      help = "Characters act on their own (see Auto battle mode). Attack once by hand first. Hotkey: Ctrl+F2." },
    { key = "AutoBattleMode", label = "Auto battle mode", type = "choice", default = "attack",
      choices = { { "attack", "Attack" }, { "repeat", "Repeat last command" } },
      help = "Attack: every character uses their basic attack. Repeat last command: each character repeats the last "
          .. "command you chose for them (skills and magic, not items); heals and buffs go to the ally with the least "
          .. "HP, and a fallen target is replaced. A command that can't be used (not enough MP) becomes an attack." },
    { key = "AutoConfirmResults", label = "Auto-confirm results", type = "toggle", default = false,
      help = "With auto battle on, the result screens are confirmed for you." },

    { header = "Speed" },
    mult("TurboMultiplier", "Turbo", 1, 4, 1, "Speeds up the whole game: field, battles and cutscenes. Hotkey: Ctrl+F6."),
    mult("BattleSpeedMultiplier", "Battle speed", 0.5, 5, 0.5, "Scales the game's own battle speed steps."),
    mult("FieldSpeedMultiplier", "Walking speed", 0.5, 3, 0.5, "Hotkey: Ctrl+F4."),

    { header = "Rewards" },
    mult("ExpMultiplier", "EXP", 0, 10, 0.5),
    mult("GilMultiplier", "Gil", 0, 10, 0.5),
    mult("MRPMultiplier", "MRP", 0, 10, 0.5),
    mult("APMultiplier", "AP", 0, 10, 0.5),
    mult("DropRateMultiplier", "Drop rate", 0, 10, 0.5),
    { key = "AlwaysDropRare", label = "Always drop rare items", type = "toggle", default = false },
    { key = "AlwaysSteal", label = "Steals always work", type = "toggle", default = false },
    { key = "AlwaysStealRare", label = "Steals give the rare item", type = "toggle", default = false },
    mult("RareEnemyMultiplier", "Rare enemy chance", 1, 10, 1,
         "How often Cactuars, Gil Snappers and Pots turn up in random battles."),
    { key = "GilAmount", label = "Gil to add", type = "choice", default = 10000, keep = true,
      choices = { { 1000, "1,000" }, { 10000, "10,000" }, { 100000, "100,000" }, { 1000000, "1,000,000" } } },
    { label = "Add Gil", type = "action", button = "Add", help = "Adds the amount above to your Gil.",
      run = function() actions.addGil() end },

    { header = "Abilities" },
    { key = "APCostPercent", label = "Ability AP cost", type = "number", min = 0, max = 100, step = 10, default = 100,
      format = "%g%%", help = "The AP abilities, passives and master skills cost to equip, in percent of normal. 0% "
          .. "makes everything free to equip." },

    { header = "Shops" },
    { key = "BuyPricePercent", label = "Buying prices", type = "number", min = 10, max = 200, step = 10, default = 100,
      format = "%g%%", help = "What shops charge, in percent of normal." },
    { key = "SellPricePercent", label = "Selling prices", type = "number", min = 10, max = 500, step = 10, default = 100,
      format = "%g%%", help = "What shops pay for your items, in percent of normal." },
    { key = "UnlimitedStock", label = "Unlimited stock", type = "toggle", default = false,
      help = "Items that shops only sell a few of can be bought without limit." },
    { key = "ShopAllItems", label = "Item shops sell everything", type = "toggle", default = false,
      help = "Every item shop also sells every consumable the game has a price for. Switched off, the added items "
          .. "show as sold out until the game is started again." },

    { header = "Field" },
    { key = "Encounters", label = "Random encounters", type = "toggle", default = true, help = "Hotkey: Ctrl+F3." },
    mult("EncounterRate", "Encounter rate", 0.25, 4, 0.25),

    { header = "Your game" },
    { label = "Heal party", type = "action", button = "Heal", run = act(live.healParty),
      help = "Every character's HP and MP back to full, knocked-out characters included, anywhere." },
    { label = "Max Gil", type = "action", button = "Max", run = act(live.maxGil),
      help = "Sets your Gil to the most the game allows (99,999,999). Like everything in this section, it changes your "
          .. "game right away and is kept when you save; load a save without saving to undo it." },
    { key = "LevelTarget", label = "Level to raise to", type = "number", min = 2, max = 99, step = 1, default = 99,
      keep = true, help = "For \"Raise every character\"." },
    { label = "Raise every character", type = "action", button = "Raise",
      run = act(function() return live.raiseLevels(cfg.LevelTarget) end),
      help = "Every character below the level above gets the EXP for it, through the game's own function for "
          .. "setting EXP. Characters already higher stay as they are." },
    { key = "ItemCount", label = "Consumables count", type = "number", min = 1, max = 99, step = 1, default = 99,
      keep = true, help = "For \"Stock every consumable\"." },
    { label = "Stock every consumable", type = "action", button = "Stock",
      run = act(function() return live.stockConsumables(cfg.ItemCount) end),
      help = "Every consumable (potions, ethers, ...) set to the count above, also the ones you don't have yet." },
    { label = "Get every artifact", type = "action", button = "Get", run = act(live.allArtifacts),
      help = "Adds every finished artifact you don't own yet (the unfinished ones in the game files are left out)." },
    { label = "Max Mastery Rank", type = "action", button = "Max", run = act(live.maxMastery),
      help = "Every character's Mastery Rank with every vision you own, at the maximum." },
    { label = "Max awakening", type = "action", button = "Max", run = act(live.maxAwakening),
      help = "Every vision you own, fully awakened." },
    { label = "Libra on every enemy met", type = "action", button = "Scan", run = act(live.libraAll),
      help = "Every enemy you have met counts as scanned with Libra, weaknesses included, as if you had scanned it "
          .. "in battle." },
    { label = "Restock shops", type = "action", button = "Restock", run = act(live.restockShops),
      help = "The limited items in every shop are back in stock." },
    { label = "Reveal every map", type = "action", button = "Reveal", run = act(live.revealMaps),
      help = "Every area shows on the map screen (event-only stages left out)." },

    { header = "General" },
    { key = "Notices", label = "On-screen messages", type = "toggle", default = true, keep = true,
      help = "Short messages when a hotkey changes something." },
    { label = "Reset everything", type = "action", button = "Reset",
      help = "Puts every option back to the game's normal values.", run = function() actions.reset() end },

    { header = "Keys" },
    { key = "GodModeKey", type = "value", default = "CTRL+F1" },
    { key = "AutoBattleKey", type = "value", default = "CTRL+F2" },
    { key = "EncountersKey", type = "value", default = "CTRL+F3" },
    { key = "FieldSpeedKey", type = "value", default = "CTRL+F4" },
    { key = "OneHitKillKey", type = "value", default = "CTRL+F5" },
    { key = "TurboKey", type = "value", default = "CTRL+F6" },
    { key = "FieldSpeedSteps", type = "value", default = "1,1.5,2,3" },
    { key = "TurboSteps", type = "value", default = "1,2,4" },
}

local function say(msg, color, ms)
    if cfg.Notices then mod:notice(msg, color, ms) else mod:log("%s", msg) end
end

-- FFRS-QoL changes EXP/Gil/MRP, drops, AP, escape, encounters and battle speed. When it is installed those
-- settings are left to it, so the two mods never multiply the same values.
local function qolInstalled()
    if kit.exists(kit.modsDir .. "/FFRS_QoL/enabled.txt") then return true end
    return (kit.readFile(kit.modsDir .. "/mods.txt") or ""):match("FFRS_QoL%s*:%s*1") ~= nil
end
local QOL = qolInstalled()
local QOL_SETTINGS = {
    ExpMultiplier = true, GilMultiplier = true, MRPMultiplier = true, APMultiplier = true,
    DropRateMultiplier = true, AlwaysDropRare = true, AlwaysEscape = true,
    Encounters = true, EncounterRate = true, BattleSpeedMultiplier = true,
}
local function owned(setting) return not (QOL and QOL_SETTINGS[setting]) end
if QOL then
    for key in pairs(QOL_SETTINGS) do
        local item = cfg:item(key)
        if item then item.note = mod:t("qolNote", "(Handled by FFRS-QoL, which is installed: this setting does nothing.)") end
    end
end

---------------------------------------------------------------------------------------------------
-- Data tables
---------------------------------------------------------------------------------------------------
local patch = tables.patcher()
local set = tables.set

-- Difficulty rows (Easy / Normal / Expert): rewards, damage and enemy strength.
local function applyDifficulty()
    local dealt, enemyHP = cfg.DamageDealtMultiplier, cfg.EnemyHPMultiplier
    if cfg.OneHitKill then dealt, enemyHP = math.max(dealt, 10), enemyHP * 0.01 end
    local rates = {
        DamageGivenRate = dealt,
        DamageTakenRate = cfg.GodMode and 0 or cfg.DamageTakenMultiplier,
        EnemyHpRate = enemyHP,
        EnemyAgilityRate = cfg.EnemySpeedMultiplier,
        EnemyBreakRate = cfg.EnemyBreakMultiplier,
    }
    if owned("ExpMultiplier") then
        rates.ExpRate, rates.MoneyRate, rates.MRPointRate = cfg.ExpMultiplier, cfg.GilMultiplier, cfg.MRPMultiplier
    end
    local parts = {}
    for f, m in pairs(rates) do parts[#parts + 1] = f .. "=" .. m end
    table.sort(parts)
    patch:apply("GAME_DIFFICULTY_PARAM", table.concat(parts, ","), function(row, orig)
        for field, m in pairs(rates) do set(row, field, orig(field) * m, orig(field)) end
    end)
end

-- Enemy rows: drop and steal chances are stored as divisors (chance = 100 / rate %, 1 = always, 0 = never).
local function applyUnits()
    local dropM = owned("DropRateMultiplier") and cfg.DropRateMultiplier or nil
    local rare = owned("AlwaysDropRare") and cfg.AlwaysDropRare
    local state = string.format("%s|%s|%s|%s", tostring(dropM), tostring(rare), tostring(cfg.AlwaysStealRare), tostring(cfg.AlwaysSteal))
    local function scaled(v)
        if v <= 0 or not dropM then return v end
        if dropM <= 0 then return 0 end
        return math.max(1, math.floor(v / dropM + 0.5))
    end
    patch:apply("UNIT_PARAMETER", state, function(row, orig)
        if dropM then
            local normal, rareRate, rareItem = orig("DropNormalItemRate"), orig("DropRareItemRate"), orig("DropRareItem")
            set(row, "DropNormalItemRate", scaled(normal), normal)
            set(row, "DropRareItemRate", (rare and rareItem > 0 and rareRate > 0) and 1 or scaled(rareRate), rareRate)
        end
        -- steals pick the normal item unless a rare roll succeeds: make the normal slot the rare item
        local stealNormal, stealRare = orig("StealNormalItem"), orig("StealRareItem")
        local want = (cfg.AlwaysStealRare and stealRare > 0) and stealRare or stealNormal
        if row.StealNormalItem ~= want then row.StealNormalItem = want end
        local stealRate = orig("StealItemRate")
        set(row, "StealItemRate", (cfg.AlwaysSteal and stealRate > 0) and 1 or stealRate, stealRate)
    end)
end

-- Battle groups: AP reward and escape chance (percent). Escape is only forced where it's allowed.
local function applyGroups()
    if not owned("APMultiplier") then return end
    patch:apply("BATTLE_GROUP_DATA", string.format("%.3f|%s", cfg.APMultiplier, tostring(cfg.AlwaysEscape)), function(row, orig)
        set(row, "ap", orig("ap") * cfg.APMultiplier, orig("ap"))
        local escape = orig("probabilityOfSuccessfulEscape")
        set(row, "probabilityOfSuccessfulEscape", (cfg.AlwaysEscape and row.CanEscape) and 1000 or escape, escape)
    end)
end

-- Maps: a random battle starts after walking a random distance, so the rate divides those distances.
local LENGTHS = { "encountMinMovementLength", "encountMaxMovementLength",
                  "chocoboEncountMinMovementLength", "chocoboEncountMaxMovementLength" }
local function applyMaps()
    if not owned("Encounters") then return end
    local rate = math.max(0.1, cfg.EncounterRate)
    patch:apply("MAP_DATA", string.format("%s|%.3f", tostring(cfg.Encounters), rate), function(row, orig)
        local want = cfg.Encounters and orig("doMovementEncount") or false
        if row.doMovementEncount ~= want then row.doMovementEncount = want end
        for _, f in ipairs(LENGTHS) do set(row, f, orig(f) / rate, orig(f)) end
    end)
end

-- Battle speed: the game's own speed steps are scaled, so its speed button keeps working.
local speedOrig = {}
local function applyBattleSpeed()
    local m = (owned("BattleSpeedMultiplier") and cfg.BattleSpeedMultiplier or 1) * cfg.TurboMultiplier
    patch:apply("BTL_GENERAL_DATA", string.format("%.3f", m), function(row, _, rowName, t)
        row.GameSpeedList:ForEach(function(i, e)
            local k = t.path .. "|" .. rowName .. "|" .. i
            if speedOrig[k] == nil then speedOrig[k] = e:get() end
            e:set(speedOrig[k] * m)
        end)
    end)
end

-- Skills: MP cost.
-- Skills: MP cost and equip (AP) cost, in percent; rounded up, so only 0% makes a cost free.
local function percent(v, pct)
    if v <= 0 or pct >= 100 then return v end
    if pct <= 0 then return 0 end
    return math.ceil(v * pct / 100)
end
local function applySkills()
    local mp, ap = cfg.MPCostPercent, cfg.APCostPercent
    patch:apply("SKILL_DATA", mp .. "|" .. ap, function(row, orig)
        set(row, "Cost", percent(orig("Cost"), mp), orig("Cost"))
        set(row, "equipCost", percent(orig("equipCost"), ap), orig("equipCost"))
    end)
    for _, struct in ipairs({ "PASSIVE_SKILL_DATA", "MASTER_SKILL_DATA" }) do
        patch:apply(struct, tostring(ap), function(row, orig)
            set(row, "equipCost", percent(orig("equipCost"), ap), orig("equipCost"))
        end)
    end
end

-- Shops: buying prices (each shop item's PriceRatio) and limited stock (MaxOrderNum, -1 = unlimited). Shop items are
-- struct elements of an array, so their originals are kept here. Numbers only: the items' Condition (a story lock)
-- is a string, and the version that rewrote it crashed the game at start-up (strings inside struct arrays are a weak
-- spot of UE4SS 3.0.1).
--
-- "Item shops sell everything": item shops (shops whose list holds consumables only) get every consumable with a
-- buying price added to the end of their list (numbers only: item id, unlimited stock, price ratio 1). The game's
-- array can't be shortened from Lua, so switching it off marks the added items sold out (MaxOrderNum 0) until the
-- tables are loaded again at the next start.
local shopOrig, shopAdded = {}, {}       -- originals by array element; ids added per shop row
local function sellable()
    local out, order = {}, {}
    tables.rows("CONSUMABLES_ITEM_DATA", function(row)
        if (row.buyingPrice or 0) > 0 and not out[row.ID] then out[row.ID] = true; order[#order + 1] = row.ID end
    end)
    table.sort(order)
    return out, order
end
local function applyShops()
    local buy, unlimited, all = cfg.BuyPricePercent, cfg.UnlimitedStock, cfg.ShopAllItems
    local consumable, order
    patch:apply("SHOP_ShopList1", buy .. "|" .. tostring(unlimited) .. "|" .. tostring(all), function(row, _, rowName, t)
        local key = t.path .. "|" .. rowName
        local added = shopAdded[key] or {}
        shopAdded[key] = added
        if all then
            if not consumable then consumable, order = sellable() end
            local have, onlyItems, n = {}, true, 0
            row.ItemList:ForEach(function(_, e)
                local id = e:get().ItemId
                n = n + 1
                have[id] = true
                if id >= 0 and not consumable[id] then onlyItems = false end
            end)
            if onlyItems and n > 0 then
                for _, id in ipairs(order) do
                    if not have[id] then
                        n = n + 1
                        row.ItemList[n] = { ItemId = id, MaxOrderNum = -1, PriceRatio = 1.0 }
                        added[id] = true
                    end
                end
            end
        end
        row.ItemList:ForEach(function(i, e)
            local s = e:get()
            local k = key .. "|" .. i
            local o = shopOrig[k]
            if not o then
                o = { price = s.PriceRatio, max = s.MaxOrderNum, added = added[s.ItemId] }
                if o.added then o.price, o.max = 1.0, -1 end
                shopOrig[k] = o
            end
            local price = o.price * buy / 100
            if math.abs(s.PriceRatio - price) > 1e-6 then s.PriceRatio = price end
            local max = unlimited and -1 or o.max
            if o.added and not all then max = 0 end      -- switched off: sold out until the next start
            if s.MaxOrderNum ~= max then s.MaxOrderNum = max end
        end)
    end)
end

-- Selling prices: each item's sellingPrice.
local function applySellPrices()
    local pct = cfg.SellPricePercent
    for _, struct in ipairs({ "CONSUMABLES_ITEM_DATA", "EQUIPMENT_ITEM_DATA", "SEED_ITEM_DATA" }) do
        patch:apply(struct, tostring(pct), function(row, orig)
            pcall(function()
                local o = orig("sellingPrice")
                if o then set(row, "sellingPrice", o * pct / 100, o) end
            end)
        end)
    end
end

-- Rare enemies: the weight of the random-encounter groups they are in (ENCOUNT_GROUP_DATA encountRatio, out of the
-- table's total). Unit ids from DT_UnitParameter: Cactuar (two), Metal Cactuar, the Gil Snappers and the Pots.
local RARE = { [38] = true, [2092] = true, [297] = true, [293] = true, [294] = true, [295] = true, [299] = true,
               [300] = true, [301] = true, [302] = true, [303] = true, [304] = true }
local rareGroups
local function findRareGroups()
    local out = {}
    tables.rows("BATTLE_GROUP_DATA", function(row)
        for _, id in ipairs(kit.ue.values(row.UnitIdList)) do if RARE[id] then out[row.ID] = true end end
    end)
    return next(out) and out or nil
end
local function applyRareEnemies()
    local m = cfg.RareEnemyMultiplier
    rareGroups = rareGroups or findRareGroups()
    if not rareGroups then return end
    patch:apply("ENCOUNT_GROUP_DATA", tostring(m), function(row, orig)
        if rareGroups[row.battleGroupId] then
            local o = orig("encountRatio")
            set(row, "encountRatio", math.min(1000, o * m), o)
        end
    end)
end

-- While encounters are off, the walked distance needed for the current map's next battle is pushed out of reach.
local thresholds, FAR = {}, 1.0e9
local function applyPlayerThreshold()
    if not owned("Encounters") then return end
    for _, p in ipairs(game.all("CPP_MapUnit_Playable")) do
        local key = p:GetFullName()
        local cur = p.m_EncountThresholdDistance
        if not cfg.Encounters then
            if cur < FAR then thresholds[key] = cur; p.m_EncountThresholdDistance = FAR end
        elseif thresholds[key] then
            if cur >= FAR then p.m_EncountThresholdDistance = thresholds[key] end
            thresholds[key] = nil
        end
    end
end

local function applyTables()
    for name, fn in pairs({ difficulty = applyDifficulty, enemies = applyUnits, ["battle groups"] = applyGroups,
                            maps = applyMaps, ["battle speed"] = applyBattleSpeed, skills = applySkills,
                            ["encounter distance"] = applyPlayerThreshold, shops = applyShops,
                            ["selling prices"] = applySellPrices, ["rare enemies"] = applyRareEnemies }) do
        mod:guard(name, fn)
    end
end

---------------------------------------------------------------------------------------------------
-- Battle: HP / MP / Limit Burst refills through the game's own setters, and healing after battle
---------------------------------------------------------------------------------------------------
local function refillParty()
    local hp, mp, lb = cfg.GodMode or cfg.InfiniteHP, cfg.GodMode or cfg.InfiniteMP, cfg.FullLimitBreak
    if not (hp or mp or lb) or not kit.events.battle then return end
    local unitLib, battleLib = game.lib("CPP_BFL_Unit"), game.lib("CPP_BFL_Battle")
    if not (unitLib and battleLib) then return end
    local maxLB = lb and unitLib:GetLimitBurstPointMaxGauge() or 0
    for _, u in ipairs(game.battleSide(game.FRIENDLY)) do
        mod:guard("refill", function()
            local p, id = u.param, u.id
            local cur = p:GetHitPoint()
            if cur <= 0 then return end                      -- knocked out: left to the game
            if hp and cur < p:GetMaxHitPoint() then unitLib:SetPlayableUnitHitPoint(id, p:GetMaxHitPoint()) end
            if mp and p:GetMagicPoint() < p:GetMaxMagicPoint() then unitLib:SetPlayableUnitMagicPoint(id, p:GetMaxMagicPoint()) end
            if lb and maxLB > 0 and p:GetLimitBurstPoint() < maxLB then battleLib:SetBattleUnitLimitBurstPoint(id, maxLB) end
        end)
    end
end

-- Limit Burst: gains scaled as they happen (each increase of a character's gauge since the last look is multiplied),
-- and each gauge kept from one battle to the next (put back in the first seconds of a battle, after the game set it).
local lbLast, lbKept, lbRestoreUntil = {}, {}, 0
local function limitBurst()
    local m, keep = cfg.LBGainMultiplier, cfg.KeepLimitBurst
    if not kit.events.battle or ((m == 1 or cfg.FullLimitBreak) and not keep) then return end
    local unitLib, battleLib = game.lib("CPP_BFL_Unit"), game.lib("CPP_BFL_Battle")
    if not (unitLib and battleLib) then return end
    local max = unitLib:GetLimitBurstPointMaxGauge()
    local restoring = keep and os.clock() < lbRestoreUntil
    for _, u in ipairs(game.battleSide(game.FRIENDLY)) do
        mod:guard("limit burst", function()
            local id = u.id
            local cur = u.param:GetLimitBurstPoint()
            if restoring and lbKept[id] and cur < lbKept[id] then
                cur = math.min(max, lbKept[id])
                battleLib:SetBattleUnitLimitBurstPoint(id, cur)
            end
            local last = lbLast[id]
            if last and cur > last and m ~= 1 and not cfg.FullLimitBreak then
                local want = math.max(last, math.min(max, math.floor(last + (cur - last) * m + 0.5)))
                if want ~= cur then battleLib:SetBattleUnitLimitBurstPoint(id, want); cur = want end
            end
            lbLast[id] = cur
            if keep and not restoring then lbKept[id] = cur end
        end)
    end
end

-- the party's maximums, remembered during battle and restored once it is over
local party = {}
local function rememberParty()
    if not (cfg.HealAfterBattle and kit.events.battle) then return end
    for _, u in ipairs(game.battleSide(game.FRIENDLY)) do
        pcall(function() party[u.id] = { hp = u.param:GetMaxHitPoint(), mp = u.param:GetMaxMagicPoint() } end)
    end
end
mod:on("battleStart", function()
    party = {}
    lbLast, lbRestoreUntil = {}, os.clock() + 3
end)
mod:on("battleEnd", function()
    if not cfg.HealAfterBattle or not next(party) then return end
    local list = party
    party = {}
    mod:after(1500, function()
        local unitLib = game.lib("CPP_BFL_Unit")
        if not unitLib then return end
        local n = 0
        for id, m in pairs(list) do
            local ok = mod:guard("heal", function()
                unitLib:SetPlayableUnitHitPoint(id, m.hp)
                unitLib:SetPlayableUnitMagicPoint(id, m.mp)
            end)
            if ok then n = n + 1 end
        end
        if n > 0 then say(mod:t("partyHealed", "Party healed"), "on") end
    end, "heal after battle")
end)

-- Turbo on the field: world time dilation. In battle the game sets it every frame from its own speed steps, which
-- applyBattleSpeed scales instead.
local turboSet = false
local function applyTurbo()
    local m = cfg.TurboMultiplier
    if (m == 1 and not turboSet) or kit.events.battle then return end
    local ws = game.first("WorldSettings")
    if not ws then return end
    if math.abs(ws.TimeDilation - m) > 0.001 then ws.TimeDilation = m end
    turboSet = m ~= 1
end

-- Walking speed: the player character's own time dilation (movement and animation together).
local fieldSpeedSet = false
local function applyFieldSpeed()
    local m = cfg.FieldSpeedMultiplier
    if m == 1 and not fieldSpeedSet then return end
    for _, p in ipairs(game.all("CPP_MapUnit_Playable")) do
        if math.abs(p.CustomTimeDilation - m) > 0.001 then p.CustomTimeDilation = m end
    end
    fieldSpeedSet = m ~= 1
end

---------------------------------------------------------------------------------------------------
-- Auto battle: when a character's command menu opens, a command is sent through the game's own "command decided"
-- event, as if chosen by hand: the basic attack, or (mode "repeat") the last command the player chose for that
-- character. Commands are copied from ones the player made, so the game always receives a shape it produced itself.
---------------------------------------------------------------------------------------------------
local auto = { menuOpen = false, menuSerial = 0, templates = {}, generic = nil, hinted = false, last = {} }
local FRIENDLY_REL = game.enum.Relation.Friendlies
local values = kit.ue.values

local function fightSkill(battleLib, unitId)
    local u = battleLib:GetBattleUnitByUniqueId(unitId, true)
    if not valid(u) then return nil end
    local ai = u:GetUnitAI()
    if not valid(ai) then return nil end
    local skill = ai:GetFightSkillId()
    return (skill and skill > 0) and skill or nil
end

-- remembers each character's last command (for "repeat"), and basic attacks (one action, not an item, from the
-- attack entry rather than a skill menu) as the template for attacking
local function recordDecision(v)
    if v.CmdType ~= 0 then return end
    local items = {}
    v.cmdDecideDataList:ForEach(function(_, e)
        local d = e:get()
        items[#items + 1] = { actionId = d.actionId, unit = d.actionUnitUniqueId, isUseItem = d.isUseItem,
                              IsAll = d.IsAll, params = values(d.ParameterList), targets = values(d.targetUnitUniqueIdList),
                              pCat = d.ParentActionKey.Category, pId = d.ParentActionKey.ID }
    end)
    if #items == 0 then return end
    local keysAll = {}
    v.actionKeys:ForEach(function(_, e)
        local k = e:get()
        keysAll[#keysAll + 1] = { Category = k.Category, ID = k.ID }
    end)
    local battleLib0 = game.lib("CPP_BFL_Battle")
    local unitId = battleLib0 and battleLib0:GetUnitIdByUniqueId(items[1].unit)
    if unitId and unitId > 0 then
        auto.last[unitId] = { CmdType = v.CmdType, CommandId = v.CommandId, isNotConsume = v.isNotConsume,
                              doCalcOrder = v.doCalcOrder, items = items, keys = keysAll }
    end
    if v.CommandId ~= -1 then return end
    if #items ~= 1 or items[1].isUseItem or items[1].IsAll then return end
    local battleLib = game.lib("CPP_BFL_Battle")
    if not battleLib or fightSkill(battleLib, items[1].unit) ~= items[1].actionId then return end
    local keys = {}
    v.actionKeys:ForEach(function(_, e)
        local k = e:get()
        keys[#keys + 1] = { Category = k.Category, ID = k.ID }
    end)
    local tpl = { isNotConsume = v.isNotConsume, doCalcOrder = v.doCalcOrder, item = items[1], keys = keys }
    auto.templates[items[1].unit] = tpl
    auto.generic = tpl
end

local function autoAttack()
    local ui = game.first("CPP_UI_BattleSubsystem")
    if not ui then return end
    local actor, phase = ui.CurrentActionUnitUniqueId, ui.BtlPhaseType
    if actor == nil or actor < 0 then return end
    if phase ~= game.enum.BtlPhase.Normal then say(mod:t("autoChoose", "Auto battle: choose this action yourself"), "warn", 2000); return end
    local tpl = auto.templates[actor] or auto.generic
    if not tpl then
        if not auto.hinted then
            auto.hinted = true
            say(mod:t("autoLearn", "Auto battle: attack once by hand, then it takes over"), "warn", 3500)
        end
        return
    end
    local battleLib = game.lib("CPP_BFL_Battle")
    local skill = battleLib and fightSkill(battleLib, actor)
    if not skill or battleLib:IsEnableCommand(actor, skill) == false then return end
    local target = battleLib:GetDefaultSkillTargetUnitUniqueId(actor, skill)
    if target == nil or target < 0 then return end

    local class = StaticFindObject("/Script/mucha.CPP_BtlCmdDecideDelegateVal")
    local dispatcher = FindFirstOf("CPP_MuchaEventDispatcher")
    if not (valid(class) and valid(dispatcher)) then return end
    local v = StaticConstructObject(class, dispatcher)
    v.CmdType = 0
    v.isNotConsume = tpl.isNotConsume
    v.doCalcOrder = tpl.doCalcOrder
    v.CommandId = -1
    local it = tpl.item
    v.cmdDecideDataList[1] = { actionId = skill, actionUnitUniqueId = actor }
    local d = v.cmdDecideDataList[1]
    d.actionId = skill
    d.actionUnitUniqueId = actor
    d.isUseItem = false
    d.IsAll = false
    d.ParentActionKey.Category = it.pCat
    d.ParentActionKey.ID = (it.pId == it.actionId) and skill or it.pId
    d.targetUnitUniqueIdList[1] = target
    for j, p in ipairs(it.params) do d.ParameterList[j] = p end
    for i, k in ipairs(tpl.keys) do
        local id = (k.ID == it.actionId) and skill or k.ID
        v.actionKeys[i] = { Category = k.Category, ID = id }
        v.actionKeys[i].Category = k.Category
        v.actionKeys[i].ID = id
    end
    dispatcher:ExecuteEvent({ TagName = FName("Delegate.Battle.Cmd.Decide") }, v)
end

-- the ally a support skill helps most: the living one with the smallest share of HP among the skill's targets
local function weakestAlly(battleLib, actor, skill)
    local list = {}
    pcall(function() battleLib:GetSkillTargetUnitUniqueIdList(list, actor, skill, FRIENDLY_REL, true) end)
    local best, bestRatio
    for _, uid in ipairs(values(list)) do
        pcall(function()
            local p = battleLib:GetBattleUnitParameter(uid, true)
            local ratio = p:GetHitPoint() / math.max(1, p:GetMaxHitPoint())
            if not bestRatio or ratio < bestRatio then best, bestRatio = uid, ratio end
        end)
    end
    return best
end

-- the character's last command again; false when there is none or it can't be used (then they attack instead)
local function repeatLast(actor)
    local battleLib = game.lib("CPP_BFL_Battle")
    if not battleLib then return false end
    local rec = auto.last[battleLib:GetUnitIdByUniqueId(actor)]
    if not rec then return false end
    local plan = {}
    for _, it in ipairs(rec.items) do
        if it.isUseItem then return false end                   -- items are never spent on their own
        if battleLib:IsEnableCommand(actor, it.actionId) == false then return false end
        local targets = {}
        if it.IsAll then
            for _, t in ipairs(it.targets) do if not battleLib:IsUnitDead(t) then targets[#targets + 1] = t end end
        else
            local t, ally = it.targets[1], false
            if t then pcall(function() ally = battleLib:GetBattleUnitParameter(t, false):GetRelation() == FRIENDLY_REL end) end
            if ally then
                t = weakestAlly(battleLib, actor, it.actionId) or t
            elseif not t or battleLib:IsUnitDead(t) then
                t = battleLib:GetDefaultSkillTargetUnitUniqueId(actor, it.actionId)
            end
            if t and t >= 0 then targets[1] = t end
        end
        if #targets == 0 then return false end
        plan[#plan + 1] = { it = it, targets = targets }
    end

    local class = StaticFindObject("/Script/mucha.CPP_BtlCmdDecideDelegateVal")
    local dispatcher = FindFirstOf("CPP_MuchaEventDispatcher")
    if not (valid(class) and valid(dispatcher)) then return false end
    local v = StaticConstructObject(class, dispatcher)
    v.CmdType = rec.CmdType
    v.isNotConsume = rec.isNotConsume
    v.doCalcOrder = rec.doCalcOrder
    v.CommandId = rec.CommandId
    for n, step in ipairs(plan) do
        local it = step.it
        v.cmdDecideDataList[n] = { actionId = it.actionId, actionUnitUniqueId = actor }
        local d = v.cmdDecideDataList[n]
        d.actionId = it.actionId
        d.actionUnitUniqueId = actor
        d.isUseItem = false
        d.IsAll = it.IsAll
        d.ParentActionKey.Category = it.pCat
        d.ParentActionKey.ID = it.pId
        for j, t in ipairs(step.targets) do d.targetUnitUniqueIdList[j] = t end
        for j, prm in ipairs(it.params) do d.ParameterList[j] = prm end
    end
    for i, k in ipairs(rec.keys) do
        v.actionKeys[i] = { Category = k.Category, ID = k.ID }
        v.actionKeys[i].Category = k.Category
        v.actionKeys[i].ID = k.ID
    end
    dispatcher:ExecuteEvent({ TagName = FName("Delegate.Battle.Cmd.Decide") }, v)
    return true
end

-- the active character's turn: their last command (mode "repeat") or the basic attack
local function autoAct()
    if cfg.AutoBattleMode == "repeat" then
        local ui = game.first("CPP_UI_BattleSubsystem")
        local actor = ui and ui.CurrentActionUnitUniqueId
        if ui and ui.BtlPhaseType == game.enum.BtlPhase.Normal and actor and actor >= 0 then
            local ok, done = pcall(repeatLast, actor)
            if not ok then kit.logOnce(mod.tag, "repeat last command", done) end
            if ok and done then return end
        end
    end
    autoAttack()
end

mod:hook("/Script/mucha.CPP_BtlDelEventCmd:OnExecuteDecideCommand", function(_, value) recordDecision(value:get()) end)
mod:on("gameEvent", function(name)
    if name == "Delegate.Battle.Cmd.List.Begin" then
        auto.menuOpen = true
        auto.menuSerial = auto.menuSerial + 1
        if cfg.AutoBattle then
            local mine = auto.menuSerial
            mod:after(400, function()
                if cfg.AutoBattle and auto.menuOpen and auto.menuSerial == mine then autoAct() end
            end, "auto battle")
        end
    elseif name == "Delegate.Battle.Cmd.List.End" then
        auto.menuOpen = false
    end
end)

-- result screens: "confirm" on the active result page, like the player would
local lastConfirm = 0
local function confirmResults()
    if not (cfg.AutoBattle and cfg.AutoConfirmResults) or os.clock() - lastConfirm < 0.5 then return end
    for _, layout in ipairs(game.all("WBP_Btl_ResultLayout_C")) do
        if layout:IsInViewport() and layout:IsVisible() and layout:IsActivated() then
            if game.isPaused() then return end
            layout:InputDecide(1)                            -- pressed
            layout:InputDecide(2)                            -- released
            lastConfirm = os.clock()
            return
        end
    end
end

---------------------------------------------------------------------------------------------------
-- Menu buttons and hotkeys
---------------------------------------------------------------------------------------------------
actions.addGil = mod:action(function()
    local amount = math.floor(cfg.GilAmount)
    game.lib("CPP_BFL_SaveDataPlayer"):AddCurrentMoney(amount, false)
    return mod:t("gilAdded", "{1} Gil added", amount)
end, { game = true, notify = function(...) say(...) end })

function actions.reset()
    cfg:reset()
    patch:invalidate()
    applyTables()
    say(mod:t("resetDone", "MogHub Trainer: everything back to normal"), "on")
end

local function toggle(key) return cfg:toggle(key, say) end

-- the next of a comma list of steps above the current value, wrapping to the first
local function nextStep(list, current, fallback)
    local steps = {}
    for v in tostring(list):gmatch("[^,%s]+") do if tonumber(v) then steps[#steps + 1] = tonumber(v) end end
    if #steps == 0 then steps = fallback end
    for _, v in ipairs(steps) do if v > current + 0.001 then return v end end
    return steps[1]
end

mod:key(cfg.GodModeKey, function() toggle("GodMode") end, "GodModeKey")
mod:key(cfg.OneHitKillKey, function() toggle("OneHitKill") end, "OneHitKillKey")
mod:key(cfg.AutoBattleKey, function()
    toggle("AutoBattle")
    if cfg.AutoBattle and auto.menuOpen then autoAct() end
end, "AutoBattleKey")
mod:key(cfg.EncountersKey, function()
    if not owned("Encounters") then say(mod:t("qolEncounters", "Encounters are handled by FFRS-QoL"), "warn"); return end
    toggle("Encounters")
end, "EncountersKey")
mod:key(cfg.FieldSpeedKey, function()
    cfg:set("FieldSpeedMultiplier", nextStep(cfg.FieldSpeedSteps, cfg.FieldSpeedMultiplier, { 1, 1.5, 2, 3 }))
    applyFieldSpeed()
    say(mod:t("walkSpeed", "Walking speed: x{1}", string.format("%g", cfg.FieldSpeedMultiplier)), cfg.FieldSpeedMultiplier == 1 and "off" or "on")
end, "FieldSpeedKey")
mod:key(cfg.TurboKey, function()
    cfg:set("TurboMultiplier", nextStep(cfg.TurboSteps, cfg.TurboMultiplier, { 1, 2, 4 }))
    applyTurbo()
    say(mod:t("turbo", "Turbo: x{1}", string.format("%g", cfg.TurboMultiplier)), cfg.TurboMultiplier == 1 and "off" or "on")
end, "TurboKey")

---------------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------------
-- Difficulty presets: damage dealt, damage taken, enemy HP, enemy speed, enemy break gauge, on top of the game's
-- own difficulty (Hard sits between Normal and Expert, as Expert's own rates are 0.8 / 1.4 / 1.6 / 1.4 / 1.6)
local PRESET_KEYS = { "DamageDealtMultiplier", "DamageTakenMultiplier", "EnemyHPMultiplier", "EnemySpeedMultiplier",
                      "EnemyBreakMultiplier" }
local PRESETS = { normal = { 1, 1, 1, 1, 1 }, hard = { 0.9, 1.2, 1.3, 1.2, 1.3 }, veryhard = { 0.8, 1.4, 1.6, 1.4, 1.6 },
                  nightmare = { 0.7, 1.6, 2, 1.5, 2 } }
local presetKey, settingPreset = {}, false
for _, k in ipairs(PRESET_KEYS) do presetKey[k] = true end
cfg:onChange(function(key, value)
    if key == "Preset" and PRESETS[value] then
        settingPreset = true
        for i, k in ipairs(PRESET_KEYS) do cfg:set(k, PRESETS[value][i]) end
        settingPreset = false
    elseif presetKey[key] and not settingPreset and cfg.Preset ~= "custom" then
        cfg:set("Preset", "custom")
    end
end)

-- "No MP cost" (0.3.0) became "MP cost" in percent: a config that had it on gets 0%
do
    local old = kit.config.read(mod:path("config.ini"))
    if old.NoMPCost and kit.config.bool(old.NoMPCost, false) and cfg.MPCostPercent == 100 then cfg:set("MPCostPercent", 0) end
end

cfg:onChange(function() applyTables(); applyTurbo(); applyFieldSpeed() end)
-- switched off in the Mods menu: settings read as their defaults, so applying them undoes every change
mod:onToggle(function() applyTables(); applyTurbo(); applyFieldSpeed() end)
local ticks = 0
mod:every(1000, function()
    ticks = ticks + 1
    if ticks % 2 == 0 then applyTables() end              -- tables reloaded by a map change get the edits again
    rememberParty()
    applyFieldSpeed()
    applyTurbo()
end, "main loop")
mod:every(500, refillParty, "refill")
mod:every(250, limitBurst, "limit burst")
mod:every(400, confirmResults, "results")
if QOL then mod:log("FFRS-QoL found: its settings are left to it") end
