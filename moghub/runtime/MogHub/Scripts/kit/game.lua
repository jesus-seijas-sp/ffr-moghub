-- Game access shared by plugins: assets and classes, strings, the save, the party, battles and the map.
-- Verified on FINAL FANTASY RESONANCE 1.0.1.0 (Steam build 24250053). Parts adapted from FFR Bestiary by Law19902
-- (MIT): save slot lookup, asset loading, string tables.
local M = {}
local kit, valid

function M.init(k) kit = k; valid = k.valid end

-- objects that live for the whole session are looked up once and kept while valid
local cache = {}
function M.find(path)
    local o = cache[path]
    if not valid(o) then o = StaticFindObject(path); cache[path] = o end
    return valid(o) and o or nil
end

-- a function library's default object: M.lib("CPP_BFL_Unit"), M.lib("/Script/Engine.Default__KismetSystemLibrary")
function M.lib(name)
    if name:sub(1, 1) == "/" then return M.find(name) end
    return M.find("/Script/mucha.Default__" .. name)
end

-- the first live (non-default) object of a class
function M.first(class)
    local o = FindFirstOf(class)
    return valid(o) and o or nil
end

-- every live object of a class (default objects left out)
function M.all(class)
    local out = {}
    for _, o in ipairs(FindAllOf(class) or {}) do
        if valid(o) and not o:GetFullName():find("Default__", 1, true) then out[#out + 1] = o end
    end
    return out
end

-- an asset by path ('/Game/Path/Asset.Asset'), loaded if needed, with UE4SS's own LoadAsset. (Not through the
-- engine's soft paths: UE4SS hands an FSoftObjectPath to Lua without its SubPathString, and passing it back to the
-- game left that field as garbage. That crashed the game now and then.)
function M.load(path)
    local o = StaticFindObject(path)
    if valid(o) then return o end
    local ok, r = pcall(LoadAsset, path)
    if ok and valid(r) then return r end
    o = StaticFindObject(path)
    if valid(o) then return o end
end

-- a Blueprint class: '/Game/Path/WBP_X' or '/Game/Path/WBP_X.WBP_X_C', loaded if needed
function M.class(path)
    if not path:find("%.") then local name = path:match("([^/]+)$"); path = path .. "." .. name .. "_C" end
    local c = StaticFindObject(path)
    if valid(c) then return c end
    pcall(LoadAsset, (path:gsub("_C$", "")))             -- the Blueprint asset; its class comes with it
    c = StaticFindObject(path)
    if valid(c) then return c end
end

function M.playerController()
    for _, pc in ipairs(FindAllOf("PlayerController") or {}) do
        if valid(pc) and not pc:GetFullName():find("Default__", 1, true) then return pc end
    end
end

-- text from one of the game's string tables, in the player's language (nil when the key has no text)
function M.text(tableId, key)
    local ok, t = pcall(function() return M.lib("/Script/Engine.Default__KismetTextLibrary"):TextFromStringTable(FName(tableId), key) end)
    if ok and t then
        local s = t:ToString()
        if s ~= "" and not s:find("MISSING STRING TABLE ENTRY", 1, true) then return s end
    end
end

function M.itemName(id)
    if not id or id < 0 then return nil end
    local ok, t = pcall(function() return M.lib("CPP_BFL_Item"):GetItemName(id) end)
    if ok and t then return t:ToString() end
end

---------------------------------------------------------------------------------------------------
-- Saves
---------------------------------------------------------------------------------------------------
local manager
local function saveManager()
    if not valid(manager) then manager = FindFirstOf("CPP_MuchaSaveDataManager") end
    return valid(manager) and manager or nil
end

-- the loaded game's save object (nil on the title screen before a load)
function M.saveData()
    local mgr = saveManager()
    local sd = mgr and mgr.m_pGameSaveData
    if valid(sd) and #sd.unitList > 0 then return sd end
end

function M.savedTicks(sd)
    local ok, t = pcall(function() return sd.Player.SavedDateTime.Ticks end)
    return ok and t or nil
end

-- the slot whose summary has this timestamp (0 = autosave), or nil. Read from the manager's summary map, not
-- FindGameSaveDataSummary's out-param, which UE4SS hands back as wrappers into memory freed after the call.
function M.slotForTicks(ticks)
    local mgr = saveManager()
    if not mgr or not ticks then return nil end
    local found
    pcall(function()
        mgr.GameSaveDataSummaryMap:ForEach(function(key, value)
            local sum = value:get()
            if not found and sum.bExists and sum.DateTime.Ticks == ticks then found = key:get() end
        end)
    end)
    return found
end

---------------------------------------------------------------------------------------------------
-- Battle and field
---------------------------------------------------------------------------------------------------
M.FRIENDLY, M.ENEMY = 1, 2   -- UCPP_UnitParameter:GetRelation()

-- the game's enums that plugins compare with (values from its type mappings: ffr-dump enums <name>)
M.enum = {
    JoinStatus = { Join = 0, NotJoin = 1, Leave = 2, TemporalLeave = 3, Lost = 4 },          -- eUnitJoinStatus
    RequestState = { NotProgressing = 0, Progressing = 1, Completed = 2 },                   -- ERequestState
    RankBattleStatus = { None = 0, Locked = 1, UnLocked = 2, Clear = 3 },                    -- EColosseum_RankBattleStatus
    VisionMastery = { Awakening = 0, Synchro = 1 },                                          -- eVisionMasteryType
    Relation = { None = 0, Friendlies = 1, Enemies = 2, All = 3 },                           -- eRelation
    BtlPhase = { Normal = 0, Additional = 1, Finish = 2 },                                   -- eBtlPhaseType
    Visibility = { Visible = 0, Collapsed = 1, Hidden = 2, HitTestInvisible = 3, SelfHitTestInvisible = 4 },  -- ESlateVisibility
}

-- the battle's units (nil outside battle)
function M.battleUnits()
    local bm = FindFirstOf("CPP_BtlManager")
    local um = valid(bm) and bm.m_pUnitManager or nil
    local list = valid(um) and um.m_UnitList or nil
    if not list or #list == 0 then return nil end
    local out = {}
    for i = 1, #list do
        local u = list[i]
        if valid(u) then out[#out + 1] = u end
    end
    return out
end

function M.inBattle() return M.battleUnits() ~= nil end

-- { unit, param, id } for each battle unit with this relation
function M.battleSide(relation)
    local out = {}
    for _, u in ipairs(M.battleUnits() or {}) do
        pcall(function()
            local p = u:GetUnitParameter()
            if valid(p) and p:GetRelation() == relation then out[#out + 1] = { unit = u, param = p, id = p:GetUnitId() } end
        end)
    end
    return out
end

-- current map id and island (eMapIslandType)
function M.location()
    local mm = FindFirstOf("CPP_MapManager")
    if not valid(mm) then return nil end
    local ok1, map = pcall(function() return mm:GetMapId() end)
    local ok2, isl = pcall(function() return mm:GetCurrentIslandType() end)
    if ok1 then return map, ok2 and isl or 0 end
end

function M.isPaused()
    local pc = M.playerController()
    local statics = M.lib("/Script/Engine.Default__GameplayStatics")
    local ok, res = pcall(function() return statics:IsGamePaused(pc) end)
    return ok and res
end

---------------------------------------------------------------------------------------------------
-- Input: raw key state, for screens that need keys the game's menus don't report (Left / Right in a list)
---------------------------------------------------------------------------------------------------
local keyStructs, pcCache = {}, nil
function M.keyDown(name)
    if not valid(pcCache) then pcCache = M.playerController() end
    if not pcCache then return false end
    local k = keyStructs[name]
    if not k then k = { KeyName = FName(name) }; keyStructs[name] = k end
    local ok, res = pcall(function() return pcCache:IsInputKeyDown(k) end)
    return ok and res == true
end

-- Left / Right with key repeat, for screens whose list only moves up and down: returns a function that gives -1, 1
-- or 0 each time it is called (D-pad, left stick, arrow keys, A / D)
local HORIZONTAL = {
    [-1] = { "Gamepad_DPad_Left", "Gamepad_LeftStick_Left", "Left", "A" },
    [1] = { "Gamepad_DPad_Right", "Gamepad_LeftStick_Right", "Right", "D" },
}
local REPEAT_FIRST, REPEAT_NEXT = 0.35, 0.11
function M.leftRight()
    local held, nextAt = 0, 0
    return function()
        local dir = 0
        for d, keys in pairs(HORIZONTAL) do
            for _, key in ipairs(keys) do if M.keyDown(key) then dir = d end end
        end
        local t = os.clock()
        if dir == 0 then held = 0; return 0 end
        if dir ~= held then held, nextAt = dir, t + REPEAT_FIRST; return dir end
        if t >= nextAt then nextAt = t + REPEAT_NEXT; return dir end
        return 0
    end
end

return M
