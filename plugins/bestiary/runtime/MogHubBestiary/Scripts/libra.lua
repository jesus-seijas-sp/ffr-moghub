-- Libra by hand: enemies whose scan data the player switched on (or off) in the Bestiary, whatever the game's save
-- says. Kept in libra.json next to the plugin, for every save alike: it is how the player wants the Bestiary to
-- look, not progress.
local json = kit.json

local M = {}
local FILE = mod:path("libra.json")

local choices                       -- [unitId] = true (shown) / false (hidden)

local function load()
    choices = {}
    local f = io.open(FILE, "r")
    if not f then return end
    local ok, data = pcall(json.decode, f:read("a")); f:close()
    if not ok or type(data) ~= "table" then return end
    for id, v in pairs(data) do if type(v) == "boolean" then choices[tonumber(id)] = v end end
end

local function save()
    local out = {}
    for id, v in pairs(choices) do out[tostring(id)] = v end
    local tmp = FILE .. ".tmp"
    local f = io.open(tmp, "w")
    if not f then return end
    f:write(json.encode(out), "\n"); f:close()
    os.remove(FILE)
    os.rename(tmp, FILE)
end

-- true / false when the player chose, nil to follow the game
function M.get(id)
    if not choices then load() end
    return choices[id]
end

-- `on` for this enemy; the choice is forgotten when it matches what the game says anyway
function M.set(id, on, natural)
    if not choices then load() end
    if on == natural then choices[id] = nil else choices[id] = on end
    save()
end

-- every choice forgotten: the game decides again
function M.clear()
    choices = {}
    save()
end

return M
