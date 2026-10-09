-- RoundUI
-- Top-of-screen status bar plus the opening objective sequence.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local ContextActionService = game:GetService("ContextActionService")

local UIDevice = require(RS:WaitForChild("UIDevice"))
local remotes = RS:WaitForChild("Remotes")
local remote = remotes:WaitForChild("RoundStatus")
local queueRemote = remotes:WaitForChild("ConfigureQueue")
local player = Players.LocalPlayer
local dead = false

local dispatchAudio = {
	-- The COMMAND CENTER accent. Every dispatch readout uses this exact value in
	-- every state so the controls stay part of the transmission. A table field
	-- rather than a file local: this script is at Luau's 200-local ceiling.
	accent = Color3.fromRGB(105, 238, 168),
	-- Text-only briefings for now. Keep the speech SoundIds, instances and cue
	-- timings so restoring the voice later is one deliberate setting change.
	voiceEnabled = false,
	action = remotes:WaitForChild("ZyntraAction"),
	claimLobbyBriefing = remotes:WaitForChild("ZyntraClaimLobbyBriefing"),
	group = SoundService:FindFirstChild("ZyntraDispatchAudio"),
	pending = false,
	pendingValue = nil,
	transmissions = {},
	transmissionSerial = 0,
}
if dispatchAudio.group and not dispatchAudio.group:IsA("SoundGroup") then
	dispatchAudio.group:Destroy()
	dispatchAudio.group = nil
end
if not dispatchAudio.group then
	dispatchAudio.group = Instance.new("SoundGroup")
	dispatchAudio.group.Name = "ZyntraDispatchAudio"
	dispatchAudio.group.Parent = SoundService
end
-- Fail quiet until the server has loaded the returning player's preference.
-- A failed/unknown profile remains silent; a late successful load updates it.
dispatchAudio.group.Volume = 0

function dispatchAudio.preferenceLoaded()
	return player:GetAttribute("ZyntraDispatchPreferenceLoaded") == true
end

function dispatchAudio.inputBlocked()
	local navigation = game:GetService("GuiService")
	return navigation.MenuIsOpen or navigation.SelectedObject ~= nil
		or UIDevice.ScreenOwningModalOpen()
		or player:GetAttribute("PartyDownCardOpen") == true
end

function dispatchAudio.preferenceUnavailable()
	return player:GetAttribute("ZyntraProfileLoaded") == true
		and not dispatchAudio.preferenceLoaded()
end

function dispatchAudio.hasActiveTransmission()
	local ambient = next(dispatchAudio.transmissions) ~= nil
	if RunService:IsStudio() then
		-- The twin of the force flag, and the reason it exists: a Studio session
		-- comes up with the first-login lobby briefing already running, so
		-- "clear the force flag" does NOT reach an idle screen. A device matrix
		-- that assumed it did was asserting against a briefing it could not see
		-- and could not stop -- the panel is drawn by a file-local table with no
		-- outside handle. This hides the AMBIENT transmission only, so a matrix
		-- can establish a real off-state; the force flag still adds one on top,
		-- and neither exists outside Studio.
		if player:GetAttribute("UIRegressionSuppressDispatch") == true then
			ambient = false
		end
		if player:GetAttribute("UIRegressionForceDispatchActive") == true then
			return true
		end
	end
	return ambient
end

function dispatchAudio.currentTransmission()
	local currentOwner = nil
	local current = nil
	for owner, transmission in pairs(dispatchAudio.transmissions) do
		if current == nil or transmission.serial > current.serial then
			currentOwner = owner
			current = transmission
		end
	end
	return currentOwner, current
end

function dispatchAudio.beginTransmission(owner, token, stopCallback)
	dispatchAudio.transmissionSerial += 1
	dispatchAudio.transmissions[owner] = {
		token = token,
		serial = dispatchAudio.transmissionSerial,
		stop = stopCallback,
	}
	dispatchAudio.refresh()
end

function dispatchAudio.finishTransmission(owner, token)
	local transmission = dispatchAudio.transmissions[owner]
	if transmission == nil or transmission.token ~= token then return end
	dispatchAudio.transmissions[owner] = nil
	dispatchAudio.refresh()
end

function dispatchAudio.clearTransmission(owner)
	if dispatchAudio.transmissions[owner] == nil then return end
	dispatchAudio.transmissions[owner] = nil
	dispatchAudio.refresh()
end

-- Text captions have their own clock. A terminal, queue dialog or other modal
-- may hide them temporarily; time spent behind that UI must not consume lines
-- from the one-time lobby welcome.
function dispatchAudio.newCaptionClock()
	return {elapsed = 0, sampledAt = os.clock()}
end

function dispatchAudio.captionPosition(clock, speech)
	if dispatchAudio.voiceEnabled then return speech.TimePosition end
	local now = os.clock()
	if dispatchAudio.captionClockRunning then
		clock.elapsed += now - clock.sampledAt
	end
	clock.sampledAt = now
	return clock.elapsed
end

function dispatchAudio.refresh()
	local loaded = dispatchAudio.preferenceLoaded()
	local muted = player:GetAttribute("ZyntraMuteDispatch") == true
	local active = dispatchAudio.hasActiveTransmission()
	-- Observability for QA and future settings; unlike the former dispatch
	-- attribute this does not ask any other HUD to disappear.
	if player:GetAttribute("DispatchTextActive") ~= active then
		player:SetAttribute("DispatchTextActive", active)
	end
	-- Captions are passive. They must never suppress puzzle controls, alerts,
	-- the CD reader or equipment just because a briefing is in progress.
	if player:GetAttribute("ZyntraDispatchClientActive") ~= false then
		player:SetAttribute("ZyntraDispatchClientActive", false)
	end
	if dispatchAudio.pendingValue ~= nil then muted = dispatchAudio.pendingValue end
	dispatchAudio.group.Volume = loaded and (muted and 0 or 1) or 0
	local hasSubtitle = dispatchAudio.subtitleCopy ~= nil and dispatchAudio.subtitleCopy ~= ""
	-- The suppression hook has to reach the SUBTITLE as well as the audio, or it
	-- suppresses nothing a regression matrix can see: a briefing whose line is
	-- already on screen keeps the panel up through `hasSubtitle` long after
	-- hasActiveTransmission() has been made to answer false. Studio only, and
	-- the force flag still wins over it.
	if RunService:IsStudio()
		and player:GetAttribute("UIRegressionSuppressDispatch") == true
		and player:GetAttribute("UIRegressionForceDispatchActive") ~= true
	then
		hasSubtitle = false
	end
	-- Captions yield to screen-owning UI and the two in-round panels that share
	-- their band. The transmission stays active and its caption clock pauses
	-- while hidden, so closing a modal resumes the line instead of skipping it.
	local shown = (active or hasSubtitle)
		and not UIDevice.ScreenOwningModalOpen()
		and player:GetAttribute("ZyntraShopDetailOpen") ~= true
		and player:GetAttribute("PartyDownCardOpen") ~= true
		and player:GetAttribute("Level2AlertOwnsBand") ~= true
	dispatchAudio.captionClockRunning = shown -- caption preferences never stall the transport
	dispatchAudio.captionVisible = shown and player:GetAttribute("CaptionsEnabled") ~= false
		and player:GetAttribute("DisableCaptions") ~= true
	if dispatchAudio.panel then
		dispatchAudio.panel.Visible = false -- RoundHud.Caption is the sole subtitle renderer
	end
	-- This is the old blocking-briefing contract consumed by detector,
	-- protection, exit and store UIs. The caption panel is now non-modal.
	if player:GetAttribute("DispatchBriefingOpen") ~= false then
		player:SetAttribute("DispatchBriefingOpen", false)
	end
	if dispatchAudio.Hud then
		if not dispatchAudio.captionVisible then
			dispatchAudio.captionSent = nil
		elseif shown and hasSubtitle and dispatchAudio.captionSent ~= dispatchAudio.subtitleCopy then
			if dispatchAudio.Hud.Caption("COMMAND CENTER", dispatchAudio.subtitleCopy) then
				dispatchAudio.captionSent = dispatchAudio.subtitleCopy
			end
		elseif not hasSubtitle and dispatchAudio.captionSent then
			dispatchAudio.Hud.Caption("COMMAND CENTER", "", 0)
			dispatchAudio.captionSent = nil
		end
	end
	if dispatchAudio.controls then
		-- The controls belong to the briefing panel, including its radio lead-in;
		-- they never float beside unrelated equipment UI -- and never outlive the
		-- panel itself, including where the queue modal has suppressed it.
		dispatchAudio.controls.Visible = active and shown
	end
	if dispatchAudio.button then
		-- Full words, always. The "[M]" prefix is a keyboard binding and is
		-- therefore supplied by UIDevice, which returns nothing at all on a phone
		-- or tablet no matter what input was used most recently.
		local muteWord = dispatchAudio.preferenceUnavailable() and "DISPATCH OFFLINE"
			or not loaded and "LOADING DISPATCH"
			or dispatchAudio.pending and "SAVING"
			or muted and "UNMUTE DISPATCH"
			or "MUTE DISPATCH"
		local binding = UIDevice.Binding("[M]", "[LB]")
		dispatchAudio.button.Text = binding ~= "" and (binding .. "  " .. muteWord) or muteWord
		-- ONE colour, in every state. This is the COMMAND CENTER line's own
		-- cyan-green, and MUTE / UNMUTE / SAVING / DISPATCH OFFLINE all wear it,
		-- so the controls read as part of the transmission rather than as chrome
		-- bolted onto it. An amber "muted" tint was tried and rejected: a second
		-- accent in a two-line panel reads as a warning, which muting is not.
		-- State is carried by the WORD and by the dimming below, never by hue.
		dispatchAudio.button.TextColor3 = dispatchAudio.accent
		-- The label IS the state readout: DISPATCH OFFLINE, LOADING DISPATCH and
		-- SAVING are things the player needs to SEE. All four of those states
		-- happen while a transmission is ACTIVE, so they survive the rule below:
		-- the control is only ever dimmed and disabled while Command is live,
		-- never removed mid-briefing.
		local ready = active and shown and loaded and not dispatchAudio.pending
		-- WHAT SHIPPED BROKEN: `Visible = true`, unconditionally and forever. The
		-- readouts belong to the briefing and to nothing else, but they were left
		-- mounted after it ended -- alive inside a hidden parent, still reported by
		-- any pass that walks descendants, and one stray `controls.Visible = true`
		-- away from painting MUTE DISPATCH over a level with no dispatch in it.
		-- They now exist EXACTLY while the transmission does; the parent frame
		-- below is hidden on the same condition, so the two can never disagree.
		dispatchAudio.button.Visible = active and shown and dispatchAudio.voiceEnabled
			and not dispatchAudio.readerPassiveLane
		dispatchAudio.button.TextTransparency = ready and 0 or .45
		UIDevice.SetEnabled(dispatchAudio.button, ready and dispatchAudio.voiceEnabled
			and not dispatchAudio.readerPassiveLane)
	end
	if dispatchAudio.stopButton then
		local stopBinding = UIDevice.Binding("[N]", "[B]")
		dispatchAudio.stopButton.TextColor3 = dispatchAudio.accent
		local stopWord = dispatchAudio.readerPassiveLane
			and (dispatchAudio.voiceEnabled and "STOP" or "SKIP")
			or (dispatchAudio.voiceEnabled and "STOP DISPATCH" or "SKIP BRIEF")
		dispatchAudio.stopButton.Text = stopBinding ~= ""
			and (stopBinding .. "  " .. stopWord) or stopWord
		-- Same rule as MUTE above: present exactly while the briefing is, gone the
		-- moment it is not. STOP has no dimmed-but-informative state at all -- an
		-- inactive STOP DISPATCH is a control that would do nothing if tapped.
		dispatchAudio.stopButton.Visible = active and shown
		dispatchAudio.stopButton.TextTransparency = active and 0 or .45
		UIDevice.SetEnabled(dispatchAudio.stopButton, active and shown)
	end
end

function dispatchAudio.awaitPreference()
	local deadline = os.clock() + 10
	while not dispatchAudio.preferenceLoaded()
		and not dispatchAudio.preferenceUnavailable()
		and os.clock() < deadline do
		RunService.Heartbeat:Wait()
	end
	if dispatchAudio.preferenceLoaded() then
		dispatchAudio.refresh()
	else
		-- Continue the briefing and subtitles, but stay fail-quiet while the
		-- persistent preference is unknown. A late profile load updates instantly.
		dispatchAudio.refresh()
	end
end

function dispatchAudio.requestToggle()
	if not dispatchAudio.voiceEnabled
		or not dispatchAudio.hasActiveTransmission()
		or dispatchAudio.pending
		or not dispatchAudio.preferenceLoaded() then
		return false
	end
	dispatchAudio.pending = true
	dispatchAudio.pendingValue = player:GetAttribute("ZyntraMuteDispatch") ~= true
	dispatchAudio.refresh() -- mute/unmute the active transmission immediately
	dispatchAudio.action:FireServer("SetMuteDispatch", dispatchAudio.pendingValue)
	task.delay(12, function()
		if dispatchAudio.pending then
			dispatchAudio.pending = false
			dispatchAudio.pendingValue = nil
			dispatchAudio.refresh()
		end
	end)
	return true
end

function dispatchAudio.requestStop()
	local owner, transmission = dispatchAudio.currentTransmission()
	if owner == nil or transmission == nil then return false end

	-- Retire this exact owner/token before invoking its callback. Any stale
	-- coroutine can now only finish its old token and cannot hide a newer cue.
	dispatchAudio.transmissions[owner] = nil
	dispatchAudio.refresh()
	transmission.stop()
	return true
end

player:GetAttributeChangedSignal("ZyntraProfileLoaded"):Connect(dispatchAudio.refresh)
player:GetAttributeChangedSignal("ZyntraDispatchPreferenceLoaded"):Connect(dispatchAudio.refresh)
player:GetAttributeChangedSignal("ZyntraMuteDispatch"):Connect(function()
	if dispatchAudio.pendingValue == nil
		or player:GetAttribute("ZyntraMuteDispatch") == dispatchAudio.pendingValue then
		dispatchAudio.pending = false
		dispatchAudio.pendingValue = nil
	end
	dispatchAudio.refresh()
end)
-- The captions carry a keyboard binding on desktop and none on touch, so they
-- have to be rebuilt whenever the form factor changes -- a keyboard being
-- attached to a tablet, or ForceTouchUI being toggled during a device test.
-- Without this the labels keep whatever they were built with.
UIDevice.Changed:Connect(function() dispatchAudio.refresh() end)
player:GetAttributeChangedSignal("ZyntraStoreOpen"):Connect(dispatchAudio.refresh)
player:GetAttributeChangedSignal("ZyntraShopDetailOpen"):Connect(dispatchAudio.refresh)
player:GetAttributeChangedSignal("PartyDownCardOpen"):Connect(dispatchAudio.refresh)
player:GetAttributeChangedSignal("Level2AlertOwnsBand"):Connect(dispatchAudio.refresh)
player:GetAttributeChangedSignal("CaptionsEnabled"):Connect(dispatchAudio.refresh)
player:GetAttributeChangedSignal("DisableCaptions"):Connect(dispatchAudio.refresh)
UIDevice.OnScreenOwningModalChanged(dispatchAudio.refresh)
if RunService:IsStudio() then
	player:GetAttributeChangedSignal("UIRegressionForceDispatchActive"):Connect(dispatchAudio.refresh)
	player:GetAttributeChangedSignal("UIRegressionSuppressDispatch"):Connect(dispatchAudio.refresh)
end
dispatchAudio.refresh()

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
local revisedLobbyLighting = {active=false, atmospheres={}}
revisedLobbyLighting.values = {
 ColorShift_Top=Color3.new(0,0,0), ColorShift_Bottom=Color3.new(0,0,0),
 Ambient=Color3.fromRGB(30,32,30), OutdoorAmbient=Color3.fromRGB(0,0,0),
 Brightness=.6, ClockTime=0, FogColor=Color3.fromRGB(30,32,30), FogStart=0, FogEnd=100000,
}
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
 if math.abs(point.X) <= 100 and math.abs(point.Z) <= 144 and point.Y >= -5 and point.Y <= 45 then return true end
 -- REACH_DARK_20261007: the tunnel carries on behind the fence at the DJ end (the easter egg), and a body there
 -- is still in the lobby. The box above ends five studs behind the end wall: past it this pass let go and the
 -- old lobby's 14:00 daylight came back, so the dark the easter egg lives in was a sunlit tunnel.
 local beyond = model:FindFirstChild("InfiniteTunnelEnd")
 local reach = beyond and beyond:GetAttribute("ReachFrame")
 if typeof(reach) ~= "CFrame" then return false end
 local at = reach:PointToObjectSpace(root.Position)
 return math.abs(at.X) <= 40 and at.Y >= -8 and at.Y <= 60 and at.Z >= -10 and at.Z <= 215
end
function revisedLobbyLighting.restore()
 -- A nonparticipant can leave R4 while another party keeps the old global
 -- level markers set. Restore only our own pass before those guards return.
 local globalsOwned = player:GetAttribute("Level4LightingOwned") == true
  or player:GetAttribute("Level2NewMapLightingOwned") == true
  or player:GetAttribute("InRound") == true or player:GetAttribute("Level6InRound") == true
 if not globalsOwned and revisedLobbyLighting.lighting then
  for property, baseline in pairs(revisedLobbyLighting.lighting) do
   if Lighting[property] == revisedLobbyLighting.applied[property] then Lighting[property] = baseline end
  end
  revisedLobbyLighting.lighting=nil; revisedLobbyLighting.applied=nil
 end
 -- Level4 (and the Level 2 new-map preview) captures the current atmosphere at entry, then restores that
 -- snapshot on exit. Keep our pre-R4 density pending through its ownership;
 -- otherwise its saved zero would leak into the original lobby on return.
 local atmosphereOwned = player:GetAttribute("Level4LightingOwned") == true
  or player:GetAttribute("Level2NewMapLightingOwned") == true
  or (player:GetAttribute("InRound") == true and workspace:GetAttribute("SelectedLevel") == 2
   and workspace:FindFirstChild("Level 2 Generated World") ~= nil
   and workspace:GetAttribute("Level2LightingOwnedByController") == true)
 if not atmosphereOwned then
  for atmosphere, density in pairs(revisedLobbyLighting.atmospheres) do
   -- Restore only our zero; preserve a later nonzero controller/server value.
   if atmosphere.Parent == Lighting and atmosphere.Density == 0 then atmosphere.Density = density end
   revisedLobbyLighting.atmospheres[atmosphere]=nil
  end
 end
 local grade = revisedLobbyLighting.grade
 if grade then
  lobbyGrade.TintColor=grade.tint; lobbyGrade.Contrast=grade.contrast
  lobbyGrade.Brightness=grade.brightness; lobbyGrade.Saturation=grade.saturation
 end
 revisedLobbyLighting.grade=nil; revisedLobbyLighting.active=false
end
function revisedLobbyLighting.apply(mazeGrade)
 if not revisedLobbyLighting.lighting then
  revisedLobbyLighting.lighting={}; revisedLobbyLighting.applied={}
  for property in pairs(revisedLobbyLighting.values) do revisedLobbyLighting.lighting[property]=Lighting[property] end
 end
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
 for property, value in pairs(revisedLobbyLighting.values) do
  Lighting[property]=value
  -- Record engine-normalized readback (e.g. Float32 brightness .600000023).
  revisedLobbyLighting.applied[property]=Lighting[property]
 end
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
 if player:GetAttribute("Level4LightingOwned") == true or player:GetAttribute("Level6PlaygroundLightingOwned") == true
  or player:GetAttribute("Level5LightingOwned") == true or player:GetAttribute("Level2NewMapLightingOwned") == true then
  -- Level2NewMapLightingOwned: the Level 2 new-map developer preview grades itself (Level2BlenderPreviewButton)
  -- the Level 4 cinema preview and the Level 6 playground grade themselves (Level 4 Lighting Controller); stand down while it owns it
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
 if inRevisedLobby then
  revisedLobbyLighting.apply(mazeGrade)
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
  if selectedLevel == 1 and workspace:GetAttribute("Level1BlenderActive") == true
   and (workspace:GetAttribute("LightMode") or "NORMAL") == "NORMAL" then
   -- Successful relay extractions are permanent for the round, including deaths/drops.
   local taken = workspace:GetAttribute("Level1RelaysExtracted") or 0
   local total = math.max(workspace:GetAttribute("Level1RelaysPlaced") or 3, 1)
   local stage = taken * 3 >= total * 2 and 3 or taken * 3 >= total and 2 or 1
   local presets = {
    {Color3.fromRGB(100,94,70), Color3.fromRGB(35,32,23), 1.3, Color3.fromRGB(120,110,79), 200, 900}, -- C
    {Color3.fromRGB(65,61,45), Color3.fromRGB(20,18,12), 1, Color3.fromRGB(85,77,55), 140, 650}, -- B
    {Color3.fromRGB(36,34,26), Color3.fromRGB(10,9,6), .65, Color3.fromRGB(55,49,34), 85, 450}, -- A
   }
   local preset = presets[stage]
   Lighting.Ambient, Lighting.OutdoorAmbient, Lighting.Brightness = preset[1], preset[2], preset[3]
   Lighting.FogColor, Lighting.FogStart, Lighting.FogEnd = preset[4], preset[5], preset[6]
  elseif selectedLevel == 1 and workspace:GetAttribute("Level1BlenderActive") == true
   and workspace:GetAttribute("LightMode") == "ALERT" then
   -- Red alert (owner 2026-10-04): a dim red fill keeps the maze readable between the pulsing lights.
   Lighting.Ambient, Lighting.OutdoorAmbient = Color3.fromRGB(48, 14, 10), Color3.fromRGB(14, 4, 3)
   Lighting.FogColor, Lighting.FogStart, Lighting.FogEnd = Color3.fromRGB(36, 10, 8), 85, 450
  end
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

player:GetAttributeChangedSignal("InRound"):Connect(applyPlayerLighting)
task.spawn(function()
 while true do
  applyPlayerLighting() -- reassert after server-side maze lighting changes
  task.wait(0.5)
 end
end)
applyPlayerLighting()

local gui = Instance.new("ScreenGui")
gui.Name = "RoundGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100
gui.Parent = player:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(0.5, 0)
label.Position = UDim2.new(0.5, 0, 0, 18)
label.Size = UDim2.new(0, 700, 0, 180)
label.BackgroundColor3 = Color3.new(0, 0, 0)
label.BackgroundTransparency = 0.72
label.BorderSizePixel = 0
label.Font = Enum.Font.GothamMedium
label.TextScaled = false
label.TextSize = 26
label.TextWrapped = true
label.TextYAlignment = Enum.TextYAlignment.Center
label.TextColor3 = Color3.fromRGB(235, 232, 222)
label.Text = ""
label.Visible = false
label.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 6)
corner.Parent = label

-- Host-only queue setup. The first player inside an empty station sees this panel;
-- the server remains authoritative over host identity, capacity and privacy.
local queueShade = Instance.new("Frame")
queueShade.Name = "QueueHostShade"
queueShade.Size = UDim2.fromScale(1, 1)
queueShade.BackgroundColor3 = Color3.new(0, 0, 0)
queueShade.BackgroundTransparency = 0.38
queueShade.BorderSizePixel = 0
queueShade.Active = true
queueShade.Visible = false
queueShade.ZIndex = 50
queueShade.Parent = gui

local queuePanel = Instance.new("Frame")
queuePanel.Name = "QueueHostPanel"
queuePanel.AnchorPoint = Vector2.new(0.5, 0.5)
queuePanel.Position = UDim2.fromScale(0.5, 0.5)
queuePanel.Size = UDim2.fromScale(0.86, 0.82)
queuePanel.BackgroundColor3 = Color3.fromRGB(16, 19, 17)
queuePanel.BackgroundTransparency = 0.04
queuePanel.BorderSizePixel = 0
queuePanel.ZIndex = 51
queuePanel.Active = true
queuePanel.Parent = queueShade
local queueConstraint = Instance.new("UISizeConstraint")
queueConstraint.MinSize = Vector2.new(320, 330)
queueConstraint.MaxSize = Vector2.new(470, 370)
queueConstraint.Parent = queuePanel
local queueCorner = Instance.new("UICorner")
queueCorner.CornerRadius = UDim.new(0, 12)
queueCorner.Parent = queuePanel
local queueStroke = Instance.new("UIStroke")
queueStroke.Color = Color3.fromRGB(105, 238, 168)
queueStroke.Transparency = 0.30
queueStroke.Thickness = 2
queueStroke.Parent = queuePanel

local function queueText(name, text, position, size, textSize, color)
 local item = Instance.new("TextLabel")
 item.Name = name
 item.Position = position
 item.Size = size
 item.BackgroundTransparency = 1
 item.BorderSizePixel = 0
 item.Font = Enum.Font.Code
 item.Text = text
 item.TextColor3 = color or Color3.fromRGB(225, 228, 213)
 item.TextSize = textSize
 item.TextWrapped = true
 item.ZIndex = 52
 item.Parent = queuePanel
 return item
end

local function queueButton(name, text, position, size)
 local button = Instance.new("TextButton")
 button.Name = name
 button.Position = position
 button.Size = size
 button.BackgroundColor3 = Color3.fromRGB(31, 38, 33)
 button.BackgroundTransparency = 0.06
 button.BorderSizePixel = 0
 button.AutoButtonColor = true
 button.Font = Enum.Font.GothamBold
 button.Text = text
 button.TextColor3 = Color3.fromRGB(225, 235, 224)
 button.TextSize = 21
 button.ZIndex = 53
 button.Parent = queuePanel
 local buttonCorner = Instance.new("UICorner")
 buttonCorner.CornerRadius = UDim.new(0, 8)
 buttonCorner.Parent = button
 local buttonStroke = Instance.new("UIStroke")
 buttonStroke.Color = Color3.fromRGB(120, 170, 137)
 buttonStroke.Transparency = 0.45
 buttonStroke.Thickness = 1.4
 buttonStroke.Parent = button
 return button, buttonStroke
end

-- 0.76, not 0.88: at 0.88 the title runs underneath the close button in the
-- top-right corner, which the panel's own internal overlap check now catches.
local queueTitle = queueText("HostTitle", "CREATE YOUR PARTY", UDim2.new(0.06, 0, 0, 16), UDim2.new(0.76, 0, 0, 38), 31, Color3.fromRGB(116, 255, 178))
queueTitle.TextXAlignment = Enum.TextXAlignment.Center
local queueStationLabel = queueText("StationLabel", "STATION", UDim2.new(0.10, 0, 0, 57), UDim2.new(0.80, 0, 0, 24), 18, Color3.fromRGB(151, 171, 155))
queueStationLabel.TextXAlignment = Enum.TextXAlignment.Center
local queueSizeCaption = queueText("SizeCaption", "MAXIMUM PLAYERS", UDim2.new(0.08, 0, 0, 94), UDim2.new(0.84, 0, 0, 24), 19, Color3.fromRGB(218, 207, 153))
local queueMinus = queueButton("DecreasePlayers", "−", UDim2.new(0.10, 0, 0, 124), UDim2.new(0.20, 0, 0, 52))
local queueCount = queueText("PlayerCount", "6", UDim2.new(0.37, 0, 0, 122), UDim2.new(0.26, 0, 0, 56), 44, Color3.fromRGB(235, 240, 225))
queueCount.TextXAlignment = Enum.TextXAlignment.Center
queueCount.TextYAlignment = Enum.TextYAlignment.Center
local queuePlus = queueButton("IncreasePlayers", "+", UDim2.new(0.70, 0, 0, 124), UDim2.new(0.20, 0, 0, 52))
local queuePrivacyCaption = queueText("PrivacyCaption", "WHO CAN JOIN?", UDim2.new(0.08, 0, 0, 194), UDim2.new(0.84, 0, 0, 24), 19, Color3.fromRGB(218, 207, 153))
local queuePrivacyButton, queuePrivacyStroke = queueButton("PrivacyToggle", "PUBLIC  •  EVERYONE", UDim2.new(0.10, 0, 0, 224), UDim2.new(0.80, 0, 0, 48))
queuePrivacyButton.TextSize = 18
local queueSubmit, queueSubmitStroke = queueButton("CreateParty", "CREATE PARTY", UDim2.new(0.10, 0, 1, -78), UDim2.new(0.80, 0, 0, 50))
queueSubmit.Modal = true -- releases first-person mouse lock while this visible button is on screen
queueSubmit.BackgroundColor3 = Color3.fromRGB(42, 105, 70)
queueSubmitStroke.Color = Color3.fromRGB(120, 255, 175)
local queueClose, queueCloseStroke = queueButton("CloseQueue", "×", UDim2.new(1, -46, 0, 10), UDim2.fromOffset(34, 34))
queueClose.Modal = true
queueClose.ZIndex = 54
queueClose.TextSize = 24
queueClose.BackgroundColor3 = Color3.fromRGB(76, 38, 38)
queueCloseStroke.Color = Color3.fromRGB(255, 138, 120)
queueCloseStroke.Transparency = 0.35
local queueHint = queueText("CancelHint", "STEP OFF THE PAD TO CANCEL", UDim2.new(0.08, 0, 1, -23), UDim2.new(0.84, 0, 0, 16), 14, Color3.fromRGB(125, 137, 126))
queueHint.TextXAlignment = Enum.TextXAlignment.Center
-- LEVEL4_QUEUE_CHOICE_20261002: a Level 4 bay in the new lobby offers TRIAL ROUND (the real round) and MAP PREVIEW
-- (the map with no entity). The server lists the modes in queuehost's 4th argument; the shade carries them as the
-- attribute QueueLaunchModes ("trial,preview" splits the submit row into two buttons). A do-block: no new local.
do
 local preview, previewStroke = queueButton("MapPreview", "MAP PREVIEW", UDim2.new(0.51, 0, 1, -78), UDim2.new(0.39, 0, 0, 50))
 preview.Modal = true
 preview.Visible = false
 preview.BackgroundColor3 = Color3.fromRGB(38, 62, 96)
 previewStroke.Color = Color3.fromRGB(125, 205, 255)
end

local function applyQueueDeviceLayout()
 local queueLayout = UIDevice.Layout()

 -- -- ONE ordered row stack, driven by the panel's ACTUAL height ------------
 -- WHAT SHIPPED BROKEN: every row in both branches was placed at a FIXED y
 -- offset measured against the panel's TALLEST size -- except CREATE PARTY,
 -- which was anchored to the panel's BOTTOM ("1, -78"). Those two conventions
 -- agree at exactly one height. At 1920x1080 the desktop panel is 470x370 and
 -- they do agree. At 705x338 the 0.82 height scale collapses onto the size
 -- constraint's 330px floor, PRIVACY TOGGLE stays at its fixed 224..272 while
 -- CREATE PARTY rides the bottom edge up to 252..302, and the two overlap by
 -- twenty pixels. Measured on a real short desktop viewport; shipped that way.
 --
 -- Rows now carry the heights they were authored with -- that is where the
 -- 44px touch floor lives, and nothing here ever shrinks one -- and the GAPS
 -- between them absorb the difference, from the authored spacing at full
 -- height down to a stated minimum. Two rows cannot overlap, because no row is
 -- ever placed anywhere except directly beneath the one above it.
 --
 -- A nested function, not a file-level one: this script sits exactly on Luau's
 -- ceiling of 200 local registers for its main chunk, and one more name at
 -- that level stops the whole file compiling.
 local function layoutQueueRows(panelHeight, bottomPad, minimumBottomPad, rows)
  -- Trailing OPTIONAL rows are dropped, last first, while even the minimum
  -- spacing overflows the panel. The cancel hint is the only one: it repeats
  -- what the X button already offers, so dropping it beats letting it hang
  -- outside the panel -- or letting it shove CREATE PARTY out of one.
  local live = #rows
  while live > 0 and rows[live].Optional do
   local minimum = minimumBottomPad
   for index = 1, live do minimum += rows[index].Height + rows[index].MinGap end
   if minimum <= panelHeight then break end
   rows[live].Control.Visible = false
   live -= 1
  end
  local rowTotal, naturalGaps, minimumGaps = 0, bottomPad, minimumBottomPad
  for index = 1, live do
   rowTotal += rows[index].Height
   naturalGaps += rows[index].Gap
   minimumGaps += rows[index].MinGap
  end
  -- t = 1 reproduces the authored spacing to the pixel -- which is exactly what
  -- the 470x370 desktop panel at 1920x1080 and the 260px touch panel at
  -- 705x338 both get -- and t = 0 packs the stack down to its stated minimum.
  -- Every value between the two is a valid, non-overlapping layout.
  local spare = naturalGaps - minimumGaps
  local t = spare > 0
   and math.clamp((panelHeight - rowTotal - minimumGaps) / spare, 0, 1)
   or 1
  local y = 0
  for index = 1, live do
   local row = rows[index]
   y += row.MinGap + math.floor((row.Gap - row.MinGap) * t + 0.5)
   if row.Control then row.Control.Visible = true end
   row.Apply(y, row.Height)
   y += row.Height
  end
  return y
 end

 -- UIDevice.IsTouch(), not UserInputService.TouchEnabled: the form-factor
 -- question has one answer in this game, and only the former honours the
 -- Studio-only override the regression matrix drives. Reading TouchEnabled here
 -- meant the whole touch branch was untestable from Luau.
 if UIDevice.IsTouch() then
  -- Phones and tablets get their own compact landscape-safe arrangement. Every
  -- interactive control in it is at least 44x44: a thumb does not get smaller
  -- because the screen did, and the previous 32x32 close button, 40px steppers,
  -- 38px privacy toggle and 42px create button were all under the floor.
  -- INSIDE the modal area, never negotiating with a movement zone.
  --
  -- This used to pick a spot from ONE zone: to the right of the thumbstick if
  -- the screen was wide enough, above it otherwise. On a 705x338 Galaxy A06 the
  -- first branch fires -- 290 + 380 = 670 <= 697 -- and puts the panel at
  -- x 290..670 while the control column owns x 537..705. Plus, Privacy, Create
  -- and half of Close were sitting under RUN, JUMP, GLOW and FLASHLIGHT. The
  -- panel now takes the rectangle UIDevice guarantees is clear of every
  -- movement affordance at once, and is sized to fit it.
  -- C_QUEUE_USES_THE_MODAL_VIEWPORT_20260831. ModalArea is the rectangle clear
  -- of every movement affordance, and it was the right answer while this dialog
  -- left the controls live underneath it. It does not any more: the dialog is a
  -- screen-owning modal and now stands movement down like the Zyntra terminal,
  -- so there is no thumbstick, no cluster and no engine jump to dodge -- and
  -- ModalArea's own 8px gutter is narrower than the 12px one every other modal
  -- in the game keeps, which put this panel 4px outside the authored modal
  -- rectangle on three portrait phones. It takes ModalViewport, the same
  -- rectangle the terminal takes, for the same reason.
  local area = queueLayout.ModalViewport
  local queueWidth = math.floor(math.min(380, area.Width))
  -- One rule, not a max/min sandwich: the row stack below is 260px at its
  -- authored spacing and 251px packed, so ask for 280 and take whatever the
  -- area can actually give. The stack absorbs the difference either way.
  local queueHeight = math.floor(math.min(280, area.Height))
  queuePanel.AnchorPoint = Vector2.new(0, 0)
  queueConstraint.MinSize = Vector2.new(queueWidth, queueHeight)
  queueConstraint.MaxSize = Vector2.new(queueWidth, queueHeight)
  queuePanel.Size = UDim2.fromOffset(queueWidth, queueHeight)
  -- ModalArea is ABSOLUTE, and this gui ignores the topbar inset, so its
  -- origin is the display's top -- 58px above the coordinate ModalArea is
  -- expressed in. Written as a raw offset the panel landed a whole topbar high:
  -- measured on a Galaxy A06 the modal resolved to y -50..214 with its Close
  -- button at y -44..0, i.e. entirely underneath the Roblox topbar.
  queuePanel.Position = UIDevice.LocalPosition(gui,
   math.floor(area.Left + (area.Width - queueWidth) * 0.5),
   math.floor(area.Top + (area.Height - queueHeight) * 0.5))
  -- Do not place a full-screen input-catching box over the mobile controls --
  -- and do not let the panel itself sink touches meant for them either. Its
  -- BUTTONS stay Active and tappable; the frame behind them does not.
  queueShade.BackgroundTransparency = 1
  queueShade.Active = false
  queuePanel.Active = false

  -- Offsets, not fractions. A fraction of a 380px panel and a fraction of the
  -- 239px one a landscape phone can actually spare are different sizes, and the
  -- narrow case is what pushed the steppers under the 44px floor.
  queueClose.AnchorPoint = Vector2.new(1, 0)
  queueClose.Position = UDim2.new(1, -6, 0, 6)
  queueClose.Size = UDim2.fromOffset(44, 44)
  queueClose.TextSize = 24
  queuePlus.AnchorPoint = Vector2.new(1, 0)
  queueTitle.TextSize = 18
  queueStationLabel.TextSize = 11
  queueSizeCaption.TextSize = 12
  queueMinus.TextSize = 22
  queueCount.TextSize = 30
  queuePlus.TextSize = 22
  queuePrivacyCaption.TextSize = 12
  queuePrivacyButton.TextSize = 15
  queueSubmit.TextSize = 16
  queueHint.TextSize = 10
  queueHint.Text = "WALK OUT OR TAP X TO CANCEL"

  -- The stepper row is the only place the width actually binds, so it is
  -- derived rather than fixed. A hard 56/56 pair with the count taking
  -- "1, -160" goes NEGATIVE below 160px of panel -- a 568x320 landscape phone
  -- leaves 156 -- and a negative size renders as nothing at all, so the player
  -- count silently disappears instead of merely being tight.
  local stepper = math.clamp(math.floor((queueWidth - 30) / 3), 44, 56)
  local countLeft = 10 + stepper + 6
  local countWidth = math.max(24, queueWidth - 20 - stepper * 2 - 12)
  -- Title and station stop clear of the close button, which reaches down to
  -- y = 50: at full width both rows run underneath a 44x44 X.
  layoutQueueRows(queueHeight, 4, 4, {
   {Height = 26, Gap = 8, MinGap = 6, Control = queueTitle, Apply = function(y, h)
    queueTitle.Position = UDim2.new(0, 10, 0, y)
    queueTitle.Size = UDim2.new(1, -66, 0, h)
   end},
   {Height = 14, Gap = 2, MinGap = 2, Control = queueStationLabel, Apply = function(y, h)
    queueStationLabel.Position = UDim2.new(0, 10, 0, y)
    queueStationLabel.Size = UDim2.new(1, -66, 0, h)
   end},
   {Height = 14, Gap = 4, MinGap = 3, Control = queueSizeCaption, Apply = function(y, h)
    queueSizeCaption.Position = UDim2.new(0, 10, 0, y)
    queueSizeCaption.Size = UDim2.new(1, -20, 0, h)
   end},
   {Height = 46, Gap = 4, MinGap = 3, Apply = function(y, h)
    queueMinus.Position = UDim2.new(0, 10, 0, y)
    queueMinus.Size = UDim2.fromOffset(stepper, h)
    queueCount.Position = UDim2.new(0, countLeft, 0, y)
    queueCount.Size = UDim2.fromOffset(countWidth, h)
    queuePlus.Position = UDim2.new(1, -10, 0, y)
    queuePlus.Size = UDim2.fromOffset(stepper, h)
   end},
   {Height = 14, Gap = 4, MinGap = 3, Control = queuePrivacyCaption, Apply = function(y, h)
    queuePrivacyCaption.Position = UDim2.new(0, 10, 0, y)
    queuePrivacyCaption.Size = UDim2.new(1, -20, 0, h)
   end},
   {Height = 46, Gap = 4, MinGap = 3, Control = queuePrivacyButton, Apply = function(y, h)
    queuePrivacyButton.Position = UDim2.new(0, 10, 0, y)
    queuePrivacyButton.Size = UDim2.new(1, -20, 0, h)
   end},
   {Height = 48, Gap = 6, MinGap = 4, Control = queueSubmit, Apply = function(y, h)
    local preview = queuePanel:FindFirstChild("MapPreview")
    if preview and queueShade:GetAttribute("QueueLaunchModes") == "trial,preview" then
     queueSubmit.TextSize = math.min(queueSubmit.TextSize, 15)
     queueSubmit.Position = UDim2.new(0, 10, 0, y)
     queueSubmit.Size = UDim2.new(0.5, -13, 0, h)
     preview.TextSize = queueSubmit.TextSize
     preview.Position = UDim2.new(0.5, 3, 0, y)
     preview.Size = UDim2.new(0.5, -13, 0, h)
     preview.Visible = true
    else
     queueSubmit.Position = UDim2.new(0, 10, 0, y)
     queueSubmit.Size = UDim2.new(1, -20, 0, h)
     if preview then preview.Visible = false end
    end
   end},
   {Height = 12, Gap = 4, MinGap = 3, Optional = true, Control = queueHint,
    Apply = function(y, h)
    queueHint.Position = UDim2.new(0, 10, 0, y)
    queueHint.Size = UDim2.new(1, -20, 0, h)
   end},
  })
 else
  -- The desktop proportions, restored in FULL. This branch used to set only
  -- the panel, the close button and the hint text, so every control the touch
  -- branch had moved kept its phone geometry once a device override had been
  -- applied -- the two layouts leaked into each other. It also left the title
  -- at its original 0.88 width, which runs underneath the close button; 0.76
  -- ends clear of it.
  queuePanel.Active = true
  queuePanel.AnchorPoint = Vector2.new(0.5, 0.5)
  queuePanel.Position = UDim2.fromScale(0.5, 0.5)
  -- Offsets, and the constraint states the SAME numbers. A scale size with a
  -- min/max constraint means the panel's real height is decided behind the
  -- layout's back -- 0.86x0.82 reads as 606x277 at 705x338 and is then silently
  -- clamped to 470x330 -- which is precisely how a stack measured for 370 came
  -- to be drawn into 330 and overlap itself.
  local queueWidth = math.clamp(math.floor(queueLayout.Width * .86), 320, 470)
  local queueHeight = math.clamp(math.floor(queueLayout.Height * .82), 330, 370)
  queueConstraint.MinSize = Vector2.new(queueWidth, queueHeight)
  queueConstraint.MaxSize = Vector2.new(queueWidth, queueHeight)
  queuePanel.Size = UDim2.fromOffset(queueWidth, queueHeight)
  queueShade.BackgroundTransparency = 0.38
  queueShade.Active = true

  -- Reset the anchors the touch branch sets. Position and Size alone are not
  -- enough: an anchored child moved back to a top-left offset without clearing
  -- its AnchorPoint lands half its own width off, and that is exactly the leak
  -- the comment above is about.
  queueClose.AnchorPoint = Vector2.new(0, 0)
  queuePlus.AnchorPoint = Vector2.new(0, 0)
  queueClose.Position = UDim2.new(1, -46, 0, 10)
  queueClose.Size = UDim2.fromOffset(34, 34)
  queueClose.TextSize = 24
  queueTitle.TextSize = 31
  queueStationLabel.TextSize = 18
  queueSizeCaption.TextSize = 19
  queueMinus.TextSize = 21
  queueCount.TextSize = 44
  queuePlus.TextSize = 21
  queuePrivacyCaption.TextSize = 19
  queuePrivacyButton.TextSize = 18
  queueSubmit.TextSize = 21
  queueHint.TextSize = 14
  queueHint.Text = "STEP OFF THE PAD TO CANCEL"

  layoutQueueRows(queueHeight, 7, 6, {
   {Height = 38, Gap = 16, MinGap = 8, Control = queueTitle, Apply = function(y, h)
    queueTitle.Position = UDim2.new(0.06, 0, 0, y)
    queueTitle.Size = UDim2.new(0.76, 0, 0, h)
   end},
   {Height = 24, Gap = 3, MinGap = 2, Control = queueStationLabel, Apply = function(y, h)
    queueStationLabel.Position = UDim2.new(0.10, 0, 0, y)
    queueStationLabel.Size = UDim2.new(0.80, 0, 0, h)
   end},
   {Height = 24, Gap = 13, MinGap = 6, Control = queueSizeCaption, Apply = function(y, h)
    queueSizeCaption.Position = UDim2.new(0.08, 0, 0, y)
    queueSizeCaption.Size = UDim2.new(0.84, 0, 0, h)
   end},
   -- The count sits two pixels proud of the steppers and four taller, which is
   -- an optical adjustment for a 44px numeral against two 21px glyphs. The
   -- row's MinGap is 4 so those two pixels can never eat the caption above it.
   {Height = 52, Gap = 6, MinGap = 4, Apply = function(y, h)
    queueMinus.Position = UDim2.new(0.10, 0, 0, y)
    queueMinus.Size = UDim2.new(0.20, 0, 0, h)
    queueCount.Position = UDim2.new(0.37, 0, 0, y - 2)
    queueCount.Size = UDim2.new(0.26, 0, 0, h + 4)
    queuePlus.Position = UDim2.new(0.70, 0, 0, y)
    queuePlus.Size = UDim2.new(0.20, 0, 0, h)
   end},
   {Height = 24, Gap = 18, MinGap = 8, Control = queuePrivacyCaption, Apply = function(y, h)
    queuePrivacyCaption.Position = UDim2.new(0.08, 0, 0, y)
    queuePrivacyCaption.Size = UDim2.new(0.84, 0, 0, h)
   end},
   {Height = 48, Gap = 6, MinGap = 4, Control = queuePrivacyButton, Apply = function(y, h)
    queuePrivacyButton.Position = UDim2.new(0.10, 0, 0, y)
    queuePrivacyButton.Size = UDim2.new(0.80, 0, 0, h)
   end},
   {Height = 50, Gap = 20, MinGap = 8, Control = queueSubmit, Apply = function(y, h)
    local preview = queuePanel:FindFirstChild("MapPreview")
    if preview and queueShade:GetAttribute("QueueLaunchModes") == "trial,preview" then
     queueSubmit.TextSize = 17
     queueSubmit.Position = UDim2.new(0.10, 0, 0, y)
     queueSubmit.Size = UDim2.new(0.39, 0, 0, h)
     preview.TextSize = 17
     preview.Position = UDim2.new(0.51, 0, 0, y)
     preview.Size = UDim2.new(0.39, 0, 0, h)
     preview.Visible = true
    else
     queueSubmit.Position = UDim2.new(0.10, 0, 0, y)
     queueSubmit.Size = UDim2.new(0.80, 0, 0, h)
     if preview then preview.Visible = false end
    end
   end},
   {Height = 16, Gap = 5, MinGap = 4, Optional = true, Control = queueHint,
    Apply = function(y, h)
    queueHint.Position = UDim2.new(0.08, 0, 0, y)
    queueHint.Size = UDim2.new(0.84, 0, 0, h)
   end},
  })
 end
end
applyQueueDeviceLayout()
-- Built once at load in the old code, so a form-factor change after start
-- left the party panel in the wrong layout for the rest of the session.
UIDevice.Changed:Connect(applyQueueDeviceLayout)

local queueStation = nil
local queueSizeValue = 6
local queuePrivacyValue = "public"
local queueSubmitting = false

local function refreshQueuePanel()
 queueCount.Text = tostring(queueSizeValue)
 local friendsOnly = queuePrivacyValue == "friends"
 queuePrivacyButton.Text = friendsOnly and "FRIENDS ONLY" or "PUBLIC  •  EVERYONE"
 queuePrivacyButton.TextColor3 = friendsOnly and Color3.fromRGB(255, 218, 125) or Color3.fromRGB(125, 255, 178)
 queuePrivacyStroke.Color = friendsOnly and Color3.fromRGB(255, 202, 95) or Color3.fromRGB(120, 255, 175)
 queueStationLabel.Text = queueStation and ("STATION " .. queueStation .. "  •  YOU ARE THE HOST") or "YOU ARE THE HOST"
 local modes = queueShade:GetAttribute("QueueLaunchModes")
 local trial = modes == "trial,preview"   -- "trial" alone is a public host: the ordinary CREATE PARTY
 queueSubmit.Text = queueSubmitting and (trial and "STARTING..." or "CREATING PARTY...") or (trial and "TRIAL ROUND" or "CREATE PARTY")
 queueSubmit.Active = not queueSubmitting
 queueSubmit.AutoButtonColor = not queueSubmitting
 queueSubmit.BackgroundColor3 = queueSubmitting and Color3.fromRGB(42, 50, 44) or Color3.fromRGB(42, 105, 70)
 local preview = queuePanel:FindFirstChild("MapPreview")
 if preview then
  preview.Text = queueSubmitting and "STARTING..." or "MAP PREVIEW"
  preview.Active = not queueSubmitting
  preview.AutoButtonColor = not queueSubmitting
  preview.BackgroundColor3 = queueSubmitting and Color3.fromRGB(40, 46, 56) or Color3.fromRGB(38, 62, 96)
 end
end

queueMinus.Activated:Connect(function()
 if queueSubmitting then return end
 queueSizeValue = math.max(1, queueSizeValue - 1)
 refreshQueuePanel()
end)
queuePlus.Activated:Connect(function()
 if queueSubmitting then return end
 queueSizeValue = math.min(6, queueSizeValue + 1)
 refreshQueuePanel()
end)
queuePrivacyButton.Activated:Connect(function()
 if queueSubmitting then return end
 queuePrivacyValue = queuePrivacyValue == "public" and "friends" or "public"
 refreshQueuePanel()
end)
-- AUDIT_FIX_20260924: the party panel was the one modal with no controller
-- path. Nothing was selected, so the stick walked the host out of the square
-- (which cancels the party), A jumped and B did nothing. A gamepad opening now
-- selects CREATE PARTY, B cancels exactly like the X, and a hide drops any
-- selection left inside -- a stale one keeps dispatchAudio.inputBlocked() true.
-- A do-block: this chunk is at the 200-local limit.
do
 -- LEVEL4_QUEUE_CHOICE_20261002: both launch buttons share one submit; the mode rides as ConfigureQueue's 4th
 -- argument ("trial" / "preview", nil on stations that offer no choice -- the server keeps today's behaviour).
 local function submitQueue(mode)
  if queueSubmitting or not queueStation then return end
  queueSubmitting = true
  refreshQueuePanel()
  queueRemote:FireServer(queueStation, queueSizeValue, queuePrivacyValue, mode)
  task.delay(3, function()
   if queueShade.Visible and queueSubmitting then
    queueSubmitting = false
    refreshQueuePanel()
   end
  end)
 end
 queueSubmit.Activated:Connect(function()
  local modes = queueShade:GetAttribute("QueueLaunchModes")
  submitQueue((modes == "trial,preview" or modes == "trial") and "trial" or (modes == "preview" and "preview" or nil))
 end)
 local mapPreview = queuePanel:FindFirstChild("MapPreview")
 if mapPreview then mapPreview.Activated:Connect(function() submitQueue("preview") end) end
 queueShade:GetAttributeChangedSignal("QueueLaunchModes"):Connect(function()
  applyQueueDeviceLayout()
  refreshQueuePanel()
 end)
 local function cancelHostedQueue()
  if queueSubmitting or not queueStation then return end
  local stationToCancel = queueStation
  queueShade.Visible = false
  queueStation = nil
  queueSubmitting = false
  refreshQueuePanel()
  queueRemote:FireServer(stationToCancel, 0, "cancel")
 end
 queueClose.Activated:Connect(cancelHostedQueue)
 queueShade:GetPropertyChangedSignal("Visible"):Connect(function()
  local navigation = game:GetService("GuiService")
  if queueShade.Visible then
   if UIDevice.LastInput() == "Gamepad" then navigation.SelectedObject = queueSubmit end
   ContextActionService:BindActionAtPriority("QueueHostClose", function(_, inputState)
    if not queueShade.Visible or navigation.MenuIsOpen then return Enum.ContextActionResult.Pass end
    if inputState == Enum.UserInputState.Begin then cancelHostedQueue() end
    return Enum.ContextActionResult.Sink
   end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
  else
   queueShade:SetAttribute("QueueLaunchModes", nil)
   ContextActionService:UnbindAction("QueueHostClose")
   if navigation.SelectedObject and navigation.SelectedObject:IsDescendantOf(queueShade) then
    navigation.SelectedObject = nil
   end
  end
 end)
end
refreshQueuePanel()

-- RoundUI is the sole cursor-policy owner. Lobby players need the mouse for the
-- queue phone and Zyntra store; gameplay hides it unless a modal is open.
-- `color`, the two action buttons and their shared list all belong to the
-- result screen and live here rather than as file locals: this script sits on
-- Luau's 200-local limit for a chunk's main body.
local completion = {returnVisible = false,
	color = Color3.fromRGB(68, 221, 196)}
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

-- The queue modal announces itself. ZyntraStore has to hide its own open button
-- while this panel is up -- two lobby modals stacked on a 705x338 phone is one
-- modal too many -- and that contract is only as strong as the flag behind it.
--
-- WHAT SHIPPED BROKEN: nothing published the state at all, so the store had no
-- way to know. The flag is deliberately derived from the ONE property that every
-- show and every hide path already writes, instead of from the fourteen call
-- sites that write it: `queuehost` opens the panel; construction, the X button,
-- showRoundEnding and the lobby / queueconfigured / queueconfigclosed /
-- queuewaitinghost / queueprivate / queuefull / lobbycancel / spectating /
-- loadinggame events all close it -- and every single one of them lands here.
-- A path that forgets to clear the flag is therefore not expressible: cancelling
-- the party, the host walking out of the square, and the round starting are all
-- just `queueShade.Visible = false`, and this fires on each of them.
player:SetAttribute("QueueModalOpen", queueShade.Visible)
-- ...and the dispatch briefing yields to this panel from the SAME choke point.
-- WHAT SHIPPED BROKEN: nothing connected the two, so a lobby briefing drew its
-- own panel over an open party dialog and a party dialog opened underneath a
-- live briefing. Mirroring the state HERE rather than at the fourteen call
-- sites is what makes the exclusion hold on every one of them -- cancelling the
-- party, the host stepping out of the square and the round starting are all
-- just `queueShade.Visible = false`, and each of them lands on this signal.
-- See C4A_BRIEFING_VS_QUEUE_20260829 in dispatchAudio.refresh for the rule.
dispatchAudio.queueModalOpen = queueShade.Visible
-- C_QUEUE_MODAL_TAKES_THE_CONTROLS_20260831 -- WHAT SHIPPED BROKEN.
--
-- QueueModalOpen is one of the four flags UIDevice.ScreenOwningModalOpen()
-- answers to -- the Level 3 reader stands down for it, the Zyntra opener hides
-- for it -- but nothing ever stood the MOVEMENT controls down, so the party
-- dialog was the one screen-owning modal in the game with a live thumbstick and
-- a live JUMP under it. Measured on a 568x320 landscape phone with the short-
-- screen row cluster: QueueModalOpen=true, TouchMovementSuppressed=false, and
-- CREATE PARTY overlapping the control row by nine pixels -- a tap meant for the
-- dialog landing on a movement button.
--
-- It suppresses now, from the same one choke point every show and hide already
-- lands on, so a path that forgets is not expressible. Touch only: UIDevice
-- ignores the request on a pointer device, where a modal has never taken
-- movement away.
UIDevice.SuppressTouchMovement(UIDevice.ScreenOwningModalOpen())
queueShade:GetPropertyChangedSignal("Visible"):Connect(function()
 player:SetAttribute("QueueModalOpen", queueShade.Visible)
 -- Zyntra/re-entry may still own the screen when this shade closes. Movement
 -- follows the combined published modal state, never whichever caller ran last.
 UIDevice.SuppressTouchMovement(UIDevice.ScreenOwningModalOpen())
 dispatchAudio.queueModalOpen = queueShade.Visible
 -- Raise or lower the briefing to match, and republish DispatchBriefingOpen
 -- with it. Both flags are written from this one handler, so they can never
 -- disagree and neither can be left stuck by a path that only touches one.
 dispatchAudio.refresh()
end)
queueShade:GetPropertyChangedSignal("Visible"):Connect(refreshCursor)
player:GetAttributeChangedSignal("InRound"):Connect(refreshCursor)
player:GetAttributeChangedSignal("DevPhoneOpen"):Connect(refreshCursor)
player:GetAttributeChangedSignal("ZyntraReentryOpen"):Connect(refreshCursor)
player:GetAttributeChangedSignal("PartyDownCardOpen"):Connect(refreshCursor)
refreshCursor()

-- An open modal must keep the pointer free. Ordinary lobby play deliberately
-- does not touch MouseBehavior here: Roblox uses its temporary right-button
-- lock to rotate the Classic camera while RMB is held.
RunService.RenderStepped:Connect(function()
 if UIS.MouseEnabled and (queueShade.Visible or player:GetAttribute("DevPhoneOpen") == true
  or player:GetAttribute("ZyntraReentryOpen") == true
  or player:GetAttribute("PartyDownCardOpen") == true
  or completion.returnVisible) then
  UIS.MouseBehavior = Enum.MouseBehavior.Default
  UIS.MouseIconEnabled = true
 end
end)

-- Every loading cover is opaque black. Imported card accents use the owner's
-- six level colours; the status and inactive track slots stay Sage.
local LOADING_PALETTES = require(RS:WaitForChild("LoadingCardView")).Palettes
local function loadingPaletteFor(level)
	return LOADING_PALETTES[tonumber(level) or 0] or LOADING_PALETTES[1]
end

-- Immediate startup cover: the player sees this before a character or maze exists.
local loadingFrame = Instance.new("Frame")
loadingFrame.Name = "LevelLoading"
loadingFrame.Size = UDim2.fromScale(1, 1)
loadingFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0) -- pure black for every level (owner, 2026-10-08)
loadingFrame.BackgroundTransparency = 0 -- opaque: the world never shows through (owner, 2026-10-08)
loadingFrame.BorderSizePixel = 0
loadingFrame.ZIndex = 100
loadingFrame.Visible = false -- the server lobby is visible first
loadingFrame.Parent = gui

local loadingTitle = nil
local loadingStatus = nil
local activeLoadingPalette = loadingPaletteFor(1)
local function applyLoadingPalette(level)
	activeLoadingPalette = loadingPaletteFor(level)
	if dispatchAudio.loadingCards then dispatchAudio.loadingCards.show(level) end
end

-- HUD_B8_LOADING: presentation only; the server's tokenized entry barrier owns release.
do
	local Hud = require(RS:WaitForChild("RoundHud"))
	local View = require(RS:WaitForChild("LoadingCardView"))
	local loadingCards = {MysteryTitles = View.MysteryTitles, MysteryTitlePool = View.MysteryTitlePool,
		MysteryTitleMode = View.MysteryTitleMode, Cards = View.Cards, level = 1, progress = 0}
	dispatchAudio.Hud = Hud
	dispatchAudio.loadingCards = loadingCards
	local function mounted(view)
		loadingCards.root, loadingCards.fill = view.Root, view.Fill
		loadingTitle, loadingStatus = view.Title, view.Status
		loadingCards.level, loadingCards.progress, loadingCards.title = view.Level, view.Progress, view.MysteryText
	end
	function loadingCards.mysteryTitle(level)
		return View.MysteryTitle(level, loadingCards.MysteryTitleMode)
	end
	function loadingCards.mount()
		if loadingCards.view then loadingCards.view:_mount() end
	end
	function loadingCards.paint()
		if loadingCards.view then loadingCards.view:_paint() end
	end
	function loadingCards.show(level)
		if not loadingCards.view then
			loadingCards.view = View.new(loadingFrame, level, mounted)
		else
			loadingCards.view.MysteryTitleMode = loadingCards.MysteryTitleMode
			loadingCards.view:SetLevel(level)
		end
	end
	function loadingCards.stage(fraction)
		loadingCards.view:SetStatus(nil, fraction)
		loadingCards.progress = loadingCards.view.Progress
	end
	loadingCards.show(1)
end

-- Full-screen round payoff. It is intentionally separate from the objective bar so
-- it scales cleanly on desktop, phone and tablet.
local endFrame = Instance.new("Frame")
endFrame.Name = "RoundEnding"
endFrame.Size = UDim2.fromScale(1, 1)
endFrame.BackgroundColor3 = Color3.fromRGB(3, 6, 4)
endFrame.BackgroundTransparency = 1
endFrame.BorderSizePixel = 0
endFrame.Active = true
endFrame.Visible = false
player:SetAttribute("RoundEndingOpen", false)
endFrame.ZIndex = 120
endFrame.Parent = gui

-- The result screen is ONE shape: a full-bleed overlay, for wins and for wipes
-- alike. It carried a second, compact "card" variant for a while so a finished
-- map stayed visible behind it; that variant is gone, and with it the pair of
-- divergent layout branches that had to be kept in step. The Level 2 exit ride
-- is unaffected -- the flume, the respawn handoff and the spectate hold-off are
-- all driven by the Level2_ExitTransition attribute on the server, never by the
-- shape of this overlay.

local endFlash = Instance.new("Frame")
endFlash.Name = "SignalFlash"
endFlash.Size = UDim2.fromScale(1, 1)
endFlash.BackgroundColor3 = Color3.fromRGB(83, 204, 145)
endFlash.BackgroundTransparency = 1
endFlash.BorderSizePixel = 0
endFlash.ZIndex = 121
endFlash.Parent = endFrame

local endLine = Instance.new("Frame")
endLine.Name = "SignalLine"
endLine.AnchorPoint = Vector2.new(0.5, 0.5)
endLine.Position = UDim2.fromScale(0.5, 0.56)
endLine.Size = UDim2.new(0, 0, 0, 2)
endLine.BackgroundColor3 = Color3.fromRGB(83, 204, 145)
endLine.BorderSizePixel = 0
endLine.ZIndex = 122
endLine.Parent = endFrame

local endTitle = nil
local endStats = nil
local endHint = nil

-- HUD_B8_RESULTS: every visual part comes from the actual imported Results tree.
do
	local Hud = require(RS:WaitForChild("RoundHud"))
	local Binder = require(RS:WaitForChild("ZyntraShopUI"):WaitForChild("ShopBinder"))
	completion.Hud = Hud
	completion.choiceMembers = {}
	completion.roster = {}
	completion.choiceRows = {}
	function completion.caption(button, text)
		local caption = Binder.find(button, "Label")
		if caption then caption.Text = text end
		local action = button:GetAttribute("CompletionAction")
		if action then
			completion.captions = completion.captions or {}
			completion.captions[action] = text
		end
	end
	function completion.opacity(value)
		if not completion.window then return end
		for _, node in ipairs(completion.window:GetDescendants()) do
			if node:IsA("TextLabel") then node.TextTransparency = value end
		end
	end
	function completion.displayName(member)
		local other = tonumber(member.UserId) and Players:GetPlayerByUserId(tonumber(member.UserId))
		return other and other.DisplayName or member.DisplayName or member.Name
	end
	function completion.render()
		if not completion.window then return end
		local data = completion.resultData or {}
		endTitle.Text = data.Title or ""
		endTitle.TextColor3 = completion.color or Color3.fromRGB(68, 221, 196)
		endHint.Text = data.Hint or ""
		endStats.Visible = not data.Temporary
		for name, value in pairs({Stat_Time = data.Time or "--:--", Stat_Survivors = data.Survivors or "--"}) do
			local num = Binder.at(endStats, name .. "/Num")
			if num then num.Text = value end
		end
		local counter = data.Counter
		local tile = Binder.find(endStats, "Stat_Counter")
		if tile then
			tile.Visible = data.Loss == true and counter ~= nil
			if tile.Visible then
				Binder.find(tile, "Label").Text = tostring(counter.Label or "PROGRESS")
				Binder.find(tile, "Num").Text = tostring(counter.Current or 0) .. "/" .. tostring(counter.Max or 0)
			end
		end
		completion.parts.Party.Visible = #(completion.choiceMembers or {}) > 0
		completion.layoutChoices()
	end
	function completion.layoutChoices()
		if not completion.choiceList then return end
		local members = completion.choiceMembers or {}
		local list = completion.choiceList
		local count = #members
		list.Visible = count > 0
		list.Active = count > 0 and endFrame.Visible
		local layout = UIDevice.Layout()
		local rowHeight = completion.compact and 36 or 68 * completion.scale
		local room = math.max(rowHeight, layout.Safe.Height - (completion.headHeight + completion.footerHeight + completion.partyHeight + 32))
		list.Size = UDim2.fromOffset(completion.width, math.min(count * rowHeight, room))
		list.CanvasSize = UDim2.fromOffset(0, count * rowHeight)
		list.ScrollingEnabled = count * rowHeight > room
		list.ScrollBarThickness = list.ScrollingEnabled and 3 or 0
		list.CanvasPosition = Vector2.new(0, math.min(list.CanvasPosition.Y, math.max(0, count * rowHeight - room)))
		for i, row in ipairs(completion.choiceRows) do
			local member = members[i]
			row.Visible = member ~= nil
			if member then
				row.AnchorPoint = Vector2.new(0, 0)
				row.Position = UDim2.fromOffset(0, (i - 1) * rowHeight)
				row.Size = UDim2.fromOffset(completion.width, rowHeight)
				local display = completion.displayName(member) or "PLAYER"
				Binder.find(row, "Who").Text = display
				Binder.at(row, "Initial/Letter").Text = string.upper(utf8.char(utf8.codepoint(display, 1)))
				local other = tonumber(member.UserId) and Players:GetPlayerByUserId(tonumber(member.UserId))
				local hum = other and other.Character and other.Character:FindFirstChildOfClass("Humanoid")
				local gotOut = other and other:GetAttribute("Escaped") == true
				local fell = hum and hum.Health <= 0
				Binder.find(row, "Sub").Text = gotOut and "GOT OUT" or fell and "FELL" or "WATCHING NEXT"
				local choice = member.Choice == "continuing" and "CONTINUE" or member.Choice == "returning" and "LOBBY"
					or completion.returnVisible and "DECIDING" or gotOut and "GOT OUT" or fell and "DOWN" or "INSIDE"
				Binder.at(row, "Chip/Label").Text = choice
			end
		end
	end
	function completion.mount()
		local layout = UIDevice.Layout()
		local touch = layout.IsTouch or layout.Safe.Height < 620 or layout.Safe.Width < 800
		completion.compact = touch
		local template = touch and "ResultsTouch" or "Results"
		local designWidth = touch and 726 or 1040
		completion.width = math.min(designWidth, layout.Safe.Width - 24)
		completion.scale = completion.width / designWidth
		local focusAction = game:GetService("GuiService").SelectedObject
		focusAction = focusAction and focusAction:GetAttribute("CompletionAction")
		if completion.window then completion.window:Destroy() end
		completion.window, completion.parts = Hud.Stack("HUD_Screens", template, endFrame,
			{Name = "ResultsWindow", Scale = completion.scale, Touch = touch})
		if not completion.window then return end
		completion.window.AnchorPoint = Vector2.new(0.5, 0.5)
		completion.window.Position = UIDevice.LocalPosition(gui,
			(layout.Safe.Left + layout.Safe.Right) / 2, (layout.Safe.Top + layout.Safe.Bottom) / 2)
		for _, node in ipairs(completion.window:GetDescendants()) do
			if node:IsA("GuiObject") then node.ZIndex = 123 end
		end
		endTitle = Binder.find(completion.window, "EndingTitle")
		endStats = Binder.find(completion.window, "EndingStats")
		endHint = Binder.find(completion.window, "EndingHint")
		completion.continueButton = Binder.find(completion.parts.Footer, "ContinueRun")
		completion.button = Binder.find(completion.parts.Footer, "ReturnToLobby")
		completion.buttons = {completion.continueButton, completion.button}
		completion.countdown = Binder.find(completion.parts.Footer, "Countdown")
		completion.countNum = Binder.find(completion.parts.Footer, "CountNum")
		completion.headHeight = completion.parts.Head.Size.Y.Offset
		completion.partyHeight = completion.parts.Party.Size.Y.Offset
		completion.footerHeight = completion.parts.Footer.Size.Y.Offset
		if touch then
			-- Imported actions are 52 high at the authored 726 width. A portrait
			-- resize must preserve their touch targets, so resize only this row.
			completion.footerHeight = 82
			completion.parts.Footer.Size = UDim2.fromOffset(completion.width, completion.footerHeight)
			for i, button in ipairs(completion.buttons) do
				button.AnchorPoint = Vector2.new(0, 1)
				button.Position = UDim2.new((i - 1) * 0.5, i == 1 and 0 or 6, 1, 0)
				button.Size = UDim2.new(0.5, -6, 0, 52)
			end
			completion.countdown.AnchorPoint = Vector2.new(0, 0)
			completion.countdown.Position = UDim2.fromOffset(0, 0)
			completion.countdown.Size = UDim2.new(1, -48, 0, 24)
			completion.countNum.AnchorPoint = Vector2.new(1, 0)
			completion.countNum.Position = UDim2.new(1, 0, 0, 0)
			completion.countNum.Size = UDim2.fromOffset(44, 24)
			if completion.width < 520 then
				completion.headHeight = math.max(completion.headHeight, 130)
				completion.parts.Head.Size = UDim2.fromOffset(completion.width, completion.headHeight)
				endTitle.TextWrapped = true
			end
		end
		local list = Instance.new("ScrollingFrame")
		list.Name = "PartyChoices"
		list.BackgroundTransparency = 1
		list.BorderSizePixel = 0
		list.ScrollingDirection = Enum.ScrollingDirection.Y
		list.ScrollBarImageColor3 = Color3.fromRGB(167, 184, 174)
		list.CanvasSize = UDim2.fromOffset(0, 0)
		list.CanvasPosition = Vector2.new(0, 0)
		list.ClipsDescendants = true
		list.LayoutOrder = 3
		list.ZIndex = 123
		list.Parent = completion.window
		completion.choiceList = list
		completion.choiceRows = {}
		for i = 1, 6 do
			local row = completion.parts["PartyChoice" .. i]
			row.Parent = list
			completion.choiceRows[i] = row
		end
		completion.parts.Footer.LayoutOrder = 10
		for i, button in ipairs(completion.buttons) do
			button:SetAttribute("CompletionAction", i == 1 and "continuenow" or "returntolobby")
			button:SetAttribute("CompletionPressedText", i == 1 and "CONTINUING..." or "RETURNING...")
			button.Visible = completion.returnVisible == true and (i == 2 or completion.nextLevel ~= nil)
			button.Active = button.Visible and not completion.pending
			button.Selectable = button.Active
			button.Modal = true
			button.Activated:Connect(function() completion.activate(button) end)
			if focusAction == button:GetAttribute("CompletionAction") and button.Active then
				game:GetService("GuiService").SelectedObject = button
			end
		end
		if not completion.continueButton.Visible and completion.button.Visible then
			completion.button.AnchorPoint = Vector2.new(0.5, 1)
			completion.button.Position = UDim2.new(0.5, 0, 1, 0)
		end
		if not completion.continueButton.Visible and not completion.button.Visible then
			completion.footerHeight = 30
			completion.parts.Footer.Size = UDim2.fromOffset(completion.width, completion.footerHeight)
		end
		completion.caption(completion.continueButton, completion.captions and completion.captions.continuenow or "CONTINUE")
		completion.caption(completion.button, completion.captions and completion.captions.returntolobby or "BACK TO LOBBY")
		Hud.Paint(completion.window, "Results", workspace:GetAttribute("SelectedLevel") or 1)
		completion.render()
	end
	function completion.clearChoices()
		completion.lastChoiceRequestAt = nil
		completion.choiceRevision = 0
		completion.choiceMembers = {}
		if completion.choiceList then
			completion.choiceList.Visible = false
			completion.choiceList.CanvasPosition = Vector2.new(0, 0)
		end
		for _, row in ipairs(completion.choiceRows) do row.Visible = false end
	end
	function completion.setRoster(packet)
		if type(packet) ~= "table" or type(packet.Members) ~= "table" then return end
		local members = {}
		for _, member in ipairs(packet.Members) do
			if type(member) == "table" and type(member.Name) == "string" and member.Name ~= "" and tonumber(member.UserId) then
				members[#members + 1] = {Name = member.Name, UserId = tonumber(member.UserId), Choice = member.Choice}
			end
		end
		completion.roster = members
		completion.choiceMembers = members
		completion.render()
	end
	function completion.suspend()
		local navigation = game:GetService("GuiService")
		if table.find(completion.buttons, navigation.SelectedObject) then navigation.SelectedObject = nil end
		for _, button in ipairs(completion.buttons) do button.Active = false; button.Selectable = false end
	end
	function completion.applyChoices(packet)
		if type(packet) ~= "table" or packet.Serial ~= completion.serverSerial
			or type(packet.Revision) ~= "number" or packet.Revision <= (completion.choiceRevision or 0)
			or type(packet.Members) ~= "table" or not completion.returnVisible then return end
		completion.choiceRevision = packet.Revision
		if packet.Closed == true then completion.pending = true end
		local editable = not completion.pending and completion.deadline
			and workspace:GetServerTimeNow() < completion.deadline
		for _, button in ipairs(completion.buttons) do
			button.Active = button.Visible and editable == true
			button.Selectable = button.Active
		end
		completion.setRoster(packet)
	end
	function completion.applyLayout(color)
		completion.color = color or completion.color
		completion.mount()
	end
	completion.mount()
	UIDevice.Changed:Connect(function() completion.applyLayout(completion.color) end)
end

-- C_ONE_SPECTATE_CAMERA_20260904: the SpectateBanner that used to live here is
-- gone. It was built, worded and hidden, and nothing ever set it Visible --
-- SpectateController owns the on-screen spectate label, and showing this one as
-- well stacked two "no surviving signal" messages on top of each other.

local exitThud = Instance.new("Sound")
exitThud.Name = "ExitThresholdThud"
exitThud.SoundId = "rbxasset://sounds/bass.wav"
exitThud.Volume = 0.9
exitThud.PlaybackSpeed = 0.62
exitThud.Parent = gui
local exitChime = Instance.new("Sound")
exitChime.Name = "ExitSignalChime"
exitChime.SoundId = "rbxasset://sounds/electronicpingshort.wav"
exitChime.Volume = 0.52
exitChime.PlaybackSpeed = 0.78
exitChime.Parent = gui

local endingSerial = 0
local spectating = false

local function formatRoundTime(seconds)
 local total = math.max(0, math.floor(tonumber(seconds) or 0))
 return string.format("%02d:%02d", math.floor(total / 60), total % 60)
end

function completion.reset()
	if not endFrame.Visible then player:SetAttribute("RoundEndingOpen", false) end
	completion.clearChoices()
	completion.deadline = nil
	completion.watchDeadline = nil
	completion.nextLevel = nil
	completion.serverSerial = nil
	completion.pending = false
	completion.returnVisible = false
	completion.caption(completion.continueButton, "CONTINUE")
	completion.caption(completion.button, "BACK TO LOBBY")
	-- AUDIT_FIX_20260924: hand back the controller focus start() gave out.
	local navigation = game:GetService("GuiService")
	if table.find(completion.buttons, navigation.SelectedObject) then navigation.SelectedObject = nil end
	for _, button in ipairs(completion.buttons) do
		button.Visible = false
		button.Active = false
		button.Selectable = false
	end
	refreshCursor()
end

-- `nextLevel` is the server's decision, and it is the ONLY thing that puts a
-- Continue action on screen. The last level reports no next level, so it shows
-- Back to Lobby alone and cannot route anyone to a level that does not exist.
function completion.start(deadline, nextLevel, serverSerial)
	completion.clearChoices()
	completion.choiceMembers = completion.roster or {}
	completion.deadline = tonumber(deadline) or (workspace:GetServerTimeNow() + 15)
	completion.nextLevel = tonumber(nextLevel)
	completion.serverSerial = tonumber(serverSerial)
	completion.pending = false
	completion.returnVisible = completion.serverSerial ~= nil
	completion.caption(completion.continueButton, "CONTINUE")
	completion.caption(completion.button, "BACK TO LOBBY")
	completion.continueButton.Visible = completion.returnVisible
		and completion.nextLevel ~= nil
	completion.button.Visible = completion.returnVisible
	for _, button in ipairs(completion.buttons) do
		button.Active = button.Visible
		button.Selectable = button.Visible
	end
	-- Re-measure: the row is one button wide on the last level and two on every
	-- other, and start() is what decides which.
	if endFrame.Visible then completion.applyLayout(completion.color) end
	refreshCursor()
	-- AUDIT_FIX_20260924: refreshCursor only frees a mouse, so a controller had
	-- no way to the choice. CONTINUE first: it is also the server's default, so
	-- a stray A changes nothing; the last level shows BACK TO LOBBY alone.
	if UIDevice.LastInput() == "Gamepad" then
		local target = completion.continueButton.Visible and completion.continueButton or completion.button
		if target.Visible then game:GetService("GuiService").SelectedObject = target end
	end
end

-- One handler for both actions. Which remote message a button sends is read
-- from the button itself, so the wiring is inspectable state rather than two
-- separate closures that can quietly be swapped.
function completion.activate(button)
	if completion.pending or not completion.returnVisible or not completion.serverSerial then
		return false
	end
	if not button.Visible or not button.Active then return false end
	local now = workspace:GetServerTimeNow()
	if not completion.deadline or now >= completion.deadline then return false end
	local action = button:GetAttribute("CompletionAction")
	if action ~= "continuenow" and action ~= "returntolobby" then return false end
	if action == "continuenow" and completion.nextLevel == nil then return false end
	if completion.lastChoiceRequestAt and now - completion.lastChoiceRequestAt < 0.15 then return false end
	completion.lastChoiceRequestAt = now
	-- Keep both choices available. The existing server roster is the only
	-- displayed selection; a click never pretends travel has already begun.
	completion.caption(button, button:GetAttribute("CompletionPressedText"))
	remote:FireServer(action, completion.serverSerial)
	return true
end

-- `remaining` only ticks once a second; cache it (and the expired state) so
-- the Text write and the button-disable loop only run when something changed.
-- Scoped in a do-block: this chunk sits at Luau's 200-local register limit,
-- and block locals hand their registers back at `end` (the closure keeps them).
do
	local completionLastDeadline, completionLastRemaining = nil, nil
	local completionButtonsDisabled = false
	RunService.RenderStepped:Connect(function()
		if not endFrame.Visible then return end
		if completion.watchDeadline then
			local remaining = math.max(0, math.ceil(completion.watchDeadline - os.clock()))
			local id = tonumber(player:GetAttribute("SpectateTargetUserId"))
			local target = id and Players:GetPlayerByUserId(id)
			completion.countdown.Text = "WATCHING " .. (target and string.upper(target.DisplayName) or "THE OTHERS") .. " IN"
			completion.countNum.Text = tostring(remaining)
			return
		end
		local deadline = completion.deadline
		if not deadline then
			completion.countdown.Text = completion.resultData and completion.resultData.Hint or ""
			completion.countNum.Text = ""
			return
		end
		if deadline ~= completionLastDeadline then
			completionLastDeadline, completionLastRemaining = deadline, nil
			completionButtonsDisabled = false
		end
		local remaining = math.max(0, math.ceil(deadline - workspace:GetServerTimeNow()))
		if remaining ~= completionLastRemaining then
			completionLastRemaining = remaining
			completion.countdown.Text = completion.nextLevel
				and ("LEVEL " .. completion.nextLevel .. " BEGINS IN") or "RETURNING TO LOBBY IN"
			completion.countNum.Text = tostring(remaining)
		end
		if remaining <= 0 and not completionButtonsDisabled then
			completionButtonsDisabled = true
			local navigation = game:GetService("GuiService")
			if table.find(completion.buttons, navigation.SelectedObject) then navigation.SelectedObject = nil end
			for _, button in ipairs(completion.buttons) do button.Active = false; button.Selectable = false end
		end
	end)
end

-- AUDIT_FIX_20260924 (Codex review): a pad picked up while the party panel or
-- the round-complete choice is ALREADY open takes focus too; opening them was
-- the only moment that set it. A focus already inside the modal is kept.
do
	local navigation = game:GetService("GuiService")
	UIS.LastInputTypeChanged:Connect(function(inputType)
		if not inputType.Name:find("^Gamepad") or navigation.MenuIsOpen then return end
		local current = navigation.SelectedObject
		if queueShade.Visible then
			if not (current and current:IsDescendantOf(queueShade)) then navigation.SelectedObject = queueSubmit end
		elseif endFrame.Visible and not table.find(completion.buttons, current) then
			local target = completion.continueButton.Visible and completion.continueButton or completion.button
			if target.Visible and target.Active then navigation.SelectedObject = target end
		end
	end)
end
-- C_ONE_SPECTATE_CAMERA_20260904 -- WHAT SHIPPED BROKEN.
--
-- TWO scripts drove the spectate camera off the same Humanoid.Died.
-- SpectateController takes a full first-person POV: CameraType.Scriptable and
-- the watched player's head CFrame written EVERY RenderStepped, plus the POV
-- lock, Q/E switching, the hidden body and the borrowed flashlight. This file
-- picked its own target and wrote CameraType.Custom + CameraSubject on a 0.35s
-- ticker. Whichever ran last won that frame, so a dead player's view flipped
-- between a locked first-person POV and an orbit camera on somebody else.
--
-- The camera half is gone from here. What is left is the FLAG half, which other
-- parts of this file genuinely read (`dead`) and which is also the cleanup path
-- after an Emergency Re-entry respawn -- SpectateController does not listen for
-- the round ending, so it now stops itself on RoundActive going false.
local function startSpectating()
 spectating = true
end

local function stopSpectating()
 spectating = false
end

-- Emergency Re-entry loads a fresh gameplay character without firing any
-- round status event, so the death/spectate state must clear on the new
-- body itself — otherwise `dead` outlives the revival and every HUD gated on
-- it stays hidden for a player who is walking around again.
player.CharacterAdded:Connect(function()
 dead = false
 stopSpectating()
end)

local function hideRoundEnding(immediate)
 completion.reset()
 endingSerial += 1
 local token = endingSerial
 if immediate then
  endFrame.Visible = false
  player:SetAttribute("RoundEndingOpen", false)
  endFrame.BackgroundTransparency = 1
  endFlash.BackgroundTransparency = 1
  return
 end
 completion.opacity(1)
 TweenService:Create(endFrame, TweenInfo.new(0.42), {BackgroundTransparency = 1}):Play()
 TweenService:Create(endLine, TweenInfo.new(0.3), {BackgroundTransparency = 1}):Play()
 task.delay(0.46, function()
  if endingSerial == token then
   endFrame.Visible = false
   player:SetAttribute("RoundEndingOpen", false)
  end
 end)
end

local function showRoundEnding(title, stats, hint, color, temporary)
 -- Capture before Clear: objective progress remains the truthful loss counter.
 local objective = completion.Hud.LastObjective()
 completion.reset()
 endingSerial += 1
 local token = endingSerial
 color = color or Color3.fromRGB(68, 221, 196)
 completion.resultData = {
  Title = title, Hint = hint or "", Temporary = temporary == true,
  Loss = title == "NO ONE FOUND A WAY OUT",
  Time = type(stats) == "string" and stats:match("TIME%s+(%d+:%d+)") or "--:--",
  Survivors = type(stats) == "string" and stats:match("SURVIVORS%s+(%d+/%d+)") or "--",
  Counter = objective and objective.Counter,
 }
 completion.choiceMembers = completion.roster or {}
 completion.watchDeadline = temporary and os.clock() + 2.75 or nil
 completion.applyLayout(color)
 completion.Hud.Clear()
 loadingFrame.Visible = false
 queueShade.Visible = false
 label.Visible = false
 endFrame.Visible = true
 player:SetAttribute("RoundEndingOpen", temporary ~= true)
 endFrame.BackgroundTransparency = 1
 endFlash.BackgroundColor3 = color
 endFlash.BackgroundTransparency = player:GetAttribute("ReduceFlashing") == true and 1 or 0.08
 completion.opacity(0)
 endLine.BackgroundColor3 = color
 endLine.BackgroundTransparency = 0
 endLine.Size = UDim2.new(0, 0, 0, 2)

 exitThud:Stop()
 exitChime:Stop()
 exitThud.TimePosition = 0
 exitChime.TimePosition = 0
 exitThud:Play()
 task.delay(0.12, function() if endingSerial == token and endFrame.Visible then exitChime:Play() end end)
 if player:GetAttribute("ReduceFlashing") ~= true then
  TweenService:Create(endFlash, TweenInfo.new(0.7, Enum.EasingStyle.Quad), {BackgroundTransparency = 1}):Play()
 end
 TweenService:Create(endFrame, TweenInfo.new(0.42, Enum.EasingStyle.Quad),
  {BackgroundTransparency = 0.08}):Play()
 TweenService:Create(endLine, TweenInfo.new(0.55, Enum.EasingStyle.Quart), {Size = UDim2.new(0.70, 0, 0, 2)}):Play()

 if temporary then
  task.delay(2.75, function()
   if endingSerial ~= token then return end
   hideRoundEnding(false)
   task.delay(0.5, function()
    -- LEVEL2_EXIT_TRANSITION_20260828: a Level 2 escapee is still physically
    -- riding the exit flume through the whole decision window. Spectating them
    -- out of their own body mid-slide is exactly the "removed or obscured"
    -- behaviour the continuous transition is meant to replace, so hold off
    -- until the server clears the transition marker.
    if player:GetAttribute("Level2_ExitTransition") == true then return end
    if player:GetAttribute("InRound") == true and (dead or player:GetAttribute("Escaped") == true) then
     startSpectating()
    end
   end)
  end)
 end
end

if RunService:IsStudio() then
 -- Studio-only press hook for UIRegression: drives the real handler, so the
 -- assertion covers the production routing rather than a stand-in for it.
 player:GetAttributeChangedSignal("UIRegressionCompletionPress"):Connect(function()
  local wanted = player:GetAttribute("UIRegressionCompletionPress")
  if type(wanted) ~= "string" or wanted == "" then return end
  for _, button in ipairs(completion.buttons) do
   if button.Name == wanted then completion.activate(button) end
  end
 end)
 player:GetAttributeChangedSignal("DevRoundEnding"):Connect(function()
  local mode = tostring(player:GetAttribute("DevRoundEnding") or ""):lower()
  if mode:find("escape", 1, true) then
   showRoundEnding("YOU GOT OUT", "", "WAITING FOR THE OTHERS", Color3.fromRGB(68, 221, 196), true)
	-- "winfinal" is tested BEFORE "win": find() is a substring match and the
	-- final-level mode would otherwise be swallowed by the ordinary one.
	elseif mode:find("winfinal", 1, true) then
		-- The last level: no next level exists, so no Continue action does either.
		showRoundEnding(("LEVEL " .. tostring(workspace:GetAttribute("SelectedLevel") or 3) .. " CLEARED"), "TIME 05:08  •  SURVIVORS 2/3", "RETURNING TO LOBBY", Color3.fromRGB(68, 221, 196), false)
		completion.start(workspace:GetServerTimeNow() + 15, nil, -1)
	elseif mode:find("win", 1, true) then
		showRoundEnding(("LEVEL " .. tostring(workspace:GetAttribute("SelectedLevel") or 1) .. " CLEARED"), "TIME 03:42  •  SURVIVORS 2/3", "RETURNING TO LOBBY", Color3.fromRGB(68, 221, 196), false)
		-- Exercise the complete production win state in UIRegression: the overlay
		-- is not valid unless its countdown and BOTH actions are present too. A
		-- negative serial is intentionally Studio-only.
		completion.start(workspace:GetServerTimeNow() + 15, 2, -1)
  elseif mode:find("lose", 1, true) then
   showRoundEnding("NO ONE FOUND A WAY OUT", "TIME 04:17  •  SURVIVORS 0/3", "RETURNING TO LOBBY", Color3.fromRGB(242, 112, 95), false)
  elseif mode:find("hide", 1, true) then
   hideRoundEnding(true)
  end
 end)
end

local loadingSequenceFinished = false
local serverReadyForEntry = false
local loadingClock = 0
local loadingBaseText = "LOCATING ANOMALOUS SPACE"

-- Dots only change twice a second; skip the rebuild/write unless the dot
-- count or the base text actually moved since last frame.
-- Scoped in a do-block: this chunk sits at Luau's 200-local register limit,
-- and block locals hand their registers back at `end` (the closure keeps them).
do
	local loadingLastBaseText = nil
	local loadingLastDotsCount = nil

	RunService.RenderStepped:Connect(function(dt)
		if not loadingFrame.Visible then return end
		loadingClock += dt
		local dotsCount = math.floor(loadingClock * 2) % 4
		if dotsCount ~= loadingLastDotsCount or loadingBaseText ~= loadingLastBaseText then
			loadingLastDotsCount = dotsCount
			loadingLastBaseText = loadingBaseText
			loadingStatus.Text = loadingBaseText .. string.rep(".", dotsCount)
		end
	end)
end

-- All levels share the server's party barrier. Only an explicit successful
-- release can lift the cover; the sequence below is presentation, never proof.
local entryState = {Active = false, Token = nil, KnownLevel = nil, Error = nil,
	ErrorArmed = true, ErrorSerial = 0, MessageSerial = 0}

local function finishLoadingWhenReady()
	if entryState.Active or not (loadingSequenceFinished and serverReadyForEntry) then return end
	if loadingFrame.Visible then loadingFrame.Visible = false end
end

-- Re-runnable so a level can replay the whole sequence per round. The run token
-- makes a new launch abandon an older sequence instead of letting the two fight
-- over loadingBaseText.
local loadingRun = 0
local function startLoadingSequence()
	loadingRun += 1
	local run = loadingRun
	loadingSequenceFinished = false
	task.spawn(function()
		local stages = {
			"LOCATING ANOMALOUS SPACE",
			"ESTABLISHING ENTRY VECTOR",
			"STABILIZING ENTRY ENERGY",
			"VERIFYING CONTAINMENT",
		}
		for i, stage in ipairs(stages) do
			if loadingRun ~= run then return end
			loadingBaseText = stage
			dispatchAudio.loadingCards.stage(i / (#stages + 1))
			loadingClock = 0
			task.wait(1.35)
		end
		if loadingRun ~= run then return end

		loadingBaseText = "SYNCHRONIZING PARTY"
		dispatchAudio.loadingCards.stage(0.9)
		loadingClock = 0
		task.wait(0.35)
		if loadingRun ~= run then return end
		loadingBaseText = "WAITING FOR EVERYONE TO LOAD"
		loadingClock = 0
		task.wait(1.6)
		if loadingRun ~= run then return end
		loadingSequenceFinished = true
		dispatchAudio.loadingCards.stage(1)
		finishLoadingWhenReady()
	end)
end

startLoadingSequence()

-- Round Entry Client owns stream/ground/asset readiness and tokenized acks.

local DEFAULT_TEXT = Color3.fromRGB(235, 232, 222)
local DEFAULT_SIZE = 26
local DEFAULT_FONT = Enum.Font.GothamMedium
local COMPACT_SIZE = UDim2.new(0, 620, 0, 48)

local function setMsg(text, color)
	entryState.MessageSerial += 1
	label.TextSize = DEFAULT_SIZE
	label.Font = DEFAULT_FONT
	label.TextTransparency = 0
	label.TextStrokeTransparency = 1
	label.Size = COMPACT_SIZE
	label.BackgroundTransparency = 0.85
	label.Text = text or ""
	label.TextColor3 = color or DEFAULT_TEXT
	label.Visible = text ~= nil and text ~= ""
end

-- A failure can arrive through both the remote and the join-time attribute,
-- then be replayed after cleanup. Give one attempt one eight-second notice.
-- Keep these helpers on entryState: this chunk has no spare top-level locals.
function entryState.ClearError(armed)
	entryState.ErrorSerial += 1
	entryState.Error = nil
	entryState.ErrorExpiresAt = nil
	entryState.ErrorMessageSerial = nil
	entryState.ErrorArmed = armed
	if armed then entryState.ErrorReason = nil end
	entryState.ErrorAttribute = player:GetAttribute("RoundLoadingError")
end

function entryState.RenderError()
	if entryState.Error and os.clock() >= entryState.ErrorExpiresAt then
		entryState.Error = nil
	end
	setMsg(entryState.Error or "", Color3.fromRGB(255, 100, 100))
	entryState.ErrorMessageSerial = entryState.MessageSerial
end

function entryState.ShowError(reason)
	if not entryState.ErrorArmed or entryState.ErrorReason then return false end
	entryState.ErrorReason = (reason == "LOADING_TIMEOUT" or reason == "timeout") and "timeout" or "failed"
	entryState.Error = entryState.ErrorReason == "timeout"
		and "LOADING TIMED OUT AFTER 60 SECONDS — PLEASE TRY AGAIN"
		or "ROUND LOADING FAILED — PLEASE TRY AGAIN"
	entryState.ErrorSerial += 1
	entryState.ErrorExpiresAt = os.clock() + 8
	entryState.RenderError()
	local serial, message = entryState.ErrorSerial, entryState.Error
	task.delay(8, function()
		if entryState.ErrorSerial ~= serial then return end
		entryState.Error = nil
		-- Expiry retires the incident, even if another status has replaced it.
		-- The text check also protects a later status written by another flow.
		if entryState.ErrorMessageSerial == entryState.MessageSerial and label.Text == message then
			setMsg("")
		end
	end)
	return true
end

-- Level 1 command briefing. This replaces the old typed objective sequence and
-- uses its own subtitle layer so the shared lobby/status label stays available.
local LEVEL_ONE_BRIEFING_ID = "rbxassetid://110249611823719"
local LEVEL_ONE_RADIO_CUE_ID = "rbxassetid://73198577463663"
local LEVEL_ONE_BRIEFING_DELAY = 2.5 -- radio cue leads in; speech still begins about 2.5s after placement
-- The Level 2 briefing (voice, radio cue, captions, run state and functions) is
-- deleted whole: it told the party the pumps alert an entity, and the new
-- Level 2 has none (owner, 2026-10-08). Its asset ids stay in
-- assets/live-asset-manifest.json.
local levelThreeBriefing = {
	speechId = "rbxassetid://113751783401897",
	radioId = "rbxassetid://105627123289647",
	delay = 2.5, -- the two-second radio cue begins half a second after placement
	run = 0,
	preloaded = false,
	started = false,
}

-- One private Command Center welcome across the player's lifetime. The server
-- sends a dedicated ready-acknowledged event after profile loading, and the
-- durable Zyntra profile retires the welcome as soon as its first transmission
-- begins. Level briefings remain repeatable because they contain gameplay info.
local lobbyBriefing = {
	speechId = "rbxassetid://121135469064341",
	radioId = "rbxassetid://116864891394910",
	delay = 2.5,
	radioLength = 1.032,
	run = 0,
	played = false,
	persistedStarted = false,
	readySent = false,
	pending = false,
	active = false,
	preloaded = false,
	cues = {
		{0.00, 1.28, "New arrival..."},
		{1.28, 2.67, "Command Center here."},
		{2.67, 6.03, "You have successfully arrived inside the Zyntra Transit Concourse—"},
		{6.03, 9.92, "the Company's only stable gateway into the anomalous spaces."},
		{9.92, 12.70, "Numbered level chambers line both sides of the tunnel."},
		{12.70, 15.62, "Select an active chamber and enter its transit gate."},
		{15.62, 19.44, "Set your team capacity and clearance, then remain inside the marked zone."},
		{19.44, 22.29, "Transfer begins when your team is assembled."},
		{22.29, 27.21, "Beyond the gate, follow your assigned briefing, stay together, and locate a route back."},
		{27.21, 28.25, "Be advised..."},
		{28.25, 31.17, "everything inside these spaces is highly classified."},
		{31.17, 33.69, "No personal account may leave this facility."},
		{33.69, 37.47, "Any disclosure will be treated as a containment breach."},
		{37.47, 39.97, "If something on the other side recognizes you..."},
		{39.97, 41.84, "do not assume it is human."},
		{41.84, 43.54, "Proceed when ready."},
		{43.54, 45.10, "Command Center, over and out."},
	},
}

local guideGui = Instance.new("ScreenGui")
guideGui.Name = "LevelOneGuideGui"
guideGui.ResetOnSpawn = false
guideGui.IgnoreGuiInset = false
guideGui.DisplayOrder = 110
guideGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
guideGui.Parent = player:WaitForChild("PlayerGui")

local function roundAndStroke(parent, radius, color, transparency, thickness)
	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, radius)
	uiCorner.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Transparency = transparency
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
end

local subtitleFrame = Instance.new("Frame")
subtitleFrame.Name = "CommandSubtitles"
subtitleFrame.AnchorPoint = Vector2.new(0.5, 1)
subtitleFrame.Position = UDim2.new(0.5, 0, 1, -64)
subtitleFrame.Size = UDim2.new(0.76, 0, 0, 96)
subtitleFrame.BackgroundColor3 = Color3.fromRGB(4, 8, 6)
subtitleFrame.BackgroundTransparency = 0.18
subtitleFrame.BorderSizePixel = 0
subtitleFrame.Visible = false
subtitleFrame.ZIndex = 20
subtitleFrame.Parent = guideGui
dispatchAudio.panel = subtitleFrame
roundAndStroke(subtitleFrame, 8, Color3.fromRGB(82, 224, 164), 0.38, 1.5)

local subtitleConstraint = Instance.new("UISizeConstraint")
-- 280 is wider than a 375px portrait screen allows once the 20px margins the
-- narrow layout applies are taken off, which forced the panel over its own
-- bounds. 240 fits every viewport in the regression matrix.
subtitleConstraint.MinSize = Vector2.new(240, 88)
subtitleConstraint.MaxSize = Vector2.new(860, 118)
subtitleConstraint.Parent = subtitleFrame

local subtitleSpeaker = Instance.new("TextLabel")
subtitleSpeaker.Name = "Speaker"
subtitleSpeaker.Position = UDim2.fromOffset(18, 8)
subtitleSpeaker.Size = UDim2.new(1, -278, 0, 20)
subtitleSpeaker.BackgroundTransparency = 1
subtitleSpeaker.Font = Enum.Font.Code
subtitleSpeaker.Text = "> COMMAND CENTER  //  LIVE"
if not dispatchAudio.voiceEnabled then
	subtitleSpeaker.Text = "> COMMAND CENTER  //  BRIEFING"
end
subtitleSpeaker.TextColor3 = Color3.fromRGB(105, 238, 168)
subtitleSpeaker.TextSize = 13
subtitleSpeaker.TextXAlignment = Enum.TextXAlignment.Left
subtitleSpeaker.ZIndex = 21
subtitleSpeaker.Parent = subtitleFrame

local subtitleText = Instance.new("TextLabel")
subtitleText.Name = "Subtitle"
subtitleText.Position = UDim2.fromOffset(18, 28)
subtitleText.Size = UDim2.new(1, -36, 1, -36)
subtitleText.BackgroundTransparency = 1
subtitleText.Font = Enum.Font.GothamMedium
subtitleText.Text = ""
subtitleText.TextColor3 = Color3.fromRGB(240, 242, 235)
subtitleText.TextSize = 20
subtitleText.TextWrapped = true
subtitleText.TextXAlignment = Enum.TextXAlignment.Left
subtitleText.TextYAlignment = Enum.TextYAlignment.Center
subtitleText.ZIndex = 21
subtitleText.Parent = subtitleFrame
dispatchAudio.subtitleLabel = subtitleText

-- Briefing audio controls live inside the subtitle panel instead of floating by
-- the equipment HUD. They deliberately read as two quiet terminal chips: easy
-- to find while Command is live, absent everywhere else.
dispatchAudio.controls = Instance.new("Frame")
dispatchAudio.controls.Name = "BriefingControls"
dispatchAudio.controls.AnchorPoint = Vector2.new(1, 0)
dispatchAudio.controls.Position = UDim2.new(1, -12, 0, 7)
dispatchAudio.controls.Size = UDim2.fromOffset(232, 28)
dispatchAudio.controls.BackgroundTransparency = 1
dispatchAudio.controls.BorderSizePixel = 0
dispatchAudio.controls.Visible = false
dispatchAudio.controls.ZIndex = 23
dispatchAudio.controls.Parent = guideGui -- transport controls are independent of the retired subtitle panel

local briefingControlsLayout = Instance.new("UIListLayout")
briefingControlsLayout.FillDirection = Enum.FillDirection.Horizontal
briefingControlsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
briefingControlsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
briefingControlsLayout.Padding = UDim.new(0, 6)
briefingControlsLayout.SortOrder = Enum.SortOrder.LayoutOrder
briefingControlsLayout.Parent = dispatchAudio.controls
dispatchAudio.layout = briefingControlsLayout

-- MUTE / STOP are terminal readouts, not buttons. They carry the COMMAND
-- CENTER label's own colour, font and weight -- no panel, no border, no
-- rounded chip -- so they read as two more lines of the transmission. The
-- tappable area is the full 44px-tall row behind the text, which is invisible
-- but comfortably larger than the glyphs.
dispatchAudio.button = Instance.new("TextButton")
dispatchAudio.button.Name = "DispatchMuteButton"
dispatchAudio.button.LayoutOrder = 1
dispatchAudio.button.Size = UDim2.fromOffset(148, 30)
dispatchAudio.button.BackgroundTransparency = 1
dispatchAudio.button.BorderSizePixel = 0
dispatchAudio.button.AutoButtonColor = false
dispatchAudio.button.Font = Enum.Font.Code
dispatchAudio.button.Text = "MUTE DISPATCH"
dispatchAudio.button.TextColor3 = Color3.fromRGB(105, 238, 168)
dispatchAudio.button.TextSize = 13
dispatchAudio.button.TextXAlignment = Enum.TextXAlignment.Right
dispatchAudio.button.ZIndex = 24
dispatchAudio.button.Parent = dispatchAudio.controls
dispatchAudio.button.Activated:Connect(function()
	dispatchAudio.requestToggle()
end)
ContextActionService:BindAction("ZyntraToggleDispatchMute", function(_, inputState)
	if inputState ~= Enum.UserInputState.Begin
		or UIS:GetFocusedTextBox()
		or dispatchAudio.inputBlocked()
		or not dispatchAudio.hasActiveTransmission() then
		return Enum.ContextActionResult.Pass
	end
	return dispatchAudio.requestToggle()
		and Enum.ContextActionResult.Sink
		or Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.M, Enum.KeyCode.ButtonL1)

dispatchAudio.stopButton = Instance.new("TextButton")
dispatchAudio.stopButton.Name = "DispatchStopButton"
dispatchAudio.stopButton.LayoutOrder = 2
dispatchAudio.stopButton.Size = UDim2.fromOffset(148, 30)
dispatchAudio.stopButton.BackgroundTransparency = 1
dispatchAudio.stopButton.BorderSizePixel = 0
dispatchAudio.stopButton.AutoButtonColor = false
dispatchAudio.stopButton.Font = Enum.Font.Code
dispatchAudio.stopButton.Text = "STOP DISPATCH"
dispatchAudio.stopButton.TextColor3 = Color3.fromRGB(105, 238, 168)
dispatchAudio.stopButton.TextSize = 13
dispatchAudio.stopButton.TextXAlignment = Enum.TextXAlignment.Right
dispatchAudio.stopButton.ZIndex = 24
dispatchAudio.stopButton.Parent = dispatchAudio.controls
dispatchAudio.stopButton.Activated:Connect(function()
	dispatchAudio.requestStop()
end)
ContextActionService:BindAction("ZyntraStopCurrentDispatch", function(_, inputState)
	if inputState ~= Enum.UserInputState.Begin
		or UIS:GetFocusedTextBox()
		or dispatchAudio.inputBlocked()
		-- ButtonB belongs to the advertised table-exit control while hiding.
		-- Let that gameplay action pass without also stopping the dispatch.
		or player:GetAttribute("Level3_Hiding") == true
		or not dispatchAudio.hasActiveTransmission() then
		return Enum.ContextActionResult.Pass
	end
	return dispatchAudio.requestStop()
		and Enum.ContextActionResult.Sink
		or Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.N, Enum.KeyCode.ButtonB)
dispatchAudio.refresh()

local levelOneBriefingSound = Instance.new("Sound")
levelOneBriefingSound.Name = "LevelOneCommandBriefing"
levelOneBriefingSound.SoundId = LEVEL_ONE_BRIEFING_ID
levelOneBriefingSound.Volume = 1
levelOneBriefingSound.Looped = false
levelOneBriefingSound.SoundGroup = dispatchAudio.group
levelOneBriefingSound.Parent = guideGui

local levelOneRadioCue = Instance.new("Sound")
levelOneRadioCue.Name = "LevelOneRadioOpen"
levelOneRadioCue.SoundId = LEVEL_ONE_RADIO_CUE_ID
levelOneRadioCue.Volume = 0
levelOneRadioCue.Looped = false
levelOneRadioCue.SoundGroup = dispatchAudio.group
levelOneRadioCue.Parent = guideGui

levelThreeBriefing.sound = Instance.new("Sound")
levelThreeBriefing.sound.Name = "LevelThreeCommandBriefing"
levelThreeBriefing.sound.SoundId = levelThreeBriefing.speechId
levelThreeBriefing.sound.Volume = 1
levelThreeBriefing.sound.PlaybackSpeed = 1
levelThreeBriefing.sound.Looped = false
levelThreeBriefing.sound.SoundGroup = dispatchAudio.group
levelThreeBriefing.sound.Parent = guideGui

levelThreeBriefing.pitch = Instance.new("PitchShiftSoundEffect")
levelThreeBriefing.pitch.Name = "FailingCommsPitch"
levelThreeBriefing.pitch.Octave = 1
levelThreeBriefing.pitch.Parent = levelThreeBriefing.sound

levelThreeBriefing.radio = Instance.new("Sound")
levelThreeBriefing.radio.Name = "LevelThreeRadioOpen"
levelThreeBriefing.radio.SoundId = levelThreeBriefing.radioId
levelThreeBriefing.radio.Volume = 0
levelThreeBriefing.radio.PlaybackSpeed = 1
levelThreeBriefing.radio.Looped = false
levelThreeBriefing.radio.SoundGroup = dispatchAudio.group
levelThreeBriefing.radio.Parent = guideGui

lobbyBriefing.sound = Instance.new("Sound")
lobbyBriefing.sound.Name = "LobbyCommandBriefing"
lobbyBriefing.sound.SoundId = lobbyBriefing.speechId
lobbyBriefing.sound.Volume = 1
lobbyBriefing.sound.PlaybackSpeed = 1
lobbyBriefing.sound.Looped = false
lobbyBriefing.sound.SoundGroup = dispatchAudio.group
lobbyBriefing.sound.Parent = guideGui

lobbyBriefing.radio = Instance.new("Sound")
lobbyBriefing.radio.Name = "LobbyRadioOpen"
lobbyBriefing.radio.SoundId = lobbyBriefing.radioId
lobbyBriefing.radio.Volume = 0
lobbyBriefing.radio.PlaybackSpeed = 1
lobbyBriefing.radio.Looped = false
lobbyBriefing.radio.SoundGroup = dispatchAudio.group
lobbyBriefing.radio.Parent = guideGui

-- Cue starts were measured from the uploaded 46.99-second recording. Captions
-- track Sound.TimePosition so loading or frame-rate delays cannot desync them.
local briefingCues = {
	{0.00, 3.46, "Team Alpha, this is Command Center. Stand by for briefing."},
	{3.46, 7.72, "We know very little about this anomalous space, but we may have identified a way out."},
	{7.72, 10.50, "Look for groups of unusually bright ceiling lights."},
	{10.50, 12.93, "A fuse relay should be nearby."},
	{12.93, 15.83, "Extract the fuses, then locate the colored cables."},
	{15.83, 20.78, "Each cable connects a fuse box to a lever... but we cannot determine which end is which."},
	{20.78, 25.86, "Power every fuse box first. Then activate each lever. They stay on; there is no time limit."},
	{25.86, 31.19, "Be advised... we are detecting movement inside the space that does not match your team."},
	{31.19, 33.88, "We know nothing about the entity responsible."},
	{33.88, 36.91, "If you see or hear anything unusual, stay alert."},
	{36.91, 39.98, "Keep your distance... and do not engage."},
	{39.98, 44.24, "Once the exit door is powered on, your energy reader will guide you to it."},
	{44.24, 45.61, "Good luck, Team Alpha."},
	{45.61, 47.10, "Command Center, over and out."},
}

-- Timed against the uploaded 52.610612-second Level 3 recording.
levelThreeBriefing.cues = {
	{0.00, 3.90, "Team Alpha. Come in. This is Command Center. Stand by for briefing."},
	{3.90, 8.50, "You've made it farther than we expected... And for that... I salute you."},
	{8.50, 11.50, "Our comms link is deteriorating, so listen carefully."},
	{11.50, 15.10, "Five compact discs, which may be CDs, are scattered throughout the space."},
	{15.10, 19.60, "Recover them and bring them to the television and VCR unit near the sealed wall."},
	{19.60, 21.90, "Every carrier must insert their own discs."},
	{21.90, 24.70, "When all five are loaded, a hidden passage should appear."},
	{24.70, 27.00, "A humanoid entity is searching the rooms."},
	{27.00, 31.00, "When the disturbing song is over, it can locate your presence in an instance."},
	{31.00, 32.70, "It hunts whoever is nearest."},
	{32.70, 35.40, "Keep moving, and do not let it corner you."},
	{35.40, 37.90, "If the music begins playing backwards..."},
	{37.90, 40.70, "The passage is open, and you have to find it."},
	{40.70, 43.90, "I have to say, that it's getting really dangerous now."},
	{43.90, 46.40, "But remember... you are doing important research."},
	{46.40, 48.80, "And your courage will never be forgotten."},
	{48.80, 50.60, "Best of luck to you."},
	{50.60, 52.65, "Command Center, over and out."},
}

-- Deterministic transmission damage keeps the instructions legible while the
-- voice itself briefly drops, snaps upward and sags in pitch. PlaybackSpeed
-- remains exactly one, so neither caption timing nor the speech pace changes.
levelThreeBriefing.interference = {
	{8.70, 9.28, "jitter"},
	{14.78, 14.86, "cut"},
	{27.65, 28.22, "jitter"},
	{32.55, 32.63, "cut"},
	{40.85, 41.42, "jitter"},
	{46.55, 47.12, "jitter"},
}
levelThreeBriefing.jitterOctaves = {0.84, 1.07, 0.91, 1.02}

local briefingRun = 0
local briefingPreloaded = false
local elevatorBriefingStarted = false
player:SetAttribute("LevelOneBriefingActive", false)
player:SetAttribute("LevelThreeBriefingActive", false)
player:SetAttribute("LobbyBriefingActive", false)
player:SetAttribute("LobbyBriefingPlayed", false)
player:SetAttribute("LobbyBriefingSkipped", false)

local function isLevelOneParticipant()
	return workspace:GetAttribute("SelectedLevel") == 1
		and player:GetAttribute("InRound") == true
		and player:GetAttribute("Escaped") ~= true
		and not dead
end

ContextActionService:UnbindAction("ToggleObjectiveHelp")

local function setSubtitle(text)
	local nextCopy = text or ""
	local changed = dispatchAudio.subtitleCopy ~= nextCopy
	dispatchAudio.subtitleCopy = nextCopy
	dispatchAudio.refresh()
	-- A device or reader change can fit the panel to a short current cue.
	-- Refit when the next line arrives so a longer line cannot overflow it.
	if changed and dispatchAudio.relayoutForCaption then
		dispatchAudio.relayoutForCaption()
	end
end

function lobbyBriefing.isEligible()
	-- PrivateServerId is server-only. GameManager already scopes the one-shot
	-- event to a public lobby. Unknown/failed profile state stays fail-quiet so a
	-- returning player can never hear the welcome again because a load timed out.
	return player:GetAttribute("InRound") ~= true
		and not dead
		and workspace:FindFirstChild("ServerLobby") ~= nil
		and dispatchAudio.preferenceLoaded()
		and (lobbyBriefing.persistedStarted
			or player:GetAttribute("ZyntraLobbyBriefingPlayed") ~= true)
end

function lobbyBriefing.hasArrived()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local lobby = workspace:FindFirstChild("ServerLobby")
	local spawn = lobby and lobby:FindFirstChild("LobbySpawn")
	return root ~= nil and root:IsA("BasePart")
		and spawn ~= nil and spawn:IsA("BasePart")
		and (root.Position - spawn.Position).Magnitude <= 30
end

function lobbyBriefing.preload()
	if lobbyBriefing.preloaded then return true end
	local ok = pcall(function()
		ContentProvider:PreloadAsync(dispatchAudio.voiceEnabled
			and {lobbyBriefing.radio, lobbyBriefing.sound} or {lobbyBriefing.radio})
	end)
	lobbyBriefing.preloaded = ok
		and lobbyBriefing.radio.IsLoaded
		and (not dispatchAudio.voiceEnabled or lobbyBriefing.sound.IsLoaded)
	return lobbyBriefing.preloaded
end

function lobbyBriefing.cancel()
	lobbyBriefing.run += 1
	dispatchAudio.clearTransmission("lobby")
	local ownedSubtitle = lobbyBriefing.active
	lobbyBriefing.pending = false
	lobbyBriefing.active = false
	lobbyBriefing.radio:Stop()
	lobbyBriefing.sound:Stop()
	player:SetAttribute("LobbyBriefingActive", false)
	if ownedSubtitle then setSubtitle(nil) end
end

function lobbyBriefing.skip()
	if not lobbyBriefing.active then return false end
	player:SetAttribute("LobbyBriefingSkipped", true)
	lobbyBriefing.cancel()
	return true
end
function lobbyBriefing.playOnce()
	do return end -- BRIEFINGS_OFF_20261004 (owner): no Command Center briefing, voice or subtitle, in the lobby or in any level
	if lobbyBriefing.played or not lobbyBriefing.isEligible() then return end
	lobbyBriefing.played = true
	lobbyBriefing.pending = true
	player:SetAttribute("LobbyBriefingSkipped", false)
	lobbyBriefing.run += 1
	local run = lobbyBriefing.run
	player:SetAttribute("LobbyBriefingPlayed", true)
	player:SetAttribute("LobbyBriefingActive", false)

	task.spawn(function()
		if dispatchAudio.voiceEnabled then dispatchAudio.awaitPreference() end
		lobbyBriefing.preload()
		local arrivalDeadline = os.clock() + 20
		while run == lobbyBriefing.run
			and lobbyBriefing.isEligible()
			and not lobbyBriefing.hasArrived()
			and os.clock() < arrivalDeadline do
			RunService.Heartbeat:Wait()
		end
		if run ~= lobbyBriefing.run
			or not lobbyBriefing.isEligible()
			or not lobbyBriefing.hasArrived() then
			if run == lobbyBriefing.run then lobbyBriefing.cancel() end
			return
		end

		-- InvokeServer may lose its response after UpdateAsync has committed. The
		-- server deliberately retains one stable claim token for this session, so
		-- make bounded, non-overlapping retries and let it recover that exact
		-- commit. Do not use isEligible() here: a successful-but-lost first call
		-- already flips the persisted attribute to true before the recovery call.
		local claimed, shouldPlay = false, false
		for _, retryDelay in ipairs({0, .35, .8, 1.5}) do
			if retryDelay > 0 then task.wait(retryDelay) end
			if run ~= lobbyBriefing.run
				or player:GetAttribute("InRound") == true
				or dead
				or not dispatchAudio.preferenceLoaded()
				or not workspace:FindFirstChild("ServerLobby")
				or not lobbyBriefing.hasArrived() then
				break
			end
			claimed, shouldPlay = pcall(function()
				return dispatchAudio.claimLobbyBriefing:InvokeServer()
			end)
			if claimed and shouldPlay == true then break end
		end
		if not claimed or shouldPlay ~= true then
			if run == lobbyBriefing.run then lobbyBriefing.cancel() end
			return
		end
		lobbyBriefing.pending = false
		lobbyBriefing.active = true
		lobbyBriefing.persistedStarted = true
		player:SetAttribute("LobbyBriefingActive", dispatchAudio.voiceEnabled)
		local speechAt = os.clock() + lobbyBriefing.delay

		local radioLength = lobbyBriefing.radio.TimeLength > 0.05
			and lobbyBriefing.radio.TimeLength or lobbyBriefing.radioLength
		local remaining = speechAt - radioLength - os.clock()
		if remaining > 0 then task.wait(remaining) end
		if run ~= lobbyBriefing.run or not lobbyBriefing.isEligible() then
			if run == lobbyBriefing.run then lobbyBriefing.cancel() end
			return
		end

		dispatchAudio.beginTransmission("lobby", run, function()
			if run ~= lobbyBriefing.run then return end
			lobbyBriefing.skip()
		end)
		lobbyBriefing.radio:Stop()
		lobbyBriefing.radio.TimePosition = 0
		local radioPlayed = pcall(function() lobbyBriefing.radio:Play() end)
		if radioPlayed then
			local radioStarted = lobbyBriefing.radio.IsPlaying
			local radioStartDeadline = os.clock() + 0.5
			local radioDeadline = os.clock() + radioLength + 1
			while run == lobbyBriefing.run
				and lobbyBriefing.isEligible()
				and os.clock() < radioDeadline do
				if lobbyBriefing.radio.IsPlaying then
					radioStarted = true
				elseif radioStarted or os.clock() >= radioStartDeadline then
					break
				end
				RunService.Heartbeat:Wait()
			end
		end
		remaining = speechAt - os.clock()
		if remaining > 0 then task.wait(remaining) end
		if run ~= lobbyBriefing.run or not lobbyBriefing.isEligible() then
			if run == lobbyBriefing.run then lobbyBriefing.cancel() end
			return
		end

		lobbyBriefing.sound:Stop()
		lobbyBriefing.sound.TimePosition = 0
		local played = true
		if dispatchAudio.voiceEnabled then
			played = pcall(function() lobbyBriefing.sound:Play() end)
		end
		if not played then
			if run == lobbyBriefing.run then lobbyBriefing.cancel() end
			return
		end

		local currentText = nil
		local playbackStarted = lobbyBriefing.sound.IsPlaying
		local playbackStartDeadline = os.clock() + 4
		local deadline = os.clock() + 50
		local captionClock = dispatchAudio.newCaptionClock()
		while run == lobbyBriefing.run
			and lobbyBriefing.isEligible()
			and (not dispatchAudio.voiceEnabled or os.clock() < deadline) do
			local position = dispatchAudio.captionPosition(captionClock, lobbyBriefing.sound)
			local cueText = nil
			for _, cue in ipairs(lobbyBriefing.cues) do
				if position >= cue[1] and position < cue[2] then
					cueText = cue[3]
					break
				end
			end
			if cueText ~= currentText then
				currentText = cueText
				setSubtitle(cueText)
			end
			if not dispatchAudio.voiceEnabled then
				if position >= lobbyBriefing.cues[#lobbyBriefing.cues][2] then break end
			elseif lobbyBriefing.sound.IsPlaying then
				playbackStarted = true
			elseif playbackStarted or os.clock() >= playbackStartDeadline then
				break
			end
			RunService.Heartbeat:Wait()
		end

		if run ~= lobbyBriefing.run then return end
		lobbyBriefing.sound:Stop()
		lobbyBriefing.active = false
		player:SetAttribute("LobbyBriefingActive", false)
		setSubtitle(nil)
		dispatchAudio.finishTransmission("lobby", run)
	end)
end

task.spawn(lobbyBriefing.preload)
player:GetAttributeChangedSignal("InRound"):Connect(function()
	if player:GetAttribute("InRound") == true then lobbyBriefing.cancel() end
end)

local function preloadLevelOneBriefing()
	if briefingPreloaded then return true end
	local ok = pcall(function()
		ContentProvider:PreloadAsync(dispatchAudio.voiceEnabled
			and {levelOneRadioCue, levelOneBriefingSound} or {levelOneRadioCue})
	end)
	briefingPreloaded = ok and levelOneRadioCue.IsLoaded
		and (not dispatchAudio.voiceEnabled or levelOneBriefingSound.IsLoaded)
	return briefingPreloaded
end

task.spawn(preloadLevelOneBriefing)

local function cancelLevelOneBriefing(hideObjectives)
	briefingRun += 1
	dispatchAudio.clearTransmission("level1")
	levelOneRadioCue:Stop()
	levelOneBriefingSound:Stop()
	player:SetAttribute("LevelOneBriefingActive", false)
	setSubtitle(nil)
end

-- The longest line the dispatch panel can ever be asked to render, read off the
-- cue tables themselves so it cannot drift from the script, plus the face
-- chooser that measures against it. The layout below sizes the subtitle face
-- against THIS rather than against the current line: a face chosen per cue
-- would jump between sentences, and a face chosen from the box alone is how the
-- panel came to overflow at all.
--
-- Both hang off `dispatchAudio` rather than becoming file-level locals, and the
-- reason is not style. This script sits exactly at Luau's ceiling of 200 local
-- registers for its main chunk: five more names here and the whole file stops
-- compiling with "Out of local registers". Anything added at this level from
-- now on has to go onto an existing table.
dispatchAudio.longestLine = (function()
	local longest = ""
	for _, set in ipairs({briefingCues, levelThreeBriefing.cues, lobbyBriefing.cues}) do
		for _, cue in ipairs(set or {}) do
			local caption = cue[3]
			if type(caption) == "string" and #caption > #longest then longest = caption end
		end
	end
	return longest
end)()

-- Layout headroom for a 1.6x localisation of the longest authored cue. The
-- runtime stays English today, but measuring only that copy left otherwise
-- valid 44px touch controls sitting above text that overflowed its own label
-- on the smallest supported phones.
dispatchAudio.fitProbe = "Noch wichtiger: das Aktivieren einer Pumpstation alarmiert offenbar eine bislang nicht identifizierte, ungewoehnlich grosse Entitaet und verraet ihr eure derzeitige Position sofort."

-- TextService:GetTextSize is the SYNCHRONOUS measurement API. The layout runs
-- from UIDevice.Changed and from a viewport signal, and yielding in there would
-- let a second layout pass start inside the first, so GetTextBoundsAsync is the
-- wrong tool here even though it is the newer one. Measured against each other
-- on this panel they agree exactly.
-- The readable floor, and it is a FLOOR rather than a preference.
--
-- WHAT SHIPPED BROKEN: the face ladder ended at 9 and 8, described as
-- "emergency rungs". They were reached in ordinary use -- every portrait phone
-- in the matrix rendered its briefing at 8px -- because the ladder was the only
-- thing that gave way when the box was short. 8px Gotham on a phone is not a
-- caption, it is a smudge, and the compact panel bought its size with it.
--
-- The ladder now stops at HARD_FACE. What gives instead is the LAYOUT: the
-- panel's own fit search below refuses any arrangement whose copy box cannot
-- hold the cue at READABLE_FACE, tries a wider rung, then a taller panel, and
-- only then accepts HARD_FACE. Width and height are cheap; legibility is not.
dispatchAudio.READABLE_FACE = 11
dispatchAudio.HARD_FACE = 10

-- What the panel must actually hold at runtime is the copy that is ON it. The
-- 1.6x localisation probe stays, but as a STRESS case the regression matrix
-- drives, not as the thing every live layout is sized against -- sizing every
-- device for a translation nobody has shipped is what pushed real English
-- briefings down to 8px.
dispatchAudio.fitCopy = function()
	-- THE STRING THAT IS ON SCREEN. The label is the authority, not the
	-- transmission's cached copy: a cue set by any path at all -- including the
	-- regression harness, which writes the label directly -- has to be the thing
	-- the box is sized for, or the panel is fitted to one sentence and rendered
	-- with another.
	local label = dispatchAudio.subtitleLabel
	if label and type(label.Text) == "string" and label.Text ~= "" then
		return label.Text
	end
	local copy = dispatchAudio.subtitleCopy
	if type(copy) == "string" and copy ~= "" then return copy end
	return dispatchAudio.longestLine
end

dispatchAudio.faceThatFits = function(ceiling, width, height, text)
	local measured = text or dispatchAudio.fitCopy()
	local faces = {20, 16, 13, 12, 11, 10}
	for _, size in ipairs(faces) do
		if size <= ceiling and size >= dispatchAudio.HARD_FACE then
			local needed = game:GetService("TextService"):GetTextSize(
				measured, size, subtitleText.Font, Vector2.new(width, 100000))
			if needed.Y <= height then return size end
		end
	end
	return dispatchAudio.HARD_FACE
end

-- How tall a copy box has to be to hold `text` at `face` and `width`.
dispatchAudio.copyHeightFor = function(text, face, width)
	return game:GetService("TextService"):GetTextSize(
		text, face, subtitleText.Font, Vector2.new(math.max(1, width), 100000)).Y
end

-- Dormant subtitle layout remains available; RoundHud owns every objective surface.
local function updateLevelOneGuideLayout()
	local layout = UIDevice.Layout()
	local viewport = layout.Viewport
	local narrow = layout.Narrow
	local touch = layout.IsTouch

	-- The briefing panel was the single biggest overlap offender: at 0.76 width
	-- anchored 64px off the bottom it landed straight on RUN and JUMP in every
	-- level. On touch it now takes UIDevice's safe band -- the largest rectangle
	-- clear of BOTH the thumbstick and the control column -- and is sized to it,
	-- because a landscape phone leaves only about 80 vertical pixels there and
	-- the authored 108px panel simply does not fit.
	-- ── the briefing panel and its two readouts ──────────────────────────────
	-- These three rectangles -- speaker line, MUTE/STOP readouts, subtitle --
	-- share one panel, and the previous version simply placed them and hoped.
	-- It did not hold: the subtitle box spanned everything below y=28 while the
	-- readouts sat at y=6, so on every viewport the two genuinely overlapped,
	-- and on the smallest landscape a stacked pair of 44px rows was 92px tall
	-- inside an 88px panel. So the space is now RESERVED rather than assumed:
	-- whichever arrangement is chosen, the subtitle is given what is left over
	-- and nothing is allowed to sit on anything else.
	--
	-- Row sizes are driven by the longest caption each form factor can produce
	-- ("[M]  UNMUTE DISPATCH" on desktop, "UNMUTE DISPATCH" on touch, where the
	-- binding is never printed) and by the 44px touch-target floor.
	-- C_DISPATCH_COMPACT_20260830 -- WHAT SHIPPED BROKEN.
	-- On touch this panel took the WHOLE safe band: 768x117 on a 956x440 iPhone
	-- 16 Pro Max, i.e. 80% of the width and 27% of the height, for two readouts
	-- and one sentence. It read as a full-screen takeover rather than a radio
	-- caption. The rows themselves were 168x44 with 13-14px type, sized for a
	-- desktop-width band.
	--
	-- The compact target is stated once, here, and the ladder below is only
	-- allowed to exceed it where the AUTHORED COPY genuinely does not fit:
	-- width first (a wider panel keeps the two readouts side by side and the
	-- copy on two lines), height only after every width has failed. On the
	-- reference device that lands 560x100 -- 59% x 23% -- and smaller phones
	-- take the least extra the measured text needs.
	local preferredRowWidth = touch and 148 or 190
	local minimumRowWidth = touch and 120 or 162
	local preferredRowHeight = touch and 44 or 30
	-- The labels stay visually subtle, but their transparent input rectangles
	-- never fall below Roblox's 44px touch-target floor.
	local minimumRowHeight = touch and 44 or 26
	local SPEAKER_MINIMUM = 110
	local PANEL_MARGIN = 12
	local TEXT_INSET = 18
	-- The touch row never gives up its 44px hit target. On the shortest supported
	-- landscape band the lead-in is already gone; removing only the fallback's
	-- ornamental top/bottom padding leaves 44px for controls plus the measured
	-- authored copy without crossing into movement space.
	local ROW_HARD_FLOOR = minimumRowHeight

	-- ── WHERE THE BRIEFING LIVES ─────────────────────────────────────────────
	-- The top band, while it can hold one. It frequently cannot: on a 705x338
	-- phone under a 58px topbar the strip above the thumbstick's activation
	-- region is 37px, and two mandatory 44px readouts do not fit in 37px. The
	-- old code met that by flooring the ceiling at 48 -- i.e. by allowing the
	-- panel to be TALLER THAN THE BAND -- so it hung into the thumbstick, which
	-- is precisely the defect the band exists to prevent.
	--
	-- Where the band cannot hold the panel, the briefing moves to ModalArea:
	-- UIDevice's largest rectangle clear of EVERY movement zone. On a landscape
	-- phone that is the lane between the thumbstick and the control column,
	-- which is 345px tall where the band is 70. The panel never grows past its
	-- home, and its home is never a place a thumb is driving the character from.
	local BRIEFING_MIN_HEIGHT = 80
	local band = layout.TopBand
	local readerPassiveLane = false
	if touch and band.Height < BRIEFING_MIN_HEIGHT
		and layout.ModalArea.Height > band.Height then
		band = layout.ModalArea
	end
	-- The Level 3 reader is a live control at the upper-right throughout a
	-- text briefing. On short landscape screens there is no room to put the
	-- caption below its 101px panel inside ModalArea, but there is a safe lane
	-- to its LEFT, above the movement controls. Fit against that lane before
	-- choosing a width; moving a full-width caption after fitting leaves it
	-- painted over the reader even though neither HUD was hidden.
	if touch then
		local readerGui = player.PlayerGui:FindFirstChild("Level3ReaderGui")
		local reader = readerGui and readerGui:FindFirstChild("ReaderPanel")
		if readerGui and readerGui.Enabled and reader and reader.Visible then
			local lane = {
				Left = layout.Safe.Left + 12,
				Right = math.min(layout.Safe.Right - 12, reader.AbsolutePosition.X - 8),
				Top = layout.Safe.Top + 8,
				Bottom = layout.Safe.Bottom - 8,
			}
			for _, zone in ipairs({layout.Zones.Thumbstick,
				layout.Zones.Controls, layout.Zones.Jump}) do
				if lane.Left < zone.Right and lane.Right > zone.Left then
					lane.Bottom = math.min(lane.Bottom, zone.Top - 8)
				end
			end
			lane.Width = math.max(0, lane.Right - lane.Left)
			lane.Height = math.max(0, lane.Bottom - lane.Top)
			-- One 44px row plus the actual cue at the hard readable face is the
			-- minimum useful caption. A narrower lane must earn its place with
			-- measured copy, not by clipping text or shrinking the skip target.
			local copyHeight = dispatchAudio.copyHeightFor(dispatchAudio.fitCopy(),
				dispatchAudio.HARD_FACE, lane.Width - 36)
			local minimumHeight = 45 + math.max(20, copyHeight)
			if lane.Width >= 240 and lane.Height >= minimumHeight then
				band = lane
			else
				-- On the smallest landscape phones the dynamic thumbstick's
				-- reserved rectangle begins only ~41px below the safe top. No
				-- complete caption can fit ABOVE it, and there is no 44px lane
				-- below the reader before the controls begin. Keep the caption
				-- visible to the reader's left as a passive, click-through layer.
				-- Only SKIP takes input, in the horizontal gap between thumbstick
				-- and reader; the panel/background never consumes a movement tap.
				lane.Bottom = math.min(layout.Safe.Bottom - 8,
					reader.AbsolutePosition.Y + reader.AbsoluteSize.Y,
					layout.Zones.Controls.Top - 4, layout.Zones.Jump.Top - 4)
				lane.Height = math.max(0, lane.Bottom - lane.Top)
				local initialWidth = math.min(math.floor(lane.Width),
					math.max(240, math.min(560, math.floor(viewport.X * .59))))
				local skipSpace = lane.Left + initialWidth - 4
					- (layout.Zones.Thumbstick.Right + 1)
				if lane.Width >= 240 and lane.Height >= minimumHeight
					and skipSpace >= 44 then
					band = lane
					readerPassiveLane = true
				end
			end
		end
	end
	dispatchAudio.readerPassiveLane = readerPassiveLane
	subtitleFrame:SetAttribute("ReaderPassiveLane", readerPassiveLane)
	-- These surfaces are visual only; SKIP is the sole interactive descendant.
	-- This matters when the tiny-screen fallback paints across the thumbstick's
	-- conservative activation rectangle without taking a movement tap.
	subtitleFrame.Active = false
	dispatchAudio.controls.Active = false
	subtitleText.Active = false
	-- ── the BAND is the ceiling, and it is enforced in ONE place ─────────────
	-- WHAT SHIPPED BROKEN: the last-resort block at the bottom of this function
	-- sized the panel to its CONTENT -- `textTop + minimumText + bottomPad` --
	-- and never once compared the result to the band it had to live in. On a
	-- 568x320 landscape phone that is 98px of readouts-plus-copy inside a
	-- TopBand under 89px tall, so the panel hung out of its own band and down
	-- into the thumbstick's activation region: the exact defect the band exists
	-- to prevent. It read GREEN the whole time because BriefingFitMatrix only
	-- ever checked the panel's INTERNALS against each other -- never the panel
	-- against the screen, the band, or a movement zone.
	--
	-- BAND_CEILING is computed once, here, and NOTHING below may return a panel
	-- taller than it. `measure` refuses candidates over it, both fallbacks clamp
	-- to it, and the placement clamps again. Because the panel is pinned to the
	-- band's own origin on touch, a panel that fits the band is inside a
	-- rectangle UIDevice has already proved clear of the thumbstick, the control
	-- column and JUMP -- so "fits the band" and "clears every movement zone"
	-- become the same assertion.
	-- NO FLOOR on touch. `math.max(48, ...)` here was the mechanism by which a
	-- panel escaped its own band on the shortest screens; the home rect chosen
	-- above is now big enough that a floor is not needed, and if it ever is not,
	-- a short panel is the correct answer and an overflowing one is not.
	local BAND_LIMIT = touch and math.floor(band.Height)
		or math.max(48, viewport.Y - (narrow and 96 or 64) - PANEL_MARGIN)
	-- The compact height target: 23% of the viewport, never more than 100px,
	-- and never past the band. 100 on the 440px reference device, 86 at 375,
	-- 73 at 320. Desktop is untouched -- it has the room and always had.
	local COMPACT_CEILING = touch
		and math.max(64, math.min(100, math.floor(viewport.Y * .23))) or BAND_LIMIT
	local BAND_CEILING = math.min(BAND_LIMIT, COMPACT_CEILING)
	local baseHeight = narrow and 108 or 96
	-- The band IS the ceiling on touch. The authored 108 is taller than the 87px
	-- band a landscape phone leaves, and starting the search there put the panel
	-- 21px into the thumbstick's activation region -- the exact defect the band
	-- exists to prevent.
	--
	-- Both bounds are clamped to BAND_CEILING rather than to `band.Height`, and
	-- the difference is not cosmetic: band heights come out FRACTIONAL (94.67 on
	-- a 705x338 Galaxy A06), and an unfloored start height is then one pixel over
	-- an integer ceiling, so `measure` would refuse every candidate and the whole
	-- growth pass would silently fall through to the salvage pass below on real
	-- hardware while still passing on any viewport that divides evenly.
	baseHeight = math.clamp(baseHeight, math.min(64, BAND_CEILING), BAND_CEILING)
	local maximumHeight = touch and math.max(baseHeight, math.min(160, BAND_CEILING))
		or math.max(baseHeight, math.min(160, viewport.Y - 220))
	-- The COMPACT width target, and the ladder that is allowed to leave it.
	-- 59% of the viewport, never more than 560, never under the 240 readability
	-- floor, never wider than the band. 560 on the reference device.
	local compactWidth = touch
		and math.min(math.floor(band.Width),
			math.max(240, math.min(560, math.floor(viewport.X * .59))))
		or math.clamp(narrow and (viewport.X - 20) or math.floor(viewport.X * .76), 240, 860)
	local widthLadder = {compactWidth}
	if touch then
		-- Two rungs, and only two. The first buys back exactly enough width to
		-- keep MUTE and STOP side by side at their preferred size
		-- (148 + 148 + 10 + 2*12 = 330); the second is the band itself. Widening
		-- is tried BEFORE growing taller because a taller panel costs the player
		-- screen, while a wider one costs almost nothing on a landscape phone.
		local sideBySide = math.min(math.floor(band.Width),
			preferredRowWidth * 2 + 10 + PANEL_MARGIN * 2)
		if sideBySide > compactWidth then table.insert(widthLadder, sideBySide) end
		local full = math.floor(band.Width)
		if full > widthLadder[#widthLadder] then table.insert(widthLadder, full) end
	end
	local panelWidth = compactWidth

	-- Candidates, most wanted first. `columns` 2 puts the readouts side by side;
	-- 1 stacks them. `ownBand` drops them below the speaker line instead of
	-- beside it, which is what a portrait phone needs and what a short landscape
	-- panel cannot afford.
	local candidates = {}
	for _, ownBand in ipairs({false, true}) do
		for _, columns in ipairs({2, 1}) do
			for _, width in ipairs({preferredRowWidth, minimumRowWidth}) do
				for _, height in ipairs({preferredRowHeight, minimumRowHeight}) do
					table.insert(candidates, {
						Columns = columns, Width = width, Height = height, OwnBand = ownBand,
					})
				end
			end
		end
	end
	-- The same matrix with the lead-in DROPPED, kept in a separate list and
	-- tried only after every full-furniture arrangement has failed.
	--
	-- "> COMMAND CENTER  //  LIVE" is the one piece of this panel that carries
	-- nothing the copy does not already carry, so it is the first thing to go
	-- when a band is too short to hold it beside two 44px readouts. Keeping it
	-- in a SEPARATE list rather than merging it into `candidates` is the part
	-- that matters: merged, a lead-in-less shape could win on a viewport that
	-- fits the full one today, which would be a silent visual regression on
	-- every device currently passing. Separated, nothing that fits today moves.
	local compressed = {}
	for _, candidate in ipairs(candidates) do
		if not candidate.OwnBand then
			table.insert(compressed, {
				Columns = candidate.Columns, Width = candidate.Width,
				Height = candidate.Height, OwnBand = false, SpeakerHidden = true,
			})
		end
	end

	-- The face this pass insists on, declared BEFORE `measure` because `measure`
	-- closes over it. READABLE first; the whole width/height search runs at
	-- that, and only a device that cannot achieve it anywhere drops to HARD --
	-- which is 10, never 8.
	local requiredFace = dispatchAudio.READABLE_FACE

	local function measure(candidate, height)
		local controlsWidth = candidate.Columns == 2
			and candidate.Width * 2 + 10 or candidate.Width
		-- 6, because the UIListLayout that stacks them uses 6. It said 4, so a
		-- stacked pair was measured 2px shorter than it renders and the two
		-- readouts overflowed the row they were given.
		local controlsHeight = candidate.Columns == 2
			and candidate.Height or candidate.Height * 2 + 6
		if controlsWidth > panelWidth - PANEL_MARGIN * 2 then return nil end
		-- The band wins before anything else is even considered.
		if height > BAND_CEILING then return nil end
		-- A short touch band cannot spare the desktop's six-pixel lead-in: two
		-- 44px targets already consume most of a 75px landscape-phone panel. Keep
		-- the side-by-side targets two pixels from the top and let the subtitle
		-- start exactly at their lower edge. The controls and copy remain visually
		-- separate (the controls occupy the right of the speaker row), while the
		-- transparent hitboxes stay fully inside the panel.
		local controlsTop = candidate.OwnBand and 30 or (touch and 2 or 6)
		local speakerWidth = 0
		if not candidate.SpeakerHidden then
			speakerWidth = candidate.OwnBand
				and (panelWidth - TEXT_INSET - PANEL_MARGIN)
				or (panelWidth - TEXT_INSET - PANEL_MARGIN - controlsWidth - 10)
			if speakerWidth < SPEAKER_MINIMUM then return nil end
		end
		-- MUTE/STOP share the top row with the speaker readout, while the actual
		-- briefing keeps the full panel width underneath. Restricting it to the
		-- narrow speaker column made real 58-113 character cues clip on landscape
		-- phones even though the rectangles themselves did not overlap.
		local textTop = math.max(28, controlsTop + controlsHeight + (touch and 0 or 2))
		local textHeight = height - textTop - (touch and 4 or 6)
		-- THE READABILITY GATE. A candidate is refused unless its copy box can
		-- hold the live cue at the face this pass is asking for. That is what
		-- turns "never silently drop to 8px" into a property of the search
		-- instead of a hope: the ladder below tries a wider panel, then a taller
		-- one, then the same search again at the hard floor.
		local copyWidth = panelWidth - TEXT_INSET * 2
		if textHeight < dispatchAudio.copyHeightFor(
			dispatchAudio.fitCopy(), requiredFace, copyWidth) then return nil end
		if textHeight < (touch and 20 or 22) then return nil end
		return {
			ControlsWidth = controlsWidth,
			ControlsHeight = controlsHeight,
			ControlsTop = controlsTop,
			SpeakerWidth = speakerWidth,
			TextWidth = panelWidth - TEXT_INSET * 2,
			TextTop = textTop,
			TextHeight = textHeight,
			Candidate = candidate,
		}
	end

	-- Grow the panel before compromising the layout: a portrait phone has 300+
	-- spare pixels of safe band and no reason to squeeze a subtitle into 22 of
	-- them. A landscape phone has none, and falls through to the second pass.
	local panelHeight, fit
	-- The ceiling actually enforced at the end. It starts as the compact target
	-- and can only ever be raised by the salvage pass, and then only as far as
	-- the MEASURED authored copy needs and never past the band. Nothing else in
	-- this function may write it.
	local effectiveCeiling = BAND_CEILING
	local desiredTextHeight = touch and layout.Portrait and 66 or 40
	-- WIDTH FIRST. Each rung of the ladder gets the full comfortable-fit search
	-- and then the best-effort search; only when a rung yields nothing at all
	-- does the next, wider one get a turn. On the reference device the first
	-- rung -- the 560px compact target -- wins outright and the ladder is never
	-- climbed.
	for _, face in ipairs({dispatchAudio.READABLE_FACE, dispatchAudio.HARD_FACE}) do
	requiredFace = face
	for ladderIndex, width in ipairs(widthLadder) do
		panelWidth = width
		for height = baseHeight, maximumHeight, 6 do
			for _, candidate in ipairs(candidates) do
				local measured = measure(candidate, height)
				if measured and measured.TextHeight >= desiredTextHeight then
					panelHeight, fit = height, measured
					break
				end
			end
			if fit then break end
		end
		if not fit then
			-- Nothing fits comfortably at this width, so take the arrangement
			-- that leaves the most subtitle, breaking ties by the preference
			-- order above.
			local best = touch and math.max(64, math.min(baseHeight, band.Height)) or baseHeight
			-- ...but never taller than the ceiling. `math.max(64, ...)` above is
			-- a readability floor and it used to be the LAST word, so on a band
			-- under 64px it quietly handed back a panel taller than the screen
			-- space it was given. The ceiling is the last word now.
			best = math.min(best, BAND_CEILING)
			for _, candidate in ipairs(candidates) do
				local measured = measure(candidate, best)
				if measured and (not fit or measured.TextHeight > fit.TextHeight) then
					panelHeight, fit = best, measured
				end
			end
			-- ...and the LEAD-IN-LESS arrangements in the same pass, not only as
			-- a last rescue.
			--
			-- WHAT THIS FIXES. The compressed list used to be tried only when
			-- every full-furniture candidate had failed outright, which was the
			-- right order for a panel that could grow. For a panel with a compact
			-- CEILING it inverted the file's own stated priority. Measured on a
			-- 390x844 portrait phone: the side-by-side readouts need 306px and the
			-- panel is 330 wide, so the speaker lead-in cannot sit beside them and
			-- every OwnBand=false candidate was refused; OwnBand=true then won by
			-- dropping the readouts onto their own 30px band, leaving the actual
			-- briefing 22 pixels. The lead-in survived and the sentence did not --
			-- the exact trade the salvage block below says must never be made.
			--
			-- Now both lists compete on the same measure, and because `>` is
			-- strict and `candidates` is iterated first, the lead-in still wins
			-- every tie. Nothing that fits today with its lead-in loses it: at
			-- 956x440 both arrangements yield a 46px copy box and the full one is
			-- kept. At 390x844 the compressed arrangement yields 50px against 22
			-- and takes it.
			for _, candidate in ipairs(compressed) do
				local measured = measure(candidate, best)
				if measured and (not fit or measured.TextHeight > fit.TextHeight) then
					panelHeight, fit = best, measured
				end
			end
		end
		if fit then break end
		-- Exhausted: keep the widest rung for the compressed and salvage passes
		-- below, which are what rescue the very smallest landscape phones.
		if ladderIndex == #widthLadder then panelWidth = width end
	end
	if fit then break end
	end
	if not fit then
		panelHeight = math.min(
			touch and math.max(64, math.min(baseHeight, band.Height)) or baseHeight,
			BAND_CEILING)
	end
	if not fit then
		-- Still nothing, at the full height of the band: drop the lead-in and try
		-- the same arrangements again. This is what rescues a 568x320 landscape
		-- phone -- 380x89 of band -- from the content-sized panel below. With
		-- "> COMMAND CENTER // LIVE" gone, the two 44px readouts take the top row
		-- outright, the copy takes everything under them, and the whole panel
		-- comes to 46 + copy + 4 instead of the 98 that overflowed the band.
		for _, candidate in ipairs(compressed) do
			local measured = measure(candidate, panelHeight)
			if measured and (not fit or measured.TextHeight > fit.TextHeight) then
				fit = measured
			end
		end
	end
	if not fit then
		-- REACHABLE, despite what this comment used to claim. `measure` refuses any
		-- candidate whose subtitle would come out under 20px, so a short landscape
		-- band -- 568x320 is the one that found this -- can reject every candidate
		-- in all three passes above and land here.
		--
		-- It used to hand back `math.max(12, panelHeight - 58)`, and a twelve-pixel
		-- subtitle box is not a layout: a TextLabel does not clip its own overflow,
		-- so two lines of copy simply rendered outside the box, upward, across the
		-- MUTE/STOP row that abuts its top edge.
		--
		-- WHAT SHIPPED BROKEN, and it is the whole of C3: this block sized the
		-- panel to its CONTENT and stopped there -- `panelHeight = math.max(
		-- panelHeight, textTop + minimumText + bottomPad)` -- with no reference
		-- to the band anywhere in it. At 568x320 that is 30 + 44 + 22 + 4 = 100
		-- against a TopBand under 89, so the panel grew straight out of the band
		-- and into the thumbstick's activation region while every existing
		-- assertion (which only compared the panel's children to each other)
		-- stayed green. The panel is now bounded by BAND_CEILING FIRST and the
		-- content is fitted into whatever that leaves.
		--
		-- The order in which things give is fixed and deliberate:
		--   1. the lead-in, already dropped by the pass above;
		--   2. the readouts' own 30px band -- they move up onto the top row;
		--   3. ornamental fallback padding (the touch target itself stays 44px).
		-- The copy never gives, because a briefing whose sentence renders
		-- outside its own panel is the failure this whole block exists to stop.
		--
		-- The copy's floor is MEASURED against the longest AUTHORED cue at the
		-- smallest face on the ladder, never hard-coded: a hard-coded 20 left the
		-- 568x320 band two pixels short of its own copy. It is deliberately NOT
		-- measured against the 1.6x synthetic localisation string -- that string
		-- is headroom for a translation nobody has shipped, and sizing the panel
		-- for it would shrink the readouts on devices that render English fine.
		--
		-- The readouts stay SIDE BY SIDE wherever the width allows. An earlier
		-- version handed back a one-column candidate (which makes the list
		-- vertical) while reserving a single row's HEIGHT for it, so the two
		-- targets stacked into a one-row box and the second one hung outside.
		local bottomPad = touch and 1 or 6
		local textWidth = panelWidth - TEXT_INSET * 2
		local sideBySide = minimumRowWidth * 2 + 10 <= panelWidth - PANEL_MARGIN * 2
		local columns = sideBySide and 2 or 1
		local controlsWidth = sideBySide and (minimumRowWidth * 2 + 10) or minimumRowWidth
		local controlsTop = touch and 0 or 6
		-- The LIVE cue at the hard floor. Sizing this to the 1.6x localisation
		-- probe is what used to make an English briefing pay for a translation
		-- nobody has shipped; the probe is a matrix stress case now.
		local needed = dispatchAudio.copyHeightFor(
			dispatchAudio.fitCopy(), dispatchAudio.HARD_FACE, textWidth)
		local minimumText = math.max(touch and 20 or 22, needed)
		-- Ask for what the content wants, then let the band cut it down.
		-- 6, matching the UIListLayout that stacks them. The other copy of this
		-- arithmetic said 4 and was fixed with it; a stacked pair measured two
		-- pixels short is a pair whose second readout hangs out of its row.
		local rowSpan = function(row)
			return columns == 2 and row or row * 2 + 6
		end
		-- THE ONE PLACE the compact target may be exceeded, and only by exactly
		-- what `minimumText` -- a TextService measurement of the longest AUTHORED
		-- cue at the smallest face on the ladder -- turns out to require. The
		-- band is still the hard bound: a phone too small for both the readouts
		-- and its copy gets a taller panel, never one outside its own band.
		local wanted = controlsTop + rowSpan(minimumRowHeight) + minimumText + bottomPad
		effectiveCeiling = math.min(BAND_LIMIT, math.max(BAND_CEILING, wanted))
		panelHeight = math.clamp(wanted,
			math.min(panelHeight or 0, effectiveCeiling), effectiveCeiling)
		local row = minimumRowHeight
		while row > ROW_HARD_FLOOR
			and controlsTop + rowSpan(row) + minimumText + bottomPad > panelHeight do
			row -= 2
		end
		local controlsHeight = rowSpan(row)
		local textTop = controlsTop + controlsHeight
		fit = {
			ControlsWidth = controlsWidth, ControlsHeight = controlsHeight,
			ControlsTop = controlsTop,
			SpeakerWidth = 0,
			TextWidth = textWidth,
			TextTop = textTop,
			TextHeight = math.max(0, panelHeight - textTop - bottomPad),
			Candidate = {Columns = columns, Width = minimumRowWidth, Height = row,
				OwnBand = false, SpeakerHidden = true},
		}
	end

	-- C_DISPATCH_NO_TALLER_THAN_ITS_COPY_20260831.
	--
	-- Every pass above answers "how tall may this panel be" and then takes that
	-- height. None of them asks whether the copy actually NEEDS it. On a
	-- 338x705 portrait phone the comfortable search finds nothing (its copy box
	-- would have to be 66px and the width does not allow it), so the second pass
	-- takes `best` -- the compact ceiling, 100 -- and measures the arrangement
	-- at exactly that, leaving a 50px copy box for a sentence that occupies 36.
	-- Eight of those pixels are the panel simply being bigger than it has to be
	-- on a phone whose owner asked for the opposite.
	--
	-- So the height is now trimmed to what the arrangement needs, one pixel at a
	-- time, under two conditions that keep it honest:
	--   * `measure` must still accept the arrangement, which is what refuses any
	--     height whose copy box cannot hold the live cue at the required face;
	--   * the FACE the panel finally achieves must not drop. Height buys
	--     legibility here -- the ceiling ladder below reads 16px from a 40px box
	--     and 13 from a 39px one -- and trading a readable sentence for eight
	--     pixels of chrome is the opposite of the trade being made.
	-- Touch only. The desktop composition is authored, sits in a corner with
	-- room to spare, and nobody asked for it to change.
	if touch and fit then
		local function achievedFace(measured)
			local faceCeiling
			if measured.TextHeight <= 32 then faceCeiling = 12
			elseif measured.TextHeight < 40 then faceCeiling = 13
			elseif touch or narrow then faceCeiling = 16
			else faceCeiling = 20 end
			return math.max(dispatchAudio.HARD_FACE, dispatchAudio.faceThatFits(
				faceCeiling, measured.TextWidth, measured.TextHeight))
		end
		local current = measure(fit.Candidate, panelHeight)
		if current then
			local wantedFace = achievedFace(current)
			-- ONE pixel, not two. A 2px step lands on whichever parity it
			-- started from, so a panel whose copy needed 88 stopped at 90 and
			-- was two pixels bigger than it had any reason to be -- on the two
			-- tablets, where the search happens to start even.
			local trimmed = panelHeight
			while trimmed - 1 > 0 do
				local smaller = measure(fit.Candidate, trimmed - 1)
				if not smaller or achievedFace(smaller) < wantedFace then break end
				trimmed -= 1
				fit = smaller
			end
			panelHeight = trimmed
		end
	end

	-- THE BAND WINS, ALWAYS -- stated once, at the end, where nothing can get
	-- past it. Every pass above already respects BAND_CEILING, so this is the
	-- guarantee rather than the mechanism; the subtitle box is re-derived from
	-- the clamped height so a clamp can never leave the copy hanging outside the
	-- panel it was measured against.
	panelHeight = math.min(panelHeight, effectiveCeiling)
	fit.TextHeight = math.max(0,
		math.min(fit.TextHeight, panelHeight - fit.TextTop - (touch and 1 or 6)))
	-- The lead-in exists only where the arrangement actually reserved room for
	-- it. Left Visible at zero width it is an invisible zero-size label that
	-- every rect-walking pass still dutifully reports.
	subtitleSpeaker.Visible = fit.SpeakerWidth >= SPEAKER_MINIMUM
	-- Which rung of the ladder this viewport landed on, published so a
	-- regression can assert the SHAPE and not merely the absence of an overlap:
	-- "full" keeps "> COMMAND CENTER // LIVE", "compact" has dropped it to fit
	-- the band. Every desktop and every portrait touch size is "full".
	subtitleFrame:SetAttribute("BriefingFitMode",
		subtitleSpeaker.Visible and "full" or "compact")
	subtitleFrame:SetAttribute("BriefingBandCeiling", effectiveCeiling)
	-- Published so a regression can assert the COMPACT CONTRACT itself and not
	-- merely the absence of an overlap: what the compact target was, and whether
	-- this viewport had to leave it (and in which axis) to fit its own copy.
	subtitleFrame:SetAttribute("BriefingCompactCeiling", COMPACT_CEILING)
	subtitleFrame:SetAttribute("BriefingCompactWidth", compactWidth)
	subtitleFrame:SetAttribute("BriefingWidthRung",
		table.find(widthLadder, panelWidth) or #widthLadder)

	if touch then
		subtitleFrame.AnchorPoint = Vector2.new(0, 0)
		local captionTop = band.Top
		local function placeBelowHud(guiName, panelName)
			if dispatchAudio.voiceEnabled then return end
			local hudGui = player.PlayerGui:FindFirstChild(guiName)
			local hud = hudGui and hudGui:FindFirstChild(panelName)
			if not (hudGui and hudGui.Enabled and hud and hud.Visible) then return end
			local pos, size = hud.AbsolutePosition, hud.AbsoluteSize
			if band.Left < pos.X + size.X and band.Left + panelWidth > pos.X
				and captionTop < pos.Y + size.Y and captionTop + panelHeight > pos.Y then
				local nextTop = pos.Y + size.Y + 8
				if nextTop + panelHeight <= band.Bottom then captionTop = nextTop end
			end
		end
		placeBelowHud("PuzzleGui", "Level1Objectives")
		placeBelowHud("Level2ObjectiveGui", "Level2ObjectivePanel")
		placeBelowHud("Level3ReaderGui", "ReaderPanel")
		subtitleFrame.Position = UIDevice.LocalPosition(guideGui, band.Left, captionTop)
		if player:GetAttribute("Level3_Hiding") == true then
			-- Hiding owns the top strip. The character is anchored, so captions
			-- can use the bottom safe area while the warning and exit stay clear.
			subtitleFrame.Position = UIDevice.LocalPosition(guideGui, band.Left,
				math.max(band.Top, layout.Safe.Bottom - 42 - panelHeight))
		end
	else
		subtitleFrame.AnchorPoint = Vector2.new(0.5, 1)
		-- Level 1–2 objective cards occupy the lower-right on desktop. The
		-- original dispatch hid them; passive captions sit just above their row.
		local bottomOffset = narrow and 96 or (dispatchAudio.voiceEnabled and 64 or 120)
		local puzzleGui = player.PlayerGui:FindFirstChild("PuzzleGui")
		local message = puzzleGui and puzzleGui:FindFirstChild("PuzzleMessage")
		if puzzleGui and puzzleGui.Enabled and message and message.Visible then
			local pos, size = message.AbsolutePosition, message.AbsoluteSize
			local captionLeft = (layout.Safe.Left + layout.Safe.Right - panelWidth) / 2
			local captionBottom = layout.Safe.Bottom - bottomOffset
			if captionLeft < pos.X + size.X and captionLeft + panelWidth > pos.X
				and captionBottom - panelHeight < pos.Y + size.Y
				and captionBottom > pos.Y then
				bottomOffset = math.max(bottomOffset,
					UIDevice.BottomOffsetFor(guideGui, pos.Y - 8))
			end
		end
		subtitleFrame.Position = UDim2.new(0.5, 0, 1, -bottomOffset)
	end
	subtitleFrame.Size = UDim2.fromOffset(panelWidth, panelHeight)
	-- The constraint used to clamp height to 118 and width to 860 behind the
	-- layout's back, which is how a panel could end up a different size from the
	-- one every child was measured against. It now states the same numbers.
	subtitleConstraint.MinSize = Vector2.new(panelWidth, panelHeight)
	subtitleConstraint.MaxSize = Vector2.new(panelWidth, panelHeight)

	local rowWidth = fit.Candidate.Width
	if readerPassiveLane then
		-- The hidden MUTE control must not reserve the only safe touch gap.
		-- The visible SKIP target keeps its 44px floor and stays wholly right
		-- of the thumbstick and left of the reader on 568x320 and 705x338.
		rowWidth = math.min(rowWidth, math.floor(
			band.Left + panelWidth - 4
			- (layout.Zones.Thumbstick.Right + 1)))
	end
	local rowHeight = fit.Candidate.Height
	dispatchAudio.button.Size = UDim2.fromOffset(rowWidth, rowHeight)
	dispatchAudio.stopButton.Size = UDim2.fromOffset(rowWidth, rowHeight)
	-- 12, not 14. The readouts keep their full 44px transparent hit rectangle;
	-- only the GLYPHS get smaller, which is what makes a 148px row hold
	-- "DISPATCH OFFLINE" and the whole panel read as a caption rather than a
	-- menu. Desktop is unchanged at 13.
	dispatchAudio.button.TextSize = touch and 12 or 13
	dispatchAudio.stopButton.TextSize = touch and 12 or 13

	-- Subtler chrome on a handheld: the panel is a radio caption over the game,
	-- not a dialog. A lighter fill and a fainter rule, and the same numbers on
	-- desktop as before.
	subtitleFrame.BackgroundTransparency = readerPassiveLane and 0.65
		or (touch and 0.30 or 0.18)
	local panelRule = subtitleFrame:FindFirstChildOfClass("UIStroke")
	if panelRule then
		panelRule.Transparency = touch and 0.55 or 0.38
		panelRule.Thickness = touch and 1 or 1.5
	end
	subtitleSpeaker.TextSize = touch and 11 or 13

	dispatchAudio.layout.FillDirection = fit.Candidate.Columns == 2
		and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
	dispatchAudio.layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	dispatchAudio.controls.AnchorPoint = Vector2.new(1, 0)
	dispatchAudio.controls.Position = UDim2.new(1,
		readerPassiveLane and -4 or -PANEL_MARGIN, 0, fit.ControlsTop)
	dispatchAudio.controls.Size = UDim2.fromOffset(fit.ControlsWidth, fit.ControlsHeight)

	subtitleSpeaker.Position = UDim2.fromOffset(TEXT_INSET, 8)
	subtitleSpeaker.Size = UDim2.fromOffset(fit.SpeakerWidth, 20)
	subtitleText.Position = UDim2.fromOffset(TEXT_INSET, fit.TextTop)
	subtitleText.Size = UDim2.fromOffset(fit.TextWidth, fit.TextHeight)
	-- A short strip gets a smaller face rather than a clipped sentence -- and
	-- whether it IS clipped is now measured, not inferred from the box's height
	-- class. The ladder below used to end here: a 42px box on a portrait phone
	-- took the 16px face because the box was "tall enough", and the longest
	-- authored cue needs 48px at that face. Nothing clipped it; the third line
	-- rendered outside the box, over the MUTE/STOP row that abuts its top edge.
	local ceiling
	if fit.TextHeight <= 32 then
		ceiling = 12
	elseif fit.TextHeight < 40 then
		ceiling = 13
	elseif touch or narrow then
		ceiling = 16
	else
		ceiling = 20
	end
	subtitleText.TextWrapped = true
	subtitleText.TextSize = math.max(dispatchAudio.HARD_FACE,
		dispatchAudio.faceThatFits(ceiling, fit.TextWidth, fit.TextHeight))
	-- Published so the matrix can assert the CONTRACT -- which face was
	-- required and which was achieved -- rather than only the pixels.
	subtitleFrame:SetAttribute("BriefingRequiredFace", requiredFace)
	subtitleFrame:SetAttribute("BriefingFace", subtitleText.TextSize)

	-- The BINDING GLYPHS live in dispatchAudio.refresh, and until now nothing
	-- re-ran it when the form factor changed. UIDevice.Binding returns "" the
	-- moment a touchscreen exists, so "[M]  MUTE DISPATCH" was correct when the
	-- captions were first built and stayed on screen afterwards -- a key glyph
	-- on a phone, naming a key the device has not got. This is the one signal
	-- that fires on a form-factor change, so the captions are rebuilt from it.
	-- refresh() never calls back into the layout, so there is no cycle here.
	-- Preserve the real stop/mute controls without restoring a subtitle plate.
	dispatchAudio.controls.AnchorPoint = Vector2.new(0.5, 1)
	dispatchAudio.controls.Position = UIDevice.LocalPosition(guideGui,
		(layout.Safe.Left + layout.Safe.Right) / 2, layout.Safe.Bottom - 156)
	dispatchAudio.refresh()
end

dispatchAudio.relayoutForCaption = updateLevelOneGuideLayout

-- Studio-only relayout seam. The regression harness sets a stress cue by
-- writing the subtitle label directly, and the panel is SIZED FOR THE COPY --
-- so without a way to say "that changed", the matrix measured a box fitted to
-- the previous sentence and reported the new one as overflowing it.
if RunService:IsStudio() then
	local relayout = Instance.new("BindableFunction")
	relayout.Name = "UIRegressionRelayoutGuide"
	relayout.OnInvoke = function()
		updateLevelOneGuideLayout()
		return subtitleText.TextSize
	end
	relayout.Parent = guideGui
end

UIDevice.Changed:Connect(updateLevelOneGuideLayout)
player:GetAttributeChangedSignal("Level3_Hiding"):Connect(updateLevelOneGuideLayout)
local viewportConnection = nil
local function connectGuideViewport()
	if viewportConnection then viewportConnection:Disconnect() end
	local camera = workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateLevelOneGuideLayout)
	end
	updateLevelOneGuideLayout()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(connectGuideViewport)
connectGuideViewport()

local function playLevelOneBriefing()
	briefingRun += 1
	local run = briefingRun
	local speechAt = os.clock() + LEVEL_ONE_BRIEFING_DELAY
	player:SetAttribute("LevelOneBriefingActive", false)
	setSubtitle(nil)
	do return end -- BRIEFINGS_OFF_20261004 (owner): no Command Center briefing, voice or subtitle, in the lobby or in any level; the objectives are up from the start

	task.spawn(function()
		if dispatchAudio.voiceEnabled then dispatchAudio.awaitPreference() end
		preloadLevelOneBriefing()

		-- Asset 73198577463663 is exactly one second long. Start it early enough
		-- that the radio opens immediately before the spoken briefing.
		local radioLength = levelOneRadioCue.TimeLength > 0.05 and levelOneRadioCue.TimeLength or 1
		local radioAt = speechAt - radioLength
		local remaining = radioAt - os.clock()
		if remaining > 0 then task.wait(remaining) end
		if run ~= briefingRun or not isLevelOneParticipant() then return end

		setMsg("")
		dispatchAudio.beginTransmission("level1", run, function()
			if run ~= briefingRun then return end
			cancelLevelOneBriefing(false)
			if isLevelOneParticipant() then
			end
		end)
		levelOneRadioCue:Stop()
		levelOneRadioCue.TimePosition = 0
		local radioPlayed = pcall(function() levelOneRadioCue:Play() end)
		if radioPlayed then
			local radioStarted = levelOneRadioCue.IsPlaying
			local radioStartDeadline = os.clock() + 0.5
			local radioDeadline = os.clock() + radioLength + 1
			while run == briefingRun and isLevelOneParticipant() and os.clock() < radioDeadline do
				if levelOneRadioCue.IsPlaying then
					radioStarted = true
				elseif radioStarted or os.clock() >= radioStartDeadline then
					break
				end
				RunService.Heartbeat:Wait()
			end
		else
			-- If the cue cannot play, preserve the original speech timing.
			local waitForSpeech = speechAt - os.clock()
			if waitForSpeech > 0 then task.wait(waitForSpeech) end
		end
		if run ~= briefingRun or not isLevelOneParticipant() then
			dispatchAudio.finishTransmission("level1", run)
			return
		end

		levelOneBriefingSound:Stop()
		levelOneBriefingSound.TimePosition = 0
		levelOneBriefingSound.Volume = 1
		player:SetAttribute("LevelOneBriefingActive", dispatchAudio.voiceEnabled)
		local played = true
		if dispatchAudio.voiceEnabled then
			played = pcall(function() levelOneBriefingSound:Play() end)
		end
		if not played then
			player:SetAttribute("LevelOneBriefingActive", false)
			dispatchAudio.finishTransmission("level1", run)
			if run == briefingRun and isLevelOneParticipant() then
			end
			return
		end

		local currentText = nil
		local playbackStarted = levelOneBriefingSound.IsPlaying
		local playbackStartDeadline = os.clock() + 4
		local deadline = os.clock() + 52
		local captionClock = dispatchAudio.newCaptionClock()
		while run == briefingRun and isLevelOneParticipant()
			and (not dispatchAudio.voiceEnabled or os.clock() < deadline) do
			local position = dispatchAudio.captionPosition(captionClock, levelOneBriefingSound)
			-- Retire the old timed-lever sentence without replaying outdated rules.
			-- Keep its corrected caption visible; the remaining recording is unchanged.
			if dispatchAudio.voiceEnabled then
				levelOneBriefingSound.Volume = (position >= 20.78 and position < 25.86) and 0 or 1
			end
			local cueText = nil
			for _, cue in ipairs(briefingCues) do
				if position >= cue[1] and position < cue[2] then
					cueText = cue[3]
					break
				end
			end
			if cueText ~= currentText then
				currentText = cueText
				setSubtitle(cueText)
			end
			if not dispatchAudio.voiceEnabled then
				if position >= briefingCues[#briefingCues][2] then break end
			elseif levelOneBriefingSound.IsPlaying then
				playbackStarted = true
			elseif playbackStarted or os.clock() >= playbackStartDeadline then
				break
			end
			RunService.Heartbeat:Wait()
		end

		player:SetAttribute("LevelOneBriefingActive", false)
		dispatchAudio.finishTransmission("level1", run)
		if run ~= briefingRun then return end
		setSubtitle(nil)
		if isLevelOneParticipant() then
		end
	end)
end

function levelThreeBriefing.resetInterference()
	levelThreeBriefing.pitch.Octave = 1
	levelThreeBriefing.sound.Volume = 1
	levelThreeBriefing.sound.PlaybackSpeed = 1
end

function levelThreeBriefing.updateInterference(position)
	local octave = 1
	local volume = 1
	for _, interference in ipairs(levelThreeBriefing.interference) do
		if position >= interference[1] and position < interference[2] then
			if interference[3] == "cut" then
				volume = 0.03
			else
				local phase = math.floor((position - interference[1]) / 0.055)
				octave = levelThreeBriefing.jitterOctaves[(phase % #levelThreeBriefing.jitterOctaves) + 1]
			end
			break
		end
	end
	if math.abs(levelThreeBriefing.pitch.Octave - octave) > 0.001 then
		levelThreeBriefing.pitch.Octave = octave
	end
	if math.abs(levelThreeBriefing.sound.Volume - volume) > 0.001 then
		levelThreeBriefing.sound.Volume = volume
	end
end

function levelThreeBriefing.cancel()
	levelThreeBriefing.run += 1
	dispatchAudio.clearTransmission("level3")
	levelThreeBriefing.radio:Stop()
	levelThreeBriefing.sound:Stop()
	levelThreeBriefing.resetInterference()
	player:SetAttribute("LevelThreeBriefingActive", false)
	setSubtitle(nil)
end

function levelThreeBriefing.isParticipant()
	return workspace:GetAttribute("SelectedLevel") == 3
		and workspace:GetAttribute("RoundActive") == true
		and player:GetAttribute("InRound") == true
		and player:GetAttribute("Escaped") ~= true
		and not dead
end

function levelThreeBriefing.preload()
	if levelThreeBriefing.preloaded then return true end
	local ok = pcall(function()
		ContentProvider:PreloadAsync(dispatchAudio.voiceEnabled
			and {levelThreeBriefing.radio, levelThreeBriefing.sound} or {levelThreeBriefing.radio})
	end)
	levelThreeBriefing.preloaded = ok
		and levelThreeBriefing.radio.IsLoaded
		and (not dispatchAudio.voiceEnabled or levelThreeBriefing.sound.IsLoaded)
	return levelThreeBriefing.preloaded
end

task.spawn(levelThreeBriefing.preload)

function levelThreeBriefing.play()
	levelThreeBriefing.run += 1
	local run = levelThreeBriefing.run
	local speechAt = os.clock() + levelThreeBriefing.delay
	player:SetAttribute("LevelThreeBriefingActive", false)
	levelThreeBriefing.resetInterference()
	setSubtitle(nil)
	do return end -- BRIEFINGS_OFF_20261004 (owner): no Command Center briefing, voice or subtitle, in the lobby or in any level

	task.spawn(function()
		if dispatchAudio.voiceEnabled then dispatchAudio.awaitPreference() end
		levelThreeBriefing.preload()

		local radioLength = levelThreeBriefing.radio.TimeLength > 0.05
			and levelThreeBriefing.radio.TimeLength or 2
		local remaining = speechAt - radioLength - os.clock()
		if remaining > 0 then task.wait(remaining) end
		if run ~= levelThreeBriefing.run or not levelThreeBriefing.isParticipant() then return end

		setMsg("")
		dispatchAudio.beginTransmission("level3", run, function()
			if run ~= levelThreeBriefing.run then return end
			levelThreeBriefing.cancel()
		end)
		levelThreeBriefing.radio:Stop()
		levelThreeBriefing.radio.TimePosition = 0
		local radioPlayed = pcall(function() levelThreeBriefing.radio:Play() end)
		if radioPlayed then
			local radioStarted = levelThreeBriefing.radio.IsPlaying
			local radioStartDeadline = os.clock() + 0.5
			local radioDeadline = os.clock() + radioLength + 1
			while run == levelThreeBriefing.run
				and levelThreeBriefing.isParticipant()
				and os.clock() < radioDeadline do
				if levelThreeBriefing.radio.IsPlaying then
					radioStarted = true
				elseif radioStarted or os.clock() >= radioStartDeadline then
					break
				end
				RunService.Heartbeat:Wait()
			end
		else
			local waitForSpeech = speechAt - os.clock()
			if waitForSpeech > 0 then task.wait(waitForSpeech) end
		end
		if run ~= levelThreeBriefing.run or not levelThreeBriefing.isParticipant() then
			dispatchAudio.finishTransmission("level3", run)
			return
		end

		levelThreeBriefing.sound:Stop()
		levelThreeBriefing.sound.TimePosition = 0
		levelThreeBriefing.resetInterference()
		player:SetAttribute("LevelThreeBriefingActive", dispatchAudio.voiceEnabled)
		local played = true
		if dispatchAudio.voiceEnabled then
			played = pcall(function() levelThreeBriefing.sound:Play() end)
		end
		if not played then
			player:SetAttribute("LevelThreeBriefingActive", false)
			levelThreeBriefing.resetInterference()
			dispatchAudio.finishTransmission("level3", run)
			return
		end

		local currentText = nil
		local playbackStarted = levelThreeBriefing.sound.IsPlaying
		local playbackStartDeadline = os.clock() + 4
		local deadline = os.clock() + 60
		local captionClock = dispatchAudio.newCaptionClock()
		while run == levelThreeBriefing.run
			and levelThreeBriefing.isParticipant()
			and (not dispatchAudio.voiceEnabled or os.clock() < deadline) do
			local position = dispatchAudio.captionPosition(captionClock, levelThreeBriefing.sound)
			if dispatchAudio.voiceEnabled then
				levelThreeBriefing.updateInterference(position)
			end
			local cueText = nil
			for _, cue in ipairs(levelThreeBriefing.cues) do
				if position >= cue[1] and position < cue[2] then
					cueText = cue[3]
					break
				end
			end
			if cueText ~= currentText then
				currentText = cueText
				setSubtitle(cueText)
			end
			if not dispatchAudio.voiceEnabled then
				if position >= levelThreeBriefing.cues[#levelThreeBriefing.cues][2] then break end
			elseif levelThreeBriefing.sound.IsPlaying then
				playbackStarted = true
			elseif playbackStarted or os.clock() >= playbackStartDeadline then
				break
			end
			RunService.Heartbeat:Wait()
		end

		player:SetAttribute("LevelThreeBriefingActive", false)
		levelThreeBriefing.resetInterference()
		dispatchAudio.finishTransmission("level3", run)
		if run ~= levelThreeBriefing.run then return end
		setSubtitle(nil)
	end)
end

local function cancelAllCommandBriefings(hideLevelOneObjectives)
	lobbyBriefing.cancel()
	cancelLevelOneBriefing(hideLevelOneObjectives)
	levelThreeBriefing.cancel()
end

-- Studio-only hook for the UI regression matrix. A live transmission re-shows
-- the subtitle panel on every subtitle cue, so a layout scenario that needs the
-- panel DOWN cannot just set Visible = false and scan: it has to end the
-- transmission, exactly the way the STOP readout does. Without this the matrix
-- reports the briefing panel colliding with whatever it was asked to measure,
-- which is a race in the harness rather than a defect in the HUD.
if RunService:IsStudio() then
	player:GetAttributeChangedSignal("UIRegressionSilenceDispatch"):Connect(function()
		if player:GetAttribute("UIRegressionSilenceDispatch") ~= true then return end
		dispatchAudio.requestStop()
		cancelAllCommandBriefings(true)
		player:SetAttribute("UIRegressionSilenceDispatch", nil)
	end)
end

function levelThreeBriefing.validate()
	if not levelThreeBriefing.isParticipant() then
		levelThreeBriefing.cancel()
	end
end
workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(levelThreeBriefing.validate)
workspace:GetAttributeChangedSignal("RoundActive"):Connect(levelThreeBriefing.validate)
player:GetAttributeChangedSignal("InRound"):Connect(levelThreeBriefing.validate)
player:GetAttributeChangedSignal("Escaped"):Connect(levelThreeBriefing.validate)

local function validateLevelOneGuide()
	if not isLevelOneParticipant() then
		cancelLevelOneBriefing(true)
	end
end
workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(validateLevelOneGuide)
player:GetAttributeChangedSignal("InRound"):Connect(validateLevelOneGuide)
player:GetAttributeChangedSignal("Escaped"):Connect(validateLevelOneGuide)

-- LEVEL2_EXIT_TRANSITION_20260828
-- The exit ride suppresses the escaped-player spectate view while it is live.
-- When it ends WITHOUT a level transition — an emergency recovery to the sealed
-- chamber, or the round closing out around the rider — fall through to the
-- normal view rather than leaving them staring down a tube with no UI.
player:GetAttributeChangedSignal("Level2_ExitTransition"):Connect(function()
	if player:GetAttribute("Level2_ExitTransition") == true then return end
	if player:GetAttribute("InRound") == true and player:GetAttribute("Escaped") == true then
		startSpectating()
	end
end)

-- Elevator cabin effects keep their existing timing and restore behavior.
-- The player retains camera control throughout loading, the ride and its stop.
local SHAKE_BIND = "UnstableElevatorCamera"
local SHAKE_DURATION = 10
local SETTLE_DURATION = 1
local shakeSequence = 0
local shakeScheduled = false

local function scheduleElevatorShake()
	if shakeScheduled then return end
	shakeScheduled = true
	shakeSequence += 1
	local token = shakeSequence

	task.delay(1, function()
		if token ~= shakeSequence then return end
		local started = os.clock()
		local elevator = workspace:FindFirstChild("Elevator")
		local cabinLights = {}
		local doorBases = {}

		if elevator then
			for _, item in ipairs(elevator:GetDescendants()) do
				if item:IsA("PointLight") then
					cabinLights[#cabinLights + 1] = {
						light = item, brightness = item.Brightness, range = item.Range,
						enabled = item.Enabled, panel = item.Parent,
						panelColor = item.Parent:IsA("BasePart") and item.Parent.Color or nil,
					}
				end
			end
			for _, name in ipairs({ "DoorL", "DoorR" }) do
				local door = elevator:FindFirstChild(name)
				if door and door:IsA("BasePart") then
					doorBases[#doorBases + 1] = { part = door, cf = door.CFrame }
				end
			end
		end

		local restored = false
		local function restoreCabin()
			if restored then return end
			restored = true
			for _, data in ipairs(cabinLights) do
				if data.light.Parent then
					data.light.Brightness = data.brightness
					data.light.Range = data.range
					data.light.Enabled = data.enabled
					if data.panelColor and data.panel:IsA("BasePart") then data.panel.Color = data.panelColor end
				end
			end
			for _, data in ipairs(doorBases) do
				if data.part.Parent then data.part.CFrame = data.cf end
			end
		end

		RunService:UnbindFromRenderStep(SHAKE_BIND)
		RunService:BindToRenderStep(SHAKE_BIND, Enum.RenderPriority.Camera.Value + 2, function()
			local elapsed = os.clock() - started
			if elapsed >= SHAKE_DURATION + SETTLE_DURATION or token ~= shakeSequence then
				restoreCabin()
				RunService:UnbindFromRenderStep(SHAKE_BIND)
				return
			end

			local settling = elapsed >= SHAKE_DURATION
			local settleProgress = math.clamp(elapsed - SHAKE_DURATION, 0, SETTLE_DURATION) / SETTLE_DURATION
			local fade = math.max(1 - elapsed / SHAKE_DURATION, 0) ^ 1.35
			local t = os.clock()

			-- Cabin lamp follows the machinery load, with two brief early brownouts.
			local brownout = (elapsed > 1.15 and elapsed < 1.28)
				or (elapsed > 2.45 and elapsed < 2.58)
			local lampWave = 1 + math.noise(t * 3.5, 40) * 0.14 * fade
			if settling then
				-- Dim on impact, then stabilize cleanly through the one-second pause.
				local smooth = settleProgress * settleProgress * (3 - 2 * settleProgress)
				lampWave = 0.42 + 0.58 * smooth
				brownout = false
			end
			for _, data in ipairs(cabinLights) do
				if data.light.Parent then
					data.light.Enabled = data.enabled
					data.light.Brightness = data.brightness * (brownout and 0.12 or lampWave)
					data.light.Range = data.range * (brownout and 0.72 or (1 + 0.03 * fade))
					if data.panelColor and data.panel:IsA("BasePart") then
						data.panel.Color = brownout and Color3.fromRGB(75, 72, 64)
							or data.panelColor:Lerp(Color3.fromRGB(255, 244, 220), 0.08 * fade)
					end
				end
			end

			-- Tiny local door rattle; the original CFrames are restored exactly.
			for index, data in ipairs(doorBases) do
				if data.part.Parent then
					if settling then
						data.part.CFrame = data.cf
					else
						local direction = index == 1 and -1 or 1
						local dx = math.noise(t * 14, index * 7) * 0.025 * fade
						local dy = math.noise(index * 9, t * 12) * 0.018 * fade
						local dz = direction * math.noise(t * 10, index * 13) * 0.035 * fade
						data.part.CFrame = data.cf * CFrame.new(dx, dy, dz)
					end
				end
			end
		end)
	end)
end
-- dead is declared with the player state above so the ending and spectate UI share it.

remote.OnClientEvent:Connect(function(ev, a, b, c, d, e, f)
	if ev == "lobby" then
		entryState.Active = false
		entryState.KnownLevel = nil
		entryState.Token = nil
		loadingRun += 1
		-- GameManager also uses "lobby" for queue resets. Preserve a welcome
		-- transmission already in progress; its dedicated event is once-only.
		if not lobbyBriefing.active and not lobbyBriefing.pending then
			cancelAllCommandBriefings(true)
		end
		hideRoundEnding(true)
		stopSpectating()
		dead = false
		loadingFrame.Visible = false
		queueShade.Visible = false
		queueStation = nil
		queueSubmitting = false
		entryState.RenderError() -- redisplay without extending the original deadline

	elseif ev == "lobbybriefing" then
		lobbyBriefing.playOnce()

	elseif ev == "queuehost" then
		loadingFrame.Visible = false
		queueStation = tonumber(a)
		queueSizeValue = math.clamp(math.floor(tonumber(b) or 6), 1, 6)
		queuePrivacyValue = c == "friends" and "friends" or "public"
		queueSubmitting = false
		queueShade:SetAttribute("QueueLaunchModes", (d == "trial,preview" or d == "trial" or d == "preview") and d or nil)
		refreshQueuePanel()
		queueShade.Visible = true
		setMsg("")

	elseif ev == "queueconfigured" then
		queueShade.Visible = false
		queueSubmitting = false
		local maximum = math.clamp(math.floor(tonumber(a) or 6), 1, 6)
		local privacyText = b == "friends" and "FRIENDS ONLY" or "PUBLIC"
		local stationNumber = tonumber(c)
		local stationText = stationNumber and ("STATION " .. stationNumber .. "  •  ") or ""
		setMsg(stationText .. "PARTY OPEN  •  MAX " .. maximum .. "  •  " .. privacyText, Color3.fromRGB(120, 255, 175))
		label.Size = UDim2.new(0, 700, 0, 68)

	elseif ev == "queueconfigclosed" then
		queueShade.Visible = false
		queueStation = nil
		queueSubmitting = false
		setMsg("")

	elseif ev == "queuewaitinghost" then
		queueShade.Visible = false
		local stationNumber = tonumber(a)
		setMsg((stationNumber and ("STATION " .. stationNumber .. "  •  ") or "") .. "HOST CHOOSING PARTY SETTINGS", Color3.fromRGB(220, 210, 155))
		label.Size = UDim2.new(0, 700, 0, 68)

	elseif ev == "queueaccessdenied" then
		queueShade.Visible = false
		queueStation = nil
		queueSubmitting = false
		setMsg(tostring(b), Color3.fromRGB(255, 205, 110))
		label.Size = UDim2.new(0, 700, 0, 92)

	elseif ev == "queueprivate" then
		queueShade.Visible = false
		local stationNumber = tonumber(a)
		local hostName = tostring(b or "HOST")
		setMsg((stationNumber and ("STATION " .. stationNumber .. "  •  ") or "") .. "FRIENDS ONLY" .. string.char(10) .. "ONLY FRIENDS OF " .. string.upper(hostName) .. " CAN JOIN", Color3.fromRGB(255, 205, 110))
		label.Size = UDim2.new(0, 700, 0, 92)

	elseif ev == "queuefull" then
		queueShade.Visible = false
		local stationNumber = tonumber(a)
		local maximum = math.clamp(math.floor(tonumber(b) or 6), 1, 6)
		setMsg((stationNumber and ("STATION " .. stationNumber .. "  •  ") or "") .. "PARTY FULL  •  " .. maximum .. "/" .. maximum, Color3.fromRGB(255, 205, 110))
		label.Size = UDim2.new(0, 700, 0, 68)

	elseif ev == "lobbycountdown" then
		loadingFrame.Visible = false
		local count = b or 0
		local stationNumber = tonumber(c)
		local maximum = math.clamp(math.floor(tonumber(d) or 6), 1, 6)
		local privacyText = e == "friends" and "FRIENDS ONLY" or "PUBLIC"
		local stationText = stationNumber and ("STATION " .. stationNumber .. "  •  ") or ""
		local modeText = f == "trial" and "  •  TRIAL ROUND" or (f == "preview" and "  •  MAP PREVIEW" or "")
		setMsg(stationText .. "GAME BEGINS IN " .. tostring(a) .. string.char(10)
			.. count .. "/" .. maximum .. " READY  •  " .. privacyText .. modeText, Color3.fromRGB(120, 255, 175))
		label.Size = UDim2.new(0, 700, 0, 92)

	elseif ev == "lobbycancel" then
		loadingFrame.Visible = false
		queueShade.Visible = false
		queueStation = nil
		queueSubmitting = false
		setMsg("COUNTDOWN CANCELLED — ENTER THE SQUARE TO TRY AGAIN", Color3.fromRGB(210, 230, 225))

	elseif ev == "spectating" then
		loadingFrame.Visible = false
		queueShade.Visible = false
		setMsg("GAME IN PROGRESS — WAIT FOR THE NEXT GROUP", Color3.fromRGB(255, 215, 120))

	elseif ev == "loadinggame" then
		local announcedLevel = (type(a) == "number" or type(a) == "string") and tonumber(a) or nil
		if not announcedLevel or announcedLevel % 1 ~= 0 or announcedLevel < 1 or announcedLevel > 6 then
			announcedLevel = nil
			-- A late untyped bootstrap cannot reset a confirmed entry or its token.
			if entryState.Active and entryState.KnownLevel ~= nil then return end
		end
		completion.roster = {}
		completion.resultData = nil
		entryState.Active = true
		entryState.KnownLevel = announcedLevel
		entryState.Token = nil
		entryState.ClearError(true)
		serverReadyForEntry = false
		cancelAllCommandBriefings(true)
		elevatorBriefingStarted = false
		levelThreeBriefing.started = false
		-- Re-arm the elevator shake for Studio-fallback servers that host
		-- several rounds in a row ("start" only fires after the ride).
		shakeScheduled = false
		hideRoundEnding(true)
		stopSpectating()
		dead = false
		queueShade.Visible = false
		queueStation = nil
		queueSubmitting = false
		setMsg("")
		-- SelectedLevel and LoadingLevel can still describe the previous round during arrival.
		-- Hold the opaque cover without its old card until the server confirms this entry's level.
		if announcedLevel then applyLoadingPalette(announcedLevel) end
		player:SetAttribute("LoadingLevel", announcedLevel)
		local card = dispatchAudio.loadingCards.root
		if card then card.Visible = announcedLevel ~= nil end
		loadingClock = 0
		loadingBaseText = "PREPARING YOUR PARTY"
		-- Paint the status line BEFORE uncovering. RenderStepped only refreshes
		-- it while the frame is visible, so revealing first shows one frame of
		-- the PREVIOUS round's line.
		loadingStatus.Text = loadingBaseText
		loadingFrame.Visible = true
		startLoadingSequence()

	elseif ev == "entryprepare" then
		if entryState.Active and type(a) == "table" then
			entryState.Token = a.Token
		end

	elseif ev == "entryreleased" then
		if entryState.Active and type(a) == "table" and a.Token == entryState.Token then
			entryState.Active = false
			entryState.KnownLevel = nil
			loadingRun += 1
			loadingSequenceFinished = true
			serverReadyForEntry = true
			finishLoadingWhenReady()
		end

	elseif ev == "entrycancel" then
		if type(a) == "table" and a.Token == entryState.Token then
			entryState.Active = false
			entryState.KnownLevel = nil
			entryState.Token = nil
			loadingRun += 1
		end

	elseif ev == "loadfailed" then
		if not entryState.ErrorArmed then return end
		entryState.Active = false
		entryState.KnownLevel = nil
		entryState.Token = nil
		loadingRun += 1
		cancelAllCommandBriefings(true)
		loadingFrame.Visible = false
		entryState.ShowError(a)

	elseif ev == "poolaccess" then
		dead = false
		if player:GetAttribute("InRound") == true then
			completion.Hud.Feed({Kind = "SYSTEM", Detail = "POOL ACCESS READY", Key = "poolaccess"})
		end
		-- The shared entry barrier releases this cover for the whole party.

	elseif ev == "level3access" then
		if not entryState.Active then
			loadingSequenceFinished = true
			serverReadyForEntry = true
			finishLoadingWhenReady()
		end
		dead = false
		if player:GetAttribute("InRound") == true then
			completion.Hud.Feed({Kind = "SYSTEM", Detail = "SERVICE LEVEL ACCESS READY", Key = "level3access"})
		end

	elseif ev == "elevator" then
		if not entryState.Active then
			loadingSequenceFinished = true
			serverReadyForEntry = true
			finishLoadingWhenReady()
		end
		scheduleElevatorShake()
		dead = false
		if not elevatorBriefingStarted then
			elevatorBriefingStarted = true
			playLevelOneBriefing()
		end

	elseif ev == "start" then
		completion.roster = {}
		completion.resultData = nil
		entryState.Active = false
		entryState.KnownLevel = nil
		entryState.Token = nil
		entryState.ClearError(false)
		loadingRun += 1
		loadingSequenceFinished = true
		hideRoundEnding(true)
		stopSpectating()
		shakeScheduled = false
		serverReadyForEntry = true
		finishLoadingWhenReady()
		dead = false
		setMsg("")
		local selectedLevel = workspace:GetAttribute("SelectedLevel")
		if selectedLevel == 3 and not levelThreeBriefing.started then
			levelThreeBriefing.started = true
			levelThreeBriefing.play()
		end

	elseif ev == "death" then
		if a == player.Name then
			dead = true
			cancelAllCommandBriefings(true)
			task.delay(0.85, function()
				if dead and player:GetAttribute("InRound") == true then startSpectating() end
			end)
		end
		-- A teammate dying used to drop this file's own spectate target so the
		-- ticker would re-pick. There is no target here any more:
		-- SpectateController owns the POV and re-picks on its own.

	elseif ev == "escape" then
		if a == player.Name then
			cancelAllCommandBriefings(true)
			showRoundEnding(
				"YOU GOT OUT",
				"",
				"WAITING FOR THE OTHERS",
				Color3.fromRGB(68, 221, 196),
				true
			)
		elseif player:GetAttribute("InRound") == true
			and player:GetAttribute("Escaped") ~= true then
			completion.Hud.Feed({Kind = "SYSTEM", Actor = a, Detail = "got out", Key = "escape:" .. tostring(a)})
		end

	elseif ev == "lose" then
		cancelAllCommandBriefings(true)
		stopSpectating()
		local totalPlayers = math.max(1, math.floor(tonumber(c) or 1))
		showRoundEnding(
			"NO ONE FOUND A WAY OUT",
			"TIME " .. formatRoundTime(a) .. "  •  SURVIVORS 0/" .. totalPlayers,
			"RETURNING TO LOBBY",
			Color3.fromRGB(242, 112, 95),
			false
		)

	elseif ev == "win" then
		cancelAllCommandBriefings(true)
		stopSpectating()
		local survivors = math.max(0, math.floor(tonumber(b) or 0))
		local totalPlayers = math.max(1, math.floor(tonumber(c) or math.max(1, survivors)))
		showRoundEnding(
			-- Level 5 runs on the lobby server, where SelectedLevel stays 1: it says its own number (so does the
			-- Level 2 new-map preview's exit slide).
			dead and "THE OTHERS FOUND A WAY OUT" or ("LEVEL " .. tostring(player:GetAttribute("Level5VoidRound") == true and 5 or player:GetAttribute("Level6PlaygroundPreview") == true and 6
				or player:GetAttribute("Level2NewMapPreview") == true and 2 or workspace:GetAttribute("SelectedLevel") or 1) .. " CLEARED"),
			"TIME " .. formatRoundTime(a) .. "  •  SURVIVORS " .. survivors .. "/" .. totalPlayers,
			"RETURNING TO LOBBY",
			Color3.fromRGB(68, 221, 196),
			false
		)
		completion.start(d, e, f)

	elseif ev == "returnpending" then
		if tonumber(a) == completion.serverSerial then
			completion.pending = true
			completion.suspend()
			completion.caption(completion.button, "RETURNING...")
		end

	elseif ev == "resultroster" then
		if player:GetAttribute("InRound") == true then completion.setRoster(a) end
	elseif ev == "postwinchoices" then
		completion.applyChoices(a)
	elseif ev == "continuefailed" then
		if tonumber(a) == completion.serverSerial and completion.deadline
			and workspace:GetServerTimeNow() < completion.deadline then
			-- The transfer did not start. Re-arm both actions; the countdown is
			-- still running and will carry this player onward if they do nothing.
			completion.pending = false
			completion.caption(completion.continueButton, "TRY CONTINUE")
			completion.caption(completion.button, "BACK TO LOBBY")
			for _, button in ipairs(completion.buttons) do
				button.Active = button.Visible
				button.Selectable = button.Visible
			end
		end

	elseif ev == "returnfailed" then
		if tonumber(a) == completion.serverSerial and completion.deadline
			and workspace:GetServerTimeNow() < completion.deadline then
			completion.pending = false
			completion.caption(completion.continueButton, "CONTINUE")
			completion.caption(completion.button, "TRY BACK TO LOBBY")
			for _, button in ipairs(completion.buttons) do
				button.Active = button.Visible
				button.Selectable = button.Visible
			end
		end

	elseif ev == "transitionfailed" then
		completion.deadline = nil
		completion.pending = true
		completion.suspend()
		completion.caption(completion.button, "RETURNING...")
		endHint.Text = "NEXT LEVEL UNAVAILABLE  •  RETURNING TO LOBBY"
	end
end)

-- ── PARTY DOWN ─────────────────────────────────────────────────────────────
-- The window that opens when the LAST living player dies: the run is not lost
-- yet, and an Emergency Re-entry brings somebody back. The server opens it on
-- the RoundStatus remote with ("partydown", seconds, whoFellLast) and closes it
-- with ("partydownclear") when the party survived it; a real wipe arrives as
-- the ordinary "lose".
--
-- It listens on its OWN connection to the same remote rather than growing a
-- branch inside the handler above. That keeps every piece of its state -- and
-- every register it costs -- inside this do-block: this chunk sits at Luau's
-- 200-local limit, and block locals hand their registers back at `end` while
-- the closures keep them as upvalues. Everything else is a field of one table
-- for the same reason.
-- HUD_B8_PARTY_DOWN: local presentation clock; the server settles the round.
do
	local GuiService = game:GetService("GuiService")
	local MarketplaceService = game:GetService("MarketplaceService")
	local Hud = require(RS:WaitForChild("RoundHud"))
	local Binder = require(RS:WaitForChild("ZyntraShopUI"):WaitForChild("ShopBinder"))
	local pd = {
		deadline = nil, window = 15, armAt = 0, armed = false, declined = false,
		lastSeconds = nil, waiting = false,
		dev = (function()
			local ok, access = pcall(require, RS:FindFirstChild("DevAccess"))
			return ok and type(access) == "table" and access.IsAllowed(player) == true
		end)(),
	}
	pd.frame = Instance.new("Frame")
	pd.frame.Name = "PartyDownOverlay"
	pd.frame.Size = UDim2.fromScale(1, 1)
	pd.frame.BackgroundColor3 = Color3.fromRGB(4, 7, 16)
	pd.frame.BackgroundTransparency = 0.1
	pd.frame.BorderSizePixel = 0
	pd.frame.Visible = false
	pd.frame.ZIndex = 112
	pd.frame.Parent = gui
	pd.brackets = Instance.new("Frame")
	pd.brackets.Name = "CornerBrackets"
	pd.brackets.Visible = not UIDevice.Layout().IsTouch
	pd.brackets.Size = UDim2.fromScale(1, 1)
	pd.brackets.BackgroundTransparency = 1
	pd.brackets.ZIndex = 113
	pd.brackets.Parent = pd.frame
	for _, corner in ipairs({{0,0}, {1,0}, {0,1}, {1,1}}) do
		for _, size in ipairs({Vector2.new(26,2), Vector2.new(2,26)}) do
			local line = Instance.new("Frame")
			line.AnchorPoint = Vector2.new(corner[1], corner[2])
			line.Position = UDim2.new(corner[1], corner[1] == 0 and 24 or -24, corner[2], corner[2] == 0 and 24 or -24)
			line.Size = UDim2.fromOffset(size.X, size.Y)
			line.BorderSizePixel = 0
			line.BackgroundColor3 = Color3.fromRGB(242,235,219)
			line.BackgroundTransparency = 0.65
			line.ZIndex = 113
			line.Parent = pd.brackets
		end
	end
	function pd.caption(button, text)
		local caption = Binder.find(button, "Label")
		if caption then caption.Text = text end
	end
	function pd.offerLayout()
		local layout = UIDevice.Layout()
		local items = Binder.find(pd.parts.Offer, "Items")
		local flow = items:FindFirstChildOfClass("UIListLayout")
		local visible = {}
		for _, button in ipairs({pd.reentry, pd.free, pd.decline}) do
			if button.Visible then visible[#visible + 1] = button end
		end
		local vertical = pd.compact and pd.width < 500
		local height = pd.compact and 52 or math.max(44, 106 * pd.scale)
		local gap = 8
		flow.FillDirection = vertical and Enum.FillDirection.Vertical or Enum.FillDirection.Horizontal
		flow.HorizontalAlignment = Enum.HorizontalAlignment.Center
		flow.VerticalAlignment = Enum.VerticalAlignment.Center
		flow.Padding = UDim.new(0, gap)
		local offerHeight = vertical and (#visible * height + math.max(0, #visible - 1) * gap) or height
		pd.parts.Offer.Size = UDim2.fromOffset(pd.width, offerHeight)
		items.AnchorPoint = Vector2.new(0, 0)
		items.Position = UDim2.fromOffset(0, 0)
		items.Size = UDim2.fromOffset(pd.width, offerHeight)
		for _, button in ipairs(visible) do
			button.AnchorPoint = Vector2.new(0, 0)
			button.Size = UDim2.fromOffset(vertical and pd.width or (pd.width - gap * (#visible - 1)) / #visible, height)
			local caption = Binder.find(button, "Label")
			caption.TextWrapped = true
		end
	end
	function pd.refresh()
		if not pd.card then return end
		local eligible = player:GetAttribute("InRound") == true
			and (workspace:GetAttribute("RoundActive") == true or player:GetAttribute("Level6PlaygroundPreview") == true)
			and player:GetAttribute("ZyntraReentryUsed") ~= true
		local credits = tonumber(player:GetAttribute("ZyntraReentryCredits")) or 0
		if credits > 0 then pd.waiting = false end
		pd.reentry.Visible = eligible
		pd.parts.Reentry.Visible = eligible
		pd.reentry.Active = eligible and pd.armed and not pd.waiting
		pd.reentry.Selectable = pd.reentry.Active
		pd.caption(pd.reentry, pd.waiting and "WAITING FOR ROBLOX..." or credits > 0
			and ("USE CREDIT \u{B7} " .. credits .. " OWNED")
			or ("BUY \u{B7} R$ " .. tostring(tonumber(player:GetAttribute("ZyntraReentryPrice")) or "--") .. " \u{B7} 0 OWNED"))
		local colour = credits > 0 and Color3.fromRGB(68,221,196) or Color3.fromRGB(232,160,36)
		for _, node in ipairs(pd.reentry:GetDescendants()) do
			if node:IsA("UIStroke") then node.Color = colour end
		end
		Binder.find(pd.reentry, "Label").TextColor3 = colour
		pd.decline.Active = pd.armed
		pd.decline.Selectable = pd.armed
		pd.free.Visible = pd.dev
		local busy = player:GetAttribute("DevRespawnBusy") == true
		pd.caption(pd.free, busy and "RESPAWNING..." or "FREE RESPAWN")
		pd.free.Active = pd.dev and pd.armed and not busy
			and player:GetAttribute("InRound") == true
			and (workspace:GetAttribute("RoundActive") == true or player:GetAttribute("Level6PlaygroundPreview") == true)
		pd.free.Selectable = pd.free.Active
		pd.offerLayout()
	end
	function pd.declineNow()
		if not (pd.frame.Visible and pd.decline.Active) then return false end
		pd.declined = true
		pd.lastSeconds = nil
		pd.setCardVisible(false)
		return true
	end
	function pd.requestReentry()
		if not pd.reentry.Active or GuiService.MenuIsOpen then return end
		if (tonumber(player:GetAttribute("ZyntraReentryCredits")) or 0) > 0 then
			if pd.lastUse and os.clock() - pd.lastUse < 0.5 then return end
			pd.lastUse = os.clock()
			dispatchAudio.action:FireServer("UseReentry")
			return
		end
		local productId = tonumber(player:GetAttribute("ZyntraReentryProductId")) or 0
		if productId <= 0 then
			completion.Hud.Feed({Kind = "SYSTEM", Detail = "Emergency Re-entry is not configured yet.", Key = "reentryerror"})
			return
		end
		pd.waiting = true
		pd.refresh()
		MarketplaceService:PromptProductPurchase(player, productId)
	end
	function pd.freeRespawn()
		if not pd.free.Active then return end
		local command = script.Parent:FindFirstChild("DevCheatCommand")
		if command and command:IsA("BindableEvent") then command:Fire("freeRespawn")
		else completion.Hud.Feed({Kind = "SYSTEM", Detail = "Developer controls are still loading. Try again.", Key = "freeerror"}) end
	end
	function pd.applyLayout()
		local layout = UIDevice.Layout()
		local touch = layout.IsTouch
		local compact = touch or layout.Safe.Height < 650 or layout.Safe.Width < 900
		local name = compact and "PartyDownCardTouch" or "PartyDownCard"
		pd.compact = compact
		local designWidth = compact and 726 or 1440
		pd.width = math.min(designWidth, layout.Safe.Width - 32)
		pd.scale = pd.width / designWidth
		local focus = GuiService.SelectedObject
		focus = focus and focus.Name
		if pd.card then pd.card:Destroy() end
		pd.card, pd.parts = Hud.Stack("HUD_Screens", name, pd.frame,
			{Name = "PartyDownCard", Scale = pd.scale, Touch = compact})
		if not pd.card then return end
		pd.card.AnchorPoint = Vector2.new(0.5, 0.5)
		pd.card.Position = UIDevice.LocalPosition(gui, (layout.Safe.Left + layout.Safe.Right) / 2,
			(layout.Safe.Top + layout.Safe.Bottom) / 2 + (touch and 18 or 0))
		for _, node in ipairs(pd.card:GetDescendants()) do
			if node:IsA("GuiObject") then node.ZIndex = 114 end
		end
		pd.reentry = Binder.find(pd.card, "PartyDownReentry")
		pd.free = Binder.find(pd.card, "PartyDownFreeRespawn")
		pd.decline = Binder.find(pd.card, "PartyDownDecline")
		pd.fallen = Binder.find(pd.card, "PartyDownFallen")
		pd.timer = Binder.find(pd.card, "PartyDownTimer")
		pd.fill = Binder.find(pd.card, "PartyDownFill")
		Binder.find(pd.card, "NoSignal").Text = "NO SIGNAL"
		Binder.find(pd.card, "PartyDownTitle").Text = "PARTY DOWN"
		pd.caption(pd.decline, "NO THANKS")
		pd.fallen.Visible = pd.faller ~= nil
		pd.fallen.Text = pd.faller and (string.upper(pd.faller) .. " FELL") or ""
		pd.fill.Size = UDim2.fromScale(pd.deadline and math.clamp((pd.deadline - os.clock()) / pd.window, 0, 1) or 1, 1)
		pd.timer.Text = string.format("%02d:%02d", 0, pd.lastSeconds or pd.window)
		pd.brackets.Visible = not touch
		pd.reentry.Activated:Connect(pd.requestReentry)
		pd.free.Activated:Connect(pd.freeRespawn)
		pd.decline.Activated:Connect(pd.declineNow)
		pd.refresh()
		for _, button in ipairs({pd.reentry, pd.free, pd.decline}) do
			button.Modal = true
			if focus == button.Name and button.Active then GuiService.SelectedObject = button end
		end
	end
	function pd.setCardVisible(visible)
		pd.frame.Visible = visible
		player:SetAttribute("PartyDownCardOpen", visible or nil)
		if visible then pd.applyLayout()
		elseif GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(pd.frame) then
			GuiService.SelectedObject = nil
		end
	end
	function pd.show(seconds, faller)
		if player:GetAttribute("InRound") ~= true then return end
		pd.window = math.max(1, tonumber(seconds) or 15)
		pd.deadline = os.clock() + pd.window
		pd.declined, pd.armed, pd.waiting = false, false, false
		pd.armAt = os.clock() + 0.6
		pd.lastSeconds, pd.lastUse = nil, nil
		local other = type(faller) == "string" and Players:FindFirstChild(faller)
		pd.faller = type(faller) == "string" and faller ~= "" and (other and other.DisplayName or faller) or nil
		player:SetAttribute("PartyDownWindowOpen", true)
		pd.setCardVisible(true)
	end
	function pd.hide()
		if pd.statusText and label.Text == pd.statusText then
			setMsg("")
			label.Position, label.Size, label.AnchorPoint = pd.labelPosition, pd.labelSize, pd.labelAnchor
		end
		pd.statusText = nil
		pd.deadline = nil
		pd.declined, pd.armed, pd.waiting = false, false, false
		pd.lastSeconds = nil
		pd.setCardVisible(false)
		player:SetAttribute("PartyDownWindowOpen", nil)
	end
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId)
		if userId == player.UserId and productId == tonumber(player:GetAttribute("ZyntraReentryProductId")) then
			pd.waiting = false
			pd.refresh()
		end
	end)
	ContextActionService:UnbindAction("PartyDownDecline")
	ContextActionService:BindActionAtPriority("PartyDownDecline", function(_, state)
		if state ~= Enum.UserInputState.Begin or GuiService.MenuIsOpen or UIS:GetFocusedTextBox()
			or not pd.frame.Visible then return Enum.ContextActionResult.Pass end
		return pd.declineNow() and Enum.ContextActionResult.Sink or Enum.ContextActionResult.Pass
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
	RunService.RenderStepped:Connect(function()
		if not pd.deadline then return end
		local left = pd.deadline - os.clock()
		pd.fill.Size = UDim2.fromScale(math.clamp(left / pd.window, 0, 1), 1)
		if not pd.armed and left > 0 and os.clock() >= pd.armAt then
			pd.armed = true
			pd.refresh()
			if pd.frame.Visible and UIDevice.LastInput() == "Gamepad" and not GuiService.MenuIsOpen then
				GuiService.SelectedObject = pd.reentry.Active and pd.reentry or pd.free.Active and pd.free or pd.decline
			end
		end
		local remaining = math.max(0, math.ceil(left))
		if remaining ~= pd.lastSeconds then
			pd.lastSeconds = remaining
			pd.timer.Text = string.format("%02d:%02d", math.floor(remaining / 60), remaining % 60)
			if pd.declined then
				if not pd.statusText then pd.labelPosition, pd.labelSize, pd.labelAnchor = label.Position, label.Size, label.AnchorPoint end
				pd.statusText = "PARTY DOWN \u{B7} " .. remaining .. " s"
				setMsg(pd.statusText, Color3.fromRGB(242,112,95))
				local layout = UIDevice.Layout()
				label.AnchorPoint = Vector2.new(0.5, 0)
				label.Position = UIDevice.LocalPosition(gui, (layout.Safe.Left + layout.Safe.Right) / 2, layout.Safe.Top + (layout.IsTouch and 94 or 112))
				label.Size = UDim2.fromOffset(math.min(460, layout.Safe.Width - 24), 32)
			end
		end
		if left <= 0 then
			if pd.armed then pd.armed = false; pd.armAt = math.huge; pd.refresh() end
			if left <= -5 then pd.hide() end
		end
	end)
	remote.OnClientEvent:Connect(function(ev, a, b)
		if ev == "partydown" then pd.show(a, b)
		elseif ev == "partydownclear" or ev == "lose" or ev == "win" or ev == "start" or ev == "lobby" or ev == "loadinggame" then pd.hide()
		elseif ev == "reentry" and a == player.Name then pd.hide() end
	end)
	UIDevice.Changed:Connect(function()
		pd.brackets.Visible = not UIDevice.Layout().IsTouch
		if pd.card then pd.applyLayout() end
	end)
	player:GetAttributeChangedSignal("InRound"):Connect(function() if player:GetAttribute("InRound") ~= true then pd.hide() end end)
	for _, attr in ipairs({"ZyntraReentryUsed", "ZyntraReentryCredits", "ZyntraReentryPrice", "DevRespawnBusy"}) do
		player:GetAttributeChangedSignal(attr):Connect(pd.refresh)
	end
	workspace:GetAttributeChangedSignal("RoundActive"):Connect(pd.refresh)
	player:GetAttributeChangedSignal("DevRespawnSerial"):Connect(function()
		local status = tostring(player:GetAttribute("DevRespawnStatus") or "")
		if pd.dev and status ~= "RESPAWNED" and pd.frame.Visible then
			completion.Hud.Feed({Kind = "SYSTEM", Detail = "FREE RESPAWN \u{B7} " .. status, Key = "freerespawn"})
		end
	end)
	if RunService:IsStudio() then
		player:GetAttributeChangedSignal("DevPartyDown"):Connect(function()
			local seconds = tonumber(player:GetAttribute("DevPartyDown"))
			if seconds and seconds > 0 then pd.show(seconds, "DEV TESTER") else pd.hide() end
		end)
	end
end


-- ── DEATH CARD ─────────────────────────────────────────────────────────────
-- WHAT KILLED YOU, and the one thing that would have stopped it.
--
-- The server marks the player at the kill site and appends a DeathAdvice key to
-- the "death" payload it already fired; this draws the copy that belongs to that
-- key and NOTHING ELSE. A key this client does not know -- or the Unknown the
-- server sends for a death nothing marked -- prints the neutral SIGNAL LOST line
-- with no tip. There is no generic fallback advice on purpose: a plausible wrong
-- tip is worse than no tip, because the player will believe it and practise it.
--
-- OWN DEATHS ONLY. It is drawn when the name in the payload is this player's, so
-- a spectator who joins the POV of somebody killed by the foam never reads that
-- player's tip as their own. Spectating changes the camera, not the card.
--
-- Its own connection and its own do-block, for exactly the reason the PARTY DOWN
-- block above gives: this chunk sits at Luau's 200-local limit and a block's
-- locals hand their registers back at `end` while the closures keep them as
-- upvalues. Everything else is a field of one table for the same reason.
-- HUD_B8_DEATH: closing cancels this death's timers and both presentations.
do
	local copyFor = function()
		return {Title = "SIGNAL LOST", Cause = "Your signal cut out.", Tip = ""}
	end
	do
		local ok, module = pcall(require, RS:FindFirstChild("DeathAdvice"))
		if ok and type(module) == "table" and type(module.Copy) == "function" then copyFor = module.Copy end
	end
	local Hud = require(RS:WaitForChild("RoundHud"))
	local Binder = require(RS:WaitForChild("ZyntraShopUI"):WaitForChild("ShopBinder"))
	local GuiService = game:GetService("GuiService")
	local dc = {serial = 0, dwell = 12, active = false, closed = false}
	function dc.hide()
		dc.serial += 1
		dc.active = false
		if dc.card then dc.card.Visible = false end
		if dc.docked then dc.docked.Visible = false end
	end
	function dc.close()
		dc.closed = true
		dc.hide()
	end
	function dc.layout()
		if not (dc.card and dc.docked) then return end
		local layout = UIDevice.Layout()
		local docked = player:GetAttribute("PartyDownCardOpen") == true
		dc.card.AnchorPoint = Vector2.new(0.5, 1)
		dc.card.Position = UIDevice.LocalPosition(gui, (layout.Safe.Left + layout.Safe.Right) / 2, layout.Safe.Bottom - 112)
		dc.docked.AnchorPoint = Vector2.new(0.5, 0)
		dc.docked.Position = UIDevice.LocalPosition(gui, (layout.Safe.Left + layout.Safe.Right) / 2,
			layout.Safe.Top + (layout.IsTouch and 6 or 16))
		dc.card.Visible = dc.active and not dc.closed and not docked
		dc.docked.Visible = dc.active and not dc.closed and docked
	end
	function dc.mount()
		local layout = UIDevice.Layout()
		local touch = layout.IsTouch or layout.Safe.Height < 344
		local width = touch and 420 or 480
		local scale = math.min(1, (layout.Safe.Width - 32) / width)
		if dc.card then dc.card:Destroy() end
		if dc.docked then dc.docked:Destroy() end
		dc.card, dc.parts = Hud.Stack("HUD_Screens", touch and "DeathCauseTouch" or "DeathCause", gui,
			{Name = "DeathCause", Scale = scale, Touch = touch})
		dc.docked = Hud.Mount("HUD_Screens", touch and "DeathCauseDockedTouch" or "DeathCauseDocked", gui,
			{Name = "DeathCauseDocked", Scale = scale, Touch = touch})
		if not dc.card or not dc.docked then return end
		dc.title = Binder.find(dc.card, "DeathCauseTitle")
		dc.cause = Binder.find(dc.card, "DeathCauseBody")
		dc.tip = Binder.find(dc.card, "DeathCauseTip")
		Binder.find(dc.card, "WhatHappened").Text = "WHAT HAPPENED"
		Binder.find(dc.card, "DeathCauseEyebrow").Text = "NEXT TIME"
		for _, root in ipairs({dc.card, dc.docked}) do
			local z = root == dc.card and 96 or 118
			root.ZIndex = z
			for _, node in ipairs(root:GetDescendants()) do if node:IsA("GuiObject") then node.ZIndex = z + 1 end end
			local close = Binder.find(root, "Close")
			close.Size = UDim2.fromOffset(44, 44)
			close.AnchorPoint = Vector2.new(1, 0)
			close.Position = UDim2.new(1, 0, 0, 0)
			close.Activated:Connect(dc.close)
		end
		local chip = Binder.at(dc.card, "Head/CloseHint/KeyChip")
		if chip then Hud.Keycap(chip, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB) end
		if dc.advice then
			dc.title.Text = dc.advice.Title
			dc.cause.Text = dc.advice.Cause
			dc.tip.Text = dc.advice.Tip or ""
			dc.parts.Advice.Visible = type(dc.advice.Tip) == "string" and dc.advice.Tip ~= ""
			Binder.find(dc.docked, "DeathCauseTitle").Text = dc.advice.Title
		end
		dc.layout()
	end
	function dc.expire(token)
		if dc.serial ~= token or not dc.active then return end
		if player:GetAttribute("PartyDownCardOpen") == true then
			task.delay(0.5, function() dc.expire(token) end)
		else dc.hide() end
	end
	function dc.show(causeKey)
		dc.serial += 1
		dc.active, dc.closed = true, false
		dc.advice = copyFor(causeKey)
		dc.mount()
		local token = dc.serial
		task.delay(dc.dwell, function() dc.expire(token) end)
	end
	player:GetAttributeChangedSignal("PartyDownCardOpen"):Connect(dc.layout)
	UIDevice.Changed:Connect(dc.mount)
	ContextActionService:UnbindAction("DeathCauseClose")
	ContextActionService:BindActionAtPriority("DeathCauseClose", function(_, state)
		if state ~= Enum.UserInputState.Begin or not dc.active or dc.closed
			or player:GetAttribute("PartyDownCardOpen") == true or GuiService.MenuIsOpen
			or UIS:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
		dc.close()
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
	-- Roblox owns Escape. MenuOpened is also wired because it can consume Esc
	-- before InputBegan reaches a game script; either path closes this life once.
	UIS.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape and dc.active then dc.close() end
	end)
	GuiService.MenuOpened:Connect(function() if dc.active then dc.close() end end)
	remote.OnClientEvent:Connect(function(ev, a, _b, c)
		if ev == "death" and a == player.Name then dc.show(c)
		elseif ev == "start" or ev == "lobby" or ev == "loadinggame" or ev == "win" or ev == "lose" then dc.hide()
		elseif ev == "reentry" and a == player.Name then dc.hide() end
	end)
	player.CharacterAdded:Connect(dc.hide)
	if RunService:IsStudio() then
		player:GetAttributeChangedSignal("DevDeathCause"):Connect(function()
			local key = player:GetAttribute("DevDeathCause")
			if type(key) == "string" and key ~= "" then dc.show(key) else dc.hide() end
		end)
	end
end

-- Announce readiness only after the persisted preference has ACTUALLY loaded.
-- A fixed timeout used to send this too early on a slow DataStore read; the
-- server then fired its one-shot event while this client was still ineligible,
-- permanently losing a new player's welcome for that session. Attribute and
-- lobby listeners make the gate event-driven without ever defaulting audible.
function lobbyBriefing.trySendReady()
	if lobbyBriefing.readySent
		or player:GetAttribute("ZyntraDispatchPreferenceLoaded") ~= true
		or player:GetAttribute("ZyntraLobbyBriefingPlayed") == true
		or player:GetAttribute("InRound") == true
		or player:GetAttribute("LobbyLoadingOpen") == true -- the briefing waits for the loading cover
		or not workspace:FindFirstChild("ServerLobby") then
		return
	end
	lobbyBriefing.readySent = true
	remote:FireServer("lobbybriefingready")
end
player:GetAttributeChangedSignal("ZyntraDispatchPreferenceLoaded"):Connect(lobbyBriefing.trySendReady)
player:GetAttributeChangedSignal("ZyntraLobbyBriefingPlayed"):Connect(lobbyBriefing.trySendReady)
player:GetAttributeChangedSignal("InRound"):Connect(lobbyBriefing.trySendReady)
player:GetAttributeChangedSignal("LobbyLoadingOpen"):Connect(lobbyBriefing.trySendReady)
workspace.ChildAdded:Connect(function(child)
	if child.Name == "ServerLobby" then lobbyBriefing.trySendReady() end
end)
task.defer(lobbyBriefing.trySendReady)

-- Responsive objective layout verified in play test.


-- ── MIMIC APPARITION ───────────────────────────────────────────────────────
-- Client-only: only the isolated target sees or hears this social scare.
local MimicPathfinding = game:GetService("PathfindingService")
local MimicTweenService = game:GetService("TweenService")

local MIMIC_ISOLATION_RADIUS = 70
local MIMIC_FOLLOW_DISTANCE = 10
local MIMIC_DESPAWN_DISTANCE = 110
local activeMimic = nil
local mimicSerial = 0
local nextMimicChance = os.clock() + math.random(35, 65)

local function mimicLocalAlive()
 local char = player.Character
 local hum = char and char:FindFirstChildOfClass("Humanoid")
 local root = char and char:FindFirstChild("HumanoidRootPart")
 local levelOneActive = workspace:GetAttribute("SelectedLevel") == 1
 return char, hum, root, levelOneActive and hum and hum.Health > 0 and root ~= nil
end

local function mimicTeammateNearby(root)
 for _, other in ipairs(Players:GetPlayers()) do
  if other ~= player and other:GetAttribute("Escaped") ~= true then
   local char = other.Character
   local hum = char and char:FindFirstChildOfClass("Humanoid")
   local otherRoot = char and char:FindFirstChild("HumanoidRootPart")
   if hum and hum.Health > 0 and otherRoot
    and (otherRoot.Position - root.Position).Magnitude < MIMIC_ISOLATION_RADIUS then
    return true
   end
  end
 end
 return false
end

local function mimicAppearanceSource()
 local choices = {}
 for _, other in ipairs(Players:GetPlayers()) do
  if other ~= player then
   local char = other.Character
   local hum = char and char:FindFirstChildOfClass("Humanoid")
   if char and hum and hum.Health > 0 then choices[#choices + 1] = other end
  end
 end
 return #choices > 0 and choices[math.random(#choices)] or player
end

local function mimicVisible(model)
 local camera = workspace.CurrentCamera
 local target = model and (model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart"))
 if not camera or not target then return false end
 local screen, onScreen = camera:WorldToViewportPoint(target.Position)
 if not onScreen or screen.Z <= 0 then return false end
 local delta = target.Position - camera.CFrame.Position
 if delta.Magnitude > 90 or camera.CFrame.LookVector:Dot(delta.Unit) < 0.5 then return false end
 local rp = RaycastParams.new()
 rp.FilterType = Enum.RaycastFilterType.Exclude
 local exclude = { model }
 if player.Character then exclude[#exclude + 1] = player.Character end
 rp.FilterDescendantsInstances = exclude
 return workspace:Raycast(camera.CFrame.Position, delta, rp) == nil
end

local function mimicSpawnBehind(root)
 local maze = workspace:FindFirstChild("Maze")
 if not maze then return nil end
 local down = RaycastParams.new()
 down.FilterType = Enum.RaycastFilterType.Include
 down.FilterDescendantsInstances = { maze }
 for _ = 1, 12 do
  local guess = root.Position - root.CFrame.LookVector * math.random(16, 22)
   + root.CFrame.RightVector * math.random(-6, 6)
  local hit = workspace:Raycast(guess + Vector3.new(0, 3, 0), Vector3.new(0, -12, 0), down)
  if hit and hit.Normal.Y > 0.6 then
   local pos = hit.Position + Vector3.new(0, 3, 0)
   local toSpawn = pos - root.Position
   if toSpawn.Magnitude > 1 and root.CFrame.LookVector:Dot(toSpawn.Unit) < -0.25 then
    local path = MimicPathfinding:CreatePath({AgentRadius=2, AgentHeight=5, AgentCanJump=false})
    local ok = pcall(function() path:ComputeAsync(pos, root.Position) end)
    if ok and path.Status == Enum.PathStatus.Success then return pos end
   end
  end
 end
 return nil
end

local function mimicFade(model)
 if not model or not model.Parent then return end
 for _, item in ipairs(model:GetDescendants()) do
  if item:IsA("BasePart") or item:IsA("Decal") then
   MimicTweenService:Create(item, TweenInfo.new(0.1), {Transparency=1}):Play()
  elseif item:IsA("Sound") then
   MimicTweenService:Create(item, TweenInfo.new(0.08), {Volume=0}):Play()
  end
 end
 task.delay(0.12, function() if model then model:Destroy() end end)
end

local function mimicAnimationId(character, keyword)
 for _, item in ipairs(character:GetDescendants()) do
  if item:IsA("Animation") and item.Name:lower():find(keyword, 1, true)
   and item.AnimationId ~= ""
   and not item:FindFirstAncestor("ZyntraHazmatSkinVisual") then
   return item.AnimationId
  end
 end
 return nil
end

local function mimicBuild(sourcePlayer, spawnPos)
 local sourceChar = sourcePlayer.Character
 if not sourceChar then return nil end
 local rigIsR15 = sourceChar:FindFirstChild("UpperTorso") ~= nil
 local walkId = mimicAnimationId(sourceChar, "walk") or (rigIsR15 and "rbxassetid://507777826" or "rbxassetid://180426354")
 local runId = mimicAnimationId(sourceChar, "run") or (rigIsR15 and "rbxassetid://507767714" or "rbxassetid://180426354")
 local wasArchivable = sourceChar.Archivable
 sourceChar.Archivable = true
 local model = sourceChar:Clone()
 sourceChar.Archivable = wasArchivable
 if not model then return nil end
 model.Name = "MimicApparition"

 -- The player's Meshy skin is driven by a separate AnimationController. A
 -- cloned character cannot inherit its running tracks, so that visual would
 -- freeze while the R15 body underneath stays transparent. Let the mimic use
 -- the native R15 suit and its own walk/run animator instead.
 local cosmetic = model:FindFirstChild("ZyntraHazmatSkinVisual")
 if cosmetic then cosmetic:Destroy() end
 for _, item in ipairs(model:GetDescendants()) do
  local original = item:GetAttribute("ZyntraHazmatOriginalTransparency")
  if type(original) == "number"
   and (item:IsA("BasePart") or item:IsA("Decal") or item:IsA("Texture")) then
   item.Transparency = original
   item:SetAttribute("ZyntraHazmatOriginalTransparency", nil)
  end
 end

 -- The clone inherits everything the source player is wearing, and that includes
 -- the overhead BillboardGui the Zyntra Supporter pass parents to the Head. A
 -- Mimic captioned ZYNTRA SUPPORTER is an instant tell, and it hangs a purchase
 -- badge over a monster. Strip every overhead GUI rather than that one name, so
 -- a future tag cannot quietly reintroduce the same leak. The Humanoid's own
 -- name and health display are suppressed separately, just below.
 for _, item in ipairs(model:GetDescendants()) do
  if item:IsA("LuaSourceContainer") or item:IsA("Tool") or item:IsA("ForceField")
   or item:IsA("Sound") or item:IsA("BillboardGui") then
   item:Destroy()
  elseif item:IsA("BasePart") then
   item.Anchored = false
   item.CanCollide = false
   item.CanTouch = false
   item.CanQuery = false
   item.Massless = true
   item.LocalTransparencyModifier = 0
  end
 end

 local hum = model:FindFirstChildOfClass("Humanoid")
 local root = model:FindFirstChild("HumanoidRootPart")
 if not hum or not root then model:Destroy() return nil end
 hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
 hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
 hum.JumpPower = 0
 hum.AutoRotate = true
 model.PrimaryPart = root
 model.Parent = workspace
 model:PivotTo(CFrame.new(spawnPos))

 local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
 local function loadTrack(id)
  if not id then return nil end
  local anim = Instance.new("Animation")
  anim.AnimationId = id
  local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
  anim:Destroy()
  if ok and track then
   track.Looped = true
   track.Priority = Enum.AnimationPriority.Movement
   return track
  end
  return nil
 end
 local walkTrack = loadTrack(walkId)
 local runTrack = loadTrack(runId)
 local rightShoulder = model:FindFirstChild("RightShoulder", true) or model:FindFirstChild("Right Shoulder", true)
 local leftShoulder = model:FindFirstChild("LeftShoulder", true) or model:FindFirstChild("Left Shoulder", true)
 local rightElbow = model:FindFirstChild("RightElbow", true)
 local leftElbow = model:FindFirstChild("LeftElbow", true)
 local neck = model:FindFirstChild("Neck", true)
 local waist = model:FindFirstChild("Waist", true)
 local poseMotors = {rightShoulder, leftShoulder, rightElbow, leftElbow, neck, waist}

 local function clearStillPose()
  for _, motor in ipairs(poseMotors) do
   if motor and motor:IsA("Motor6D") then motor.Transform = CFrame.identity end
  end
 end

 local function applyStillPose()
  -- Deliberately simple: arms hanging beside the torso, shoulders slightly
  -- lowered and the head subtly dipped. No borrowed idle animation or swaying.
  if rightShoulder and rightShoulder:IsA("Motor6D") then
   rightShoulder.Transform = CFrame.Angles(math.rad(7), 0, math.rad(82))
  end
  if leftShoulder and leftShoulder:IsA("Motor6D") then
   leftShoulder.Transform = CFrame.Angles(math.rad(7), 0, math.rad(-82))
  end
  if rightElbow and rightElbow:IsA("Motor6D") then
   rightElbow.Transform = CFrame.Angles(math.rad(-7), 0, 0)
  end
  if leftElbow and leftElbow:IsA("Motor6D") then
   leftElbow.Transform = CFrame.Angles(math.rad(-7), 0, 0)
  end
  if neck and neck:IsA("Motor6D") then
   neck.Transform = CFrame.Angles(math.rad(6), 0, 0)
  end
  if waist and waist:IsA("Motor6D") then
   waist.Transform = CFrame.Angles(math.rad(-3), 0, 0)
  end
 end

 local moving, fast = nil, nil
 local function setMoving(on, sprinting)
  if moving == on and fast == sprinting then return end
  moving, fast = on, sprinting
  if on then clearStillPose() end
  if walkTrack then
   if on and not sprinting then walkTrack:Play(0.12) else walkTrack:Stop(0.08) end
  end
  if runTrack then
   if on and sprinting then runTrack:Play(0.06) else runTrack:Stop(0.08) end
  end
  if not on then
   applyStillPose()
   task.delay(0.1, function()
    if model.Parent and moving == false then applyStillPose() end
   end)
  end
 end
 setMoving(false, false)
 return {model=model, hum=hum, root=root, setMoving=setMoving}
end

local function mimicGuide(mimic, goal)
 local path = MimicPathfinding:CreatePath({AgentRadius=2, AgentHeight=5, AgentCanJump=false})
 local ok = pcall(function() path:ComputeAsync(mimic.root.Position, goal) end)
 if ok and path.Status == Enum.PathStatus.Success then
  local points = path:GetWaypoints()
  local point = points[math.min(3, #points)]
  if point then mimic.hum:MoveTo(point.Position) return end
 end
 mimic.hum:MoveTo(goal)
end

local function mimicRun(spawnPos, devForced)
 mimicSerial += 1
 local token = mimicSerial
 local mimic = mimicBuild(mimicAppearanceSource(), spawnPos)
 if not mimic then return end
 activeMimic = mimic
 local noticed, fleeing = false, false
 local lookedFor, lastPath = 0, 0
 local unseenSince = nil

 task.spawn(function()
  while activeMimic == mimic and mimic.model.Parent and token == mimicSerial do
   local dt = task.wait(0.08)
   local _, playerHum, playerRoot, alive = mimicLocalAlive()
   if (not workspace:GetAttribute("RoundActive") and not devForced) or not alive
    or (player:GetAttribute("Escaped") == true and not devForced) then break end
   local distance = (mimic.root.Position - playerRoot.Position).Magnitude

   if mimicVisible(mimic.model) then
    lookedFor += dt
    unseenSince = nil
   else
    lookedFor = 0
    if fleeing then unseenSince = unseenSince or os.clock() end
   end
   -- The instant the player gets a clear look, the Mimic bolts.
   if not noticed and lookedFor >= 0.1 then
    noticed = true
    fleeing = true
    mimic.hum.WalkSpeed = math.max(playerHum.WalkSpeed * 3.5, 56)
    mimic.setMoving(true, true)
   end

   if fleeing then
    mimic.setMoving(true, true)
    if os.clock() - lastPath > 0.22 then
     lastPath = os.clock()
     local away = mimic.root.Position - playerRoot.Position
     away = Vector3.new(away.X, 0, away.Z)
     if away.Magnitude < 1 then away = -playerRoot.CFrame.LookVector end
     local lateral = Vector3.new(-away.Z, 0, away.X).Unit * math.random(-12, 12)
     mimicGuide(mimic, mimic.root.Position + away.Unit * 82 + lateral)
    end
    if distance >= MIMIC_DESPAWN_DISTANCE
     or (unseenSince and os.clock() - unseenSince > 0.3) then break end
   elseif not noticed then
    mimic.hum.WalkSpeed = math.max(playerHum.WalkSpeed * 0.9, 8)
    local goal = playerRoot.Position - playerRoot.CFrame.LookVector * MIMIC_FOLLOW_DISTANCE
    if distance > MIMIC_FOLLOW_DISTANCE + 3 then
     mimic.setMoving(true, false)
     if os.clock() - lastPath > 0.8 then lastPath=os.clock(); mimicGuide(mimic, goal) end
    else
     mimic.setMoving(false, false)
     mimic.hum:MoveTo(mimic.root.Position)
    end
   else
    mimic.setMoving(false, false)
   end
  end
  mimic.setMoving(false, false)
  if activeMimic == mimic then activeMimic = nil end
  mimicFade(mimic.model)
 end)
end

-- Studio-only Mimic test command. The close-spawn search starts below the
-- ceiling, checks for a clear floor and sightline, and never silently drops the command.
local lastMimicDevSpawn = 0
local function mimicDevSpawnBehind(root, character)
 local forward = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
 local right = Vector3.new(root.CFrame.RightVector.X, 0, root.CFrame.RightVector.Z)
 if forward.Magnitude < 0.01 then forward = Vector3.new(0, 0, -1) else forward = forward.Unit end
 if right.Magnitude < 0.01 then right = Vector3.new(1, 0, 0) else right = right.Unit end

 local rayParams = RaycastParams.new()
 rayParams.FilterType = Enum.RaycastFilterType.Exclude
 rayParams.FilterDescendantsInstances = { character }
 rayParams.IgnoreWater = true
 local overlapParams = OverlapParams.new()
 overlapParams.FilterType = Enum.RaycastFilterType.Exclude
 overlapParams.FilterDescendantsInstances = { character }
 overlapParams.MaxParts = 20

 for _ = 1, 18 do
  local guess = root.Position - forward * math.random(8, 11) + right * math.random(-3, 3)
  -- Start below the maze ceiling so the ceiling can never be mistaken for the floor.
  local hit = workspace:Raycast(guess + Vector3.new(0, 3, 0), Vector3.new(0, -12, 0), rayParams)
  if hit and hit.Normal.Y > 0.65 and math.abs(hit.Position.Y - root.Position.Y) <= 6 then
   local spawnPos = hit.Position + Vector3.new(0, 3, 0)
   local blocked = false
   for _, part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(spawnPos), Vector3.new(3, 5, 3), overlapParams)) do
    if part:IsA("BasePart") and part.CanCollide then blocked = true break end
   end
   local eye = spawnPos + Vector3.new(0, 1.5, 0)
   local target = root.Position + Vector3.new(0, 1.5, 0)
   local wall = workspace:Raycast(eye, target - eye, rayParams)
   if not blocked and not wall then return spawnPos end
  end
 end
 return nil
end

local function devSpawnMimicNow()
 if not RunService:IsStudio() or os.clock() - lastMimicDevSpawn < 0.6 then return end
 lastMimicDevSpawn = os.clock()
 local char, _, root, alive = mimicLocalAlive()
 if not alive then warn("[Mimic Dev] Player is not alive") return end

 if activeMimic then
  mimicSerial += 1
  local previous = activeMimic
  activeMimic = nil
  mimicFade(previous.model)
 end

 local spawnPos = mimicDevSpawnBehind(root, char)
 if not spawnPos then
  warn("[Mimic Dev] No clear floor 8-11 studs behind the player — move away from the wall and retry")
  return
 end

 nextMimicChance = os.clock() + 120
 mimicRun(spawnPos, true)
 print(string.format("[Mimic Dev] Spawned %.1f studs behind %s", (spawnPos - root.Position).Magnitude, player.Name))
end

if RunService:IsStudio() then
 local TextChatService = game:GetService("TextChatService")
 local existingCommand = TextChatService:FindFirstChild("DevSpawnMimic")
 if existingCommand then existingCommand:Destroy() end
 local devCommand = Instance.new("TextChatCommand")
 devCommand.Name = "DevSpawnMimic"
 devCommand.PrimaryAlias = "/spawn"
 devCommand.SecondaryAlias = "/spawnmimic"
 devCommand.AutocompleteVisible = true
 devCommand.Parent = TextChatService
 -- Roblox may pass either the full text or only the arguments here. Because this
 -- command exists only in Studio, either alias always means "spawn the Mimic".
 devCommand.Triggered:Connect(function()
  devSpawnMimicNow()
 end)

 player.Chatted:Connect(function(message)
  message = message:lower():gsub("%s+", " ")
  if message == "/spawn mimic" or message == "/spawnmimic" or message == "/mimic" then
   devSpawnMimicNow()
  end
 end)
 player:GetAttributeChangedSignal("DevSpawnMimic"):Connect(devSpawnMimicNow)
end

task.spawn(function()
 while true do
  task.wait(5)
  if activeMimic and (not activeMimic.model or not activeMimic.model.Parent) then activeMimic=nil end
  local _, _, root, alive = mimicLocalAlive()
  if not activeMimic and workspace:GetAttribute("RoundActive") and alive
   and player:GetAttribute("Escaped") ~= true and not mimicTeammateNearby(root)
   and os.clock() >= nextMimicChance then
   nextMimicChance = os.clock() + math.random(15, 28)
   if math.random() < 0.45 then
    local spawnPos = mimicSpawnBehind(root)
    if spawnPos then
     nextMimicChance = os.clock() + math.random(100, 180)
     mimicRun(spawnPos)
    end
   end
  end
 end
end)

workspace:GetAttributeChangedSignal("RoundActive"):Connect(function()
 if not workspace:GetAttribute("RoundActive") and activeMimic then
  mimicSerial += 1
  local old = activeMimic
  activeMimic = nil
  mimicFade(old.model)
 end
end)


-- ── AMBIENT SCARE DIRECTOR ────────────────────────────────────────────────
-- Client-only, non-lethal scares. The pace rises sharply once lever power
-- is committed, and every effect stays private to the targeted player.
local AmbientTweenService = game:GetService("TweenService")
local AmbientDebris = game:GetService("Debris")
local AMBIENT_KNOCK_SOUND = "rbxassetid://133468930879347"
local ambientBusy = false

-- Warm the authored take once so a random scare never spends its short emitter
-- lifetime waiting for the first network load.
task.spawn(function()
 local warm = Instance.new("Sound")
 warm.Name = "Level 1 Random Knock Preload"
 warm.SoundId = AMBIENT_KNOCK_SOUND
 warm.Volume = 0
 warm.Parent = SoundService
 pcall(function() ContentProvider:PreloadAsync({warm}) end)
 warm:Destroy()
end)
local ambientLastKind = nil
local ambientNextAt = os.clock() + math.random(14, 22)
local ambientLeverPressureUntil = 0

local function ambientCharacter()
 local character = player.Character
 local humanoid = character and character:FindFirstChildOfClass("Humanoid")
 local root = character and character:FindFirstChild("HumanoidRootPart")
 return character, humanoid, root, humanoid and humanoid.Health > 0 and root ~= nil
end

local function ambientCanScare()
 local _, _, _, alive = ambientCharacter()
 return alive
  and workspace:GetAttribute("SelectedLevel") == 1
  and workspace:GetAttribute("RoundActive") == true
  and player:GetAttribute("InRound") == true
  and player:GetAttribute("Escaped") ~= true
end

local function ambientFlatUnit(vector, fallback)
 local flat = Vector3.new(vector.X, 0, vector.Z)
 if flat.Magnitude < 0.01 then return fallback or Vector3.new(0, 0, -1) end
 return flat.Unit
end

local function ambientEmitter(name, position, lifetime)
 local emitter = Instance.new("Part")
 emitter.Name = name
 emitter.Size = Vector3.new(0.2, 0.2, 0.2)
 emitter.CFrame = CFrame.new(position)
 emitter.Transparency = 1
 emitter.Anchored = true
 emitter.CanCollide = false
 emitter.CanTouch = false
 emitter.CanQuery = false
 emitter.CastShadow = false
 emitter.Parent = workspace
 AmbientDebris:AddItem(emitter, lifetime or 4)
 return emitter
end

local function ambientKnocks()
 -- Level 2 owns its own soundscape; keep the Level 1 wall-knock scare out.
 if workspace:GetAttribute("SelectedLevel") == 2 then return false end
 local _, _, root, alive = ambientCharacter()
 if not alive then return false end
 local forward = ambientFlatUnit(root.CFrame.LookVector)
 local right = ambientFlatUnit(root.CFrame.RightVector, Vector3.new(1, 0, 0))
 local side = math.random(0, 1) == 0 and -1 or 1
 local position = root.Position + right * side * math.random(13, 20)
  + forward * math.random(-7, 7) + Vector3.new(0, 2.7, 0)
 local emitter = ambientEmitter("DistantWallKnock", position, 10)
 local knock = Instance.new("Sound")
 knock.Name = "Knock"
 knock.SoundId = AMBIENT_KNOCK_SOUND
 knock.Volume = 0.50
 knock.PlaybackSpeed = 1
 knock.RollOffMinDistance = 6
 knock.RollOffMaxDistance = 38
 knock.Parent = emitter

 -- This upload is already a complete authored knocking take. Preload this
 -- exact emitter, then play it once at natural pitch so the old clickfast
 -- retrigger cannot chop off its tail.
 pcall(function() ContentProvider:PreloadAsync({knock}) end)
 if not emitter.Parent or not ambientCanScare() then return false end
 knock:Play()
 return true
end

local function ambientLightDrop()
 local _, _, root, alive = ambientCharacter()
 local maze = workspace:FindFirstChild("Maze")
 if not alive or not maze then return false end
 local backward = -ambientFlatUnit(root.CFrame.LookVector)
 local candidates = {}
 for _, item in ipairs(maze:GetDescendants()) do
  if item:IsA("Light") and item.Enabled and item.Brightness > 0.1
   and item.Parent and item.Parent:IsA("BasePart") then
   local delta = item.Parent.Position - root.Position
   local flat = Vector3.new(delta.X, 0, delta.Z)
   if flat.Magnitude > 2 and flat.Magnitude < 50 and backward:Dot(flat.Unit) > 0.05 then
    candidates[#candidates + 1] = {light = item, distance = flat.Magnitude}
   end
  end
 end
 table.sort(candidates, function(a, b) return a.distance < b.distance end)
 if #candidates == 0 then return false end

 local affected = {}
 for index = 1, math.min(4, #candidates) do
  local light = candidates[index].light
  affected[#affected + 1] = {light = light, brightness = light.Brightness}
  AmbientTweenService:Create(light, TweenInfo.new(0.13, Enum.EasingStyle.Quad), {Brightness = 0}):Play()
 end
 task.wait(1.35)
 for _, data in ipairs(affected) do
  local light = data.light
  -- If another game system changed or disabled it, that newer state wins.
  if light.Parent and light.Brightness <= 0.05 then
   AmbientTweenService:Create(light, TweenInfo.new(0.75, Enum.EasingStyle.Quad), {
    Brightness = data.brightness,
   }):Play()
  end
 end
 return true
end

local function ambientShadow()
 if workspace:FindFirstChild("MimicApparition") then return false end
 local character, _, root, alive = ambientCharacter()
 local camera = workspace.CurrentCamera
 if not alive or not camera then return false end
 local forward = ambientFlatUnit(camera.CFrame.LookVector, ambientFlatUnit(root.CFrame.LookVector))
 local right = ambientFlatUnit(camera.CFrame.RightVector, Vector3.new(1, 0, 0))
 local floorParams = RaycastParams.new()
 floorParams.FilterType = Enum.RaycastFilterType.Exclude
 floorParams.FilterDescendantsInstances = {character}
 floorParams.IgnoreWater = true

 local base, chosenSide
 for _ = 1, 10 do
  local side = math.random(0, 1) == 0 and -1 or 1
  local guess = root.Position + forward * math.random(10, 16) + right * side * math.random(4, 7)
  local floorHit = workspace:Raycast(guess + Vector3.new(0, 3, 0), Vector3.new(0, -12, 0), floorParams)
  if floorHit and floorHit.Normal.Y >= 0.65 and math.abs(floorHit.Position.Y - root.Position.Y) <= 7 then
   local candidateBase = floorHit.Position
   local target = candidateBase + Vector3.new(0, 4, 0)
   local screenPoint, onScreen = camera:WorldToViewportPoint(target)
   local sight = workspace:Raycast(camera.CFrame.Position, target - camera.CFrame.Position, floorParams)
   if onScreen and screenPoint.Z > 0 and (not sight or (sight.Position - target).Magnitude <= 2) then
    base = candidateBase
    chosenSide = side
    break
   end
  end
 end
 if not base then return false end

 local model = Instance.new("Model")
 model.Name = "AmbientShadowGlimpse"
 model.Parent = workspace
 local origin = Vector3.new(base.X, base.Y, base.Z)
 local facingTarget = Vector3.new(root.Position.X, base.Y, root.Position.Z)
 local facing = CFrame.lookAt(origin, facingTarget)
 local parts = {}
 local function shadowPart(name, size, offset, shape)
  local part = Instance.new("Part")
  part.Name = name
  part.Size = size
  part.Shape = shape or Enum.PartType.Block
  part.Color = Color3.fromRGB(2, 2, 2)
  part.Material = Enum.Material.SmoothPlastic
  part.Transparency = 0.12
  part.Anchored = true
  part.CanCollide = false
  part.CanTouch = false
  part.CanQuery = false
  part.CastShadow = false
  part.CFrame = facing * CFrame.new(offset)
  part.Parent = model
  parts[#parts + 1] = part
 end
 shadowPart("Torso", Vector3.new(2.1, 3.3, 0.75), Vector3.new(0, 3.35, 0))
 shadowPart("Head", Vector3.new(1.45, 1.45, 1.45), Vector3.new(0, 5.65, 0), Enum.PartType.Ball)
 shadowPart("LeftLeg", Vector3.new(0.65, 2.7, 0.65), Vector3.new(-0.48, 1.35, 0))
 shadowPart("RightLeg", Vector3.new(0.65, 2.7, 0.65), Vector3.new(0.48, 1.35, 0))
 shadowPart("LeftArm", Vector3.new(0.5, 3.0, 0.5), Vector3.new(-1.28, 3.25, 0))
 shadowPart("RightArm", Vector3.new(0.5, 3.0, 0.5), Vector3.new(1.28, 3.25, 0))

 local movement = right * (-chosenSide) * 7
 for _, part in ipairs(parts) do
  AmbientTweenService:Create(part, TweenInfo.new(0.58, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
   CFrame = part.CFrame + movement,
   Transparency = 0.88,
  }):Play()
 end
 task.delay(0.32, function()
  for _, part in ipairs(parts) do
   if part.Parent then AmbientTweenService:Create(part, TweenInfo.new(0.22), {Transparency = 1}):Play() end
  end
 end)
 AmbientDebris:AddItem(model, 0.65)
 return true
end
local ambientScares = {
 knocks = ambientKnocks,
 lights = ambientLightDrop,
 -- Not in the random rotation (ambientChooseKind), but registered so the
 -- documented Studio DevAmbientScare hook can actually trigger it.
 shadow = ambientShadow,
}

local function ambientChooseKind()
 local kind = math.random(1, 100) <= 50 and "knocks" or "lights"
 if kind == ambientLastKind then
  kind = kind == "knocks" and "lights" or "knocks"
 end
 return kind
end

local function ambientTrigger(kind)
 if ambientBusy or not ambientCanScare() then return false end
 local scare = ambientScares[kind]
 if not scare then return false end
 ambientBusy = true
 local ok, started = pcall(scare)
 if not ok then warn("[Ambient Scare] " .. kind .. " failed: " .. tostring(started)) end
 if ok and started then ambientLastKind = kind end
 ambientBusy = false
 return ok and started == true
end

local function ambientHighPressure()
 local mode = workspace:GetAttribute("LightMode")
 return mode == "POWERDOWN" or mode == "ESCAPE" or os.clock() < ambientLeverPressureUntil
end

workspace:GetAttributeChangedSignal("LightMode"):Connect(function()
 if ambientHighPressure() and ambientCanScare() then
  ambientNextAt = math.min(ambientNextAt, os.clock() + math.random(2, 4))
 end
end)

local ambientPuzzleStatus = remotes:FindFirstChild("PuzzleStatus")
if ambientPuzzleStatus and ambientPuzzleStatus:IsA("RemoteEvent") then
 ambientPuzzleStatus.OnClientEvent:Connect(function(kind, active)
  if kind == "lever" and (tonumber(active) or 0) > 0 then
   ambientLeverPressureUntil = os.clock() + 12
   if ambientCanScare() then
    ambientNextAt = math.min(ambientNextAt, os.clock() + math.random(2, 4))
   end
  elseif kind == "exit" then
   ambientLeverPressureUntil = os.clock() + 20
  end
 end)
end

-- Studio test hook: set the local player's DevAmbientScare attribute to
-- knocks, lights or shadow (append any suffix to repeat one type).
if RunService:IsStudio() then
 player:GetAttributeChangedSignal("DevAmbientScare"):Connect(function()
  local raw = tostring(player:GetAttribute("DevAmbientScare") or ""):lower()
  local kind = raw:match("^(%a+)")
  if ambientScares[kind] then task.spawn(ambientTrigger, kind) end
 end)
end

task.spawn(function()
 while true do
  task.wait(0.75)
  if not ambientCanScare() then
   ambientNextAt = os.clock() + math.random(14, 22)
  elseif os.clock() >= ambientNextAt then
   ambientTrigger(ambientChooseKind())
   ambientNextAt = os.clock() + (ambientHighPressure() and math.random(7, 12) or math.random(22, 38))
  end
 end
end)

-- The entry client waits for the actual HUD bindings and listeners to exist.
player:SetAttribute("RoundEntryUIReady", true)

-- A failed reserved-server launch carries its category back to the lobby.
-- The attribute survives a join-time remote arriving before this script loads.
do
	local function restoreLoadingError()
		local reason = player:GetAttribute("RoundLoadingError")
		if reason == entryState.ErrorAttribute then return end
		entryState.ErrorAttribute = reason
		if type(reason) ~= "string" or reason == "" or entryState.Active then return end
		if entryState.ShowError(reason) then
			loadingRun += 1
			loadingFrame.Visible = false
		end
	end
	player:GetAttributeChangedSignal("RoundLoadingError"):Connect(restoreLoadingError)
	restoreLoadingError()
end
