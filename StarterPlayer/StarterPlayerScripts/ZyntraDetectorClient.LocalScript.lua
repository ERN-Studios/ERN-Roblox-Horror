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
 player:SetAttribute("ZyntraDetectorStowed",nil)      -- a fresh scan always comes up in the hand
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
 local shownAt=os.clock()
 connection=RunService.RenderStepped:Connect(function()
  local hum=char and char:FindFirstChildOfClass("Humanoid")
  local remaining=expires-workspace:GetServerTimeNow()
  if player.Character~=char or not hum or hum.Health<=0 or player:GetAttribute("InRound")~=true
   or workspace:GetAttribute("RoundActive")~=true or player:GetAttribute("Escaped")==true
   or player:GetAttribute("Spectating")==true or remaining<=0 then clear() return end
  -- Reading floats above ordinary HUDs. Important full-screen modals take
  -- precedence; do not cover death, loading, store or a dispatch briefing.
  gui.Enabled=not UIDevice.ScreenOwningModalOpen() and player:GetAttribute("DispatchBriefingOpen")~=true
  -- DETECTOR_LIVE_20261008: the band follows the entity for as long as the detector is on (the server
  -- republishes it on this attribute), and the device goes when the server says the reading is over.
  local live=player:GetAttribute("ZyntraDetectorReading")
  if Visual.Colors[live] then reading=live end
  -- (not in the first second: the attribute of a reading that was cut short may still be on its way out)
  if os.clock()-shownAt>1 and (player:GetAttribute("ZyntraDetectorReadingUntil") or expires)<=0 then clear() return end
  local safe=UIDevice.Layout().Safe
  -- DETECTOR_BIG_SCREEN_20261008 (owner: "a much larger screen when used"). The device is drawn large and held
  -- low: its screen ends just above the status line and the grip runs off the bottom edge, as a thing in the
  -- hand does. Never wider than half the screen, so a portrait phone keeps both thumbs' controls in sight.
  -- It is on for thirty seconds, so the equipment key puts it away and brings it back (ProtectionHUD sets
  -- `ZyntraDetectorStowed`); the status line stays either way.
  local layout=UIDevice.Layout()
  local h=math.min(math.clamp(safe.Height*.7,240,600),safe.Width*.5/.66)
  local middle,captionWidth=(safe.Left+safe.Right)/2,math.min(300,safe.Width-32)
  -- MOBILE_QA_20261008: on a touch screen the middle of the bottom edge is where the buttons are. Measured on
  -- 568x320: the device lay on SCAN/HIDE and DROP GLOW and the status line across SNEAK and RUN, so the one button
  -- that puts the device away was under it. There the device is smaller (62% of the safe height, no 240 floor)
  -- and both it and the status line end 8 px left of the control cluster; nothing in this gui takes input, so
  -- over the thumbstick's side it costs the thumb nothing.
  local edge=nil
  if layout.IsTouch then
   h=math.min(math.max(150,safe.Height*.62),safe.Width*.5/.66)
   edge=layout.Zones.Controls.Left-8
  end
  local w=h*.66
  if edge then
   middle=math.max(safe.Left+w/2+8,math.min(middle,edge-w/2))
   captionWidth=math.min(captionWidth,math.max(w+70,190))
  end
  local stowed=player:GetAttribute("ZyntraDetectorStowed")==true
  preview.Root.Visible=not stowed
  preview.Root.Size=UDim2.fromOffset(w,h)
  preview.Root.AnchorPoint=Vector2.new(.5,1)
  preview.Root.Position=UIDevice.LocalPosition(gui,middle,safe.Bottom-52+h*(1-Visual.ScreenBottom))
  preview:SetReading(reading,false,remaining)
  local captionMiddle=middle
  if edge then captionMiddle=math.max(safe.Left+captionWidth/2+8,math.min(middle,edge-captionWidth/2)) end
  caption.Size=UDim2.fromOffset(captionWidth,32)
  caption.Position=UIDevice.LocalPosition(gui,captionMiddle,safe.Bottom-45)
  caption.Text=Visual.Labels[reading]..string.format("  ·  %ds",math.ceil(remaining))
  caption.TextColor3=Visual.Colors[reading]
 end)
end)
player.CharacterRemoving:Connect(clear)
script.Destroying:Connect(clear)
