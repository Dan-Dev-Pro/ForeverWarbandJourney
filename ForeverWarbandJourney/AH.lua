-- Forever Warband Journey: Auction House prices for the profession shopping list.
-- Works with the modern Auction House (C_AuctionHouse) and the classic one (QueryAuctionItems).
local C = FWJ

-- cost to buy n of an item from the last scan: walks the cheapest listings first
function C:BuyCost(id, n)
  local p = self.db.prices and self.db.prices[id]
  if not p or not p.l or #p.l == 0 then return nil end
  local left, total = n, 0
  for _, l in ipairs(p.l) do
    local take = math.min(left, l[2])
    total = total + take * l[1]; left = left - take
    if left <= 0 then break end
  end
  return total, left > 0 and (n - left) or n, p.t
end

-- one-step conversion for an intermediate (bars, bronze, bolts, grinding stones). The game's own recipe
-- (read from your profession window) wins over the built-in one.
function C:Conv0(id)
  local live = self.db and self.db.conv and self.db.conv[id]
  if live then return { p = C.CONV0[id] and C.CONV0[id].p or "Mining", n = 1, r = live } end
  return C.CONV0[id]
end
function C:HasProf(p)
  for _, c in pairs(self.db.chars) do if c.profs and c.profs[p] then return true end end
  return false
end
function C:HavePrices() return self.db.prices and next(self.db.prices) ~= nil end

-- cheapest unit cost of an item: vendor, Auction House (priced on 20 units, so a lone cheap listing
-- doesn't win), or making it from its parts if someone on the account has that profession
local ucache, ucv = {}, -1
function C:UnitCost(id, depth)
  local v = (self.priceV or 0) * 1000 + (self.convV or 0)
  if ucv ~= v then ucache, ucv = {}, v end
  local hit = ucache[id]
  if hit then return hit.c or nil, hit.how end
  depth = depth or 0
  local best, how
  local it = C.ITEM[id]
  if it and it[2] == "vendor" and it[3] then best, how = it[3], "vendor" end
  local cost, got = self:BuyCost(id, 20)
  if cost and got > 0 then
    local u = cost / got
    if not best or u < best then best, how = u, "ah" end
  end
  local cv = depth < 3 and self:Conv0(id)
  if cv and self:HasProf(cv.p) then
    local sum, ok = 0, true
    for _, m in ipairs(cv.r) do
      local u = self:UnitCost(m[1], depth + 1)
      if not u then ok = false; break end
      sum = sum + u * m[2]
    end
    if ok then
      local u = sum / cv.n
      if not best or u < best then best, how = u, "craft" end
    end
  end
  ucache[id] = { c = best or false, how = how }
  return best, how
end

-- every material that could matter between your skill and the target: direct reagents of every
-- recipe usable in that range, plus what those are made from (ore for bars, cloth for bolts...)
function C:ScanSet(k)
  local c = self:Char(k)
  local set, list = {}, {}
  local function add(id, depth)
    if set[id] then return end
    set[id] = true
    local it = C.ITEM[id]
    if not (it and it[2] == "vendor") then list[#list + 1] = id end
    local cv = depth < 3 and self:Conv0(id)
    if cv then for _, m in ipairs(cv.r) do add(m[1], depth + 1) end end
  end
  for prof, v in pairs(c and c.profs or {}) do
    if C.RECIPES[prof] then
      local skill, to = v[1], self:RecSkill(k, v[1])
      local known = c.known and c.known[prof]
      for name, rec in pairs(self:RecipesFor(k, prof)) do
        local live = known and known[name]
        local usable = live and live[1] ~= "grey" or (not live and rec.l < to and rec.g > skill)
        if usable then for _, m in ipairs(rec.r) do add(m[1], 0) end end
      end
    end
  end
  return list
end

-- scanning ------------------------------------------------------------------------------------
local queue, current, timer = {}, nil, nil
local MODERN = C_AuctionHouse and C_AuctionHouse.SendSearchQuery
local function store(id, listings)
  table.sort(listings, function(a, b) return a[1] < b[1] end)
  local keep = {}
  for i = 1, math.min(30, #listings) do keep[i] = listings[i] end
  C.db.prices = C.db.prices or {}
  C.db.prices[id] = { t = time(), l = keep }
  C.priceV = (C.priceV or 0) + 1
end
local nextQuery
local function finish()
  if timer then timer:Cancel(); timer = nil end
  current = nil
  if C.ahPanel then C:AHRefresh() end
  if #queue > 0 then C_Timer.After(.4, nextQuery) else C.scanning = false; if C.ahPanel then C:AHRefresh() end end
end
nextQuery = function()
  if #queue == 0 then C.scanning = false; return end
  if not MODERN and CanSendAuctionQuery and not CanSendAuctionQuery() then C_Timer.After(.5, nextQuery); return end
  current = table.remove(queue, 1)
  if MODERN then
    local key = C_AuctionHouse.MakeItemKey(current)
    C_AuctionHouse.SendSearchQuery(key, { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }, false)
  else
    local name = C.ITEM[current] and C.ITEM[current][1] or (GetItemInfo(current))
    if not name then finish(); return end
    QueryAuctionItems(name, nil, nil, 0, false, nil, false, true)
  end
  timer = C_Timer.NewTimer(4, function() timer = nil; if current then store(current, {}); finish() end end)
end
function C:ScanPrices(ids)
  queue = {}
  for _, id in ipairs(ids) do queue[#queue + 1] = id end
  self.scanning = true
  self.scanTotal = #queue
  nextQuery()
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "AUCTION_ITEM_LIST_UPDATE" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, e, a1)
  if not C.db then return end
  if e == "AUCTION_HOUSE_SHOW" then C:AHShow()
  elseif e == "AUCTION_HOUSE_CLOSED" then
    queue = {}; current = nil; C.scanning = false
    if C.ahPanel then C.ahPanel:Hide() end
    -- you scanned and (probably) bought: lock the route so it stops shifting as you craft
    if C.scannedThisVisit then C.scannedThisVisit = nil; C:LockAll(C.key) end
  elseif not current then return
  elseif e == "COMMODITY_SEARCH_RESULTS_UPDATED" and a1 == current then
    local l = {}
    for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(current) or 0 do
      local r = C_AuctionHouse.GetCommoditySearchResultInfo(current, i)
      if r and r.unitPrice then l[#l + 1] = { r.unitPrice, r.quantity or 1 } end
    end
    store(current, l); finish()
  elseif e == "ITEM_SEARCH_RESULTS_UPDATED" and a1 and a1.itemID == current then
    local l = {}
    for i = 1, C_AuctionHouse.GetNumItemSearchResults(a1) or 0 do
      local r = C_AuctionHouse.GetItemSearchResultInfo(a1, i)
      if r and r.buyoutAmount then l[#l + 1] = { r.buyoutAmount / math.max(1, r.quantity or 1), r.quantity or 1 } end
    end
    store(current, l); finish()
  elseif e == "AUCTION_ITEM_LIST_UPDATE" then
    local l = {}
    for i = 1, GetNumAuctionItems("list") or 0 do
      local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemId = GetAuctionItemInfo("list", i)
      if itemId == current and buyout and buyout > 0 and count and count > 0 then l[#l + 1] = { buyout / count, count } end
    end
    store(current, l); finish()
  end
end)

-- panel beside the Auction House ---------------------------------------------------------------
local function money(c)
  if not c then return "-" end
  c = math.floor(c + .5)
  local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  if g > 0 then return string.format("%d|cffffd100g|r %02d|cffc7c7cfs|r", g, s) end
  if s > 0 then return string.format("%d|cffc7c7cfs|r %02d|cffeda55fc|r", s, cp) end
  return string.format("%d|cffeda55fc|r", cp)
end
C.MoneyText = money

function C:AHShow()
  local host = AuctionHouseFrame or AuctionFrame
  if not host then return end
  if not self.ahPanel then
    local f = self:Plate(host)
    f:SetSize(300, 200)
    f:SetPoint("TOPLEFT", host, "TOPRIGHT", 4, 0)
    f:EnableMouse(true)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.title:SetPoint("TOPLEFT", 16, -12)
    f.title:SetText("FWJ shopping list")
    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); f.sub:SetPoint("TOPLEFT", 16, -28); f.sub:SetPoint("RIGHT", -12, 0); f.sub:SetJustifyH("LEFT")
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(96, 20); b:SetPoint("TOPRIGHT", -10, -9); b:SetText("Scan prices")
    b:SetScript("OnClick", function() C:ScanShopping() end)
    f.btn = b
    f.rows = {}
    f.total = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.total:SetJustifyH("RIGHT")
    self.ahPanel = f
  end
  self.ahPanel:Show()
  self:AHRefresh()
end

function C:ScanShopping()
  self.scannedThisVisit = true
  self:ScanPrices(self:ScanSet(self.key)); self:AHRefresh()
end

local HOW = { ah = "", vendor = "vendor", craft = "make", none = "not on the AH" }
function C:AHRefresh()
  local f = self.ahPanel
  if not f or not f:IsShown() then return end
  local shop = self:Shopping(self.key)
  local tl = {}
  for prof, t in pairs(shop.targets) do if t[2] > t[1] then tl[#tl + 1] = string.format("%s %d to %d", prof, t[1], t[2]) end end
  f.sub:SetText(#tl > 0 and table.concat(tl, ", ") or "Your professions are at or above the level benchmark.")
  local y = -48
  local i = 0
  local function line(left, right, note)
    i = i + 1
    local r = f.rows[i]
    if not r then
      r = { n = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), c = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
        s = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall") }
      r.n:SetJustifyH("LEFT"); r.c:SetJustifyH("RIGHT"); r.s:SetJustifyH("LEFT"); r.n:SetWordWrap(false)
      f.rows[i] = r
    end
    r.n:ClearAllPoints(); r.n:SetPoint("TOPLEFT", 16, y); r.n:SetWidth(190); r.n:SetText(left)
    r.c:ClearAllPoints(); r.c:SetPoint("TOPRIGHT", -12, y); r.c:SetText(right or "")
    r.s:ClearAllPoints(); r.s:SetPoint("TOPLEFT", 28, y - 12); r.s:SetText(note or "")
    r.n:Show(); r.c:Show(); r.s:Show()
    y = y - (note and note ~= "" and 26 or 15)
  end
  -- the route
  for _, st in ipairs(shop.route) do
    line(string.format("|cffffd100%s|r x%d", st.name, st.crafts), string.format("|cffa89a84%d to %d|r", st.from, st.to))
  end
  if #shop.route > 0 then y = y - 4 end
  for _, e in ipairs(shop.buy) do
    local name = C.ITEM[e.id] and C.ITEM[e.id][1] or ("item " .. e.id)
    local right = e.cost and (money(e.cost) .. (e.partial and " |cffff6060+|r" or "")) or (self.scanning and "|cffa89a84...|r" or "|cffa89a84none listed|r")
    line(string.format("%d x %s", e.n, name), right, e.note)
  end
  for _, m in ipairs(shop.make) do
    line(string.format("|cffa89a84make %d %s|r", m.n, C.ITEM[m.id] and C.ITEM[m.id][1] or ""), "", nil)
  end
  if #shop.buy == 0 then line("Nothing to buy: you have the materials.") end
  for j = i + 1, #f.rows do f.rows[j].n:Hide(); f.rows[j].c:Hide(); f.rows[j].s:Hide() end
  y = y - 6
  f.total:ClearAllPoints(); f.total:SetPoint("TOPRIGHT", -12, y)
  f.total:SetText((self.scanning and string.format("Scanning, %d left...  ", #queue + (current and 1 or 0)) or "") .. "Total " .. money(shop.total)
    .. (shop.unpriced > 0 and string.format("  |cffa89a84(%d unpriced)|r", shop.unpriced) or ""))
  f:SetHeight(-y + 28)
end
