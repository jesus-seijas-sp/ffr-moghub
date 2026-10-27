-- Main-menu screens. The kit's data pak (zzz_MogHub_9_P) adds scene rows to the game's main-menu table: "Mods"
-- (the kit's hub) and a few spare slots that plugins can claim for an entry of their own (MogHub Bestiary does). Each
-- row opens the game's Help layout, which the screen's owner then rebuilds, so the page gets the game's own frame,
-- header, list, scrollbar, key guide, transitions and input handling.
--
-- Technique from FFR Bestiary by Law19902 (MIT): the DisplaySceneList append, the Help layout as host, and the
-- confirm signal taken from Help's attempt to open a tutorial.
local M = {}
local kit, valid, game

M.HUB_TAG = "UI.MainMenu.Scene.Mods"
M.SLOT_TAGS = { "UI.MainMenu.Scene.MogHub1", "UI.MainMenu.Scene.MogHub2", "UI.MainMenu.Scene.MogHub3" }
M.PAK = "zzz_MogHub_9_P"
M.HOST_CLASS = "WBP_HelpLayout_C"
M.HOST_PARENT = "WBP_MainMenuLayout"    -- the game's own Help screen is not under the main menu
local MENU_TABLE = "/Game/UI/MainMenu/Data/DT_MainMenuScene.DT_MainMenuScene"
local ENTRY = "/Game/UI/MainMenu/Root/Widget/WBP_MainMenuRootEntry.WBP_MainMenuRootEntry_C"
local SYSTEM_TAG = "UI.MainMenu.Scene.System"
local TUTORIAL_LAYOUT, OPEN_LAYOUT = "UI.Layout.Tutorial", "UI.Layout.MainMenu"

M.screens = {}           -- tag -> screen { tag, title, owner, opened, poll, closed, confirm }
local order = {}         -- tags in menu order (plugin slots, then the hub)

function M.init(k)
    kit, valid, game = k, k.valid, k.game
end

-- the data pak, next to the game's own: FFRS/Content/Paks/~mods (from Mods/MogHub: Mods, ue4ss, Win64, Binaries)
local pakChecked
function M.pakInstalled()
    if pakChecked == nil then
        pakChecked = kit.exists(kit.dir .. "/../../../../../Content/Paks/~mods/" .. M.PAK .. ".utoc")
        if not pakChecked then
            kit.log("menu pak not found in FFRS/Content/Paks/~mods: extract the whole MogHub zip into the game folder")
        end
    end
    return pakChecked
end

---------------------------------------------------------------------------------------------------
-- Registering screens
---------------------------------------------------------------------------------------------------
-- def: { title = "Bestiary", opened = fn(host, ui), poll = fn(host), closed = fn(), confirm = fn() }
-- Returns the screen, or nil when every slot is taken.
function M.register(owner, def, tag)
    if not tag then
        for _, t in ipairs(M.SLOT_TAGS) do
            if not M.screens[t] then tag = t; break end
        end
    end
    if not tag then
        kit.log("%s: no free main-menu slot for '%s'", owner and owner.id or "kit", tostring(def.title))
        return nil
    end
    local screen = { tag = tag, owner = owner, title = def.title or "Mod", opened = def.opened, poll = def.poll,
                     closed = def.closed, confirm = def.confirm }
    M.screens[tag] = screen
    if tag == M.HUB_TAG then order[#order + 1] = tag else table.insert(order, #order + 1, tag) end
    -- the hub goes last, right above System
    table.sort(order, function(a, b)
        if a == M.HUB_TAG then return false end
        if b == M.HUB_TAG then return true end
        return a < b
    end)
    return screen
end

-- a screen's entry text in the player's language: screen.title from its plugin's lang files (hub.title for the hub)
function M.title(screen)
    if not screen then return "" end
    if screen.owner then return screen.owner:t("screen.title", screen.title) end
    return kit.t("hub.title", screen.title)
end

---------------------------------------------------------------------------------------------------
-- Menu entries
---------------------------------------------------------------------------------------------------
-- Names: the pak's rows carry placeholder names ("Mod 1"); the rows' texts are set from the registered screens.
local named = {}         -- tag -> title already written into its row
local function nameRows()
    local todo = false
    for tag, s in pairs(M.screens) do if named[tag] ~= M.title(s) then todo = true end end
    if not todo then return end
    local dt = StaticFindObject(MENU_TABLE)
    if not valid(dt) then return end
    pcall(function()
        dt:ForEachRow(function(_, row)
            local tag = row.SceneTag.TagName:ToString()
            local s = M.screens[tag]
            if s and named[tag] ~= M.title(s) then
                named[tag] = M.title(s)
                local ok, err = pcall(function()
                    row.SceneTitle = FText(M.title(s))
                    row.EntryName = FText(M.title(s))
                end)
                if not ok then kit.logOnce("MogHub", "menu row names", err) end
            end
        end)
    end)
end

-- a screen whose plugin is switched off has no entry
local function shown(tag)
    local s = M.screens[tag]
    return s and (not s.owner or s.owner.enabled)
end

-- The menu reads DA_MainMenuRoot.DisplaySceneList each time it opens: the registered screens go before System.
function M.addEntries()
    if not M.pakInstalled() or #order == 0 then return end
    nameRows()
    local da = FindFirstOf("CPP_DA_MainMenuRoot")
    if not valid(da) then return end
    local list = da.DisplaySceneList
    local n = #list
    if n == 0 then return end
    local tags, theirs = {}, {}
    for i = 1, n do
        tags[i] = list[i].TagName:ToString()
        if not M.screens[tags[i]] then theirs[#theirs + 1] = tags[i] end
    end
    -- [... game ..., ours ..., System, ... after System]
    local at = #theirs + 1
    for i, t in ipairs(theirs) do if t == SYSTEM_TAG then at = i; break end end
    local rebuilt = {}
    for i = 1, at - 1 do rebuilt[#rebuilt + 1] = theirs[i] end
    for _, t in ipairs(order) do if shown(t) then rebuilt[#rebuilt + 1] = t end end
    for i = at, #theirs do rebuilt[#rebuilt + 1] = theirs[i] end
    if table.concat(rebuilt, ",") == table.concat(tags, ",") then return end
    if #rebuilt < n then list:Empty(); n = 0 end          -- an entry went away: written again from the start
    for i, t in ipairs(rebuilt) do
        if i <= n then
            if tags[i] ~= t then list[i].TagName = FName(t) end
        else
            list[i] = { TagName = FName(t) }
        end
    end
    if kit.debug then kit.log("main menu: %s", table.concat(rebuilt, ", ")) end
end

-- a plugin was switched on or off: its entry comes or goes the next time the main menu opens
function M.changed()
    pcall(M.addEntries)
    if kit.hub then kit.hub.changed() end
end

-- The entry texts, in case the row names could not be set: entries showing one of our tags get its title.
local function labelEntries()
    for _, e in ipairs(FindAllOf("WBP_MainMenuRootEntry_C") or {}) do
        pcall(function()
            local tag = e.VM_MainMenuRootEntry.SceneTag.TagName:ToString()
            local s = M.screens[tag]
            if s and e.CommonTextBlock_82:GetText():ToString() ~= M.title(s) then
                e.CommonTextBlock_82:SetText(FText(M.title(s)))
            end
        end)
    end
end

---------------------------------------------------------------------------------------------------
-- The open screen
---------------------------------------------------------------------------------------------------
local lastTag, lastTagAt = nil, 0   -- scene of the main-menu entry chosen last, and when
local lastHost, calls = nil, 0
-- the activated Help layout under the main menu, or nil. The menu pools the widget, so the one found last is
-- checked first; the slow object search runs every third call otherwise.
local function findHost()
    if valid(lastHost) then
        local ok, active = pcall(function() return lastHost:IsActivated() end)
        if ok and active then return lastHost end
    end
    calls = calls + 1
    if calls % 3 ~= 0 then return nil end
    for _, w in ipairs(FindAllOf(M.HOST_CLASS) or {}) do
        if valid(w) and (w:GetFullName():find(M.HOST_PARENT, 1, true) or w:GetFullName() == M.titleHost) then
            local ok, active = pcall(function() return w:IsActivated() end)
            if ok and active then lastHost = w; return w end
        end
    end
end

-- the main menu's open page (CPP_VM_MainMenu:GetCurrentScene), or nil. Not its page stack (SceneDataStack): UE4SS
-- can't always read the stack's GameplayTags, and an unreadable stack let FFR Bestiary take MogHub's pages for its own
local function currentScene()
    local tag
    pcall(function() tag = FindFirstOf("CPP_VM_MainMenu"):GetCurrentScene().TagName:ToString() end)
    if tag == "" or tag == "None" then tag = nil end
    return tag
end

-- which entry is focused in the main menu right now (backup for the click hook)
local function focusedTag()
    for _, e in ipairs(FindAllOf("WBP_MainMenuRootEntry_C") or {}) do
        local ok, tag = pcall(function()
            if e:HasFocusedDescendants() or e:HasAnyUserFocus() then return e.VM_MainMenuRootEntry.SceneTag.TagName:ToString() end
        end)
        if ok and tag and M.screens[tag] then return tag end
    end
end

M.open = nil             -- { host, name, screen, ui }
M.titleHost = nil        -- full name of the Help layout borrowed on the title screen
local pendingConfirm, clickTick, ticks, lastClick = false, nil, 0, 0
local foreign            -- the open host belongs to another mod's entry

local function close()
    local o = M.open
    M.open = nil
    -- a Help layout borrowed on the title screen goes back to being the game's Help
    if o and o.name == M.titleHost then M.titleHost = nil end
    if o and o.screen.closed then kit.guarded(o.screen.owner, "screen closed", o.screen.closed) end
    if o and kit.list then kit.list.giveKeys(o.name) end      -- the list's own Left / Right paging back
    if o and kit.list then pcall(kit.list.releaseAll) end     -- the rows as the game made them, for the next user
end

-- safety net: if a tutorial pop-up still opens over our screen, hide it and take it off the input stack
local closing = {}
local function closeStrayPopup()
    for _, w in ipairs(FindAllOf("WBP_TutorialLayout_C") or {}) do
        local ok, active = pcall(function() return w:IsActivated() end)
        local key = w:GetAddress()
        if ok and active and not closing[key] then
            local vis = 4
            pcall(function() vis = w:GetVisibility() end)
            closing[key] = vis
            pcall(function() w:SetVisibility(1) end)
            pcall(function() w:DeactivateWidget() end)
            if os.clock() - lastClick > 0.3 then pendingConfirm = true end
        elseif ok and not active and closing[key] then
            pcall(function() w:SetVisibility(closing[key]) end)
            closing[key] = nil
        end
    end
end

function M.poll()
    ticks = ticks + 1
    local host = findHost()
    if not host then
        if M.open then close() end
        foreign = nil
        return
    end
    local name = host:GetFullName()
    if name == foreign then return end
    if not M.open or M.open.name ~= name then
        if M.open then close() end
        -- the host was just activated: the entry chosen a moment ago says which screen it is. Another mod's entry
        -- that also opens the Help layout (FFR Bestiary's) leaves it alone.
        local scene = name ~= M.titleHost and currentScene() or nil
        if (scene and scene:find("^UI%.MainMenu%.Scene%.") and not M.screens[scene])
            or (not scene and lastTag and not M.screens[lastTag] and os.clock() - lastTagAt < 3) then
            foreign = name
            return
        end
        local tag
        if name == M.titleHost then tag = M.HUB_TAG
        elseif scene and M.screens[scene] then tag = scene
        elseif lastTag and M.screens[lastTag] and os.clock() - lastTagAt < 3 then tag = lastTag
        else tag = focusedTag() or (M.screens[lastTag or ""] and lastTag) or M.HUB_TAG end
        if not shown(tag) then tag = M.HUB_TAG end          -- an entry left over from before its plugin was switched off
        local screen = M.screens[tag] or M.screens[M.HUB_TAG]
        if not screen then return end
        kit.trace("open %s: widgets", screen.title)
        local o = { host = host, name = name, screen = screen, ui = kit.ui.on(host) }
        M.open = o
        -- Left / Right belong to the screen while it is open (kit.list.takeKeys; given back in close())
        kit.trace("open %s: keys", screen.title)
        pcall(function() kit.list.takeKeys(host, kit.ui.find(host.WidgetTree.RootWidget, "WBP_HelpList")) end)
        kit.trace("open %s: opened()", screen.title)
        pendingConfirm = false
        if screen.opened then
            local ok = kit.guarded(screen.owner, "screen " .. screen.title, screen.opened, host, o.ui)
            if not ok then o.failed = true end
        end
        return
    end
    local screen = M.open.screen
    if M.open.failed then return end
    if clickTick and ticks - clickTick <= 10 then pcall(closeStrayPopup) end
    if pendingConfirm then
        pendingConfirm = false
        if screen.confirm then kit.guarded(screen.owner, "confirm", screen.confirm) end
    end
    if screen.poll then kit.guarded(screen.owner, "screen " .. screen.title, screen.poll, host) end
end

---------------------------------------------------------------------------------------------------
-- Hooks
---------------------------------------------------------------------------------------------------
local hooked = false
local function installHooks()
    if hooked then return end
    if not kit.game.loadedClass(ENTRY) then return end
    hooked = true
    pcall(function()
        RegisterHook("/Game/UI/MainMenu/Root/Widget/WBP_MainMenuRootEntry.WBP_MainMenuRootEntry_C:BP_OnClicked", function(ctx)
            pcall(function() lastTag = ctx:get().VM_MainMenuRootEntry.SceneTag.TagName:ToString() end)
            lastTagAt = os.clock()
            if kit.debug then kit.log("main menu entry chosen: %s", tostring(lastTag)) end
        end)
    end)
end

function M.start()
    -- Confirm in Help's list asks for a tutorial pop-up: while one of our screens is open, that push becomes one of
    -- the main menu's own layout (already open, so nothing opens) and counts as "confirm" for the screen.
    local ok, err = pcall(function()
        RegisterHook("/Script/mucha.CPP_BFL_GameWidgetManager:PushLayoutWidget", function(_, tag)
            local t = tag:get()
            local name = t.TagName:ToString()
            if kit.debug then kit.log("PushLayoutWidget %s", name) end
            if not M.open or name ~= TUTORIAL_LAYOUT then return end
            -- on the title screen the main menu isn't open: the Help layout itself is
            local open = (M.open.name == M.titleHost) and kit.config.kitValue("TitleLayoutTag", "UI.Layout.System.Help") or OPEN_LAYOUT
            t.TagName = FName(open)
            lastClick = os.clock()
            clickTick = ticks
            pendingConfirm = true
        end)
    end)
    if not ok then kit.log("hook PushLayoutWidget: %s", tostring(err)) end
    kit.every(1000, function() installHooks(); M.addEntries(); labelEntries() end, "menu entries")
    kit.every(50, M.poll, "screens")
end

return M
