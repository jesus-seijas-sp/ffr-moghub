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
local OURS = { ["zzz_moghub_p"] = true }
local NOT_MODS = { shared = true, Keybinds = true }   -- UE4SS's own library folders, not mods

M.list = {}                -- { kind = "ue4ss" | "pak", name, on, path, where, files, changed }

function M.init(k) kit = k end

local function win(path) return (path:gsub("/", "\\")) end

-- names in a folder: folders (dirs = true) or files
local function names(dir, dirs)
    local out = {}
    local p = io.popen('dir /b ' .. (dirs and "/ad" or "/a-d") .. ' "' .. win(dir) .. '" 2>nul')
    if p then
        for n in p:lines() do out[#out + 1] = n end
        p:close()
    end
    table.sort(out, function(a, b) return a:lower() < b:lower() end)
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
    for _, folder in ipairs(names(kit.modsDir, true)) do
        local dir = kit.modsDir .. "/" .. folder
        if folder ~= "MogHub" and not NOT_MODS[folder] and not kit.exists(dir .. "/moghub.lua")
            and (kit.exists(dir .. "/Scripts/main.lua") or kit.exists(dir .. "/enabled.txt") or listed[folder] ~= nil
                 or kit.exists(dir .. "/dlls/main.dll")) then
            out[#out + 1] = { kind = "ue4ss", name = folder, path = dir, where = "ue4ss\\Mods\\" .. folder,
                              on = kit.exists(dir .. "/enabled.txt") or listed[folder] == true }
        end
    end
end

local function scanPaks(out, dir, where)
    local files = names(dir)
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
    local out = {}
    pcall(scanUE4SS, out)
    local paks = paksDir()
    pcall(scanPaks, out, paks .. "/~mods", "Content\\Paks\\~mods")
    for _, sub in ipairs(names(paks .. "/~mods", true)) do
        pcall(scanPaks, out, paks .. "/~mods/" .. sub, "Content\\Paks\\~mods\\" .. sub)
    end
    pcall(scanPaks, out, paks, "Content\\Paks")
    -- keep what was switched this session (it shows until the next start)
    local changed = {}
    for _, m in ipairs(M.list) do if m.changed then changed[m.kind .. "|" .. m.path] = true end end
    for _, m in ipairs(out) do m.changed = changed[m.kind .. "|" .. m.path] end
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
