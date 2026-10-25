-- Bestiary progress: which enemies were seen, and where. One JSON file per save slot (saves/slot<N>.json), never
-- inside the game's saves. MogHub's store follows the game: the file is read when a slot is loaded and written when
-- the game saves to a slot, so reloading without saving forgets what was seen since, exactly like the game does.
local game = require("game")
local data = require("bestiary_data")

local M = {}
M.units = {}        -- [unitId] = { seen = true, seenAreas = { [areaKey] = true }, fromSave = true if taken from the save }
M.visited = {}      -- [areaKey] = true: areas the player has been in (their enemies are listed, unseen ones as ???)
M.slot = nil        -- slot the progress belongs to (nil for an unsaved new game)

function M.markSeen(unitId, area)
    local u = M.units[unitId]
    if not u then u = { seen = true, seenAreas = {} }; M.units[unitId] = u end
    if area then u.seenAreas[area] = true end
end

function M.markVisited(area)
    if area then M.visited[area] = true end
end

-- What the game's save already knows, for a Bestiary installed mid-game (and for anything met without the mod):
-- enemies defeated or scanned count as seen, though not where (the list files them under the areas the game data
-- gives them, among the areas visited; their locations stay ??? until met again), and the maps the save marks as
-- visited (Map.perMapSaveDataMap[mapId].bIsVisited) count as visited areas, with the world-map island they are on.
local enemyIds
local function seedFromSave(sd, records)
    if next(records or {}) == nil then return end         -- title screen / new game: nothing saved yet
    if not enemyIds then
        enemyIds = {}
        for _, e in ipairs(data.entries) do for _, u in ipairs(e.units) do enemyIds[u] = true end end
    end
    local n, v = 0, 0
    for id, r in pairs(records) do
        if enemyIds[id] and not M.units[id] then
            local ok, known = pcall(function() return r.IsAnalyzed or (r.defeatNum or 0) > 0 end)
            if ok and known then M.units[id] = { seen = true, seenAreas = {}, fromSave = true }; n = n + 1 end
        end
    end
    local function visit(a) if a and not M.visited[a] then M.visited[a] = true; v = v + 1 end end
    -- the title screen's placeholder save has empty unit records: leave its map data alone (a crash at start-up
    -- happened around here once)
    local any = n > 0
    for _, r in pairs(records) do if any then break end; pcall(function() any = r.IsAnalyzed or (r.defeatNum or 0) > 0 end) end
    if not any then return end
    local ok, err = pcall(function()
        local maps = kit.ue.map(sd.Map.perMapSaveDataMap, function(v) return v.bIsVisited or nil end)
        for id in pairs(maps) do
            local a = data.mapArea[tostring(id)]
            visit(a)
            if a and data.areaRegion[a] then visit(data.islandArea[tostring(data.areaRegion[a])]) end
        end
    end)
    if not ok then mod:log("visited maps: %s", tostring(err)) end
    mod:log("from the game save: %d enemies, %d visited areas", n, v)
end

local st = mod:store("bestiary", { file = "slot%s.json" })

st:onLoad(function(saved, slot)
    M.units, M.visited, M.slot = {}, {}, slot
    local n = 0
    for id, u in pairs(type(saved.units) == "table" and saved.units or {}) do
        local areas = {}
        for _, a in ipairs(u.seenAreas or {}) do areas[a] = true end
        M.units[tonumber(id)] = { seen = u.seen ~= false, seenAreas = areas, fromSave = u.fromSave == true }
        n = n + 1
    end
    for _, a in ipairs(saved.visitedAreas or {}) do M.visited[a] = true end
    if slot then mod:log("slot %s: %d units", tostring(slot), n) end
    local sd = game.saveData()
    if sd then seedFromSave(sd, game.records(sd)) end
end)

-- the file: { version, slot, units = { [id] = { seen, scanned, seenAreas = [...], fromSave } }, visitedAreas = [...] }
-- (scanned is taken from the game's records, for anyone reading the file)
st:onSave(function(saved, slot)
    local sd = game.saveData()
    local records = sd and game.records(sd) or {}
    local units = {}
    for id, u in pairs(M.units) do
        local areas = {}
        for a in pairs(u.seenAreas) do areas[#areas + 1] = a end
        table.sort(areas)
        local r = records[id]
        units[tostring(id)] = { seen = true, scanned = r and r.IsAnalyzed or false, seenAreas = areas, fromSave = u.fromSave or nil }
    end
    local visited = {}
    for a in pairs(M.visited) do visited[#visited + 1] = a end
    table.sort(visited)
    for k in pairs(saved) do saved[k] = nil end
    saved.version, saved.slot, saved.units, saved.visitedAreas = 1, slot, units, visited
    M.slot = slot
end)

return M
