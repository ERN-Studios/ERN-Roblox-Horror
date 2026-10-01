
local p=game.Players.LocalPlayer local w=workspace["Level 6 Generated World"]
local pair
for _,d in w:GetDescendants() do if d:IsA("PointLight") and d:GetAttribute("Level6_CeilingBounce") then pair={fill=d,main=d.Parent.Parent} break end end
assert(pair)
local old={enabled=pair.main.Enabled,brightness=pair.main.Brightness,color=pair.main.Color}
pair.main.Enabled=false pair.main.Brightness=0 task.wait(.12)
local off=not pair.fill.Enabled and pair.fill.Brightness==0
pair.main.Enabled=true pair.main.Brightness=old.brightness*.5 task.wait(.12)
local half=math.abs(pair.fill.Brightness-.08)<.0001
pair.main.Brightness=old.brightness pair.main.Enabled=old.enabled task.wait(.12)
local restored=math.abs(pair.fill.Brightness-.16)<.0001 and pair.fill.Enabled==old.enabled
local state=game.ReplicatedStorage["Level 6 State"]
assert(state:GetAttribute("Level6_BlackoutActive")==false and state:GetAttribute("Level6_ExitUnlocked")==false)
state:SetAttribute("Level6_BlackoutActive",true)
task.wait(.65)
local bad={} local fills=0
for _,d in w:GetDescendants() do if d:IsA("Light") then
if d:GetAttribute("Level6_CeilingBounce") then fills+=1 end
if d.Enabled or d.Brightness~=0 then bad[#bad+1]=d:GetFullName() end
end end
state:SetAttribute("Level6_BlackoutActive",false)
task.wait(.65)
local recoveryBad={}
for _,d in w:GetDescendants() do if d:IsA("PointLight") and d:GetAttribute("Level6_CeilingBounce") then
local main=d.Parent.Parent local normal=d:GetAttribute("Level6_PrimaryBrightness")
if d.Enabled~=main.Enabled or math.abs(d.Brightness-.16*math.clamp(main.Brightness/normal,0,1))>.0001 then recoveryBad[#recoveryBad+1]=d:GetFullName() end
end end
return game:GetService("HttpService"):JSONEncode({test="Controlled Play phase smoke check, not natural music/objective progression",ballastOff=off,ballastHalf=half,ballastRestore=restored,blackoutFillCount=fills,blackoutLightsLeftOn=bad,restorationMismatches=recoveryBad,health=p.Character.Humanoid.Health})
