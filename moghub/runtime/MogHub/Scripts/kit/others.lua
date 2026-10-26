-- The game's other mods, the ones that aren't MogHub plugins: UE4SS mods (folders in ue4ss\Mods) and pak mods (paks in
-- Content\Paks\~mods, its subfolders, and extra paks in Content\Paks). The Mods screen lists them and switches them
-- on or off; the change takes effect the next time the game starts.
--   UE4SS mod: on = an enabled.txt in its folder (or a "Name : 1" line in Mods\mods.txt); switching writes / removes
--   enabled.txt and keeps mods.txt in step when it lists the mod.
--   Pak mod: off = its .pak renamed to .pak.disabled. The game keeps a running mod's .utoc / .ucas open but not its
--   small .pak, and without the .pak the pair isn't loaded, so this works while playing. A pak mod in the old single
--   .pak format is locked while the game runs: switch it with the game closed.
local M = {}
local kit

local BASE_GAME = { ["ffrs-windows"] = true, ["ffrs-windows_0_p"] = true, ["global"] = true }
local OURS = { ["zzz_moghub_9_p"] = true, ["zzz_moghub_p"] = true }   -- (1.0.0 named it zzz_MogHub_P)
local NOT_MODS = { shared = true, Keybinds = true }   -- UE4SS's own library folders, not mods

M.list = {}                -- { kind = "ue4ss" | "pak", name, on, path, where, files, changed }

function M.init(k) kit = k end

-- Folder listings come from UE4SS's IterateGameDirectories (in the game's process): io.popen("dir") starts a
-- cmd.exe, which froze the game for seconds and crashed it when the Mods screen opened. Folders are named by their
-- path under the game's FFRS folder, e.g. { "Content", "Paks", "~mods" }.
local function folder(path)
    local ok, d = pcall(function()
        local d = IterateGameDirectories().Game
        for _, part in ipairs(path) do
            d = d and d[part]
        end
        return d
    end)
    return ok and type(d) == "table" and d or nil
end

-- names in a folder: its folders (dirs = true) or its files
local function names(path, dirs)
    local out = {}
    local d = folder(path)
    if d then
        if dirs then
            for k, v in pairs(d) do
                if type(k) == "string" and k:sub(1, 2) ~= "__" and type(v) == "table" then out[#out + 1] = k end
            end
        else
            for _, f in ipairs(d.__files or {}) do
                local n = f.__name
                if type(n) == "string" then out[#out + 1] = n end
            end
        end
    end
    table.sort(out, function(a, b) return a:lower() < b:lower() end)
    return out
end

local MODS = { "Binaries", "Win64", "ue4ss", "Mods" }
local PAKS = { "Content", "Paks" }
local function sub(path, ...)
    local out = { table.unpack(path) }
    for _, p in ipairs({ ... }) do out[#out + 1] = p end
    return out
end

M.paksDir = nil
local function paksDir()
    -- from Mods/MogHub: Mods, ue4ss, Win64, Binaries, FFRS
    M.paksDir = M.paksDir or (kit.dir .. "/../../../../../Content/Paks")
    return M.paksDir
end

-- mods.txt: "Name : 1" lines (UE4SS loads a listed mod set to 1, and any mod with an enabled.txt)
local function modsTxt()
    local out = {}
    for line in (kit.readFile(kit.modsDir .. "/mods.txt") or ""):gmatch("[^\r\n]+") do
        local name, v = line:match("^%s*([^;#:][^:]-)%s*:%s*(%d)%s*$")
        if name then out[name] = v == "1" end
    end
    return out
end

local function scanUE4SS(out)
    local listed = modsTxt()
    for _, folder in ipairs(names(MODS, true)) do
        local dir = kit.modsDir .. "/" .. folder
        if folder ~= "MogHub" and not NOT_MODS[folder] and not kit.exists(dir .. "/moghub.lua")
            and (kit.exists(dir .. "/Scripts/main.lua") or kit.exists(dir .. "/enabled.txt") or listed[folder] ~= nil
                 or kit.exists(dir .. "/dlls/main.dll")) then
            out[#out + 1] = { kind = "ue4ss", name = folder, path = dir, where = "ue4ss\\Mods\\" .. folder,
                              on = kit.exists(dir .. "/enabled.txt") or listed[folder] == true }
        end
    end
end

local function scanPaks(out, path, dir, where)
    local files = names(path)
    local present = {}
    for _, f in ipairs(files) do present[f:lower()] = true end
    for _, f in ipairs(files) do
        local base, disabled = f:match("^(.-)%.pak(%.disabled)$")
        if not base then base = f:match("^(.-)%.pak$") end
        if base and not BASE_GAME[base:lower()] and not OURS[base:lower()] then
            local parts = {}
            for _, ext in ipairs({ ".pak", ".utoc", ".ucas", ".sig" }) do
                if present[(base .. ext):lower()] or (ext == ".pak" and disabled) then parts[#parts + 1] = base .. ext end
            end
            out[#out + 1] = { kind = "pak", name = base, path = dir .. "/" .. base .. ".pak", where = where,
                              on = not disabled, zen = present[(base .. ".utoc"):lower()] == true, files = parts }
        end
    end
end

function M.scan()
    local started = os.clock()
    local out = {}
    pcall(scanUE4SS, out)
    local paks = paksDir()
    pcall(scanPaks, out, sub(PAKS, "~mods"), paks .. "/~mods", "Content\\Paks\\~mods")
    for _, name in ipairs(names(sub(PAKS, "~mods"), true)) do
        pcall(scanPaks, out, sub(PAKS, "~mods", name), paks .. "/~mods/" .. name, "Content\\Paks\\~mods\\" .. name)
    end
    pcall(scanPaks, out, PAKS, paks, "Content\\Paks")
    -- what was switched this session shows as switched until the next start (the listing may predate the switch)
    local changed = {}
    for _, m in ipairs(M.list) do if m.changed then changed[m.kind .. "|" .. m.path] = m end end
    for _, m in ipairs(out) do
        local was = changed[m.kind .. "|" .. m.path]
        if was then m.changed, m.on = true, was.on end
    end
    kit.trace("others: %d mod(s), %.0f ms (game folder %s)", #out, (os.clock() - started) * 1000,
        tostring(folder({}) and folder({}).__absolute_path))
    M.list = out
    return out
end

-- mods.txt lines for `name` set to 1 / 0 (only when it lists the mod)
local function setModsTxt(name, on)
    local path = kit.modsDir .. "/mods.txt"
    local text = kit.readFile(path)
    if not text then return end
    local found = false
    local out = text:gsub("([^\r\n]*)", function(line)
        local n = line:match("^%s*([^;#:][^:]-)%s*:%s*%d%s*$")
        if n == name then found = true; return n .. " : " .. (on and "1" or "0") end
        return line
    end)
    if found then kit.writeFile(path, out) end
end

-- switches a mod on or off for the next start; returns true, or false and why
function M.setEnabled(m, on)
    if m.on == on then return true end
    local ok, err
    if m.kind == "ue4ss" then
        if on then ok = kit.writeFile(m.path .. "/enabled.txt", "")
        else os.remove(m.path .. "/enabled.txt"); ok = not kit.exists(m.path .. "/enabled.txt") end
        if ok then setModsTxt(m.name, on) end
    else
        local from, to = m.path .. (on and ".disabled" or ""), m.path .. (on and "" or ".disabled")
        ok, err = os.rename(from, to)
        if not ok then
            return false, m.zen and tostring(err) or "locked"
        end
    end
    if not ok then return false, err end
    m.on, m.changed = on, not m.changed
    kit.log("%s %s switched %s (next start)", m.kind, m.name, on and "on" or "off")
    return true
end

return M
