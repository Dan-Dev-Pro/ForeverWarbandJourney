-- Forever Warband Journey: error log. Any error from this addon is saved to FWJ_ERRORS (in the
-- SavedVariables file) with its stack, so it can be read after a /reload or logout.
FWJ = FWJ or {}
local C = FWJ
local buffer, seen = {}, {}
local function record(msg, stack)
  msg = tostring(msg)
  if seen[msg] then seen[msg].n = seen[msg].n + 1; return end
  local e = { msg = msg, stack = stack, t = time and time() or 0, n = 1, v = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("ForeverWarbandJourney", "Version") }
  seen[msg] = e
  buffer[#buffer + 1] = e
  if #buffer == 1 and DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Forever Warband Journey:|r hit an error. It's been saved; the rest of the addon keeps running.")
  end
  if FWJ_ERRORS then table.insert(FWJ_ERRORS, e); while #FWJ_ERRORS > 30 do table.remove(FWJ_ERRORS, 1) end end
end
C.RecordError = record
local prev = geterrorhandler and geterrorhandler()
if seterrorhandler and prev then
  seterrorhandler(function(msg, ...)
    if type(msg) == "string" and msg:find("ForeverWarbandJourney") then record(msg, debugstack and debugstack(2, 20, 0)) end
    return prev(msg, ...)
  end)
end
-- run a function, logging (once) instead of throwing; used for timers and refreshes that repeat
function C.Safe(f, ...)
  local ok, err = xpcall(f, function(e) record(e, debugstack and debugstack(2, 20, 0)); return e end, ...)
  return ok, err
end
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, _, name)
  if name ~= "ForeverWarbandJourney" then return end
  FWJ_ERRORS = {}   -- each session starts fresh; this session's errors are what gets saved
  for _, e in ipairs(buffer) do table.insert(FWJ_ERRORS, e) end
end)
