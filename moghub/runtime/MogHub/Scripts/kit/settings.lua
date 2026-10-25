-- Plugin settings: declared once in the plugin, shown in the Mods menu, kept in the plugin's own ini file (people
-- can edit it by hand too: changes are picked up within a second).
--   local s = mod:settings{
--       { header = "Battle" },
--       { key = "GodMode", label = "God mode", type = "toggle", default = false, help = "..." },
--       { key = "Exp", label = "EXP", type = "number", min = 0, max = 10, step = 0.5, default = 1, format = "x%g" },
--       { key = "Gil", label = "Gil to add", type = "choice", default = 10000,
--         choices = { { 1000, "1,000" }, { 10000, "10,000" } } },
--       { label = "Add Gil", type = "action", run = function() ... end },
--       { key = "TurboKey", type = "value", default = "CTRL+F6" },   -- in the file only, not in the menu
--   }
--   if s.GodMode then ... end
--   s:onChange(function(key, value, old) ... end)
local M = {}
local kit

function M.init(k) kit = k end

local Settings = {}
local methods = {}

local function clamp(item, n)
    if item.min then n = math.max(item.min, n) end
    if item.max then n = math.min(item.max, n) end
    if item.step and item.step > 0 then
        local base = item.min or 0
        n = base + math.floor((n - base) / item.step + 0.5) * item.step
        n = tonumber(string.format("%.6g", n))
    end
    return n
end

-- text from the file -> the item's value
local function parse(item, text)
    if text == nil then return item.default end
    if item.type == "toggle" then return kit.config.bool(text, item.default) end
    if item.type == "number" then
        local n = tonumber(text)
        return n and clamp(item, n) or item.default
    end
    if item.type == "choice" then
        for _, c in ipairs(item.choices) do
            if tostring(c[1]) == text then return c[1] end
        end
        local n = tonumber(text)
        if n then for _, c in ipairs(item.choices) do if c[1] == n then return n end end end
        return item.default
    end
    if type(item.default) == "number" then return tonumber(text) or item.default end
    if type(item.default) == "boolean" then return kit.config.bool(text, item.default) end
    return text
end

local function serialize(v)
    if type(v) == "boolean" then return v and "1" or "0" end
    return tostring(v)
end

function M.new(mod, def)
    local s = setmetatable({}, Settings)
    local items = def.items or def
    rawset(s, "_", { mod = mod, items = {}, byKey = {}, values = {}, listeners = {},
                     path = mod.dir .. "/" .. (def.file or "config.ini"), text = nil })
    local p = s._
    local section
    for _, it in ipairs(items) do
        local item = {}
        for k, v in pairs(it) do item[k] = v end
        if item.header then item.type = "header"; item.label = item.header; section = item.header end
        item.type = item.type or (type(item.default) == "boolean" and "toggle") or "value"
        item.section = item.section or section
        if item.type == "number" then item.step = item.step or 1 end
        p.items[#p.items + 1] = item
        if item.key then p.byKey[item.key] = item; p.values[item.key] = item.default end
    end
    methods.reload(s, true)
    mod:every(1000, function() methods.reload(s) end, "settings file", { loading = true })
    return s
end

-- while the plugin is switched off its settings read as their defaults (what the menu shows stays the saved value)
Settings.__index = function(s, k)
    if methods[k] then return methods[k] end
    local p = rawget(s, "_")
    if not p.mod.enabled and p.byKey[k] then return p.byKey[k].default end
    return p.values[k]
end
Settings.__newindex = function(s, k, v) methods.set(s, k, v) end

-- reads the file again; changed values reach the listeners (first = true: no events, writes a missing file)
function methods.reload(s, first)
    local p = s._
    local values, text = kit.config.read(p.path)
    if not first and text == p.text then return end
    p.text = text
    if not text and first then
        methods.writeAll(s)
        return
    end
    for key, item in pairs(p.byKey) do
        local v = parse(item, values[key])
        local old = p.values[key]
        if v ~= old then
            p.values[key] = v
            if not first then methods.fire(s, key, v, old) end
        end
    end
end

function methods.fire(s, key, v, old)
    for _, fn in ipairs(s._.listeners) do kit.guarded(s._.mod, "settings change", fn, key, v, old) end   -- not while off
    if kit.hub then kit.hub.changed() end
end

-- a new file with every setting, by section
function methods.writeAll(s)
    local p = s._
    local out, section = { "; " .. p.mod.name .. " settings. Change them in the game (main menu > Mods) or here." }, nil
    for _, item in ipairs(p.items) do
        if item.key then
            if item.section ~= section then
                section = item.section
                out[#out + 1] = ""
                out[#out + 1] = "[" .. (section or "General") .. "]"
            end
            out[#out + 1] = item.key .. " = " .. serialize(p.values[item.key])
        end
    end
    local text = table.concat(out, "\n") .. "\n"
    kit.writeFile(p.path, text)
    p.text = text
end

function methods.set(s, key, v)
    local p = s._
    local item = p.byKey[key]
    if not item then error("unknown setting " .. tostring(key), 2) end
    if item.type == "number" and type(v) == "number" then v = clamp(item, v) end
    local old = p.values[key]
    if v == old then return end
    p.values[key] = v
    kit.config.write(p.path, key, serialize(v), item.section or "General")
    p.text = kit.readFile(p.path)
    methods.fire(s, key, v, old)
end

function methods.get(s, key) return s._.values[key] end
function methods.onChange(s, fn) table.insert(s._.listeners, fn) end
function methods.items(s) return s._.items end
function methods.item(s, key) return s._.byKey[key] end

-- every item shown in the menu back to its default (actions, file-only values and `keep = true` items stay)
function methods.reset(s)
    for _, item in ipairs(s._.items) do
        if item.key and not item.keep and (item.type == "toggle" or item.type == "number" or item.type == "choice") then
            methods.set(s, item.key, item.default)
        end
    end
end

-- the text the menu shows for an item's value
function methods.display(s, item) return methods.format(s, item, s._.values[item.key]) end
function methods.format(_, item, v)
    if item.type == "toggle" then return v and "On" or "Off" end
    if item.type == "number" then return string.format(item.format or "%g", v) end
    if item.type == "choice" then
        for _, c in ipairs(item.choices) do if c[1] == v then return c[2] or tostring(c[1]) end end
        return tostring(v)
    end
    if item.type == "action" then return item.button or "" end
    return ""
end

-- one step left (-1) or right (+1); confirm on a toggle flips it, on numbers and choices it steps right and wraps
function methods.step(s, item, dir, wrap)
    local v = s._.values[item.key]
    if item.type == "toggle" then
        methods.set(s, item.key, not v)
    elseif item.type == "number" then
        local n = v + dir * item.step
        if wrap and item.max and n > item.max + 1e-9 then n = item.min or 0 end
        if wrap and item.min and n < item.min - 1e-9 then n = item.max or n end
        methods.set(s, item.key, clamp(item, n))
    elseif item.type == "choice" then
        local idx = 1
        for i, c in ipairs(item.choices) do if c[1] == v then idx = i end end
        local n = #item.choices
        local nextIdx = idx + dir
        if wrap then nextIdx = (nextIdx - 1) % n + 1 else nextIdx = math.max(1, math.min(n, nextIdx)) end
        methods.set(s, item.key, item.choices[nextIdx][1])
    end
end

M.Settings = Settings
return M
