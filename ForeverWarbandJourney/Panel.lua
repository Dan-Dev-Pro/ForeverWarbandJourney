-- Forever Warband Journey: the main panel. Layout is a list of drawing ops drawn by a small backend.
local C = FWJ
local DAY = 86400

local T = {
  gold = { 1, .82, 0 }, white = { 1, 1, 1 }, grey = { .66, .6, .52 }, dim = { .45, .41, .36 },
  green = { .3, .88, .3 }, red = { 1, .38, .38 }, amber = { 1, .65, .2 }, purple = { .04, .4, .68 }, blue = { .04, .4, .68 },
  card = { .09, .09, .09, 1 }, edge = { .78, .73, .56, .9 }, track = { .04, .4, .68, .28 },
}
C.T = T
local PROFICON = { Mining = "Trade_Mining", Blacksmithing = "Trade_BlackSmithing", Tailoring = "Trade_Tailoring", Enchanting = "Trade_Engraving",
  Herbalism = "Trade_Herbalism", Alchemy = "Trade_Alchemy", Skinning = "INV_Misc_Pelt_Wolf_01", Engineering = "Trade_Engineering",
  Leatherworking = "INV_Misc_ArmorKit_17", ["First Aid"] = "Spell_Holy_SealOfSacrifice", Cooking = "INV_Misc_Food_15", Fishing = "Trade_Fishing" }
local PERKICON = { bed = "Spell_Nature_Sleep", heart = "Spell_Holy_Heal", book = "INV_Misc_Book_09", camp = "Spell_Fire_Fire", eye = "Ability_Hunter_EagleEye",
  map = "Ability_Mount_Wyvern_01", pot = "INV_Misc_Food_15", tomb = "Spell_Holy_Resurrection", hammer = "INV_Hammer_20", hands = "INV_Misc_Note_02",
  watch = "Spell_Holy_WordFortitude", trophy = "INV_BannerPVP_02", flask = "INV_Potion_93", gearh = "Trade_Engineering", herb = "INV_Misc_Herb_07",
  fish = "Trade_Fishing", coin = "INV_Misc_Coin_02", scroll = "INV_Scroll_03", needle = "Trade_Tailoring", rune = "Trade_Engraving" }
local function icon(n) if not n then return "Interface\\Icons\\INV_Misc_QuestionMark" end if type(n) == "number" or n:find("\\") then return n end return "Interface\\Icons\\" .. n end
C.ICON = icon
local function ccol(k)
  local c = C:Char(k)
  local cc = c and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.classFile or ""]
  return cc and { cc.r, cc.g, cc.b } or T.white
end
-- class portrait: the circular class icon sheet
local function portrait(L, x, y, s, k, desat)
  local c = C:Char(k)
  local tc = c and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[c.classFile or ""]
  if tc then L:tex(x, y, s, s, "Interface\\TargetingFrame\\UI-Classes-Circles", nil, { coords = { tc[1], tc[2], tc[3], tc[4] }, desat = desat })
  else L:tex(x, y, s, s, icon("INV_Misc_QuestionMark"), nil, { round = true, desat = desat }) end
end

-- layout --------------------------------------------------------------------------------
local Lay = {}
Lay.__index = Lay
local function newLay(w) return setmetatable({ ops = {}, y = 0, W = w, x0 = 0 }, Lay) end
function Lay:op(o) self.ops[#self.ops + 1] = o; return o end
function Lay:plate(x, y, w, h) return self:op({ k = "plate", x = x, y = y, w = w, h = h }) end
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
function Lay:tex(x, y, w, h, file, col, extra)
  if extra and extra.round and not file then file = CIRCLE; extra.round = nil end
  local o = { k = "tex", x = x, y = y, w = w, h = h, file = file, col = col }
  if extra then for a, b in pairs(extra) do o[a] = b end end
  return self:op(o)
end
function Lay:rect(x, y, w, h, col) return self:tex(x, y, w, h, nil, col) end
function Lay:text(x, y, w, s, size, col, j, wrap)
  size = size or 11
  local h = wrap and C.Measure(s, size, w) or (size + 3)
  self:op({ k = "text", x = x, y = y, w = w, h = h, s = s, size = size, col = col or T.white, j = j or "LEFT", wrap = wrap })
  return h
end
function Lay:hit(x, y, w, h, click, tip) return self:op({ k = "hit", x = x, y = y, w = w, h = h, click = click, tip = tip }) end
function Lay:icon(x, y, s, file, extra)
  self:rect(x - 1, y - 1, s + 2, s + 2, { 0, 0, 0, .9 })
  local e = { coords = { .07, .93, .07, .93 } }
  if extra then for a, b in pairs(extra) do e[a] = b end end
  return self:tex(x, y, s, s, icon(file), nil, e)
end
function Lay:bar(x, y, w, h, v, mx, col, label, size)
  self:rect(x, y, w, h, T.track)
  local f = mx > 0 and math.max(0, math.min(1, v / mx)) or 0
  if f > 0 then
    self:rect(x, y, w * f, h, { col[1], col[2], col[3], .9 })
  end
  if label then self:text(x, y + (h - (size or 10) - 2) / 2, w, label, size or 10, T.white, "CENTER") end
end
function Lay:pill(x, y, s, col, w)
  w = w or (C.Measure(s, 10, 999, true) + 12)
  self:rect(x, y, w, 15, { col[1] * .25, col[2] * .25, col[3] * .25, .9 })
  self:rect(x, y, w, 1, { col[1], col[2], col[3], .5 }); self:rect(x, y + 14, w, 1, { col[1], col[2], col[3], .5 })
  self:text(x, y + 1, w, s, 10, col, "CENTER")
  return w
end
-- card: a framed block with a gold title; body() adds content using self.y and self.x0
function Lay:card(title, body, right, tip, rcol)
  local x, w = 0, self.W
  local i0 = #self.ops + 1
  local top = self.y
  self.y = self.y + 10
  if title then
    self:text(12, self.y, w - 24, title, 12, T.gold)
    local rw = 0
    if tip then
      local tw = C.Measure(title, 12, 999, true)
      self:help(18 + tw, self.y, title .. "\n" .. tip)
    end
    if right then self:text(12, self.y + 1, w - 24, right, 10, rcol or T.grey, "RIGHT") end
    self.y = self.y + 19
  elseif tip then
    self:help(w - 26, self.y - 2, tip)
  end
  self.x0 = 12
  body(self, 12, w - 24)
  self.x0 = 0
  self.y = self.y + 8
  local h = self.y - top
  local frame = { { k = "plate", x = x, y = top, w = w, h = h } }
  for j = #frame, 1, -1 do table.insert(self.ops, i0, frame[j]) end
  self.y = self.y + 8
end
-- row: icon, title, sub-line, right text, optional bar under the title
function Lay:row(x, w, o)
  local y = self.y
  local s = o.iconSize or 30
  local tx = x
  if o.icon then self:icon(x, y, s, o.icon, o.iconExtra); tx = x + s + 8 end
  local tw = w - (tx - x)
  self:text(tx, y, tw, o.title or "", o.size or 12, o.col or T.white)
  if o.right then self:text(tx, y + 1, tw, o.right, 10, o.rcol or T.grey, "RIGHT") end
  local yy = y + (o.size or 12) + 4
  if o.bar then self:bar(tx, yy, tw, 10, o.bar[1], o.bar[2], o.bar[3] or T.purple, o.bar[4], 9); yy = yy + 13 end
  if o.sub then yy = yy + self:text(tx, yy, tw, o.sub, 10, o.scol or T.grey, "LEFT", true) end
  if o.tip then self:hit(x, y, w, math.max(s, yy - y), nil, o.tip) end
  self.y = math.max(y + s, yy) + (o.gap or 8)
end
-- small "?" that shows an explanation on hover
function Lay:help(x, y, tip)
  self:tex(x, y, 13, 13, nil, { .3, .26, .18, 1 }, { round = true })
  self:text(x, y, 13, "?", 9, T.gold, "CENTER")
  self:hit(x - 3, y - 3, 19, 19, nil, tip)
end
-- one-line row: optional icon or colour dot, label, a middle note, a value on the right; tooltip on hover
function Lay:line(x, w, o)
  local y = self.y
  local tx = x
  if o.icon then self:icon(x, y + 1, 15, o.icon); tx = x + 22
  elseif o.dot then self:rect(x + 1, y + 5, 8, 8, o.dot); tx = x + 16 end
  local vw = o.value and math.min(120, C.Measure(o.value, 11, 999, true) + 12) or 0
  local mw = o.mid and 90 or 0
  self:text(tx, y + 2, w - (tx - x) - vw - mw, o.label or "", 11, o.lcol or T.white)
  if o.mid then self:text(x + w - vw - mw - 4, y + 3, mw, o.mid, 9, T.grey, "RIGHT") end
  if o.value then self:text(x, y + 2, w, o.value, 11, o.vcol or T.white, "RIGHT") end
  if o.tip or o.click then self:hit(x, y, w, 18, o.click, o.tip) end
  self.y = y + 20
end
function Lay:para(x, w, s, size, col)
  self.y = self.y + self:text(x, self.y, w, s, size or 11, col or T.white, "LEFT", true) + 6
end
function Lay:bullets(x, w, list)
  for _, s in ipairs(list or {}) do
    self:rect(x + 3, self.y + 5, 4, 4, T.gold)
    self.y = self.y + self:text(x + 14, self.y, w - 14, s, 11, T.white, "LEFT", true) + 5
  end
end
function Lay:tiles(x, w, list)
  local n = #list
  local gap = 6
  local tw = (w - gap * (n - 1)) / n
  for i, t in ipairs(list) do
    local tx = x + (i - 1) * (tw + gap)
    self:rect(tx, self.y, tw, 46, { 0, 0, 0, .35 })
    self:rect(tx, self.y, tw, 1, { 1, 1, 1, .06 })
    self:text(tx + 8, self.y + 6, tw - 16, t[1], 15, t[3] or T.white)
    self:text(tx + 8, self.y + 27, tw - 16, t[2], 9, T.grey)
  end
  self.y = self.y + 52
end


-- buttons and inputs
function Lay:button(x, y, w, h, label, click, opts)
  opts = opts or {}
  local on = opts.on
  self:rect(x, y, w, h, on and { .25, .18, .07, .95 } or { .13, .1, .07, .95 })
  self:rect(x, y, w, 1, on and { 1, .82, 0, .7 } or { 1, 1, 1, .08 })
  self:rect(x, y + h - 1, w, 1, { 0, 0, 0, .8 })
  self:rect(x, y, 1, h, { 1, 1, 1, .05 }); self:rect(x + w - 1, y, 1, h, { 0, 0, 0, .6 })
  self:text(x, y + (h - 13) / 2, w, label, opts.size or 11, opts.col or (on and T.gold or T.white), "CENTER")
  self:hit(x, y, w, h, click, opts.tip)
end
function Lay:iconbtn(x, y, s, file, click, tip)
  self:tex(x, y, s, s, file)
  self:hit(x, y, s, s, click, tip)
end
function Lay:edit(x, y, w, id, value, opts)
  opts = opts or {}
  self:rect(x, y, w, 20, { 0, 0, 0, .7 })
  self:rect(x, y, w, 1, { .4, .33, .22, 1 }); self:rect(x, y + 19, w, 1, { .4, .33, .22, 1 })
  self:rect(x, y, 1, 20, { .4, .33, .22, 1 }); self:rect(x + w - 1, y, 1, 20, { .4, .33, .22, 1 })
  self:op({ k = "edit", x = x + 4, y = y + 1, w = w - 8, h = 18, id = id, value = value or "", numeric = opts.numeric, hint = opts.hint, enter = opts.enter })
end
function Lay:check(x, y, w, label, on, click)
  self:rect(x, y + 1, 14, 14, { 0, 0, 0, .7 }); self:rect(x, y + 1, 14, 1, { .5, .4, .25, 1 }); self:rect(x, y + 14, 14, 1, { .5, .4, .25, 1 })
  self:rect(x, y + 1, 1, 14, { .5, .4, .25, 1 }); self:rect(x + 13, y + 1, 1, 14, { .5, .4, .25, 1 })
  if on then self:tex(x - 2, y - 1, 18, 18, "Interface\\Buttons\\UI-CheckBox-Check") end
  self:text(x + 22, y + 2, w - 22, label, 11, T.white)
  self:hit(x, y, w, 18, click)
end

-- header and tab bar ------------------------------------------------------------------------------
local TABS = { "Now", "Goals", "Talents", "Trades", "Legacy", "Warband" }
C.tab = C.tab or "Now"
C.form = C.form or {}
function C:ViewKey()
  if self.view and self:Char(self.view) then return self.view end
  return self.key
end

local function headerOps(W)
  local L = newLay(W)
  local k = C:ViewKey()
  local c = C:Char(k)
  local lv = C:Lv(k)
  local cc = ccol(k)
  portrait(L, 18, 16, 52, k)
  L:tex(-1, -3, 90, 90, nil, nil, { atlas = "auctionhouse-itemicon-border-artifact" })
  L:rect(30, 62, 28, 16, { 0, 0, 0, .9 }); L:rect(30, 62, 28, 1, T.gold); L:rect(30, 77, 28, 1, T.gold)
  L:text(30, 63, 28, tostring(math.floor(lv)), 11, T.gold, "CENTER")
  L:text(84, 16, 200, c.name or C:Short(k), 16, cc)
  L:text(84, 38, 200, string.format("%s %s%s", c.race or "", c.class or "", c.role and ("  |  " .. c.role) or ""), 11, T.grey)
  local g = C:ActiveGoal()
  if g and g.ch == k then
    local d = C:DaysAhead(g)
    if d and d >= .5 then L:pill(84, 56, string.format("+%.1f days", d), T.green)
    elseif d and d <= -.5 then L:pill(84, 56, string.format("%.1f days behind", -d), T.red)
    else L:pill(84, 56, "on plan", T.gold) end
  elseif g then L:pill(84, 56, "plan says " .. C:Short(g.ch), T.grey)
  elseif #C.db.goals == 0 then L:pill(84, 56, "no goals yet", T.amber) end
  -- switcher: characters in the plan, plus a settings cog
  local plan = C:Plan()
  local n = math.min(#plan, 5)
  for i = 1, n do
    local kk = plan[i]
    local x = W - 14 - 30 - (n - i + 1) * 32
    local on = kk == k
    L:tex(x, 16, 28, 28, nil, on and { 1, .82, 0, 1 } or { .3, .26, .2, 1 }, { round = true })
    portrait(L, x + 2, 18, 24, kk, not on)
    L:hit(x, 16, 28, 28, function() C.view = kk; C:Refresh() end, function(t) t:AddLine(C:Char(kk).name); t:AddLine(string.format("Level %d %s", C:Char(kk).level or 1, C:Char(kk).class or ""), 1, 1, 1) end)
  end
  L:iconbtn(W - 38, 18, 24, "Interface\\Icons\\Trade_Engineering", function() C.tab = C.tab == "Settings" and "Now" or "Settings"; C:Refresh() end, function(t) t:AddLine("Settings") end)
  if C.tab == "Settings" then L:rect(W - 40, 44, 28, 2, T.gold) end
  local xp, mx = c.xp or 0, math.max(1, c.xpMax or 1)
  local rp = C:RestedPct(k)
  local fmt = BreakUpLargeNumbers or tostring
  local label = math.floor(lv) >= 60 and "Level 60" or string.format("%s / %s XP%s", fmt(xp), fmt(mx), rp and rp > 0 and string.format("   %d%% rested", rp) or "")
  L:bar(14, 84, W - 28, 13, xp, mx, T.blue, label, 10)
  if rp and rp > 0 then
    local a = math.min(1, xp / mx)
    local f = math.min(1, (xp + rp / 100 * mx) / mx)
    L:rect(14 + (W - 28) * a, 84, (W - 28) * (f - a), 2, { .3, .55, 1, .9 })
  end
  return L.ops
end

local function tabOps(W)
  local L = newLay(W)
  local tw = (W - 28) / #TABS
  for i, name in ipairs(TABS) do
    local x = 14 + (i - 1) * tw
    local on = C.tab == name
    L:rect(x + 1, 6, tw - 2, 24, on and { .22, .16, .07, .95 } or { .06, .05, .04, .9 })
    L:rect(x + 1, 6, tw - 2, 1, { 1, 1, 1, .05 })
    if on then L:rect(x + 1, 28, tw - 2, 2, T.gold) end
    L:text(x, 11, tw, name, 11, on and T.gold or T.grey, "CENTER")
    L:hit(x, 6, tw, 24, function() C.tab = name; C:Refresh() end)
  end
  return L.ops
end

-- tab bodies ---------------------------------------------------------------------------------------
-- Style: one line per fact, numbers on the right, explanations in tooltips (hover the ? or the row).
local BODY = {}
local function goalLabel(g) return string.format("%s to %d", C:Short(g.ch), g.to) end
local function hm(sec)
  local m = math.abs(sec or 0) / 60
  if m >= 60 then return string.format("%dh %02dm", m / 60, m % 60) end
  return string.format("%dm", math.max(1, m))
end
local function iconOf(id)
  local i = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id))
  if not i and GetItemInfoInstant then i = select(5, GetItemInfoInstant(id)) end
  return i or "INV_Misc_QuestionMark"
end
local function iname(id) return C.ITEM[id] and C.ITEM[id][1] or ("item " .. id) end
local function goldOnly(c) return (C.Money(c or 0):match("^(%-?%d+g)")) or "0g" end

-- NOW: what to do, how you're tracking, this level
function BODY.Now(L, k)
  local c = C:Char(k)
  local lv = C:Lv(k)
  local g = C:ActiveGoal()
  local mine = C:NextGoalFor(k)
  local rows = C:Forecast()
  if #C.db.goals == 0 then
    L:card("Set up", function(L, x, w)
      L:button(x, L.y, (w - 8) / 2, 24, "Add goals", function() C.tab = "Goals"; C:Refresh() end, { on = true })
      L:button(x + (w + 8) / 2, L.y, (w - 8) / 2, 24, "Pick characters", function() C.tab = "Warband"; C:Refresh() end)
      L.y = L.y + 30
    end, nil, "Log in on each character once so FWJ can read them.\nThen pick who's in your plan and add level goals.")
  end
  -- hero: who to play and how it's going
  if g and g.ch ~= k then
    L:card(nil, function(L, x, w)
      portrait(L, x, L.y, 32, g.ch)
      L:text(x + 42, L.y + 1, w - 42, "Play " .. (C:Char(g.ch).name or C:Short(g.ch)), 14, ccol(g.ch))
      L:text(x + 42, L.y + 19, w - 42, "next goal: " .. goalLabel(g), 10, T.grey)
      L.y = L.y + 38
    end)
  end
  if mine then
    local h = C:Hours(k, lv, mine.to)
    local r = rows[mine.id]
    local d = C:DaysAhead(mine)
    local status, scol = nil, T.gold
    if d and d >= .5 then status, scol = string.format("+%.1f days", d), T.green
    elseif d and d <= -.5 then status, scol = string.format("%.1f days behind", -d), T.red
    elseif d then status = "on plan" end
    L:card("Level " .. mine.to .. (mine.by and ("  by " .. mine.by) or ""), function(L, x, w)
      local from = mine.startLv or math.floor(lv)
      L:bar(x, L.y, w, 12, lv - from, math.max(.01, mine.to - from), T.blue, string.format("%.1f / %d", lv, mine.to), 9)
      L.y = L.y + 18
      local tn = k == C.key and C:Tonight(k)
      L:tiles(x, w, { { string.format("%.1f h", h), "left to play" },
        { r and r.at > 0 and date("%a %d %b", r.at) or "-", "finish" },
        tn and { tn.onPlan and tn.target <= lv and "on plan" or string.format("%.1f", tn.target), "tonight", T.gold } or { string.format("%.2f", (C:Pace(k))), "pace" } })
    end, status, "Left to play: hours at your own pace.\nFinish: when you'll get there, from your playing hours.\nTonight: the level to reach by midnight to stay on plan.", scol)
  end
  -- to do
  local items = {}
  local due = C:TrainerDue(k)
  if due then items[#items + 1] = { "Ability_Warrior_BattleShout", due } end
  if (c.freeTalents or 0) > 0 then items[#items + 1] = { "Ability_Marksmanship", string.format("Spend %d talent point%s", c.freeTalents, c.freeTalents > 1 and "s" or "") } end
  for name, v in pairs(c.profs or {}) do
    local a = C:ProfAdvice(k, name, v[1], v[2])
    if a.state == "train" then items[#items + 1] = { PROFICON[name], name .. ": " .. a.text } end
  end
  local m = C:NextMilestone(k)
  if #items > 0 then
    L:card("To do", function(L, x, w)
      for _, it in ipairs(items) do L:line(x, w, { icon = it[1], label = it[2], lcol = T.gold }) end
    end)
  end
  -- this level
  local live = k == C.key and C:LevelLive()
  local pace, life, rec, n = C:PaceParts(k)
  L:card("This level", function(L, x, w)
    if live then
      local good = live.ahead >= 0
      L:line(x, w, { label = string.format("Level %d   %s of %s", live.lv, hm(live.spent), hm(live.est)), value = (good and "ahead " or "behind ") .. hm(live.ahead), vcol = good and T.green or T.red })
      L:bar(x, L.y, w, 6, math.min(live.spent, live.est), math.max(1, live.est), good and T.green or T.red)
      L:rect(x + w * math.min(1, live.expect / math.max(1, live.est)) - 1, L.y - 2, 2, 10, T.gold)
      L.y = L.y + 12
    end
    local c0 = C:Char(k)
    local nowP = (c0 and c0.played or 0) + ((k == C.key and C.playedAt) and (GetTime() - C.playedAt) or 0)
    for i, r in ipairs(C:LevelPlan(k, 4)) do
      local at = C:AfterHours(time(), math.max(0, r.reach - nowP) / 3600)
      L:line(x, w, { label = "Level " .. r.lv, lcol = i == 1 and T.white or T.grey, mid = r.est > 0 and hm(r.est) or "", value = date("%a %d %b", at), vcol = T.grey })
    end
    local lt = C:LevelTimes(k)
    if #lt > 0 then
      local e = lt[1]
      local dd = (e.h - e.est) * 3600
      L:line(x, w, { label = "Last level (" .. e.lv .. ")", lcol = T.grey, mid = hm(e.h * 3600), value = (dd <= 0 and "-" or "+") .. hm(dd), vcol = dd <= 0 and T.green or T.red })
    end
  end, string.format("pace %.2f", pace), "Top line: time on this level against its estimate. The gold mark is where you'd be if exactly on pace.\nRows: each coming level's estimate and the day you'll reach it.\nPace: your time vs an average player (lower is faster)"
    .. (rec and string.format(", from your last %d levels (%.2f) and lifetime (%.2f).", n, rec, life) or ", from lifetime /played."))
  -- session and guide
  if k == C.key and C.sess then
    local rate = C:XPRate()
    local left = UnitXPMax("player") - UnitXP("player")
    local kills = C:KillsToLevel()
    L:card("Session", function(L, x, w)
      L:tiles(x, w, { { rate > 0 and string.format("%.1fk", rate / 1000) or "-", "XP / hour" },
        { rate > 0 and hm(left / rate * 3600) or "-", "next level" },
        { kills and tostring(kills) or "-", "kills" },
        { string.format("%dm", (GetTime() - C.sess.start) / 60), "played" } })
    end)
  end
  if c.jny and c.jg and c.jg[c.jny] then
    local e = c.jg[c.jny]
    L:card(nil, function(L, x, w)
      L:line(x, w, { icon = "INV_Misc_Map_01", label = C:JourneyName(c.jny), mid = C:JourneyStep(e.step) or "", value = string.format("%.1f h", (e.sec or 0) / 3600), vcol = T.grey,
        tip = "Journey guide\nYour current guide and step, read from the Journey addon. Hours count while you're on this guide." })
    end)
  end
  if m then
    L:card(nil, function(L, x, w) L:line(x, w, { icon = "INV_Misc_PocketWatch_01", label = string.format("At %d: %s", m[1], m[2]), lcol = T.grey }) end)
  end
end

-- GOALS: the queue, add one, templates, target date
function BODY.Goals(L)
  local rows = C:Forecast()
  local g0 = C:ActiveGoal()
  L:card("Goals", function(L, x, w)
    if #C.db.goals == 0 then L:text(x, L.y, w, "No goals yet.", 11, T.grey); L.y = L.y + 18 end
    for i, g in ipairs(C.db.goals) do
      local ok = C:Char(g.ch)
      local done = ok and C:GoalDone(g)
      local r = rows[g.id]
      local y = L.y
      if g == g0 then L:rect(x - 4, y - 2, w + 8, 24, { 1, .82, 0, .08 }) end
      if ok then portrait(L, x, y, 20, g.ch, done) end
      L:text(x + 26, y + 3, 140, goalLabel(g), 11, done and T.dim or (g == g0 and T.gold or T.white))
      local right = done and "|cff4ce04cdone|r" or (r and r.at > 0 and date("%a %d %b", r.at) or "")
      if g.by and not done then
        local late = r and r.at > 0 and C.ParseDate(g.by) and r.at > C.ParseDate(g.by) + 86399
        right = (late and "|cffff6060" or "|cffffffff") .. right .. "|r|cffa89a84  / " .. g.by:sub(6) .. "|r"
      end
      L:text(x + 170, y + 3, w - 170 - 70, right, 10, T.grey, "RIGHT")
      L:iconbtn(x + w - 62, y + 1, 18, "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up", function() C:MoveGoal(i, -1); C:Refresh() end, "Move up")
      L:iconbtn(x + w - 42, y + 1, 18, "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up", function() C:MoveGoal(i, 1); C:Refresh() end, "Move down")
      L:iconbtn(x + w - 20, y + 2, 16, "Interface\\Buttons\\UI-StopButton", function() C:RemoveGoal(i); C:Refresh() end, "Remove")
      L.y = y + 26
    end
  end, "finish  /  deadline", "Played top to bottom. The highlighted goal is the one to play now.\nDates: forecast finish, then your deadline. Red means the forecast misses it.")
  L:card("Add", function(L, x, w)
    local plan = C:Plan()
    C.form.goalCh = C.form.goalCh or plan[1]
    local k = C.form.goalCh
    if not k then L:text(x, L.y, w, "Pick characters on the Warband tab first.", 11, T.grey); L.y = L.y + 18 return end
    L:rect(x, L.y, 120, 20, { .13, .1, .07, .95 })
    portrait(L, x + 3, L.y + 2, 16, k)
    L:text(x + 24, L.y + 4, 92, C:Short(k), 11, ccol(k))
    L:hit(x, L.y, 120, 20, function()
      local idx = 1
      for i, kk in ipairs(plan) do if kk == k then idx = i end end
      C.form.goalCh = plan[idx % #plan + 1]; C:Refresh() end, "Character\nClick to switch")
    L:edit(x + 126, L.y, 44, "goalTo", C.form.goalTo or "", { numeric = true, hint = "lvl" })
    L:edit(x + 176, L.y, w - 176 - 70, "goalBy", C.form.goalBy or "", { hint = "deadline (optional)" })
    L:button(x + w - 64, L.y, 64, 20, "Add", function()
      local to = tonumber(C.form.goalTo)
      local by = C.form.goalBy
      if by == "" then by = nil end
      if not to then C:Print("enter a target level.") return end
      if by and not C.ParseDate(by) then C:Print("deadline must look like 2026-11-30.") return end
      C:AddGoal(C.form.goalCh, to, by); C.form.goalTo = nil; C.form.goalBy = nil; C:Refresh()
    end, { on = true })
    L.y = L.y + 26
  end, nil, "Deadline format: 2026-11-30")
  L:card("Templates", function(L, x, w)
    local tpl = { { "solo", "Solo", "Solo\nMain to 60." }, { "crafter", "Main + crafter", "Main + crafter\nCrafter 10, main 30, crafter 20, main 60, crafter 60." },
      { "relay", "Relay", "Relay\nCrafter 10, main 30, gatherer 10, crafter 20, main 60, crafter 60, gatherer 60." } }
    local bw = (w - 16) / 3
    for i, t in ipairs(tpl) do
      L:button(x + (i - 1) * (bw + 8), L.y, bw, 22, t[2], function() if not C:ApplyTemplate(t[1]) then C:Print("set the Main, Crafter and Gatherer roles on the Warband tab first.") end; C:Refresh() end, { tip = t[3] .. "\n\nReplaces your current goals." })
    end
    L.y = L.y + 28
  end, nil, "Builds goals from the roles on the Warband tab, replacing your list.")
  L:card("Target date", function(L, x, w)
    L:edit(x, L.y, 120, "target", C.db.opt.target or "", { hint = "2026-12-02", enter = function(v) if v == "" or C.ParseDate(v) then C.db.opt.target = v ~= "" and v or nil; C:Refresh() end end })
    L:text(x + 130, L.y + 4, w - 130, "Enter to save", 10, T.dim)
    L.y = L.y + 26
  end, nil, "When your last goal should be done. The pace tracker counts down to it.")
end

-- TALENTS: the trees, nothing else
function BODY.Talents(L, k)
  local c = C:Char(k)
  if not c.talents or #c.talents == 0 then
    L:card(nil, function(L, x, w) L:text(x, L.y, w, "Log in on " .. C:Short(k) .. " to read their talents.", 11, T.grey); L.y = L.y + 18 end)
    return
  end
  if (c.freeTalents or 0) > 0 then
    L:card(nil, function(L, x, w) L:line(x, w, { icon = "Ability_Marksmanship", label = string.format("%d point%s to spend", c.freeTalents, c.freeTalents > 1 and "s" or ""), lcol = T.gold, value = "press N", vcol = T.grey }) end)
  end
  local n = #c.talents
  L:card(nil, function(L, x, w)
    local gap = 10
    local tw = (w - gap * (n - 1)) / n
    local s, sp = 26, 6
    local maxTier = 1
    for _, tab in ipairs(c.talents) do for _, t in ipairs(tab.talents) do maxTier = math.max(maxTier, t[3] or 1) end end
    local y0 = L.y
    for ti, tab in ipairs(c.talents) do
      local tx = x + (ti - 1) * (tw + gap)
      L:text(tx, y0, tw, tab.name .. "  |cffffffff" .. tab.spent .. "|r", 11, T.gold, "CENTER")
      local gx = tx + (tw - (4 * s + 3 * sp)) / 2
      for _, t in ipairs(tab.talents) do
        local ix, iy = gx + ((t[4] or 1) - 1) * (s + sp), y0 + 20 + ((t[3] or 1) - 1) * (s + 10)
        local has = t[5] > 0
        L:icon(ix, iy, s, t[2], { desat = not has })
        if has then
          L:rect(ix + s - 18, iy + s - 8, 20, 11, { 0, 0, 0, .9 })
          L:text(ix + s - 18, iy + s - 9, 20, t[5] .. "/" .. t[6], 8, t[5] == t[6] and T.green or T.gold, "CENTER")
        end
        L:hit(ix, iy, s, s, nil, t[1] .. "\nRank " .. t[5] .. " of " .. t[6])
      end
    end
    L.y = y0 + 20 + maxTier * (s + 10)
  end)
end

-- TRADES: per profession, what to craft and what to buy
function BODY.Trades(L, k)
  local c = C:Char(k)
  local names = {}
  for n in pairs(c.profs or {}) do names[#names + 1] = n end
  table.sort(names)
  if #names == 0 then
    L:card(nil, function(L, x, w)
      L:text(x, L.y, w, c.profs and "No professions yet." or ("Log in on " .. C:Short(k) .. " to read their professions."), 11, T.grey); L.y = L.y + 18
    end)
  end
  local short = C:Shortfall()
  for _, n in ipairs(names) do
    local v = c.profs[n]
    local skill, mx = v[1], v[2]
    local a = C:ProfAdvice(k, n, skill, mx)
    local target = C:RecSkill(k, skill)
    L:card(nil, function(L, x, w)
      -- header: icon, name, skill bar, target
      L:icon(x, L.y, 24, PROFICON[n])
      L:text(x + 32, L.y, 160, n, 12, T.gold)
      L:text(x + 32, L.y, w - 32, a.state == "train" and ("|cffffd100" .. a.text .. "|r") or (target > skill and ("target " .. target) or "on target"), 10, T.grey, "RIGHT")
      L:bar(x + 32, L.y + 16, w - 32, 8, skill, math.max(target, skill + 1), T.blue)
      L:text(x + 32, L.y + 15, w - 36, skill .. " / " .. mx, 8, T.white, "RIGHT")
      L:hit(x, L.y, w, 26, nil, n .. "\nTarget: 5 skill per character level, within the rank your level allows.\nApprentice 75, Journeyman 150 (level 10), Expert 225 (level 20), Artisan 300 (level 35).")
      L.y = L.y + 32
      if C.RECIPES[n] and skill < 300 then
        local picks, locked, done = C:NextSteps(k, n, skill, target > skill and target or C.NextCap(skill))
        local rt = C:Route(k, n)
        L:text(x, L.y, w, "Craft", 10, T.gold)
        if locked then
          L:button(x + w - 64, L.y - 2, 64, 16, "Re-plan", function() C:UnlockRoute(k, n); C:Refresh() end, { size = 9, tip = "Re-plan\nThrow away the locked route and plan again from what you own now." })
          L:text(x, L.y, w - 72, "|cff4ce04clocked|r", 9, T.grey, "RIGHT")
        else
          L:button(x + w - 64, L.y - 2, 64, 16, "Lock", function() C:LockRoute(k, n); C:Refresh() end, { size = 9, tip = "Lock route\nKeep this plan while you craft, instead of re-planning as your bags change.\nIt also locks when you leave the Auction House after scanning." })
        end
        L.y = L.y + 16
        if #picks == 0 then L:line(x, w, { label = "Nothing gives skill-ups here: visit the trainer", lcol = T.amber }) end
        for i = 1, math.min(3, #picks) do
          local e = picks[i]
          local reag = {}
          for _, r in ipairs(e.rec.r) do reag[#reag + 1] = r[2] .. " " .. iname(r[1]) end
          local can = C:CanMake(k, e.rec)
          local tip = e.name .. "\n" .. e.from .. " to " .. e.to .. ", about " .. e.crafts .. " crafts\nEach: " .. table.concat(reag, ", ")
            .. (not e.live and "\nLearn it at the trainer." or (can > 0 and ("\nYou can make " .. can .. " from your bags.") or "\nYou need materials."))
          L:line(x, w, { dot = C.COLOURS[e.col] or T.grey, label = e.name, lcol = i == 1 and T.white or T.grey,
            mid = not e.live and "|cffffd100learn|r" or (can > 0 and ("|cff4ce04c" .. math.min(can, e.crafts) .. " ready|r") or "|cffff6060need mats|r"),
            value = "x" .. e.crafts, vcol = T.gold, tip = tip })
        end
      elseif C.NODES[n] then
        L:text(x, L.y, w, "Nodes", 10, T.gold); L.y = L.y + 16
        local shown = 0
        for _, node in ipairs(C.NODES[n]) do
          if node[2] <= skill + 25 and shown < 6 then
            local vd = C:NodeVerdict(k, n, node, short)
            if vd.col ~= "grey" or vd[1] ~= "Ignore" or shown < 2 then
              shown = shown + 1
              L:line(x, w, { dot = C.COLOURS[vd.col] or T.grey, label = node[1], lcol = vd.col == "grey" and T.grey or T.white,
                value = vd[1], vcol = vd[3] == "gold" and T.gold or vd[3] == "red" and T.red or T.grey, tip = node[1] .. "\n" .. vd[2] })
            end
          end
        end
      end
    end)
  end
  -- shopping: to reach the targets
  local shop = C:Shopping(k)
  if #shop.buy > 0 or #shop.make > 0 then
    L:card("Shopping", function(L, x, w)
      if #shop.buy == 0 then L:line(x, w, { label = "You have everything", lcol = T.green }) end
      for _, e in ipairs(shop.buy) do
        L:line(x, w, { icon = iconOf(e.id), label = e.n .. "  " .. iname(e.id), value = e.cost and (C.MoneyText(e.cost) .. (e.partial and " |cffff6060+|r" or "")) or "|cffa89a84?|r",
          tip = iname(e.id) .. (e.note and ("\n" .. e.note) or "") .. (e.partial and "\nNot enough listed at your last scan." or "") })
      end
      if #shop.make > 0 then
        local mk = {}
        for _, m in ipairs(shop.make) do mk[#mk + 1] = m.n .. " " .. iname(m.id) end
        L:line(x, w, { icon = "Trade_Mining", label = "Make: " .. table.concat(mk, ", "), lcol = T.grey })
      end
      L:line(x, w, { label = "Total", lcol = T.gold, value = C.MoneyText(shop.total) .. (shop.unpriced > 0 and string.format(" |cffa89a84+%d?|r", shop.unpriced) or ""), vcol = T.gold })
    end, C.db.prices and next(C.db.prices) and "priced" or "scan at the AH",
    "What's still short of your targets, after counting bags and banks on every character.\nPress Scan prices at the Auction House: the route and this list switch to the cheapest options, ore against bars included.")
  end
  if C.sess and C.sess.mats and next(C.sess.mats) and k == C.key then
    L:card("Gathered", function(L, x, w)
      local list = {}
      for id, nn in pairs(C.sess.mats) do list[#list + 1] = { id, nn } end
      table.sort(list, function(p, q) return p[2] > q[2] end)
      for i = 1, math.min(5, #list) do L:line(x, w, { icon = iconOf(list[i][1]), label = iname(list[i][1]), value = tostring(list[i][2]), vcol = T.gold }) end
    end, "this session")
  end
  local sec = {}
  for n in pairs(c.secondary or {}) do sec[#sec + 1] = n end
  table.sort(sec)
  if #sec > 0 then
    L:card(nil, function(L, x, w)
      for _, n in ipairs(sec) do
        local v = c.secondary[n]
        L:line(x, w, { icon = PROFICON[n], label = n, lcol = T.grey, value = v[1] .. " / " .. v[2], vcol = T.grey })
      end
    end)
  end
end

-- LEGACY: points bar, perks with -/+
function BODY.Legacy(L, k)
  local c = C:Char(k)
  c.legacy = c.legacy or {}
  local spent, byTree = 0, {}
  for tree, perks in pairs(C.LEGACY) do
    byTree[tree] = 0
    for _, p in ipairs(perks) do local r = c.legacy[p[1]] or 0; spent = spent + r; byTree[tree] = byTree[tree] + r end
  end
  L:card(nil, function(L, x, w)
    L:bar(x, L.y, w, 14, spent, C.LEGACY_MAX, T.blue, string.format("%d / %d points planned", spent, C.LEGACY_MAX), 9)
    L.y = L.y + 18
  end, nil)
  for _, tree in ipairs({ "Adventure", "Resourcefulness", "Professions" }) do
    local perks = C.LEGACY[tree]
    if perks then
      L:card(tree, function(L, x, w)
        for _, p in ipairs(perks) do
          local r = c.legacy[p[1]] or 0
          local gate = C.LEGACY_GATE[p[1]]
          local locked = gate and (byTree[gate[1]] - (gate[1] == tree and r or 0)) < gate[2]
          local y = L.y
          L:icon(x, y, 18, PERKICON[p[4]], { desat = r == 0 })
          L:text(x + 26, y + 2, w - 120, p[1], 11, r > 0 and T.white or T.grey)
          L:text(x + w - 92, y + 2, 40, locked and "|cffffa533locked|r" or (r .. "/" .. p[2]), 11, r == p[2] and T.green or (r > 0 and T.gold or T.grey), "CENTER")
          L:hit(x, y, w - 48, 20, nil, p[1] .. "\n" .. p[3] .. (locked and string.format("\nNeeds %d points in %s first.", gate[2], gate[1]) or ""))
          L:iconbtn(x + w - 44, y, 20, "Interface\\Buttons\\UI-MinusButton-Up", function() if r > 0 then c.legacy[p[1]] = r - 1; C:Refresh() end end)
          L:iconbtn(x + w - 22, y, 20, "Interface\\Buttons\\UI-PlusButton-Up", function()
            if r < p[2] and spent < C.LEGACY_MAX and not locked then c.legacy[p[1]] = r + 1; C:Refresh() end end)
          L.y = y + 24
        end
      end, tostring(byTree[tree]), tree == "Adventure" and "Addons can't read Legacy points, so this is your plan, not a readout.\nHover a perk for what it does." or nil)
    end
  end
end

-- WARBAND: everyone at a glance
function BODY.Warband(L)
  L:card(nil, function(L, x, w)
    local pct = C:AccountPct()
    L:bar(x, L.y, w, 14, pct, 100, T.blue, string.format("Warband to 60: %.1f%%", pct), 9)
    L.y = L.y + 20
    local total = 0
    for _, k in ipairs(C:Roster()) do total = total + (C:Char(k).money or 0) end
    local wp, wplan = C:WeekPlayed()
    L:tiles(x, w, { { goldOnly(total), "gold" }, { string.format("%.1f / %d h", wp, wplan), "this week" },
      { tostring(math.max(0, math.ceil((C.RAIDS - time()) / DAY))), "days to raids" } })
  end)
  for _, k in ipairs(C:Roster()) do
    local c = C:Char(k)
    L:card(nil, function(L, x, w)
      local y = L.y
      portrait(L, x, y, 28, k, not c.inPlan)
      L:text(x + 36, y, w - 180, c.name or C:Short(k), 12, c.inPlan and ccol(k) or T.grey)
      L:text(x + 36, y + 15, w - 180, string.format("%.1f  %s", C:Lv(k), c.class or ""), 10, T.grey)
      L:button(x + w - 140, y + 4, 66, 18, c.inPlan and (c.role or "Alt") or "Add", function()
        if not c.inPlan then c.inPlan = true; c.order = #C:Plan()
        else
          local i = 1
          for j, r in ipairs(C.ROLES) do if r == c.role then i = j end end
          c.role = C.ROLES[i % #C.ROLES + 1]
        end
        C:Refresh() end, { size = 10, on = c.inPlan, tip = c.inPlan and "Role\nClick to cycle Main, Crafter, Gatherer, Alt. Templates and the mail button use these." or "Add to the plan" })
      if c.inPlan then L:button(x + w - 70, y + 4, 70, 18, "Remove", function() c.inPlan = false; C:Refresh() end, { size = 10, tip = "Take out of the plan" }) end
      L.y = y + 32
      if c.inPlan then
        -- professions as icon + number, then gold and rested
        local names = {}
        for n in pairs(c.profs or {}) do names[#names + 1] = n end
        table.sort(names)
        local px = x
        for _, n in ipairs(names) do
          L:icon(px, L.y, 14, PROFICON[n])
          L:text(px + 18, L.y + 1, 40, tostring(c.profs[n][1]), 10, T.white)
          L:hit(px, L.y, 54, 14, nil, n .. "\n" .. c.profs[n][1] .. " / " .. c.profs[n][2])
          px = px + 58
        end
        local rp = C:RestedPct(k)
        L:text(x, L.y + 1, w, goldOnly(c.money) .. (rp and rp > 0 and string.format("   |cff6fa8ff%d%% rested|r", rp) or ""), 10, T.grey, "RIGHT")
        L.y = L.y + 18
      end
    end)
  end
  L:card("Last 7 days", function(L, x, w)
    local vals, mx = {}, 1
    for i = 6, 0, -1 do
      local t = time() - i * DAY
      local h = C:DayStats(date("%Y-%m-%d", t))
      local plan = C:DayHours(C:Midnight(t))
      vals[#vals + 1] = { t, h, plan }
      mx = math.max(mx, h, plan)
    end
    local ch, gap = 56, 8
    local bw = (w - gap * 6) / 7
    for i, v in ipairs(vals) do
      local bx = x + (i - 1) * (bw + gap)
      L:rect(bx, L.y, bw, ch, { 0, 0, 0, .3 })
      local ph = v[3] / mx * ch
      if ph > 0 then L:rect(bx, L.y + ch - ph, bw, 1, { 1, .82, 0, .7 }) end
      local hh = v[2] / mx * ch
      if hh > 0 then L:rect(bx + 3, L.y + ch - hh, bw - 6, hh, v[2] >= v[3] and { .3, .75, .35, .95 } or { .12, .55, .9, .95 }) end
      L:text(bx, L.y + ch + 3, bw, date("%a", v[1]), 9, i == 7 and T.gold or T.grey, "CENTER")
      L:text(bx, L.y + ch - hh - 13, bw, v[2] > 0 and string.format("%.1f", v[2]) or "", 9, T.white, "CENTER")
      L:hit(bx, L.y, bw, ch, nil, date("%A %d %b", v[1]) .. string.format("\nPlayed %.1f h, planned %.1f h", v[2], v[3]))
    end
    L.y = L.y + ch + 16
  end, nil, "Bars: hours played. Gold line: hours planned. Green: you hit the plan.")
end

-- SETTINGS
function BODY.Settings(L)
  local o = C.db.opt
  L:card("Playing time", function(L, x, w)
    local mwd, mwe, nwd, nwe = C:MeasuredHours()
    local a, b = C:BaseHours()
    L:tiles(x, w, { { string.format("%.1f h", a), "weekdays" }, { string.format("%.1f h", b), "weekend days" },
      { (mwd and mwe) and "measured" or string.format("%d + %d days", nwd, nwe), (mwd and mwe) and "source" or "measuring" } })
    L:check(x, L.y, w, "Use my measured time", o.measured, function() o.measured = not o.measured; C:Refresh() end); L.y = L.y + 22
    L:text(x, L.y + 4, 90, "Fallback", 10, T.grey)
    L:text(x + 90, L.y + 4, 60, "weekday", 10, T.grey); L:edit(x + 150, L.y, 40, "wd", tostring(o.wd), { numeric = true, enter = function(v) o.wd = tonumber(v) or o.wd; C:Refresh() end })
    L:text(x + 204, L.y + 4, 60, "weekend", 10, T.grey); L:edit(x + 264, L.y, 40, "we", tostring(o.we), { numeric = true, enter = function(v) o.we = tonumber(v) or o.we; C:Refresh() end })
    L.y = L.y + 26
  end, nil, "Forecast dates use these hours per day.\nMeasured: your real average over the last 4 weeks, days off included, away dates left out. It needs 5 weekdays and 2 weekend days first.\nFallback: what to use until then. Press Enter to save.")
  L:card("Time away", function(L, x, w)
    for i, a in ipairs(o.away) do
      L:line(x, w - 24, { label = a.from:sub(6) .. "  to  " .. a.to:sub(6), value = a.hours .. " h / day", vcol = T.grey })
      L:iconbtn(x + w - 18, L.y - 19, 16, "Interface\\Buttons\\UI-StopButton", function() table.remove(o.away, i); C:Refresh() end, "Remove")
    end
    L:edit(x, L.y, 96, "awayFrom", C.form.awayFrom or "", { hint = "from" })
    L:edit(x + 102, L.y, 96, "awayTo", C.form.awayTo or "", { hint = "to" })
    L:edit(x + 204, L.y, 40, "awayH", C.form.awayH or "", { numeric = true, hint = "h" })
    L:button(x + w - 56, L.y, 56, 20, "Add", function()
      if C.ParseDate(C.form.awayFrom) and C.ParseDate(C.form.awayTo) then
        table.insert(o.away, { from = C.form.awayFrom, to = C.form.awayTo, hours = tonumber(C.form.awayH) or 0 })
        C.form.awayFrom, C.form.awayTo, C.form.awayH = nil, nil, nil; C:Refresh()
      else C:Print("dates must look like 2026-11-12.") end end, { on = true })
    L.y = L.y + 26
  end, nil, "Holidays or busy weeks: the hours you'll have each day in that range.\nDates look like 2026-11-12.")
  L:card("Options", function(L, x, w)
    local opts = { { "hud", "Pace tracker" }, { "lock", "Lock tracker position" }, { "popups", "Level-up banners" },
      { "sell", "Sell greys" }, { "repair", "Auto repair" }, { "nodeTips", "Node tips on veins and herbs", true } }
    local col = (w - 10) / 2
    for i, op in ipairs(opts) do
      local cx = x + ((i - 1) % 2) * (col + 10)
      local on = o[op[1]]
      if op[3] then on = on ~= false end
      L:check(cx, L.y, col, op[2], on, function()
        if op[3] then o[op[1]] = not (o[op[1]] ~= false) else o[op[1]] = not o[op[1]] end
        if op[1] == "hud" and C.hud then C.hud:SetShown(o.hud) end; C:Refresh() end)
      if i % 2 == 0 then L.y = L.y + 22 end
    end
    if #opts % 2 == 1 then L.y = L.y + 22 end
  end)
end

function C:BuildPanel(W)
  local L = newLay(W)
  local k = self:ViewKey()
  local b = BODY[self.tab] or BODY.Now
  b(L, k)
  return headerOps(W + 20), L.ops, L.y, tabOps(W + 20)
end

-- WoW backend ---------------------------------------------------------------------------------
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local measurer
function C.Measure(s, size, w, single)
  if not measurer then
    local holder = CreateFrame("Frame", nil, UIParent)
    holder:SetSize(1, 1); holder:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -2000, 2000); holder:SetAlpha(0)
    measurer = holder:CreateFontString(nil, "OVERLAY")
    measurer:SetPoint("TOPLEFT"); measurer:SetWordWrap(true); measurer:SetJustifyH("LEFT")
  end
  measurer:SetFont(FONT, size, "")
  measurer:SetWidth(single and 0 or w)
  measurer:SetText(s)
  if single then return measurer:GetStringWidth() end
  return math.ceil(measurer:GetStringHeight()) + 2
end

local function canvas(parent)
  local cv = CreateFrame("Frame", nil, parent)
  cv.tex, cv.fs, cv.hits, cv.eds, cv.plates = {}, {}, {}, {}, {}
  cv.bg = CreateFrame("Frame", nil, cv); cv.bg:SetAllPoints(); cv.bg:SetFrameLevel(cv:GetFrameLevel() + 1)
  cv.fg = CreateFrame("Frame", nil, cv); cv.fg:SetAllPoints(); cv.fg:SetFrameLevel(cv:GetFrameLevel() + 2)
  return cv
end
local function draw(cv, ops)
  local nt, nf, nh, ne, np = 0, 0, 0, 0, 0
  for _, o in ipairs(ops) do
    if o.k == "plate" then
      np = np + 1
      local p = cv.plates[np]
      if not p then p = C:Plate(cv.bg); cv.plates[np] = p end
      p:ClearAllPoints(); p:SetPoint("TOPLEFT", cv, "TOPLEFT", o.x, -o.y); p:SetSize(o.w, o.h); p:Show()
    elseif o.k == "tex" then
      nt = nt + 1
      local t = cv.tex[nt]
      if not t then t = cv.fg:CreateTexture(nil, "ARTWORK"); cv.tex[nt] = t end
      t:ClearAllPoints(); t:SetPoint("TOPLEFT", cv, "TOPLEFT", o.x, -o.y); t:SetSize(math.max(.01, o.w), math.max(.01, o.h))
      if o.atlas then if t.SetAtlas then t:SetAtlas(o.atlas) else t:SetColorTexture(0, 0, 0, 0) end; t:SetVertexColor(1, 1, 1, 1)
      elseif o.file then t:SetTexture(o.file); if o.col then t:SetVertexColor(o.col[1], o.col[2], o.col[3], o.col[4] or 1) else t:SetVertexColor(1, 1, 1, 1) end
      else t:SetColorTexture(o.col[1], o.col[2], o.col[3], o.col[4] or 1) end
      if o.atlas then
      elseif o.coords then t:SetTexCoord(o.coords[1], o.coords[2], o.coords[3], o.coords[4]) else t:SetTexCoord(0, 1, 0, 1) end
      if t.SetDesaturated then t:SetDesaturated(o.desat and true or false) end
      if o.round and t.SetMask and not t.craftMasked then pcall(t.SetMask, t, "Interface\\CharacterFrame\\TempPortraitAlphaMask"); t.craftMasked = true
      elseif not o.round and t.craftMasked then pcall(t.SetMask, t, ""); t.craftMasked = nil end
      t:Show()
    elseif o.k == "text" then
      nf = nf + 1
      local f = cv.fs[nf]
      if not f then f = cv.fg:CreateFontString(nil, "OVERLAY"); f:SetShadowOffset(1, -1); f:SetShadowColor(0, 0, 0, 1); cv.fs[nf] = f end
      f:SetFont(FONT, o.size, "")
      f:ClearAllPoints(); f:SetPoint("TOPLEFT", cv, "TOPLEFT", o.x, -o.y); f:SetWidth(o.w)
      f:SetJustifyH(o.j); f:SetJustifyV("TOP"); f:SetWordWrap(o.wrap and true or false)
      if not o.wrap then f:SetHeight(o.size + 3) else f:SetHeight(0) end
      f:SetTextColor(o.col[1], o.col[2], o.col[3]); f:SetText(o.s); f:Show()
    elseif o.k == "edit" then
      ne = ne + 1
      local e = cv.eds[ne]
      if not e then
        e = CreateFrame("EditBox", nil, cv); cv.eds[ne] = e
        e:SetAutoFocus(false); e:SetFontObject(ChatFontNormal); e:SetTextInsets(2, 2, 0, 0)
        e.hintFs = e:CreateFontString(nil, "OVERLAY"); e.hintFs:SetFont(FONT, 11, ""); e.hintFs:SetTextColor(.45, .41, .36); e.hintFs:SetPoint("LEFT", 3, 0)
        e:SetScript("OnTextChanged", function(s) if s.fid then C.form[s.fid] = s:GetText() end; s.hintFs:SetShown(s:GetText() == "" and not s:HasFocus()) end)
        e:SetScript("OnEditFocusGained", function(s) s.hintFs:Hide() end)
        e:SetScript("OnEditFocusLost", function(s) s.hintFs:SetShown(s:GetText() == "") end)
        e:SetScript("OnEnterPressed", function(s) if s.enter then s.enter(s:GetText()) end; s:ClearFocus() end)
        e:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
        e:SetScript("OnTabPressed", function(s) s:ClearFocus() end)
      end
      e:ClearAllPoints(); e:SetPoint("TOPLEFT", cv, "TOPLEFT", o.x, -o.y); e:SetSize(o.w, o.h)
      e.fid, e.enter = o.id, o.enter
      e:SetNumeric(o.numeric and true or false)
      if not e:HasFocus() then e:SetText(o.value or "") end
      e.hintFs:SetText(o.hint or ""); e.hintFs:SetShown((o.value or "") == "" and not e:HasFocus())
      e:SetFrameLevel(cv:GetFrameLevel() + 9); e:Show()
    elseif o.k == "hit" then
      nh = nh + 1
      local b = cv.hits[nh]
      if not b then
        b = CreateFrame("Button", nil, cv); cv.hits[nh] = b
        b:EnableMouse(true)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, .82, 0, .08)
        b:SetScript("OnClick", function(s) if s.click then PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856); s.click() end end)
        b:SetScript("OnEnter", function(s) if s.tip then GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); s.tip(GameTooltip); GameTooltip:Show() end end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
      end
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", cv, "TOPLEFT", o.x, -o.y); b:SetSize(o.w, o.h)
      b.click, b.tip = o.click, o.tip
      if type(o.tip) == "string" then
        local str = o.tip
        b.tip = function(t)
          local first = true
          for ln in (str .. "\n"):gmatch("(.-)\n") do
            if first then t:AddLine(ln); first = false else t:AddLine(ln, 1, 1, 1, true) end
          end
        end
      end
      b:EnableMouse(o.click ~= nil or o.tip ~= nil)
      b:SetFrameLevel(cv:GetFrameLevel() + 8); b:Show()
    end
  end
  for i = nt + 1, #cv.tex do cv.tex[i]:Hide() end
  for i = np + 1, #cv.plates do cv.plates[i]:Hide() end
  for i = nf + 1, #cv.fs do cv.fs[i]:Hide() end
  for i = nh + 1, #cv.hits do cv.hits[i]:Hide() end
  for i = ne + 1, #cv.eds do cv.eds[i]:Hide() end
end


local PW, PH, HEAD, FOOT = 460, 620, 106, 40
function C:CreateUI()
  if self.frame then return end
  local f = CreateFrame("Frame", "FWJFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(PW, PH)
  f:SetPoint("RIGHT", UIParent, "RIGHT", -60, 20)
  f:SetFrameStrata("MEDIUM"); f:SetToplevel(true)
  f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(s) s:StopMovingOrSizing(); local p, _, rp, x, y = s:GetPoint(); C.db.opt.pos = { p, rp, x, y } end)
  if f.SetBackdrop then
    f:SetBackdrop(C.PLATE); f:SetBackdropColor(.06, .06, .06, .97); f:SetBackdropBorderColor(.78, .73, .56, 1)
  end
  if C.db.opt.pos then local p = C.db.opt.pos; f:ClearAllPoints(); f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) end
  tinsert(UISpecialFrames, "FWJFrame")
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4); close:SetFrameLevel(f:GetFrameLevel() + 20)
  f.head = canvas(f); f.head:SetPoint("TOPLEFT", 10, -8); f.head:SetSize(PW - 20, HEAD)
  f.foot = canvas(f); f.foot:SetPoint("BOTTOMLEFT", 10, 8); f.foot:SetSize(PW - 20, FOOT)
  local sf = CreateFrame("ScrollFrame", "FWJScroll", f, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 20, -(8 + HEAD + 4)); sf:SetPoint("BOTTOMRIGHT", -32, 8 + FOOT)
  f.body = canvas(sf); f.body:SetSize(PW - 52, 10)
  sf:SetScrollChild(f.body)
  f.scroll = sf
  self.frame = f
  if not C.db.opt.shown then f:Hide() end
  f:SetScript("OnShow", function() C.db.opt.shown = true; C:Refresh() end)
  f:SetScript("OnHide", function() C.db.opt.shown = false end)
  if self.MinimapButton then self:MinimapButton() end
  if self.CreateHUD then self:CreateHUD() end
  self:Refresh()
end

function C:Refresh()
  if self.UpdateHUD then self:UpdateHUD() end
  local f = self.frame
  if not f or not f:IsShown() then return end
  local head, body, h, foot = self:BuildPanel(PW - 52)
  draw(f.head, head); draw(f.body, body); draw(f.foot, foot)
  f.body:SetHeight(math.max(10, h))
  local key = self.tab .. (self:ViewKey() or "")
  if self.lastTab ~= key then f.scroll:SetVerticalScroll(0); self.lastTab = key end
end

function C:Toggle()
  if not self.frame then self:CreateUI() end
  if self.frame:IsShown() then self.frame:Hide() else self.frame:Show() end
end
