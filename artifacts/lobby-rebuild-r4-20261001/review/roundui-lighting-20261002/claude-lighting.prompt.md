Read-only focused Roblox client lighting code review. Use only supplied code, no tools. Answer at most400 words, flag only material behavior/scope/restoration defects and conclude whether safe for actual Play. Current live baseline RoundUI local lobby pass sets ClockTime14, Ambient76/69/45 and warm Tint255/242/188 every.5sec. It must remain exactly that outside new R4 model. Existing Level4/2/3/6 ownership guards retain priority; Level5 distant preview has no lighting controller in capture and is outside bounds. R4 is owned Ready visualRevision4 centered220,30,-760; tube isX±35,Z±140, six side bays extendX±91, Y0..39; originalLobby centered0,30,-760 extendsX±91, so R4bound minimumX120 excludes it. Test-selected R4night values came from root actualPlay, not speculation. InRound=false during local Level6 preview, so Level6InRound explicitly excludes it. Restore only Atmosphere densities written by this branch while stillzero, preserving another controller's subsequent nonzero density. Grade props restored before ownership return. No Source or Studio writes in this CLI review. Consider normal lobby return, level controller handoff, atmosphere replacement, death/respawn, and any .5sec polling hazards. Exact candidate fragment:

```lua
-- Lighting is global on the server, but lobby players can coexist with a party
-- inside the dark maze. This local pass keeps the lobby warm and readable while
-- preserving the exact horror grade for active participants.
local lobbyGrade = Lighting:FindFirstChild("LobbyLocalGrade") or Instance.new("ColorCorrectionEffect")
lobbyGrade.Name = "LobbyLocalGrade"
lobbyGrade.Saturation = -0.08
lobbyGrade.Contrast = 0.04
lobbyGrade.Brightness = 0.02
lobbyGrade.TintColor = Color3.fromRGB(255, 242, 188)
lobbyGrade.Parent = Lighting

-- Only the owned R4 lobby has its own enclosed-night client pass. Preserve
-- atmosphere values while here; never carry this pass into an active level.
local revisedLobbyLighting = {active=false, atmospheres=setmetatable({}, {__mode="k"})}
function revisedLobbyLighting.contains(inMaze)
 if inMaze or player:GetAttribute("Level6InRound") == true then return false end
 local model = workspace:FindFirstChild("LobbyReimaginedPreview")
 if not model or not model:IsA("Model") or model.Parent ~= workspace
  or model:GetAttribute("LobbyReimaginedOwned") ~= true or model:GetAttribute("Ready") ~= true
  or model:GetAttribute("LobbyVisualRevision") ~= 4 then return false end
 local center = model:GetAttribute("PreviewCenter")
 local character = player.Character
 local root = character and character:FindFirstChild("HumanoidRootPart")
 if typeof(center) ~= "Vector3" or not root or not root:IsA("BasePart") then return false end
 local point = root.Position-center
 -- Authored R4 tube plus six circular bays. The original lobby is outside
 -- these bounds even at its nearest bay; distant level previews stay excluded.
 return math.abs(point.X) <= 100 and math.abs(point.Z) <= 144 and point.Y >= -5 and point.Y <= 45
end
function revisedLobbyLighting.restore()
 if not revisedLobbyLighting.active then return end
 for atmosphere, density in pairs(revisedLobbyLighting.atmospheres) do
  -- Do not overwrite a level controller/server that has since changed density.
  if atmosphere.Parent == Lighting and atmosphere.Density == 0 then atmosphere.Density = density end
 end
 table.clear(revisedLobbyLighting.atmospheres)
 local grade = revisedLobbyLighting.grade
 if grade then
  lobbyGrade.TintColor=grade.tint; lobbyGrade.Contrast=grade.contrast
  lobbyGrade.Brightness=grade.brightness; lobbyGrade.Saturation=grade.saturation
 end
 revisedLobbyLighting.grade=nil; revisedLobbyLighting.active=false
end
function revisedLobbyLighting.apply(mazeGrade)
 if not revisedLobbyLighting.active then
  revisedLobbyLighting.grade={tint=lobbyGrade.TintColor,contrast=lobbyGrade.Contrast,
   brightness=lobbyGrade.Brightness,saturation=lobbyGrade.Saturation}
  revisedLobbyLighting.active=true
 end
 local atmosphere=Lighting:FindFirstChildOfClass("Atmosphere")
 if atmosphere then
  local saved=revisedLobbyLighting.atmospheres[atmosphere]
  if saved == nil or atmosphere.Density ~= 0 then revisedLobbyLighting.atmospheres[atmosphere]=atmosphere.Density end
  atmosphere.Density=0
 end
 Lighting.ColorShift_Top=Color3.new(0,0,0); Lighting.ColorShift_Bottom=Color3.new(0,0,0)
 Lighting.Ambient=Color3.fromRGB(30,32,30); Lighting.OutdoorAmbient=Color3.fromRGB(0,0,0)
 Lighting.Brightness=.6; Lighting.ClockTime=0
 Lighting.FogColor=Color3.fromRGB(30,32,30); Lighting.FogStart=0; Lighting.FogEnd=100000
 lobbyGrade.TintColor=Color3.new(1,1,1); lobbyGrade.Contrast=.12
 lobbyGrade.Brightness=0; lobbyGrade.Saturation=0; lobbyGrade.Enabled=true
 if mazeGrade then mazeGrade.Enabled=false end
end

local function applyPlayerLighting()
 local inMaze = player:GetAttribute("InRound") == true
 local mazeGrade = Lighting:FindFirstChild("MongoGrade")
 local selectedLevel = workspace:GetAttribute("SelectedLevel")
 local levelTwoWorld = workspace:FindFirstChild("Level 2 Generated World")
 local levelThreeWorld = workspace:FindFirstChild("Level 3 Generated World")
 local levelSixWorld = workspace:FindFirstChild("Level 6 Generated World")
 local isLevelTwo = levelTwoWorld ~= nil and (selectedLevel == 2 or inMaze)
 local isLevelThree = levelThreeWorld ~= nil and (selectedLevel == 3 or inMaze)
 local inRevisedLobby = revisedLobbyLighting.contains(inMaze)
 if not inRevisedLobby then revisedLobbyLighting.restore() end
 if player:GetAttribute("Level4LightingOwned") == true then
  -- the Level 4 cinema preview grades itself (Level 4 Lighting Controller); stand down while it owns it
  revisedLobbyLighting.restore()
  lobbyGrade.Enabled = false
  if mazeGrade then mazeGrade.Enabled = false end
  return
 end

 if levelSixWorld ~= nil and workspace:GetAttribute("Level6SelectedLevel") == 6
  and player:GetAttribute("Level6InRound") == true
  and workspace:GetAttribute("Level6LightingOwnedByController") == true then
  -- Level 6 runs as a separate preview round, so InRound remains false. Let
  -- its own client controller keep the mall at night instead of restoring the
  -- lobby's 14:00 daylight every half-second.
  revisedLobbyLighting.restore()
  lobbyGrade.Enabled = false
  if mazeGrade then mazeGrade.Enabled = false end
  return
 end
 if isLevelThree and workspace:GetAttribute("Level3LightingOwnedByController") == true then
  -- The dedicated mall controller owns and restores this grade. Never let the
  -- Level 1 darkness reassert itself over Level 3.
  revisedLobbyLighting.restore()
  lobbyGrade.Enabled = false
  if mazeGrade then mazeGrade.Enabled = false end
  return
 end
 if isLevelTwo and workspace:GetAttribute("Level2LightingOwnedByController") == true then
  revisedLobbyLighting.restore()
  lobbyGrade.Enabled = false
  if mazeGrade then mazeGrade.Enabled = false end
  return
 end

 if inRevisedLobby then
  revisedLobbyLighting.apply(mazeGrade)
  return
 end

 Lighting.ColorShift_Top = Color3.new(0, 0, 0)
 Lighting.ColorShift_Bottom = Color3.new(0, 0, 0)
 if inMaze then
  Lighting.Ambient = Color3.fromRGB(4, 4, 3)
  Lighting.OutdoorAmbient = Color3.fromRGB(0, 0, 0)
  Lighting.Brightness = 0.3
  Lighting.ClockTime = 0
  Lighting.FogColor = Color3.fromRGB(16, 14, 9)
  Lighting.FogStart = 30
  Lighting.FogEnd = 220
  lobbyGrade.Enabled = false
  if mazeGrade then mazeGrade.Enabled = true end
 else
  Lighting.Ambient = Color3.fromRGB(76, 69, 45)
  Lighting.OutdoorAmbient = Color3.fromRGB(48, 43, 28)
  Lighting.Brightness = 1.35
  Lighting.ClockTime = 14
  Lighting.FogColor = Color3.fromRGB(205, 190, 125)
  Lighting.FogStart = 0
  Lighting.FogEnd = 100000
  lobbyGrade.Enabled = true
  if mazeGrade then mazeGrade.Enabled = false end
 end
end


```
