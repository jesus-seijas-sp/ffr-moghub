-- Translations. MogHub follows the game's text language (or the Language setting in MogHub's config.ini) and looks
-- texts up in lang/<culture>.ini files next to MogHub and each plugin, falling back to the English in the code:
--   mod:t("partyHealed", "Party healed")                  -- lang/ja.ini:  partyHealed = パーティを回復しました
--   mod:t("gilAdded", "{1} Gil added", amount)            -- {1}, {2}... are the extra arguments
-- Settings are looked up by themselves (<key>.label, <key>.help, ...: see kit/settings.lua), so a plugin becomes
-- translatable just by adding lang files. The game's official languages and their culture codes:
local M = {}
local kit

M.LANGS = { "en", "fr", "de", "es", "ja", "ko", "zh-Hans", "zh-Hant" }
M.NAMES = { en = "English", fr = "Français", de = "Deutsch", es = "Español", ja = "日本語", ko = "한국어",
            ["zh-Hans"] = "简体中文", ["zh-Hant"] = "繁體中文" }
M.lang = "en"

local known = {}
for _, l in ipairs(M.LANGS) do known[l:lower()] = l end

-- a culture name from the engine or the config ("ja-JP", "zh-CN", "zh-Hant-TW", "FR") -> one of M.LANGS, or nil
function M.normalize(name)
    if type(name) ~= "string" or name == "" then return nil end
    local n = name:gsub("_", "-"):lower()
    if known[n] then return known[n] end
    if n:find("^zh") then
        if n:find("hant") or n:find("%-tw") or n:find("%-hk") or n:find("%-mo") then return "zh-Hant" end
        return "zh-Hans"
    end
    return known[n:match("^(%a%a)")]
end

-- the game's text language: the engine's current culture (the game's Text Language option sets it)
local function gameLanguage()
    local lib = kit.game.lib("/Script/Engine.Default__KismetInternationalizationLibrary")
    if not lib then return nil end
    for _, get in ipairs({ function() return lib:GetCurrentLanguage() end, function() return lib:GetCurrentCulture() end }) do
        local ok, v = pcall(get)
        if ok and v ~= nil then
            local s = type(v) == "string" and v or (v.ToString and v:ToString())
            local l = M.normalize(s)
            if l then return l end
        end
    end
end

function M.detect()
    local forced = M.normalize(kit.config.kitValue("Language", "auto"))
    return forced or gameLanguage() or "en"
end

---------------------------------------------------------------------------------------------------
-- Files
---------------------------------------------------------------------------------------------------
-- lang/<culture>.ini: "key = text" lines (UTF-8; ; or # starts a comment; \n is a line break)
local function parse(text)
    local out = {}
    if not text then return out end
    text = text:gsub("^\239\187\191", "")              -- UTF-8 BOM
    for line in text:gmatch("[^\r\n]+") do
        if not line:match("^%s*[;#]") then
            local k, v = line:match("^%s*(.-)%s*=%s*(.-)%s*$")
            if k and k ~= "" then out[k] = v:gsub("\\n", "\n") end
        end
    end
    return out
end

local cache = {}                -- dir -> lang -> { key = text }
local function dict(dir, lang)
    cache[dir] = cache[dir] or {}
    local d = cache[dir][lang]
    if not d then
        d = parse(kit.readFile(dir .. "/lang/" .. lang .. ".ini"))
        cache[dir][lang] = d
    end
    return d
end

local function format(text, ...)
    local args = table.pack(...)
    if args.n == 0 then return text end
    return (text:gsub("{(%d+)}", function(i)
        local v = args[tonumber(i)]
        return v ~= nil and tostring(v) or "{" .. i .. "}"
    end))
end

-- the text for `key` from `dir`'s lang file for the current language, else `default` (the English in the code;
-- lang/en.ini is only a template for translators, written by tools/i18n_template.py, and never read)
function M.text(dir, key, default, ...)
    local s = M.lang ~= "en" and dict(dir, M.lang)[key] or nil
    if s == nil then s = default end
    if s == nil then return key end
    return format(s, ...)
end

-- MogHub's own texts (lang files in MogHub's folder)
function M.t(key, default, ...) return M.text(kit.dir, key, default, ...) end

---------------------------------------------------------------------------------------------------
-- Following the game
---------------------------------------------------------------------------------------------------
function M.init(k)
    kit = k
    kit.t = M.t
end

-- checked now and then: the player can change the text language in the game's options at any time
function M.start()
    M.lang = M.detect()
    kit.log("language: %s", M.lang)
    kit.every(2000, function()
        local l = M.detect()
        if l == M.lang then return end
        M.lang = l
        kit.log("language: %s", l)
        kit.emit("languageChanged", l)
        if kit.menu then kit.menu.changed() end
    end, "language", { loading = true })
end

-- lang files edited while the game runs (development): read them again
function M.reload() cache = {} end

return M
