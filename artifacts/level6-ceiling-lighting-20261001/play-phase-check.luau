
local w=workspace["Level 6 Generated World"] local s=game.ReplicatedStorage["Level 6 State"]
local keys={"Level6_PreBlackoutActive","Level6_PreBlackoutStartedAtServerTime","Level6_PreBlackoutUntilServerTime","Level6_RecoveryFlickerActive","Level6_RecoveryFlickerStartedAtServerTime","Level6_RecoveryFlickerUntilServerTime","Level6_ExitUnlocked","Level6_CompletionDimStartedAtServerTime","Level6_CompletionDimDuration"}
local saved={} for _,k in keys do saved[k]=s:GetAttribute(k) end
local function mismatch()
 local bad={} for _,d in w:GetDescendants() do if d:IsA("PointLight") and d:GetAttribute("Level6_CeilingBounce") then
 local main=d.Parent.Parent local normal=d:GetAttribute("Level6_PrimaryBrightness")
 if d.Enabled~=main.Enabled or math.abs(d.Brightness-.16*math.clamp(main.Brightness/normal,0,1))>.0001 then bad[#bad+1]=d:GetFullName() end end end return bad
end
s:SetAttribute("Level6_PreBlackoutStartedAtServerTime",workspace:GetServerTimeNow())
s:SetAttribute("Level6_PreBlackoutUntilServerTime",workspace:GetServerTimeNow()+5)
s:SetAttribute("Level6_PreBlackoutActive",true) task.wait(.42)
local pre=mismatch()
s:SetAttribute("Level6_PreBlackoutActive",false) task.wait(.25)
s:SetAttribute("Level6_RecoveryFlickerStartedAtServerTime",workspace:GetServerTimeNow())
s:SetAttribute("Level6_RecoveryFlickerUntilServerTime",workspace:GetServerTimeNow()+3.2)
s:SetAttribute("Level6_RecoveryFlickerActive",true) task.wait(.42)
local recovery=mismatch()
s:SetAttribute("Level6_RecoveryFlickerActive",false) task.wait(.25)
s:SetAttribute("Level6_CompletionDimStartedAtServerTime",workspace:GetServerTimeNow())
s:SetAttribute("Level6_CompletionDimDuration",5.5)
s:SetAttribute("Level6_ExitUnlocked",true) task.wait(2.85)
local mid=mismatch()
local fadeSamples={} for _,d in w:GetDescendants() do if d:IsA("PointLight") and d:GetAttribute("Level6_CeilingBounce") and #fadeSamples<4 then fadeSamples[#fadeSamples+1]=d.Brightness end end
task.wait(3.2)
local lit={} for _,d in w:GetDescendants() do if d:IsA("Light") and (d.Enabled or d.Brightness>.0001) then lit[#lit+1]=d:GetFullName() end end
for _,k in keys do s:SetAttribute(k,saved[k]) end task.wait(.65)
return game:GetService("HttpService"):JSONEncode({test="Controlled client phase flags in actual Play, no natural full-CD progression claimed",preMismatches=pre,recoveryMismatches=recovery,midFadeMismatches=mid,midFadeSamples=fadeSamples,completionLightsRemaining=lit,restoredMismatches=mismatch(),health=game.Players.LocalPlayer.Character.Humanoid.Health})
