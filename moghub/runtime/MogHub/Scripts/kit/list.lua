-- The Help layout's native list, reused for any list of rows: the game draws the rows, the cursor, the scrollbar
-- and handles Up / Down; the screen gives each row its text and optional extras.
--   local L = kit.list.attach(host, ui, { window = { w, h }, list = { w, h }, lead = 40, row = fn(e, ui, tree) })
--   L:setRows(n, function(i) return label end)   -- whenever the rows change
--   L:poll(function(i, e) ... end)                -- every tick: decorates the visible rows, returns the focused row
-- Each row's extras `e`: e.title (its text), e.value (a right-aligned text), e.right (the HorizontalBox holding
-- e.value, for more widgets: layout.row(e, ui, tree) adds them once per row widget), and with layout.lead an image
-- before the title (kit.list.lead). The list recycles row widgets while scrolling: decorate every visible row on
-- every tick.
-- Technique from FFR Bestiary by Law19902 (MIT).
local M = {}
local kit, valid

function M.init(k) kit, valid = k, k.valid end

local List = {}
List.__index = List

-- finds the Help layout's parts; `layout` sizes: { window = {w, h}, list = {w, h} }
function M.attach(host, u, layout)
    local root = host.WidgetTree.RootWidget
    local find = u.find
    local L = setmetatable({ host = host, u = u, extras = {}, n = 0, textures = {}, queued = {}, queue = {} }, List)
    L.box, L.title, L.gap = find(root, "CPP_CommonSizeBox_0"), find(root, "Text_Title"), find(root, "Spacer_101")
    L.slot, L.listBox, L.view = find(root, "NamedSlot_93"), find(root, "SizeBox_0"), find(root, "CmnListView")
    L.helpList = find(root, "WBP_HelpList")
    assert(L.box and L.slot and L.listBox and L.view and L.helpList, "the Help layout changed: cannot build the screen")
    layout = layout or {}
    L.leadSize, L.rowBuilt = layout.lead, layout.row
    if layout.window then L.box:SetWidthOverride(layout.window[1]); L.box:SetHeightOverride(layout.window[2]) end
    if layout.list then L.listBox:SetWidthOverride(layout.list[1]); L.listBox:SetHeightOverride(layout.list[2]) end
    if L.title then L.title:SetVisibility(1) end         -- the page header already names the screen
    if L.gap then L.gap:SetVisibility(1) end
    return L
end

-- puts `content` in the window, with the list inside it where the screen wants: content must hold L.listBox
-- (add it with L:takeList(parent) first)
function List:setContent(content) self.slot:SetContent(content) end
function List:takeList(parent, fill)
    local add = parent.AddChildToVerticalBox and "AddChildToVerticalBox" or "AddChildToHorizontalBox"
    local s = parent[add](parent, self.listBox)
    if fill then pcall(function() s:SetSize({ SizeRule = 1, Value = 1 }) end) end
    -- holds an image of each texture loaded with L:texture, so it stays alive while its rows are off screen
    self.keep = self.u.new("VerticalBox")
    self.keep:SetVisibility(1)
    parent[add](parent, self.keep)
    return s
end

-- a texture for row decorations: at once when loaded already, otherwise nil and queued (L:poll loads two per tick,
-- so scrolling stays smooth); ask again on the next tick
function List:texture(path)
    local t = self.textures[path]
    if t and valid(t) then return t end
    if not self.queued[path] then self.queued[path] = true; self.queue[#self.queue + 1] = path end
end

function List:loadQueued()
    for _ = 1, 2 do
        local path = table.remove(self.queue, 1)
        if not path then break end
        self.queued[path] = nil
        local tex = kit.game.load(path)
        if tex then
            self.textures[path] = tex
            if self.keep then pcall(function() self.keep:AddChildToVerticalBox(self.u.image(tex)) end) end
        end
    end
end

-- The list's navigator owns the list items: SetChildrenCount makes one per row (keeping those it has), so the
-- count its cursor moves through always matches ours. Being the game's, the items are never collected under us.
function List:setRows(n, label)
    self.label = label
    self.pathMenu = valid(self.pathMenu) and self.pathMenu or self.helpList:GetPathMenu()
    self.pathMenu:SetChildrenCount(n, true)
    local items = {}
    local arr = self.pathMenu.ListItems
    for i = 1, #arr do
        local it = arr[i]
        if type(it) == "userdata" and not it.IsValid then it = it:get() end
        items[i] = it
    end
    for i = 1, n do
        local item = items[i]
        if valid(item) then
            item.ItemIndex = i - 1
            item.TutorialData.Name = FText(label(i) or "")
        end
    end
    self.n = n
    if self.view:GetNumItems() ~= #items then pcall(function() self.view:SetListItems(items) end) end
    pcall(function() self.view:RequestRefresh() end)
    for _, e in pairs(self.extras) do e.shown = nil end  -- every row redraws its text
end

function List:refresh() pcall(function() self.view:RequestRefresh() end) end

-- the entry widgets on screen (the list recycles them while scrolling)
function List:entries()
    local out = {}
    local ok, arr = pcall(function() return self.view:GetDisplayedEntryWidgets() end)
    if ok and arr then
        if type(arr) == "table" then
            for _, v in ipairs(arr) do
                local okG, w = pcall(function() return v:get() end)
                w = okG and w or v
                if valid(w) then out[#out + 1] = w end
            end
        else
            pcall(function() arr:ForEach(function(_, v) local w = v:get(); if valid(w) then out[#out + 1] = w end end) end)
        end
    end
    return out
end

local entryLib
function List:rowOf(w)
    entryLib = valid(entryLib) and entryLib or StaticFindObject("/Script/UMG.Default__UserObjectListEntryLibrary")
    local item = entryLib:GetListItemObject(w)
    if valid(item) then return item.ItemIndex + 1 end
end

-- extras added once to each (recycled) entry widget: a right-aligned box with a value text, an indent for nested
-- rows, and (layout.lead) an image before the title
function List:extra(w)
    local key = w:GetAddress()
    local e = self.extras[key]
    if e and valid(e.value) then return e end
    local u = self.u
    local button = w.WidgetTree.RootWidget              -- WBP_LeftLineButton_C
    local overlay = valid(button) and u.find(button.WidgetTree.RootWidget, "Overlay_0")
    if not overlay then return nil end
    local tree = button.WidgetTree
    -- the indent pads the button's own content (bar, background, text): the list resets the entry's outer padding
    -- whenever it reuses a row while scrolling
    e = { right = u.new("HorizontalBox", tree), value = u.text("", nil, tree), indentSlot = overlay.Slot }
    pcall(function() e.value:SetJustification(2) end)    -- right
    e.right:AddChildToHorizontalBox(e.value):SetVerticalAlignment(2)
    local s = overlay:AddChildToOverlay(e.right)
    s:SetHorizontalAlignment(3); s:SetVerticalAlignment(2)
    s:SetPadding({ Left = 0, Top = 0, Right = 24, Bottom = 0 })
    local inner = button.WidgetTree.RootWidget
    e.title = u.find(inner, "Text_Title")
    -- [lead][title] in the title's ScaleBox. Every row stays one height (the list assumes it): the lead box is
    -- `lead` tall on every row, and 0 wide on rows without a lead
    local scale = self.leadSize and u.find(inner, "ScaleBox_0")
    if scale and e.title then
        local line = u.new("HorizontalBox", w.WidgetTree)
        local slot = scale:SetContent(line)
        pcall(function() slot:SetHorizontalAlignment(1) end)
        local size = self.leadSize
        e.lead = u.image(nil, size, w.WidgetTree)
        e.leadBox = u.sized(e.lead, 0, size, w.WidgetTree)
        e.leadSlot = line:AddChildToHorizontalBox(e.leadBox)
        e.leadSlot:SetVerticalAlignment(2)
        line:AddChildToHorizontalBox(e.title):SetVerticalAlignment(2)
        e.leadSize = size
    end
    if self.rowBuilt then
        local ok, err = pcall(self.rowBuilt, e, u, tree)
        if not ok then kit.logOnce("MogHub", "list row", err) end
    end
    self.extras[key] = e
    return e
end

-- decorate(i, extra) for each visible row (extra.title, extra.value, extra:indent(px)); returns the focused row
function List:poll(decorate)
    pcall(self.loadQueued, self)
    local focused
    for _, w in ipairs(self:entries()) do
        pcall(function()
            local i = self:rowOf(w)
            if not i then return end
            local e = self:extra(w)
            if e then
                if e.shown ~= i and e.title and self.label then
                    e.shown = i
                    e.title:SetText(FText(self.label(i) or ""))
                end
                if decorate then decorate(i, e) end
            end
            if w:HasFocusedDescendants() then focused = i end
        end)
    end
    -- after the list scrolls to the cursor it can leave its last row empty until the next input: refresh once the
    -- cursor rests on a new row
    if focused and focused ~= self.refreshedFor then
        self.refreshedFor = focused
        self:refresh()
    end
    if focused then self.focused = focused end
    return self.focused
end

function M.indent(e, px)
    if e.indent ~= px and e.indentSlot then
        e.indent = px
        pcall(function() e.indentSlot:SetPadding({ Left = px, Top = 0, Right = 0, Bottom = 0 }) end)
    end
end

-- a row's lead image: `on` keeps its space (so names line up), `texture` shows in it (nil: the space stays empty)
function M.lead(e, on, texture)
    if not e.lead then return end
    if e.leadOn ~= on then
        e.leadOn = on
        e.leadBox:SetWidthOverride(on and e.leadSize or 0)
        e.leadSlot:SetPadding({ Left = 0, Top = 0, Right = on and 10 or 0, Bottom = 0 })
    end
    if texture and e.leadTex ~= texture then
        e.lead:SetBrushFromTexture(texture, false)
        e.lead:SetDesiredSizeOverride({ X = e.leadSize, Y = e.leadSize })
        e.leadTex = texture
    end
    e.lead:SetVisibility((on and texture) and 4 or 2)   -- SelfHitTestInvisible / Hidden (keeps its space)
end

function M.setValue(e, text, color)
    if e.valueText ~= text then
        e.valueText = text
        e.value:SetText(FText(text or ""))
    end
    if e.valueColor ~= color then
        e.valueColor = color
        kit.ui.paint(e.value, color)
    end
end

return M
