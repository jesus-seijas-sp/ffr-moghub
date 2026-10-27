-- "Travel here" on an area's page: fast travel as the game's own world map does it (through it, in fact: see M.go),
-- to the same places and under the same rules (DA_WldMapParameter.FastTravelProperty): only once fast travel is unlocked in the story, never while the
-- party is in a dungeon, never to a place not visited yet, never while an important event is underway. Where a place
-- leads depends on the story (the capital while it burns, then rebuilt): the landmark's first map version whose
-- condition holds, as the game resolves it (data/travel_data.lua, from DA_MapLandmark).
local data = require("travel_data")

local M = {}
local game = kit.game

local UNLOCK_FLAG = 34              -- FastTravelProperty.EnableFlagIdData: the story flag that unlocks fast travel
local DIALOG = "/Game/Datatable/Strings/UI/UI_Dialog/ST_CommonDialog.ST_CommonDialog"
local GUIDE = "/Game/Datatable/Strings/UI/UI_Common/ST_UI_Guide.ST_UI_Guide"
-- the game's own messages for each "no" (the world map's fast travel dialogs)
local WHY = { dungeon = "CommonDialog_034", event = "CommonDialog_035", unvisited = "CommonDialog_036" }

local function cond(s)
    if s == nil or s == "" then return true end
    local ok, r = pcall(function() return game.lib("CPP_BFL_Condition"):IsMeetCondition(s, false) end)
    return ok and r == true
end

-- where a landmark leads now: the first version whose condition holds (nil: nowhere at this point of the story)
local function resolve(versions)
    for _, v in ipairs(versions) do
        if cond(v.cond) then return v.map >= 0 and v or nil end
    end
end

local function unlocked()
    local ok, r = pcall(function() return game.lib("CPP_BFL_SaveDataProgress"):GetFlag(UNLOCK_FLAG) end)
    return ok and r == true
end

local function visited(mapId)
    local ok, r = pcall(function() return game.lib("CPP_BFL_SaveData_PerMap"):IsVisited(mapId) end)
    return ok and r == true
end

-- the map the party is on, and whether it's a dungeon (eMapType::Dungeon = 1 in MAP_DATA.MapType)
local function here()
    local id, dungeon
    pcall(function()
        local map = game.lib("CPP_BFL_Map")
        id = map:GetCurrentMapId()
        dungeon = kit.ue.enum(map:GetCurrntMapData().MapType, { [1] = "Dungeon" }) == 1
    end)
    return id, dungeon
end

-- The area's destination: its map id, or nil and why not: "none" (no place on the world map, or none at this point
-- of the story), "locked" (fast travel not unlocked yet), "dungeon" (the party is in one), "unvisited", "here" (the
-- party is there). An area with several places (the vision shrines) goes to the first one that can be reached.
function M.target(area)
    local list = data.areas[area]
    if not list then return nil, "none" end
    if not unlocked() then return nil, "locked" end
    local current, inDungeon = here()
    if inDungeon then return nil, "dungeon" end
    local reason = "none"
    for _, versions in ipairs(list) do
        local v = resolve(versions)
        if v then
            if not visited(v.map) then reason = (reason == "here") and reason or "unvisited"
            elseif v.map == current then reason = "here"
            else return v.map end
        end
    end
    return nil, reason
end

-- what kind of place the area is: an eMapType name (Town, Dungeon, Underworld, VisionSmallShrine, Field), or nil
function M.kind(area) return data.kinds and data.kinds[area] end

-- the game's text for a "no", when it has one
function M.why(reason)
    local key = WHY[reason]
    return key and game.text(DIALOG, key)
end

-- the game's name for it ("Fast Travel", from the world map's key guide)
function M.name() return game.text(GUIDE, "KeyGuideMapFastTravel") end

-- The trip itself goes through the game's own world map, as if the player had picked the place there: the main menu
-- switches to the map, the map focuses the place's landmark, and confirm on it brings up the game's Fast Travel
-- question. The game then applies all of its rules (its "important event" one included), travels, and closes the
-- menu its own way. (Calling the map change from the Bestiary page crashed: the menu was torn down under it.)
local MAP_SCENE = "UI.MainMenu.Scene.Map"
local STEP_MS, TRIES = 100, 30
function M.go(mapId)
    local sub = FindFirstOf("CPP_MainMenuSubsystem")
    if not (sub and sub:IsValid()) then return false end
    local ok, err = pcall(function()
        sub:SetScene({ TagName = FName(MAP_SCENE) }, { bStackScene = false, bMainMenuBgEnable = true })
    end)
    if not ok then mod:log("travel: map screen: %s", tostring(err)); return false end
    local tries = 0
    local function step()
        tries = tries + 1
        local vm = FindFirstOf("CPP_VM_WldMap")
        local scene
        pcall(function() scene = sub:GetCurrentScene().TagName:ToString() end)
        if vm and vm:IsValid() and scene == MAP_SCENE then
            pcall(function() vm:JumpToMap(mapId) end)
            mod:after(300, function()                     -- the map settles on the landmark first
                local v = FindFirstOf("CPP_VM_WldMap")
                if v and v:IsValid() then pcall(function() v:DecideObject() end) end
            end, "travel: decide")
        elseif tries < TRIES then
            mod:after(STEP_MS, step, "travel: map")
        end
    end
    mod:after(STEP_MS, step, "travel: map")
    return true
end

return M
