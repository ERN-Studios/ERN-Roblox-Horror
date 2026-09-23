-- A bounded server snapshot. No client positions, targets or ownership claims.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local CS=game:GetService("CollectionService")
local Config=require(RS:WaitForChild("ZyntraConfig")).Detector
local Sensing=require(script.Parent:WaitForChild("ZyntraDetectorSensing"))
-- ANALYTICS_20260921. Measurement only, after the scan is granted.
local Analytics=require(script.Parent:WaitForChild("ZyntraAnalytics"))
local remote=Instance.new("RemoteEvent")
remote.Name="ZyntraDetector"
remote.Parent=RS:WaitForChild("Remotes")
local requests=setmetatable({},{__mode="k"})
remote.OnServerEvent:Connect(function(player,action)
 if action~="scan" then return end
 local now=workspace:GetServerTimeNow()
 if now-(requests[player] or -math.huge)<.5 then return end
 requests[player]=now
 if player:GetAttribute("ZyntraOwnsEntityDetector")~=true then
  remote:FireClient(player,"refused","DETECTOR PASS REQUIRED") return
 end
 local char=player.Character
 local hum=char and char:FindFirstChildOfClass("Humanoid")
 local root=char and char:FindFirstChild("HumanoidRootPart")
 if not root or not hum or hum.Health<=0 or (root.Anchored and player:GetAttribute("Level3_Hiding")~=true)
  or player:GetAttribute("InRound")~=true or player:GetAttribute("Escaped")==true
  or player:GetAttribute("Spectating")==true or player:GetAttribute("Level2_ExitTransition")==true
  or workspace:GetAttribute("RoundActive")~=true then
  remote:FireClient(player,"refused","SCAN DURING A RUN") return
 end
 if now<(player:GetAttribute("ZyntraDetectorReadyAt") or 0) then return end
 local reading=Sensing.Read(root.Position,workspace:GetAttribute("SelectedLevel"),Config)
 player:SetAttribute("ZyntraDetectorReadyAt",now+Config.Cooldown)
 player:SetAttribute("ZyntraDetectorReading",reading)
 player:SetAttribute("ZyntraDetectorReadingUntil",now+Config.ReadingSeconds)
 Analytics.ItemUse(player,"DetectorScan",workspace:GetAttribute("SelectedLevel"))
 remote:FireClient(player,"reading",reading,now+Config.ReadingSeconds)
end)
local function watch(player)
 local function clear() player:SetAttribute("ZyntraDetectorReadingUntil",0) end
 player.CharacterRemoving:Connect(clear)
 player:GetAttributeChangedSignal("InRound"):Connect(function()
  if player:GetAttribute("InRound")~=true then clear() end
 end)
end
Players.PlayerAdded:Connect(watch)
for _,p in ipairs(Players:GetPlayers()) do watch(p) end
