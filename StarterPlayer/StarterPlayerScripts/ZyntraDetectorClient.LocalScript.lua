local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local SoundService=game:GetService("SoundService")
local player=Players.LocalPlayer
local Visual=require(RS:WaitForChild("ZyntraDetectorVisual"))
local remote=RS:WaitForChild("Remotes"):WaitForChild("ZyntraDetector")
local model,connection,sound
local function clear()
 if connection then connection:Disconnect() connection=nil end
 if model then model:Destroy() model=nil end
 if sound then sound:Destroy() sound=nil end
end
remote.OnClientEvent:Connect(function(event,reading,expires)
 if event~="reading" or not Visual.Colors[reading] or type(expires)~="number" then return end
 clear()
 local text
 model,text=Visual.Build(workspace.CurrentCamera)
 text.Text="ZYNTRA\n"..reading text.TextColor3=Visual.Colors[reading]
 sound=Instance.new("Sound") sound.Name="LocalDetectorPing"
 sound.SoundId="rbxasset://sounds/volume_slider.ogg" sound.Volume=.12 sound.PlaybackSpeed=1.4 sound.Parent=SoundService sound:Play()
 local char=player.Character
 connection=RunService.RenderStepped:Connect(function()
  local hum=char and char:FindFirstChildOfClass("Humanoid")
  if player.Character~=char or not hum or hum.Health<=0 or player:GetAttribute("InRound")~=true
   or workspace:GetAttribute("RoundActive")~=true or player:GetAttribute("Escaped")==true
   or workspace:GetServerTimeNow()>=expires then clear() return end
  local camera=workspace.CurrentCamera
  if camera then model:PivotTo(camera.CFrame*CFrame.new(1.05,-.7,-2.7)*CFrame.Angles(0,math.pi,0)) end
 end)
end)
player.CharacterRemoving:Connect(clear)
script.Destroying:Connect(clear)
