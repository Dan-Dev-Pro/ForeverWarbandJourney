-- Forever Warband Journey: profession planner.
-- Built-in skill-up paths (DataProf.lua), your real recipe colours from the profession window,
-- materials across bags, bank and every character, and a gather-or-ignore verdict for nodes.
local C = FWJ
C.CAPS = { 75, 150, 225, 300 }
function C.NextCap(skill) for _, c in ipairs(C.CAPS) do if skill < c then return c end end return 300 end
-- planning horizon: the highest rank this character's level allows (at least the next cap)
function C:ProfTarget(k, skill)
  local lv = math.floor(self:Lv(k))
  local best = C.NextCap(skill)
  for _, r in ipairs(C.RANKS) do if lv >= r[3] and r[2] > best then best = r[2] end end
  return best
end

-- inventory ---------------------------------------------------------------------------------
local function tracked(id) return id and (C.ITEM[id] or C.MADEFROM[id] or (C.db and C.db.items and C.db.items[id])) end
local function scan(bags)
  local out = {}
  for _, bag in ipairs(bags) do
    local n = C.CSlots(bag) or 0
    for slot = 1, n do
      local id, _, _, _, count = C.CInfo(bag, slot)
      if tracked(id) then out[id] = (out[id] or 0) + (count or 1) end
    end
  end
  return out
end
function C:ScanBags()
  local c = self.key and self:Char(self.key)
  -- backpack, bags, and the reagent bag (slot 5 on modern clients)
  local last = (NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 1)
  local list = {}
  for b = 0, last do list[#list + 1] = b end
  if c then c.bags = scan(list); c.bagsT = time() end
end
function C:ScanBank()
  local c = self.key and self:Char(self.key)
  local first = (NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 0) + 1
  local list = { -1, -3 }
  for b = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do list[#list + 1] = b end
  if c then c.bank = scan(list); c.bankT = time() end
end

-- conversions: what an item is made from. The game's own recipe (read from your profession window) wins
-- over the built-in table, so if Forever smelts 2 ore into a bar, that's what gets used.
function C:Conv(id)
  local live = self.db and self.db.conv and self.db.conv[id]
  return live or C.MADEFROM[id], live and true
end
function C:Expand(id, n, acc, depth)
  depth = depth or 0
  local cv, live = self:Conv(id)
  if cv and depth < 4 and not (C.ITEM[id] and (C.ITEM[id][2] == "ore" or C.ITEM[id][2] == "stone" or C.ITEM[id][2] == "herb" or C.ITEM[id][2] == "cloth")) then
    for _, m in ipairs(cv) do
      if live then self:Expand(m[1], n * m[2], acc, depth + 1) else acc[m[1]] = (acc[m[1]] or 0) + n * m[2] end
    end
  else acc[id] = (acc[id] or 0) + n end
  return acc
end
local rawCache = {}
function C:RawOf(rec)
  local hit = rawCache[rec]
  if hit and hit.v == (self.convV or 0) then return hit.raw end
  local acc = {}
  for _, m in ipairs(rec.r) do self:Expand(m[1], m[2], acc) end
  local raw = {}
  for id, nn in pairs(acc) do raw[#raw + 1] = { id, nn } end
  rawCache[rec] = { v = self.convV or 0, raw = raw }
  return raw
end

-- raw materials held across the account (bars, bolts and other made items count as what they're made from)
function C:RawHave()
  local have, where = {}, {}
  local function add(id, n, k)
    have[id] = (have[id] or 0) + n
    where[id] = where[id] or {}
    where[id][k] = (where[id][k] or 0) + n
  end
  for k, c in pairs(self.db.chars) do
    for _, src in ipairs({ c.bags or {}, c.bank or {} }) do
      for id, n in pairs(src) do
        local nm = C.ITEM[id] and C.ITEM[id][1] or ""
        if self:Conv(id) and (nm:find(" Bar$") or nm:find("^Bolt of")) then
          for rid, rn in pairs(self:Expand(id, n, {})) do add(rid, rn, k) end
        elseif C.ITEM[id] then add(id, n, k) end
      end
    end
  end
  return have, where
end

-- path ---------------------------------------------------------------------------------------
-- steps and raw materials to go from skill a to b
function C:PathSpan(prof, a, b)
  local steps, mats = {}, {}
  for _, s in ipairs(C.PATHS[prof] or {}) do
    local lo, hi = math.max(a, s.f), math.min(b, s.t)
    if hi > lo then
      local crafts = math.max(1, math.ceil(s.c * (hi - lo) / (s.t - s.f)))
      steps[#steps + 1] = { s = s, from = lo, to = hi, crafts = crafts }
      for _, m in ipairs(s.raw) do mats[m[1]] = (mats[m[1]] or 0) + m[2] * crafts end
    end
  end
  return steps, mats
end

-- recipe colour at a skill level, from the path data
function C.Colour(skill, learn, yellow, grey)
  if skill < learn then return "locked" end
  if skill < yellow then return "orange" end
  if skill >= grey then return "grey" end
  if skill < math.floor((yellow + grey) / 2) then return "yellow" end
  return "green"
end
C.COLOURS = { orange = { 1, .5, .25 }, yellow = { 1, 1, 0 }, green = { .25, .75, .25 }, grey = { .5, .5, .5 }, locked = { .6, .4, .4 },
  optimal = { 1, .5, .25 }, medium = { 1, 1, 0 }, easy = { .25, .75, .25 }, trivial = { .5, .5, .5 } }
local LIVE = { optimal = "orange", medium = "yellow", easy = "green", trivial = "grey" }

-- what the whole account needs for every crafting profession to reach its next rank cap
function C:AccountNeed()
  if self.needCache and GetTime() - self.needCache.t < 10 then return self.needCache.need, self.needCache.why end
  local need, why = {}, {}
  for k, c in pairs(self.db.chars) do
    if c.inPlan ~= false then
      for prof, v in pairs(c.profs or {}) do
        if C.PATHS[prof] and v[1] < 300 then
          local cap = self:ProfTarget(k, v[1])
          local _, mats = self:PlanLive(k, prof, v[1], cap)
          for id, n in pairs(mats) do
            need[id] = (need[id] or 0) + n
            why[id] = why[id] or {}
            why[id][#why[id] + 1] = string.format("%s %s to %d", self:Short(k), prof, cap)
          end
        end
      end
    end
  end
  self.needCache = { t = GetTime(), need = need, why = why }
  return need, why
end
function C:Shortfall()
  local need, why = self:AccountNeed()
  local have = self:RawHave()
  local short = {}
  for id, n in pairs(need) do
    local s = math.ceil(n - (have[id] or 0))
    if s > 0 then short[id] = s end
  end
  return short, need, have, why
end

-- gathering: node colour and the verdict
function C.NodeColour(skill, req)
  if skill < req then return "locked" end
  local d = skill - req
  if d < 25 then return "orange" elseif d < 50 then return "yellow" elseif d < 100 then return "green" end
  return "grey"
end
function C:NodeVerdict(k, prof, node, short)
  local c = self:Char(k)
  local skill = c and c.profs and c.profs[prof] and c.profs[prof][1]
  if not skill then return nil end
  short = short or self:Shortfall()
  local col = C.NodeColour(skill, node[2])
  local need = 0
  local parts = {}
  for i = 3, 4 do
    local id = node[i]
    if id and short[id] then need = need + short[id]; parts[#parts + 1] = string.format("%d %s", short[id], C.ITEM[id] and C.ITEM[id][1] or "?") end
  end
  -- a locked node close above you that drops something you need makes lower skill-ups worth it
  local unlock
  if col ~= "locked" and col ~= "grey" and need == 0 then
    for _, nd in ipairs(C.NODES[prof]) do
      if nd[2] > skill and nd[2] <= skill + 40 and ((nd[3] and short[nd[3]]) or (nd[4] and short[nd[4]])) then unlock = nd; break end
    end
  end
  local v
  if unlock then v = { "Gather", string.format("skill-up toward %s at %d, which drops %s you need", unlock[1], unlock[2],
      C.ITEM[(unlock[4] and short[unlock[4]]) and unlock[4] or unlock[3]][1]), "gold" }
  elseif col == "locked" then v = { "Can't gather yet", "needs " .. prof .. " " .. node[2] .. (need > 0 and (", and you need " .. table.concat(parts, ", ")) or ""), "red" }
  elseif need > 0 then v = { "Gather", "still need " .. table.concat(parts, ", "), "gold" }
  elseif col == "orange" or col == "yellow" then v = { "Gather", "skill-up (" .. col .. ")", "gold" }
  elseif col == "green" then
    local lv = math.floor(self:Lv(k))
    local behind = skill < math.min(300, lv * 5) - 25
    v = behind and { "Gather", "green skill-up, and you're behind your level", "gold" } or { "Optional", "green, slow skill-ups and no materials needed", "grey" }
  else v = { "Ignore", "no skill-up and no materials needed", "dim" } end
  v.col = col
  return v
end

-- live recipe colours from the profession window ---------------------------------------------
local REL = { [0] = "orange", [1] = "yellow", [2] = "green", [3] = "grey" }
function C:ReadTradeSkill(craft)
  local c = self.key and self:Char(self.key)
  if not c then return end
  local prof, known = nil, {}
  if not craft and C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
    -- WoW Forever's profession window (the modern one)
    local info = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
    prof = info and info.professionName
    if (not prof or prof == "") and C_TradeSkillUI.GetChildProfessionInfo then
      local ci = C_TradeSkillUI.GetChildProfessionInfo(); prof = ci and (ci.parentProfessionName or ci.professionName)
    end
    if (not prof or prof == "") and C_TradeSkillUI.GetTradeSkillDisplayName and C_TradeSkillUI.GetTradeSkillLine then
      prof = C_TradeSkillUI.GetTradeSkillDisplayName(C_TradeSkillUI.GetTradeSkillLine())
    end
    for _, id in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
      local r = C_TradeSkillUI.GetRecipeInfo(id)
      if r and r.name and r.learned ~= false then
        local col = REL[r.relativeDifficulty] or LIVE[r.difficulty or ""] or "yellow"
        known[r.name] = { col, r.numAvailable or 0 }
        if C_TradeSkillUI.GetRecipeSchematic then
          local ok, sc = pcall(C_TradeSkillUI.GetRecipeSchematic, id, false)
          local out = ok and sc and sc.outputItemID
          -- every recipe's reagents, so recipes WoW Forever added (not in the built-in data) can be planned too
          if ok and sc and sc.reagentSlotSchematics then
            local rr = {}
            for _, slot in ipairs(sc.reagentSlotSchematics) do
              local rg = slot.reagents and slot.reagents[1]
              if rg and rg.itemID and (slot.quantityRequired or 0) > 0 and (slot.reagentType == nil or slot.reagentType == 1) then
                rr[#rr + 1] = { rg.itemID, slot.quantityRequired }
                self.db.items = self.db.items or {}
                if not C.ITEM[rg.itemID] and not self.db.items[rg.itemID] then
                  local nm = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(rg.itemID)) or (GetItemInfo(rg.itemID))
                  if nm then self.db.items[rg.itemID] = nm end
                end
              end
            end
            known[r.name][3] = rr
            known[r.name][4] = sc.outputItemID
            known[r.name][5] = math.max(1, sc.quantityMin or 1)
          end
          if out and (C.MADEFROM[out] or C.ITEM[out]) and sc.reagentSlotSchematics then
            local q = math.max(1, sc.quantityMin or 1)
            local list = {}
            for _, slot in ipairs(sc.reagentSlotSchematics) do
              local rg = slot.reagents and slot.reagents[1]
              if rg and rg.itemID and (slot.quantityRequired or 0) > 0 and (slot.reagentType == nil or slot.reagentType == 1) then
                list[#list + 1] = { rg.itemID, slot.quantityRequired / q }
              end
            end
            if #list > 0 then
              self.db.conv = self.db.conv or {}
              self.db.conv[out] = list
              self.convV = (self.convV or 0) + 1
            end
          end
        end
      end
    end
    -- the window can open before recipes load; skip empty reads
    if not next(known) then prof = nil end
  else
    local n
    if craft then
      prof = GetCraftDisplaySkillLine and GetCraftDisplaySkillLine() or (GetCraftName and GetCraftName())
      n = GetNumCrafts and GetNumCrafts() or 0
    else
      prof = GetTradeSkillLine and GetTradeSkillLine()
      n = GetNumTradeSkills and GetNumTradeSkills() or 0
    end
    for i = 1, n do
      local name, t, num
      if craft then local a, _, ty, nu = GetCraftInfo(i); name, t, num = a, ty, nu
      else name, t, num = GetTradeSkillInfo(i) end
      if name and t and t ~= "header" then known[name] = { LIVE[t] or t, num or 0 } end
    end
  end
  if not prof or prof == "UNKNOWN" or not next(known) then return end
  c.known = c.known or {}
  c.known[prof] = known
  c.knownSkill = c.knownSkill or {}
  c.knownSkill[prof] = c.profs and c.profs[prof] and c.profs[prof][1]
  self.recV = (self.recV or 0) + 1
  c.knownT = c.knownT or {}
  c.knownT[prof] = time()
  -- reading the window is also a good moment to refresh skill levels
  self:ReadProfs(c)
end

-- node tooltips: add the verdict when you mouse over a vein or herb
local NODE = {}
for prof, list in pairs(C.NODES) do for _, n in ipairs(list) do NODE[n[1]] = { prof, n } end end
local function onTip(tt)
  if not C.db or C.db.opt.nodeTips == false then return end
  local l1 = _G[tt:GetName() .. "TextLeft1"]
  local t = l1 and l1:GetText()
  local hit = t and NODE[t]
  if not hit or tt.fwjNode == t then return end
  local v = C:NodeVerdict(C.key, hit[1], hit[2])
  if not v then return end
  tt.fwjNode = t
  local col = v[3] == "gold" and { 1, .82, 0 } or v[3] == "red" and { 1, .38, .38 } or { .6, .6, .6 }
  tt:AddLine("FWJ: " .. v[1] .. "  |cffa89a84" .. v[2] .. "|r", col[1], col[2], col[3])
  tt:Show()
end
if GameTooltip then
  GameTooltip:HookScript("OnShow", onTip)
  GameTooltip:HookScript("OnHide", function(tt) tt.fwjNode = nil end)
  if GameTooltip.HookScript then GameTooltip:HookScript("OnUpdate", function(tt) if not tt.fwjNode then onTip(tt) end end) end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "BANKFRAME_OPENED", "PLAYERBANKSLOTS_CHANGED", "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE",
  "TRADE_SKILL_DATA_SOURCE_CHANGED", "CRAFT_SHOW", "CRAFT_UPDATE", "PLAYER_ENTERING_WORLD" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, e)
  if not C.db then return end
  if e == "BANKFRAME_OPENED" or e == "PLAYERBANKSLOTS_CHANGED" then C.bankOpen = true; C:ScanBank()
  elseif e:find("^TRADE_SKILL") then C:ReadTradeSkill(false)
  elseif e == "CRAFT_SHOW" or e == "CRAFT_UPDATE" then C:ReadTradeSkill(true)
  elseif e == "PLAYER_ENTERING_WORLD" then C:ScanBags() end
end)

-- recipes to plan with: the built-in ones, plus any your profession window has that the data doesn't
-- (WoW Forever added recipes like Enchant Chest - Inferior Stamina). Their skill range is estimated
-- from the colour the window showed at the skill you had when you opened it.
local GUESS = { orange = { 8, 30 }, yellow = { -5, 15 }, green = { -20, 5 } }
local rcache = {}
function C:RecipesFor(k, prof)
  local key = k .. prof .. (self.recV or 0)
  if rcache[key] then return rcache[key] end
  local out = {}
  for name, rec in pairs(C.RECIPES[prof] or {}) do out[name] = rec end
  local c = self:Char(k)
  local known = c and c.known and c.known[prof]
  local s0 = c and c.knownSkill and c.knownSkill[prof] or (c and c.profs and c.profs[prof] and c.profs[prof][1]) or 1
  for name, live in pairs(known or {}) do
    if not out[name] and live[3] and #live[3] > 0 then
      local gq = GUESS[live[1]]
      if gq then out[name] = { l = 0, y = s0 + gq[1], g = s0 + gq[2], r = live[3], m = live[4], n = live[5] or 1, extra = true } end
    end
  end
  rcache = { [key] = out }
  return out
end
-- what kind of material an item is, for cost weights (by name for items the data doesn't know)
function C:Kind(id)
  local it = C.ITEM[id]
  if it then return it[2] end
  local nm = self.db and self.db.items and self.db.items[id] or ""
  if nm:find("Dust") or nm:find("Essence") or nm:find("Shard") then return "ench" end
  if nm:find(" Ore$") then return "ore" end
  if nm:find("Cloth$") then return "cloth" end
  if nm:find("Stone$") then return "stone" end
  if nm:find("Thread") or nm:find("Vial") or nm:find("Flux") or nm:find("Dye") or nm:find("Wood") then return "vendor" end
  return "other"
end

-- what to craft right now ------------------------------------------------------------------------
-- Ranks every recipe you could make at this skill. Your profession window is the truth for colours
-- (WoW Forever has changed some recipes); the built-in data fills in recipes you haven't opened yet.
local WEIGHT = { ore = 1, stone = 2.5, herb = 1, cloth = .6, ench = 1.5, vendor = .15, leather = 3, other = 8 }
local function chanceFor(col, skill, rec)
  if col == "orange" then return 1 end
  if col == "grey" or col == "locked" then return 0 end
  -- data chance when the data agrees with the colour, otherwise a typical value for that colour
  local dc = (skill >= rec.y and skill < rec.g) and (rec.g - skill) / (rec.g - rec.y) or nil
  local dcol = C.Colour(skill, rec.l, rec.y, rec.g)
  if dc and dcol == col then return math.max(.1, dc) end
  return col == "yellow" and .75 or .3
end
-- skill-ups you can expect from a recipe before it goes grey (or until the cap)
local function runLength(col, skill, rec, cap)
  local top = math.min(cap, rec.g)
  if C.Colour(skill, rec.l, rec.y, rec.g) == "grey" then top = math.min(cap, skill + (col == "orange" and 10 or col == "yellow" and 5 or 2)) end
  return math.max(1, top - skill)
end
function C:CraftNow(k, prof, skill, cap, n)
  local c = self:Char(k)
  local known = c and c.known and c.known[prof]
  local have = self:RawHave()
  local list = {}
  for name, rec in pairs(self:RecipesFor(k, prof)) do
    local live = known and known[name]
    local col = live and live[1] or C.Colour(skill, rec.l, rec.y, rec.g)
    local ch = chanceFor(col, skill, rec)
    if ch > 0 and (live or rec.l <= skill) then
      local cost = 0
      for _, m in ipairs(self:RawOf(rec)) do
        local w = WEIGHT[self:Kind(m[1])] or 8
        if (have[m[1]] or 0) >= m[2] then w = w * .5 end
        cost = cost + w * m[2]
      end
      local score = cost / ch
      if live and (live[2] or 0) > 0 then score = score * .6 end   -- you can make it right now
      if known and not live then score = score * 1.2 end             -- needs a trainer visit first
      list[#list + 1] = { name = name, rec = rec, col = col, chance = ch, score = score, live = live,
        run = runLength(col, skill, rec, cap) }
    end
  end
  table.sort(list, function(a, b) return a.score < b.score end)
  local out = {}
  for i = 1, math.min(n or 3, #list) do
    local e = list[i]
    -- crafts for the next few points with this recipe (the chance falls as you go)
    local pts = math.min(e.run, 10)
    local crafts = 0
    for s = skill, skill + pts - 1 do
      local cc = e.live and s == skill and e.chance or chanceFor(C.Colour(s, e.rec.l, e.rec.y, e.rec.g), s, e.rec)
      if cc <= 0 then cc = .2 end
      crafts = crafts + 1 / cc
    end
    e.pts, e.crafts = pts, math.ceil(crafts)
    out[#out + 1] = e
  end
  return out
end

-- planner ----------------------------------------------------------------------------------------
-- recommended skill for this character's level: 5 per level, within the rank the level allows
function C:RecSkill(k, skill)
  local lv = math.floor(self:Lv(k))
  return math.max(skill, math.min(self:ProfTarget(k, skill), lv * 5, 300))
end

-- colour of a recipe at skill s, given what the profession window said at skill s0
local RUN = { orange = 10, yellow = 5, green = 3 }
local function colourAt(rec, live, s, s0)
  local data = C.Colour(s, rec.l, rec.y, rec.g)
  if not live then return data end
  if live[1] == "grey" then return "grey" end
  if C.Colour(s0, rec.l, rec.y, rec.g) == live[1] then return data end
  -- Forever's levels differ from the data: trust the window for a few points, then assume it fades
  if s < s0 + (RUN[live[1]] or 3) then return live[1] end
  return "grey"
end

-- simulate skilling from a to b: the best recipe at each point (with a little stickiness so the
-- plan doesn't flip between recipes), its expected crafts and the raw materials
function C:PlanLive(k, prof, a, b)
  local c = self:Char(k)
  local known = c and c.known and c.known[prof]
  local steps, mats = {}, {}
  local cur
  local priced = self.HavePrices and self:HavePrices()
  -- what you already own is nearly free, so the plan spends it first (exact items across the account,
  -- plus the parts of an intermediate when someone can make it, e.g. ore for bars)
  local pool = {}
  for _, ch in pairs(self.db.chars) do
    for _, src in ipairs({ ch.bags or {}, ch.bank or {} }) do for id, n in pairs(src) do pool[id] = (pool[id] or 0) + n end end
  end
  local function ownedShare(id, q)
    local got = math.min(pool[id] or 0, q)
    local left = q - got
    local cv = left > 0 and self.Conv0 and self:Conv0(id)
    if cv and self:HasProf(cv.p) then
      local k2 = left / cv.n
      local frac = 1
      for _, m in ipairs(cv.r) do frac = math.min(frac, (pool[m[1]] or 0) / (m[2] * k2)) end
      got = got + left * math.max(0, math.min(1, frac))
    end
    return got / q
  end
  local function spend(id, q)
    local use = math.min(pool[id] or 0, q)
    pool[id] = (pool[id] or 0) - use
    q = q - use
    local cv = q > 0 and self.Conv0 and self:Conv0(id)
    if cv and self:HasProf(cv.p) then for _, m in ipairs(cv.r) do pool[m[1]] = math.max(0, (pool[m[1]] or 0) - q / cv.n * m[2]) end end
  end
  local function cost(rec)
    local t = 0
    if priced then
      -- real money: the cheapest way to get each reagent (buy it, buy its parts, or vendor)
      for _, m in ipairs(rec.r) do
        local u = self:UnitCost(m[1])
        if not u then
          u = 60 * (WEIGHT[self:Kind(m[1])] or 8)   -- unpriced: rough guess so it isn't free
        end
        t = t + u * m[2] * (1 - .98 * ownedShare(m[1], m[2]))
      end
      return t
    end
    for _, m in ipairs(rec.r) do
      local w = 0
      local acc = self:Expand(m[1], 1, {})
      for id, n in pairs(acc) do w = w + (WEIGHT[self:Kind(id)] or 8) * n end
      t = t + w * m[2] * (1 - .98 * ownedShare(m[1], m[2]))
    end
    return t
  end
  for s = a, b - 1 do
    local best, bestV, bestCh
    for name, rec in pairs(self:RecipesFor(k, prof)) do
      local live = known and known[name]
      if live or rec.l <= s then
        local col = colourAt(rec, live, s, a)
        local ch = chanceFor(col, s, rec)
        if ch > .05 then
          local v = cost(rec) / ch
          if known and not live then v = v * 1.2 end
          if not bestV or v < bestV then best, bestV, bestCh = rec, v, ch end
          rec._n = name
        end
      end
    end
    if cur and cur ~= best then
      local live = known and known[cur._n]
      local ch = (live or cur.l <= s) and chanceFor(colourAt(cur, live, s, a), s, cur) or 0
      if ch > .05 and bestV and cost(cur) / ch <= bestV * 1.25 then best, bestCh = cur, ch end
    end
    if not best then break end
    cur = best
    local crafts = 1 / bestCh
    local last = steps[#steps]
    if last and last.rec == best then last.to = s + 1; last.crafts = last.crafts + crafts
    else steps[#steps + 1] = { rec = best, name = best._n, from = s, to = s + 1, crafts = crafts } end
    for _, m in ipairs(self:RawOf(best)) do mats[m[1]] = (mats[m[1]] or 0) + m[2] * crafts end
    for _, m in ipairs(best.r) do spend(m[1], m[2] * crafts) end
  end
  for _, st in ipairs(steps) do st.crafts = math.ceil(st.crafts) end
  return steps, mats
end

-- shopping list for one character: what's short to reach the recommended skill in each crafting profession
function C:ShoppingList(k)
  local c = self:Char(k)
  local need = {}
  local targets = {}
  for prof, v in pairs(c and c.profs or {}) do
    if C.RECIPES[prof] then
      local to = self:RecSkill(k, v[1])
      targets[prof] = { v[1], to }
      if to > v[1] then
        local _, mats = self:PlanLive(k, prof, v[1], to)
        for id, nn in pairs(mats) do need[id] = (need[id] or 0) + nn end
      end
    end
  end
  local have = self:RawHave()
  local list = {}
  for id, nn in pairs(need) do
    local n = math.ceil(nn - (have[id] or 0))
    if n > 0 then list[#list + 1] = { id = id, need = math.ceil(nn), have = math.floor(have[id] or 0), short = n } end
  end
  table.sort(list, function(p, q) return p.short > q.short end)
  return list, targets
end

-- the shopping plan: route to the recommended skill, then for each reagent the cheapest way to get
-- what you don't already have (exact items first, then parts), and what you'll make yourself
function C:Shopping(k)
  local c = self:Char(k)
  local out = { route = {}, buy = {}, make = {}, total = 0, unpriced = 0, targets = {} }
  local need = {}
  for prof, v in pairs(c and c.profs or {}) do
    if C.RECIPES[prof] then
      local to = self:RecSkill(k, v[1])
      out.targets[prof] = { v[1], to }
      if to > v[1] then
        local ahead = self:RouteAhead(k, prof, v[1])
        local steps = ahead or self:PlanLive(k, prof, v[1], to)
        if ahead then out.targets[prof][2] = self:Route(k, prof).to end
        for _, st in ipairs(steps) do
          out.route[#out.route + 1] = st
          for _, m in ipairs(st.rec.r) do need[m[1]] = (need[m[1]] or 0) + m[2] * st.crafts end
        end
      end
    end
  end
  -- exact items held across the account
  local held = {}
  for _, ch in pairs(self.db.chars) do
    for _, src in ipairs({ ch.bags or {}, ch.bank or {} }) do for id, n in pairs(src) do held[id] = (held[id] or 0) + n end end
  end
  local buy, make = {}, {}
  local priced = self:HavePrices()
  local function resolve(id, n, depth)
    local use = math.min(held[id] or 0, n)
    held[id] = (held[id] or 0) - use
    n = n - use
    if n <= 1e-6 then return end
    local cv = self:Conv0(id)
    -- parts you already own get made up first (your ore becomes bars before buying bars)
    if cv and depth < 3 and self:HasProf(cv.p) then
      local k2 = n / cv.n
      local f = 1
      for _, m in ipairs(cv.r) do f = math.min(f, (held[m[1]] or 0) / (m[2] * k2)) end
      if f > 0 then
        local made = n * f
        make[id] = (make[id] or 0) + made
        for _, m in ipairs(cv.r) do held[m[1]] = (held[m[1]] or 0) - made / cv.n * m[2] end
        n = n - made
        if n <= 1e-6 then return end
      end
    end
    local _, how = self:UnitCost(id)
    -- without prices, make intermediates yourself so the list ends in gatherable materials
    if (how == "craft" or (not priced and cv and self:HasProf(cv.p))) and depth < 3 and cv then
      make[id] = (make[id] or 0) + n
      for _, m in ipairs(cv.r) do resolve(m[1], n / cv.n * m[2], depth + 1) end
    else
      buy[id] = (buy[id] or 0) + n
    end
  end
  for id, n in pairs(need) do resolve(id, n, 0) end
  for id, n in pairs(buy) do
    n = math.ceil(n - 1e-6)
    local it = C.ITEM[id]
    local e = { id = id, n = n }
    if it and it[2] == "vendor" and it[3] then e.cost = it[3] * n; e.note = "vendor"
    else
      local cost, got = self:BuyCost(id, n)
      if cost then e.cost = cost; e.partial = got < n end
      local cv = self:Conv0(id)
      if C.CONV0[id] and cost then e.note = "cheaper to buy than to make" end
      if not cost and cv then e.note = "no listings: make it from parts, or gather" end
    end
    if e.cost then out.total = out.total + e.cost else out.unpriced = out.unpriced + 1 end
    out.buy[#out.buy + 1] = e
  end
  table.sort(out.buy, function(a, b) return (a.cost or 0) > (b.cost or 0) end)
  for id, n in pairs(make) do out.make[#out.make + 1] = { id = id, n = math.ceil(n - 1e-6) } end
  table.sort(out.make, function(a, b) return a.n > b.n end)
  return out
end

-- locked routes ----------------------------------------------------------------------------------
-- Once you've bought for a route, it stays put: Craft now walks the saved steps instead of re-planning
-- every time your bags change. A step whose recipe goes grey early is skipped. Re-plan clears it.
function C:Route(k, prof)
  return self.db.routes and self.db.routes[k] and self.db.routes[k][prof]
end
function C:LockRoute(k, prof)
  local c = self:Char(k)
  local v = c and c.profs and c.profs[prof]
  if not v or not C.RECIPES[prof] then return end
  local to = self:RecSkill(k, v[1])
  if to <= v[1] then return end
  local steps = self:PlanLive(k, prof, v[1], to)
  local out = {}
  for _, st in ipairs(steps) do out[#out + 1] = { n = st.name, f = st.from, t = st.to, c = st.crafts } end
  self.db.routes = self.db.routes or {}
  self.db.routes[k] = self.db.routes[k] or {}
  self.db.routes[k][prof] = { steps = out, t = time(), to = to }
  self:Print(string.format("%s route locked to %d (%d steps).", prof, to, #out))
end
function C:LockAll(k)
  local c = self:Char(k)
  for prof in pairs(c and c.profs or {}) do if C.RECIPES[prof] then self:LockRoute(k, prof) end end
end
function C:UnlockRoute(k, prof)
  if self.db.routes and self.db.routes[k] then self.db.routes[k][prof] = nil end
end
-- the steps still ahead on a locked route, with crafts scaled to the skill left in the current step
function C:RouteAhead(k, prof, skill)
  local rt = self:Route(k, prof)
  if not rt then return nil end
  local c = self:Char(k)
  local known = c and c.known and c.known[prof]
  local out = {}
  for _, st in ipairs(rt.steps) do
    if st.t > skill then
      local live = known and known[st.n]
      local rec = self:RecipesFor(k, prof)[st.n]
      local grey = live and live[1] == "grey"
      if rec and not grey then
        local from = math.max(st.f, skill)
        local crafts = math.max(1, math.ceil(st.c * (st.t - from) / math.max(1, st.t - st.f)))
        out[#out + 1] = { name = st.n, rec = rec, from = from, to = st.t, crafts = crafts, live = live,
          col = live and live[1] or C.Colour(from, rec.l, rec.y, rec.g) }
      end
    end
  end
  if skill >= rt.to or #out == 0 then return nil, true end
  return out
end

-- crafts you could do right now from what this character carries (bars made from ore count if they can smelt)
function C:CanMake(k, rec)
  local c = self:Char(k)
  local bags = c and c.bags or {}
  local n = math.huge
  for _, m in ipairs(rec.r) do
    local have = bags[m[1]] or 0
    local cv = self:Conv0(m[1])
    if cv and c.profs and c.profs[cv.p] then
      local extra = math.huge
      for _, p in ipairs(cv.r) do extra = math.min(extra, (bags[p[1]] or 0) / p[2] * cv.n) end
      if extra < math.huge then have = have + extra end
    end
    n = math.min(n, math.floor(have / m[2]))
  end
  return n == math.huge and 0 or n
end
-- the next steps to show under Craft now: the locked route, or the live plan (the same plan the
-- materials and shopping list use, so they always agree)
function C:NextSteps(k, prof, skill, to)
  local ahead, done = self:RouteAhead(k, prof, skill)
  if ahead then return ahead, true, done end
  local c = self:Char(k)
  local known = c and c.known and c.known[prof]
  local steps = self:PlanLive(k, prof, skill, math.max(to, skill + 1))
  for _, st in ipairs(steps) do
    st.live = known and known[st.name]
    st.col = st.live and st.live[1] or C.Colour(st.from, st.rec.l, st.rec.y, st.rec.g)
  end
  return steps, false, done
end
