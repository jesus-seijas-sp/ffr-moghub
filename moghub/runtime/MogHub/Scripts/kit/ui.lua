-- Widget helpers for screens built inside the game's own layouts, so they look like the other menu pages: the
-- game's text style, headings, framed panels and key icons. Bind them to a host widget first:
--   local u = kit.ui.on(host)
--   local t = u.text("Hello"); local box = u.sized(t, 300); local h = u.heading("Section")
-- Adapted from FFR Bestiary by Law19902 (MIT).
local M = {}
local kit, valid, game

M.TEXT_STYLE = "/Game/UI/Common/Text/TextStyle/SystemText/BP_SystemTextStyle"
M.SUBHEAD = "/Game/UI/Common/Layout/Subhead/WBP_SystemSubhead"
M.WINDOW = "/Game/UI/Common/Window/WBP_Cmn_Window"
M.KEY_ICON = "/Game/UI/Common/KeyIcon/WBP_KeyIcon"
M.CHECK_ICON = "/Game/UI/Textures/Icon/menu/ICON_Quest_Check.ICON_Quest_Check"
M.ACTION = {
    decide = "/Game/Input/UI/Common/InputAction/IA_UI_Common_Decide.IA_UI_Common_Decide",
}
M.WHITE = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }
M.GREY = { R = 0.55, G = 0.58, B = 0.63, A = 1.0 }
M.DIM = { R = 0.42, G = 0.44, B = 0.48, A = 1.0 }
M.GOLD = { R = 1.0, G = 0.85, B = 0.45, A = 1.0 }
M.BLUE = { R = 0.55, G = 0.8, B = 1.0, A = 1.0 }

function M.init(k) kit, valid, game = k, k.valid, k.game end

-- depth-first search through a widget and the trees of the user widgets inside it
function M.walk(w, test, depth)
    depth = depth or 0
    if not valid(w) or depth > 16 then return nil end
    if test(w) then return w end
    local okTree, tree = pcall(function() return w.WidgetTree end)
    if okTree and valid(tree) and depth > 0 then return M.walk(tree.RootWidget, test, depth + 1) end
    local okN, n = pcall(function() return w:GetChildrenCount() end)
    if okN and n then
        for i = 0, n - 1 do
            local hit = M.walk(w:GetChildAt(i), test, depth + 1)
            if hit then return hit end
        end
    end
end
function M.find(w, name) return M.walk(w, function(x) return x:GetFName():ToString() == name end) end

-- a game widget from its class path, owned by the player
function M.create(path)
    local cls = game.class(path)
    if not valid(cls) then kit.logOnce("MogHub", "widget", "missing " .. path); return nil end
    local pc = game.playerController()
    return StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary"):Create(pc, cls, pc)
end

function M.paint(t, color) t:SetColorAndOpacity({ SpecifiedColor = color or M.WHITE, ColorUseRule = 0 }) end

-- screen pixels per UI design pixel (the UI is laid out for 1920x1080), e.g. to draw sprites at whole pixels
local vpScale
function M.viewportScale()
    if not vpScale then
        pcall(function()
            vpScale = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary"):GetViewportScale(game.playerController())
        end)
        if not vpScale or vpScale <= 0 then vpScale = nil; return 1 end
    end
    return vpScale
end

function M.on(host)
    local u = {}
    -- looked up per screen: after a return to the title the old ones can be gone
    local styleClass = game.class(M.TEXT_STYLE)
    local subheadClass = game.class(M.SUBHEAD)
    local checkTex

    function u.new(kind, outer)
        local module = kind:find("^Common") and "/Script/CommonUI." or (kind:find("^CPP_") and "/Script/mucha." or "/Script/UMG.")
        local o = StaticConstructObject(StaticFindObject(module .. kind), outer or host.WidgetTree)
        assert(valid(o), "cannot create " .. kind)
        return o
    end

    -- body text in the game's SystemText style
    function u.text(value, color, outer)
        local t = u.new("CommonTextBlock", outer)
        if valid(styleClass) then pcall(function() t:SetStyle(styleClass) end) end
        t:SetText(FText(value or ""))
        M.paint(t, color)
        return t
    end

    function u.set(t, value, color)
        t:SetText(FText(value or ""))
        if color then M.paint(t, color) end
    end

    -- a heading with the game's underline (WBP_SystemSubhead); change it with h:SetTitle(FText(...))
    function u.heading(value)
        local pc = game.playerController()
        local h = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary"):Create(pc, subheadClass, pc)
        h:SetTitle(FText(value or ""))
        return h
    end

    function u.sized(content, w, h, outer)
        local b = u.new("SizeBox", outer)
        if w then b:SetWidthOverride(w) end
        if h then b:SetHeightOverride(h) end
        if content then b:SetContent(content) end
        return b
    end

    function u.spacer(h, w)
        local s = u.new("Spacer")
        s:SetSize({ X = w or 1, Y = h or 1 })
        return s
    end

    -- an image of `size` design pixels (a number, or { w, h }); `texture` may be nil (set it later with
    -- img:SetBrushFromTexture(tex, false))
    function u.image(texture, size, outer)
        local img = u.new("Image", outer)
        if valid(texture) then img:SetBrushFromTexture(texture, false) end
        if size then
            local w, h = size, size
            if type(size) == "table" then w, h = size[1], size[2] end
            img:SetDesiredSizeOverride({ X = w, Y = h })
        end
        return img
    end

    -- the Quests page's check mark
    function u.check(size, outer)
        if not valid(checkTex) then checkTex = game.load(M.CHECK_ICON) end
        return u.image(checkTex, size, outer)
    end

    -- `content` shrunk to fit its box when it would not (never enlarged), kept at the top left
    function u.fit(content)
        local f = u.new("ScaleBox")
        pcall(function() f:SetStretch(2); f:SetStretchDirection(1) end)   -- ScaleToFit, DownOnly
        local slot = f:SetContent(content)
        pcall(function() slot:SetHorizontalAlignment(1); slot:SetVerticalAlignment(1) end)
        return f
    end

    -- the glyph of an input action for the device in use (keyboard key or pad button)
    function u.keyIcon(action)
        local w = M.create(M.KEY_ICON)
        if w then pcall(function() w:SetInputAction(game.load(M.ACTION[action] or action)) end) end
        return w
    end

    -- a framed panel like the Equipment page's sections (WBP_Cmn_Window); the bare content if it's missing
    function u.panel(content, pad)
        pad = pad or 16
        local box = u.new("VerticalBox")
        box:AddChildToVerticalBox(content):SetPadding({ Left = pad, Top = 8, Right = pad, Bottom = 8 })
        local w = M.create(M.WINDOW)
        if not w then return box end
        local ok = pcall(function() M.find(w.WidgetTree.RootWidget, "Window_Content"):SetContent(box) end)
        return ok and w or box
    end

    -- "Label    value" line added to a VerticalBox; returns the value text
    function u.row(parent, label, labelW, valueW)
        local line = u.new("HorizontalBox")
        line:AddChildToHorizontalBox(u.sized(u.text(label, M.GREY), labelW or 230))
        local v = u.text("")
        pcall(function() v:SetAutoWrapText(true) end)
        line:AddChildToHorizontalBox(u.sized(v, valueW))
        parent:AddChildToVerticalBox(line):SetPadding({ Left = 0, Top = 3, Right = 0, Bottom = 3 })
        return v
    end

    -- "Label    [text][widgets]" line: returns the value text and a HorizontalBox for the game's own icon widgets
    -- (show one or the other)
    function u.widgetRow(parent, label, labelW)
        local line = u.new("HorizontalBox")
        line:AddChildToHorizontalBox(u.sized(u.text(label, M.GREY), labelW or 230))
        local v = u.text("")
        line:AddChildToHorizontalBox(v):SetVerticalAlignment(2)
        local box = u.new("HorizontalBox")
        line:AddChildToHorizontalBox(box):SetVerticalAlignment(2)
        parent:AddChildToVerticalBox(line):SetPadding({ Left = 0, Top = 3, Right = 0, Bottom = 3 })
        return v, box
    end

    u.find = M.find
    u.create = M.create
    u.paint = M.paint
    u.viewportScale = M.viewportScale
    return u
end

return M
