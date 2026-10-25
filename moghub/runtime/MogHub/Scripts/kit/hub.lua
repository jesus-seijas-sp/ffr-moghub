-- The "Mods" screen: every installed plugin, each opening into its settings. Built in the game's Help layout: the
-- native list on the left, a detail panel on the right for the row under the cursor.
--   Confirm on a plugin: open / close it.  Left / Right on a plugin: switch it on / off, right away.
--   Confirm on a setting: change it (toggles flip, lists step and wrap).  Left / Right on a setting: previous / next.
local M = {}
local kit, valid, list

local WINDOW_W, WINDOW_H = 1760, 830
local LIST_W, LIST_H = 820, 690
local DETAIL_W = 720                -- with the list and its cursor area, fills the window inside its frame
local NEST = 34

local rows = {}
local expanded = {}
local view                      -- the built screen: { L, u, detail widgets }
local shown                     -- row shown in the detail panel
local horizontal                -- Left / Right reader (kit.game.leftRight)

function M.init(k)
    kit, valid = k, k.valid
    list = require("kit.list")
    list.init(k)
    kit.list = list
    horizontal = k.game.leftRight()
end

---------------------------------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------------------------------
local t = function(...) return kit.t(...) end
local function onOff(on) return on and t("on", "On") or t("off", "Off") end
-- a header's text in the plugin's language (items keep the English header name in item.section)
local function section(mod, name) return kit.i18n.text(mod.dir, "header." .. name, name) end

local function pluginStatus(mod)
    if not mod.enabled then return "<  " .. onOff(false) .. "  >", kit.ui.DIM end
    if mod.error then return t("hub.error", "Error"), kit.ui.GOLD end
    return "<  " .. onOff(true) .. "  >", kit.ui.WHITE
end

local function buildRows()
    rows = {}
    for _, mod in ipairs(kit.plugins) do
        rows[#rows + 1] = { kind = "plugin", mod = mod }
        if expanded[mod.id] then
            rows[#rows + 1] = { kind = "switch", mod = mod }
            if mod.ownScreen then rows[#rows + 1] = { kind = "info", mod = mod } end
            if mod.enabled and mod.config then
                for _, item in ipairs(mod.config:items()) do
                    if item.type == "header" then
                        rows[#rows + 1] = { kind = "section", mod = mod, item = item }
                    elseif item.label and item.type ~= "value" and not item.hidden then
                        rows[#rows + 1] = { kind = "item", mod = mod, item = item }
                    end
                end
            end
        end
    end
    if #rows == 0 then rows[1] = { kind = "empty" } end
end

local function label(i)
    local r = rows[i]
    if not r then return "" end
    if r.kind == "plugin" then return r.mod:displayName() end
    if r.kind == "switch" then return t("hub.switch", "Switched on") end
    if r.kind == "info" then return t("hub.menuEntry", "Menu entry") end
    if r.kind == "section" then return "- " .. r.mod.config:text(r.item, "label") .. " -" end
    if r.kind == "item" then return r.mod.config:text(r.item, "label") end
    return t("hub.noPlugins", "No plugins installed")
end

local function value(r)
    if r.kind == "plugin" then return pluginStatus(r.mod) end
    if r.kind == "switch" then return onOff(r.mod.enabled), r.mod.enabled and kit.ui.WHITE or kit.ui.DIM end
    if r.kind == "info" then return kit.menu.title(r.mod.ownScreen), kit.ui.GREY end
    if r.kind == "item" then
        local kind = r.item.type
        if kind == "action" then return r.mod.config:text(r.item, "button") or "", kit.ui.BLUE end
        local text = r.mod.config:display(r.item)
        if kind == "number" or kind == "choice" then text = "<  " .. text .. "  >" end
        return text, kit.ui.WHITE
    end
    return "", kit.ui.GREY
end

---------------------------------------------------------------------------------------------------
-- Detail panel
---------------------------------------------------------------------------------------------------
local function show(i)
    shown = i
    local r = rows[i]
    if not view or not r then return end
    local u, d = view.u, view.detail
    local name, sub, body, val = "", "", "", ""
    if r.kind == "plugin" or r.kind == "switch" or r.kind == "info" then
        local mod = r.mod
        name = mod:displayName()
        local parts = {}
        if mod.version ~= "" then parts[#parts + 1] = t("hub.version", "Version {1}", mod.version) end
        if mod.author ~= "" then parts[#parts + 1] = t("hub.author", "by {1}", mod.author) end
        sub = table.concat(parts, "   ")
        body = mod:displayDescription()
        if mod.error then body = body .. "\n\n" .. t("hub.failed", "It could not start: {1}", mod.error) end
        local state = onOff(mod.enabled) .. "      " .. t("hub.hintSwitchLR", "(Left / Right: switch on / off)")
        if r.kind == "plugin" then
            val = state .. "\n" .. (expanded[mod.id] and t("hub.hintClose", "Confirm: close") or t("hub.hintOpen", "Confirm: show its settings"))
        elseif r.kind == "switch" then
            body = t("hub.switchHelp", "While {1} is off it does nothing and its changes to the game are undone. "
                .. "It stays off the next time the game starts, until you switch it on again.", name)
            if mod.ownScreen then body = body .. " " .. t("hub.switchEntry", "Its main-menu entry goes away the next time the menu opens.") end
            val = onOff(mod.enabled) .. "      " .. t("hub.hintSwitch", "(Confirm: switch)")
        else
            body = t("hub.entryHelp", "{1} has an entry of its own in the main menu: {2}.", name, kit.menu.title(mod.ownScreen))
        end
    elseif r.kind == "section" then
        name, sub = r.mod.config:text(r.item, "label"), r.mod:displayName()
    elseif r.kind == "item" then
        local item, cfg = r.item, r.mod.config
        name = cfg:text(item, "label")
        sub = r.mod:displayName() .. (item.section and ("  /  " .. section(r.mod, item.section)) or "")
        body = (cfg:text(item, "help") or "") .. (item.note and ("\n" .. item.note) or "")
        if item.type == "action" then
            val = t("hub.hintRun", "Confirm: run")
        elseif item.type == "toggle" then
            val = cfg:display(item) .. "      " .. t("hub.hintSwitch", "(Confirm: switch)")
        else
            val = "<  " .. cfg:display(item) .. "  >      " .. t("hub.hintChange", "(Left / Right: change)")
            if item.default ~= nil and cfg:get(item.key) ~= item.default then
                val = val .. "\n" .. t("hub.default", "Default: {1}", cfg:format(item, item.default))
            end
        end
    else
        name = t("hub.noPlugins", "No plugins installed")
        body = t("hub.noPluginsHelp", "Plugins are folders in ue4ss\\Mods with a moghub.lua file. See the MogHub page on Nexus Mods.")
    end
    d.name:SetTitle(FText(name))
    u.set(d.sub, sub)
    u.set(d.body, body)
    u.set(d.value, val)
end

local function build(host, u)
    local L = list.attach(host, u, { window = { WINDOW_W, WINDOW_H }, list = { LIST_W, LIST_H } })
    local body = u.new("HorizontalBox")
    L:setContent(body)
    local column = u.new("VerticalBox")
    body:AddChildToHorizontalBox(column)
    column:AddChildToVerticalBox(u.spacer(26))
    L:takeList(column)
    body:AddChildToHorizontalBox(u.sized(nil, 40))
    local detail = u.new("VerticalBox")
    body:AddChildToHorizontalBox(u.sized(detail, DETAIL_W, LIST_H))
    detail:AddChildToVerticalBox(u.spacer(26))
    local d = {}
    d.name = u.heading("")
    detail:AddChildToVerticalBox(d.name)
    d.sub = u.text("", kit.ui.GREY)
    detail:AddChildToVerticalBox(d.sub):SetPadding({ Left = 4, Top = 4, Right = 0, Bottom = 10 })
    local inner = u.new("VerticalBox")
    d.body = u.text("")
    pcall(function() d.body:SetAutoWrapText(true) end)
    inner:AddChildToVerticalBox(u.sized(d.body, DETAIL_W - 40))
    inner:AddChildToVerticalBox(u.spacer(18))
    d.value = u.text("", kit.ui.GOLD)
    inner:AddChildToVerticalBox(d.value)
    detail:AddChildToVerticalBox(u.panel(inner))
    view = { L = L, u = u, detail = d }
end

local function refresh(focus)
    buildRows()
    view.L:setRows(#rows, label)
    show(math.min(focus or shown or 1, #rows))
end

---------------------------------------------------------------------------------------------------
-- Input
---------------------------------------------------------------------------------------------------
local function change(i, dir, isConfirm)
    local r = rows[i]
    if not r then return end
    if (r.kind == "plugin" and not isConfirm) or r.kind == "switch" then
        local mod = r.mod
        kit.setEnabled(mod, not mod.enabled)
        kit.notice.show(mod.enabled and t("hub.noticeOn", "{1} on", mod:displayName()) or t("hub.noticeOff", "{1} off", mod:displayName()),
            mod.enabled and "on" or "off")
        refresh(i)                                        -- its settings come and go with it
    elseif r.kind == "plugin" then
        expanded[r.mod.id] = not expanded[r.mod.id] or nil
        refresh(i)
    elseif r.kind == "item" then
        local item, cfg = r.item, r.mod.config
        if item.type == "action" then
            if isConfirm and item.run then
                local ok = kit.guarded(r.mod, "action " .. item.label, item.run)
                if ok and item.done then kit.notice.show(cfg:text(item, "done"), "on") end
            end
        elseif item.type == "toggle" or item.type == "number" or item.type == "choice" then
            cfg:step(item, dir, isConfirm)
        end
        show(i)
    end
end

---------------------------------------------------------------------------------------------------
-- Screen
---------------------------------------------------------------------------------------------------
local screen = {
    title = "Mods",                                       -- hub.title in MogHub's lang files
    opened = function(host, u)
        view, shown = nil, nil
        if #kit.plugins == 1 then expanded[kit.plugins[1].id] = true end
        build(host, u)
        -- on the title screen there's no main-menu page header: the window's own title names the screen
        if kit.menu.open and kit.menu.open.name == kit.menu.titleHost and view.L.title then
            pcall(function()
                view.L.title:SetVisibility(4)
                view.L.title:SetText(FText(t("hub.heading", "MODS")))
            end)
        end
        refresh(1)
    end,
    closed = function() view = nil end,
    confirm = function()
        local i = view and (view.L.focused or shown)
        if i then change(i, 1, true) end
    end,
    poll = function()
        if not view then return end
        local focused = view.L:poll(function(i, e)
            local r = rows[i]
            if not r then return end
            list.indent(e, (r.kind == "plugin" or r.kind == "empty") and 0 or NEST)
            local text, color = value(r)
            list.setValue(e, text, color)
            if e.title and e.kind ~= r.kind then
                e.kind = r.kind
                kit.ui.paint(e.title, r.kind == "section" and kit.ui.GREY or kit.ui.WHITE)
            end
        end)
        if focused and focused ~= shown then show(focused) end
        local dir = horizontal()
        if dir ~= 0 and focused then
            local r = rows[focused]
            if r and (r.kind == "item" or r.kind == "plugin") then change(focused, dir, false); view.L:refresh() end
        end
    end,
}

function M.start()
    kit.menu.register(nil, screen, kit.menu.HUB_TAG)
end

-- values changed elsewhere (hotkeys, the ini file) show up while the screen is open
function M.changed()
    if view and shown then show(shown); view.L:refresh() end
end

return M
