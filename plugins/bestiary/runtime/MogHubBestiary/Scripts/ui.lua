-- The Bestiary screen. Its main-menu entry opens the game's Help layout (MogHub hosts it); this turns it into the
-- bestiary: the window covers the whole page, Help's native list (kit.list) shows areas with counts and their
-- enemies, and a detail panel sits beside it. Widgets come from MogHub's kit.ui: the game's own text style, headings
-- and framed panels (as on the Quests and Equipment pages); scanned enemies get the Quests check.
local game = require("game")
local store = require("store")
local tracker = require("tracker")
local data = require("bestiary_data")
local libra = require("libra")

local M = {}
M.showAll = false                  -- every enemy counts as seen, everywhere (the "Show all monsters" setting)
M.libraAll = false                 -- every enemy counts as scanned (the "Libra on every monster" setting)
M.libraPlus = true                 -- Libra+: exact status resistances and drop / steal chances (setting)
M.areaLevels = true                -- each area's enemy level range (setting)

local valid = game.valid
local function log(s) mod:log("%s", s) end

-- layout, in the UI's 1920x1080 design units
local WINDOW_W, WINDOW_H = 1760, 830
local LIST_W, LIST_H = 640, 670     -- wide enough for "Dirnado, the Continent of Wind" plus its counts
local DETAIL_W = 950
local COLUMN_GAP = 30
local SPRITE = 320
local SPRITE_FILL = 0.9            -- the enemy fills this much of the sprite box (its larger side)...
local SPRITE_FILL_MEASURED = 0.97  -- ...nearly all of it when its outline was measured (exact)
local MEASURE_SCALE = 0.5          -- dev measure mode: canvas drawn at half its fitted size, so nothing is clipped
local SPRITE_MAX_PX = 3.0          -- ...but small ones are drawn no bigger than 3 screen pixels per sprite pixel
local LABEL_W = 230
local DROP_LABEL_W = 190           -- "Items Dropped" / "Stealable Items" (left room for "Lightning Scroll I" etc.)
local PANEL_PAD = 16               -- inside a framed panel (the game's WBP_Cmn_Window), each side
local VALUE_W = DETAIL_W - SPRITE - 24 - LABEL_W - 10 - 2 * PANEL_PAD   -- detail width - sprite - gap - label - panel
local AREAS_H = 110                -- locations list height; scrolls beyond that
-- affinity groups shown in the scan panel (DA_BtlLibra styles Weak/Halved/Invalid/Absorb), eResistance values
-- (labels: the scan panel's own keys have no text, so the battle's damage words: Weak / Resisted / Immune / Absorbed)
local RESIST_ROWS = { { key = "UIBtlProp_Weakness", value = 1 }, { key = "UIBtlProp_Halved", value = 2 },
                      { key = "UIBtlProp_Invalid", value = 3 }, { key = "UIBtlProp_Absorb", value = 4 } }
local ELEMENT_ICONS_MAX = 8        -- eElement 1..8
local MAX_CONDITIONS = 21           -- eUnitStatusCondition values a unit can resist (1..21)
local NEST = 34                    -- enemy rows sit this far in from their area header
local FACE = 40                    -- face icon before an enemy's name in the list
local TOP_PAD = 26                 -- the window's title was collapsed; keep content clear of the frame
local GREY, DIM, WHITE = kit.ui.GREY, kit.ui.DIM, kit.ui.WHITE
local UNKNOWN = "???"
-- the game has no strings for these: from the plugin's lang files (built into the screen, which is built again when
-- the language changes)
local function ENCOUNTERED() return mod:t("encountered", "Encountered") end
local function SCANNED() return mod:t("scanned", "Scanned") end

-- widget helpers: MogHub's kit.ui bound to the open screen, with the Bestiary's sizes ----------------------------------
local host, ui, u, L               -- open host widget, the widgets built into it, kit.ui bound to it, its list
local rowWidgets

-- a row another list takes over: undo the dimming of a not-yet-met monster (kit.list hides our row widgets itself)
local function releaseRow(e)
    if e.dim and e.title then pcall(kit.ui.paint, e.title, WHITE) end
    e.dim = nil
end

local function new(kind, outer) return u.new(kind, outer) end
local function text(value, color) return u.text(value, color) end
local function set(t, value, color) u.set(t, value, color or WHITE) end   -- always repaints (fields go DIM and back)
local function heading(value) return u.heading(value) end
local function sized(content, w, h) return u.sized(content, w, h) end
local function spacer(h) return u.spacer(h) end
local function create(path) return u.create(path) end
local function panel(content) return u.panel(content, PANEL_PAD) end
-- "Label    value" with a scan-panel label (an ST_UI_Libra key); returns the value text
local function row(parent, key, valueW) return u.row(parent, game.libra(key) or key, LABEL_W, valueW or VALUE_W) end
-- the same with room for the game's icon widgets; returns the value text and their box
local function widgetRow(parent, key, labelW) return u.widgetRow(parent, game.libra(key) or key, labelW or LABEL_W) end

-- build (once per host widget; the game pools it) ---------------------------------------------------------------
local function build()
    -- kit.list sizes the window and list and collapses Help's own title (the page header already says BESTIARY)
    L = kit.list.attach(host, u, { window = { WINDOW_W, WINDOW_H }, list = { LIST_W, LIST_H }, lead = FACE,
                                   row = rowWidgets, release = releaseRow })
    ui = {}
    kit.trace("bestiary build: list attached")

    local body = new("HorizontalBox")
    L:setContent(body)
    local column = new("VerticalBox")
    body:AddChildToHorizontalBox(column)
    local summary = new("HorizontalBox")
    ui.summary = text("", GREY)
    ui.summaryScanned = text("", GREY)
    summary:AddChildToHorizontalBox(text(ENCOUNTERED() .. "  ", GREY))
    summary:AddChildToHorizontalBox(ui.summary)
    summary:AddChildToHorizontalBox(sized(nil, 30, nil))
    summary:AddChildToHorizontalBox(u.check(26)):SetVerticalAlignment(2)
    summary:AddChildToHorizontalBox(text(" " .. SCANNED() .. "  ", GREY))
    summary:AddChildToHorizontalBox(ui.summaryScanned)
    column:AddChildToVerticalBox(sized(summary, LIST_W, nil)):SetPadding({ Left = 14, Top = TOP_PAD, Right = 0, Bottom = 8 })
    L:takeList(column)
    body:AddChildToHorizontalBox(sized(nil, COLUMN_GAP, nil))

    -- an enemy with many affinities / locations / long traits can need more room: the panel then shrinks to fit
    local detail = new("VerticalBox")
    kit.trace("bestiary build: summary and list")
    ui.fit = u.fit(detail)
    body:AddChildToHorizontalBox(sized(ui.fit, DETAIL_W, LIST_H + 40))

    detail:AddChildToVerticalBox(spacer(TOP_PAD))          -- clear of the window frame
    -- name bar like the scan panel's: name, then Lv. and the scanned check on the right
    local nameLine = new("HorizontalBox")
    ui.name = heading("")
    nameLine:AddChildToHorizontalBox(sized(ui.name, DETAIL_W - 254, nil))
    nameLine:AddChildToHorizontalBox(sized(nil, 24, nil))  -- keep the heading's underline clear of "Lv."
    ui.level = text("")
    nameLine:AddChildToHorizontalBox(sized(ui.level, 160, nil)):SetVerticalAlignment(2)
    ui.check = u.check(40)
    nameLine:AddChildToHorizontalBox(ui.check):SetVerticalAlignment(2)
    detail:AddChildToVerticalBox(nameLine)
    ui.forms = new("HorizontalBox")
    ui.formsKey = u.keyIcon("decide")
    if ui.formsKey then ui.forms:AddChildToHorizontalBox(ui.formsKey):SetVerticalAlignment(2) end
    ui.formsText = text("", GREY)
    ui.forms:AddChildToHorizontalBox(ui.formsText):SetPadding({ Left = 8, Top = 0, Right = 0, Bottom = 0 })
    detail:AddChildToVerticalBox(ui.forms):SetPadding({ Left = 4, Top = 2, Right = 0, Bottom = 0 })
    detail:AddChildToVerticalBox(spacer(6))
    local areaInfo = new("VerticalBox")                   -- shown for area headers
    ui.areaEnc = row(areaInfo, ENCOUNTERED())
    ui.areaScan = row(areaInfo, SCANNED())
    ui.areaLevel = row(areaInfo, mod:t("enemyLevel", "Enemy level"))
    ui.areaInfo = panel(areaInfo)
    detail:AddChildToVerticalBox(sized(ui.areaInfo, DETAIL_W / 2, nil))

    local top = new("HorizontalBox")
    ui.top = top
    detail:AddChildToVerticalBox(top)
    ui.spriteBox = sized(nil, SPRITE, SPRITE)
    pcall(function() ui.spriteBox:SetClipping(1) end)    -- ClipToBounds: nothing spills over the text
    -- top-aligned so the box stays SPRITE x SPRITE: stretched to the stats panel's height, the sprite widget fitted
    -- the canvas to a box whose height changed with each enemy's text
    top:AddChildToHorizontalBox(ui.spriteBox):SetVerticalAlignment(1)
    top:AddChildToHorizontalBox(sized(nil, 24, nil))
    local info = new("VerticalBox")
    top:AddChildToHorizontalBox(sized(panel(info), DETAIL_W - SPRITE - 24, nil))

    -- fields in the scan panel's order (DA_BtlLibra); each row has a text value and/or the game's own icon widgets
    ui.affinity, ui.affinityBox = widgetRow(info, "UI_Libra_Resistance")
    ui.affinityRows = new("VerticalBox")                  -- one line per group (Weak / Resisted / ...)
    ui.affinityBox:AddChildToHorizontalBox(sized(ui.affinityRows, VALUE_W, nil))
    -- each group on its own line: its word, then one icon widget per element in a wrapping row, so a long list
    -- carries on onto the next line at full size (one widget holding eight icons can't wrap)
    ui.elementGroups = {}
    for _, kind in ipairs(RESIST_ROWS) do
        local g = { row = new("WrapBox"), label = text(game.battleWord(kind.key) or kind.key, GREY), icons = {} }
        g.row:AddChildToWrapBox(g.label):SetPadding({ Left = 0, Top = 0, Right = 8, Bottom = 0 })
        for i = 1, ELEMENT_ICONS_MAX do
            local w = create(game.ELEMENT_ICONS)
            if w then g.row:AddChildToWrapBox(w); g.icons[i] = w end
        end
        ui.affinityRows:AddChildToVerticalBox(g.row)
        ui.elementGroups[kind.value] = g
    end
    kit.trace("bestiary build: affinities")
    ui.hp = row(info, "UI_Libra_HP")
    ui.race = row(info, "UI_Libra_Race")
    ui.resist, ui.resistBox = widgetRow(info, "UI_Libra_Condition_Invalid")
    -- one icon widget per status in a wrapping row (like the affinities)
    ui.conditionWrap = new("WrapBox")
    ui.resistBox:AddChildToHorizontalBox(sized(ui.conditionWrap, VALUE_W, nil))
    ui.conditions = {}
    for i = 1, MAX_CONDITIONS do
        local w = create(game.CONDITION_ICONS)
        if not w then break end
        ui.conditionWrap:AddChildToWrapBox(w); ui.conditions[i] = w
    end
    kit.trace("bestiary build: immunities")
    -- Libra+: the statuses it only partly resists, each with its icon and percentage (the scan shows immunities only)
    ui.partial, ui.partialBox = widgetRow(info, mod:t("statusResist", "Status resistance"))
    ui.partialWrap = new("WrapBox")
    ui.partialBox:AddChildToHorizontalBox(sized(ui.partialWrap, VALUE_W, nil))
    ui.partials = {}
    for i = 1, MAX_CONDITIONS do
        local w = create(game.CONDITION_ICONS)
        if not w then break end
        local pair = new("HorizontalBox")
        pair:AddChildToHorizontalBox(w):SetVerticalAlignment(2)
        local pct = text("", GREY)
        pair:AddChildToHorizontalBox(pct):SetPadding({ Left = 2, Top = 0, Right = 14, Bottom = 0 })
        ui.partialWrap:AddChildToWrapBox(pair)
        ui.partials[i] = { box = pair, icon = w, text = pct }
    end
    kit.trace("bestiary build: partial resistances")
    info:AddChildToVerticalBox(spacer(6))
    ui.traits = { row(info, "UI_Libra_1"), row(info, "UI_Libra_2"), row(info, "UI_Libra_3"), row(info, "UI_Libra_4") }

    detail:AddChildToVerticalBox(spacer(6))
    local scan = new("HorizontalBox")
    local left, right = new("VerticalBox"), new("VerticalBox")
    scan:AddChildToHorizontalBox(sized(left, DETAIL_W / 2 - PANEL_PAD, nil))
    scan:AddChildToHorizontalBox(sized(right, DETAIL_W / 2 - PANEL_PAD, nil))
    ui.items = {}
    for _, f in ipairs({ { left, "UI_Libra_NormalDrop", "DropNormalItem", 1 }, { left, "UI_Libra_RareDrop", "DropRareItem", 2 },
                         { right, "UI_Libra_NormalSteal", "StealNormalItem", 3 }, { right, "UI_Libra_RareSteal", "StealRareItem" } }) do
        local t, box = widgetRow(f[1], f[2], DROP_LABEL_W)   -- narrower label: long item names fit their column
        local w = create(game.ITEM_ENTRY)
        if w then box:AddChildToHorizontalBox(w) end
        local pct = text("", GREY)                        -- Libra+: the chance (rare steal has none of its own)
        box:AddChildToHorizontalBox(pct):SetPadding({ Left = 8, Top = 0, Right = 0, Bottom = 0 })
        ui.items[#ui.items + 1] = { text = t, box = box, widget = w, field = f[3], rate = f[4], pct = pct }
    end
    kit.trace("bestiary build: items")
    ui.scan = panel(scan)
    detail:AddChildToVerticalBox(ui.scan)

    detail:AddChildToVerticalBox(spacer(6))
    local where = new("VerticalBox")
    where:AddChildToVerticalBox(heading(mod:t("locations", "Locations")))   -- the game has no string for this
    ui.areasScroll = new("ScrollBox")
    where:AddChildToVerticalBox(sized(ui.areasScroll, nil, AREAS_H))
    ui.areas = new("VerticalBox")
    ui.areasScroll:AddChild(ui.areas)
    ui.areasHead = panel(where)                           -- shown / hidden as a whole
    kit.trace("bestiary build: done")
    detail:AddChildToVerticalBox(ui.areasHead)
end

-- data --------------------------------------------------------------------------------------------------------------
local ELEMENT = { "Fire", "Ice", "Wind", "Earth", "Thunder", "Water", "Light", "Dark" }   -- APPROXIMATION: text until the icons are wired
local RESIST = { [1] = "Weak", [2] = "Halved", [3] = "Null", [4] = "Absorb", [5] = "Reflect" }

local rows = {}                   -- list rows: { header = area, seen = n, total = m } or { entry = e, known = bool }
local expanded = {}               -- [area] = true when its enemies are shown
local shown

local function areaName(key)
    if key == "?" then return game.libra("UI_Libra_Nodata") or "-" end
    local a = data.areas[key]
    return a and a.table and game.text(a.table, a.key) or key
end

-- areas where some unit of entry `e` was seen (`real`: even with "Show all monsters" on)
local function seenAreasOf(e, real)
    local out = {}
    if M.showAll and not real then for _, a in ipairs(e.areas) do out[a] = true end; return out end
    for _, u in ipairs(e.units) do
        local s = store.units[u]
        if s then
            for a in pairs(s.seenAreas) do out[a] = true end
            -- seen where no area could be named (enemies taken from the save are filed by groupAreasOf instead)
            if next(s.seenAreas) == nil and not s.fromSave then out["?"] = true end
        end
    end
    return out
end

-- areas the list files entry `e` under: where it was seen, plus, if the save already knew it, its data areas the
-- player has visited (all of them if none is marked visited)
local function groupAreasOf(e)
    local out = seenAreasOf(e, true)
    for _, u in ipairs(e.units) do
        local s = store.units[u]
        if s and s.fromSave then
            local any = false
            for _, a in ipairs(e.areas) do if store.visited[a] then out[a] = true; any = true end end
            if not any then for _, a in ipairs(e.areas) do out[a] = true end end
            if #e.areas == 0 then out["?"] = true end
        end
    end
    return out
end

-- scanned in the game's save
local function gameScanned(e)
    for _, u in ipairs(e.units) do
        local r = ui.records[u]; if r and r.IsAnalyzed then return true end
    end
    return false
end

-- scan data shown without a choice by hand: every enemy with "Libra on every monster", else as the game says
local function defaultScanned(e) return M.libraAll or gameScanned(e) end

-- scan data shown: a choice made by hand for this enemy wins, otherwise the default above
local function isScanned(e)
    local chosen = libra.get(e.units[1])
    if chosen ~= nil then return chosen end
    return defaultScanned(e)
end

local function entryName(e)
    local p = game.unitParam(e.units[1]) or {}
    return p.Name or ("#" .. e.units[1])
end

-- UE4SS hands TMap / TArray out-params back as Lua tables; values may be numbers, enum names or wrapped params
local plain, enumIndex = kit.ue.plain, kit.ue.enum

local ELEMENT_NAMES = { [1] = "Fire", "Ice", "Wind", "Earth", "Thunder", "Water", "Light", "Dark" }
local RESIST_NAMES = { [1] = "Weakness", "Halved", "Invalid", "Absorb", "Reflect" }

local function affinities(p)
    local out = {}
    pcall(function()
        for k, v in pairs(p.ElementResistanceList or {}) do
            local key, val = k, v
            if type(v) == "table" then key, val = v.Key, v.Value end   -- array of pairs, if that's the shape
            local r = RESIST[enumIndex(val, RESIST_NAMES) or 0]
            if r then out[#out + 1] = r .. " " .. (ELEMENT[enumIndex(key, ELEMENT_NAMES) or 0] or "?") end
        end
    end)
    table.sort(out)
    return #out > 0 and table.concat(out, ", ") or (game.libra("UI_Libra_Nodata") or "-")
end

local function traits(p)
    local out = {}
    pcall(function()
        for i = 1, 4 do
            local t = p.Traits and p.Traits[i]
            if t == nil then break end
            local s = plain(t)
            if type(s) == "string" and s ~= "" then out[#out + 1] = s end
        end
    end)
    return out
end

local hpRate
local logged = false
local function logShapes(p)
    if logged then return end
    logged = true
    local parts = {}
    for k, v in pairs(p.ElementResistanceList or {}) do parts[#parts + 1] = type(k) .. ":" .. tostring(k) .. "=" .. type(v) .. ":" .. tostring(plain(v)) end
    log("shapes: elements {" .. table.concat(parts, ", ") .. "} traits " .. type(p.Traits) .. " n=" .. tostring(p.Traits and #p.Traits))
end

-- enemy HP as the battle shows it: the table value times the save's difficulty rate (Expert: x1.6)
hpRate = function()
    local d = 1
    pcall(function() d = plain(game.saveData().Player.GameDifficulty) end)
    return data.enemyHpRate[tostring(enumIndex(d, { [0] = "Easy", "Normal", "Expert" }) or 1)] or 1
end

-- detail panel ------------------------------------------------------------------------------------------------------
-- the enemy's battle sprite, playing its idle animation, in the game's own SpriteStudio player. (The game's
-- WBP_UnitSsPlayerWidget looks projects up by unit in a table that only has party members and Visions.)
local function setSprite(id)
    pcall(function()
        if not valid(ui.sprite) then
            ui.sprite = new("CPP_MuchaSsPlayerWidget")
            ui.spriteBack = new("Border")                 -- clear; magenta in the dev measure mode
            ui.spriteBack:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
            ui.spriteBack:SetBrushColor({ R = 0, G = 0, B = 0, A = 0 })
            ui.spriteBack:SetContent(ui.sprite)
            ui.spriteBox:SetContent(ui.spriteBack)
            ui.sprite:SetRenderTransformPivot({ X = 0.5, Y = 0.5 })
        end
        local path = id and data.sprites[tostring(id)]
        local project = path and game.load(path)
        ui.sprite:SetVisibility(project and 4 or 1)          -- SelfHitTestInvisible / Collapsed
        if not project or (ui.spriteFor == path and not M.measure) then return end
        ui.spriteFor = path
        -- The widget draws the animation's canvas fitted into the box (k box pixels per sprite pixel), centred.
        -- Scale it so the enemy fills the box (whole screen pixels per sprite pixel, so it stays sharp), and move the
        -- enemy's centre to the box centre. The enemy's outline comes from measuring it as the game draws it
        -- (spriteBox: x0, x1, y0, y1 in sprite pixels from the canvas centre, y down; tools/sprite_measure.py);
        -- without one, from the estimate in spriteSize (tools/sprite_bounds.py).
        local b = data.spriteSize[path] or { cw = 256, ch = 256, py = 0, w = 128, h = 128, cy = 64 }
        local k = math.min(SPRITE / b.cw, SPRITE / b.ch)
        local m = data.spriteBox and data.spriteBox[path]
        local bw, bh, cx, cy
        if m then bw, bh, cx, cy = m[2] - m[1], m[4] - m[3], (m[1] + m[2]) / 2, (m[3] + m[4]) / 2
        else bw, bh, cx, cy = b.w, b.h, 0, -(b.py * b.ch + b.cy) end
        local px = math.min(SPRITE_MAX_PX, (m and SPRITE_FILL_MEASURED or SPRITE_FILL) * SPRITE / math.max(bw, bh, 1))
        local vs = u.viewportScale()                     -- screen px per design px
        -- whole screen pixels per sprite pixel when there is room for 2 or more (sharp); below that the exact fit, as
        -- rounding 1.9 down to 1 would halve the enemy
        if px * vs >= 2 then px = math.floor(px * vs) / vs end
        local scale, tx, ty = px / k, -px * cx, -px * cy
        if M.measure then scale, tx, ty = MEASURE_SCALE, 0, 0 end
        M.lastSprite = { path = path, k = k, vs = vs }
        ui.spriteBack:SetBrushColor(M.measure and { R = 1, G = 0, B = 1, A = 1 } or { R = 0, G = 0, B = 0, A = 0 })
        ui.sprite:SetRenderScale({ X = scale, Y = scale })
        ui.sprite:SetRenderTranslation({ X = tx, Y = ty })
        ui.sprite:SetSsProject(project)
        ui.sprite:SetAutoUpdate(true)
        local names, idle = {}, nil
        pcall(function() ui.sprite:GetAnimationNameList(names) end)
        for _, n in ipairs(names) do
            local name = n:get():ToString()
            if name:lower():find("idle") then idle = name; break end
        end
        ui.sprite:PlayAnimation(FName(idle or "idle"), 0, 1.0, 0)
    end)
end

-- every value field: texts set, the game's icon widgets hidden (text-only state: ??? or blank)
local function fields(value, color)
    ui.forms:SetVisibility(1)
    for _, t in ipairs({ ui.affinity, ui.hp, ui.race, ui.resist, ui.partial, ui.traits[1], ui.traits[2], ui.traits[3], ui.traits[4] }) do
        set(t, value, color); t:SetVisibility(4)
    end
    ui.affinityBox:SetVisibility(1); ui.resistBox:SetVisibility(1); ui.partialBox:SetVisibility(1)
    pcall(function() ui.partial:GetParent():SetVisibility(M.libraPlus and 4 or 1) end)   -- the whole Libra+ line
    for _, it in ipairs(ui.items) do
        set(it.text, value, color); it.text:SetVisibility(4); it.box:SetVisibility(1); set(it.pct, "")
    end
    set(ui.level, "")
end

local function blocks(visible)
    ui.top:SetVisibility(visible and 4 or 1); ui.scan:SetVisibility(visible and 4 or 1)
    ui.areaInfo:SetVisibility(visible and 1 or 4)
end

-- the level range of an area's random encounters, bosses left out: { min, max }, or nil (towns, and caves whose
-- enemies are placed on the map). From the data file (tools/area_levels.py).
local function levelRange(area) return data.areaLevel and data.areaLevel[area] end

local function showHeader(r)
    setSprite(nil)
    blocks(false)
    ui.forms:SetVisibility(1)                             -- an enemy's forms line must not stay on a header
    ui.check:SetVisibility(1)
    set(ui.level, "")
    ui.name:SetTitle(FText(areaName(r.header)))
    set(ui.areaEnc, r.seen .. " / " .. r.total)
    set(ui.areaScan, r.scanned .. " / " .. r.total)
    local lv = levelRange(r.header)
    set(ui.areaLevel, lv and (lv[1] == lv[2] and tostring(lv[1]) or (lv[1] .. " - " .. lv[2])) or "-")
    pcall(function() ui.areaLevel:GetParent():SetVisibility(M.areaLevels and 4 or 1) end)
    ui.areasHead:SetVisibility(1)
    ui.areas:ClearChildren()
end

local function showUnknown()
    setSprite(nil)
    blocks(true)
    fields(UNKNOWN, DIM)
    ui.check:SetVisibility(1)
    ui.name:SetTitle(FText(UNKNOWN))
    ui.areasHead:SetVisibility(1)
    ui.areas:ClearChildren()
end

local function showLocations(e, id)
    ui.areasHead:SetVisibility(4)
    ui.areas:ClearChildren()
    local seen, shownAny = seenAreasOf(e), false
    for _, a in ipairs(e.areas) do
        local named = data.areas[a] and data.areas[a].table
        if named then
            local k = seen[a]
            ui.areas:AddChildToVerticalBox(text(k and areaName(a) or UNKNOWN, k and WHITE or DIM)):SetPadding({ Left = 14, Top = 2, Right = 0, Bottom = 2 })
            shownAny = true
        end
    end
    if not shownAny then                                  -- only met in unnamed places (world-map events)
        ui.areas:AddChildToVerticalBox(text(game.libra("UI_Libra_Nodata") or "-", DIM)):SetPadding({ Left = 14, Top = 2, Right = 0, Bottom = 2 })
    end
    setSprite(id)
end

-- element -> resistance for a unit (eElement / eResistance numbers)
local function resistances(p)
    local out = {}
    pcall(function()
        for k, v in pairs(p.ElementResistanceList or {}) do
            local key, val = k, v
            if type(v) == "table" then key, val = v.Key, v.Value end
            local e, r = enumIndex(key, ELEMENT_NAMES), enumIndex(val, RESIST_NAMES)
            if e and r and r > 0 then out[e] = r end
        end
    end)
    return out
end

-- elements whose reaction the player has already seen in battle (the save's analyzedElments), for unscanned entries
local function discovered(e)
    local out = {}
    for _, u in ipairs(e.units) do
        local r = ui.records[u]
        if r then
            pcall(function()
                r.analyzedElments:ForEach(function(k, v)
                    if plain(v) then out[enumIndex(k, ELEMENT_NAMES) or -1] = true end
                end)
            end)
        end
    end
    return out
end

-- statuses the unit is immune to (StatusConditionResistanceList value 100). APPROXIMATION: the scan panel's own
-- rule lives in C++; "Resistances" is keyed UI_Libra_Condition_Invalid, so immune-only is assumed. Check in battle.
-- statuses resisted in part (StatusConditionResistanceList 1..99): { { status, percent }, ... } by status
local function partialResistances(p)
    local out = {}
    pcall(function()
        for k, v in pairs(p.StatusConditionResistanceList or {}) do
            local key, val = k, v
            if type(v) == "table" then key, val = v.Key, v.Value end
            local n = tonumber(plain(val)) or 0
            if n > 0 and n < 100 then out[#out + 1] = { tonumber(plain(key)) or plain(key), n } end
        end
    end)
    table.sort(out, function(x, y) return tostring(x[1]) < tostring(y[1]) end)
    return out
end

-- a drop / steal chance from DT_UnitParameter's divisor (1 in `rate`; 0: never) as "8.3%"
local function chance(rate)
    rate = tonumber(rate)
    if not rate or rate <= 0 then return "" end
    local pct = 100 / rate
    if pct == math.floor(pct) then return string.format("%d%%", pct) end
    return string.format("%.1f%%", pct)
end

local function immunities(p)
    local out = {}
    pcall(function()
        for k, v in pairs(p.StatusConditionResistanceList or {}) do
            local key, val = k, v
            if type(v) == "table" then key, val = v.Key, v.Value end
            if (tonumber(plain(val)) or 0) >= 100 then out[#out + 1] = tonumber(plain(key)) or plain(key) end
        end
    end)
    table.sort(out, function(x, y) return tostring(x) < tostring(y) end)
    return out
end

local form = 1                     -- which unit (form / phase / mode) of the shown entry
local function showEntry(e, met)
    if form > #e.units then form = 1 end
    local id = e.units[form]
    local p = game.unitParam(id) or {}
    local scanned = isScanned(e)
    local none = game.libra("UI_Libra_Nodata") or "-"
    blocks(true)
    fields(UNKNOWN, DIM)                                  -- start from "nothing known", then reveal

    ui.name:SetTitle(FText(entryName(e)))
    ui.check:SetVisibility(scanned and 4 or 1)
    set(ui.level, (game.libra("UI_Libra_Level") or "Lv.") .. " " .. tostring(p.Level or "?"))
    -- confirm switches Libra for this enemy; Left / Right (or Q / E) page through its forms / phases
    local hint = (met and "" or (mod:t("notMet", "Not met yet") .. "        "))
        .. (scanned and mod:t("libraOn", "Libra: On") or mod:t("libraOff", "Libra: Off"))
    if libra.get(e.units[1]) ~= nil then hint = hint .. " " .. mod:t("setByYou", "(set by you)") end
    if #e.units > 1 then hint = hint .. "        " .. mod:t("forms", "Form {1} / {2}  (Left / Right)", form, #e.units) end
    ui.forms:SetVisibility(4)
    set(ui.formsText, hint, GREY)

    -- Affinities: the game's icons per Weak/Halved/Null/Absorb; before a scan only reactions already seen in battle
    local res, seen = resistances(p), (not scanned) and discovered(e) or nil
    local any = false
    for value, g in pairs(ui.elementGroups) do
        local list = {}
        for el, r in pairs(res) do if r == value and (scanned or seen[el]) then list[#list + 1] = el end end
        table.sort(list)
        local on = #list > 0
        g.row:SetVisibility(on and 4 or 1)
        for i, w in pairs(g.icons) do
            w:SetVisibility(list[i] and 4 or 1)
            if list[i] then pcall(function() w:SetElementList({ list[i] }) end) end
        end
        any = any or on
    end
    if any then ui.affinity:SetVisibility(1); ui.affinityBox:SetVisibility(4)
    elseif scanned then set(ui.affinity, none) end

    -- Trait 1 shows without a scan (DA_BtlLibra); everything else needs one
    local tr = traits(p)
    set(ui.traits[1], tr[1] or none)
    if not scanned then return showLocations(e, id) end

    set(ui.hp, p.MaxHitPoint and tostring(math.floor(p.MaxHitPoint * hpRate() + 0.5)) or "?")
    set(ui.race, game.libra("UI_Libra_Race_" .. (game.RACE_KEY[tonumber(plain(p.Race)) or 0] or "None")) or "?")
    local imm = immunities(p)
    if #ui.conditions > 0 and #imm > 0 then
        ui.resist:SetVisibility(1); ui.resistBox:SetVisibility(4)
        for i, w in ipairs(ui.conditions) do
            w:SetVisibility(imm[i] and 4 or 1)
            if imm[i] then pcall(function() w:SetConditionList({ imm[i] }) end) end
        end
    else
        set(ui.resist, none)                              -- an empty icon list draws only its underline
    end
    if M.libraPlus then
        local part = partialResistances(p)
        if #ui.partials > 0 and #part > 0 then
            ui.partial:SetVisibility(1); ui.partialBox:SetVisibility(4)
            for i, slot in ipairs(ui.partials) do
                local st = part[i]
                slot.box:SetVisibility(st and 4 or 1)
                if st then
                    pcall(function() slot.icon:SetConditionList({ st[1] }) end)
                    set(slot.text, st[2] .. "%", GREY)
                end
            end
        else
            set(ui.partial, none)
        end
    end
    for k = 2, 4 do set(ui.traits[k], tr[k] or none) end
    for _, it in ipairs(ui.items) do
        if it.widget then
            it.text:SetVisibility(1); it.box:SetVisibility(4)
            pcall(function() it.widget:SetContentId(tonumber(plain(p[it.field])) or -1) end)
        else
            set(it.text, game.itemName(p[it.field]) or none)
        end
        local has = (tonumber(plain(p[it.field])) or -1) >= 0
        set(it.pct, (M.libraPlus and has and it.rate) and chance(p.Rates and p.Rates[it.rate]) or "", GREY)
    end
    showLocations(e, id)
end

local function show(i, force)
    local r = rows[i]
    if not r or (shown == i and not force) then return end
    if shown ~= i then form = 1 end
    shown = i
    if r.header then showHeader(r) elseif r.known then showEntry(r.entry, r.met) else showUnknown() end
end

-- list --------------------------------------------------------------------------------------------------------------
-- With "Show all monsters" every enemy is listed under all of its areas, but the counts stay what was really met.
local function buildRows()
    local total, members, seenIn, metIn, seenCount, scannedCount = {}, {}, {}, {}, 0, 0
    for _, e in ipairs(data.entries) do
        for _, a in ipairs(e.areas) do
            total[a] = (total[a] or 0) + 1
            members[a] = members[a] or {}
            table.insert(members[a], e)
        end
        local met = groupAreasOf(e)
        if next(met) then
            seenCount = seenCount + 1
            if isScanned(e) then scannedCount = scannedCount + 1 end
        end
        for a in pairs(met) do metIn[a] = metIn[a] or {}; metIn[a][e] = true end
        local seen = met
        if M.showAll then
            seen = {}
            for a in pairs(met) do seen[a] = true end
            for _, a in ipairs(e.areas) do seen[a] = true end
            if next(seen) == nil then seen["?"] = true end    -- no area in the data: under "no data"
        end
        for a in pairs(seen) do
            seenIn[a] = seenIn[a] or {}
            seenIn[a][e] = true
            if not total[a] or a == "?" then                 -- seen somewhere the data doesn't list it
                members[a] = members[a] or {}
                local listed = false
                for _, x in ipairs(members[a]) do if x == e then listed = true end end
                if not listed then table.insert(members[a], e) end
            end
        end
    end
    local order, inOrder = {}, {}
    for _, a in ipairs(data.areaOrder) do order[#order + 1] = a; inOrder[a] = true end
    for a in pairs(seenIn) do if not inOrder[a] then order[#order + 1] = a end end

    rows = {}
    for _, a in ipairs(order) do
        local named = a == "?" or (data.areas[a] and data.areas[a].table)
        if named and (M.showAll or store.visited[a] or seenIn[a]) then
            local list, seenHere, metHere = members[a] or {}, seenIn[a] or {}, metIn[a] or {}
            local n, sc = 0, 0
            for e in pairs(metHere) do
                n = n + 1
                if isScanned(e) then sc = sc + 1 end
            end
            rows[#rows + 1] = { header = a, seen = n, scanned = sc, total = math.max(total[a] or 0, #list) }
            if expanded[a] then
                for _, e in ipairs(list) do
                    rows[#rows + 1] = { entry = e, area = a, known = seenHere[e] == true, met = metHere[e] == true }
                end
            end
        end
    end
    set(ui.summary, string.format("%d / %d", seenCount, #data.entries), GREY)
    set(ui.summaryScanned, string.format("%d / %d", scannedCount, #data.entries), GREY)
end

-- the text a row shows
local function rowLabel(r) return r.header and areaName(r.header) or (r.known and entryName(r.entry) or UNKNOWN) end

local function fillList(focus)
    L:setRows(#rows, function(i) return rowLabel(rows[i]) end)
    shown = nil
    if #rows == 0 then
        ui.name:SetTitle(FText("")); fields(""); setSprite(nil); ui.check:SetVisibility(1); ui.areasHead:SetVisibility(1)
        return
    end
    focus = math.min(focus or 1, #rows)
    show(focus)
end

local function refresh(focus)
    local sd = game.saveData()
    ui.records = sd and game.records(sd) or {}
    buildRows()
    fillList(focus)
end

-- the extras on each list row (kit.list adds them once to each recycled row widget): on area headers the count, the
-- check and the scanned count on the right; on enemies the check alone, when scanned
rowWidgets = function(e, uu, tree)
    e.count, e.scanned, e.icon = uu.text("", nil, tree), uu.text("", nil, tree), uu.check(26, tree)
    pcall(function() e.count:SetJustification(2); e.scanned:SetJustification(2) end)   -- right
    e.countBox = uu.sized(e.count, 110, nil, tree)
    e.gap = uu.sized(nil, 18, nil, tree)
    e.scanBox = uu.sized(e.scanned, 52, nil, tree)
    e.right:AddChildToHorizontalBox(e.countBox)
    e.right:AddChildToHorizontalBox(e.gap)
    e.right:AddChildToHorizontalBox(e.icon):SetVerticalAlignment(2)
    e.right:AddChildToHorizontalBox(e.scanBox)
end

-- each visible row, every tick (the list recycles row widgets, so a row can't keep another row's state)
local function decorate(i, e)
    local r = rows[i]
    local header = r and r.header
    kit.list.indent(e, header and 0 or NEST)              -- enemies sit in from their area
    -- the enemy's face (the battle timeline's icon) before its name; ??? rows keep the space so names line up
    local path = r and r.entry and r.known and data.faces[tostring(r.entry.units[1])]
    kit.list.lead(e, (r and r.entry) and true or false, path and L:texture(path))
    if not e.count or e.row == r then return end         -- the rest only changes with the row
    e.row = r
    -- listed but not met yet ("Show all monsters"): dimmed; other rows keep the game's own colours
    local dim = (r and r.entry and r.known and not r.met) and true or false
    if e.title and dim ~= (e.dim or false) then e.dim = dim; pcall(u.paint, e.title, dim and DIM or WHITE) end
    local scannedEnemy = r and r.entry and r.known and isScanned(r.entry)
    e.countBox:SetVisibility(header and 4 or 1)
    e.gap:SetVisibility(header and 4 or 1)
    e.scanBox:SetVisibility(header and 4 or 1)
    e.icon:SetVisibility((header or scannedEnemy) and 4 or 1)
    if header then
        e.count:SetText(FText(r.seen .. " / " .. r.total))
        e.scanned:SetText(FText(tostring(r.scanned)))
    end
end

-- Confirm on a row. Help's handler (WBP_HelpLayout:HandleClickedHelpList) pushes the tutorial pop-up with
-- CPP_BFL_GameWidgetManager:PushLayoutWidget(UI.Layout.Tutorial, PrioritizeExisting) and stops if it gets no tutorial
-- widget back. While the Bestiary is open the push is turned into one of the main menu's own layout, which is
-- already open, so nothing opens; the push also tells us a row was confirmed. On an area header that expands or
-- collapses the area; on an enemy it switches Libra (its scan data) on or off.
local focusRow                     -- row of the entry widget holding focus (the detail panel may lag behind it)
-- work left for the next poll by the push hook, the Q / E keys and confirm (nothing else schedules its own call:
-- UE4SS callbacks running into each other broke its Lua state)
local pendingConfirm, pendingRefresh, pendingForm
function M.queueForm(step) pendingForm = step end
-- development: show entry after entry in the detail panel (sprite review)
local devIndex, pendingDev, devTargets = 0, false, nil
function M.queueDevNext() pendingDev = true end
function M.toggleMeasure()
    M.measure = not M.measure
    pcall(function() ui.fit:SetStretch(M.measure and 0 or 2) end)   -- measure: no shrinking, the box stays put
    log("measure " .. tostring(M.measure))
end
local function confirmed(row)
    row = row or focusRow or shown
    local r = rows[row or 0]
    if r and r.header then
        expanded[r.header] = not expanded[r.header] or nil
        pendingRefresh = row or true                      -- next tick, after the click has been handled
    elseif r and r.entry and r.known then                -- Libra on / off for this enemy
        local e = r.entry
        libra.set(e.units[1], not isScanned(e), defaultScanned(e))
        pendingRefresh = row or true                      -- the counts change too
    end
end

-- MogHub owns the PushLayoutWidget hook and the stray tutorial pop-up (for every screen it hosts) and calls this
function M.confirm()
    if not host or not ui then return end
    pendingConfirm = focusRow or true                     -- handled by the next poll
end

-- open / poll / close (MogHub's screen callbacks) ----------------------------------------------------------------------
-- h: the Help layout MogHub hands over, uu: kit.ui bound to it. The game pools the widget: it is built once per
-- object and refreshed each time it opens.
local builtFor, pending
function M.open(h, uu)
    host, u = h, uu
    local addr = h:GetFullName()                          -- unique per object, unlike its address
    local ok, err = pcall(function()
        -- built again for a new widget, or when the language changed (texts are built in)
        local key = addr .. "|" .. kit.i18n.lang
        kit.trace("bestiary: open (build %s)", tostring(builtFor ~= key or not (ui and valid(ui.name))))
        if builtFor ~= key or not (ui and valid(ui.name)) then build(); builtFor = key end
        kit.trace("bestiary: refresh")
        pendingForm, pendingConfirm, pendingRefresh = nil, nil, nil   -- input from before it was open
        local here = tracker.currentArea()
        if here then expanded[here] = true end           -- open on the area the player is in
        refresh(1)
        kit.trace("bestiary: open done")
    end)
    if not ok then log("screen: " .. tostring(err)); host = nil end
end

function M.close() host = nil end

-- every tick while open
function M.poll()
    if not host or not ui then return end
    if pendingRefresh then local r = pendingRefresh; pendingRefresh = nil; pcall(refresh, r ~= true and r or shown) end
    if pendingConfirm then local r = pendingConfirm; pendingConfirm = nil; pcall(confirmed, r ~= true and r or nil) end
    if pendingForm then local f = pendingForm; pendingForm = nil; pcall(M.switchForm, f) end
    if pendingDev then
        pendingDev = false
        -- normal: every entry; measure mode: one unit for each sprite not measured yet
        if not devTargets or devTargets.measure ~= M.measure then
            devTargets, devIndex = { measure = M.measure }, 0
            local seen = {}
            for _, en in ipairs(data.entries) do
                for f, unit in ipairs(en.units) do
                    local sp = data.sprites[tostring(unit)]
                    if not M.measure and f == 1 then devTargets[#devTargets + 1] = { en, f }
                    elseif M.measure and sp and not data.spriteBox[sp] and not seen[sp] then
                        seen[sp] = true; devTargets[#devTargets + 1] = { en, f }
                    end
                end
            end
            log("dev targets: " .. #devTargets)
        end
        devIndex = devIndex % math.max(#devTargets, 1) + 1
        local t = devTargets[devIndex]
        if not t then return end
        local e = t[1]
        local id = e.units[t[2]]
        local path = data.sprites[tostring(id)]
        form = t[2]
        pcall(showEntry, e, true)
        local ls = M.lastSprite or {}
        log(string.format("dev sprite %d unit %d %s k=%.5f vs=%.4f measure=%s", devIndex, id, tostring(path),
            ls.k or 0, ls.vs or 0, tostring(M.measure)))
        shown = focusRow                                  -- so the cursor's row does not replace it next tick
        return
    end
    focusRow = L:poll(decorate)
    -- the detail panel follows the cursor; an enemy (its sprite loads) waits until the cursor rests for one tick, so
    -- scrolling past rows stays smooth
    if focusRow and focusRow ~= shown then
        local r = rows[focusRow]
        if not (r and r.entry and r.known) or pending == focusRow then show(focusRow); pending = nil
        else pending = focusRow end
    end
end

-- Q / E: previous / next form of the shown entry (only while the Bestiary is open)
function M.switchForm(step)
    if not host or not ui then return end
    local r = rows[shown or 0]
    if not (r and r.entry and r.known and #r.entry.units > 1) then return end
    form = (form - 1 + step) % #r.entry.units + 1
    show(shown, true)
end

-- development: where is keyboard focus?
function M.debugFocus()
    local out = {}
    pcall(function() out[#out + 1] = "host=" .. tostring(host and host:HasFocusedDescendants()) end)
    pcall(function() out[#out + 1] = "list=" .. tostring(L.view:HasFocusedDescendants()) end)
    pcall(function() out[#out + 1] = "rows=" .. #rows .. " items=" .. tostring(L.view:GetNumItems()) .. " focusRow=" .. tostring(focusRow) end)
    log("focus: " .. table.concat(out, " "))
end

return M
