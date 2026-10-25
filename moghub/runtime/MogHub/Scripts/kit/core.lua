-- MogHub core: logging, the one game-thread tick, timers, events and the plugin loader.
-- Every plugin runs in this Lua state (UE4SS gives each of its mods a separate one), so plugins call the kit
-- directly. One timer drives everything: UE4SS callbacks running into each other break its Lua state.
local kit = { VERSION = "0.1.0", plugins = {}, dir = nil, modsDir = nil, debug = false }

local function log(tag, fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    print("[" .. tag .. "] " .. (ok and msg or tostring(fmt)) .. "\n")
end
function kit.log(fmt, ...) log("MogHub", fmt, ...) end
-- with Debug = 1 only: step-by-step lines for finding where something fails (a crash leaves the last one in the log)
function kit.trace(fmt, ...) if kit.debug then log("trace", fmt, ...) end end

-- an error logged once per distinct message, so a failure inside a loop doesn't flood the log
local seen = {}
function kit.logOnce(tag, what, err)
    local msg = what .. ": " .. tostring(err)
    if seen[msg] then return end
    seen[msg] = true
    log(tag, "%s", msg)
end

-- a live object (a dead object's wrapper can throw instead of answering IsValid)
function kit.valid(o)
    if o == nil then return false end
    local ok, v = pcall(function() return o:IsValid() end)
    return ok and v == true
end

---------------------------------------------------------------------------------------------------
-- Files
---------------------------------------------------------------------------------------------------
function kit.readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local text = f:read("a")
    f:close()
    return text
end

-- written through a .tmp file, so a reader never sees half a file and a failed write loses nothing
function kit.writeFile(path, text)
    local tmp = path .. ".tmp"
    local f = io.open(tmp, "wb")
    if not f then return false end
    f:write(text)
    f:close()
    os.remove(path)
    return os.rename(tmp, path) ~= nil
end

function kit.exists(path)
    local f = io.open(path, "rb")
    if f then f:close() end
    return f ~= nil
end

---------------------------------------------------------------------------------------------------
-- Tick, timers and events
---------------------------------------------------------------------------------------------------
local TICK_MS = 50
local timers = {}          -- { due, every, fn, name, owner, loading }
local now = 0              -- ms since the kit started, advanced by the tick
kit.loading = true         -- behind a loading screen: objects are being torn down, timers wait

local function guarded(owner, name, fn, ...)
    if owner and not owner.enabled then return true end     -- a plugin switched off in the Mods menu sleeps
    local ok, err = pcall(fn, ...)
    if not ok then kit.logOnce(owner and owner.tag or "MogHub", name, err) end
    return ok
end
kit.guarded = guarded

-- `opts.loading = true` keeps the timer running behind loading screens
local function addTimer(owner, ms, fn, name, repeating, opts)
    local t = { due = now + ms, every = repeating and ms or nil, fn = fn, name = name or "timer", owner = owner,
                loading = opts and opts.loading }
    timers[#timers + 1] = t
    return t
end

-- the kit's own timers (plugins use mod:after / mod:every)
function kit.after(ms, fn, name, opts) return addTimer(nil, ms, fn, name, false, opts) end
function kit.every(ms, fn, name, opts) return addTimer(nil, ms, fn, name, true, opts) end

local handlers = {}        -- event -> list of { fn, owner }
function kit.emit(event, ...)
    for _, h in ipairs(handlers[event] or {}) do guarded(h.owner, event, h.fn, ...) end
end
local function addHandler(owner, event, fn)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], { fn = fn, owner = owner })
end

local function tick()
    now = now + TICK_MS
    kit.emit("tick")
    local i = 1
    while i <= #timers do
        local t = timers[i]
        if t.cancelled then
            table.remove(timers, i)
        else
            if now >= t.due and (t.loading or not kit.loading) then
                guarded(t.owner, t.name, t.fn)
                if t.every then t.due = now + t.every else t.cancelled = true end
            end
            i = i + 1
        end
    end
end

---------------------------------------------------------------------------------------------------
-- Plugins
---------------------------------------------------------------------------------------------------
-- The object a plugin's moghub.lua receives: the kit's API bound to that plugin (its folder, its log tag, its
-- settings and storage). Everything it registers is tagged with it, so errors name the plugin.
local Mod = {}
Mod.__index = Mod

function Mod:log(fmt, ...) log(self.tag, fmt, ...) end
function Mod:every(ms, fn, name, opts) return addTimer(self, ms, fn, name, true, opts) end
function Mod:after(ms, fn, name, opts) return addTimer(self, ms, fn, name, false, opts) end
function Mod:cancel(t) if t then t.cancelled = true end end
function Mod:on(event, fn) addHandler(self, event, fn) end
-- a hook that can't take the game down: errors are logged with the plugin's name
function Mod:hook(path, fn)
    local mod = self
    local ok, err = pcall(RegisterHook, path, function(...) guarded(mod, path, fn, ...) end)
    if not ok then self:log("hook %s unavailable: %s", path, tostring(err)) end
    return ok
end
-- a hotkey from a spec like "CTRL+F6" (F1-F12, A-Z, 0-9 with CTRL+ / SHIFT+ / ALT+); runs on the game thread
local MODIFIERS = { CTRL = "CONTROL", CONTROL = "CONTROL", SHIFT = "SHIFT", ALT = "ALT" }
local DIGITS = { [0] = "ZERO", "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE" }
function Mod:key(spec, fn, name)
    spec = tostring(spec or ""):upper():gsub("%s", "")
    if spec == "" or spec == "NONE" then return false end
    local mods, keyName = {}, nil
    for part in spec:gmatch("[^+]+") do
        if MODIFIERS[part] then mods[#mods + 1] = ModifierKey[MODIFIERS[part]] else keyName = part end
    end
    if keyName and keyName:match("^%d$") then keyName = DIGITS[tonumber(keyName)] end
    local key = keyName and Key[keyName]
    if not key then self:log("unknown key '%s'%s", spec, name and (" for " .. name) or ""); return false end
    local mod = self
    local run = function() ExecuteInGameThread(function() guarded(mod, name or spec, fn) end) end
    if #mods > 0 then RegisterKeyBind(key, mods, run) else RegisterKeyBind(key, run) end
    return true
end
function Mod:path(rel) return self.dir .. "/" .. rel end
-- settings shown under the plugin in the Mods menu and kept in its config.ini (see kit/settings.lua)
function Mod:settings(def)
    self.config = kit.settings.new(self, def)
    return self.config
end
-- a main-menu entry of the plugin's own (see kit/menu.lua); nil when the kit's spare entries are all taken
function Mod:screen(def)
    self.ownScreen = kit.menu.register(self, def)
    return self.ownScreen
end
function Mod:notice(msg, color, ms) kit.notice.show(msg, color, ms) end
-- a text in the player's language from the plugin's lang/<culture>.ini, else `default` (see kit/i18n.lua)
function Mod:t(key, default, ...) return kit.i18n.text(self.dir, key, default, ...) end
-- the plugin's name and description in the player's language (plugin.name / plugin.description in its lang files)
function Mod:displayName() return self:t("plugin.name", self.name) end
function Mod:displayDescription() return self:t("plugin.description", self.description) end
-- fn(on) when the plugin is switched on or off in the Mods menu. While it is off nothing it registered runs and its
-- settings read as their defaults, so a plugin undoes its changes by applying its settings again.
function Mod:onToggle(fn) self.toggles[#self.toggles + 1] = fn end
-- per-save-slot JSON storage (see kit/store.lua)
function Mod:store(name, opts) return kit.store.new(self, name, opts) end

-- require() inside a plugin looks in the plugin's own folder first, with a cache per plugin, so two plugins can
-- each have a "ui.lua" without one getting the other's
local function pluginRequire(mod, env)
    local cache = {}
    return function(name)
        if cache[name] ~= nil then return cache[name] end
        local rel = name:gsub("%.", "/")
        for _, base in ipairs({ mod.dir .. "/", mod.dir .. "/Scripts/" }) do
            local file = base .. rel .. ".lua"
            if kit.exists(file) then
                local chunk, err = loadfile(file, "t", env)
                if not chunk then error(err, 2) end
                local res = chunk(name)
                if res == nil then res = true end
                cache[name] = res
                return res
            end
        end
        return require(name)
    end
end

local function readManifest(dir)
    local m = {}
    local text = kit.readFile(dir .. "/moghub.ini")
    if not text then return m end
    for line in text:gmatch("[^\r\n]+") do
        local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if k then m[k] = v end
    end
    return m
end

function kit.loadPlugin(folder)
    local dir = kit.modsDir .. "/" .. folder
    local entry = dir .. "/moghub.lua"
    if not kit.exists(entry) then return nil end
    local manifest = readManifest(dir)
    local mod = setmetatable({
        id = folder, dir = dir, tag = folder, kit = kit,
        name = manifest.Name or folder, version = manifest.Version or "", author = manifest.Author or "",
        description = manifest.Description or "", order = tonumber(manifest.Order) or 50,
        enabled = kit.config.pluginEnabled(folder), toggles = {},
    }, Mod)
    kit.plugins[#kit.plugins + 1] = mod
    if not mod.enabled then kit.log("%s is switched off in the Mods menu", folder); return mod end
    kit.startPlugin(mod)
    return mod
end

-- runs the plugin's moghub.lua (at start-up, or when a plugin that was off is switched on)
function kit.startPlugin(mod)
    mod.started = true
    local folder, entry = mod.id, mod.dir .. "/moghub.lua"
    local env = setmetatable({ mod = mod, kit = kit }, { __index = _G })   -- its modules see both too
    env.require = pluginRequire(mod, env)
    local chunk, err = loadfile(entry, "t", env)
    if not chunk then
        mod.error = tostring(err)
        kit.log("%s: %s", folder, mod.error)
        return mod
    end
    local ok, res = pcall(chunk, mod, kit)
    if not ok then
        mod.error = tostring(res)
        kit.log("%s failed to start: %s", folder, mod.error)
    else
        kit.log("%s %s loaded", mod.name, mod.version)
    end
end

-- switches a plugin on or off right away (and for the next start)
function kit.setEnabled(mod, on)
    if mod.enabled == on then return end
    kit.config.setPluginEnabled(mod.id, on)
    mod.enabled = on
    if on and not mod.started then
        kit.startPlugin(mod)
    else
        for _, fn in ipairs(mod.toggles) do
            local ok, err = pcall(fn, on)
            if not ok then kit.logOnce(mod.tag, "switched " .. (on and "on" or "off"), err) end
        end
    end
    kit.log("%s switched %s", mod.name, on and "on" or "off")
    kit.menu.changed()
end

-- every folder in ue4ss/Mods with a moghub.lua, in name order (plugins sort themselves with Order in moghub.ini)
local function pluginFolders()
    local out = {}
    local p = io.popen('dir /b /ad "' .. kit.modsDir:gsub("/", "\\") .. '" 2>nul')
    if p then
        for name in p:lines() do
            if kit.exists(kit.modsDir .. "/" .. name .. "/moghub.lua") then out[#out + 1] = name end
        end
        p:close()
    end
    table.sort(out, function(a, b) return a:lower() < b:lower() end)
    return out
end

---------------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------------
function kit.start(dir)
    kit.dir = dir
    kit.modsDir = dir:match("^(.*)/[^/]+$") or "ue4ss/Mods"
    kit.config = require("kit.config")
    kit.config.init(kit)
    kit.debug = kit.config.kitBool("Debug", false)
    kit.json = require("kit.json")
    kit.game = require("kit.game")
    kit.game.init(kit)
    kit.i18n = require("kit.i18n")
    kit.i18n.init(kit)
    kit.tables = require("kit.tables")
    kit.notice = require("kit.notice")
    kit.notice.init(kit)
    kit.ui = require("kit.ui")
    kit.ui.init(kit)
    kit.menu = require("kit.menu")
    kit.menu.init(kit)
    kit.settings = require("kit.settings")
    kit.settings.init(kit)
    kit.store = require("kit.store")
    kit.store.init(kit)
    kit.hub = require("kit.hub")
    kit.hub.init(kit)
    kit.events = require("kit.events")
    kit.events.init(kit)
    kit.title = require("kit.title")
    kit.title.init(kit)

    kit.i18n.start()                                      -- the language first: plugins name things as they load
    kit.hub.start()                                       -- the Mods screen first: plugins take the spare slots
    for _, folder in ipairs(pluginFolders()) do kit.loadPlugin(folder) end
    table.sort(kit.plugins, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.name:lower() < b.name:lower()
    end)
    kit.events.start()
    kit.menu.start()
    kit.title.start()
    require("kit.dev").start(kit)

    -- the game starts behind a loading screen that began before the kit loaded: wait for its end (or 20 s)
    ExecuteWithDelay(20000, function() if not kit.events.sawLoading then kit.loading = false end end)
    LoopAsync(TICK_MS, function()
        ExecuteInGameThread(function() guarded(nil, "tick", tick) end)
        return false
    end)
    kit.log("version %s, %d plugin(s)", kit.VERSION, #kit.plugins)
end

kit.Mod = Mod
return kit
