-- The game's progress, read live through its own functions; nothing here writes. Conditions are the game's own
-- strings from its tables ("{progress:1}==20"), checked with CPP_BFL_Condition:IsMeetCondition as the game does.
-- Every read is cached until refresh(), which the screen calls when it opens and every few seconds while open.
local M = {}
local game, ue = kit.game, kit.ue
local cache = kit.cache({ "saveLoaded" })
local REQUEST, RANK, JOIN = game.enum.RequestState, game.enum.RankBattleStatus, game.enum.JoinStatus

function M.refresh() cache:clear() end

local function cached(key, fn) return cache:get(key, fn) end

-- true / false; an empty condition holds
function M.cond(s)
    if s == nil or s == "" then return true end
    return cached("c|" .. s, function() return game.lib("CPP_BFL_Condition"):IsMeetCondition(s, false) == true end)
end

function M.loaded() return game.saveData() ~= nil end

---------------------------------------------------------------------------------------------------
-- Areas
---------------------------------------------------------------------------------------------------
local areas = {}
function M.setAreas(list) areas = list end

function M.regionVisited(region)
    return cached("rv|" .. region, function()
        for _, a in ipairs(areas) do
            if a.region == region and not a.field and M.visited(a) then return true end
        end
        return false
    end)
end

function M.visited(area)
    if area.field then return M.regionVisited(area.region) end
    return cached("v|" .. area.key, function()
        if M.treasure(area).found > 0 then return true end      -- something picked up there (older saves miss visits)
        local lib = game.lib("CPP_BFL_SaveData_PerMap")
        for _, mid in ipairs(area.maps) do
            if lib:IsVisited(mid) then return true end
        end
        return false
    end)
end

-- the save's chest and item spot records: open[map][unique id] = true. One pass over Map.mapGimmick; where that
-- can't be read, each one is asked with IsOpenTreasureBox (by its unique id, as the save keys them)
local function records()
    return cached("records", function()
        return ue.map(game.saveData().Map.mapGimmick, function(v)
            local m = {}
            ue.each(v.treasureBox.treasureBoxList, function(e) if e.IsOpen then m[e.UniqueID] = true end end)
            return m
        end)
    end)
end

local function isOpen(map, uid)
    local open = records()
    if open then return open[map] ~= nil and open[map][uid] == true end
    return cached("o|" .. map .. "|" .. uid, function()
        return game.lib("CPP_BFL_SaveDataMap"):IsOpenTreasureBox(map, uid) == true
    end)
end

-- { open, total = chests; spotsOpen, spots = item spots other than tablet shards; shardsOpen, shards = tablet shard
--   spots; found, all = the three together; chest[i], spot[i] = opened / picked up }
function M.treasure(area)
    return cached("t|" .. area.key, function()
        local r = { open = 0, total = #area.chests, spotsOpen = 0, spots = 0, shardsOpen = 0, shards = 0, chest = {}, spot = {} }
        for i, c in ipairs(area.chests) do
            r.chest[i] = isOpen(c.map, c.uid)
            if r.chest[i] then r.open = r.open + 1 end
        end
        for i, sp in ipairs(area.spots) do
            r.spot[i] = isOpen(sp.map, sp.uid)
            if sp.shard then
                r.shards = r.shards + 1
                if r.spot[i] then r.shardsOpen = r.shardsOpen + 1 end
            else
                r.spots = r.spots + 1
                if r.spot[i] then r.spotsOpen = r.spotsOpen + 1 end
            end
        end
        r.found, r.all = r.open + r.spotsOpen + r.shardsOpen, r.total + r.spots + r.shards
        return r
    end)
end

---------------------------------------------------------------------------------------------------
-- Side quests: in progress (a stage's condition holds), available (its accept condition holds), done or not yet
---------------------------------------------------------------------------------------------------
local function progressKey(q)
    for _, s in ipairs(q.stages) do
        local k = s.cond:match("{progress:(%d+)}")
        if k then return tonumber(k) end
    end
end

local function lastStageValue(q, key)
    local best
    for _, s in ipairs(q.stages) do
        for k, v in s.cond:gmatch("{progress:(%d+)}[=><]+(%d+)") do
            if tonumber(k) == key then best = math.max(best or 0, tonumber(v)) end
        end
    end
    return best
end

-- the game's request records (SaveData_Request.DataMap): id -> { state = ERequestState, index = ProgressIndex }
-- (only requests taken so far are there; ProgressIndex is the current stage, counted from 0)
local function requests()
    return cached("requests", function()
        return ue.map(game.saveData().request.DataMap, function(v) return { state = v.State, index = v.ProgressIndex } end)
    end)
end

-- (the game's condition strings only use ==, >=, <=, so "more than" is written as >= value + 1)
-- "done", "active" (with the stage number), "available" or "locked"
function M.quest(q)
    return cached("q|" .. q.id, function()
        local rec = (requests() or {})[q.id]
        if rec and rec.state == REQUEST.Completed then return { state = "done" } end
        if rec and rec.state == REQUEST.Progressing then
            local i = rec.index
            return { state = "active", stage = type(i) == "number" and i >= 0 and i < #q.stages and i + 1 or nil }
        end
        -- no record: the stage conditions. Done first: past the last stage's value (a >= stage would still hold)
        local key = progressKey(q)
        local last = key and lastStageValue(q, key)
        if last and M.cond(string.format("{progress:%d}>=%d", key, last + 1)) then return { state = "done" } end
        for i = #q.stages, 1, -1 do                     -- the latest stage that holds (some stages use >=)
            local st = q.stages[i]
            if st.cond ~= "" and M.cond(st.cond) then return { state = "active", stage = i } end
        end
        if M.cond(q.accept) then return { state = "available" } end
        return { state = "locked" }
    end)
end

---------------------------------------------------------------------------------------------------
-- Colosseum: battle <id> is cleared when {colosseum:<id>}==3 (the next battle's own unlock condition)
---------------------------------------------------------------------------------------------------
-- the save's rank battle records (colosseumProgress.RankBattle): battle id -> { status, clears }
local function rankBattles()
    return cached("rank", function()
        local out = {}
        for _, r in pairs(ue.map(game.saveData().colosseumProgress.RankBattle, function(v)   -- keyed by name
            return { id = v.ID, status = v.Status, clears = v.ClearCount }
        end)) do out[r.id] = r end
        return out
    end)
end

-- "cleared", "open" or "locked", and how many times it has been won (nil when the save doesn't say)
function M.colosseum(c)
    local rec = (rankBattles() or {})[c.id]
    if rec and rec.status == RANK.Clear then return "cleared", rec.clears end
    if rec and rec.status == RANK.UnLocked then return "open", rec.clears end
    if rec and rec.status == RANK.Locked then return "locked", 0 end
    if M.cond(string.format("{colosseum:%d}==3", c.id)) then return "cleared" end
    if c.cond == "" or M.cond(c.cond) then return "open" end
    return "locked"
end

---------------------------------------------------------------------------------------------------
-- Tablet shards: held ones (inventory) and the collector's rewards; a reward is claimed once the collector's
-- counter has moved past the value its condition waits for
---------------------------------------------------------------------------------------------------
function M.shardsHeld(item)
    return cached("s|held", function() return game.lib("CPP_BFL_SaveDataInventory"):FindInventory(item) or 0 end)
end

function M.shardReward(r)
    local key, value = r.cond:match("{progress:(%d+)}==(%d+)")
    if not key then return M.cond(r.cond) and "next" or "later" end
    if M.cond(string.format("{progress:%s}>=%d", key, tonumber(value) + 1)) then return "claimed" end
    if M.cond(r.cond) then return "next" end
    return "later"
end

---------------------------------------------------------------------------------------------------
-- Story
---------------------------------------------------------------------------------------------------
-- the story chapter (the main progress counter counts 1000 a chapter)
function M.chapter()
    return cached("chapter", function()
        return math.max(1, math.floor(game.lib("CPP_BFL_Progress"):GetMainProgress() / 1000))
    end)
end

-- party members who have joined, of all the playable characters
function M.party()
    local v = cached("party", function()
        local joined, all = 0, 0
        ue.each(game.saveData().unitParameterList, function(u)
            all = all + 1
            if u.JoinStatus == JOIN.Join then joined = joined + 1 end
        end)
        return { joined, all }
    end)
    if v then return v[1], v[2] end
end

function M.visions()
    return cached("visions", function() return game.lib("CPP_BFL_Vision"):GetOwnedVisionNum() end)
end

function M.encounters()
    return cached("encounters", function() return game.lib("CPP_BFL_SaveDataMap"):GetEncountCount() end)
end

return M
