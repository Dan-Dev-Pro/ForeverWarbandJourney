-- Forever Warband Journey: minimap button, level-up nudges, mailbox helper, slash commands
local C = FWJ

function C:MinimapButton()
  if self.mini or not Minimap then return end
  local b = CreateFrame("Button", "FWJMinimapButton", Minimap)
  b:SetSize(31, 31); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local icon = b:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01"); icon:SetSize(20, 20); icon:SetPoint("CENTER", 0, 1)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); border:SetSize(53, 53); border:SetPoint("TOPLEFT")
  local function place()
    local a = math.rad(C.db.opt.mini or 200)
    b:ClearAllPoints(); b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * 80, math.sin(a) * 80)
  end
  place()
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnDragStart", function(s) s:SetScript("OnUpdate", function()
    local mx, my = Minimap:GetCenter(); local cx, cy = GetCursorPosition(); local sc = Minimap:GetEffectiveScale()
    C.db.opt.mini = math.deg(math.atan2(cy / sc - my, cx / sc - mx)); place() end) end)
  b:SetScript("OnDragStop", function(s) s:SetScript("OnUpdate", nil) end)
  b:SetScript("OnClick", function() C:Toggle() end)
  b:SetScript("OnEnter", function(s)
    GameTooltip:SetOwner(s, "ANCHOR_LEFT"); GameTooltip:AddLine(C.NAME)
    local g = C:ActiveGoal()
    if g then GameTooltip:AddLine(string.format("Active goal: %s to %d", C:Short(g.ch), g.to), 1, 1, 1) end
    GameTooltip:AddLine("Click to open. Drag to move.", .7, .7, .7); GameTooltip:Show() end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  self.mini = b
end

function C:LevelPopup(lv)
  local k = self.key
  local c = self:Char(k)
  local lines = {}
  local g = self:NextGoalFor(k)
  for _, gg in ipairs(self.db.goals) do if gg.ch == k and gg.to == lv then lines[#lines + 1] = "Goal reached: level " .. lv .. "!" end end
  if lv >= 10 then lines[#lines + 1] = "New talent point to spend." end
  if lv % 2 == 0 and lv < 60 then lines[#lines + 1] = "New spell ranks at your class trainer." end
  for _, m in ipairs(C.MILESTONES) do if m[1] == lv then lines[#lines + 1] = m[2] .. "." end end
  for name, v in pairs(c.profs or {}) do
    local a = self:ProfAdvice(k, name, v[1], v[2])
    if a.state == "train" then lines[#lines + 1] = name .. ": " .. a.text .. "." end
  end
  for _, l in ipairs(lines) do self:Print("Level " .. lv .. ": " .. l) end
  if self.db.opt.popups and RaidNotice_AddMessage and RaidWarningFrame and #lines > 0 then
    RaidNotice_AddMessage(RaidWarningFrame, "Level " .. lv .. ": " .. lines[1], ChatTypeInfo["RAID_WARNING"])
  end
  self:Refresh()
end

function C:MailHelper()
  local ck = self:CharWithRole("Crafter")
  if not ck or ck == self.key then return end
  local items = self:MailItems()
  if #items == 0 then return end
  local links = {}
  for i = 1, math.min(#items, 10) do links[#links + 1] = items[i][3] end
  self:Print(string.format("%d item%s for %s: %s", #items, #items > 1 and "s" or "", self:Short(ck), table.concat(links, " ")))
end

SLASH_FWJ1 = "/fwj"
SLASH_FWJ2 = "/warband"
SlashCmdList.FWJ = function(msg)
  local cmd, arg = (msg or ""):match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()
  local o = C.db.opt
  if cmd == "target" and (arg == "" or C.ParseDate(arg)) then
    o.target = arg ~= "" and arg or nil; C:Print(arg ~= "" and ("target date " .. arg .. ".") or "target date cleared."); C:Refresh()
  elseif cmd == "hours" and arg:match("^%d+%s+%d+$") then
    local a, b = arg:match("^(%d+)%s+(%d+)$"); o.wd, o.we = tonumber(a), tonumber(b); C:Print(string.format("%d h weekdays, %d h weekend days.", o.wd, o.we)); C:Refresh()
  elseif cmd == "hud" then o.hud = not o.hud; if C.hud then C.hud:SetShown(o.hud) end
  elseif cmd == "lock" then o.lock = not o.lock; C:Print("pace tracker " .. (o.lock and "locked." or "unlocked."))
  elseif cmd == "goals" then C.tab = "Goals"; if not C.frame:IsShown() then C:Toggle() else C:Refresh() end
  elseif cmd == "debug" then
    local gf = GetMouseFocus and GetMouseFocus() or (GetMouseFoci and GetMouseFoci()[1])
    local nm = gf and (gf.GetName and gf:GetName() or tostring(gf)) or "nothing"
    local par = gf and gf.GetParent and gf:GetParent()
    C:Print(string.format("mouse over: %s (parent %s, strata %s, level %s, mouse %s)", tostring(nm),
      tostring(par and par.GetName and par:GetName() or par), tostring(gf and gf.GetFrameStrata and gf:GetFrameStrata()),
      tostring(gf and gf.GetFrameLevel and gf:GetFrameLevel()), tostring(gf and gf.IsMouseEnabled and gf:IsMouseEnabled())))
  elseif cmd == "profs" then
    local c = C:Char(C.key)
    C:ReadProfs(c)
    local apis = string.format("GetProfessions %s, C_SkillInfo %s, GetSkillLineInfo %s, C_TradeSkillUI %s", tostring(GetProfessions ~= nil),
      tostring(C_SkillInfo ~= nil), tostring(GetSkillLineInfo ~= nil), tostring(C_TradeSkillUI ~= nil))
    C:Print(apis)
    local n = 0
    for name, v in pairs(c.profs or {}) do n = n + 1; C:Print(string.format("%s %d / %d", name, v[1], v[2])) end
    for name, v in pairs(c.secondary or {}) do C:Print(string.format("%s %d / %d", name, v[1], v[2])) end
    if n == 0 then C:Print("no primary professions read") end
    for prof, list in pairs(c.known or {}) do local m = 0; for _ in pairs(list) do m = m + 1 end; C:Print(string.format("%s: %d recipes read", prof, m)) end
  elseif cmd == "help" then
    C:Print("/fwj  open or close || /fwj goals || /fwj hud || /fwj lock || /fwj hours 2 4 || /fwj target 2026-12-02 || /fwj profs")
  else C:Toggle() end
end
