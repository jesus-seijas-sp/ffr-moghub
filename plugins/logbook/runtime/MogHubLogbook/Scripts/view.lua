-- The Logbook screen, in the game's Help layout like MogHub's Mods screen: the list on the left (a summary, then
-- Areas, Side quests, Colosseum and Tablet shards, each opening with confirm), the detail of the row under the cursor
-- on the right. Everything shown is read live (progress.lua) and refreshed every few seconds while the screen is open.
local M = {}
local data = require("logbook_data")
local progress = require("progress")
local list = kit.list
local ui = kit.ui

local WINDOW_W, WINDOW_H = 1760, 830
local LIST_W, LIST_H = 820, 690
local DETAIL_W = 720
local COLUMN_LINES = 15        -- a longer detail list is shown in two columns
local NEST = 34
local REFRESH_POLLS = 60       -- the screen polls every 50 ms: read the game again about every 3 s

M.showContents = true          -- unopened chests and item spots show what they hold (setting)
M.showLocked = true            -- quests not available yet show their name (setting)

local rows, expanded = {}, {}
local view, shown, polls, tot = nil, nil, 0, nil

local function t(key, default, ...) return mod:t(key, default, ...) end
local function text(ref) return ref and kit.game.text(ref[1], ref[2]) or nil end
local function clean(s) return (s or ""):gsub("\r?\n", " ") end
local CHECK, OPEN = "●", "○"           -- (the game font has no ✔)

---------------------------------------------------------------------------------------------------
-- Names and totals
---------------------------------------------------------------------------------------------------
local function areaName(a) return text(a.name) or a.key end
local function regionName(r) return text(data.regions[r] or data.regions[tostring(r)]) or "" end

-- what a chest or item spot holds
local function contents(c)
    if c.gil and c.gil > 0 then return t("gil", "{1} Gil", c.gil) end
    local name = kit.game.itemName(c.item) or ("#" .. c.item)
    if (c.num or 1) > 1 then name = name .. " x" .. c.num end
    return name
end

local function totals()
    if tot then return tot end
    tot = { chests = 0, open = 0, spots = 0, spotsOpen = 0, shards = 0, shardsOpen = 0, found = 0, all = 0, areas = 0,
            visited = 0, quests = #data.quests, done = 0, active = 0, battles = #data.colosseum, cleared = 0, wins = 0,
            rewards = #data.shards.rewards, claimed = 0 }
    for _, a in ipairs(data.areas) do
        local r = progress.treasure(a)
        for _, k in ipairs({ "open", "spotsOpen", "shardsOpen", "spots", "shards", "found", "all" }) do tot[k] = tot[k] + r[k] end
        tot.chests = tot.chests + r.total
        if not a.field then
            tot.areas = tot.areas + 1
            if progress.visited(a) then tot.visited = tot.visited + 1 end
        end
    end
    for _, q in ipairs(data.quests) do
        local st = progress.quest(q).state
        if st == "done" then tot.done = tot.done + 1 elseif st == "active" then tot.active = tot.active + 1 end
    end
    for _, c in ipairs(data.colosseum) do
        local s, wins = progress.colosseum(c)
        if s == "cleared" then tot.cleared = tot.cleared + 1 end
        tot.wins = tot.wins + (wins or 0)
    end
    for _, r in ipairs(data.shards.rewards) do if progress.shardReward(r) == "claimed" then tot.claimed = tot.claimed + 1 end end
    return tot
end

-- by heading name: islands sharing a name share a heading
local function regionTreasure(name)
    local found, all = 0, 0
    for _, a in ipairs(data.areas) do
        if regionName(a.region) == name then
            local r = progress.treasure(a)
            found, all = found + r.found, all + r.all
        end
    end
    return found, all
end

local function hasShards(a)
    for _, s in ipairs(a.spots) do if s.shard then return true end end
    return false
end

---------------------------------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------------------------------
local SECTIONS = {
    { id = "areas", label = function() return t("areas", "Areas") end },
    { id = "quests", label = function() return t("quests", "Side quests") end },
    { id = "colosseum", label = function() return t("colosseum", "Colosseum") end },
    { id = "shards", label = function() return t("shards", "Tablet shards") end },
}

local function regionRows(items, key, add)
    local lastName
    for _, it in ipairs(items) do
        local name = regionName(it.region)
        if name ~= lastName then
            rows[#rows + 1] = { kind = "region", region = key and it.region or nil, name = name }
            lastName = name
        end
        add(it)
    end
end

local function buildRows()
    rows = { { kind = "summary" } }
    for _, s in ipairs(SECTIONS) do
        rows[#rows + 1] = { kind = "section", section = s }
        if expanded[s.id] then
            if s.id == "areas" then
                regionRows(data.areas, true, function(a) rows[#rows + 1] = { kind = "area", area = a } end)
            elseif s.id == "quests" then
                regionRows(data.quests, false, function(q) rows[#rows + 1] = { kind = "quest", quest = q } end)
            elseif s.id == "colosseum" then
                for _, c in ipairs(data.colosseum) do rows[#rows + 1] = { kind = "battle", battle = c } end
            else
                rows[#rows + 1] = { kind = "region", name = t("shardSpots", "Where to find them") }
                for _, a in ipairs(data.areas) do
                    if hasShards(a) then rows[#rows + 1] = { kind = "shardArea", area = a } end
                end
                rows[#rows + 1] = { kind = "region", name = t("shardRewards", "The collector's rewards") }
                for _, r in ipairs(data.shards.rewards) do rows[#rows + 1] = { kind = "reward", reward = r } end
            end
        end
    end
end

local function questName(q, st)
    if st.state == "locked" and not M.showLocked then return "???" end
    return text(q.name) or ("#" .. q.id)
end

local function label(i)
    local r = rows[i]
    if not r then return "" end
    if r.kind == "summary" then return t("summary", "Summary") end
    if r.kind == "section" then return r.section.label() end
    if r.kind == "region" then return "- " .. r.name .. " -" end
    if r.kind == "area" or r.kind == "shardArea" then return areaName(r.area) end
    if r.kind == "quest" then return questName(r.quest, progress.quest(r.quest)) end
    if r.kind == "battle" then return text(r.battle.name) or ("#" .. r.battle.id) end
    if r.kind == "reward" then return t("shardCount", "{1} tablet shards", r.reward.num) end
    return ""
end

local STATE_TEXT = {
    done = function() return t("questDone", "Completed") end,
    available = function() return t("questAvailable", "Available") end,
    locked = function() return t("questLocked", "Not yet") end,
}

local function count(found, all, visited)
    if all == 0 then return "-", ui.DIM end
    return found .. " / " .. all, found == all and ui.GOLD or (visited and ui.WHITE or ui.DIM)
end

-- the value on the right of a row, and its colour
local function value(r)
    local W, G, D, Y = ui.WHITE, ui.GREY, ui.DIM, ui.GOLD
    if r.kind == "section" then
        local tot = totals()
        local id = r.section.id
        local txt = id == "areas" and (tot.found .. " / " .. tot.all)
            or id == "quests" and (tot.done .. " / " .. tot.quests)
            or id == "colosseum" and (tot.cleared .. " / " .. tot.battles)
            or (tot.shardsOpen .. " / " .. tot.shards)
        return (expanded[id] and "-  " or "+  ") .. txt, W
    end
    if r.kind == "region" and r.region then
        local f, n = regionTreasure(r.name)
        return f .. " / " .. n, G
    end
    if r.kind == "area" then
        local tr = progress.treasure(r.area)
        return count(tr.found, tr.all, progress.visited(r.area))
    end
    if r.kind == "shardArea" then
        local tr = progress.treasure(r.area)
        return count(tr.shardsOpen, tr.shards, progress.visited(r.area))
    end
    if r.kind == "quest" then
        local st = progress.quest(r.quest)
        if st.state == "active" then
            return st.stage and t("questStage", "Stage {1}/{2}", st.stage, #r.quest.stages) or t("questActive", "In progress"), W
        end
        return STATE_TEXT[st.state](), st.state == "done" and Y or (st.state == "available" and W or D)
    end
    if r.kind == "battle" then
        local s, wins = progress.colosseum(r.battle)
        if s == "cleared" then
            return (wins and wins > 1) and t("clearedTimes", "Cleared x{1}", wins) or t("cleared", "Cleared"), Y
        end
        if s == "open" then return t("lv", "Lv {1}", r.battle.level), W end
        return t("battleLocked", "Locked"), D
    end
    if r.kind == "reward" then
        local s = progress.shardReward(r.reward)
        if s == "claimed" then return CHECK, Y end
        if s == "next" then return t("next", "Next"), W end
        return "", D
    end
    return "", G
end

---------------------------------------------------------------------------------------------------
-- Detail panel
---------------------------------------------------------------------------------------------------
-- one line per chest or item spot: opened / not, and what it holds (??? while closed, with the setting off)
local function itemLines(lines, things, opened, filter)
    for k, c in ipairs(things) do
        if not filter or filter(c) then
            local what = (opened[k] or M.showContents) and contents(c) or "???"
            lines[#lines + 1] = (opened[k] and CHECK or OPEN) .. "  " .. what .. (c.trap and ("  " .. t("trap", "(trap)")) or "")
        end
    end
end

local function areaDetail(a, shardsOnly)
    local tr = progress.treasure(a)
    local lines = {}
    if shardsOnly then
        lines[1] = t("shardsHere", "Tablet shards here: {1} / {2}", tr.shardsOpen, tr.shards)
        itemLines(lines, a.spots, tr.spot, function(s) return s.shard end)
        return lines, ""
    end
    if tr.total > 0 then
        lines[#lines + 1] = t("chestsHeader", "Treasure chests: {1} / {2}", tr.open, tr.total)
        itemLines(lines, a.chests, tr.chest)
    end
    if #a.spots > 0 then
        if #lines > 0 then lines[#lines + 1] = "" end
        lines[#lines + 1] = t("spotsHeader", "Item spots: {1} / {2}", tr.spotsOpen + tr.shardsOpen, tr.spots + tr.shards)
        itemLines(lines, a.spots, tr.spot)
    end
    if #lines == 0 then return { t("noTreasure", "No treasure chests or item spots here.") }, "" end
    return lines, t("found", "Found: {1} / {2}", tr.found, tr.all)
end

local function setBody(lines)
    local left, right = lines, {}
    if #lines > COLUMN_LINES then
        local half = math.ceil(#lines / 2)
        left, right = {}, {}
        for k, line in ipairs(lines) do
            if k <= half then left[#left + 1] = line else right[#right + 1] = line end
        end
    end
    local d = view.detail
    view.u.set(d.body, table.concat(left, "\n"))
    view.u.set(d.body2, table.concat(right, "\n"))
    -- one column uses the whole width; the second shows only for a long list
    local two = #right > 0
    if d.two ~= two then
        d.two = two
        pcall(function()
            d.left:SetWidthOverride(two and d.colW or d.fullW)
            local vis = two and kit.game.enum.Visibility.SelfHitTestInvisible or kit.game.enum.Visibility.Collapsed
            d.gap:SetVisibility(vis)
            d.right:SetVisibility(vis)
        end)
    end
end

local function show(i)
    shown = i
    local r = rows[i]
    if not view or not r then return end
    local d = view.detail
    local name, sub, body, val = "", "", {}, ""
    if not progress.loaded() then
        name, body = t("title", "Logbook"), { t("noGame", "Load a game to see your progress.") }
    elseif r.kind == "summary" then
        local tot = totals()
        local ch = progress.chapter()
        local chName = text(data.chapters[ch] or data.chapters[tostring(ch)])
        name = t("title", "Logbook")
        sub = t("chapter", "Chapter {1}", ch) .. (chName and ("  " .. chName) or "")
        local joined, members = progress.party()
        body = {
            t("sumChests", "Treasure chests opened: {1} / {2}", tot.open, tot.chests),
            t("sumSpots", "Item spots found: {1} / {2}", tot.spotsOpen, tot.spots),
            t("sumShardSpots", "Tablet shards found: {1} / {2}", tot.shardsOpen, tot.shards),
            t("sumAreas", "Areas visited: {1} / {2}", tot.visited, tot.areas),
            "",
            t("sumQuests", "Side quests completed: {1} / {2}", tot.done, tot.quests)
                .. (tot.active > 0 and ("   " .. t("sumActive", "In progress: {1}", tot.active)) or ""),
            t("sumColosseum", "Colosseum battles cleared: {1} / {2}", tot.cleared, tot.battles)
                .. (tot.wins > 0 and ("   " .. t("sumWins", "Wins: {1}", tot.wins)) or ""),
            t("sumShards", "Tablet shards held: {1}   Rewards claimed: {2} / {3}", progress.shardsHeld(data.shards.item), tot.claimed, tot.rewards),
            "",
        }
        if joined then body[#body + 1] = t("sumParty", "Party members: {1} / {2}", joined, members) end
        if progress.visions() then body[#body + 1] = t("sumVisions", "Visions: {1}", progress.visions()) end
        if progress.encounters() then body[#body + 1] = t("sumEncounters", "Encounters: {1}", progress.encounters()) end
        val = t("hintOpen", "Confirm on a section: open / close")
    elseif r.kind == "section" then
        name = r.section.label()
        local help = {
            areas = t("areasHelp", "Every town, dungeon and island field with its treasure chests and item spots (the sparkling pickups): what you have found, and what each one holds."),
            quests = t("questsHelp", "Side quests by region: done, in progress (with the current goal), ready to take, or not available yet."),
            colosseum = t("colosseumHelp", "The Colosseum's rank battles: cleared (and how many times), open (with the recommended level) or still locked."),
            shards = t("shardsHelp", "Where the tablet shards are and which you have picked up, and what the collector gives for each number of shards handed over."),
        }
        body = { help[r.section.id] }
        val = expanded[r.section.id] and t("hintClose", "Confirm: close") or t("hintOpenOne", "Confirm: open")
    elseif r.kind == "region" then
        name = r.name
    elseif r.kind == "area" or r.kind == "shardArea" then
        local a = r.area
        name = areaName(a)
        sub = regionName(a.region) .. "   " .. (progress.visited(a) and t("visited", "Visited") or t("notVisited", "Not visited yet"))
        body, val = areaDetail(a, r.kind == "shardArea")
    elseif r.kind == "quest" then
        local q, st = r.quest, progress.quest(r.quest)
        name = questName(q, st)
        local who = text(q.requester)
        sub = (who and (t("requester", "Requested by {1}", who) .. "   ") or "") .. regionName(q.region)
        if st.state == "active" then
            local goal = st.stage and text(q.stages[st.stage].goal)
            body = { goal and t("goal", "Current goal: {1}", clean(goal)) or t("questActive", "In progress") }
            val = st.stage and t("questStage", "Stage {1}/{2}", st.stage, #q.stages) or ""
        elseif st.state == "done" then
            body, val = { t("questDone", "Completed") }, CHECK
        elseif st.state == "available" then
            body = { who and t("availableFrom", "Ready to take: talk to {1} in {2}.", who, regionName(q.region)) or t("questAvailable", "Available") }
        else
            body = { t("lockedHelp", "Not available yet: it opens later in the story or after another quest.") }
        end
    elseif r.kind == "battle" then
        local c = r.battle
        local s, wins = progress.colosseum(c)
        name = text(c.name) or ""
        sub = t("recommended", "Recommended level {1}", c.level)          -- the name already says the rank
        if s == "cleared" then body = { t("cleared", "Cleared") }
        elseif s == "open" then body = { t("battleOpen", "Open: you can take this battle at the Colosseum.") }
        else body = { t("battleLocked", "Locked") .. (text(c.locked) and ("\n" .. clean(text(c.locked))) or "") } end
        if wins and wins > 0 then val = t("wins", "Times won: {1}", wins) end
    elseif r.kind == "reward" then
        local rw, s = r.reward, progress.shardReward(r.reward)
        name = t("shardCount", "{1} tablet shards", rw.num)
        sub = clean(text(rw.room) or "")
        body = { t("shardsHeld", "Tablet shards held: {1}", progress.shardsHeld(data.shards.item)) }
        val = s == "claimed" and t("claimed", "Claimed") or (s == "next" and t("nextReward", "Next reward") or "")
    end
    d.name:SetTitle(FText(name))
    view.u.set(d.sub, sub)
    setBody(body)
    view.u.set(d.value, val)
end

---------------------------------------------------------------------------------------------------
-- Screen
---------------------------------------------------------------------------------------------------
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
    d.sub = u.text("", ui.GREY)
    detail:AddChildToVerticalBox(d.sub):SetPadding({ Left = 4, Top = 4, Right = 0, Bottom = 10 })
    local inner = u.new("VerticalBox")
    local columns = u.new("HorizontalBox")
    d.colW, d.fullW = math.floor((DETAIL_W - 60) / 2), DETAIL_W - 40
    d.body, d.body2 = u.text(""), u.text("")
    pcall(function() d.body:SetAutoWrapText(true); d.body2:SetAutoWrapText(true) end)
    d.left, d.gap, d.right = u.sized(d.body, d.colW), u.sized(nil, 20), u.sized(d.body2, d.colW)
    columns:AddChildToHorizontalBox(d.left)
    columns:AddChildToHorizontalBox(d.gap)
    columns:AddChildToHorizontalBox(d.right)
    inner:AddChildToVerticalBox(columns)
    inner:AddChildToVerticalBox(u.spacer(18))
    d.value = u.text("", ui.GOLD)
    inner:AddChildToVerticalBox(d.value)
    detail:AddChildToVerticalBox(u.panel(inner))
    view = { L = L, u = u, detail = d }
end

local function refresh(focus)
    buildRows()
    view.L:setRows(#rows, label)
    show(math.min(focus or shown or 1, #rows))
end

function M.open(host, u)
    view, shown = nil, nil
    progress.setAreas(data.areas)
    progress.refresh()
    polls, tot = 0, nil
    build(host, u)
    refresh(1)
end

function M.close() view = nil end

function M.confirm()
    local i = view and (view.L.focused or shown)
    local r = i and rows[i]
    if r and r.kind == "section" then
        expanded[r.section.id] = not expanded[r.section.id] or nil
        refresh(i)
    end
end

local NESTED = { area = true, shardArea = true, quest = true, battle = true, reward = true }

function M.poll()
    if not view then return end
    polls = polls + 1
    if polls >= REFRESH_POLLS then                      -- the game moves on while the screen is open (rarely)
        polls, tot = 0, nil
        progress.refresh()
        view.L:refresh()
        if shown then show(shown) end
    end
    local focused = view.L:poll(function(i, e)
        local r = rows[i]
        if not r then return end
        list.indent(e, NESTED[r.kind] and NEST or 0)
        local txt, color = value(r)
        list.setValue(e, txt, color)
        if e.title and e.kind ~= r.kind then
            e.kind = r.kind
            ui.paint(e.title, r.kind == "region" and ui.GREY or ui.WHITE)
        end
    end)
    if focused and focused ~= shown then show(focused) end
end

return M
