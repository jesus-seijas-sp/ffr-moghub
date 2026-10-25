-- On-screen notices: a short message in a box near the top of the screen. kit.notice.show("Turbo: x2", "on")
local M = {}
local kit, valid
local state = { serial = 0, shown = 0 }
local COLORS = {
    on = { R = 0.5, G = 1.0, B = 0.6, A = 1.0 },
    off = { R = 0.85, G = 0.85, B = 0.85, A = 1.0 },
    warn = { R = 1.0, G = 0.8, B = 0.4, A = 1.0 },
}

function M.init(k)
    kit, valid = k, k.valid
    M.enabled = kit.config.kitBool("Notices", true)
end

local function make(class, outer, name)
    return StaticConstructObject(StaticFindObject("/Script/UMG." .. class), outer, FName(name))
end

local function widget()
    if valid(state.widget) and valid(state.text) then return state end
    local gi = FindFirstOf("GameInstance")
    if not valid(gi) then return nil end
    state.serial = state.serial + 1
    local base = "MogHub_Notice_" .. state.serial
    local w = make("UserWidget", gi, base)
    local tree = make("WidgetTree", w, base .. "_Tree")
    w.WidgetTree = tree
    local canvas = make("CanvasPanel", tree, base .. "_Canvas")
    tree.RootWidget = canvas
    local box = make("Border", tree, base .. "_Box")
    box:SetBrushColor({ R = 0.02, G = 0.05, B = 0.25, A = 0.85 })
    box:SetPadding({ Left = 18, Top = 10, Right = 18, Bottom = 10 })
    local slot = canvas:AddChildToCanvas(box)
    slot:SetAutoSize(true)
    slot:SetAnchors({ Minimum = { X = 0.5, Y = 0.15 }, Maximum = { X = 0.5, Y = 0.15 } })
    slot:SetAlignment({ X = 0.5, Y = 0.5 })
    local text = make("TextBlock", tree, base .. "_Text")
    local font = text.Font
    font.Size = 22
    text:SetFont(font)
    box:SetContent(text)
    state.widget, state.text = w, text
    return state
end

-- color: "on" (green), "off" (white), "warn" (amber); ms: how long it stays (default 1.8 s)
function M.show(msg, color, ms)
    kit.log("%s", msg)
    if not M.enabled then return end
    local ok, err = pcall(function()
        local n = widget()
        if not n then return end
        if not n.widget:IsInViewport() then n.widget:AddToViewport(1001) end
        n.text:SetText(FText(msg))
        n.text:SetColorAndOpacity({ SpecifiedColor = COLORS[color] or COLORS.off, ColorUseRule = 0 })
        n.widget:SetVisibility(3)                       -- HitTestInvisible
        n.shown = n.shown + 1
        local mine = n.shown
        kit.after(ms or 1800, function()
            if n.shown == mine and valid(n.widget) then n.widget:SetVisibility(1) end      -- Collapsed
        end, "notice", { loading = true })
    end)
    if not ok then kit.logOnce("MogHub", "notice", err) end
end

return M
