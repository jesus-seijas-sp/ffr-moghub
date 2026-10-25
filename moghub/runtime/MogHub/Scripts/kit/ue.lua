-- Reading the game's containers and values from Lua, the way that works with UE4SS 3.0.1:
--   kit.ue.each(sd.unitList, function(unit, i) ... end)          -- TArray of structs: elements in place
--   local ids = kit.ue.values(row.UnitIdList)                     -- TArray of numbers / objects -> Lua list
--   local byId = kit.ue.map(sd.request.DataMap, function(v, k) return v.State end)   -- TMap -> Lua table
--   kit.ue.plain(v), kit.ue.enum(v, { [0] = "Join", "NotJoin" })
-- Notes from earlier crashes: read struct fields where they are (each / map hand them over in place) and copy out
-- what is needed before the call returns; don't keep the elements themselves, and don't write strings into structs
-- inside arrays.
local M = {}

-- a value UE4SS hands back, unwrapped: a wrapped element's value (:get()), an FString / FName as a Lua string
function M.plain(v)
    if type(v) == "table" and type(rawget(v, "get")) == "function" then v = v:get() end   -- a wrapper in a Lua list
    if type(v) ~= "userdata" then return v end
    local ok, x = pcall(function() return v:get() end)
    if ok and x ~= nil then v = x end
    if type(v) == "userdata" then
        local okS, s = pcall(function() return v:ToString() end)
        if okS and s ~= nil then return s end
    end
    return v
end

-- fn(element, index) for each element of a TArray of structs (the element is the struct itself, readable and
-- writable in place); a Lua table works too
local function list(arr) return type(arr) == "table" and rawget(arr, "ForEach") == nil and getmetatable(arr) == nil end

function M.each(arr, fn)
    if list(arr) then
        for i, v in ipairs(arr) do fn(v, i) end
        return
    end
    for i = 1, #arr do fn(arr[i], i) end
end

-- the elements of an array as a Lua list of plain values (numbers, strings, objects); nil or unreadable -> {}
function M.values(arr)
    local out = {}
    if list(arr) then
        for _, v in ipairs(arr) do out[#out + 1] = M.plain(v) end
    elseif arr ~= nil then
        pcall(function() arr:ForEach(function(_, v) out[#out + 1] = M.plain(v:get()) end) end)
    end
    return out
end

-- a TMap as a Lua table: out[key] = fn(value, key), or the value itself without fn (keys plain; return nil from fn
-- to leave an entry out)
function M.map(tmap, fn)
    local out = {}
    tmap:ForEach(function(k, v)
        local key, value = M.plain(k:get()), v:get()
        if fn then value = fn(value, key) end
        if value ~= nil then out[key] = value end
    end)
    return out
end

-- an enum value as its number: numbers pass through, "eType::Name" or "Name" is looked up in names ([n] = "Name")
function M.enum(v, names)
    v = M.plain(v)
    if type(v) == "number" then return v end
    local name = tostring(v):match("::(%w+)$") or tostring(v)
    for i, n in pairs(names or {}) do if n == name then return i end end
end

return M
