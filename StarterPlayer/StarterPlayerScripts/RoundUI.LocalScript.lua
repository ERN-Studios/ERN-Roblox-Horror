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

function dispatchAudio.refresh()
	local loaded = dispatchAudio.preferenceLoaded()
	local muted = player:GetAttribute("ZyntraMuteDispatch") == true
	local active = dispatchAudio.hasActiveTransmission()
	-- Other level HUDs use this client-local authority to yield their screen
	-- space for the briefing, then restore themselves as soon as Command stops.
	if player:GetAttribute("ZyntraDispatchClientActive") ~= active then
		player:SetAttribute("ZyntraDispatchClientActive", active)
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
	-- C4A_BRIEFING_VS_QUEUE_20260829 -- WHAT SHIPPED BROKEN.
	-- The briefing panel and the queue host modal were two independent modals
	-- that knew nothing about each other, so both could be on screen at once. On
	-- touch this panel is pinned to UIDevice's TopBand -- (12,66) 517x75 on a
	-- 705x338 Galaxy A06 -- and it lives in LevelOneGuideGui at DisplayOrder 110
	-- while the queue shade is RoundGui at DisplayOrder 100: the briefing drew
	-- straight OVER an open party dialog, and its MUTE/STOP readouts took the
	-- taps that belonged to the modal underneath.
	--
	-- Queue and the full Zyntra terminal win, in BOTH directions, out of ONE
	-- expression: a briefing raised while either modal is up never draws, and a
	-- modal opened over a live briefing hides it. Nothing is torn down -- the
	-- transmission, its cue timer and ZyntraDispatchClientActive are untouched --
	-- so closing the modal brings the panel back mid-sentence.
	--
	-- `dispatchAudio.queueModalOpen` is mirrored from queueShade.Visible at the
	-- one property-changed signal that every show and every hide path already
	-- lands on, so a path that forgets to clear it is not expressible. It is a
	-- table field rather than a file local for two reasons: `queueShade` is
	-- declared hundreds of lines BELOW this function and is not in scope here,
	-- and this script sits on Luau's 200-local ceiling for its main chunk.
	local shown = (active or hasSubtitle)
		and dispatchAudio.queueModalOpen ~= true
		and player:GetAttribute("ZyntraStoreOpen") ~= true
	if dispatchAudio.panel then
		dispatchAudio.panel.Visible = shown
	end
	-- Published for ZyntraStore, whose lobby opener sits inside this same TopBand
	-- rectangle and has to stand down while the briefing owns it. Derived from
	-- `shown` -- the very value the panel itself is given -- so the flag and the
	-- pixels cannot drift apart, and it is cleared by that same expression on
	-- every path that lowers the panel.
	if player:GetAttribute("DispatchBriefingOpen") ~= shown then
		player:SetAttribute("DispatchBriefingOpen", shown)
	end
	if dispatchAudio.subtitleLabel then
		dispatchAudio.subtitleLabel.Text = hasSubtitle
			and dispatchAudio.subtitleCopy
			or active and "ESTABLISHING COMMAND LINK..."
			or ""
		dispatchAudio.subtitleLabel.TextColor3 = hasSubtitle
			and Color3.fromRGB(240, 242, 235)
			or Color3.fromRGB(127, 190, 169)
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
		local binding = UIDevice.Binding("[M]")
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
		dispatchAudio.button.Visible = active and shown
		dispatchAudio.button.TextTransparency = ready and 0 or .45
		UIDevice.SetEnabled(dispatchAudio.button, ready)
	end
	if dispatchAudio.stopButton then
		local stopBinding = UIDevice.Binding("[N]", "[B]")
		dispatchAudio.stopButton.TextColor3 = dispatchAudio.accent
		dispatchAudio.stopButton.Text = stopBinding ~= ""
			and (stopBinding .. "  STOP DISPATCH") or "STOP DISPATCH"
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
	if not dispatchAudio.hasActiveTransmission()
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

local function applyPlayerLighting()
 local inMaze = player:GetAttribute("InRound") == true
 local mazeGrade = Lighting:FindFirstChild("MongoGrade")
 local selectedLevel = workspace:GetAttribute("SelectedLevel")
 local levelTwoWorld = workspace:FindFirstChild("Level 2 Generated World")
 local levelThreeWorld = workspace:FindFirstChild("Level 3 Generated World")
 local isLevelTwo = levelTwoWorld ~= nil and (selectedLevel == 2 or inMaze)
 local isLevelThree = levelThreeWorld ~= nil and (selectedLevel == 3 or inMaze)

 if isLevelThree and workspace:GetAttribute("Level3LightingOwnedByController") == true then
  -- The dedicated mall controller owns and restores this grade. Never let the
  -- Level 1 darkness reassert itself over Level 3.
  lobbyGrade.Enabled = false
  if mazeGrade then mazeGrade.Enabled = false end
  return
 end

 if isLevelTwo and workspace:GetAttribute("Level2LightingOwnedByController") == true then
  lobbyGrade.Enabled = false
  if mazeGrade then mazeGrade.Enabled = false end
  return
 end


 if isLevelTwo then
  lobbyGrade.Enabled = false
  if mazeGrade then mazeGrade.Enabled = false end
  Lighting.ClockTime = 14
  Lighting.FogColor = Color3.fromRGB(216, 217, 195)
  Lighting.FogStart = 100000
  Lighting.FogEnd = 100000

  if levelTwoWorld:GetAttribute("ValveColorWashActive") == true then
   local valveColor = levelTwoWorld:GetAttribute("ValveColorWashColor")
   if typeof(valveColor) == "Color3" then
    Lighting.Brightness = 1.95
    Lighting.Ambient = Color3.fromRGB(92, 90, 78):Lerp(valveColor, .30)
    Lighting.OutdoorAmbient = Color3.fromRGB(102, 100, 88):Lerp(valveColor, .22)
    Lighting.ColorShift_Top = Color3.new(1, 1, 1):Lerp(valveColor, .42)
    Lighting.ColorShift_Bottom = valveColor:Lerp(Color3.new(0, 0, 0), .76)
    return
   end
  end

  Lighting.Ambient = Color3.fromRGB(92, 90, 78)
  Lighting.OutdoorAmbient = Color3.fromRGB(102, 100, 88)
  Lighting.Brightness = 1.75
  Lighting.ColorShift_Top = Color3.fromRGB(255, 246, 220)
  Lighting.ColorShift_Bottom = Color3.fromRGB(20, 29, 28)
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
queueCloseStroke.Color = Color3.fromRGB(255, 125, 125)
queueCloseStroke.Transparency = 0.35
local queueHint = queueText("CancelHint", "STEP OUT OF THE SQUARE TO CANCEL", UDim2.new(0.08, 0, 1, -23), UDim2.new(0.84, 0, 0, 16), 14, Color3.fromRGB(125, 137, 126))
queueHint.TextXAlignment = Enum.TextXAlignment.Center

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
  local area = queueLayout.ModalArea
  local queueWidth = math.floor(math.min(380, area.Width))
  -- One rule, not a max/min sandwich: the row stack below is 260px at its
  -- authored spacing and 251px packed, so ask for 280 and take whatever the
  -- area can actually give. The stack absorbs the difference either way.
  local queueHeight = math.floor(math.min(280, area.Height))
  queuePanel.AnchorPoint = Vector2.new(0, 0)
  queueConstraint.MinSize = Vector2.new(queueWidth, queueHeight)
  queueConstraint.MaxSize = Vector2.new(queueWidth, queueHeight)
  queuePanel.Size = UDim2.fromOffset(queueWidth, queueHeight)
  queuePanel.Position = UDim2.fromOffset(
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
    queueSubmit.Position = UDim2.new(0, 10, 0, y)
    queueSubmit.Size = UDim2.new(1, -20, 0, h)
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
  queueHint.Text = "STEP OUT OF THE SQUARE TO CANCEL"

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
    queueSubmit.Position = UDim2.new(0.10, 0, 0, y)
    queueSubmit.Size = UDim2.new(0.80, 0, 0, h)
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
 queueSubmit.Text = queueSubmitting and "CREATING PARTY..." or "CREATE PARTY"
 queueSubmit.Active = not queueSubmitting
 queueSubmit.AutoButtonColor = not queueSubmitting
 queueSubmit.BackgroundColor3 = queueSubmitting and Color3.fromRGB(42, 50, 44) or Color3.fromRGB(42, 105, 70)
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
queueSubmit.Activated:Connect(function()
 if queueSubmitting or not queueStation then return end
 queueSubmitting = true
 refreshQueuePanel()
 queueRemote:FireServer(queueStation, queueSizeValue, queuePrivacyValue)
 task.delay(3, function()
  if queueShade.Visible and queueSubmitting then
   queueSubmitting = false
   refreshQueuePanel()
  end
 end)
end)
queueClose.Activated:Connect(function()
 if queueSubmitting or not queueStation then return end
 local stationToCancel = queueStation
 queueShade.Visible = false
 queueStation = nil
 queueSubmitting = false
 refreshQueuePanel()
 queueRemote:FireServer(stationToCancel, 0, "cancel")
end)
refreshQueuePanel()

-- RoundUI is the sole cursor-policy owner. Lobby players need the mouse for the
-- queue phone and Zyntra store; gameplay hides it unless a modal is open.
-- `color`, the two action buttons and their shared list all belong to the
-- result screen and live here rather than as file locals: this script sits on
-- Luau's 200-local limit for a chunk's main body.
local completion = {returnVisible = false,
	color = Color3.fromRGB(115, 255, 170)}
local function shouldShowCursor()
 return player:GetAttribute("InRound") ~= true
  or queueShade.Visible
  or player:GetAttribute("DevPhoneOpen") == true
  or player:GetAttribute("ZyntraReentryOpen") == true
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
queueShade:GetPropertyChangedSignal("Visible"):Connect(function()
 player:SetAttribute("QueueModalOpen", queueShade.Visible)
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
refreshCursor()

-- An open modal must keep the pointer free. Ordinary lobby play deliberately
-- does not touch MouseBehavior here: Roblox uses its temporary right-button
-- lock to rotate the Classic camera while RMB is held.
RunService.RenderStepped:Connect(function()
 if UIS.MouseEnabled and (queueShade.Visible or player:GetAttribute("DevPhoneOpen") == true
  or player:GetAttribute("ZyntraReentryOpen") == true or completion.returnVisible) then
  UIS.MouseBehavior = Enum.MouseBehavior.Default
  UIS.MouseIconEnabled = true
 end
end)

-- The loading cover wears the colour of the level it is covering. Level 1 keeps
-- its terminal green. Level 2 uses the complex's own water blue — Status is
-- literally Configuration.Colors.Water from "Level 2 Configuration", and the
-- other three are luminance-matched to the greens they replace (within .007 of
-- relative luminance) so the screen reads with identical weight and contrast.
local LOADING_PALETTES = {
	[1] = {
		Background = Color3.fromRGB(3, 5, 4),
		Title = Color3.fromRGB(105, 230, 135),
		Status = Color3.fromRGB(65, 165, 90),
		TitleDone = Color3.fromRGB(125, 255, 155),
	},
	[2] = {
		Background = Color3.fromRGB(3, 6, 8),
		Title = Color3.fromRGB(105, 222, 238),
		Status = Color3.fromRGB(48, 150, 159),
		TitleDone = Color3.fromRGB(155, 244, 255),
	},
}
local function loadingPaletteFor(level)
	return LOADING_PALETTES[tonumber(level) or 0] or LOADING_PALETTES[1]
end

-- Immediate startup cover: the player sees this before a character or maze exists.
local loadingFrame = Instance.new("Frame")
loadingFrame.Name = "LevelLoading"
loadingFrame.Size = UDim2.fromScale(1, 1)
loadingFrame.BackgroundColor3 = Color3.fromRGB(3, 5, 4)
loadingFrame.BorderSizePixel = 0
loadingFrame.ZIndex = 100
loadingFrame.Visible = false -- the server lobby is visible first
loadingFrame.Parent = gui

local loadingTitle = Instance.new("TextLabel")
loadingTitle.AnchorPoint = Vector2.new(0.5, 0.5)
loadingTitle.Position = UDim2.new(0.5, 0, 0.46, 0)
loadingTitle.Size = UDim2.new(0.9, 0, 0, 78)
loadingTitle.BackgroundTransparency = 1
loadingTitle.Font = Enum.Font.Code
loadingTitle.TextSize = 45
loadingTitle.TextXAlignment = Enum.TextXAlignment.Center
loadingTitle.TextYAlignment = Enum.TextYAlignment.Center
loadingTitle.TextColor3 = Color3.fromRGB(105, 230, 135)
loadingTitle.Text = "> ENTERING LEVEL"
loadingTitle.ZIndex = 101
loadingTitle.Parent = loadingFrame

local loadingStatus = Instance.new("TextLabel")
loadingStatus.AnchorPoint = Vector2.new(0.5, 0.5)
loadingStatus.Position = UDim2.new(0.5, 0, 0.53, 0)
loadingStatus.Size = UDim2.new(0.9, 0, 0, 54)
loadingStatus.BackgroundTransparency = 1
loadingStatus.Font = Enum.Font.Code
loadingStatus.TextSize = 27
loadingStatus.TextXAlignment = Enum.TextXAlignment.Center
loadingStatus.TextYAlignment = Enum.TextYAlignment.Center
loadingStatus.TextColor3 = Color3.fromRGB(65, 165, 90)
loadingStatus.Text = "GENERATING LEVEL"
loadingStatus.ZIndex = 101
loadingStatus.Parent = loadingFrame

local activeLoadingPalette = loadingPaletteFor(1)
local function applyLoadingPalette(level)
	activeLoadingPalette = loadingPaletteFor(level)
	loadingFrame.BackgroundColor3 = activeLoadingPalette.Background
	loadingTitle.TextColor3 = activeLoadingPalette.Title
	loadingStatus.TextColor3 = activeLoadingPalette.Status
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
endFlash.BackgroundColor3 = Color3.fromRGB(105, 255, 165)
endFlash.BackgroundTransparency = 1
endFlash.BorderSizePixel = 0
endFlash.ZIndex = 121
endFlash.Parent = endFrame

local endLine = Instance.new("Frame")
endLine.Name = "SignalLine"
endLine.AnchorPoint = Vector2.new(0.5, 0.5)
endLine.Position = UDim2.fromScale(0.5, 0.56)
endLine.Size = UDim2.new(0, 0, 0, 2)
endLine.BackgroundColor3 = Color3.fromRGB(105, 255, 165)
endLine.BorderSizePixel = 0
endLine.ZIndex = 122
endLine.Parent = endFrame

local endTitle = Instance.new("TextLabel")
endTitle.Name = "EndingTitle"
endTitle.AnchorPoint = Vector2.new(0.5, 0.5)
endTitle.Position = UDim2.fromScale(0.5, 0.43)
endTitle.Size = UDim2.new(0.88, 0, 0.18, 0)
endTitle.BackgroundTransparency = 1
endTitle.Font = Enum.Font.GothamBlack
endTitle.Text = ("LEVEL " .. tostring(workspace:GetAttribute("SelectedLevel") or 1) .. " CLEARED")
endTitle.TextColor3 = Color3.fromRGB(115, 255, 170)
endTitle.TextScaled = true
endTitle.TextStrokeColor3 = Color3.new(0, 0, 0)
endTitle.TextStrokeTransparency = 0.35
endTitle.TextTransparency = 1
endTitle.TextWrapped = true
endTitle.ZIndex = 123
endTitle.Parent = endFrame
local endTitleSize = Instance.new("UITextSizeConstraint")
endTitleSize.MinTextSize = 24
endTitleSize.MaxTextSize = 62
endTitleSize.Parent = endTitle

local endStats = Instance.new("TextLabel")
endStats.Name = "EndingStats"
endStats.AnchorPoint = Vector2.new(0.5, 0.5)
endStats.Position = UDim2.fromScale(0.5, 0.63)
endStats.Size = UDim2.new(0.86, 0, 0, 44)
endStats.BackgroundTransparency = 1
endStats.Font = Enum.Font.Code
endStats.Text = "TIME 00:00  •  SURVIVORS 1/1"
endStats.TextColor3 = Color3.fromRGB(205, 235, 210)
endStats.TextSize = 25
endStats.TextTransparency = 1
endStats.TextWrapped = true
endStats.ZIndex = 123
endStats.Parent = endFrame

local endHint = Instance.new("TextLabel")
endHint.Name = "EndingHint"
endHint.AnchorPoint = Vector2.new(0.5, 0.5)
endHint.Position = UDim2.fromScale(0.5, 0.72)
endHint.Size = UDim2.new(0.86, 0, 0, 32)
endHint.BackgroundTransparency = 1
endHint.Font = Enum.Font.Code
endHint.Text = "RETURNING TO BASE"
endHint.TextColor3 = Color3.fromRGB(112, 145, 120)
endHint.TextSize = 17
endHint.TextTransparency = 1
endHint.TextWrapped = true
endHint.ZIndex = 123
endHint.Parent = endFrame

-- Two actions, built identically and laid out together so neither can drift.
-- Both are DIRECT children of endFrame rather than sitting inside a container:
-- UIRegression asserts the internal composition of RoundEnding, and a wrapper
-- frame would hide the two buttons from exactly the overlap test they most
-- need. Text is TextScaled between 11 and 18 so "BACK TO LOBBY" cannot spill
-- out of a narrow phone button.
do
local function makeCompletionButton(name, text)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(0.5, 0.83)
	button.Size = UDim2.fromOffset(240, 48)
	button.BackgroundColor3 = Color3.fromRGB(13, 37, 29)
	button.BackgroundTransparency = 0.08
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Active = false
	button.Selectable = false
	button.Modal = true
	button.Font = Enum.Font.GothamBold
	button.Text = text
	button.TextColor3 = Color3.fromRGB(130, 255, 184)
	button.TextScaled = true
	button.TextTransparency = 1
	button.Visible = false
	button.ZIndex = 124
	button.Parent = endFrame
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(105, 255, 165)
	stroke.Transparency = 0.28
	stroke.Thickness = 1.5
	stroke.Parent = button
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = button
	local textSize = Instance.new("UITextSizeConstraint")
	textSize.MinTextSize = 11
	textSize.MaxTextSize = 18
	textSize.Parent = button
	return button
end

completion.continueButton = makeCompletionButton("ContinueRun", "CONTINUE")
completion.button = makeCompletionButton("ReturnToLobby", "BACK TO LOBBY")
completion.buttons = {completion.continueButton, completion.button}
completion.continueButton:SetAttribute("CompletionAction", "continuenow")
completion.continueButton:SetAttribute("CompletionPressedText", "CONTINUING...")
completion.button:SetAttribute("CompletionAction", "returntolobby")
completion.button:SetAttribute("CompletionPressedText", "RETURNING...")
end

-- Which shape the result screen is wearing, and in what accent, so a viewport
-- or orientation change can re-measure the card without waiting for the next
-- result to arrive.
function completion.applyLayout(color)
 completion.color = color or completion.color
 endFrame.AnchorPoint = Vector2.new(0, 0)
 endFrame.Position = UDim2.fromScale(0, 0)
 endFrame.Size = UDim2.fromScale(1, 1)
 endFlash.Visible = true
 endLine.Visible = true

 endTitle.AnchorPoint = Vector2.new(0.5, 0.5)
 endTitle.Position = UDim2.fromScale(0.5, 0.43)
 endTitle.Size = UDim2.new(0.88, 0, 0.18, 0)
 endTitle.TextXAlignment = Enum.TextXAlignment.Center
 endTitle.TextWrapped = true
 -- Min BEFORE Max: a UITextSizeConstraint with Min > Max is invalid, and it
 -- throws out of showRoundEnding before the screen is ever shown.
 endTitleSize.MinTextSize = 24
 endTitleSize.MaxTextSize = 62

 -- Fixed 44px and 32px boxes at 0.63 and 0.72 of the height are 63px apart on
 -- a 720px screen and 32px apart on a 353px one, where the two boxes genuinely
 -- collided. The rows scale with the viewport so the stack stays separated.
 local deviceLayout = UIDevice.Layout()
 local viewportHeight = deviceLayout.Height
 local statsHeight = math.clamp(viewportHeight * .06, 22, 44)
 local hintHeight = math.clamp(viewportHeight * .045, 18, 32)

 endStats.AnchorPoint = Vector2.new(0.5, 0.5)
 endStats.Position = UDim2.fromScale(0.5, 0.63)
 endStats.Size = UDim2.new(0.86, 0, 0, statsHeight)
 endStats.TextSize = math.clamp(math.floor(statsHeight * .58), 14, 25)
 endStats.TextXAlignment = Enum.TextXAlignment.Center
 endStats.TextTruncate = Enum.TextTruncate.None

 endHint.AnchorPoint = Vector2.new(0.5, 0.5)
 endHint.Position = UDim2.fromScale(0.5, 0.72)
 endHint.Size = UDim2.new(0.86, 0, 0, hintHeight)
 endHint.TextSize = math.clamp(math.floor(hintHeight * .55), 12, 17)
 endHint.TextXAlignment = Enum.TextXAlignment.Center
 endHint.TextTruncate = Enum.TextTruncate.None

 -- The action row. One button is centred; two share a row, and fall back to a
 -- stack when the row would squeeze either below a comfortable tap size.
 -- UIListLayout is deliberately not used here: see makeCompletionButton.
 local visible = {}
 for _, button in ipairs(completion.buttons) do
  if button.Visible then table.insert(visible, button) end
 end
 if #visible == 0 then return end
 -- A phone in landscape is only ~375 tall, and .075 of that is 28px. The floor
 -- has to be the 44px minimum tap target on any touch device, or the result
 -- screen ships actions nobody can reliably hit.
 local buttonHeight = math.clamp(math.floor(viewportHeight * .075),
  deviceLayout.IsTouch and 44 or 40, 54)
 local gap = math.clamp(math.floor(viewportHeight * .022), 10, 18)
 local rowWidth = math.min(deviceLayout.Width * .86, 620)
 local paired = math.floor((rowWidth - gap) * .5)
 local stacked = #visible > 1 and paired < 168

 -- The row is positioned from the COUNTDOWN'S REAL BOTTOM EDGE, not from a
 -- fixed fraction of the height. A stacked pair anchored at .80 of a 390x844
 -- portrait overlapped the countdown by 11px, and by 19px at 375x667, because
 -- the two were laid out against the viewport independently and nothing ever
 -- compared them.
 local hintBottom = viewportHeight * .72 + hintHeight * .5
 local rowHeight = stacked and (buttonHeight * 2 + gap) or buttonHeight
 local bottomLimit = viewportHeight - rowHeight - 8
 local preferred = viewportHeight * (stacked and .80 or .83) - rowHeight * .5
 local rowTop = math.max(preferred, hintBottom + gap)
 if rowTop > bottomLimit then
  -- Not enough room for the full gap. Keep the row on screen and take the
  -- separation down to whatever is left, never below zero.
  rowTop = math.max(bottomLimit, math.min(rowTop, hintBottom + 2))
 end

 if #visible == 1 then
  local width = math.clamp(math.floor(rowWidth * .55), 180, 340)
  visible[1].Size = UDim2.fromOffset(width, buttonHeight)
  visible[1].Position = UDim2.fromOffset(
   math.floor(deviceLayout.Width * .5), math.floor(rowTop + buttonHeight * .5))
 elseif stacked then
  local width = math.clamp(math.floor(rowWidth), 160, 340)
  local centreX = math.floor(deviceLayout.Width * .5)
  visible[1].Size = UDim2.fromOffset(width, buttonHeight)
  visible[1].Position = UDim2.fromOffset(centreX, math.floor(rowTop + buttonHeight * .5))
  visible[2].Size = UDim2.fromOffset(width, buttonHeight)
  visible[2].Position = UDim2.fromOffset(centreX,
   math.floor(rowTop + buttonHeight + gap + buttonHeight * .5))
 else
  -- Side by side, symmetrical about the centre.
  local offset = math.floor((paired + gap) * .5)
  local centreX = math.floor(deviceLayout.Width * .5)
  local centreY = math.floor(rowTop + buttonHeight * .5)
  visible[1].Size = UDim2.fromOffset(paired, buttonHeight)
  visible[1].Position = UDim2.fromOffset(centreX - offset, centreY)
  visible[2].Size = UDim2.fromOffset(paired, buttonHeight)
  visible[2].Position = UDim2.fromOffset(centreX + offset, centreY)
 end
end

-- The layout is viewport-dependent, so a resize or an orientation change
-- re-measures it.
UIDevice.Changed:Connect(function()
 if endFrame.Visible then completion.applyLayout(completion.color) end
end)

local spectateBanner = Instance.new("TextLabel")
spectateBanner.Name = "SpectateBanner"
spectateBanner.AnchorPoint = Vector2.new(0.5, 1)
spectateBanner.Position = UDim2.new(0.5, 0, 1, -28)
spectateBanner.Size = UDim2.new(0.72, 0, 0, 42)
spectateBanner.BackgroundColor3 = Color3.fromRGB(3, 7, 5)
spectateBanner.BackgroundTransparency = 0.30
spectateBanner.BorderSizePixel = 0
spectateBanner.Font = Enum.Font.Code
spectateBanner.Text = "SPECTATING  •  SEARCHING FOR SIGNAL"
spectateBanner.TextColor3 = Color3.fromRGB(115, 255, 170)
spectateBanner.TextSize = 20
spectateBanner.TextWrapped = true
spectateBanner.Visible = false
spectateBanner.ZIndex = 118
spectateBanner.Parent = gui
local spectateCorner = Instance.new("UICorner")
spectateCorner.CornerRadius = UDim.new(0, 7)
spectateCorner.Parent = spectateBanner

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
local spectateTarget = nil
local spectateClock = 0

local function formatRoundTime(seconds)
 local total = math.max(0, math.floor(tonumber(seconds) or 0))
 return string.format("%02d:%02d", math.floor(total / 60), total % 60)
end

function completion.reset()
	completion.deadline = nil
	completion.nextLevel = nil
	completion.serverSerial = nil
	completion.pending = false
	completion.returnVisible = false
	completion.continueButton.Text = "CONTINUE"
	completion.button.Text = "BACK TO LOBBY"
	for _, button in ipairs(completion.buttons) do
		button.Visible = false
		button.Active = false
		button.Selectable = false
		button.TextTransparency = 1
	end
	refreshCursor()
end

-- `nextLevel` is the server's decision, and it is the ONLY thing that puts a
-- Continue action on screen. The last level reports no next level, so it shows
-- Back to Lobby alone and cannot route anyone to a level that does not exist.
function completion.start(deadline, nextLevel, serverSerial)
	completion.deadline = tonumber(deadline) or (workspace:GetServerTimeNow() + 15)
	completion.nextLevel = tonumber(nextLevel)
	completion.serverSerial = tonumber(serverSerial)
	completion.pending = false
	completion.returnVisible = completion.serverSerial ~= nil
	completion.continueButton.Text = "CONTINUE"
	completion.button.Text = "BACK TO LOBBY"
	completion.continueButton.Visible = completion.returnVisible
		and completion.nextLevel ~= nil
	completion.button.Visible = completion.returnVisible
	for _, button in ipairs(completion.buttons) do
		button.Active = button.Visible
		button.Selectable = button.Visible
		button.TextTransparency = 1
		if button.Visible then
			TweenService:Create(button, TweenInfo.new(0.35), {TextTransparency = 0}):Play()
		end
	end
	-- Re-measure: the row is one button wide on the last level and two on every
	-- other, and start() is what decides which.
	if endFrame.Visible then completion.applyLayout(completion.color) end
	refreshCursor()
end

-- One handler for both actions. Which remote message a button sends is read
-- from the button itself, so the wiring is inspectable state rather than two
-- separate closures that can quietly be swapped.
function completion.activate(button)
	if completion.pending or not completion.returnVisible or not completion.serverSerial then
		return false
	end
	if not button.Visible or not button.Active then return false end
	local action = button:GetAttribute("CompletionAction")
	if type(action) ~= "string" then return false end
	-- Continue cannot route past the last level: the server sends no next level
	-- there, and this is the second, client-side guard on the same rule.
	if action == "continuenow" and completion.nextLevel == nil then return false end
	completion.pending = true
	for _, other in ipairs(completion.buttons) do
		other.Active = false
		other.Selectable = false
	end
	button.Text = button:GetAttribute("CompletionPressedText") or button.Text
	-- The server advances as soon as every remaining player has chosen; the
	-- countdown stays as the backstop for anyone who never presses anything.
	remote:FireServer(action, completion.serverSerial)
	return true
end

for _, completionButton in ipairs(completion.buttons) do
	completionButton.Activated:Connect(function()
		completion.activate(completionButton)
	end)
end

RunService.RenderStepped:Connect(function()
	if not completion.deadline or not endFrame.Visible then return end
	local remaining = math.max(0, math.ceil(completion.deadline - workspace:GetServerTimeNow()))
	if completion.nextLevel then
		endHint.Text = remaining > 0
			and ("LEVEL " .. tostring(completion.nextLevel) .. " BEGINS IN " .. tostring(remaining))
			or ("ENTERING LEVEL " .. tostring(completion.nextLevel))
	else
		endHint.Text = remaining > 0
			and ("RETURNING TO LOBBY IN " .. tostring(remaining))
			or "RETURNING TO LOBBY"
	end
	if remaining <= 0 then
		for _, button in ipairs(completion.buttons) do
			button.Active = false
			button.Selectable = false
		end
	end
end)

local function validSpectateTarget(candidate)
 if not candidate or candidate == player or candidate.Parent ~= Players then return false end
 if candidate:GetAttribute("InRound") ~= true or candidate:GetAttribute("Escaped") == true then return false end
 local character = candidate.Character
 local humanoid = character and character:FindFirstChildOfClass("Humanoid")
 return humanoid ~= nil and humanoid.Health > 0
end

local function chooseSpectateTarget()
 for _, candidate in ipairs(Players:GetPlayers()) do
  if validSpectateTarget(candidate) then return candidate end
 end
 return nil
end

local function updateSpectating()
 if not spectating then return end
 if not validSpectateTarget(spectateTarget) then spectateTarget = chooseSpectateTarget() end
 local camera = workspace.CurrentCamera
 if spectateTarget and camera then
  local humanoid = spectateTarget.Character and spectateTarget.Character:FindFirstChildOfClass("Humanoid")
  if humanoid then
   camera.CameraType = Enum.CameraType.Custom
   camera.CameraSubject = humanoid
   spectateBanner.Text = "SPECTATING  •  " .. string.upper(spectateTarget.DisplayName)
  end
 else
  spectateBanner.Text = "SPECTATING  •  NO SURVIVING SIGNAL"
 end
end

local function startSpectating()
 spectating = true
 spectateTarget = nil
 -- The banner stays hidden: SpectateController owns the on-screen spectate
 -- label, and showing this one too stacked two "no surviving signal"
 -- messages on top of each other.
 updateSpectating()
end

local function stopSpectating()
 spectating = false
 spectateTarget = nil
 spectateBanner.Visible = false
 local camera = workspace.CurrentCamera
 local character = player.Character
 local humanoid = character and character:FindFirstChildOfClass("Humanoid")
 if camera then
  camera.CameraType = Enum.CameraType.Custom
  if humanoid then camera.CameraSubject = humanoid end
 end
end

RunService.RenderStepped:Connect(function(dt)
 if not spectating then return end
 spectateClock += dt
 if spectateClock >= 0.35 then
  spectateClock = 0
  updateSpectating()
 end
end)

-- Emergency Re-entry loads a fresh gameplay character without firing any
-- round status event, so the death/spectate state must clear on the new
-- body itself — otherwise the spectate banner outlives the revival.
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
  endFrame.BackgroundTransparency = 1
  endFlash.BackgroundTransparency = 1
  return
 end
 TweenService:Create(endFrame, TweenInfo.new(0.42), {BackgroundTransparency = 1}):Play()
 TweenService:Create(endTitle, TweenInfo.new(0.28), {TextTransparency = 1, TextStrokeTransparency = 1}):Play()
 TweenService:Create(endStats, TweenInfo.new(0.25), {TextTransparency = 1}):Play()
 TweenService:Create(endHint, TweenInfo.new(0.25), {TextTransparency = 1}):Play()
 TweenService:Create(endLine, TweenInfo.new(0.3), {BackgroundTransparency = 1}):Play()
 task.delay(0.46, function()
  if endingSerial == token then endFrame.Visible = false end
 end)
end

local function showRoundEnding(title, stats, hint, color, temporary)
 completion.reset()
 endingSerial += 1
 local token = endingSerial
 color = color or Color3.fromRGB(115, 255, 170)
 completion.applyLayout(color)
 loadingFrame.Visible = false
 queueShade.Visible = false
 label.Visible = false
 endFrame.Visible = true
 endFrame.BackgroundTransparency = 1
 endFlash.BackgroundColor3 = color
 endFlash.BackgroundTransparency = 0.08
 endTitle.Text = title
 endTitle.TextColor3 = color
 endTitle.TextTransparency = 1
 endTitle.TextStrokeTransparency = 1
 endStats.Text = stats or ""
 endStats.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.68)
 endStats.TextTransparency = 1
 endHint.Text = hint or ""
 endHint.TextTransparency = 1
 endLine.BackgroundColor3 = color
 endLine.BackgroundTransparency = 0
 endLine.Size = UDim2.new(0, 0, 0, 2)

 exitThud:Stop()
 exitChime:Stop()
 exitThud.TimePosition = 0
 exitChime.TimePosition = 0
 exitThud:Play()
 task.delay(0.12, function() if endFrame.Visible then exitChime:Play() end end)
 TweenService:Create(endFlash, TweenInfo.new(0.7, Enum.EasingStyle.Quad), {BackgroundTransparency = 1}):Play()
 TweenService:Create(endFrame, TweenInfo.new(0.42, Enum.EasingStyle.Quad),
  {BackgroundTransparency = 0.08}):Play()
 TweenService:Create(endTitle, TweenInfo.new(0.48), {TextTransparency = 0, TextStrokeTransparency = 0.35}):Play()
 TweenService:Create(endStats, TweenInfo.new(0.42), {TextTransparency = 0}):Play()
 TweenService:Create(endHint, TweenInfo.new(0.55), {TextTransparency = 0}):Play()
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
   showRoundEnding(("LEVEL " .. tostring(workspace:GetAttribute("SelectedLevel") or 1) .. " CLEARED"), "SIGNAL LOST", "WAITING FOR THE OTHERS", Color3.fromRGB(115, 255, 170), true)
	-- "winfinal" is tested BEFORE "win": find() is a substring match and the
	-- final-level mode would otherwise be swallowed by the ordinary one.
	elseif mode:find("winfinal", 1, true) then
		-- The last level: no next level exists, so no Continue action does either.
		showRoundEnding(("LEVEL " .. tostring(workspace:GetAttribute("SelectedLevel") or 3) .. " CLEARED"), "TIME 05:08  •  SURVIVORS 2/3", "RETURNING TO BASE", Color3.fromRGB(115, 255, 170), false)
		completion.start(workspace:GetServerTimeNow() + 15, nil, -1)
	elseif mode:find("win", 1, true) then
		showRoundEnding(("LEVEL " .. tostring(workspace:GetAttribute("SelectedLevel") or 1) .. " CLEARED"), "TIME 03:42  •  SURVIVORS 2/3", "RETURNING TO BASE", Color3.fromRGB(115, 255, 170), false)
		-- Exercise the complete production win state in UIRegression: the overlay
		-- is not valid unless its countdown and BOTH actions are present too. A
		-- negative serial is intentionally Studio-only.
		completion.start(workspace:GetServerTimeNow() + 15, 2, -1)
  elseif mode:find("lose", 1, true) then
   showRoundEnding("NO ONE FOUND A WAY OUT", "TIME 04:17  •  SURVIVORS 0/3", "RETURNING TO BASE", Color3.fromRGB(255, 82, 72), false)
  elseif mode:find("hide", 1, true) then
   hideRoundEnding(true)
  end
 end)
end

local loadingSequenceFinished = false
local serverReadyForEntry = false
local loadingClock = 0
local loadingBaseText = "LOCATING ANOMALOUS SPACE"

RunService.RenderStepped:Connect(function(dt)
	if not loadingFrame.Visible then return end
	loadingClock += dt
	local dots = string.rep(".", math.floor(loadingClock * 2) % 4)
	loadingStatus.Text = loadingBaseText .. dots
end)

-- Set only on the level that holds its own cover, so the server can be told
-- when this client is genuinely looking at the world instead of a guess.
local entryAckPending = false

local function finishLoadingWhenReady()
	if not (loadingSequenceFinished and serverReadyForEntry) then return end
	if loadingFrame.Visible then loadingFrame.Visible = false end
	if entryAckPending then
		entryAckPending = false
		remote:FireServer("entryready")
	end
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
		for _, stage in ipairs(stages) do
			if loadingRun ~= run then return end
			loadingBaseText = stage
			loadingClock = 0
			task.wait(1.35)
		end
		if loadingRun ~= run then return end

		loadingTitle.Text = "> ENTRY STABILIZED SUCCESSFULLY"
		loadingTitle.TextColor3 = activeLoadingPalette.TitleDone
		loadingBaseText = "MISSION IS A GO"
		loadingClock = 0
		task.wait(1.6)
		if loadingRun ~= run then return end
		loadingSequenceFinished = true
		finishLoadingWhenReady()
	end)
end

startLoadingSequence()

-- Level 2 has no elevator ride to hide the stream-in behind, so its cover has to
-- stay up until the complex is actually around the character. Solid ground under
-- the root is the honest test — it is the very thing the server's anchored
-- placement protects against, and it cannot pass while the arrival platform is
-- still streaming. The timeout exists so a client that never streams is let in
-- anyway rather than trapped behind the cover forever.
local LEVEL_TWO_ENTRY_TIMEOUT = 15

local function levelTwoGroundReady()
	if not workspace:FindFirstChild("Level 2 Generated World") then return false end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {character}
	return workspace:Raycast(root.Position + Vector3.yAxis * 5,
		Vector3.new(0, -60, 0), params) ~= nil
end

local function waitForLevelTwoEntry()
	local deadline = os.clock() + LEVEL_TWO_ENTRY_TIMEOUT
	local requestedStream = false
	while os.clock() < deadline do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and not requestedStream then
			requestedStream = true
			task.spawn(function()
				pcall(function()
					player:RequestStreamAroundAsync(root.Position, 10)
				end)
			end)
		end
		if levelTwoGroundReady() then return true end
		task.wait(0.15)
	end
	return false
end

local DEFAULT_TEXT = Color3.fromRGB(235, 232, 222)
local DEFAULT_SIZE = 26
local DEFAULT_FONT = Enum.Font.GothamMedium
local COMPACT_SIZE = UDim2.new(0, 620, 0, 48)

local function setMsg(text, color)
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

-- Level 1 command briefing. This replaces the old typed objective sequence and
-- uses its own subtitle layer so the shared lobby/status label stays available.
local LEVEL_ONE_BRIEFING_ID = "rbxassetid://110249611823719"
local LEVEL_ONE_RADIO_CUE_ID = "rbxassetid://73198577463663"
local LEVEL_ONE_BRIEFING_DELAY = 2.5 -- radio cue leads in; speech still begins about 2.5s after placement
local LEVEL_TWO_BRIEFING_ID = "rbxassetid://139075030898721"
local LEVEL_TWO_RADIO_CUE_ID = "rbxassetid://121765399252460"
local LEVEL_TWO_BRIEFING_DELAY = 2.5 -- measured from the moment the Poolrooms cover clears
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
dispatchAudio.controls.Parent = subtitleFrame

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
		or not dispatchAudio.hasActiveTransmission() then
		return Enum.ContextActionResult.Pass
	end
	return dispatchAudio.requestToggle()
		and Enum.ContextActionResult.Sink
		or Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.M)

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
		or not dispatchAudio.hasActiveTransmission() then
		return Enum.ContextActionResult.Pass
	end
	return dispatchAudio.requestStop()
		and Enum.ContextActionResult.Sink
		or Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.N, Enum.KeyCode.ButtonB)
dispatchAudio.refresh()

local objectivesButton = Instance.new("TextButton")
objectivesButton.Name = "ObjectivesButton"
objectivesButton.Position = UDim2.fromOffset(12, 12)
objectivesButton.Size = UDim2.fromOffset(154, 44)
objectivesButton.BackgroundColor3 = Color3.fromRGB(8, 14, 9)
objectivesButton.BackgroundTransparency = 0.12
objectivesButton.BorderSizePixel = 0
objectivesButton.AutoButtonColor = true
objectivesButton.Active = true
objectivesButton.Selectable = true
objectivesButton.Font = Enum.Font.Code
objectivesButton.Text = UIS.TouchEnabled and "OBJECTIVES" or "OBJECTIVES  [H]"
objectivesButton.TextColor3 = Color3.fromRGB(120, 255, 175)
objectivesButton.TextSize = 16
objectivesButton.Visible = false
objectivesButton.ZIndex = 30
objectivesButton.Parent = guideGui
roundAndStroke(objectivesButton, 8, Color3.fromRGB(105, 238, 168), 0.27, 1.5)

local objectivesPanel = Instance.new("Frame")
objectivesPanel.Name = "ObjectivesPanel"
objectivesPanel.Position = UDim2.fromOffset(12, 64)
objectivesPanel.Size = UDim2.fromOffset(420, 338)
objectivesPanel.BackgroundColor3 = Color3.fromRGB(8, 14, 9)
objectivesPanel.BackgroundTransparency = 0.06
objectivesPanel.BorderSizePixel = 0
objectivesPanel.Active = true
objectivesPanel.Visible = false
objectivesPanel.ZIndex = 30
objectivesPanel.Parent = guideGui
roundAndStroke(objectivesPanel, 10, Color3.fromRGB(105, 238, 168), 0.27, 1.5)

local objectivesTitle = Instance.new("TextLabel")
objectivesTitle.Name = "Title"
objectivesTitle.Position = UDim2.fromOffset(16, 10)
objectivesTitle.Size = UDim2.new(1, -68, 0, 32)
objectivesTitle.BackgroundTransparency = 1
objectivesTitle.Font = Enum.Font.Code
objectivesTitle.Text = "> LEVEL 1 — ESCAPE PROCEDURE"
objectivesTitle.TextColor3 = Color3.fromRGB(120, 255, 175)
objectivesTitle.TextSize = 18
objectivesTitle.TextXAlignment = Enum.TextXAlignment.Left
objectivesTitle.ZIndex = 31
objectivesTitle.Parent = objectivesPanel

local objectivesClose = Instance.new("TextButton")
objectivesClose.Name = "Close"
objectivesClose.AnchorPoint = Vector2.new(1, 0)
objectivesClose.Position = UDim2.new(1, -8, 0, 6)
objectivesClose.Size = UDim2.fromOffset(40, 40)
objectivesClose.BackgroundTransparency = 1
objectivesClose.Font = Enum.Font.GothamBold
objectivesClose.Text = "×"
objectivesClose.TextColor3 = Color3.fromRGB(218, 237, 223)
objectivesClose.TextSize = 26
objectivesClose.ZIndex = 32
objectivesClose.Parent = objectivesPanel

local objectivesDivider = Instance.new("Frame")
objectivesDivider.Name = "Divider"
objectivesDivider.Position = UDim2.fromOffset(16, 50)
objectivesDivider.Size = UDim2.new(1, -32, 0, 1)
objectivesDivider.BackgroundColor3 = Color3.fromRGB(105, 238, 168)
objectivesDivider.BackgroundTransparency = 0.45
objectivesDivider.BorderSizePixel = 0
objectivesDivider.ZIndex = 31
objectivesDivider.Parent = objectivesPanel

local objectivesBody = Instance.new("ScrollingFrame")
objectivesBody.Name = "NumberedObjectives"
objectivesBody.Position = UDim2.fromOffset(14, 60)
objectivesBody.Size = UDim2.new(1, -28, 1, -72)
objectivesBody.BackgroundTransparency = 1
objectivesBody.BorderSizePixel = 0
objectivesBody.CanvasSize = UDim2.new()
objectivesBody.AutomaticCanvasSize = Enum.AutomaticSize.Y
objectivesBody.ScrollBarThickness = 3
objectivesBody.ScrollBarImageColor3 = Color3.fromRGB(105, 238, 168)
objectivesBody.ScrollingDirection = Enum.ScrollingDirection.Y
objectivesBody.ZIndex = 31
objectivesBody.Parent = objectivesPanel

local objectivesLayout = Instance.new("UIListLayout")
objectivesLayout.Padding = UDim.new(0, 8)
objectivesLayout.SortOrder = Enum.SortOrder.LayoutOrder
objectivesLayout.Parent = objectivesBody

local objectiveCopy = {
	"Find a group of unusually bright ceiling lights. A fuse relay is nearby.",
	"Interact with the relay to extract its fuse.",
	"Follow the colored cables. Each circuit connects one fuse box to one lever, but the cable does not identify which end is which.",
	"Insert one fuse into every fuse box.",
	"After every box is powered, activate all levers within 10 seconds.",
	"Follow the energy reader to the powered exit door.",
	"Keep away from the entity. Do not engage.",
}

for index, copy in ipairs(objectiveCopy) do
	local row = Instance.new("Frame")
	row.Name = "Objective" .. index
	row.Size = UDim2.new(1, -4, 0, 0)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.BackgroundTransparency = 1
	row.LayoutOrder = index
	row.ZIndex = 31
	row.Parent = objectivesBody

	local number = Instance.new("TextLabel")
	number.Name = "Number"
	number.Size = UDim2.fromOffset(28, 22)
	number.BackgroundTransparency = 1
	number.Font = Enum.Font.Code
	number.Text = tostring(index) .. "."
	number.TextColor3 = index == #objectiveCopy
		and Color3.fromRGB(235, 220, 150)
		or Color3.fromRGB(120, 255, 175)
	number.TextSize = 15
	number.TextXAlignment = Enum.TextXAlignment.Left
	number.TextYAlignment = Enum.TextYAlignment.Top
	number.ZIndex = 32
	number.Parent = row

	local description = Instance.new("TextLabel")
	description.Name = "Description"
	description.Position = UDim2.fromOffset(28, 0)
	description.Size = UDim2.new(1, -32, 0, 0)
	description.AutomaticSize = Enum.AutomaticSize.Y
	description.BackgroundTransparency = 1
	description.Font = Enum.Font.Code
	description.Text = copy
	description.TextColor3 = index == #objectiveCopy
		and Color3.fromRGB(235, 220, 150)
		or Color3.fromRGB(218, 237, 223)
	description.TextSize = 14
	description.TextWrapped = true
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.ZIndex = 32
	description.Parent = row
end

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
levelOneRadioCue.Volume = 1
levelOneRadioCue.Looped = false
levelOneRadioCue.SoundGroup = dispatchAudio.group
levelOneRadioCue.Parent = guideGui

local levelTwoBriefingSound = Instance.new("Sound")
levelTwoBriefingSound.Name = "LevelTwoCommandBriefing"
levelTwoBriefingSound.SoundId = LEVEL_TWO_BRIEFING_ID
levelTwoBriefingSound.Volume = 1
levelTwoBriefingSound.Looped = false
levelTwoBriefingSound.SoundGroup = dispatchAudio.group
levelTwoBriefingSound.Parent = guideGui

local levelTwoRadioCue = Instance.new("Sound")
levelTwoRadioCue.Name = "LevelTwoRadioOpen"
levelTwoRadioCue.SoundId = LEVEL_TWO_RADIO_CUE_ID
levelTwoRadioCue.Volume = 1
levelTwoRadioCue.Looped = false
levelTwoRadioCue.SoundGroup = dispatchAudio.group
levelTwoRadioCue.Parent = guideGui

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
levelThreeBriefing.radio.Volume = 1
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
lobbyBriefing.radio.Volume = 1
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
	{20.78, 25.86, "Power every fuse box first. Then, activate all levers within ten seconds."},
	{25.86, 31.19, "Be advised... we are detecting movement inside the space that does not match your team."},
	{31.19, 33.88, "We know nothing about the entity responsible."},
	{33.88, 36.91, "If you see or hear anything unusual, stay alert."},
	{36.91, 39.98, "Keep your distance... and do not engage."},
	{39.98, 44.24, "Once the exit door is powered on, your energy reader will guide you to it."},
	{44.24, 45.61, "Good luck, Team Alpha."},
	{45.61, 47.10, "Command Center, over and out."},
}

local levelTwoBriefingCues = {
	{0.00, 4.70, "Team Alpha, this is Command Center. Stand by for briefing."},
	{4.70, 7.55, "Good work making it safely to Level Two."},
	{7.55, 12.20, "This space appears to contain three inactive pump stations. Locate and activate all three."},
	{12.20, 17.10, "Be advised... we have detected poolfoam-like entities near what appear to be children's play areas."},
	{17.10, 18.65, "Avoid close contact."},
	{18.65, 25.00, "Even more important: activating a pump appears to alert an unidentified, unusually large entity to your location."},
	{25.00, 26.65, "Once a pump is running, move quickly."},
	{26.65, 31.10, "After all three pumps are active, the main pool chamber should unlock."},
	{31.10, 33.45, "Enter it, reach the upper floor, and locate the exit tube."},
	{33.45, 37.75, "At that point... assume the entity knows where you are—and where you are headed."},
	{37.75, 39.00, "Stay alert."},
	{39.00, 41.30, "And I repeat: do not stop moving."},
	{41.30, 42.55, "Good luck, Team Alpha."},
	{42.55, 44.13, "Command Center, over and out."},
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
local objectivesAvailable = false
local levelTwoBriefingRun = 0
local levelTwoBriefingPreloaded = false
local levelTwoBriefingStarted = false
player:SetAttribute("LevelOneBriefingActive", false)
player:SetAttribute("LevelTwoBriefingActive", false)
player:SetAttribute("LevelThreeBriefingActive", false)
player:SetAttribute("LobbyBriefingActive", false)
player:SetAttribute("LobbyBriefingPlayed", false)
player:SetAttribute("LobbyBriefingSkipped", false)
player:SetAttribute("LevelOneGuideObjectivesOpen", nil)

local function isLevelOneParticipant()
	return workspace:GetAttribute("SelectedLevel") == 1
		and player:GetAttribute("InRound") == true
		and player:GetAttribute("Escaped") ~= true
		and not dead
end

-- The one rule for whether the OBJECTIVES button is on screen.
--
-- On touch the panel takes UIDevice's whole safe band, which begins above the
-- button; the panel is Active, so wherever they overlap the button stops
-- responding to the tap that would close it. They are alternatives rather than
-- companions -- the panel carries its own Close -- so the button stands down
-- while the panel is up. Its published state also lets PuzzleUI yield its
-- lower-right counter stack while this larger help panel owns that corner.
local function refreshObjectivesButton()
	local panelOpen = objectivesAvailable and objectivesPanel.Visible
	local published = panelOpen and true or nil
	if player:GetAttribute("LevelOneGuideObjectivesOpen") ~= published then
		player:SetAttribute("LevelOneGuideObjectivesOpen", published)
	end
	if not objectivesAvailable then
		objectivesButton.Visible = false
		return
	end
	objectivesButton.Visible = not (UIDevice.IsTouch() and objectivesPanel.Visible)
end

local function setObjectivesAvailable(available)
	objectivesAvailable = available == true
	if not objectivesAvailable then
		objectivesPanel.Visible = false
	end
	refreshObjectivesButton()
end

local function setSubtitle(text)
	dispatchAudio.subtitleCopy = text or ""
	dispatchAudio.refresh()
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
		ContentProvider:PreloadAsync({lobbyBriefing.radio, lobbyBriefing.sound})
	end)
	lobbyBriefing.preloaded = ok
		and lobbyBriefing.radio.IsLoaded
		and lobbyBriefing.sound.IsLoaded
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
	if lobbyBriefing.played or not lobbyBriefing.isEligible() then return end
	lobbyBriefing.played = true
	lobbyBriefing.pending = true
	player:SetAttribute("LobbyBriefingSkipped", false)
	lobbyBriefing.run += 1
	local run = lobbyBriefing.run
	player:SetAttribute("LobbyBriefingPlayed", true)
	player:SetAttribute("LobbyBriefingActive", false)

	task.spawn(function()
		dispatchAudio.awaitPreference()
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
		player:SetAttribute("LobbyBriefingActive", true)
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
		local played = pcall(function() lobbyBriefing.sound:Play() end)
		if not played then
			if run == lobbyBriefing.run then lobbyBriefing.cancel() end
			return
		end

		local currentText = nil
		local playbackStarted = lobbyBriefing.sound.IsPlaying
		local playbackStartDeadline = os.clock() + 4
		local deadline = os.clock() + 50
		while run == lobbyBriefing.run
			and lobbyBriefing.isEligible()
			and os.clock() < deadline do
			local position = lobbyBriefing.sound.TimePosition
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
			if lobbyBriefing.sound.IsPlaying then
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
		ContentProvider:PreloadAsync({levelOneRadioCue, levelOneBriefingSound})
	end)
	briefingPreloaded = ok and levelOneRadioCue.IsLoaded and levelOneBriefingSound.IsLoaded
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
	if hideObjectives then
		setObjectivesAvailable(false)
	end
end

local function toggleObjectives()
	if objectivesAvailable and isLevelOneParticipant() then
		objectivesPanel.Visible = not objectivesPanel.Visible
	else
		objectivesPanel.Visible = false
	end
	refreshObjectivesButton()
end

objectivesButton.Activated:Connect(toggleObjectives)
objectivesClose.Activated:Connect(function()
	objectivesPanel.Visible = false
	refreshObjectivesButton()
end)
local OBJECTIVES_ACTION = "ToggleObjectiveHelp"
ContextActionService:UnbindAction(OBJECTIVES_ACTION)
ContextActionService:BindActionAtPriority(
	OBJECTIVES_ACTION,
	function(_, inputState)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		-- Availability, not button visibility: on touch the button hides itself
		-- while the panel is open, and gating on it would make the binding a
		-- one-way door that could open the panel but never close it.
		if UIS:GetFocusedTextBox() or not objectivesAvailable then
			return Enum.ContextActionResult.Pass
		end
		toggleObjectives()
		return Enum.ContextActionResult.Sink
	end,
	false,
	Enum.ContextActionPriority.High.Value,
	Enum.KeyCode.H
)

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
	for _, set in ipairs({briefingCues, levelTwoBriefingCues, levelThreeBriefing.cues, lobbyBriefing.cues}) do
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
dispatchAudio.faceThatFits = function(ceiling, width, height)
	-- 9/8 are emergency rungs used only when an ultra-short landscape safe band
	-- leaves 24px under two mandatory 44px touch targets. They keep the full cue
	-- inside its label instead of drawing across the controls or movement zone.
	local faces = {20, 16, 13, 12, 11, 10, 9, 8}
	for _, size in ipairs(faces) do
		if size <= ceiling then
			local needed = game:GetService("TextService"):GetTextSize(
				dispatchAudio.fitProbe, size, subtitleText.Font,
				Vector2.new(width, 100000))
			if needed.Y <= height then return size end
		end
	end
	return faces[#faces]
end

local function updateLevelOneGuideLayout()
	local layout = UIDevice.Layout()
	local viewport = layout.Viewport
	local narrow = layout.Narrow
	local touch = layout.IsTouch

	-- A touch target never goes under 44px, whatever the narrow layout does to
	-- the rest of the panel. The narrow branch used to shrink OBJECTIVES to
	-- 140x40 and the panel's close button was 40x40 everywhere, which is under
	-- the floor on exactly the devices that need it most. Desktop keeps its
	-- original compact sizes; nothing here grows a mouse-driven control.
	local touchFloor = touch and 44 or nil
	objectivesButton.Size = narrow
		and UDim2.fromOffset(140, touchFloor or 40)
		or UDim2.fromOffset(154, 44)
	objectivesButton.TextSize = narrow and 14 or 16
	objectivesButton.Text = UIDevice.Caption("OBJECTIVES", "[H]")
	objectivesClose.Size = UDim2.fromOffset(touchFloor or 40, touchFloor or 40)
	if touch then
		objectivesButton.AnchorPoint = Vector2.new(0, 0)
		objectivesButton.Position = UDim2.fromOffset(12, 12)
	else
		-- PuzzleUI owns the final 140px at the bottom-right. Keep this guide
		-- immediately to its left while closed; opening the guide publishes a
		-- modal flag so PuzzleUI yields the corner to the panel below.
		objectivesButton.AnchorPoint = Vector2.new(1, 1)
		objectivesButton.Position = UDim2.new(1, -(18 + 140 + 10), 1, -18)
	end

	-- The objectives panel is Active and nearly full-bleed, so on touch it is the
	-- single most likely element to swallow the movement controls. It takes the
	-- safe band EXACTLY -- no minimum-height floor, because a floor is what
	-- silently defeated the first attempt at this clamp and put a 160px panel
	-- back on top of the thumbstick at 667x375.
	if touch then
		local band = layout.TopBand
		objectivesPanel.AnchorPoint = Vector2.new(0, 0)
		objectivesPanel.Position = UDim2.fromOffset(band.Left,
			UIDevice.TopOffsetFor(guideGui, band.Top))
		objectivesPanel.Size = UDim2.fromOffset(band.Width, band.Height)
		-- The panel takes the WHOLE safe band on touch, which starts 8px under
		-- the top inset -- above the button that opened it. On a phone's 36px
		-- inset the two overlap, and the panel is Active, so the button it covers
		-- stops responding. They are alternatives rather than companions: the
		-- panel carries its own Close, so the button stands down while it is up.
		refreshObjectivesButton()
		objectivesTitle.TextSize = narrow and 15 or 18
		subtitleText.TextSize = narrow and 16 or 20
	elseif narrow then
		objectivesPanel.AnchorPoint = Vector2.new(1, 1)
		objectivesPanel.Position = UDim2.new(1, -10, 1, -70)
		objectivesPanel.Size = UDim2.new(1, -20, 0,
			math.max(120, math.min(360, viewport.Y - 82)))
		objectivesTitle.TextSize = 15
		subtitleText.TextSize = 16
	else
		objectivesPanel.AnchorPoint = Vector2.new(1, 1)
		objectivesPanel.Position = UDim2.new(1, -18, 1, -70)
		objectivesPanel.Size = UDim2.fromOffset(420,
			math.max(120, math.min(338, viewport.Y - 82)))
		objectivesTitle.TextSize = 18
		subtitleText.TextSize = 20
	end

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
	local preferredRowWidth = touch and 168 or 190
	local minimumRowWidth = touch and 132 or 162
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

	local band = layout.TopBand
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
	local BAND_CEILING = touch and math.max(48, math.floor(band.Height))
		or math.max(48, viewport.Y - (narrow and 96 or 64) - PANEL_MARGIN)
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
	local panelWidth = math.clamp(
		touch and band.Width or (narrow and (viewport.X - 20) or math.floor(viewport.X * .76)),
		240, 860)
	-- The 240 floor above is a READABILITY floor, and on touch it is allowed to
	-- ask for more width than the band actually has. It never wins: the band is
	-- the outer boundary of this panel on both axes, not just the vertical one.
	if touch then panelWidth = math.min(panelWidth, math.floor(band.Width)) end

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

	local function measure(candidate, height)
		local controlsWidth = candidate.Columns == 2
			and candidate.Width * 2 + 10 or candidate.Width
		local controlsHeight = candidate.Columns == 2
			and candidate.Height or candidate.Height * 2 + 4
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
	local desiredTextHeight = touch and layout.Portrait and 66 or 40
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
		-- Nothing fits comfortably, so take the arrangement that leaves the most
		-- subtitle, breaking ties by the preference order above.
		panelHeight = touch and math.max(64, math.min(baseHeight, band.Height)) or baseHeight
		-- ...but never taller than the band. `math.max(64, ...)` above is a
		-- readability floor and it used to be the LAST word, so on a band under
		-- 64px it quietly handed back a panel taller than the screen space it
		-- was given. The band is the last word now.
		panelHeight = math.min(panelHeight, BAND_CEILING)
		for _, candidate in ipairs(candidates) do
			local measured = measure(candidate, panelHeight)
			if measured and (not fit or measured.TextHeight > fit.TextHeight) then
				fit = measured
			end
		end
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
		local needed = game:GetService("TextService"):GetTextSize(
			dispatchAudio.longestLine, 11, subtitleText.Font,
			Vector2.new(textWidth, 100000)).Y
		local minimumText = math.max(touch and 20 or 22, needed)
		-- Ask for what the content wants, then let the band cut it down.
		local rowSpan = function(row)
			return columns == 2 and row or row * 2 + 4
		end
		panelHeight = math.clamp(
			controlsTop + rowSpan(minimumRowHeight) + minimumText + bottomPad,
			math.min(panelHeight or 0, BAND_CEILING), BAND_CEILING)
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

	-- THE BAND WINS, ALWAYS -- stated once, at the end, where nothing can get
	-- past it. Every pass above already respects BAND_CEILING, so this is the
	-- guarantee rather than the mechanism; the subtitle box is re-derived from
	-- the clamped height so a clamp can never leave the copy hanging outside the
	-- panel it was measured against.
	panelHeight = math.min(panelHeight, BAND_CEILING)
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
	subtitleFrame:SetAttribute("BriefingBandCeiling", BAND_CEILING)

	if touch then
		subtitleFrame.AnchorPoint = Vector2.new(0, 0)
		subtitleFrame.Position = UDim2.fromOffset(band.Left,
			UIDevice.TopOffsetFor(guideGui, band.Top))
	else
		subtitleFrame.AnchorPoint = Vector2.new(0.5, 1)
		subtitleFrame.Position = UDim2.new(0.5, 0, 1, narrow and -96 or -64)
	end
	subtitleFrame.Size = UDim2.fromOffset(panelWidth, panelHeight)
	-- The constraint used to clamp height to 118 and width to 860 behind the
	-- layout's back, which is how a panel could end up a different size from the
	-- one every child was measured against. It now states the same numbers.
	subtitleConstraint.MinSize = Vector2.new(panelWidth, panelHeight)
	subtitleConstraint.MaxSize = Vector2.new(panelWidth, panelHeight)

	local rowWidth = fit.Candidate.Width
	local rowHeight = fit.Candidate.Height
	dispatchAudio.button.Size = UDim2.fromOffset(rowWidth, rowHeight)
	dispatchAudio.stopButton.Size = UDim2.fromOffset(rowWidth, rowHeight)
	dispatchAudio.button.TextSize = touch and 14 or 13
	dispatchAudio.stopButton.TextSize = touch and 14 or 13

	dispatchAudio.layout.FillDirection = fit.Candidate.Columns == 2
		and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
	dispatchAudio.layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	dispatchAudio.controls.AnchorPoint = Vector2.new(1, 0)
	dispatchAudio.controls.Position = UDim2.new(1, -PANEL_MARGIN, 0, fit.ControlsTop)
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
	subtitleText.TextSize = dispatchAudio.faceThatFits(ceiling, fit.TextWidth, fit.TextHeight)

	-- The BINDING GLYPHS live in dispatchAudio.refresh, and until now nothing
	-- re-ran it when the form factor changed. UIDevice.Binding returns "" the
	-- moment a touchscreen exists, so "[M]  MUTE DISPATCH" was correct when the
	-- captions were first built and stayed on screen afterwards -- a key glyph
	-- on a phone, naming a key the device has not got. This is the one signal
	-- that fires on a form-factor change, so the captions are rebuilt from it.
	-- refresh() never calls back into the layout, so there is no cycle here.
	dispatchAudio.refresh()
end

UIDevice.Changed:Connect(updateLevelOneGuideLayout)

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
	setObjectivesAvailable(false)
	setSubtitle(nil)

	task.spawn(function()
		dispatchAudio.awaitPreference()
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
				setObjectivesAvailable(true)
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
		player:SetAttribute("LevelOneBriefingActive", true)
		local played = pcall(function() levelOneBriefingSound:Play() end)
		if not played then
			player:SetAttribute("LevelOneBriefingActive", false)
			dispatchAudio.finishTransmission("level1", run)
			if run == briefingRun and isLevelOneParticipant() then
				setObjectivesAvailable(true)
			end
			return
		end

		local currentText = nil
		local playbackStarted = levelOneBriefingSound.IsPlaying
		local playbackStartDeadline = os.clock() + 4
		local deadline = os.clock() + 52
		while run == briefingRun and isLevelOneParticipant() and os.clock() < deadline do
			local position = levelOneBriefingSound.TimePosition
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
			if levelOneBriefingSound.IsPlaying then
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
			setObjectivesAvailable(true)
		end
	end)
end

local function cancelLevelTwoBriefing()
	levelTwoBriefingRun += 1
	dispatchAudio.clearTransmission("level2")
	levelTwoRadioCue:Stop()
	levelTwoBriefingSound:Stop()
	player:SetAttribute("LevelTwoBriefingActive", false)
	setSubtitle(nil)
end

local function isLevelTwoParticipant()
	return workspace:GetAttribute("SelectedLevel") == 2
		and workspace:GetAttribute("RoundActive") == true
		and player:GetAttribute("InRound") == true
		and player:GetAttribute("Escaped") ~= true
		and not dead
end

local function preloadLevelTwoBriefing()
	if levelTwoBriefingPreloaded then return true end
	local ok = pcall(function()
		ContentProvider:PreloadAsync({levelTwoRadioCue, levelTwoBriefingSound})
	end)
	levelTwoBriefingPreloaded = ok and levelTwoRadioCue.IsLoaded and levelTwoBriefingSound.IsLoaded
	return levelTwoBriefingPreloaded
end

task.spawn(preloadLevelTwoBriefing)

local function playLevelTwoBriefing()
	levelTwoBriefingRun += 1
	local run = levelTwoBriefingRun
	local speechAt = os.clock() + LEVEL_TWO_BRIEFING_DELAY
	player:SetAttribute("LevelTwoBriefingActive", false)
	setSubtitle(nil)

	task.spawn(function()
		dispatchAudio.awaitPreference()
		preloadLevelTwoBriefing()

		local radioLength = levelTwoRadioCue.TimeLength > 0.05 and levelTwoRadioCue.TimeLength or 1
		local remaining = speechAt - radioLength - os.clock()
		if remaining > 0 then task.wait(remaining) end
		if run ~= levelTwoBriefingRun or not isLevelTwoParticipant() then return end

		setMsg("")
		dispatchAudio.beginTransmission("level2", run, function()
			if run ~= levelTwoBriefingRun then return end
			cancelLevelTwoBriefing()
		end)
		levelTwoRadioCue:Stop()
		levelTwoRadioCue.TimePosition = 0
		local radioPlayed = pcall(function() levelTwoRadioCue:Play() end)
		if radioPlayed then
			local radioStarted = levelTwoRadioCue.IsPlaying
			local radioStartDeadline = os.clock() + 0.5
			local radioDeadline = os.clock() + radioLength + 1
			while run == levelTwoBriefingRun and isLevelTwoParticipant() and os.clock() < radioDeadline do
				if levelTwoRadioCue.IsPlaying then
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
		if run ~= levelTwoBriefingRun or not isLevelTwoParticipant() then
			dispatchAudio.finishTransmission("level2", run)
			return
		end

		levelTwoBriefingSound:Stop()
		levelTwoBriefingSound.TimePosition = 0
		player:SetAttribute("LevelTwoBriefingActive", true)
		local played = pcall(function() levelTwoBriefingSound:Play() end)
		if not played then
			player:SetAttribute("LevelTwoBriefingActive", false)
			dispatchAudio.finishTransmission("level2", run)
			return
		end

		local currentText = nil
		local playbackStarted = levelTwoBriefingSound.IsPlaying
		local playbackStartDeadline = os.clock() + 4
		local deadline = os.clock() + 50
		while run == levelTwoBriefingRun and isLevelTwoParticipant() and os.clock() < deadline do
			local position = levelTwoBriefingSound.TimePosition
			local cueText = nil
			for _, cue in ipairs(levelTwoBriefingCues) do
				if position >= cue[1] and position < cue[2] then
					cueText = cue[3]
					break
				end
			end
			if cueText ~= currentText then
				currentText = cueText
				setSubtitle(cueText)
			end
			if levelTwoBriefingSound.IsPlaying then
				playbackStarted = true
			elseif playbackStarted or os.clock() >= playbackStartDeadline then
				break
			end
			RunService.Heartbeat:Wait()
		end

		player:SetAttribute("LevelTwoBriefingActive", false)
		dispatchAudio.finishTransmission("level2", run)
		if run ~= levelTwoBriefingRun then return end
		setSubtitle(nil)
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
		ContentProvider:PreloadAsync({levelThreeBriefing.radio, levelThreeBriefing.sound})
	end)
	levelThreeBriefing.preloaded = ok
		and levelThreeBriefing.radio.IsLoaded
		and levelThreeBriefing.sound.IsLoaded
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

	task.spawn(function()
		dispatchAudio.awaitPreference()
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
		player:SetAttribute("LevelThreeBriefingActive", true)
		local played = pcall(function() levelThreeBriefing.sound:Play() end)
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
		while run == levelThreeBriefing.run
			and levelThreeBriefing.isParticipant()
			and os.clock() < deadline do
			local position = levelThreeBriefing.sound.TimePosition
			levelThreeBriefing.updateInterference(position)
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
			if levelThreeBriefing.sound.IsPlaying then
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
	cancelLevelTwoBriefing()
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

local function validateLevelTwoBriefing()
	if not isLevelTwoParticipant() then
		cancelLevelTwoBriefing()
	end
end
workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(validateLevelTwoBriefing)
workspace:GetAttributeChangedSignal("RoundActive"):Connect(validateLevelTwoBriefing)
player:GetAttributeChangedSignal("InRound"):Connect(validateLevelTwoBriefing)
player:GetAttributeChangedSignal("Escaped"):Connect(validateLevelTwoBriefing)

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

-- Old, unstable elevator camera motion. It peaks after the one-second
-- startup delay, then decays smoothly for ten seconds without moving the player.
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

			local camera = workspace.CurrentCamera
			if not camera then return end
			local settling = elapsed >= SHAKE_DURATION
			local settleProgress = math.clamp(elapsed - SHAKE_DURATION, 0, SETTLE_DURATION) / SETTLE_DURATION
			local fade = math.max(1 - elapsed / SHAKE_DURATION, 0) ^ 1.35
			local t = os.clock()

			-- Layered noise: low mechanical sway plus a restrained high-frequency rattle.
			local side = (math.noise(t * 3.2, 0) * 0.055 + math.noise(t * 11.0, 5) * 0.018) * fade
			local lift = (math.noise(0, t * 4.0) * 0.075 + math.noise(8, t * 13.0) * 0.022) * fade
			local roll = math.rad(math.noise(t * 2.7, 14) * 0.22 * fade)
			local pitch = math.rad(math.noise(21, t * 3.0) * 0.12 * fade)

			if settling then
				-- One firm but controlled downward stop, followed by a soft recovery.
				local joltPhase = math.clamp(settleProgress / 0.62, 0, 1)
				lift = -math.sin(joltPhase * math.pi) * 0.16
				side = 0
				roll = 0
				pitch = math.rad(math.sin(joltPhase * math.pi) * 0.28)
			end

			camera.CFrame = camera.CFrame
				* CFrame.new(side, lift, 0)
				* CFrame.Angles(pitch, 0, roll)

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
		setMsg("") -- the in-world sign carries the idle lobby instruction

	elseif ev == "lobbybriefing" then
		lobbyBriefing.playOnce()

	elseif ev == "queuehost" then
		loadingFrame.Visible = false
		queueStation = tonumber(a)
		queueSizeValue = math.clamp(math.floor(tonumber(b) or 6), 1, 6)
		queuePrivacyValue = c == "friends" and "friends" or "public"
		queueSubmitting = false
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
		setMsg(stationText .. "GAME BEGINS IN " .. tostring(a) .. string.char(10)
			.. count .. "/" .. maximum .. " READY  •  " .. privacyText, Color3.fromRGB(120, 255, 175))
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
		cancelAllCommandBriefings(true)
		elevatorBriefingStarted = false
		levelTwoBriefingStarted = false
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
		-- GameManager sends the level with this event because it sets
		-- SelectedLevel later, inside ensureWorld — reading the attribute here
		-- would paint the cover in the PREVIOUS round's colour.
		local announcedLevel = tonumber(a)
		local launchingLevel = announcedLevel
			or workspace:GetAttribute("SelectedLevel") or 1
		-- Only a launch whose level the server ANNOUNCED may arm the held cover.
		-- The join-time status fire carries no level, and a player arriving then
		-- is not in the party, so it would never receive the poolaccess that
		-- releases the hold — it would sit behind a black screen forever.
		local heldCover = announcedLevel == 2
		entryAckPending = heldCover
		applyLoadingPalette(launchingLevel)
		loadingTitle.Text = "> ENTERING ANOMALOUS SPACE"
		loadingClock = 0
		-- Level 2 replays the full staged sequence every round; it is the only
		-- cover it gets. Every other level keeps the single generating line.
		loadingBaseText = heldCover and "LOCATING ANOMALOUS SPACE" or "GENERATING WORLD"
		-- Paint the status line BEFORE uncovering. RenderStepped only refreshes
		-- it while the frame is visible, so revealing first shows one frame of
		-- the PREVIOUS round's line.
		loadingStatus.Text = loadingBaseText
		loadingFrame.Visible = true
		if heldCover then
			serverReadyForEntry = false
			startLoadingSequence()
			-- Absolute backstop, independent of every event above: whatever goes
			-- wrong upstream, this client is let into the world.
			local guard = loadingRun
			task.delay(LEVEL_TWO_ENTRY_TIMEOUT + 20, function()
				if loadingRun == guard and loadingFrame.Visible then
					loadingSequenceFinished = true
					serverReadyForEntry = true
					finishLoadingWhenReady()
				end
			end)
		end

	elseif ev == "loadfailed" then
		cancelAllCommandBriefings(true)
		loadingFrame.Visible = false
		setMsg("WORLD GENERATION FAILED — RETURNING TO LOBBY", Color3.fromRGB(255, 100, 100))

	elseif ev == "poolaccess" then
		dead = false
		setMsg("POOL ACCESS READY", Color3.fromRGB(105, 230, 210))
		-- Do NOT uncover here. The world exists on the server, but with
		-- StreamingEnabled the client is still pulling in a 60k-instance
		-- complex; dropping the cover now is what put players in an empty room.
		task.spawn(function()
			local grounded = waitForLevelTwoEntry()
			if not grounded then
				-- Streaming never settled. Let them in regardless — a stuck
				-- cover is worse than an unfinished one.
				loadingSequenceFinished = true
			end
			serverReadyForEntry = true
			finishLoadingWhenReady()
		end)

	elseif ev == "level3access" then
		loadingFrame.Visible = false
		serverReadyForEntry = true
		finishLoadingWhenReady()
		dead = false
		setMsg("SERVICE LEVEL ACCESS READY", Color3.fromRGB(95, 235, 215))

	elseif ev == "elevator" then
		loadingFrame.Visible = false
		serverReadyForEntry = true
		finishLoadingWhenReady()
		scheduleElevatorShake()
		dead = false
		if not elevatorBriefingStarted then
			elevatorBriefingStarted = true
			playLevelOneBriefing()
		end

	elseif ev == "start" then
		hideRoundEnding(true)
		stopSpectating()
		shakeScheduled = false
		serverReadyForEntry = true
		finishLoadingWhenReady()
		dead = false
		setMsg("")
		local selectedLevel = workspace:GetAttribute("SelectedLevel")
		if selectedLevel == 2 and not levelTwoBriefingStarted then
			levelTwoBriefingStarted = true
			playLevelTwoBriefing()
		elseif selectedLevel == 3 and not levelThreeBriefing.started then
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
		elseif spectating and spectateTarget and a == spectateTarget.Name then
			spectateTarget = nil
		end

	elseif ev == "escape" then
		if a == player.Name then
			cancelAllCommandBriefings(true)
			showRoundEnding(
				("LEVEL " .. tostring(workspace:GetAttribute("SelectedLevel") or 1) .. " CLEARED"),
				"SIGNAL LOST",
				"WAITING FOR THE OTHERS",
				Color3.fromRGB(115, 255, 170),
				true
			)
		elseif player:GetAttribute("Escaped") ~= true then
			local msg = "One player has successfully escaped. Follow the green lights to safety."
			setMsg(msg, Color3.fromRGB(150, 235, 175))
			task.delay(8, function()
				if label.Text == msg then setMsg("") end
			end)
		end

	elseif ev == "lose" then
		cancelAllCommandBriefings(true)
		stopSpectating()
		local totalPlayers = math.max(1, math.floor(tonumber(c) or 1))
		showRoundEnding(
			"NO ONE FOUND A WAY OUT",
			"TIME " .. formatRoundTime(a) .. "  •  SURVIVORS 0/" .. totalPlayers,
			"RETURNING TO BASE",
			Color3.fromRGB(255, 82, 72),
			false
		)

	elseif ev == "win" then
		cancelAllCommandBriefings(true)
		stopSpectating()
		local survivors = math.max(0, math.floor(tonumber(b) or 0))
		local totalPlayers = math.max(1, math.floor(tonumber(c) or math.max(1, survivors)))
		showRoundEnding(
			dead and "THE OTHERS FOUND A WAY OUT" or ("LEVEL " .. tostring(workspace:GetAttribute("SelectedLevel") or 1) .. " CLEARED"),
			"TIME " .. formatRoundTime(a) .. "  •  SURVIVORS " .. survivors .. "/" .. totalPlayers,
			"RETURNING TO BASE",
			Color3.fromRGB(115, 255, 170),
			false
		)
		completion.start(d, e, f)

	elseif ev == "returnpending" then
		if tonumber(a) == completion.serverSerial then
			completion.pending = true
			completion.button.Active = false
			completion.button.Selectable = false
			completion.button.Text = "RETURNING..."
		end

	elseif ev == "continuefailed" then
		if tonumber(a) == completion.serverSerial and completion.deadline
			and workspace:GetServerTimeNow() < completion.deadline then
			-- The transfer did not start. Re-arm both actions; the countdown is
			-- still running and will carry this player onward if they do nothing.
			completion.pending = false
			completion.continueButton.Text = "TRY CONTINUE"
			completion.button.Text = "BACK TO LOBBY"
			for _, button in ipairs(completion.buttons) do
				button.Active = button.Visible
				button.Selectable = button.Visible
			end
		end

	elseif ev == "returnfailed" then
		if tonumber(a) == completion.serverSerial and completion.deadline
			and workspace:GetServerTimeNow() < completion.deadline then
			completion.pending = false
			completion.continueButton.Text = "CONTINUE"
			completion.button.Text = "TRY BACK TO LOBBY"
			for _, button in ipairs(completion.buttons) do
				button.Active = button.Visible
				button.Selectable = button.Visible
			end
		end

	elseif ev == "transitionfailed" then
		completion.deadline = nil
		completion.pending = true
		completion.button.Active = false
		completion.button.Selectable = false
		completion.button.Text = "RETURNING..."
		endHint.Text = "NEXT LEVEL UNAVAILABLE  •  RETURNING TO LOBBY"
	end
end)

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
		or not workspace:FindFirstChild("ServerLobby") then
		return
	end
	lobbyBriefing.readySent = true
	remote:FireServer("lobbybriefingready")
end
player:GetAttributeChangedSignal("ZyntraDispatchPreferenceLoaded"):Connect(lobbyBriefing.trySendReady)
player:GetAttributeChangedSignal("ZyntraLobbyBriefingPlayed"):Connect(lobbyBriefing.trySendReady)
player:GetAttributeChangedSignal("InRound"):Connect(lobbyBriefing.trySendReady)
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
   and item.AnimationId ~= "" then return item.AnimationId end
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
 local steps = Instance.new("Sound")
 steps.Name = "MimicFootsteps"
 steps.SoundId = "rbxasset://sounds/action_footsteps_plastic.mp3"
 steps.Volume = 0.27 -- 50% louder than before
 local mimicStepSpeed = 0.78 + math.random() * 0.10
 steps.PlaybackSpeed = mimicStepSpeed
 steps.Looped = true
 steps.RollOffMinDistance = 5
 steps.RollOffMaxDistance = 46
 steps.Parent = root

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
  if on then
   steps.PlaybackSpeed = sprinting and 1.23 or mimicStepSpeed
   if not steps.IsPlaying then
    -- A random phase and delayed start keep these steps unmistakably separate
    -- from the local player's own walking loop.
    local startToken = os.clock()
    steps:SetAttribute("StartToken", startToken)
    task.delay(0.25 + math.random() * 0.45, function()
     if workspace:GetAttribute("SelectedLevel") == 1
      and model.Parent and moving == true and steps:GetAttribute("StartToken") == startToken then
      steps.TimePosition = math.random() * 0.28
      steps:Play()
     end
    end)
   end
  else
   steps:SetAttribute("StartToken", os.clock())
   steps:Stop()
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

local function ambientFootsteps()
 -- Level 2 owns its real shallow-water/entity step mix in SoundController.
 -- Do not layer the dry plastic fake-footstep scare over that soundscape.
 if workspace:GetAttribute("SelectedLevel") == 2 then return false end
 local _, _, root, alive = ambientCharacter()
 if not alive then return false end
 local backward = -ambientFlatUnit(root.CFrame.LookVector)
 local right = ambientFlatUnit(root.CFrame.RightVector, Vector3.new(1, 0, 0))
 local startPosition = root.Position + backward * math.random(11, 17)
  + right * math.random(-6, 6) + Vector3.new(0, 1.1, 0)
 local emitter = ambientEmitter("DistantFootsteps", startPosition, 4.2)
 local sound = Instance.new("Sound")
 sound.Name = "Footsteps"
 sound.SoundId = "rbxasset://sounds/action_footsteps_plastic.mp3"
 sound.Volume = 0.33 -- 50% louder than before
 sound.PlaybackSpeed = 0.78 + math.random() * 0.10
 sound.Looped = true
 sound.RollOffMinDistance = 6
 sound.RollOffMaxDistance = 48
 sound.Parent = emitter

 local startDelay = 0.25 + math.random() * 0.45
 local drift = backward * math.random(6, 10) + right * math.random(-4, 4)
 task.delay(startDelay, function()
  if not emitter.Parent then return end
  -- The separate start delay, phase and speed prevent synchronization with
  -- the player's own footsteps.
  sound.TimePosition = math.random() * 0.28
  sound:Play()
  AmbientTweenService:Create(emitter, TweenInfo.new(2.45, Enum.EasingStyle.Linear), {
   CFrame = emitter.CFrame + drift,
  }):Play()
 end)
 task.delay(startDelay + 1.95, function()
  if sound.Parent then
   AmbientTweenService:Create(sound, TweenInfo.new(0.52), {Volume = 0}):Play()
  end
 end)
 return true
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
 footsteps = ambientFootsteps,
 knocks = ambientKnocks,
 lights = ambientLightDrop,
 -- Not in the random rotation (ambientChooseKind), but registered so the
 -- documented Studio DevAmbientScare hook can actually trigger it.
 shadow = ambientShadow,
}

local function ambientChooseKind()
 local roll = math.random(1, 100)
 local kind = roll <= 34 and "footsteps"
  or roll <= 54 and "knocks"
  or roll <= 81 and "lights"
  or "footsteps"
 if kind == ambientLastKind then
  local alternatives = {"footsteps", "knocks", "lights"}
  table.remove(alternatives, table.find(alternatives, kind))
  kind = alternatives[math.random(1, #alternatives)]
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
 if (not ok or not started) and kind ~= "footsteps" and ambientCanScare() then
  pcall(ambientFootsteps)
  ambientLastKind = "footsteps"
 end
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
-- footsteps, knocks, lights or shadow (append any suffix to repeat one type).
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
