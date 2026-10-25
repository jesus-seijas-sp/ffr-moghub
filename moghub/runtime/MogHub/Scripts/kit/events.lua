-- Game events for plugins (mod:on(name, fn)):
--   "loadingBegin" / "loadingEnd"   a loading screen starts / ends (timers wait behind loading screens)
--   "gameEvent" (tag, value)        every event of the game's own dispatcher (CPP_MuchaEventDispatcher:ExecuteEvent)
--   "battleStart" / "battleEnd"     a battle's units appear / are gone (checked twice a second)
--   "saveLoaded" (slot, save)       a save was loaded or a new game started (slot nil: not from a slot)
--   "saved" (slot, save)            the game saved to a slot
--   "tick"                          every 50 ms, on the game thread
local M = {}
local kit, game

function M.init(k)
    kit, game = k, k.game
    M.sawLoading = false
    M.battle = false
end

local function hookDispatcher()
    local ok, err = pcall(function()
        RegisterHook("/Script/mucha.CPP_MuchaEventDispatcher:ExecuteEvent", function(_, tag, value)
            local okT, name = pcall(function() return tag:get().TagName:ToString() end)
            if not okT then return end
            if name == "Delegate.Common.LoadingScreen.Begin" then
                kit.loading, M.sawLoading = true, true
                kit.emit("loadingBegin")
            elseif name == "Delegate.Common.LoadingScreen.End" then
                kit.loading = false
                kit.emit("loadingEnd")
            end
            kit.emit("gameEvent", name, value)
        end)
    end)
    if not ok then kit.log("event hook unavailable: %s", tostring(err)) end
end

-- a new save object means a load (or a new game); the same object with a new timestamp means the game saved
local lastObj, lastTicks, pendingSave
local function pollSave()
    local sd = game.saveData()
    if not sd then return end
    local obj, ticks = sd:GetFullName(), game.savedTicks(sd)
    if obj ~= lastObj then
        lastObj, lastTicks, pendingSave = obj, ticks, nil
        M.slot = game.slotForTicks(ticks)
        kit.emit("saveLoaded", M.slot, sd)
    elseif ticks ~= lastTicks then
        lastTicks, pendingSave = ticks, ticks
    end
    if pendingSave then                                  -- the slot summary may update a moment after the save
        local slot = game.slotForTicks(pendingSave)
        if slot then
            pendingSave = nil
            M.slot = slot
            kit.emit("saved", slot, sd)
        end
    end
end

local function pollBattle()
    local now = game.inBattle()
    if now ~= M.battle then
        M.battle = now
        kit.emit(now and "battleStart" or "battleEnd")
    end
end

function M.start()
    hookDispatcher()
    kit.every(500, pollBattle, "battle events")
    kit.every(1000, pollSave, "save events")
end

return M
