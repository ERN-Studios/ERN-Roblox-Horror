-- Exact scoped policy bodies extracted from authoritative baseline and task patch.
local Color3={fromRGB=function(r,g,b) return {r,g,b} end}
local attrs={InRound=true}
local player={GetAttribute=function(_,key) return attrs[key] end}
local UIS={MouseEnabled=true,MouseIconEnabled=false,MouseBehavior="LockCenter"}
local queueShade={Visible=false}
local Enum={MouseBehavior={Default="Default"}}
local policy=(function()
local completion = {returnVisible = false,
	color = Color3.fromRGB(127, 218, 166)}
local function shouldShowCursor()
 return player:GetAttribute("InRound") ~= true
  or queueShade.Visible
  or player:GetAttribute("DevPhoneOpen") == true
  or player:GetAttribute("Level5ColourLockOpen") == true
  or player:GetAttribute("ZyntraReentryOpen") == true
  -- The PARTY DOWN card is this file's own modal and frees its own cursor. It
  -- does reach ZyntraReentryOpen as well, but only via ZyntraStore's listener
  -- on a deferred attribute hop -- a modal owned here must not need another
  -- script to have run before it can be clicked.
  or player:GetAttribute("PartyDownCardOpen") == true
  or completion.returnVisible
end

local function refreshCursor()
 if not UIS.MouseEnabled then return end
 local visible = shouldShowCursor()
 if visible then UIS.MouseBehavior = Enum.MouseBehavior.Default end
 UIS.MouseIconEnabled = visible
end

return {show=shouldShowCursor,refresh=refreshCursor,completion=completion}

end)()
local before=(function()
local completion = {returnVisible = false,
	color = Color3.fromRGB(127, 218, 166)}
local function shouldShowCursor()
 return player:GetAttribute("InRound") ~= true
  or queueShade.Visible
  or player:GetAttribute("DevPhoneOpen") == true
  or player:GetAttribute("ZyntraReentryOpen") == true
  -- The PARTY DOWN card is this file's own modal and frees its own cursor. It
  -- does reach ZyntraReentryOpen as well, but only via ZyntraStore's listener
  -- on a deferred attribute hop -- a modal owned here must not need another
  -- script to have run before it can be clicked.
  or player:GetAttribute("PartyDownCardOpen") == true
  or completion.returnVisible
end

local function refreshCursor()
 if not UIS.MouseEnabled then return end
 local visible = shouldShowCursor()
 if visible then UIS.MouseBehavior = Enum.MouseBehavior.Default end
 UIS.MouseIconEnabled = visible
end

return {show=shouldShowCursor,refresh=refreshCursor,completion=completion}

end)()
local completion=policy.completion
local function enforce()

 if UIS.MouseEnabled and (queueShade.Visible or player:GetAttribute("DevPhoneOpen") == true
  or player:GetAttribute("ZyntraReentryOpen") == true
  or player:GetAttribute("PartyDownCardOpen") == true
  or player:GetAttribute("Level5ColourLockOpen") == true or completion.returnVisible) then
  UIS.MouseBehavior = Enum.MouseBehavior.Default
  UIS.MouseIconEnabled = true
 end
end
local n=0
local function check(ok,why) n+=1;assert(ok,why) end
check(not policy.show(),"normal gameplay hides pointer")
attrs.Level5ColourLockOpen=true
check(not before.show(),"baseline reproduces missing padlock ownership")
check(policy.show(),"padlock participates in the existing owner")
policy.refresh();check(UIS.MouseIconEnabled and UIS.MouseBehavior=="Default","immediate free visible mouse")
UIS.MouseBehavior="LockCenter";UIS.MouseIconEnabled=false;enforce()
check(UIS.MouseIconEnabled and UIS.MouseBehavior=="Default","camera override is corrected while open")
attrs.Level5ColourLockOpen=false;policy.refresh();check(not UIS.MouseIconEnabled,"close returns gameplay icon policy")
UIS.MouseBehavior="CameraOwned";enforce();check(UIS.MouseBehavior=="CameraOwned","closed padlock stops forcing free mouse")
attrs.Level5ColourLockOpen=true;policy.refresh();check(UIS.MouseIconEnabled,"reopen works")
attrs.ZyntraReentryOpen=true;attrs.Level5ColourLockOpen=false;policy.refresh();check(UIS.MouseIconEnabled,"close respects another modal")
attrs.ZyntraReentryOpen=nil;attrs.InRound=false;policy.refresh();check(UIS.MouseIconEnabled,"lobby return keeps pointer")
UIS.MouseBehavior="TemporaryRightButton";enforce();check(UIS.MouseBehavior=="TemporaryRightButton","lobby camera right-button behavior untouched")
attrs.InRound=true;UIS.MouseEnabled=false;UIS.MouseIconEnabled=false;UIS.MouseBehavior="TouchCamera";attrs.Level5ColourLockOpen=true
policy.refresh();enforce();check(not UIS.MouseIconEnabled and UIS.MouseBehavior=="TouchCamera","pointer policy does not affect touch-only input")
print("PASS "..n.." cursor-policy regression assertions")
