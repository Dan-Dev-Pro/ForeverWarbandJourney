-- Forever Warband Journey: optional link to the Journey levelling guide addon.
-- Reads only the player's own progress (Journey_Character: current guide id and step id).
-- No guide content is read or stored.
local C = FWJ

local ZONES = {
  D = "Durotar", M = "Mulgore", TG = "Tirisfal Glades", SF = "Silverpine Forest", B = "The Barrens", NB = "Northern Barrens",
  SB = "Southern Barrens", SP = "Stonetalon", AS = "Ashenvale", HF = "Hillsbrad", TN = "Thousand Needles", AH = "Arathi Highlands",
  DS = "Desolace", STV = "Stranglethorn", BA = "Badlands", SW = "Swamp of Sorrows", DM = "Dustwallow Marsh", TA = "Tanaris",
  FE = "Feralas", HI = "The Hinterlands", AZ = "Azshara", SG = "Searing Gorge", UG = "Un'Goro", FL = "Felwood", BS = "Burning Steppes",
  WP = "Western Plaguelands", EP = "Eastern Plaguelands", WS = "Winterspring", SI = "Silithus", BL = "Blasted Lands",
}

function C:JourneyName(id)
  if not id then return nil end
  local lv, z = id:match("^[HA](%d+)(%u+)")
  if not lv then return id end
  return string.format("%s %d+", ZONES[z] or z, tonumber(lv))
end

function C:JourneyStep(step)
  if not step then return nil end
  local sec, st = step:match("^(%d+)%-(%w+)$")
  if sec then return string.format("section %d, step %s", tonumber(sec), (st:gsub("^0+(%d)", "%1"))) end
  return step
end

function C:JourneyNow()
  local jc = rawget(_G, "Journey_Character")
  if type(jc) ~= "table" or not jc.lastGuide then return nil end
  local bm = type(jc.bookmarks) == "table" and jc.bookmarks[jc.lastGuide]
  return jc.lastGuide, bm and bm.stepID
end

-- called from the HUD ticker every 2 s; time on a guide only counts while not AFK
function C:JourneyTick()
  local k = self.key
  local c = k and self:Char(k)
  if not c then return end
  local g, step = self:JourneyNow()
  if not g then return end
  c.jg = c.jg or {}
  local e = c.jg[g]
  local lv = self:Lv(k)
  if not e then e = { sec = 0, lv0 = lv, first = time() }; c.jg[g] = e end
  local now = GetTime()
  if self.jLast and self.jLastG == g and not (UnitIsAFK and UnitIsAFK("player")) then
    local d = now - self.jLast
    if d > 0 and d < 30 then e.sec = e.sec + d end
  end
  self.jLast, self.jLastG = now, g
  e.lv1, e.last, e.step = lv, time(), step
  c.jny = g
end

function C:JourneyLine()
  local g, step = self:JourneyNow()
  if not g then return nil end
  local c = self:Char(self.key)
  local e = c and c.jg and c.jg[g]
  local t = e and e.sec or 0
  local tt = t >= 3600 and string.format("%dh %02dm", t / 3600, (t % 3600) / 60) or string.format("%dm", t / 60)
  return string.format("|cffe8b64cJourney|r %s  |cffa89a84/|r %s  |cffa89a84/|r %s", self:JourneyName(g), self:JourneyStep(step) or "-", tt)
end

function C:JourneyTooltip(tt)
  local c = self:Char(self.key)
  if not c or not c.jg or not next(c.jg) then return end
  tt:AddLine(" ")
  tt:AddLine("Journey guides on this character", 1, .82, 0)
  local list = {}
  for g, e in pairs(c.jg) do list[#list + 1] = { g, e } end
  table.sort(list, function(a, b) return (a[2].first or 0) < (b[2].first or 0) end)
  for _, r in ipairs(list) do
    local e = r[2]
    local gain = (e.lv1 or e.lv0 or 0) - (e.lv0 or 0)
    local h = (e.sec or 0) / 3600
    tt:AddDoubleLine(self:JourneyName(r[1]) .. (r[1] == c.jny and " (now)" or ""),
      string.format("%.1f h  +%.1f lv%s", h, gain, h > 0.25 and string.format("  %.1f lv/h", gain / h) or ""), .8, .8, .8, 1, 1, 1)
  end
end
