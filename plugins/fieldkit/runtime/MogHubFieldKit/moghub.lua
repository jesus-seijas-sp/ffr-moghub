-- MogHub Field Kit: field and HUD comforts for FINAL FANTASY RESONANCE, each one a switch in MogHub's Mods menu (and
-- config.ini). Everything goes back to the game's own state when its switch, or the plugin, is turned off.
local mod, kit = ...
local game, tables = kit.game, kit.tables
local valid = kit.valid
local VIS = game.enum.Visibility

local cfg
cfg = mod:settings{
    { header = "HUD" },
    { key = "HideMinimap", label = "Hide minimap", type = "toggle", default = false,
      help = "Hides the minimap in the top-right corner. The map screen still works." },
    { key = "HideQuestTracker", label = "Hide quest tracker", type = "toggle", default = false,
      help = "Hides the chapter and current goal in the top-left corner. The Quests menu still shows them." },
    { key = "HideKeyGuide", label = "Hide key guide", type = "toggle", default = false,
      help = "Hides the list of field keys on the left (Mount Chocobo, World Map, Quests...). The keys keep working." },
    { key = "HideHUD", label = "Hide the whole HUD", type = "toggle", default = false,
      help = "Hides everything drawn over the field, for screenshots or a clean screen. Hotkey: Ctrl+F7." },
    { header = "Field" },
    { key = "EncounterMeter", label = "Encounter meter", type = "toggle", default = false,
      help = "Shows how far you are from the next random battle, under the minimap. Hotkey: Ctrl+F8." },
    { key = "SaveAnywhere", label = "Save anywhere", type = "toggle", default = false,
      help = "Save in the system menu (Esc) works everywhere, not only at save points and on the world map. "
          .. "Never during battles or story scenes." },
    { header = "Battle" },
    { key = "QuietVoices", label = "Quieter battle voices", type = "choice", default = "off",
      choices = { { "off", "Off" }, { "turn", "Turn start" }, { "menus", "Turn start and menus" },
                  { "more", "Also battle start and victory" } },
      help = "Silences the lines characters say over and over: at the start of each turn, when opening the skill and "
          .. "Ex menus, and at the start and end of battles. Skill shouts, reactions and story voices stay." },
    { key = "EscapeRewards", label = "Escape rewards", type = "toggle", default = false,
      help = "Fleeing a battle after defeating at least one enemy still gives the EXP and Gil of the enemies you "
          .. "defeated." },
    { header = "Start-up" },
    { key = "SkipLogos", label = "Skip intro logos", type = "toggle", default = false,
      help = "The logos shown when the game starts go by at once. Takes effect the next time the game starts." },
    { key = "HideHUDKey", type = "value", default = "CTRL+F7" },
    { key = "EncounterMeterKey", type = "value", default = "CTRL+F8" },
}

---------------------------------------------------------------------------------------------------
-- HUD: parts of the field layout (WBP_FieldLayout_C) hidden while their switch is on. The visibility each part had
-- is kept and put back, and a part the game shows again (a quest update, the minimap key) is hidden again.
---------------------------------------------------------------------------------------------------
local HIDDEN = VIS.Hidden                                -- (keeps its space)
local PARTS = {
    { key = "HideMinimap", name = "WBP_MiniMapLayout" },
    { key = "HideQuestTracker", name = "WBP_FieldQuestLayout" },
    { key = "HideKeyGuide", name = "WBP_FieldFuncList2" },
}
local hud = { layout = nil, parts = {}, orig = {} }

local function findChild(w, name, depth)
    if not valid(w) or depth > 6 then return nil end
    if w:GetFName():ToString() == name then return w end
    local ok, n = pcall(function() return w:GetChildrenCount() end)
    if ok and n then
        for i = 0, n - 1 do
            local found = findChild(w:GetChildAt(i), name, depth + 1)
            if found then return found end
        end
    end
end

local function fieldLayout()
    if valid(hud.layout) then return hud.layout end
    hud.layout, hud.parts, hud.orig = game.first("WBP_FieldLayout_C"), {}, {}
    if not valid(hud.layout) then hud.layout = nil; return nil end
    local root = hud.layout.WidgetTree.RootWidget
    for _, p in ipairs(PARTS) do hud.parts[p.key] = findChild(root, p.name, 0) end
    return hud.layout
end

-- keeps one widget hidden (want) or puts back what it had
local function hold(id, w, want)
    if not valid(w) then return end
    local vis = w:GetVisibility()
    if want then
        if vis ~= HIDDEN then
            hud.orig[id] = vis
            w:SetVisibility(HIDDEN)
        end
    elseif hud.orig[id] ~= nil then
        if vis == HIDDEN then w:SetVisibility(hud.orig[id]) end
        hud.orig[id] = nil
    end
end

local function anyHidden()
    for _, p in ipairs(PARTS) do if cfg[p.key] then return true end end
    return cfg.HideHUD or next(hud.orig) ~= nil
end

local function applyHUD()
    if not anyHidden() then return end                  -- nothing to hide or put back: leave the HUD alone
    local layout = fieldLayout()
    if not layout then return end
    for _, p in ipairs(PARTS) do hold(p.key, hud.parts[p.key], cfg[p.key]) end
    hold("layout", layout, cfg.HideHUD)
end

---------------------------------------------------------------------------------------------------
-- Encounter meter: the share of the walk to the next random battle already done (the map manager's own
-- GetEncountMovementLengthParcentage), as a bar and a number under the minimap. Shown in the field only, on maps
-- with random battles.
---------------------------------------------------------------------------------------------------
local meter = {}

local function make(class, outer, name)
    return StaticConstructObject(StaticFindObject("/Script/UMG." .. class), outer, FName(name))
end

local function meterWidget()
    if valid(meter.widget) and valid(meter.text) and valid(meter.bar) then return meter end
    local gi = FindFirstOf("GameInstance")
    if not valid(gi) then return nil end
    meter.serial = (meter.serial or 0) + 1
    local base = "MogHubFieldKit_Meter_" .. meter.serial
    local w = make("UserWidget", gi, base)
    local tree = make("WidgetTree", w, base .. "_Tree")
    w.WidgetTree = tree
    local canvas = make("CanvasPanel", tree, base .. "_Canvas")
    tree.RootWidget = canvas
    local box = make("Border", tree, base .. "_Box")
    box:SetBrushColor({ R = 0.02, G = 0.04, B = 0.12, A = 0.6 })
    box:SetPadding({ Left = 12, Top = 6, Right = 12, Bottom = 8 })
    local slot = canvas:AddChildToCanvas(box)
    slot:SetAutoSize(true)
    slot:SetAnchors({ Minimum = { X = 1, Y = 0 }, Maximum = { X = 1, Y = 0 } })
    slot:SetAlignment({ X = 1, Y = 0 })
    slot:SetPosition({ X = -70, Y = 390 })                -- just below the minimap frame
    local column = make("VerticalBox", tree, base .. "_Column")
    box:SetContent(column)
    local text = make("TextBlock", tree, base .. "_Text")
    local font = text.Font
    font.Size = 18
    text:SetFont(font)
    column:AddChildToVerticalBox(text)
    local size = make("SizeBox", tree, base .. "_BarSize")
    size:SetWidthOverride(220)
    size:SetHeightOverride(8)
    local bar = make("ProgressBar", tree, base .. "_Bar")
    size:SetContent(bar)
    column:AddChildToVerticalBox(size):SetPadding({ Left = 0, Top = 4, Right = 0, Bottom = 0 })
    meter.widget, meter.text, meter.bar = w, text, bar
    return meter
end

local function hideMeter()
    if valid(meter.widget) then meter.widget:SetVisibility(VIS.Collapsed) end
end

-- the meter is a layer of its own over the screen: it steps aside while the game is paused or one of its menus,
-- dialogs or tutorials is open over the field (the game keeps its closed menus around, hidden: only visible ones count)
local MENUS = { "WBP_MainMenuRootLayout_C", "WBP_MainMenuLayout_C", "WBP_SystemMenuLayout_C", "WBP_SHOP_Layout_C",
                "WBP_DialogLayout_C", "WBP_ChoiceDialogLayout_C", "WBP_TutorialLayout_C", "WBP_ATCLayout_C",
                "WBP_TalkEvent_SystemMenuLayout_C", "WBP_TalkEvent_ChoiceDialogLayout_C" }
local function menuOpen()
    if game.isPaused() then return true end
    for _, class in ipairs(MENUS) do
        for _, w in ipairs(game.all(class)) do
            local ok, shown = pcall(function() return w:IsVisible() and (w:IsInViewport() or valid(w:GetParent())) end)
            if ok and shown then return true end
        end
    end
    return false
end

-- 0..1, or nil when there is nothing to show (no field, no random battles here, a menu open)
local function encounterShare()
    if kit.events.battle or kit.loading then return nil end
    local layout = fieldLayout()
    if not layout or not layout:IsVisible() or cfg.HideHUD then return nil end
    if menuOpen() then return nil end
    local mm = game.first("CPP_MapManager")
    if not mm then return nil end
    local ok, data = pcall(function() return game.lib("CPP_BFL_Map"):GetCurrntMapData() end)
    if ok and data and data.doMovementEncount == false then return nil end
    local okP, v = pcall(function() return mm:GetEncountMovementLengthParcentage() end)
    if not okP or type(v) ~= "number" or v ~= v then return nil end
    if v > 1.0001 then v = v / 100 end                  -- a percentage rather than a fraction
    return math.max(0, math.min(1, v))
end

local function updateMeter()
    if not cfg.EncounterMeter then hideMeter(); return end
    local share = encounterShare()
    if not share then hideMeter(); return end
    local m = meterWidget()
    if not m then return end
    if not m.widget:IsInViewport() then m.widget:AddToViewport(900) end
    local pct = math.floor(share * 100 + 0.5)
    if m.shown ~= pct then
        m.shown = pct
        m.text:SetText(FText(mod:t("meter", "Next battle: {1}%", pct)))
        m.bar:SetPercent(share)
        -- white, then amber, then red as the battle gets close
        local c = share < 0.6 and { R = 0.85, G = 0.9, B = 1, A = 1 }
            or share < 0.85 and { R = 1, G = 0.8, B = 0.35, A = 1 } or { R = 1, G = 0.4, B = 0.35, A = 1 }
        m.bar:SetFillColorAndOpacity(c)
    end
    m.widget:SetVisibility(VIS.HitTestInvisible)
end

---------------------------------------------------------------------------------------------------
-- Save anywhere: the system menu's Save entry (CPP_DA_SystemMenu, UI.System.SystemMenu.Entry.Save) loses its
-- save-point, map-type and saveable-map conditions, like the Load entry. Battles and story scenes still block it.
---------------------------------------------------------------------------------------------------
local SAVE_ENTRY = "UI.System.SystemMenu.Entry.Save"
local SAVE_FLAGS = { "bEnableOnSavePoint", "bIsEnableMapType", "bCheckMapSaveable" }
local saveOrig, saveState

local function applySave()
    if not cfg.SaveAnywhere and not saveOrig then return end   -- never switched on: don't touch the menu data
    local da = game.first("CPP_DA_SystemMenu")
    if not da then return end
    local state = da:GetFullName() .. "|" .. tostring(cfg.SaveAnywhere)
    if state == saveState then return end
    da.EntryPropertyMap:ForEach(function(k, v)
        if k:get().TagName:ToString() ~= SAVE_ENTRY then return end
        local e = v:get()
        if not saveOrig then
            saveOrig = {}
            for _, f in ipairs(SAVE_FLAGS) do saveOrig[f] = e[f] end
        end
        for _, f in ipairs(SAVE_FLAGS) do
            local want = (not cfg.SaveAnywhere) and saveOrig[f] or false
            if e[f] ~= want then e[f] = want end
        end
    end)
    saveState = state
end

---------------------------------------------------------------------------------------------------
-- Quieter battle voices: the battle voice table (BTL_VOICE_DATA) picks a line by situation, weighted by
-- probabilityWithinSituation; a weight of 0 for every line of a situation silences it. Rows by name: turn start
-- (command menu opens), skill and Ex menus, encounter and victory.
---------------------------------------------------------------------------------------------------
local patch = tables.patcher()
local QUIET = {
    turn = { "コマンド選択時" },
    menus = { "コマンド選択時", "スキル選択時", "Exコマンドオープン時" },
    more = { "コマンド選択時", "スキル選択時", "Exコマンドオープン時", "エンカウント時", "リザルト時" },
}

local function silenced(rowName)
    for _, prefix in ipairs(QUIET[cfg.QuietVoices] or {}) do
        if rowName:sub(1, #prefix) == prefix then return true end
    end
    return false
end

local voicesTouched = false
local function applyVoices()
    if cfg.QuietVoices == "off" and not voicesTouched then return end    -- never changed: don't read the table
    voicesTouched = true
    patch:apply("BTL_VOICE_DATA", tostring(cfg.QuietVoices), function(row, orig, rowName)
        local o = orig("probabilityWithinSituation")
        tables.set(row, "probabilityWithinSituation", silenced(tostring(rowName)) and 0 or o, o)
    end)
end

---------------------------------------------------------------------------------------------------
-- Skip intro logos: each logo of the start-up splash (CPP_DA_DisplayLogList) is shown for a moment instead of 3 s.
-- The list loads with the splash screen, so it's looked for from the start until it has been changed.
---------------------------------------------------------------------------------------------------
local LOGO_SEC = 0.05
local logosDone, logosTimer

local function applyLogos()
    if logosDone or not cfg.SkipLogos then return end
    local da = game.first("CPP_DA_DisplayLogList")
    if not da then return end
    local list = da.LogoList
    for i = 1, #list do
        local e = list[i]
        if e.defaultDisplaySec > LOGO_SEC then e.defaultDisplaySec = LOGO_SEC end
    end
    for _, w in ipairs(game.all("WBP_SplashLayout_C")) do
        pcall(function() if w.FadeSec > 0.1 then w.FadeSec = 0.1 end end)
    end
    logosDone = true
    kit.trace("Field Kit: intro logos shortened")
    if logosTimer then mod:cancel(logosTimer); logosTimer = nil end
end

---------------------------------------------------------------------------------------------------
-- Escape rewards: the enemies of a battle are followed while it lasts; when the party flees (the game's escape
-- sequence, Delegate.Battle.Sequencer.Escape), the EXP and Gil of the defeated ones are given as a victory would
-- (DT_UnitParameter Experience / Money, times the difficulty's rates) to the party members still standing.
---------------------------------------------------------------------------------------------------
local fight = { enemies = {}, party = {}, escaped = false }
local unitRewards

local function rewardsOf(unitId)
    unitRewards = unitRewards or tables.index("UNIT_PARAMETER", "ID", function(row)
        return { exp = row.Experience or 0, gil = row.Money or 0 }
    end)
    return unitRewards[unitId]
end

local function watchBattle()
    if not cfg.EscapeRewards or not kit.events.battle or fight.escaped then return end
    local seen = {}
    for _, e in ipairs(game.battleSide(game.ENEMY)) do
        local key = e.unit:GetFullName()
        seen[key] = true
        local rec = fight.enemies[key] or { id = e.id }
        local ok, hp = pcall(function() return e.param:GetHitPoint() end)
        rec.dead = ok and hp <= 0 or rec.dead
        rec.present = true
        fight.enemies[key] = rec
    end
    for key, rec in pairs(fight.enemies) do
        if rec.present and not seen[key] then rec.dead, rec.present = true, false end   -- removed when defeated
    end
    local party = {}
    for _, f in ipairs(game.battleSide(game.FRIENDLY)) do
        local ok, hp = pcall(function() return f.param:GetHitPoint() end)
        if ok and hp > 0 then party[#party + 1] = f.id end
    end
    if #party > 0 then fight.party = party end
end

local function grantEscapeRewards()
    local exp, gil, kills = 0, 0, 0
    for _, rec in pairs(fight.enemies) do
        if rec.dead then
            local r = rewardsOf(rec.id)
            if r then exp, gil, kills = exp + r.exp, gil + r.gil, kills + 1 end
        end
    end
    if kills == 0 then return end
    local player = game.lib("CPP_BFL_SaveDataPlayer")
    exp = math.floor(exp * player:GetCurDifficultyExpRate() + 0.5)
    gil = math.floor(gil * player:GetCurDifficultyMoneyRate() + 0.5)
    if gil > 0 then player:AddCurrentMoney(gil, false) end
    local unit, saved = game.lib("CPP_BFL_Unit"), game.lib("CPP_BFL_SaveDataUnit")
    local done = {}
    if exp > 0 then
        for _, id in ipairs(fight.party) do
            if not done[id] then
                done[id] = true
                pcall(function() unit:SetPlayableUnitExperience(id, saved:GetSaveDataUnitExperience(id) + exp, false) end)
            end
        end
    end
    mod:log("escape rewards: %d defeated, %d EXP to %d characters, %d Gil", kills, exp, #fight.party, gil)
    mod:notice(mod:t("escapeRewards", "Escape rewards: {1} EXP, {2} Gil", exp, gil), "on", 3000)
end

mod:on("battleStart", function() fight = { enemies = {}, party = {}, escaped = false } end)
mod:on("gameEvent", function(name, value)
    if name ~= "Delegate.Battle.Sequencer.Escape" or not kit.events.battle then return end
    local ok, success = pcall(function() return value:get().isSuccessEscape end)
    kit.trace("Field Kit: escape sequence (success %s)", tostring(ok and success))
    if ok and success == false then return end
    if not fight.escaped then
        watchBattle()
        fight.escaped = true
    end
end)
mod:on("battleEnd", function()
    local escaped = fight.escaped
    fight.escaped = false
    if escaped and cfg.EscapeRewards then grantEscapeRewards() end
end)

---------------------------------------------------------------------------------------------------
-- Wiring. Each part touches the game only while its switch is on (or to put back what it changed).
---------------------------------------------------------------------------------------------------
-- each step on its own, so one failing doesn't stop the others
local function applyAll()
    mod:guard("hud", applyHUD)
    mod:guard("save anywhere", applySave)
    mod:guard("battle voices", applyVoices)
    mod:guard("encounter meter", updateMeter)
end

mod:key(cfg.HideHUDKey, function() cfg:toggle("HideHUD") end, "HideHUDKey")
mod:key(cfg.EncounterMeterKey, function() cfg:toggle("EncounterMeter") end, "EncounterMeterKey")
cfg:onChange(applyAll)
mod:onToggle(function(on)
    applyAll()
    if not on then hideMeter() end
end)
mod:on("loadingEnd", function() hud.layout = nil end)
mod:every(250, applyHUD, "hud")
mod:every(250, updateMeter, "encounter meter")
mod:every(500, watchBattle, "escape rewards")
mod:every(2000, applySave, "save anywhere")
mod:every(2000, applyVoices, "battle voices")
logosTimer = mod:every(50, applyLogos, "intro logos", { loading = true })
applyAll()
