-- Forever Warband Journey: the pace tracker
local C = FWJ
local DAY = 86400

local function short(n) if n >= 1000 then return string.format("%.1fk", n / 1000) end return tostring(math.floor(n)) end
local function dur(sec)
  if not sec or sec ~= sec or sec == math.huge or sec < 0 then return "-" end
  if sec >= 3600 then return string.format("%dh %02dm", sec / 3600, (sec % 3600) / 60) end
  return string.format("%dm", math.max(1, sec / 60))
end
local function ccode(k)
  local c = C:Char(k)
  local cc = c and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.classFile or ""]
  if cc then return string.format("|cff%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255) end
  return "|cffffffff"
end
C.ccode = ccode

-- plate look: Blizzard's glue tooltip frame, dark fill with a parchment edge (the style Journey uses)
C.PLATE = { bgFile = "Interface\\Glues\\Common\\Glue-Tooltip-Background", edgeFile = "Interface\\Glues\\Common\\Glue-Tooltip-Border",
  tile = true, tileEdge = true, tileSize = 16, edgeSize = 16, insets = { left = 10, right = 5, top = 4, bottom = 9 } }
function C:Plate(parent)
  local p = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  if p.SetBackdrop then
    p:SetBackdrop(C.PLATE); p:SetBackdropColor(.09, .09, .09, 1); p:SetBackdropBorderColor(.78, .73, .56, 1)
  end
  p:EnableMouse(false)
  return p
end
local HW = 236
local CIRCLES = "Interface\\TargetingFrame\\UI-Classes-Circles"
local TC = { WARRIOR = { 0, .25, 0, .25 }, MAGE = { .25, .49609375, 0, .25 }, ROGUE = { .49609375, .7421875, 0, .25 }, DRUID = { .7421875, .98828125, 0, .25 },
  HUNTER = { 0, .25, .25, .5 }, SHAMAN = { .25, .49609375, .25, .5 }, PRIEST = { .49609375, .7421875, .25, .5 }, WARLOCK = { .7421875, .98828125, .25, .5 },
  PALADIN = { 0, .25, .5, .75 } }
local ROWS = { "tonight", "craft", "week", "goal", "target", "raids", "journey" }
local LABEL = { tonight = "Tonight", craft = "Crafting", week = "This week", goal = "Goal", target = "Target", raids = "Raids", journey = "Journey" }

function C:CreateHUD()
  if self.hud then return end
  local f = CreateFrame("Frame", "FWJPace", UIParent)
  f:SetSize(HW + 26, 150)
  f:SetPoint("TOP", UIParent, "TOP", 0, -120)
  f:SetFrameStrata("LOW")
  f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(s) if not C.db.opt.lock then s:StartMoving() end end)
  f:SetScript("OnDragStop", function(s) s:StopMovingOrSizing(); local p, _, rp, x, y = s:GetPoint(); C.db.opt.hudpos = { p, rp, x, y } end)
  f:SetScript("OnMouseUp", function(_, btn) if btn == "RightButton" then C:Toggle() end end)
  if C.db.opt.hudpos then local p = C.db.opt.hudpos; f:ClearAllPoints(); f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) end

  -- header plate
  local h = C:Plate(f)
  h:SetSize(HW, 50); h:SetPoint("TOPLEFT", 26, 0)
  f.head = h
  local por = h:CreateTexture(nil, "OVERLAY", nil, 1)
  por:SetSize(34, 34); por:SetPoint("CENTER", h, "LEFT", 0, 2)
  por:SetTexture(CIRCLES)
  local ring = h:CreateTexture(nil, "OVERLAY", nil, 2)
  ring:SetSize(52, 52); ring:SetPoint("CENTER", por, "CENTER", 0, 0)
  if ring.SetAtlas then ring:SetAtlas("auctionhouse-itemicon-border-artifact") end
  f.por = por
  local function fs(parent, tmpl, justify)
    local t = parent:CreateFontString(nil, "OVERLAY", tmpl)
    t:SetJustifyH(justify or "LEFT"); t:SetWordWrap(false)
    return t
  end
  f.name = fs(h, "GameFontNormal"); f.name:SetPoint("TOPLEFT", 30, -9)
  f.status = fs(h, "GameFontNormalSmall", "RIGHT"); f.status:SetPoint("TOPRIGHT", -10, -10)
  f.sub = fs(h, "GameFontHighlightSmall"); f.sub:SetPoint("TOPLEFT", 30, -25)
  f.subR = fs(h, "GameFontHighlightSmall", "RIGHT"); f.subR:SetPoint("TOPRIGHT", -10, -25)
  -- thin XP bar with a gold mark at your on-pace point
  local track = h:CreateTexture(nil, "ARTWORK", nil, 1)
  track:SetPoint("BOTTOMLEFT", 30, 12); track:SetPoint("BOTTOMRIGHT", -10, 12); track:SetHeight(4); track:SetColorTexture(.04, .4, .68, .3)
  local fill = h:CreateTexture(nil, "ARTWORK", nil, 2)
  fill:SetPoint("TOPLEFT", track, "TOPLEFT"); fill:SetHeight(4); fill:SetColorTexture(.12, .55, .9, 1)
  local mark = h:CreateTexture(nil, "ARTWORK", nil, 3)
  mark:SetSize(2, 8); mark:SetColorTexture(1, .82, 0, 1)
  f.track, f.fill, f.mark = track, fill, mark

  -- detail plate: label on the left, value on the right
  local d = C:Plate(f)
  d:SetPoint("TOPLEFT", h, "BOTTOMLEFT", -14, 3); d:SetWidth(HW + 14)
  f.det = d
  f.rows = {}
  for _, key in ipairs(ROWS) do
    local r = { key = key }
    r.l = fs(d, "GameFontNormalSmall"); r.l:SetText(LABEL[key]); r.l:SetTextColor(.78, .73, .56)
    r.v = fs(d, "GameFontHighlightSmall", "RIGHT")
    r.l:SetWidth(70)
    f.rows[key] = r
  end
  local bar = d:CreateTexture(nil, "ARTWORK", nil, 1)
  bar:SetHeight(3); bar:SetColorTexture(.04, .4, .68, .3)
  local bfill = d:CreateTexture(nil, "ARTWORK", nil, 2)
  bfill:SetHeight(3); bfill:SetColorTexture(.12, .55, .9, 1)
  f.wbar, f.wfill = bar, bfill
  f:SetScript("OnEnter", function(s) C:HUDTooltip(s) end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  self.hud = f
  if not C.db.opt.hud then f:Hide() end
  C_Timer.NewTicker(2, function() C:UpdateHUD() end)
  self:UpdateHUD()
end

local function hm(sec)
  sec = math.max(0, sec or 0)
  local m = sec / 60
  if m >= 60 then return string.format("%dh %02dm", m / 60, m % 60) end
  return string.format("%dm", m)
end
local GREEN, RED, GOLD, DIM = "|cff4ce04c", "|cffff6060", "|cffffd100", "|cffa89a84"

function C:UpdateHUD()
  local f = self.hud
  if not f or not f:IsShown() then return end
  local k = self.key
  local c = self:Char(k)
  if not c then return end
  if self.JourneyTick then self:JourneyTick() end
  local lv = self:Lv(k)
  local max = UnitLevel("player") >= 60

  -- header
  local tc = TC[c.classFile or ""] or (CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[c.classFile or ""])
  if tc then f.por:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) end
  local mine = self:NextGoalFor(k)
  f.name:SetText(ccode(k) .. self:Short(k) .. "|r  |cffffffff" .. string.format("%.1f", lv) .. "|r" .. (mine and (DIM .. "  to " .. mine.to .. "|r") or ""))
  local g = self:ActiveGoal()
  if g and g.ch == k then
    -- overall pace on the goal, in hours of play
    local gh = self:GoalAheadHours(g)
    -- ahead of the goal = spare time you can spend on crafting (or anything) and still be on plan
    if gh and math.abs(gh) >= 1 / 6 then f.status:SetText(gh > 0 and (GREEN .. hm(gh * 3600) .. " spare|r") or (RED .. hm(-gh * 3600) .. " behind|r"))
    elseif gh then f.status:SetText(GOLD .. "on plan|r")
    else f.status:SetText(GOLD .. "active goal|r") end
  elseif g then f.status:SetText(DIM .. "plan says " .. self:Short(g.ch) .. "|r")
  else f.status:SetText(#self.db.goals == 0 and (DIM .. "no goals|r") or (GREEN .. "goals done|r")) end

  local live = self.LevelLive and self:LevelLive()
  if live then
    f.sub:SetText(string.format("%slevel|r %s %s/ %s|r", DIM, hm(live.spent), DIM, hm(live.est)))
    f.subR:SetText(live.ahead >= 0 and (GREEN .. hm(live.ahead) .. " ahead|r") or (RED .. hm(-live.ahead) .. " behind|r"))
  elseif not max then
    f.sub:SetText(DIM .. "Level time shows after /played loads|r"); f.subR:SetText("")
  else f.sub:SetText("Level 60"); f.subR:SetText("") end
  local mx = UnitXPMax("player") or 0
  local frac = mx > 0 and (UnitXP("player") or 0) / mx or 0
  local tw = f.track:GetWidth() or 0
  if tw <= 0 then tw = HW - 40 end
  f.fill:SetWidth(math.max(.01, tw * math.min(1, frac)))
  if live and live.est > 0 then
    f.mark:ClearAllPoints(); f.mark:SetPoint("CENTER", f.track, "LEFT", tw * math.min(1, live.spent / live.est), 0); f.mark:Show()
  else f.mark:Hide() end

  -- detail rows
  local val = {}
  local tn = not max and self.Tonight and self:Tonight(k)
  if tn then
    if tn.onPlan and tn.target <= lv then val.tonight = GREEN .. "on plan|r"
    elseif tn.left > 0 then val.tonight = string.format("%s%.1f|r %sin %.1f h%s", GOLD, tn.target, DIM, tn.left, tn.onPlan and " (plan)" or "") .. "|r"
    else val.tonight = DIM .. "bonus time|r" end
  end
  local bt = self.BusyToday and self:BusyToday() or 0
  if bt >= 60 then val.craft = hm(bt) .. DIM .. " today|r" end
  local played, plan = self:WeekPlayed()
  val.week = string.format("%.1f %s/ %d h|r", played, DIM, plan)
  local now = time()
  local fin = self:FinalGoal()
  local rows = self:Forecast()
  local tgt = self:Target()
  if fin and rows[fin.id] and rows[fin.id].at > 0 then
    local at = rows[fin.id].at
    local late = tgt and at > tgt
    val.goal = string.format("%s %d  %s%s|r", self:Short(fin.ch), fin.to, late and RED or GREEN, date("%a %d %b", at))
  end
  if fin and tgt and tgt > now then
    local days = (tgt - now) / DAY
    local hrs = 0
    for _, gg in ipairs(self.db.goals) do local r = rows[gg.id]; if r then hrs = hrs + r.h end; if gg == fin then break end end
    val.target = string.format("%s  %s%.1f h/day|r", date("%d %b", tgt), DIM, hrs / days)
  end
  val.raids = string.format("%d days", math.ceil((C.RAIDS - now) / DAY))
  local jg, jstep
  if self.JourneyNow then jg, jstep = self:JourneyNow() end
  if jg then
    local sec, st = (jstep or ""):match("^(%d+)%-(%w+)$")
    val.journey = self:JourneyName(jg) .. (sec and string.format("  %s%d.%s|r", DIM, tonumber(sec), (st:gsub("^0+(%d)", "%1"))) or "")
  end
  local y = -11
  for _, key in ipairs(ROWS) do
    local r = f.rows[key]
    if val[key] then
      r.l:ClearAllPoints(); r.l:SetPoint("TOPLEFT", 14, y)
      r.v:ClearAllPoints(); r.v:SetPoint("TOPRIGHT", -10, y); r.v:SetPoint("LEFT", r.l, "RIGHT", 4, 0)
      r.v:SetText(val[key]); r.l:Show(); r.v:Show()
      y = y - 15
      if key == "week" then
        f.wbar:ClearAllPoints(); f.wbar:SetPoint("TOPLEFT", 14, y + 1); f.wbar:SetPoint("TOPRIGHT", -10, y + 1)
        local bw = f.wbar:GetWidth() or 0
        if bw <= 0 then bw = HW - 10 end
        f.wfill:ClearAllPoints(); f.wfill:SetPoint("TOPLEFT", f.wbar, "TOPLEFT")
        f.wfill:SetWidth(math.max(.01, bw * math.min(1, played / math.max(.1, plan))))
        y = y - 7
      end
    else r.l:Hide(); r.v:Hide() end
  end
  local dh = -y + 12
  f.det:SetHeight(dh); f:SetHeight(50 - 3 + dh)
end

function C:HUDTooltip(owner)
  GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
  GameTooltip:AddLine(C.NAME)
  GameTooltip:AddLine("Last 7 days", 1, .82, 0)
  for i = 0, 6 do
    local day = date("%Y-%m-%d", time() - i * DAY)
    local h, l = self:DayStats(day)
    GameTooltip:AddDoubleLine(date("%a %d", time() - i * DAY) .. (i == 0 and " (today)" or ""), string.format("%.1f h  %s", h, table.concat(l, ", ")), .8, .8, .8, 1, 1, 1)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Rested XP", 1, .82, 0)
  for _, k in ipairs(self:Plan()) do
    local pct, full = self:RestedPct(k)
    if pct then GameTooltip:AddDoubleLine(self:Short(k), string.format("%d%%%s", pct, full and ("  full " .. date("%a %H:%M", full)) or (pct >= 150 and "  full" or "")), .8, .8, .8, 1, 1, 1) end
  end
  if self.sess then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("This session", 1, .82, 0)
    GameTooltip:AddDoubleLine("Time", dur(GetTime() - self.sess.start), .8, .8, .8, 1, 1, 1)
    GameTooltip:AddDoubleLine("XP", short(self.sess.xp), .8, .8, .8, 1, 1, 1)
    local rate = self:XPRate()
    if rate > 0 then
      GameTooltip:AddDoubleLine("XP an hour", short(rate), .8, .8, .8, 1, 1, 1)
      GameTooltip:AddDoubleLine("Next level at this rate", dur((UnitXPMax("player") - UnitXP("player")) / rate * 3600), .8, .8, .8, 1, 1, 1)
    end
    GameTooltip:AddDoubleLine("Gold", C.Money(GetMoney() - self.sess.money0), .8, .8, .8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Cloth looted", tostring(self.sess.cloth), .8, .8, .8, 1, 1, 1)
  end
  if self.durability then GameTooltip:AddDoubleLine("Durability / free slots", string.format("%d%% / %d", self.durability, self.freeSlots or 0), .8, .8, .8, 1, 1, 1) end
  if self.JourneyTooltip then self:JourneyTooltip(GameTooltip) end
  local bind = GetBindLocation and GetBindLocation()
  if bind then GameTooltip:AddDoubleLine("Hearth", bind, .8, .8, .8, 1, 1, 1) end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Drag to move. Right-click for the full panel.", .6, .6, .6)
  GameTooltip:Show()
end
