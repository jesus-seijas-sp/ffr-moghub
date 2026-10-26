-- Per-save-slot data for plugins, kept next to the plugin (never inside the game's saves). It follows the game:
-- read when a slot is loaded, written when the game saves to a slot, so reloading without saving forgets what
-- changed since, exactly like the game does.
--   local st = mod:store("progress")          -- <plugin>/saves/progress_slot<N>.json
--   mod:store("progress", { file = "slot%s.json" })   -- or a name of your own in saves/ (%s: the slot)
--   st:onLoad(function(data, slot) ... end)    -- data is a fresh table for a new game
--   st.data.seen[id] = true                    -- change it any time; it's written on the next save
-- Adapted from FFR Bestiary by Law19902 (MIT).
local M = {}
local kit

local Store = {}
Store.__index = Store

function M.init(k) kit = k end

-- the folder, made only when it isn't there yet: os.execute starts a cmd.exe whose console window takes the focus
-- from the game, which then ignored keyboard, mouse and controller until the player alt-tabbed back
local function ensureDir(dir)
    local probe = dir .. ".probe"
    local f = io.open(probe, "w")
    if f then f:close(); os.remove(probe); return end
    os.execute('mkdir "' .. dir:gsub("/", "\\") .. '" 2>nul')
end

function M.new(mod, name, opts)
    local dir = mod.dir .. "/saves/"
    ensureDir(dir)
    name = name or "data"
    local file = opts and opts.file or (name .. "_slot%s.json")
    local st = setmetatable({ mod = mod, name = name, file = file, dir = dir, data = {}, slot = nil, loaders = {}, savers = {} }, Store)
    mod:on("saveLoaded", function(slot) st:load(slot) end)
    mod:on("saved", function(slot) st:save(slot) end)
    -- a slot loaded while the plugin was off
    mod:onToggle(function(on) if on and st.slot ~= kit.events.slot then st:load(kit.events.slot) end end)
    return st
end

function Store:path(slot) return self.dir .. self.file:format(tostring(slot)) end
function Store:onLoad(fn) table.insert(self.loaders, fn) end
-- fn(data, slot) runs just before writing (to add what only exists at save time)
function Store:onSave(fn) table.insert(self.savers, fn) end

function Store:load(slot)
    self.data, self.slot = {}, slot
    if slot ~= nil then
        local text = kit.readFile(self:path(slot))
        if text then
            local ok, data = pcall(kit.json.decode, text)
            if ok and type(data) == "table" then
                self.data = data
            else
                os.rename(self:path(slot), self:path(slot) .. ".bad")   -- kept for a look; the next save writes a new one
                self.mod:log("%s: unreadable file (kept as .bad), starting empty", self:path(slot))
            end
        end
    end
    for _, fn in ipairs(self.loaders) do kit.guarded(self.mod, "store load", fn, self.data, slot) end
end

function Store:save(slot)
    for _, fn in ipairs(self.savers) do kit.guarded(self.mod, "store save", fn, self.data, slot) end
    if kit.writeFile(self:path(slot), kit.json.encode(self.data) .. "\n") then
        self.slot = slot
    else
        self.mod:log("cannot write %s", self:path(slot))
    end
end

return M
