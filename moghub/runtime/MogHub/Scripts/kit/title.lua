-- "Mods" on the title screen. WBP_TitleLayout_C:SetDisplayEntryList takes the entry types to show (0-4); the list
-- is shown again with a type the game doesn't use, so its own click handler ignores that entry, and choosing it
-- opens the Mods screen in a Help layout pushed by the kit.
local M = {}
local kit, valid

local TITLE = "/Game/UI/Title/WBP_TitleLayout.WBP_TitleLayout_C"
local TITLE_ENTRY = "/Game/UI/Title/List/WBP_Title_ListEntry.WBP_Title_ListEntry_C"
local MODS_TYPE = 5
local state = { hooked = false, rebuilding = false, entry = nil, layout = nil, focused = nil, refreshed = false }

function M.init(k) kit, valid = k, k.valid end

local function entries(layout)
    local out = {}
    pcall(function()
        layout.WBP_DirectionLayoutMenu.DirectionGridPanel.EntryWidgetList:ForEach(function(_, e)
            local w = e:get()
            if valid(w) then out[#out + 1] = w end
        end)
    end)
    return out
end

local function addEntry(layout, types)
    local before = entries(layout)
    if #types == 0 or #before ~= #types then return end
    for _, v in ipairs(types) do if v == MODS_TYPE then return end end
    local list = {}
    for i, v in ipairs(types) do list[i] = v end
    list[#list + 1] = MODS_TYPE
    state.rebuilding = true
    local ok, err = pcall(function() layout:SetDisplayEntryList(list) end)
    state.rebuilding = false
    if not ok then kit.log("title entry: %s", tostring(err)); return end
    local rebuilt = entries(layout)
    if #rebuilt ~= #types + 1 then return end
    local mine = rebuilt[#rebuilt]
    state.entry, state.layout = mine:GetFName():ToString(), layout
    pcall(function() mine.CommonTextBlock_47:SetText(FText(kit.t("hub.title", "Mods"))) end)
end

-- The Help layout, pushed the way the game pushes its layouts; the one that turns up activated outside the main
-- menu right after is the Mods screen's host.
local function openHub()
    local lib = kit.game.lib("CPP_BFL_GameWidgetManager")
    local tag = kit.config.kitValue("TitleLayoutTag", "UI.Layout.System.Help")
    local pushed = false
    for _, args in ipairs({ { { TagName = FName(tag) }, 0 }, { { TagName = FName(tag) } } }) do
        if not pushed then
            local ok, err = pcall(function() lib:PushLayoutWidget(table.unpack(args)) end)
            pushed = ok
            if not ok and kit.debug then kit.log("PushLayoutWidget(%s): %s", tag, tostring(err)) end
        end
    end
    if not pushed then kit.notice.show(kit.t("title.unavailable", "Mods: open it from the main menu once a game is loaded"), "warn", 3000); return end
    local tries, timer = 0, nil
    timer = kit.every(100, function()
        tries = tries + 1
        if tries > 30 then timer.cancelled = true; return end
        for _, w in ipairs(FindAllOf(kit.menu.HOST_CLASS) or {}) do
            if valid(w) and not w:GetFullName():find(kit.menu.HOST_PARENT, 1, true) then
                local ok, active = pcall(function() return w:IsActivated() end)
                if ok and active then kit.menu.titleHost = w:GetFullName(); timer.cancelled = true; return end
            end
        end
    end, "title host", { loading = true })
end

local function hook()
    if state.hooked then return end
    if not (kit.game.class(TITLE) and kit.game.class(TITLE_ENTRY)) then return end
    state.hooked = true
    local ok, err = pcall(function()
        RegisterHook(TITLE .. ":SetDisplayEntryList", function(ctx, list)
            if state.rebuilding then return end
            local layout = ctx:get()
            local types = {}
            pcall(function() list:get():ForEach(function(_, e) types[#types + 1] = e:get() end) end)
            state.entry = nil
            kit.after(50, function() addEntry(layout, types) end, "title entry", { loading = true })
        end)
        -- the click handler gets the button event, not the entry: the chosen one has the focus (or the mouse)
        RegisterHook(TITLE .. ":HandleClickedEntry", function(ctx)
            local mine
            for _, e in ipairs(entries(ctx:get())) do
                if e:GetFName():ToString() == state.entry then mine = e end
            end
            if not mine then return end
            local function active(w)
                local hit = false
                pcall(function() hit = hit or w:HasAnyUserFocus() end)
                pcall(function() hit = hit or w:HasFocusedDescendants() end)
                pcall(function() hit = hit or w:IsHovered() end)
                return hit
            end
            local chosen = active(mine)
            pcall(function() chosen = chosen or active(mine.PathButton) end)
            chosen = chosen or state.focused == state.entry
            if chosen then kit.after(250, openHub, "open from title", { loading = true }) end
        end)
    end)
    for _, fn in ipairs({ "SetFocuedItemWidget", "BP_OnItemFocused" }) do
        pcall(function()
            RegisterHook("/Script/EnhancedUI.CPP_WBP_MenuBase:" .. fn, function(_, a)
                pcall(function()
                    local name = a:get():GetFName():ToString()
                    if name:find("Title_ListEntry", 1, true) then state.focused = name end
                end)
            end)
        end)
    end
    if not ok then kit.log("title hooks: %s", tostring(err)); state.hooked = false end
end

-- the title list is usually shown before the hook exists: show it again once so the entry appears
local function refresh()
    if state.entry or not state.hooked or state.refreshed then return end
    for _, layout in ipairs(FindAllOf("WBP_TitleLayout_C") or {}) do
        if valid(layout) and not layout:GetFullName():find("Default__", 1, true) and layout:IsVisible() then
            local types = {}
            for _, e in ipairs(entries(layout)) do types[#types + 1] = e.EntryType end
            if #types > 0 then state.refreshed = true; addEntry(layout, types) end
            return
        end
    end
end

M.openHub = openHub     -- for dev_eval.lua

function M.start()
    if not kit.config.kitBool("TitleEntry", true) then return end
    kit.every(1000, function() hook(); refresh() end, "title entry", { loading = true })
end

return M
