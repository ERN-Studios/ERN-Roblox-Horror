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
 -- DETECTOR_LIVE_20261008 (owner: "last for 30 seconds and have a cooldown of 10 seconds"). The detector stays on
 -- for ReadingSeconds and its band FOLLOWS the entity for that long (a reading thirty seconds old would be a
 -- lie); the cooldown counts from the moment it switches off. Still only a band: no position ever leaves here.
 local expires=now+Config.ReadingSeconds
 player:SetAttribute("ZyntraDetectorReadyAt",expires+Config.Cooldown)
 player:SetAttribute("ZyntraDetectorReading",reading)
 player:SetAttribute("ZyntraDetectorReadingUntil",expires)
 task.spawn(function()
  while true do
   task.wait(Config.RefreshSeconds or .5)
   local clock=workspace:GetServerTimeNow()
   if player.Parent~=Players or player:GetAttribute("ZyntraDetectorReadingUntil")~=expires or clock>=expires then return end
   local body=player.Character
   local life=body and body:FindFirstChildOfClass("Humanoid")
   local at=body and body:FindFirstChild("HumanoidRootPart")
   if not at or not life or life.Health<=0 or player:GetAttribute("InRound")~=true
    or player:GetAttribute("Escaped")==true or player:GetAttribute("Spectating")==true
    or workspace:GetAttribute("RoundActive")~=true then
    -- Off early (a death, the exit, the round's end): the cooldown counts from now, not from the full 30.
    player:SetAttribute("ZyntraDetectorReadingUntil",0)
    player:SetAttribute("ZyntraDetectorReadyAt",math.min(player:GetAttribute("ZyntraDetectorReadyAt") or 0,clock+Config.Cooldown))
    return
   end
   local band=Sensing.Read(at.Position,workspace:GetAttribute("SelectedLevel"),Config)
   if band~=player:GetAttribute("ZyntraDetectorReading") then player:SetAttribute("ZyntraDetectorReading",band) end
  end
 end)
 -- CHALLENGES_20260923: a scan is an aid, so this run is assisted.
 player:SetAttribute("ZyntraRunAided",true)
 Analytics.ItemUse(player,"DetectorScan",workspace:GetAttribute("SelectedLevel"))
 remote:FireClient(player,"reading",reading,expires)
end)
local function watch(player)
 local function clear()
  player:SetAttribute("ZyntraDetectorReadingUntil",0)
  -- the cooldown of a detector that was cut short counts from now (DETECTOR_LIVE_20261008)
  local ready=player:GetAttribute("ZyntraDetectorReadyAt")
  if type(ready)=="number" then
   player:SetAttribute("ZyntraDetectorReadyAt",math.min(ready,workspace:GetServerTimeNow()+Config.Cooldown))
  end
 end
 player.CharacterRemoving:Connect(clear)
 player:GetAttributeChangedSignal("InRound"):Connect(function()
  if player:GetAttribute("InRound")~=true then clear() end
 end)
end
Players.PlayerAdded:Connect(watch)
for _,p in ipairs(Players:GetPlayers()) do watch(p) end
