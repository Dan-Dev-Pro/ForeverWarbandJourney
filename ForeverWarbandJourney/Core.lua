-- Forever Warband Journey: core model (roster, goals, calendar, forecast, benchmarks)
FWJ = FWJ or {}
local C = FWJ
local DAY = 86400
C.NAME = "Forever Warband Journey"

-- levelling model ---------------------------------------------------------------------------
-- Hours per level for an average player. Each level is weighted by the XP it needs divided by the XP a
-- same-level mob gives (level x 5 + 45), then scaled to the WoW Forever bracket estimates:
-- 20 h for 1-20, 50 h for 20-40, 80 h for 40-60 (150 h in total).
C.XPNEED = { 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400, 16000, 17700, 19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400, 50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700, 95800, 101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200, 147500, 153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800 }
C.LVH = {}
do
  local w = {}
  for l = 1, 59 do w[l] = C.XPNEED[l] / (l * 5 + 45) end
  -- scale per bracket, blended between bracket midpoints so there is no jump at 20 or 40
  local ks, mids = {}, { 10, 29.5, 49.5 }
  for i, b in ipairs({ { 1, 19, 20 }, { 20, 39, 50 }, { 40, 59, 80 } }) do
    local s = 0
    for l = b[1], b[2] do s = s + w[l] end
    ks[i] = b[3] / s
  end
  for l = 1, 59 do
    local k
    if l <= mids[1] then k = ks[1] elseif l >= mids[3] then k = ks[3]
    else
      local i = l < mids[2] and 1 or 2
      k = ks[i] + (ks[i + 1] - ks[i]) * (l - mids[i]) / (mids[i + 1] - mids[i])
    end
    C.LVH[l] = w[l] * k
  end
end
C.CLASSM = { WARRIOR = 1.12, PALADIN = 1.08, SHAMAN = 1.02, DRUID = 1.0, ROGUE = 1.0, PRIEST = 1.0, WARLOCK = 0.92, MAGE = 0.92, HUNTER = 0.88 }
C.RAIDS = time({ year = 2026, month = 12, day = 9, hour = 0 })
C.LEGACY_GATE = { ["Permanence"] = { "Resourcefulness", 5 }, ["Bartering"] = { "Professions", 5 }, ["Dedicated Study"] = { "Professions", 10 } }
C.LEGACY_MAX = 16
C.ROLES = { "Main", "Crafter", "Gatherer", "Alt" }
C.PRIMARY = { Mining = 1, Herbalism = 1, Skinning = 1, Blacksmithing = 1, Tailoring = 1, Enchanting = 1, Alchemy = 1, Engineering = 1, Leatherworking = 1 }
C.GATHER = { Mining = 1, Herbalism = 1, Skinning = 1 }
C.SECONDARY = { ["First Aid"] = 1, Cooking = 1, Fishing = 1 }
-- profession ranks: name, cap, level needed, skill needed to train
C.RANKS = { { "Apprentice", 75, 1, 0 }, { "Journeyman", 150, 10, 50 }, { "Expert", 225, 20, 125 }, { "Artisan", 300, 35, 200 } }
C.CLOTH = { [2589] = true, [2592] = true, [4306] = true, [4338] = true, [14047] = true, [14256] = true }

local function perLvl(l) return C.LVH[math.max(1, math.min(59, l))] end
C.PerLvl = perLvl
function C.lvH(a, b)
  local h, l = 0, a
  while l < b - 1e-9 do
    local nl = math.min(b, math.floor(l) + 1)
    h = h + perLvl(math.floor(l)) * (nl - l)
    l = nl
  end
  return h
end
function C.lvAfter(a, h)
  local l = a
  while h > 1e-9 and l < 60 do
    local pl = perLvl(math.floor(l))
    local nl = math.floor(l) + 1
    local c = pl * (nl - l)
    if c >= h then return l + h / pl end
    h = h - c; l = nl
  end
  return math.min(60, l)
end

-- saved data -----------------------------------------------------------------------------------
function C:InitDB()
  if type(FWJDB) ~= "table" then FWJDB = {} end
  local db = FWJDB
  db.chars = db.chars or {}
  db.goals = db.goals or {}
  db.days = db.days or {}
  db.sessions = db.sessions or {}
  db.opt = db.opt or {}
  local o = db.opt
  local def = { wd = 2, we = 4, hud = true, popups = true, sell = true, repair = true, mini = 200, away = {}, nextId = 1, measured = true }
  for k, v in pairs(def) do if o[k] == nil then o[k] = v end end
  self.db = db
end

function C:Key() return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "") end
function C:Char(k) return k and self.db.chars[k] end
function C:Short(k) return (k or "?"):match("^([^%-]+)") end
function C:Plan()
  local out = {}
  for k, c in pairs(self.db.chars) do if c.inPlan then out[#out + 1] = k end end
  table.sort(out, function(a, b)
    local ra, rb = self.db.chars[a].order or 99, self.db.chars[b].order or 99
    if ra ~= rb then return ra < rb end
    return a < b
  end)
  return out
end
function C:Roster()
  local out = {}
  for k in pairs(self.db.chars) do out[#out + 1] = k end
  table.sort(out, function(a, b)
    local ca, cb = self.db.chars[a], self.db.chars[b]
    if (ca.inPlan and 1 or 0) ~= (cb.inPlan and 1 or 0) then return ca.inPlan and true or false end
    if (ca.order or 99) ~= (cb.order or 99) then return (ca.order or 99) < (cb.order or 99) end
    return (ca.level or 0) > (cb.level or 0)
  end)
  return out
end
function C:CharWithRole(role)
  for _, k in ipairs(self:Plan()) do if self.db.chars[k].role == role then return k end end
end

function C:Lv(k)
  local c = self:Char(k)
  if not c then return 1 end
  local frac = (c.xpMax and c.xpMax > 0) and (c.xp or 0) / c.xpMax or 0
  return math.min(60, (c.level or 1) + frac)
end

function C:ProfMult(k)
  local n = 0
  for name in pairs(self:Char(k).profs or {}) do if C.PRIMARY[name] then n = n + 1 end end
  return 1 + 0.03 * n
end
function C:ClassMult(k) return C.CLASSM[self:Char(k).classFile or ""] or 1 end

-- pace: your time vs the average player (1.0 = average, 0.5 = twice as fast).
-- Lifetime pace comes from total /played; recent pace from your last logged levels.
-- They are blended: the more levels logged (up to 8), the more the recent pace counts.
function C:PaceParts(k)
  local life, measured = self:LifetimePace(k)
  local c = self:Char(k)
  local rec, n = nil, 0
  if c and c.lvlog then
    local lvls = {}
    for lv, t in pairs(c.lvlog) do local nx = c.lvlog[lv + 1]; if nx and nx > t then lvls[#lvls + 1] = { lv, (nx - t) / 3600 } end end
    table.sort(lvls, function(a, b) return a[1] > b[1] end)
    local act, model = 0, 0
    for i = 1, math.min(8, #lvls) do
      act = act + lvls[i][2]; model = model + perLvl(lvls[i][1]) * self:ClassMult(k) * self:ProfMult(k); n = n + 1
    end
    if n >= 2 and model > 0 then
      rec = act / model
      if rec < 0.2 or rec > 3 then rec, n = nil, 0 end
    end
  end
  local wt = rec and math.min(1, n / 8) or 0
  local pace = rec and (rec * wt + life * (1 - wt)) or life
  return pace, life, rec, n, measured
end
function C:Pace(k) local p, _, _, _, m = self:PaceParts(k); return p, m end
function C:LifetimePace(k)
  local c = self:Char(k)
  if c and c.played and c.played > 1800 and (c.level or 1) >= 4 then
    local model = C.lvH(1, self:Lv(k)) * self:ClassMult(k) * self:ProfMult(k)
    if model > 0 then
      local f = (c.played / 3600) / model
      if f > 0.2 and f < 3 then return f, true end
    end
  end
  local own = {}
  for _, kk in ipairs(self:Plan()) do
    local cc = self:Char(kk)
    if kk ~= k and cc.played and cc.played > 3600 then
      local m = C.lvH(1, self:Lv(kk)) * self:ClassMult(kk) * self:ProfMult(kk)
      if m > 0 then own[#own + 1] = (cc.played / 3600) / m end
    end
  end
  if #own > 0 then local s = 0 for _, v in ipairs(own) do s = s + v end return s / #own, false end
  return 1.0, false
end
function C:Hours(k, from, to)
  if to <= from then return 0 end
  return C.lvH(from, to) * self:ClassMult(k) * self:ProfMult(k) * (self:Pace(k))
end

-- calendar -----------------------------------------------------------------------------------------
local function parseDate(s)
  local y, m, d = (s or ""):match("^(%d%d%d%d)%-(%d%d?)%-(%d%d?)$")
  if not y then return nil end
  return time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 0 })
end
C.ParseDate = parseDate
function C:Midnight(t) local d = date("*t", t); return time({ year = d.year, month = d.month, day = d.day, hour = 0 }) end
-- average hours actually played per weekday and per weekend day, from the day ledger
-- (last 28 full days after the day tracking began; days inside an away range are left out)
local function isWeekend(t) local w = date("*t", t + 3600).wday; return w == 1 or w == 7 end
C.IsWeekend = isWeekend
function C:InAway(t)
  for _, a in ipairs(self.db.opt.away or {}) do
    local f, to = C.ParseDate(a.from), C.ParseDate(a.to)
    if f and to and t >= f and t <= to then return true end
  end
end
function C:MeasuredHours()
  if self.mCache and self.mCache.day == date("%Y-%m-%d") then return self.mCache.wd, self.mCache.we, self.mCache.nwd, self.mCache.nwe end
  local first
  for day in pairs(self.db.days) do if not first or day < first then first = day end end
  local today0 = self:Midnight(time())
  local sum, n = { 0, 0 }, { 0, 0 }
  if first then
    for i = 1, 28 do
      local t = today0 - i * DAY + 12 * 3600
      local day = date("%Y-%m-%d", t)
      if day <= first then break end -- the install day is only part-tracked
      if not self:InAway(self:Midnight(t)) then
        local j = isWeekend(self:Midnight(t)) and 2 or 1
        sum[j] = sum[j] + (self:DayStats(day)); n[j] = n[j] + 1
      end
    end
  end
  local wd = n[1] >= 5 and sum[1] / n[1] or nil
  local we = n[2] >= 2 and sum[2] / n[2] or nil
  self.mCache = { day = date("%Y-%m-%d"), wd = wd, we = we, nwd = n[1], nwe = n[2] }
  return wd, we, n[1], n[2]
end
function C:BaseHours()
  local o = self.db.opt
  local wd, we = o.wd, o.we
  if o.measured then
    local mwd, mwe = self:MeasuredHours()
    wd, we = mwd or wd, mwe or we
  end
  return wd, we
end
function C:DayHours(t)
  local o = self.db.opt
  -- later entries win, so a single day inside a longer break can be overridden
  local hit
  for _, a in ipairs(o.away or {}) do
    local f, to = parseDate(a.from), parseDate(a.to)
    if f and to and t >= f and t <= to then hit = a.hours or 0 end
  end
  if hit then return hit end
  local wd, we = self:BaseHours()
  return isWeekend(t) and we or wd
end
function C:Capacity(a, b)
  if b <= a then return 0 end
  local h, t = 0, self:Midnight(a)
  while t < b do
    local s0, s1 = t + 18 * 3600, t + DAY
    local lo, hi = math.max(a, s0), math.min(b, s1)
    if hi > lo then h = h + self:DayHours(t) * (hi - lo) / (s1 - s0) end
    t = t + DAY
  end
  return h
end
function C:AfterHours(from, hours)
  local t = from
  for _ = 1, 500 do
    local mid = self:Midnight(t)
    local s0, s1 = mid + 18 * 3600, mid + DAY
    local lo = math.max(t, s0)
    local dh = self:DayHours(mid)
    if lo < s1 and dh > 0 then
      local cap = dh * (s1 - lo) / (s1 - s0)
      if cap >= hours then return lo + (s1 - s0) * hours / dh end
      hours = hours - cap
    end
    t = s1
  end
  return t
end
function C:Target() return parseDate(self.db.opt.target) end

-- goals ---------------------------------------------------------------------------------------------
-- a goal: { id, ch = key, to = level, by = "YYYY-MM-DD" or nil, done = bool, startT, startLv }
function C:GoalDone(g) return g.done or self:Lv(g.ch) >= g.to end
function C:ActiveGoal()
  for _, g in ipairs(self.db.goals) do
    if self:Char(g.ch) and not self:GoalDone(g) then
      if not g.startT then g.startT = time(); g.startLv = self:Lv(g.ch) end
      return g
    end
  end
end
function C:NextGoalFor(k)
  for _, g in ipairs(self.db.goals) do if g.ch == k and not self:GoalDone(g) then return g end end
end
function C:AddGoal(k, to, by)
  local id = self.db.opt.nextId; self.db.opt.nextId = id + 1
  table.insert(self.db.goals, { id = id, ch = k, to = math.max(2, math.min(60, to)), by = by })
end
function C:MoveGoal(i, d)
  local g = self.db.goals
  local j = i + d
  if j < 1 or j > #g then return end
  g[i], g[j] = g[j], g[i]
end
function C:RemoveGoal(i) table.remove(self.db.goals, i) end

-- templates built from roles
function C:ApplyTemplate(name)
  local main, crafter, gatherer = self:CharWithRole("Main"), self:CharWithRole("Crafter"), self:CharWithRole("Gatherer")
  local g = {}
  if name == "solo" and main then g = { { main, 60 } }
  elseif name == "crafter" and main and crafter then g = { { crafter, 10 }, { main, 30 }, { crafter, 20 }, { main, 60 }, { crafter, 60 } }
  elseif name == "relay" and main and crafter and gatherer then
    g = { { crafter, 10 }, { main, 30 }, { gatherer, 10 }, { crafter, 20 }, { main, 60 }, { crafter, 60 }, { gatherer, 60 } }
  else return false end
  self.db.goals = {}
  for _, x in ipairs(g) do self:AddGoal(x[1], x[2]) end
  return true
end

-- forecast: goals in order on the calendar
function C:Forecast()
  local lv = {}
  local hours, rows, t0 = 0, {}, time()
  for _, g in ipairs(self.db.goals) do
    if self:Char(g.ch) and not g.done then
      lv[g.ch] = lv[g.ch] or self:Lv(g.ch)
      local h = self:Hours(g.ch, lv[g.ch], g.to)
      if h > 0 then
        hours = hours + h
        lv[g.ch] = g.to
      end
      rows[g.id] = { at = h > 0 and self:AfterHours(t0, hours) or 0, h = h }
    end
  end
  return rows, hours
end
function C:FinalGoal()
  local last
  for _, g in ipairs(self.db.goals) do if self:Char(g.ch) and not self:GoalDone(g) then last = g end end
  local mainK = self:CharWithRole("Main")
  if mainK then
    for _, g in ipairs(self.db.goals) do if g.ch == mainK and not self:GoalDone(g) then last = g end end
  end
  return last
end

-- where a goal with a deadline expects the character to be at time t
function C:ExpectedLv(g, t)
  if not g.by or not g.startT then return nil end
  local by = parseDate(g.by)
  if not by or by <= g.startT then return nil end
  local total = self:Capacity(g.startT, by)
  if total <= 0 then return nil end
  local f = math.min(1, self:Capacity(g.startT, t) / total)
  return C.lvAfter(g.startLv, C.lvH(g.startLv, g.to) * f)
end
function C:DaysAhead(g)
  if not g or not g.by then return nil end
  local L, now = self:Lv(g.ch), time()
  local e = self:ExpectedLv(g, now)
  if not e then return nil end
  if e >= L then
    for d = 0, 60, 0.25 do local x = self:ExpectedLv(g, now - d * DAY); if not x or x <= L then return -d end end
    return -60
  end
  for d = 0, 60, 0.25 do local x = self:ExpectedLv(g, now + d * DAY); if x and x >= L then return d end end
  return 60
end

-- account progress over the plan, weighted by levelling hours
function C:AccountPct()
  local got, tot = 0, 0
  for _, k in ipairs(self:Plan()) do
    local m = self:ClassMult(k)
    got = got + C.lvH(1, self:Lv(k)) * m
    tot = tot + C.lvH(1, 60) * m
  end
  return tot > 0 and got / tot * 100 or 0
end

-- training benchmarks --------------------------------------------------------------------------------
function C:ProfAdvice(k, name, rank, max)
  local lv = math.floor(self:Lv(k))
  local cur, nxt
  for i, r in ipairs(C.RANKS) do if max <= r[2] then cur = r; nxt = C.RANKS[i + 1]; break end end
  local out = {}
  if nxt and rank >= cur[2] - 10 then
    if lv < nxt[3] then out.text, out.state = string.format("Capped at %d until level %d (%s)", cur[2], nxt[3], nxt[1]), "wait"
    elseif rank < nxt[4] then out.text, out.state = string.format("%d more points, then train %s", nxt[4] - rank, nxt[1]), "soon"
    else out.text, out.state = "Train " .. nxt[1] .. " now", "train" end
  elseif nxt and lv >= nxt[3] and rank >= nxt[4] then out.text, out.state = "Train " .. nxt[1] .. " now", "train"
  elseif not nxt and rank >= 300 then out.text, out.state = "Maxed", "done"
  elseif nxt then out.text, out.state = string.format("%s next at skill %d, level %d", nxt[1], nxt[4], nxt[3]), "ok"
  else out.text, out.state = "", "ok" end
  if C.GATHER[name] then
    local want = math.min(300, lv * 5)
    if rank < want - 25 then out.pace = string.format("Behind your level: aim for about %d", want) end
  end
  return out
end

function C:TrainerDue(k)
  local c = self:Char(k)
  local lv = c.level or 1
  if lv < 2 then return nil end
  local last = c.trained or 1
  if lv - last >= 2 then return string.format("Class trainer: %d levels of new ranks since your last visit", lv - last) end
end

C.MILESTONES = { { 10, "Talent points start" }, { 20, "Expert professions" }, { 35, "Artisan professions" }, { 40, "Riding (100g) and dual specialisation" }, { 60, "Level 60" } }
function C:NextMilestone(k)
  local lv = math.floor(self:Lv(k))
  for _, m in ipairs(C.MILESTONES) do if lv < m[1] then return m end end
end

-- snapshot of the logged-in character -----------------------------------------------------------------
function C:Snapshot()
  local k = self.key
  if not k then return end
  local c = self.db.chars[k] or {}
  self.db.chars[k] = c
  c.name = UnitName("player")
  c.class, c.classFile = UnitClass("player")
  c.race = UnitRace("player")
  c.faction = UnitFactionGroup and UnitFactionGroup("player")
  local lv = UnitLevel("player") or 0
  local xp, mx = UnitXP("player") or 0, UnitXPMax("player") or 0
  -- at login and logout the client can report level/XP as stale or 0; keep the last good reading
  if lv > 0 and lv >= (c.level or 0) then
    if lv > (c.level or 0) then c.xp, c.xpMax = 0, nil end
    c.level = lv
    if mx > 0 then c.xp, c.xpMax = xp, mx end
  end
  c.money = GetMoney()
  c.zone = GetRealZoneText and GetRealZoneText() or nil
  c.seen = time()
  c.goals = nil
  self:ReadProfs(c)
  self:ReadTalents(c)
end

-- professions. WoW Forever replaced the old skill line globals: try GetProfessions first, then C_SkillInfo,
-- then the classic globals.
function C:ReadProfs(c)
  local p, sec, found = {}, {}, false
  local function put(name, rank, mx)
    if not name then return end
    found = true
    if C.PRIMARY[name] then p[name] = { rank or 0, mx or 0 }
    elseif C.SECONDARY[name] then sec[name] = { rank or 0, mx or 0 }
    elseif name == "Riding" then c.riding = rank end
  end
  if GetProfessions and GetProfessionInfo then
    local list = { GetProfessions() }
    for i = 1, 6 do
      local idx = list[i]
      if idx then local name, _, rank, mx = GetProfessionInfo(idx); put(name, rank, mx) end
    end
  end
  if C_SkillInfo and C_SkillInfo.GetNumSkillLines then
    for i = 1, C_SkillInfo.GetNumSkillLines() do
      local s = C_SkillInfo.GetSkillLineInfo(i)
      if s and not s.isHeader then put(s.name, s.rank or s.skillRank, s.maxRank or s.skillMaxRank) end
    end
  elseif GetNumSkillLines and GetSkillLineInfo then
    for i = 1, GetNumSkillLines() do
      local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
      if name and not isHeader then put(name, rank, maxRank) end
    end
  end
  -- only overwrite when the client actually returned something
  if found then c.profs, c.secondary = p, sec end
end

function C:ReadTalents(c)
  if not GetNumTalentTabs or not GetTalentInfo then return end
  local tabs = {}
  for t = 1, GetNumTalentTabs() do
    local r = { GetTalentTabInfo(t) }
    local name = type(r[1]) == "string" and r[1] or r[2]
    local tab = { name = name or ("Tree " .. t), talents = {}, spent = 0 }
    for i = 1, (GetNumTalents(t) or 0) do
      local tn, icon, tier, col, rank, max = GetTalentInfo(t, i)
      if tn then
        tab.talents[#tab.talents + 1] = { tn, icon, tier, col, rank or 0, max or 1 }
        tab.spent = tab.spent + (rank or 0)
      end
    end
    tabs[t] = tab
  end
  c.talents = tabs
  local free = (GetUnspentTalentPoints and GetUnspentTalentPoints()) or (UnitCharacterPoints and UnitCharacterPoints("player")) or 0
  c.freeTalents = free
end

function C:Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cffe8b64cFWJ|r " .. msg) end
function C.Money(c)
  c = math.floor(c or 0)
  return string.format("%dg %ds %dc", math.floor(c / 10000), math.floor(c / 100) % 100, c % 100)
end

-- quiet /played
local quiet = false
function C:RequestPlayed() quiet = true; RequestTimePlayed() end
if ChatFrame_DisplayTimePlayed then
  local orig = ChatFrame_DisplayTimePlayed
  ChatFrame_DisplayTimePlayed = function(...) if quiet then quiet = false return end return orig(...) end
end

-- events ----------------------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE", "TIME_PLAYED_MSG", "SKILL_LINES_CHANGED",
  "PLAYER_MONEY", "ZONE_CHANGED_NEW_AREA", "CHARACTER_POINTS_CHANGED", "TRAINER_SHOW", "PLAYER_LOGOUT" }) do ev:RegisterEvent(e) end
ev:SetScript("OnEvent", function(_, e, a1, a2)
  if e == "ADDON_LOADED" and a1 == "ForeverWarbandJourney" then C:InitDB(); return end
  if not C.db then return end
  if e == "PLAYER_LOGIN" then
    C.key = C:Key()
    local isNew = not C.db.chars[C.key]
    C:Snapshot()
    local c = C.db.chars[C.key]
    if isNew then
      c.trained = c.level
      local n = #C:Plan()
      if n < 3 then c.inPlan = true; c.order = n + 1; c.role = n == 0 and "Main" or "Alt" end
    end
    C:RequestPlayed()
    if C.CreateUI then C:CreateUI() end
    C:Print("tracking " .. c.name .. ". Type |cffffd100/fwj|r to open" .. (isNew and ", and set up your goals on the Goals tab." or "."))
  elseif e == "TIME_PLAYED_MSG" then
    local c = C:Char(C.key)
    if c then
      c.played = a1; c.playedLevel = a2; C.playedAt = GetTime()
      -- level log: total /played when each level was reached (total minus time spent at this level)
      local lv = UnitLevel("player")
      if lv and lv > 0 and a1 and a2 then
        c.lvlog = c.lvlog or {}
        local start = a1 - a2
        if not c.lvlog[lv] or math.abs(c.lvlog[lv] - start) > 120 then c.lvlog[lv] = start end
      end
    end
    if C.Refresh then C:Refresh() end
  elseif e == "PLAYER_LEVEL_UP" then
    local c = C:Char(C.key)
    c.level = a1; c.xp = 0; c.xpMax = nil
    C:Snapshot()
    C:RequestPlayed()
    if C.LevelPopup then C:LevelPopup(a1) end
  elseif e == "TRAINER_SHOW" then
    if not (IsTradeskillTrainer and IsTradeskillTrainer()) then local c = C:Char(C.key); if c then c.trained = c.level end end
  elseif e == "PLAYER_LOGOUT" then
    -- level and XP are kept from the last in-game reading; only refresh the rest
    local c = C:Char(C.key)
    if c then c.money = GetMoney(); c.zone = GetRealZoneText and GetRealZoneText() or c.zone; c.seen = time() end
  else
    C:Snapshot()
    if C.Refresh then C:Refresh() end
  end
end)

-- your recorded time for each finished level (hours), from the level log
function C:LevelTimes(k)
  local c = self:Char(k)
  local out = {}
  if not c or not c.lvlog then return out end
  for lv, t in pairs(c.lvlog) do
    local nx = c.lvlog[lv + 1]
    local busy = c.busy and c.busy[lv] or 0
    if nx and nx > t then out[#out + 1] = { lv = lv, h = math.max(60, nx - t - busy) / 3600, busy = busy / 3600, est = perLvl(lv) * self:ClassMult(k) * self:ProfMult(k) * (self:Pace(k)) } end
  end
  table.sort(out, function(a, b) return a.lv > b.lv end)
  return out
end

-- estimated hours for one level for this character (average x class x professions x your pace)
function C:LevelEst(k, lv) return perLvl(lv) * self:ClassMult(k) * self:ProfMult(k) * (self:Pace(k)) end

-- live check on the level you're on: time spent so far vs what the estimate expects at this much XP
function C:LevelLive()
  local k = self.key
  local c = k and self:Char(k)
  if not c or not c.playedLevel or not self.playedAt or UnitLevel("player") >= 60 then return nil end
  local lv = UnitLevel("player")
  local mx = UnitXPMax("player") or 0
  local frac = mx > 0 and (UnitXP("player") or 0) / mx or 0
  local est = self:LevelEst(k, lv) * 3600
  local busy = self:BusyAt(lv)
  local spent = math.max(0, c.playedLevel + (GetTime() - self.playedAt) - busy)
  local expect = est * frac
  return { lv = lv, spent = spent, est = est, expect = expect, ahead = expect - spent, frac = frac, busy = busy,
    played = (c.played or 0) + (GetTime() - self.playedAt) }
end

-- the next n levels: estimate per level and the total /played when you should reach it
function C:LevelPlan(k, n)
  local out = {}
  local lvl = self:Lv(k)
  local c = self:Char(k)
  local played = c and c.played or 0
  if k == self.key and self.playedAt then played = played + (GetTime() - self.playedAt) end
  local cur = math.floor(lvl)
  local t = played + self:LevelEst(k, cur) * 3600 * (1 - (lvl - cur))
  for L = cur + 1, math.min(60, cur + n) do
    out[#out + 1] = { lv = L, reach = t, est = L < 60 and self:LevelEst(k, L) * 3600 or 0 }
    t = t + (L < 60 and self:LevelEst(k, L) * 3600 or 0)
  end
  return out
end

-- tonight: hours left in today's plan, and the level to reach by the end of it
function C:Tonight(k)
  k = k or self.key
  local lv = self:Lv(k)
  local today = self:Midnight(time())
  local plan = self:DayHours(today)
  local played = self.DayStats and (self:DayStats(date("%Y-%m-%d"))) or 0
  local left = math.max(0, plan - played)
  local g = self:NextGoalFor(k)
  local target, onPlan
  if g and g.by then
    target = self:ExpectedLv(g, today + DAY)
    onPlan = true
  end
  if not target then
    local m = self:ClassMult(k) * self:ProfMult(k) * (self:Pace(k))
    target = C.lvAfter(lv, left / m)
  end
  if g then target = math.min(target, g.to) end
  return { target = target, left = left, plan = plan, played = played, onPlan = onPlan, lv = lv, goal = g }
end

-- time at professions, the Auction House, bank and mailbox, per level. It doesn't count against the
-- level timer, so an afternoon of crafting doesn't make your levelling look slow.
local open, since = {}, nil
function C:BusyAt(lv)
  local c = self.key and self:Char(self.key)
  local b = c and c.busy and c.busy[lv] or 0
  if since then b = b + (GetTime() - since) end
  return b
end
local function flush()
  if not since then return end
  local c = C.key and C:Char(C.key)
  local lv = UnitLevel("player")
  if c and lv then
    c.busy = c.busy or {}
    c.busy[lv] = (c.busy[lv] or 0) + (GetTime() - since)
  end
  since = nil
end
C.FlushBusy = flush
local PAIRS = { TRADE_SKILL_SHOW = { "trade", true }, TRADE_SKILL_CLOSE = { "trade", false }, CRAFT_SHOW = { "craft", true }, CRAFT_CLOSE = { "craft", false },
  AUCTION_HOUSE_SHOW = { "ah", true }, AUCTION_HOUSE_CLOSED = { "ah", false }, BANKFRAME_OPENED = { "bank", true }, BANKFRAME_CLOSED = { "bank", false },
  MAIL_SHOW = { "mail", true }, MAIL_CLOSED = { "mail", false } }
local bev = CreateFrame("Frame")
for e in pairs(PAIRS) do pcall(bev.RegisterEvent, bev, e) end
pcall(bev.RegisterEvent, bev, "PLAYER_LEVEL_UP"); pcall(bev.RegisterEvent, bev, "PLAYER_LOGOUT")
bev:SetScript("OnEvent", function(_, e)
  if not C.db then return end
  if e == "PLAYER_LEVEL_UP" or e == "PLAYER_LOGOUT" then
    -- close the old level's count; keep counting into the new level if a window is still open
    local was = since ~= nil
    if e == "PLAYER_LEVEL_UP" and since then
      local c = C.key and C:Char(C.key)
      local lv = UnitLevel("player") - 1
      if c then c.busy = c.busy or {}; c.busy[lv] = (c.busy[lv] or 0) + (GetTime() - since) end
      since = GetTime()
    else flush() end
    return
  end
  local p = PAIRS[e]
  if not p then return end
  open[p[1]] = p[2] or nil
  if next(open) then since = since or GetTime() else flush() end
end)

-- goal pace in hours: how far ahead or behind the goal's deadline plan you are, in hours of play
function C:GoalAheadHours(g)
  if not g or not g.by then return nil end
  local e = self:ExpectedLv(g, time())
  if not e then return nil end
  local L = self:Lv(g.ch)
  if L >= e then return self:Hours(g.ch, e, L) end
  return -self:Hours(g.ch, L, e)
end
