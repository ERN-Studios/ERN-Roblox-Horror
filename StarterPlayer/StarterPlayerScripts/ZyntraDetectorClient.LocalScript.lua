-- ZyntraDetectorClient: a scan's reading on the round HUD (owner, 2026-10-08; HUD batch B1, element 09 C).
-- The 3D handheld in its own ScreenGui at order 1100 (ZyntraDetectorReadout) is gone: RoundHud.Detector draws
-- the flat C card (HUD_PC/DetectorCard above the SCAN chip; on touch the one-line HUD_Touch/DetectorLine in the
-- feed lane) inside RoundHud at order 10, under the death card, PARTY DOWN and the results (RoundUI, 100).
-- This script keeps the logic: which reading, for how long, and when the card must stand down.
-- (artifacts/hud-final-20261008/BUILD-PLAN.md 2 "09", FRAMEWISP-PIPELINE.md 2.6.) ZyntraDetectorVisual stays
-- for the shop display.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local SoundService=game:GetService("SoundService")
local player=Players.LocalPlayer
local Visual=require(RS:WaitForChild("ZyntraDetectorVisual"))
local UIDevice=require(RS:WaitForChild("UIDevice"))
local RoundHud=require(RS:WaitForChild("RoundHud"))
local remote=RS:WaitForChild("Remotes"):WaitForChild("ZyntraDetector")
local connection,sound,shown
local function clear()
 if connection then connection:Disconnect() connection=nil end
 if sound then sound:Destroy() sound=nil end
 shown=nil
 RoundHud.Detector(nil)
end
remote.OnClientEvent:Connect(function(event,reading,expires)
 if event~="reading" or not Visual.Colors[reading] or type(expires)~="number" then return end
 clear()
 player:SetAttribute("ZyntraDetectorStowed",nil)      -- a fresh scan always comes up in the hand
 sound=Instance.new("Sound") sound.Name="LocalDetectorPing"
 sound.SoundId="rbxasset://sounds/volume_slider.ogg" sound.Volume=.12 sound.PlaybackSpeed=1.4 sound.Parent=SoundService sound:Play()
 local char=player.Character
 local shownAt=os.clock()
 connection=RunService.RenderStepped:Connect(function()
  local hum=char and char:FindFirstChildOfClass("Humanoid")
  local remaining=expires-workspace:GetServerTimeNow()
  -- RoundActive goes false before the results are sent, so the card is gone before they draw (owner, 2026-10-08).
  if player.Character~=char or not hum or hum.Health<=0 or player:GetAttribute("InRound")~=true
   or workspace:GetAttribute("RoundActive")~=true or player:GetAttribute("Escaped")==true
   or player:GetAttribute("Spectating")==true or remaining<=0 then clear() return end
  -- DETECTOR_LIVE_20261008: the band follows the entity for as long as the detector is on (the server
  -- republishes it on this attribute), and the device goes when the server says the reading is over.
  local live=player:GetAttribute("ZyntraDetectorReading")
  if Visual.Colors[live] then reading=live end
  -- (not in the first second: the attribute of a reading that was cut short may still be on its way out)
  if os.clock()-shownAt>1 and (player:GetAttribute("ZyntraDetectorReadingUntil") or expires)<=0 then clear() return end
  -- The card stands down under a screen-owning modal, a dispatch briefing or PARTY DOWN, and while the
  -- equipment key has put the detector away (ProtectionHUD's `ZyntraDetectorStowed`). Standing down is a
  -- Hide, so coming back is a change: 100 % for 4 s again (owner, 2026-10-08).
  local want=reading
  if UIDevice.ScreenOwningModalOpen() or player:GetAttribute("DispatchBriefingOpen")==true
   or player:GetAttribute("PartyDownCardOpen")==true or player:GetAttribute("ZyntraDetectorStowed")==true then want=nil end
  -- Only on a change: RoundHud keeps its own countdown, expiry and attention timers (owner, 2026-10-08).
  if want~=shown then
   shown=want
   RoundHud.Detector(want,expires)
  end
 end)
end)
player.CharacterRemoving:Connect(clear)
script.Destroying:Connect(clear)
