local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local SoundService=game:GetService("SoundService")
local player=Players.LocalPlayer
local Visual=require(RS:WaitForChild("ZyntraDetectorVisual"))
local UIDevice=require(RS:WaitForChild("UIDevice"))
local remote=RS:WaitForChild("Remotes"):WaitForChild("ZyntraDetector")
local gui,preview,connection,sound
local function clear()
 if connection then connection:Disconnect() connection=nil end
 if preview then preview:Destroy() preview=nil end
 if gui then gui:Destroy() gui=nil end
 if sound then sound:Destroy() sound=nil end
end
remote.OnClientEvent:Connect(function(event,reading,expires)
 if event~="reading" or not Visual.Colors[reading] or type(expires)~="number" then return end
 clear()
 gui=Instance.new("ScreenGui") gui.Name="ZyntraDetectorReadout"
 gui.ResetOnSpawn=false gui.DisplayOrder=1100 gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets
 gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling gui.Parent=player:WaitForChild("PlayerGui")
 preview=Visual.Preview(gui)
 local caption=Instance.new("TextLabel") caption.Name="ReadableScanStatus"
 caption.AnchorPoint=Vector2.new(.5,0) caption.BackgroundColor3=Color3.fromRGB(9,14,19)
 caption.BackgroundTransparency=.08 caption.BorderSizePixel=0 caption.Font=Enum.Font.GothamBold
 caption.TextSize=14 caption.TextWrapped=true caption.Parent=gui
 local corner=Instance.new("UICorner") corner.CornerRadius=UDim.new(0,7) corner.Parent=caption
 sound=Instance.new("Sound") sound.Name="LocalDetectorPing"
 sound.SoundId="rbxasset://sounds/volume_slider.ogg" sound.Volume=.12 sound.PlaybackSpeed=1.4 sound.Parent=SoundService sound:Play()
 local char=player.Character
 connection=RunService.RenderStepped:Connect(function()
  local hum=char and char:FindFirstChildOfClass("Humanoid")
  local remaining=expires-workspace:GetServerTimeNow()
  if player.Character~=char or not hum or hum.Health<=0 or player:GetAttribute("InRound")~=true
   or workspace:GetAttribute("RoundActive")~=true or player:GetAttribute("Escaped")==true
   or player:GetAttribute("Spectating")==true or remaining<=0 then clear() return end
  -- Reading floats above ordinary HUDs. Important full-screen modals take
  -- precedence; do not cover death, loading, store or a dispatch briefing.
  gui.Enabled=not UIDevice.ScreenOwningModalOpen() and player:GetAttribute("DispatchBriefingOpen")~=true
  local safe=UIDevice.Layout().Safe
  local h=math.min(420,math.max(225,safe.Height*.65))
  local w=h*.66
  preview.Root.Size=UDim2.fromOffset(w,h)
  -- Centre strip leaves both touch-control banks free. Four-second lifetime.
  preview.Root.AnchorPoint=Vector2.new(.5,1)
  preview.Root.Position=UIDevice.LocalPosition(gui,(safe.Left+safe.Right)/2,safe.Bottom-48)
  preview:SetReading(reading,false,remaining)
  caption.Size=UDim2.fromOffset(math.min(270,safe.Width-32),32)
  caption.Position=UIDevice.LocalPosition(gui,(safe.Left+safe.Right)/2,safe.Bottom-45)
  caption.Text=Visual.Labels[reading]..string.format("  ·  %.1fs",remaining)
  caption.TextColor3=Visual.Colors[reading]
 end)
end)
player.CharacterRemoving:Connect(clear)
script.Destroying:Connect(clear)
