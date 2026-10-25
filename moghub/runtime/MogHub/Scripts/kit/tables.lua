-- The game's data tables: rows(struct, fn) and index(struct, field, pick) to read them, and reversible edits. A patcher keeps each field's original value the first time it touches it, and every
-- write is computed from those originals, so turning an option off puts the game's own values back.
--   local patch = kit.tables.patcher()
--   patch:apply("SKILL_DATA", tostring(noCost), function(row, orig) kit.tables.set(row, "Cost", noCost and 0 or orig("Cost")) end)
-- `state` names what the edit depends on: the rows are only rewritten when it changes, or when the game reloads
-- the table (it does on some map changes).
local M = {}

-- tables by row struct name: { [struct] = { { dt, path, rows }, ... } }. Searching every DataTable is slow-ish
-- (tens of ms): cached for one tick, so several patchers in the same tick share one search.
local found, foundAt = nil, nil
function M.collect()
    local stamp = os.clock()
    if found and foundAt and stamp - foundAt < 0.05 then return found end
    found, foundAt = {}, stamp
    for _, dt in ipairs(FindAllOf("DataTable") or {}) do
        pcall(function()
            if not dt:IsValid() then return end
            local s = dt:GetRowStruct()
            local name = s and s:IsValid() and s:GetFName():ToString()
            if name then
                found[name] = found[name] or {}
                table.insert(found[name], { dt = dt, path = dt:GetFullName(), rows = #dt })
            end
        end)
    end
    return found
end

function M.find(struct) return M.collect()[struct] or {} end

-- fn(row, rowName, table) for every row of every loaded table with this row struct (read-only use: for edits that
-- go back, use a patcher)
function M.rows(struct, fn)
    for _, t in ipairs(M.find(struct)) do
        t.dt:ForEachRow(function(rowName, row) fn(row, rowName, t) end)
    end
end

-- the rows as a Lua table by one field: out[row[field]] = pick(row), copied out of the game (the first row wins
-- when tables repeat a key)
--   local rewards = kit.tables.index("UNIT_PARAMETER", "ID", function(r) return { exp = r.Experience } end)
function M.index(struct, field, pick)
    local out = {}
    M.rows(struct, function(row)
        local k = row[field]
        if k ~= nil and out[k] == nil then out[k] = pick(row) end
    end)
    return out
end

-- writes a number, keeping integer fields whole; skips the write when the value is already there
function M.set(row, field, value, like)
    if like == nil then like = row[field] end
    if math.type(like) == "integer" and type(value) == "number" then value = math.floor(value + 0.5) end
    if row[field] ~= value then row[field] = value end
end

local Patcher = {}
Patcher.__index = Patcher

function M.patcher() return setmetatable({ orig = {}, applied = {} }, Patcher) end

local function identity(list)
    local parts = {}
    for _, t in ipairs(list) do parts[#parts + 1] = t.path .. "#" .. t.rows .. "@" .. tostring(t.dt:GetAddress()) end
    return table.concat(parts, ";")
end

-- fn(row, orig, rowName, table) for every row of every table with this row struct; returns true if it ran
function Patcher:apply(struct, state, fn)
    local list = M.find(struct)
    if #list == 0 then return false end
    local key = identity(list) .. "|" .. tostring(state)
    if self.applied[struct] == key then return false end
    self.applied[struct] = key
    local orig = self.orig
    for _, t in ipairs(list) do
        t.dt:ForEachRow(function(rowName, row)
            local prefix = t.path .. "|" .. rowName .. "|"
            local function original(field)
                local k = prefix .. field
                local v = orig[k]
                if v == nil then v = row[field]; orig[k] = v end
                return v
            end
            fn(row, original, rowName, t)
        end)
    end
    return true
end

-- forget what was applied, so the next apply() rewrites every row (after a reset, for example)
function Patcher:invalidate() self.applied = {} end

return M
