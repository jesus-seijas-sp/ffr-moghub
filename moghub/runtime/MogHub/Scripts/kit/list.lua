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
local extras = {}          -- entry widget address -> its extras (see List:extra)

-- finds the Help layout's parts; `layout` sizes: { window = {w, h}, list = {w, h} }
function M.attach(host, u, layout)
    local root = host.WidgetTree.RootWidget
    local find = u.find
    local L = setmetatable({ host = host, u = u, n = 0, textures = {}, queued = {}, queue = {} }, List)
    L.box, L.title, L.gap = find(root, "CPP_CommonSizeBox_0"), find(root, "Text_Title"), find(root, "Spacer_101")
    L.slot, L.listBox, L.view = find(root, "NamedSlot_93"), find(root, "SizeBox_0"), find(root, "CmnListView")
    L.helpList = find(root, "WBP_HelpList")
    assert(L.box and L.slot and L.listBox and L.view and L.helpList, "the Help layout changed: cannot build the screen")
    layout = layout or {}
    L.leadSize, L.rowBuilt, L.release = layout.lead, layout.row, layout.release
    if layout.window then L.box:SetWidthOverride(layout.window[1]); L.box:SetHeightOverride(layout.window[2]) end
    if layout.list then L.listBox:SetWidthOverride(layout.list[1]); L.listBox:SetHeightOverride(layout.list[2]) end
    if L.title then L.title:SetVisibility(1) end         -- the page header already names the screen
    if L.gap then L.gap:SetVisibility(1) end
    M.takeKeys(host, L.helpList)
    return L
end

-- The list's navigator (WBP_ListViewMenu) moves the cursor JumpShiftAdd rows (5) on Left / Right: screens use those
-- keys themselves (the Mods screen changes values, the Bestiary pages forms), so the jump is 0 while one of them owns
-- the list, and the game's value comes back when it closes (the title screen borrows the game's own Help screen).
local jumps = {}           -- host full name -> { menu, value }
function M.takeKeys(host, helpList)
    pcall(function()
        local key = host:GetFullName()
        local pm = helpList:GetPathMenu()
        if not jumps[key] then jumps[key] = { menu = pm, value = pm.JumpShiftAdd } end
        if pm.JumpShiftAdd ~= 0 then pm.JumpShiftAdd = 0 end
    end)
end
function M.giveKeys(hostName)
    local j = jumps[hostName]
    if not j then return end
    jumps[hostName] = nil
    pcall(function() if valid(j.menu) then j.menu.JumpShiftAdd = j.value end end)
end

-- puts `content` in the window, with the list inside it where the screen wants: content must hold L.listBox
-- (add it with L:takeList(parent) first)
-- Another mod's page taken out of the window (FFR Bestiary's, in the same pooled Help layout) is kept in a hidden box
-- inside ours. Left alone, nothing refers to it: the garbage collector frees it at the next save point or map change,
-- FFR Bestiary puts the freed page back in the window, and the game crashes (in SetContent). Putting it back takes it
-- out of the box by itself.
local mine, hold = {}, nil  -- full names of the pages MogHub put in a window; the box, moved into each of them
function List:setContent(content)
    local prev
    pcall(function() prev = self.slot:GetContent() end)
    self.slot:SetContent(content)
    local ok, err = pcall(function()
        mine[content:GetFullName()] = true
        if not valid(hold) then hold = self.u.new("VerticalBox"); hold:SetVisibility(1) end   -- Collapsed
        content:AddChild(hold)
        if valid(prev) and not mine[prev:GetFullName()] and prev:GetAddress() ~= self.listBox:GetAddress() then
            kit.trace("list: another mod's page kept: %s", prev:GetFullName())
            hold:AddChild(prev)
        end
    end)
    if not ok then kit.trace("list: keeping the window's page: %s", tostring(err)) end
end
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
    kit.trace("list: setRows %d", n)
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
    kit.trace("list: items %d", #items)
    if self.view:GetNumItems() ~= #items then pcall(function() self.view:SetListItems(items) end) end
    pcall(function() self.view:RequestRefresh() end)
    kit.trace("list: rows set")
    for _, e in pairs(extras) do if e.owner == self then e.shown = nil end end   -- every row redraws its text
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

-- Extras on each entry widget, kept per widget, not per list: the game pools the widgets, so the same row widget comes
-- back when a screen is built again (the Mods screen on every visit) and can serve another screen's list. The list
-- using a row owns it; a list taking a row over clears what the previous one left there (its value, indent, lead,
-- its own widgets, through layout.release).

local function base(u, w)
    local button = w.WidgetTree.RootWidget              -- WBP_LeftLineButton_C
    local overlay = valid(button) and u.find(button.WidgetTree.RootWidget, "Overlay_0")
    if not overlay then return nil end
    local tree = button.WidgetTree
    -- the indent pads the button's own content (bar, background, text): the list resets the entry's outer padding
    -- whenever it reuses a row while scrolling
    local e = { right = u.new("HorizontalBox", tree), value = u.text("", nil, tree), indentSlot = overlay.Slot,
                tree = tree, built = {}, custom = {}, overlay = overlay, widget = w, widgetName = w:GetFullName() }
    pcall(function() e.value:SetJustification(2) end)    -- right
    e.right:AddChildToHorizontalBox(e.value):SetVerticalAlignment(2)
    local s = overlay:AddChildToOverlay(e.right)
    s:SetHorizontalAlignment(3); s:SetVerticalAlignment(2)
    s:SetPadding({ Left = 0, Top = 0, Right = 24, Bottom = 0 })
    e.inner = button.WidgetTree.RootWidget
    e.title = u.find(e.inner, "Text_Title")
    e.scale = u.find(e.inner, "ScaleBox_0")
    e.titleAlign = 1                                     -- Left, unless the game's own slot says otherwise
    pcall(function()
        if e.scale:GetContent():GetAddress() == e.title:GetAddress() then e.titleAlign = e.title.Slot.HorizontalAlignment end
    end)
    return e
end

local function same(a, b)
    local ok, r = pcall(function() return a:GetAddress() == b:GetAddress() end)
    return ok and r
end

-- Another mod's boxes on the row (the game's own Overlay_0 holds an Image and the button, never a HorizontalBox):
-- hidden while the row is ours, shown again when we give it back.
local function hideForeign(e)
    e.foreign = e.foreign or {}
    pcall(function()
        for i = 0, e.overlay:GetChildrenCount() - 1 do
            local x = e.overlay:GetChildAt(i)
            if not same(x, e.right) and x:GetClass():GetFName():ToString() == "HorizontalBox" then
                local key = x:GetAddress()
                if not e.foreign[key] then e.foreign[key] = { w = x, vis = x:GetVisibility() } end
                if x:GetVisibility() ~= 1 then x:SetVisibility(1) end
            end
        end
    end)
end

-- the title as the ScaleBox's own content, as the game has it
local function titleHome(e)
    if not (e.scale and e.title) then return end
    pcall(function()
        if not same(e.scale:GetContent(), e.title) then
            local slot = e.scale:SetContent(e.title)
            pcall(function() slot:SetHorizontalAlignment(e.titleAlign) end)
        end
    end)
end

-- The rows as the game made them, for whoever uses the pooled widgets next (FFR Bestiary uses the same Help layout
-- and the same rows): our extras hidden, no indent, the title back as the ScaleBox's own content.
local function restore(e)
    pcall(function() e.right:SetVisibility(1) end)
    for key, f in pairs(e.foreign or {}) do
        pcall(function() f.w:SetVisibility(f.vis) end)
        e.foreign[key] = nil
    end
    M.indent(e, 0)
    titleHome(e)
end

-- Ours again: extras shown, and the title back in our [lead][title] line if another mod moved it.
local function reclaim(e)
    hideForeign(e)
    pcall(function() e.right:SetVisibility(4) end)
    if e.line and e.scale and e.title then
        pcall(function()
            if not same(e.scale:GetContent(), e.line) then
                local slot = e.scale:SetContent(e.line)
                pcall(function() slot:SetHorizontalAlignment(1) end)
                e.line:AddChildToHorizontalBox(e.title):SetVerticalAlignment(2)
            end
        end)
    else
        titleHome(e)                                     -- no lead: the title is the ScaleBox's own content
    end
end

-- The row widget is still the one the extras were made for. A trip to another map can free the list's row widgets:
-- touching their old extras then crashed the game (UE4SS reads a freed widget before any pcall can help), and a new
-- widget can come back at a freed one's address.
local function alive(e)
    local ok, same = pcall(function() return valid(e.widget) and e.widget:GetFullName() == e.widgetName end)
    return ok and same
end

-- a screen closed: every row it used goes back to the game's own state
function M.releaseAll()
    for key, e in pairs(extras) do
        if not alive(e) then extras[key] = nil; kit.trace("list: a freed row forgotten")
        elseif e.owner then
            if e.owner.release then pcall(e.owner.release, e) end
            for _, x in ipairs(e.custom) do pcall(function() x:SetVisibility(1) end) end
            restore(e)
            e.owner, e.shown, e.row = nil, nil, nil
        end
    end
end

-- [lead][title] in the title's ScaleBox. Every row stays one height (the list assumes it): the lead box is `size`
-- tall on every row, and 0 wide on rows without a lead
local function addLead(u, w, e, size)
    local scale = e.scale
    if not (scale and e.title) then return end
    local line = u.new("HorizontalBox", w.WidgetTree)
    e.line = line
    local slot = scale:SetContent(line)
    pcall(function() slot:SetHorizontalAlignment(1) end)
    e.lead = u.image(nil, size, w.WidgetTree)
    e.leadBox = u.sized(e.lead, 0, size, w.WidgetTree)
    e.leadSlot = line:AddChildToHorizontalBox(e.leadBox)
    e.leadSlot:SetVerticalAlignment(2)
    line:AddChildToHorizontalBox(e.title):SetVerticalAlignment(2)
    e.leadSize = size
end

function List:extra(w)
    local key = w:GetAddress()
    local e = extras[key]
    if e and not (alive(e) and valid(e.value)) then extras[key], e = nil, nil end
    if not e then
        kit.trace("list: extras for a new row widget")
        e = base(self.u, w)
        if not e then return nil end
        extras[key] = e
    end
    if e.owner == self then return e end
    -- taking the row over
    kit.trace("list: row taken over (lead %s, row widgets %s)", tostring(self.leadSize), tostring(self.rowBuilt ~= nil))
    local prev = e.owner
    if prev and prev.release then pcall(prev.release, e) end
    for _, x in ipairs(e.custom) do pcall(function() x:SetVisibility(1) end) end
    e.owner, e.shown, e.row = self, nil, nil
    reclaim(e)
    M.indent(e, 0)
    M.setValue(e, "", nil)
    if self.leadSize and not e.lead then addLead(self.u, w, e, self.leadSize); kit.trace("list: lead added") end
    if e.lead then M.lead(e, false) end
    if self.rowBuilt then
        local mine = e.built[self.rowBuilt]
        if not mine then
            -- the widgets the screen adds to e.right are remembered, to hide them when another list takes the row
            local before = e.right:GetChildrenCount()
            kit.trace("list: row widgets")
            local ok, err = pcall(self.rowBuilt, e, self.u, e.tree)
            if not ok then kit.logOnce("MogHub", "list row", err) end
            mine = {}
            for i = before, e.right:GetChildrenCount() - 1 do
                local x = e.right:GetChildAt(i)
                mine[#mine + 1] = x
                e.custom[#e.custom + 1] = x
            end
            e.built[self.rowBuilt] = mine
        end
        for _, x in ipairs(mine) do pcall(function() x:SetVisibility(4) end) end
    end
    kit.trace("list: row ready")
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
