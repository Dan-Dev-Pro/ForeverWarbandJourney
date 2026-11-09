-- Forever Warband Journey: session and daily tracking, rested XP, housekeeping
local C = FWJ

local DAY = 86400

local function today() return date("%Y-%m-%d") end

-- live /played: last server value plus time since it arrived
function C:PlayedNow()
  if not self.key then return nil end
  local c = self:Char(self.key)
  if not c or not c.played or not self.playedAt then return c.played end
  return c.played + (GetTime() - self.playedAt)
end

-- session ---------------------------------------------------------------------------
function C:StartSession()
  self.sess = { start = GetTime(), t = time(), xp = 0, lv0 = UnitLevel("player"), money0 = GetMoney(), cloth = 0, kills = {}, lastXP = UnitXP("player"), lastMax = UnitXPMax("player") }
end

function C:OnXP()
  local s = self.sess
  if not s then return end
  local xp, mx = UnitXP("player"), UnitXPMax("player")
  local d = xp - s.lastXP
  if d < 0 then d = (s.lastMax - s.lastXP) + xp end
  if d > 0 then
    s.xp = s.xp + d
    s.recent = s.recent or {}
    table.insert(s.recent, { GetTime(), d })
  end
  s.lastXP, s.lastMax = xp, mx
end

-- XP per hour over the last 20 minutes of play (falls back to the whole session)
function C:XPRate()
  local s = self.sess
  if not s then return 0 end
  local now, win, sum = GetTime(), 1200, 0
  local first
  for _, r in ipairs(s.recent or {}) do
    if now - r[1] <= win then sum = sum + r[2]; first = first or r[1] end
  end
  local span = math.min(win, now - s.start)
  if span < 120 then return 0 end
  if sum > 0 then return sum / span * 3600 end
  return s.xp / (now - s.start) * 3600
end

function C:KillXP(msg)
  local n = tonumber((msg or ""):match("dies, you gain (%d+) experience"))
  if not n or not self.sess then return end
  local k = self.sess.kills
  k[#k + 1] = n
  if #k > 25 then table.remove(k, 1) end
end
function C:KillsToLevel()
  local k = self.sess and self.sess.kills or {}
  if #k < 3 then return nil end
  local sum = 0
  for _, v in ipairs(k) do sum = sum + v end
  local avg = sum / #k
  return math.max(0, math.ceil((UnitXPMax("player") - UnitXP("player")) / avg)), avg
end

function C:OnLoot(msg)
  if not self.sess or not msg then return end
  local id = tonumber(msg:match("item:(%d+)"))
  if id and C.CLOTH[id] then
    self.sess.cloth = self.sess.cloth + (tonumber(msg:match("x(%d+)")) or 1)
  end
  if id and C.ITEM and C.ITEM[id] and not msg:find("^You create") then
    self.sess.mats = self.sess.mats or {}
    self.sess.mats[id] = (self.sess.mats[id] or 0) + (tonumber(msg:match("x(%d+)")) or 1)
  end
end

-- per-day ledger: hours played and levels gained, per character
function C:TickDay()
  local k = self.key
  if not k then return end
  local p = self:PlayedNow()
  if not p then return end
  local d = self.db.days[today()] or {}
  self.db.days[today()] = d
  local e = d[k] or { p0 = p, l0 = self:Lv(k) }
  e.p1, e.l1 = p, self:Lv(k)
  d[k] = e
  -- prune to 60 days
  local cut = date("%Y-%m-%d", time() - 60 * DAY)
  for day in pairs(self.db.days) do if day < cut then self.db.days[day] = nil end end
end

function C:DayStats(day)
  local d = self.db.days[day]
  local h, l = 0, {}
  if d then
    for k, e in pairs(d) do
      h = h + math.max(0, (e.p1 or e.p0) - e.p0) / 3600
      local g = (e.l1 or e.l0) - e.l0
      if g > 0.01 then l[#l + 1] = string.format("%s +%.1f", C:Short(k), g) end
    end
  end
  return h, l
end

function C:WeekPlayed()
  local t = time()
  local wday = date("*t", t).wday               -- 1 = Sunday
  local back = (wday + 5) % 7                     -- days since Monday
  local h, plan = 0, 0
  for i = 0, back do
    local day = t - i * DAY
    h = h + self:DayStats(date("%Y-%m-%d", day))
  end
  local mon = self:Midnight(t - back * DAY)
  for i = 0, 6 do plan = plan + self:DayHours(mon + i * DAY) end
  return h, plan, mon
end

function C:EndSession()
  local s = self.sess
  if not s or not self.key then return end
  local list = self.db.sessions
  list[#list + 1] = {
    t = s.t, ch = self.key, mins = math.floor((GetTime() - s.start) / 60), xp = s.xp,
    lv0 = s.lv0, lv1 = UnitLevel("player"), gold = GetMoney() - s.money0, cloth = s.cloth,
  }
  while #list > 60 do table.remove(list, 1) end
end

-- rested XP ---------------------------------------------------------------------------
function C:SaveRested()
  local k = self.key
  if not k then return end
  local c = self:Char(k)
  c.rested = GetXPExhaustion() or 0
  c.restedAt = time()
  c.inInn = IsResting() and true or false
end

-- estimated rested % of a level now: 5% per 8 h in an inn (a quarter of that outside), cap 150%
function C:RestedPct(k)
  local c = self:Char(k)
  if k == self.key then
    local r = GetXPExhaustion() or 0
    return r / math.max(1, UnitXPMax("player")) * 100, nil
  end
  if not c.restedAt then return nil end
  local pct = (c.rested or 0) / math.max(1, c.xpMax or 1) * 100
  local rate = (c.inInn and 5 or 1.25) / (8 * 3600)
  local now = pct + (time() - c.restedAt) * rate
  local full
  if now < 150 then full = time() + (150 - now) / rate end
  return math.min(150, now), full
end

-- Dedicated Study: 23 h cooldown, remembered per character
function C:OnSpell(spellID)
  local name = GetSpellInfo and GetSpellInfo(spellID) or (C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID) or {}).name
  if name == "Dedicated Study" and self.key then
    self:Char(self.key).study = time()
    self:Print("Dedicated Study cast. Ready again " .. date("%a %H:%M", time() + 23 * 3600) .. ".")
  end
end
function C:StudyReady(k)
  local t = self:Char(k).study
  if not t then return nil end
  return t + 23 * 3600
end

-- housekeeping -------------------------------------------------------------------------
local function cslots(bag) if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) end return GetContainerNumSlots(bag) end
local function cinfo(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local i = C_Container.GetContainerItemInfo(bag, slot)
    if i then return i.itemID, i.hyperlink, i.quality, i.isBound, i.stackCount, i.hasNoValue end
    return
  end
  local _, count, _, quality, _, _, link, _, noValue, id, bound = GetContainerItemInfo(bag, slot)
  return id, link, quality, bound, count, noValue
end
C.CSlots, C.CInfo = cslots, cinfo
local function cuse(bag, slot) if C_Container and C_Container.UseContainerItem then C_Container.UseContainerItem(bag, slot) else UseContainerItem(bag, slot) end end
local function cpick(bag, slot) if C_Container and C_Container.PickupContainerItem then C_Container.PickupContainerItem(bag, slot) else PickupContainerItem(bag, slot) end end
C.cslots, C.cinfo = cslots, cinfo

function C:OnMerchant()
  local o = self.db.opt
  if o.repair and CanMerchantRepair and CanMerchantRepair() then
    local cost, can = GetRepairAllCost()
    if can and cost > 0 and cost <= GetMoney() then RepairAllItems(); self:Print("repaired for " .. C.Money(cost) .. ".") end
  end
  if o.sell then
    local total, n = 0, 0
    for bag = 0, 4 do
      for slot = 1, (cslots(bag) or 0) do
        local _, link, q, _, count, noValue = cinfo(bag, slot)
        if link and q == 0 and not noValue then
          local price = select(11, GetItemInfo(link)) or 0
          if price > 0 then total = total + price * (count or 1); n = n + 1; cuse(bag, slot) end
        end
      end
    end
    if n > 0 then self:Print(string.format("sold %d grey item%s for %s.", n, n > 1 and "s" or "", C.Money(total))) end
  end
end

function C:CheckDurability()
  local low = 100
  for slot = 1, 18 do
    local cur, mx = GetInventoryItemDurability(slot)
    if cur and mx and mx > 0 then low = math.min(low, cur / mx * 100) end
  end
  self.durability = low
  if low <= 25 and not self.warnedDur then
    self.warnedDur = true
    self:Print(string.format("|cffff6060gear at %d%% durability|r. Repair before the next dungeon.", low))
  elseif low > 50 then self.warnedDur = nil end
end

function C:FreeSlots()
  local free = 0
  for bag = 0, 4 do
    local f, bagType
    if C_Container and C_Container.GetContainerNumFreeSlots then f, bagType = C_Container.GetContainerNumFreeSlots(bag) else f, bagType = GetContainerNumFreeSlots(bag) end
    if f and (bagType == 0 or bagType == nil) then free = free + f end
  end
  return free
end
function C:CheckBags()
  local f = self:FreeSlots()
  self.freeSlots = f
  if f <= 2 and not self.warnedBags then self.warnedBags = true; self:Print("|cffff6060" .. f .. " bag slot" .. (f == 1 and "" or "s") .. " left.|r")
  elseif f > 4 then self.warnedBags = nil end
end

-- mail drafting: fill a mail to the crafter with cloth and BoEs (you still press Send)
function C:MailItems()
  local out = {}
  for bag = 0, 4 do
    for slot = 1, (cslots(bag) or 0) do
      local id, link, q, bound = cinfo(bag, slot)
      if id and link then
        local eq = (C_Item and C_Item.IsEquippableItem and C_Item.IsEquippableItem(link)) or (IsEquippableItem and IsEquippableItem(link))
        if C.CLOTH[id] or (not bound and q and q >= 2 and q <= 4 and eq) then out[#out + 1] = { bag, slot, link } end
      end
    end
  end
  return out
end
function C:FillMail()
  if not SendMailFrame then return end
  if MailFrameTab_OnClick then MailFrameTab_OnClick(nil, 2) end
  local ck = self:CharWithRole("Crafter")
  if not ck or ck == self.key then self:Print("set a Crafter on the Warband tab first.") return end
  local to = self:Char(ck).name
  if SendMailNameEditBox then SendMailNameEditBox:SetText(to) end
  if SendMailSubjectEditBox then SendMailSubjectEditBox:SetText("Cloth and BoEs") end
  local items, n = self:MailItems(), 0
  for _, it in ipairs(items) do
    if n >= 12 then break end
    ClearCursor()
    cpick(it[1], it[2])
    n = n + 1
    ClickSendMailItemButton(n)
  end
  ClearCursor()
  self:Print(n > 0 and ("loaded " .. n .. " item" .. (n > 1 and "s" or "") .. " for " .. to .. ". Check and press Send.") or "nothing to send.")
end
function C:MailButton()
  local ck = self:CharWithRole("Crafter")
  if self.mailBtn then self.mailBtn:SetShown(ck and ck ~= self.key) return end
  if not SendMailFrame or not ck or ck == self.key then return end
  local b = CreateFrame("Button", nil, MailFrame, "UIPanelButtonTemplate")
  b:SetSize(130, 22)
  b:SetPoint("TOPRIGHT", MailFrame, "TOPRIGHT", -40, -30)
  b:SetText("FWJ: fill for crafter")
  b:SetScript("OnClick", function() C:FillMail() end)
  self.mailBtn = b
end

-- events -------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_XP_UPDATE", "CHAT_MSG_COMBAT_XP_GAIN", "CHAT_MSG_LOOT", "MERCHANT_SHOW",
  "UPDATE_INVENTORY_DURABILITY", "BAG_UPDATE_DELAYED", "PLAYER_UPDATE_RESTING", "UPDATE_EXHAUSTION", "UNIT_SPELLCAST_SUCCEEDED",
  "PLAYER_LOGOUT", "MAIL_SHOW", "TIME_PLAYED_MSG" }) do ev:RegisterEvent(e) end
ev:SetScript("OnEvent", function(_, e, a1, a2, a3)
  if not C.db then return end
  if e == "PLAYER_ENTERING_WORLD" then
    if not C.sess then C:StartSession() end
    C:CheckDurability(); C:CheckBags(); C:SaveRested()
  elseif e == "TIME_PLAYED_MSG" then
    if C.key then C:Char(C.key).played = a1 end
    C.playedAt = GetTime(); C:TickDay()
  elseif e == "PLAYER_XP_UPDATE" then C:OnXP()
  elseif e == "CHAT_MSG_COMBAT_XP_GAIN" then C:KillXP(a1)
  elseif e == "CHAT_MSG_LOOT" then C:OnLoot(a1)
  elseif e == "MERCHANT_SHOW" then C:OnMerchant()
  elseif e == "UPDATE_INVENTORY_DURABILITY" then C:CheckDurability()
  elseif e == "BAG_UPDATE_DELAYED" then C:CheckBags(); if C.ScanBags then C:ScanBags() end
  elseif e == "PLAYER_UPDATE_RESTING" or e == "UPDATE_EXHAUSTION" then C:SaveRested()
  elseif e == "UNIT_SPELLCAST_SUCCEEDED" then if a1 == "player" then C:OnSpell(a3) end
  elseif e == "MAIL_SHOW" then C:MailButton(); if C.MailHelper then C:MailHelper() end
  elseif e == "PLAYER_LOGOUT" then C:TickDay(); C:SaveRested(); C:EndSession()
  end
end)

C_Timer.NewTicker(30, function() if C.db then C:TickDay() end end)
