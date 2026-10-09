-- FlashlightController  (v4 — pitch-stable handheld beam)
-- PASTE INTO: StarterPlayer → StarterPlayerScripts → Insert Object → LocalScript → rename to "FlashlightController"
-- REPLACES the old FlashlightController entirely — paste over the old contents.
--
-- F toggles. The beam points exactly where you look (up/down included) while the
-- light source sits beside-and-below your eye like a torch in your hand. The hand
-- position is HORIZONTAL-only, so pitching down never drives the light into the
-- floor (that was the old "beam disappears looking down" bug).

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIDevice = require(RS:WaitForChild("UIDevice"))
local Profiles = require(RS:WaitForChild("FlashlightProfiles"))
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local remote = RS:WaitForChild("Remotes"):WaitForChild("ToggleFlashlight")
local player = Players.LocalPlayer
local vitalRemote = RS:WaitForChild("Remotes"):WaitForChild("RoundStatus")
local lastVitalReport = -math.huge

-- how the torch is held, relative to the eye (horizontal offset + drop)
local HAND_SIDE = 0.25  -- small hand offset: avoids putting the light inside walls
local HAND_DOWN = -0.25
local HAND_FORWARD = 0.3
local SWAY = 14         -- higher = snappier, lower = more lag/sway

local mount, coreLight, spillLight, fillLight
local on = false
-- FLASHLIGHT_REWORK_20261002: a faint warm fill around the hand (the bounce a real torch throws back off nearby
-- surfaces) so your immediate surroundings are never pitch black while the light is on, and a click on toggle.
local FILL_BRIGHTNESS, FILL_RANGE = 0.28, 11
local clickSound = Instance.new("Sound")
clickSound.Name = "FlashlightClick"
clickSound.SoundId = "rbxassetid://9116284750" -- ProSoundEffects "Light Switch Wall Plastic Flip On Off 2"
clickSound.Volume = 0.35
clickSound.Parent = game:GetService("SoundService")
local lastBeamProfile = ""
local aimCF = nil
local aimSendClock = 0

local function buildMount()
	local camera = workspace.CurrentCamera
	if not camera then return end
	if mount then
		mount:Destroy()
		mount, coreLight, spillLight, fillLight = nil, nil, nil, nil
	end

	mount = Instance.new("Part")
	mount.Name = "FlashlightMount"
	mount.Size = Vector3.new(0.2, 0.2, 0.2)
	mount.Anchored = true
	mount.CanCollide = false
	mount.CanQuery = false
	mount.Transparency = 1

	-- tight bright core: the actual "beam" (numbers live in FlashlightProfiles)
	coreLight = Instance.new("SpotLight")
	coreLight.Color = Color3.fromRGB(255, 244, 214)
	coreLight.Shadows = true -- localized cone stops at walls instead of lighting whole parts through them
	coreLight.Enabled = on
	coreLight.Face = Enum.NormalId.Front
	coreLight.Parent = mount

	-- wide dim spill: what your eye reads as the "cone of light"
	spillLight = Instance.new("SpotLight")
	spillLight.Color = Color3.fromRGB(255, 240, 205)
	spillLight.Shadows = false
	spillLight.Enabled = on
	spillLight.Face = Enum.NormalId.Front
	spillLight.Parent = mount

	fillLight = Instance.new("PointLight")
	fillLight.Name = "Fill"
	fillLight.Color = Color3.fromRGB(255, 236, 200)
	fillLight.Brightness = FILL_BRIGHTNESS
	fillLight.Range = FILL_RANGE
	fillLight.Shadows = false
	fillLight.Enabled = on
	fillLight.Parent = mount

	-- A light parented below CurrentCamera can report Enabled while contributing
	-- nothing to world lighting. Keep the invisible local mount in Workspace and
	-- drive its CFrame from the camera instead; it remains client-only.
	mount.Parent = workspace
end

local function isFocused()
	local char = player.Character
	return player:GetAttribute("ZyntraOwnsAdvancedEquipment") == true
		and char ~= nil and char:GetAttribute("FlashlightFocused") == true
end
local function applyBeamProfile()
	local profile = Profiles.Current()
	local focused = isFocused()
	local key = profile .. tostring(focused)
	if key == lastBeamProfile then return end
	lastBeamProfile = key
	Profiles.Apply(Profiles.Own, profile, coreLight, spillLight, focused)
end

buildMount()
applyBeamProfile()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	lastBeamProfile = ""
	buildMount()
	applyBeamProfile()
end)
workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(function()
	lastBeamProfile = ""
	applyBeamProfile()
end)
workspace:GetAttributeChangedSignal("Level3BlackoutActive"):Connect(function()
	lastBeamProfile = ""
	applyBeamProfile()
end)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- Illumination is produced only by localized SpotLights. The removed
-- Highlight adorned the entire hit floor/wall/ceiling part and looked exactly
-- like Studio selection rather than a physical flashlight beam.

-- Cached so the per-frame suppression below skips the name build, the
-- FindFirstChild lookup and GetChildren() once the instance is found.
local REPLICATED_SELF_NAME = "ReplicatedFlashlight_" .. player.UserId
local replicatedSelf, replicatedLights = nil, {}

-- bind AFTER the camera updates, so up/down tracking is exact
-- Level3UnderTableCamera finalizes a hidden player's camera at Camera + 1.
-- Aim one priority later so the torch always originates from that real POV.
RunService:BindToRenderStep("MongoFlashlight", Enum.RenderPriority.Camera.Value + 2, function(dt)
	applyBeamProfile()
	local camera = workspace.CurrentCamera
	if not camera then return end
	if not (mount and mount.Parent == workspace) then
		lastBeamProfile = ""
		buildMount()
		applyBeamProfile()
		if not mount then return end
	end
	applyBeamProfile()

	-- smooth the aim so the beam trails your turn like a held object
	aimCF = aimCF and aimCF:Lerp(camera.CFrame, math.clamp(dt * SWAY, 0, 1))
		or camera.CFrame

	local eye = camera.CFrame.Position

	-- hand position: beside & below the eye, but using a HORIZONTAL-only right
	-- vector + a world-space drop — so pitching up/down never pushes the light
	-- into the floor or ceiling
	local right = aimCF.RightVector
	local rightFlat = Vector3.new(right.X, 0, right.Z)
	rightFlat = (rightFlat.Magnitude > 0.001) and rightFlat.Unit or Vector3.new(1, 0, 0)
	local handPos = eye + rightFlat * HAND_SIDE + Vector3.new(0, HAND_DOWN, 0)
		+ aimCF.LookVector * HAND_FORWARD

	-- never originate the light inside a wall (kills close-range illumination)
	local filter = { camera }
	if player.Character then table.insert(filter, player.Character) end
	rayParams.FilterDescendantsInstances = filter
	local toHand = handPos - eye
	local hit = workspace:Raycast(eye, toHand, rayParams)
	if hit then
		handPos = eye + toHand.Unit * math.max((hit.Position - eye).Magnitude - 0.3, 0)
	end

	-- position at the hand, but point EXACTLY where the camera looks
	mount.CFrame = aimCF.Rotation + handPos

	-- The server mount lets other players see this flashlight. Suppress only the
	-- local player's replicated copy so their own camera never receives the same
	-- two SpotLights twice; this is a client-local property override.
	if not (replicatedSelf and replicatedSelf.Parent == workspace) then
		replicatedSelf = workspace:FindFirstChild(REPLICATED_SELF_NAME)
		replicatedLights = {}
		if replicatedSelf then
			for _, item in ipairs(replicatedSelf:GetChildren()) do
				if item:IsA("Light") then table.insert(replicatedLights, item) end
			end
		end
	end
	for _, item in ipairs(replicatedLights) do
		item.Enabled = false
	end

	if on then
		aimSendClock += dt
		if aimSendClock >= 1 / 15 then
			aimSendClock = 0
			remote:FireServer("aim", mount.CFrame)
		end
	else
		aimSendClock = 0
	end
end)

-- ── battery ───────────────────────────────────────────────
-- The beam itself warns too: one blink at 50%, a few blinks at 25%. The level is on the PC widget
-- below (07 B; owner, 2026-10-08) and, on touch, in the LIGHT cell's segments (14 A; owner, 2026-10-08).
local BATTERY_BASE     = 100
local DRAIN_PER_SEC    = 1.111 -- ~90s of continuous light on a full charge
local RECHARGE_PER_SEC = 3.0  -- full recharge in roughly 33s while switched OFF
local MIN_TO_TURN_ON   = 5    -- can't switch on below this (must recharge a bit)
local function batteryMax()
	return BATTERY_BASE * math.max(1, tonumber(player:GetAttribute("ZyntraBatteryMultiplier")) or 1)
end
local battery = batteryMax()
local warned50, warned25 = false, false
-- The round body carries the torch: a round, or the Level 2 new-map dev preview, which wears it outside a
-- round (Level2NewMapPreview, set and cleared by Level2BlenderPreviewAccess; FlashlightSync agrees).
local function roundBody()
	return player:GetAttribute("InRound") == true or player:GetAttribute("Level2NewMapPreview") == true
end

-- The flashlight gui. Its name stays FlashlightPopup (UIRegression's REQUIRED_GUIS and BORROWED_GUIS
-- read it), but since HUD batch B1 (owner, 2026-10-08) it holds the PC widget below and, since B2, the
-- touch LIGHT cell. The dead-battery strip it was named for is gone: the widget reads EMPTY.
local popupGui = Instance.new("ScreenGui")
popupGui.Name = "FlashlightPopup"
popupGui.ResetOnSpawn = false
popupGui.DisplayOrder = 61 -- BUILD-PLAN 1.4: 60 tied with StaminaGui (owner, 2026-10-08)
popupGui.Enabled = roundBody()
popupGui.Parent = player:WaitForChild("PlayerGui")

-- == B flashlight widget (07 B; owner, 2026-10-08) ==
-- artifacts/hud-final-20261008/BUILD-PLAN.md 07 and FRAMEWISP-PIPELINE.md 2.2. PC and gamepad mount
-- HUD_PC/FlashlightWidget bottom-left (Safe.Left + 24, bottom - 24): an F / R1 keycap, five battery
-- segments and one line. It replaces the torch silhouette, the [RB] caption and the focus hint on PC.
-- The touch layout never shows it (owner P1: on a phone the battery lives only in the LIGHT button,
-- which is the torch button below until batch B2 mounts the LIGHT cell).
-- RoundHud is looked up, never waited for: without it the beam still works and no widget draws.
local REFUSED_SECONDS = 2 -- a press below MIN_TO_TURN_ON reads "LIGHT . TOO LOW" this long
local refusedUntil = -math.huge
local widget, widgetParts = nil, nil

local function placeWidget()
	if not widget then return end
	local safe = UIDevice.Layout().Safe
	widget.AnchorPoint = Vector2.new(0, 1)
	widget.Position = UIDevice.LocalPosition(popupGui, safe.Left + 24, safe.Bottom - 24)
end
UIDevice.Changed:Connect(placeWidget)

local function mountWidget()
	if widget then return end
	local hudModule = RS:FindFirstChild("RoundHud")
	local shopUI = RS:FindFirstChild("ZyntraShopUI")
	local binderModule = shopUI and shopUI:FindFirstChild("ShopBinder")
	if not (hudModule and binderModule) then return end
	local Hud, Binder = require(hudModule), require(binderModule)
	local root = Hud.Mount("HUD_PC", "FlashlightWidget", popupGui)
	if not root then return end -- RoundHud warned by path; the next round entry tries again
	-- Hidden until the next heartbeat paints it: the clone carries the template's sample line, which
	-- must not show for a frame (on touch least of all, owner P1). `widget` is set last, so a
	-- half-built mount is never painted (owner, 2026-10-08).
	root.Visible = false
	Hud.Keycap(Binder.find(root, "KeyChip"), Enum.KeyCode.F, Enum.KeyCode.ButtonR1)
	local shell = Binder.at(root, "Battery/Shell")
	widgetParts = {Palette = Binder.Palette, Line = Binder.text(Binder.find(root, "Line")),
		Hud = Hud, KeyChip = Binder.find(root, "KeyChip"),
		Shell = shell and shell:FindFirstChildOfClass("UIStroke"), Nub = Binder.at(root, "Battery/Nub"), Segs = {}}
	for index = 1, 5 do widgetParts.Segs[index] = Binder.at(root, "Battery/Seg" .. index) end
	widget = root
	placeWidget()
end

-- s = {Fraction, Empty, On, Charging, Refused, Advanced, Focused, Spectating}. Empty: the light is
-- off and cannot be switched on (battery <= MIN_TO_TURN_ON). Returns the line, its tone, lit segments
-- and whether the outline (shell and nub) is Coral. The B tiles (owner, 2026-10-08): EMPTY is a Coral
-- outline round no segments; TOO LOW keeps the Cream outline round one Coral segment.
local function widgetState(s)
	local lit = s.Empty and 0 or math.clamp(math.ceil(s.Fraction * 5), 0, 5)
	if s.Spectating then return "THEIR LIGHT", "Cream", lit, s.Empty == true end
	if s.Refused then return "LIGHT \u{B7} TOO LOW", "Coral", 1, false end
	if s.Empty then return "LIGHT \u{B7} EMPTY", "Coral", 0, true end
	if lit <= 2 then return "LIGHT \u{B7} LOW", "Amber", lit, false end
	if not s.On then return s.Charging and "LIGHT OFF \u{B7} CHARGING" or "LIGHT OFF", "Cream", lit, false end
	if s.Advanced then return s.Focused and "LIGHT \u{B7} FOCUSED" or "LIGHT \u{B7} WIDE", "Cream", lit, false end
	return "LIGHT", "Cream", lit, false
end

-- shown: the caller's gate (spectate target, modal). The touch layout always hides the widget.
local function paintWidget(s, shown)
	if not widget then return end
	widget.Visible = shown and not UIDevice.IsTouch()
	local line, tone, lit, coral = widgetState(s)
	local P = widgetParts.Palette
	if widgetParts.Spectating ~= s.Spectating then
		-- No keycap while spectating: F / R1 act on your own light, which is out (owner, 2026-10-08).
		widgetParts.Spectating = s.Spectating
		if s.Spectating then
			widgetParts.Hud.Keycap(widgetParts.KeyChip)
		else
			widgetParts.Hud.Keycap(widgetParts.KeyChip, Enum.KeyCode.F, Enum.KeyCode.ButtonR1)
		end
	end
	if widgetParts.Line then
		widgetParts.Line.Text = line
		widgetParts.Line.TextColor3 = P[tone]
	end
	local outline = coral and P.Coral or P.Cream
	if widgetParts.Shell then widgetParts.Shell.Color = outline end
	if widgetParts.Nub then widgetParts.Nub.BackgroundColor3 = outline end
	local fill = tone == "Coral" and P.Coral or lit <= 2 and P.Amber or P.Cream
	for index, segment in pairs(widgetParts.Segs) do
		segment.BackgroundColor3 = index > lit and P.Line or fill
		-- the template draws a lit segment at 0.1 and an unlit one opaque (the HUD_PC dump)
		segment.BackgroundTransparency = index > lit and 0 or 0.1
	end
end
-- == end B flashlight widget ==

-- == B2 LIGHT cell (mount) ==
-- 14 A, owner P1 (owner, 2026-10-08; artifacts/hud-final-20261008/b2/B2-DESIGN.md 6): on touch the
-- battery lives only in this cell, HUD_Touch's TouchCluster/FlashlightPower: five segments over a
-- LIGHT label. It replaces the torch silhouette, its transparent tap target and the HOLD / WIDE hint
-- (D12: the beam itself shows WIDE / FOCUSED). Mounted once, at load, on every client (PC too, hidden),
-- so the registered root never changes; it is never re-mounted or destroyed.
-- C3: nothing here waits on a child. After game.Loaded the templates are place data; a missing bundle,
-- RoundHud or ShopBinder mounts nothing (RoundHud warns by path), registers nothing and leaves the beam,
-- the keys and the heartbeat as they are.
if not game:IsLoaded() then game.Loaded:Wait() end
local lightCell, lightParts = nil, nil

-- s is the widget's input; the cell paints your own light only (it is hidden while spectating, D11).
-- lit 3+: Cream segments. lit 1-2: Amber segments, LOW in Amber. EMPTY: no segments in a Coral outline,
-- LIGHT. A refused press: one Coral segment, LOW in Coral, for REFUSED_SECONDS. On / off (D10) and
-- WIDE / FOCUSED (D12) are not drawn. C8: only colours, alphas and the label are written; the stroke's
-- Thickness is the template's (ScaledSize) and scaleText's, so the resize a layout pass does cannot
-- undo a paint.
local function paintLight(s)
	local parts = lightParts
	if not parts then return end
	local _, tone, lit, coral = widgetState(s)
	local P = parts.Palette
	for index, segment in pairs(parts.Segs) do
		local filled = index <= lit
		segment.BackgroundColor3 = filled and P[tone] or P.Cream
		segment.BackgroundTransparency = filled and parts.LitAlpha or parts.UnlitAlpha
	end
	if parts.Stroke then parts.Stroke.Color = coral and P.Coral or parts.StrokeColor end
	if parts.Label then
		local low = tone == "Amber" or (tone == "Coral" and not coral)
		parts.Label.Text = low and "LOW" or parts.LabelText
		parts.Label.TextColor3 = low and P[tone] or parts.LabelColor
	end
end

do
	local hudModule = RS:FindFirstChild("RoundHud")
	local shopUI = RS:FindFirstChild("ZyntraShopUI")
	local binderModule = shopUI and shopUI:FindFirstChild("ShopBinder")
	local Hud = hudModule and binderModule and require(hudModule)
	local cell = Hud and Hud.Mount("HUD_Touch", "TouchCluster/FlashlightPower", popupGui, {Name = "FlashlightPower"})
	if cell then
		local Binder = require(binderModule)
		-- Before the first SetInteractive: UIDevice latches the first Selectable it sees, and the
		-- template ships it true (B2-DESIGN 2.2 rule 2).
		cell.AutoButtonColor, cell.Selectable, cell.Visible, cell.Active = false, false, false, false
		local segs = {}
		for index = 1, 5 do segs[index] = Binder.find(cell, "Seg" .. index) end
		local label = Binder.text(Binder.find(cell, "Label"))
		local stroke = cell:FindFirstChildOfClass("UIStroke")
		-- The template's own look: a lit Seg1 at 0.1, an unlit Seg5 at 0.85, a Line outline, a Cream LIGHT.
		lightParts = {Palette = Binder.Palette, Segs = segs, Label = label, Stroke = stroke,
			LitAlpha = segs[1] and segs[1].BackgroundTransparency or 0.1,
			UnlitAlpha = segs[5] and segs[5].BackgroundTransparency or 0.85,
			StrokeColor = stroke and stroke.Color, LabelColor = label and label.TextColor3,
			LabelText = label and label.Text}
		lightCell = cell
		-- Painted before anything can show it: the template's sample (four of five lit) never draws.
		paintLight({Fraction = math.clamp(battery / batteryMax(), 0, 1)})
	end
end
-- == end B2 LIGHT cell (mount) ==

-- Whether the cell is currently tagged as part of the movement cluster.
-- C_CONTROL_ZONE_INVALIDATION_20260831: the registration follows the FORM
-- FACTOR rather than being done once at load. On a pointer device the cell is
-- hidden and is no movement control at all, and leaving it tagged put a
-- rectangle every HUD dodges where nothing is drawn. Latched, so a relayout that
-- changes nothing does not churn the zone; and reversible, because a tablet
-- leaving its keyboard case flips the form factor without a restart.
local flashlightRegistered = false

-- On touch the LIGHT cell takes its slot in the movement cluster. (The old torch
-- sat bottom-LEFT, inside the dynamic thumbstick's activation region.) On desktop
-- it is not drawn at all: the PC widget is the readout there (owner, 2026-10-08).
--
-- C_SHORT_SCREEN_CLUSTER_20260831: the slot is READ from UIDevice's control
-- plan, not re-derived here, so the cluster can reflow (the 4 + 4 grid, or the
-- short-screen row) without this file knowing. D6 (owner, 2026-10-08): Size
-- follows the slot every pass, 52 px on a phone and 64 on a tablet, and
-- ShopBinder.scaleText re-fits the label on the resize. Never re-mounted.
local function applyFlashlightLayout()
	if not lightCell then return end -- D14: no template, nothing drawn and nothing registered
	local layout = UIDevice.Layout()
	if layout.IsTouch ~= flashlightRegistered then
		flashlightRegistered = layout.IsTouch
		if flashlightRegistered then
			UIDevice.RegisterControlRect("FlashlightPower", lightCell)
		else
			UIDevice.UnregisterControlRect(lightCell)
		end
	end
	if layout.IsTouch then
		local slot = layout.ControlPlan.Slots.FlashlightPower
		lightCell.AnchorPoint = Vector2.new(1, 1)
		lightCell.Size = UDim2.fromOffset(slot.Width, slot.Height)
		lightCell.Position = UDim2.new(1, -slot.Right, 1, -slot.Bottom)
	end
end

-- Visible AND Active move together (UIDevice.SetInteractive): a hidden but
-- Active button keeps swallowing taps, which is how the old transparent torch
-- target once competed with the thumbstick. The cell stands down on exactly the
-- states the movement cluster does.
-- C_LIVE_CONTROL_RECTS_20260831: the cell registers its rectangle like the rest
-- of the cluster. The registration lives in applyFlashlightLayout, which is
-- where the form factor is already known.

-- C_GAMEPAD_FLASHLIGHT_20260904: a controller had no way to switch the light on
-- at all. ButtonR1 toggles it (see the InputBegan handler). The "[RB]" caption
-- that said so is gone (owner, 2026-10-08): the widget's keycap shows the R1
-- glyph through RoundHud.Keycap whenever a gamepad is the live input.

-- Keep the production shade itself in the availability predicate. The shared
-- QueueModalOpen attribute remains the fallback contract, but its listener and
-- the shade listener have no guaranteed ordering; relying on the attribute
-- alone leaves an invisible DisplayOrder-60 tap target alive for that gap.
local queueShadeVisible = player:GetAttribute("QueueModalOpen") == true

local function flashlightTargetAvailable()
	if not UIDevice.IsTouch() then return false end
	if not roundBody() then return false end
	if player:GetAttribute("Escaped") == true then return false end
	if player:GetAttribute("Spectating") == true then return false end
	-- D13 (owner, 2026-10-08): the eight screen-owning modals through UIDevice's one predicate, the one
	-- its zones use, instead of a private list of four. The shade can lead QueueModalOpen by two frames.
	if queueShadeVisible or UIDevice.ScreenOwningModalOpen() then return false end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- The only writer of the LIGHT cell's Visible (and Active).
local function applyFlashlightTouchTarget()
	if lightCell then UIDevice.SetInteractive(lightCell, flashlightTargetAvailable()) end
end
-- No modal attribute is listed: UIDevice.Changed (below) fires, forced, on every screen-owning modal (D13).
for _, attribute in ipairs({"InRound", "Level2NewMapPreview", "Escaped", "Level3_Hiding", "Spectating"}) do
	player:GetAttributeChangedSignal(attribute):Connect(function()
		applyFlashlightTouchTarget()
	end)
end
-- QueueModalOpen is derived from QueueHostShade.Visible. Listening only to the
-- derived attribute adds a second deferred signal hop: for two frames the
-- DisplayOrder-60 flashlight target can still sit above a newly opened party
-- modal. Watch production's actual choke point too, so the target stands down
-- on the very next Heartbeat while the attribute remains the shared contract
-- for every other screen-owning modal.
task.spawn(function()
	local playerGui = player:WaitForChild("PlayerGui")
	local roundGui = playerGui:WaitForChild("RoundGui", 15)
	local queueShade = roundGui and roundGui:WaitForChild("QueueHostShade", 15)
	if not queueShade then return end
	queueShadeVisible = queueShade.Visible
	queueShade:GetPropertyChangedSignal("Visible"):Connect(function()
		queueShadeVisible = queueShade.Visible
		applyFlashlightTouchTarget()
	end)
	applyFlashlightTouchTarget()
end)
player.CharacterAdded:Connect(function(character)
	local humanoid = character:WaitForChild("Humanoid", 8)
	if humanoid then humanoid.Died:Connect(applyFlashlightTouchTarget) end
	applyFlashlightTouchTarget()
end)
applyFlashlightTouchTarget()
applyFlashlightLayout()
UIDevice.Changed:Connect(function()
	applyFlashlightTouchTarget()
	applyFlashlightLayout()
end)

local function setLights(state)
 on = state
	if coreLight then coreLight.Enabled = state end
	if spillLight then spillLight.Enabled = state end
	if fillLight then fillLight.Enabled = state end
 remote:FireServer(state)
end

-- a low-battery WARNING flicker: briefly drop the beam `times` times then
-- restore it. Purely visual — doesn't change the real on/off state, so it
-- doesn't spam the server or affect the entity's sight bonus.
local function warnBlink(times)
	if not on then return end
	task.spawn(function()
		for _ = 1, times do
			if not on then break end
			if coreLight then coreLight.Enabled = false end
			if spillLight then spillLight.Enabled = false end
			if fillLight then fillLight.Enabled = false end
			task.wait(0.08)
			if coreLight then coreLight.Enabled = on end
			if spillLight then spillLight.Enabled = on end
			if fillLight then fillLight.Enabled = on end
			task.wait(0.14)
		end
	end)
end

local function alive()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum and hum.Health > 0
end

local function toggle()
	if not roundBody() then return end
	if not alive() then return end -- dead / spectating: no flashlight of your own
	if on then
		setLights(false)
		clickSound:Play()
	elseif battery > MIN_TO_TURN_ON then
		setLights(true)
		clickSound:Play()
		refusedUntil = -math.huge -- the refusal is answered
	else
		refusedUntil = time() + REFUSED_SECONDS -- no longer silent: "LIGHT . TOO LOW" (owner, 2026-10-08)
	end
end

local function toggleFocus()
	if not roundBody() or not alive() then return end
	if player:GetAttribute("ZyntraOwnsAdvancedEquipment") ~= true then return end
	remote:FireServer("focus", not isFocused())
end
-- == B2 LIGHT cell (input/paint) ==
-- The torch button's handler, moved onto the cell verbatim (owner, 2026-10-08): a touch, or the Studio
-- ForceTouchUI mouse; a second press inside 0.2 s is ignored; holding 0.45 s with Advanced Equipment
-- focuses instead (UIS.InputEnded below toggles a short press). Here, after toggle and toggleFocus, so
-- both are in scope (critic C2). The paint is paintLight in the mount block, so the first one lands
-- before the first SetInteractive; the heartbeat repaints it.
local press, lastTouchToggle = nil, 0
if lightCell then
	lightCell.InputBegan:Connect(function(input)
		local touch = input.UserInputType == Enum.UserInputType.Touch
		local studioMouse = RunService:IsStudio() and workspace:GetAttribute("ForceTouchUI") == true
			and input.UserInputType == Enum.UserInputType.MouseButton1
		if not (touch or studioMouse) or os.clock() - lastTouchToggle < .2 then return end
		lastTouchToggle = os.clock()
		local current = {Input = input, Held = false}
		press = current
		task.delay(.45, function()
			if press == current and player:GetAttribute("ZyntraOwnsAdvancedEquipment") == true then
				current.Held = true
				toggleFocus()
			end
		end)
	end)
end
-- == end B2 LIGHT cell (input/paint) ==
UIS.InputEnded:Connect(function(input)
	if press and press.Input == input then
		local current = press
		press = nil
		if not current.Held then toggle() end
	end
end)

UIS.InputBegan:Connect(function(input, processed)
	if processed then return end
	-- Same handler for both: ButtonR1 is the gamepad's F. `toggle` already
	-- carries every guard (out of round, dead, flat battery), so the
	-- controller cannot reach a state the keyboard cannot.
	if input.KeyCode == Enum.KeyCode.Y or input.KeyCode == Enum.KeyCode.ButtonR3 then toggleFocus() end
	if input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.ButtonR1 then
		toggle()
	end
end)

-- on (re)spawn: light off, battery back to FULL (so it refills each round reset),
-- and kill the beam the instant you die so a dead spectator isn't shining it
local boundCharacter
local function bindCharacter(char)
	if boundCharacter == char then return end
	boundCharacter = char
	setLights(false)
	battery = batteryMax()
	local hum = char:WaitForChild("Humanoid")
	hum.Died:Connect(function() setLights(false); applyFlashlightTouchTarget() end)
end
player.CharacterAdded:Connect(bindCharacter)
if player.Character then task.spawn(bindCharacter, player.Character) end

local function updateRoundVisibility()
	local inRound = roundBody()
	popupGui.Enabled = inRound
	if not inRound and on then setLights(false) end
	if inRound then mountWidget() end
end
player:GetAttributeChangedSignal("InRound"):Connect(updateRoundVisibility)
player:GetAttributeChangedSignal("Level2NewMapPreview"):Connect(updateRoundVisibility)
updateRoundVisibility()

-- ── teammates' flashlights (visible to YOU) ───────────────
-- Your own beam lives on your camera, so others can't see it — but everyone's
-- on/off flag replicates (FlashlightSync's FlashlightOn BoolValue). Attach a
-- beam to every OTHER character's head that follows their flag, so you see
-- teammates' lights sweeping around the maze.
local mateBeams = {} -- [character] = { core = ..., spill = ..., shaft/lens (visible beam) }
local MATE_SHAFT_LENGTH = 40
local mateRay = RaycastParams.new()
mateRay.FilterType = Enum.RaycastFilterType.Exclude
local lastMateProfile -- last applied profile name; nil forces a re-apply

local function attachMateBeam(char)
	task.spawn(function()
		local head = char:WaitForChild("Head", 30)
		if not head then return end
		if head:FindFirstChild("MateBeamCore") then return end

		local core = Instance.new("SpotLight")
		core.Name = "MateBeamCore"
		core.Color = Color3.fromRGB(255, 244, 214)
		core.Shadows = true
		core.Face = Enum.NormalId.Front -- follows where their head points
		core.Enabled = false
		core.Parent = head

		local spill = Instance.new("SpotLight")
		spill.Name = "MateBeamSpill"
		spill.Color = Color3.fromRGB(255, 240, 205)
		spill.Shadows = false
		spill.Face = Enum.NormalId.Front
		spill.Enabled = false
		spill.Parent = head

		-- FLASHLIGHT_REWORK_20261002: what you SEE of a teammate's torch -- a soft camera-facing light shaft that
		-- stops at the first wall, and a small glowing lens at their hand. Client-local, nothing replicates.
		local a0 = Instance.new("Attachment")
		a0.Name = "MateBeamA0"
		a0.Position = Vector3.new(0.35, -0.25, -0.7)
		a0.Parent = head
		local a1 = Instance.new("Attachment")
		a1.Name = "MateBeamA1_" .. char.Name
		a1.Parent = workspace.Terrain
		local shaft = Instance.new("Beam")
		shaft.Name = "MateBeamShaft"
		shaft.Attachment0, shaft.Attachment1 = a0, a1
		shaft.FaceCamera = true
		shaft.Segments = 1
		shaft.LightEmission = 1
		shaft.LightInfluence = 0
		shaft.Width0 = 0.35
		shaft.Color = ColorSequence.new(Color3.fromRGB(255, 240, 210))
		shaft.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(0.55, 0.93), NumberSequenceKeypoint.new(1, 1),
		})
		shaft.Enabled = false
		-- the Beam lives with a1, outside the character: a character clone (the Level 1 Mimic) never carries it
		shaft.Parent = a1
		local lensPart = Instance.new("Part")
		lensPart.Name = "MateLens"
		lensPart.Shape = Enum.PartType.Ball
		lensPart.Size = Vector3.new(0.26, 0.26, 0.26)
		lensPart.Material = Enum.Material.Neon
		lensPart.Color = Color3.fromRGB(255, 236, 196)
		lensPart.Anchored, lensPart.CanCollide, lensPart.CanQuery, lensPart.CanTouch = true, false, false, false
		lensPart.CastShadow = false
		lensPart.Transparency = 1
		lensPart.Parent = workspace

		mateBeams[char] = { core = core, spill = spill, head = head, a0 = a0, a1 = a1, shaft = shaft, lens = lensPart }
		lastMateProfile = nil -- new beam still has default values; force a re-apply
		char.AncestryChanged:Connect(function(_, parent)
			if not parent then -- character gone
				mateBeams[char] = nil
				a1:Destroy()
				lensPart:Destroy()
			end
		end)
	end)
end

local function hookMate(p)
	if p == player then return end -- your own beam is the camera torch above
	if p.Character then attachMateBeam(p.Character) end
	p.CharacterAdded:Connect(attachMateBeam)
end
Players.PlayerAdded:Connect(hookMate)
for _, p in ipairs(Players:GetPlayers()) do hookMate(p) end
Players.PlayerRemoving:Connect(function(p)
	if p.Character then mateBeams[p.Character] = nil end
end)

-- drive every mate beam from its owner's replicated flag EVERY frame — no
-- one-shot event binding to go stale, and it works exactly the same whether
-- you're alive, dead, or spectating (the beams live on THEIR heads, not yours)
RunService.Heartbeat:Connect(function()
	local profile = Profiles.Current()
	local profileChanged = profile ~= lastMateProfile
	lastMateProfile = profile
	local spectatedId = player:GetAttribute("Spectating") == true and player:GetAttribute("SpectateTargetUserId") or nil
	for char, beams in pairs(mateBeams) do
		local flag = char:FindFirstChild("FlashlightOn")
		local hum = char:FindFirstChildOfClass("Humanoid")
		local shine = flag ~= nil and flag.Value == true
			and hum ~= nil and hum.Health > 0
		local focused = char:GetAttribute("FlashlightFocused") == true
		if profileChanged or beams.Focused ~= focused then
			Profiles.Apply(Profiles.Mate, profile, beams.core, beams.spill, focused)
			beams.Focused = focused
		end
		beams.core.Enabled = shine
		beams.spill.Enabled = shine
		if beams.shaft then
			-- the teammate you are spectating: their own torch lens/shaft would sit right in front of your camera
			local owner = Players:GetPlayerFromCharacter(char)
			local visible = shine and not (owner and spectatedId and owner.UserId == spectatedId)
			beams.shaft.Enabled = visible
			beams.lens.Transparency = visible and 0 or 1
			if visible and beams.head.Parent then
				local origin = beams.a0.WorldPosition
				local look = beams.head.CFrame.LookVector
				mateRay.FilterDescendantsInstances = { char, beams.lens }
				local hit = workspace:Raycast(origin, look * MATE_SHAFT_LENGTH, mateRay)
				local reach = hit and (hit.Position - origin).Magnitude or MATE_SHAFT_LENGTH
				beams.a1.WorldPosition = origin + look * reach
				beams.shaft.Width1 = math.clamp(reach * 0.42, 0.8, 9)
				beams.lens.CFrame = CFrame.new(origin)
			end
		end
	end
end)

-- DevCheats owns the single output confirmation; this listener only applies
-- the battery state so pressing U never prints two messages.
player:GetAttributeChangedSignal("DevUnlimited"):Connect(function()
	local active = player:GetAttribute("DevUnlimited") == true
	if active then battery = batteryMax() end
end)

-- Level 4: a battery pack from the arcade prize case refills it (the server
-- counts pickups in Level4_BatteryRefill), and holding the beam on the Usher
-- costs extra (the server raises Level4_BeamingUsher while it is lit).
local USHER_DRAIN_PER_SEC = 3
local lastRefill = player:GetAttribute("Level4_BatteryRefill") or 0
player:GetAttributeChangedSignal("Level4_BatteryRefill"):Connect(function()
	local count = player:GetAttribute("Level4_BatteryRefill") or 0
	if type(count) == "number" and count > lastRefill then battery = batteryMax() end
	lastRefill = type(count) == "number" and count or 0
end)

-- The widget's input, refilled each frame so the heartbeat allocates no table (owner, 2026-10-08).
local widgetInput = {}

-- drain while on, recharge while off; die at empty
RunService.Heartbeat:Connect(function(dt)
	if player:GetAttribute("DevUnlimited") == true then
		battery = batteryMax() -- dev cheat (DevCheats, U key): never drains
	elseif on then
		battery = battery - (DRAIN_PER_SEC
			+ (player:GetAttribute("Level4_BeamingUsher") == true and USHER_DRAIN_PER_SEC or 0)) * dt
		if battery <= 0 then
			battery = 0
			setLights(false) -- (sets `on` false, so this fires once at the drain-out)
			-- the widget reads "LIGHT . EMPTY" until it can be switched on again (owner, 2026-10-08)
		end
	else
		battery = math.min(batteryMax(), battery + RECHARGE_PER_SEC * dt)
	end

	-- re-arm and fire warnings by percentage, so upgrades preserve the same UX.
	local batteryFraction = math.clamp(battery / batteryMax(), 0, 1)
	if player:GetAttribute("InRound") == true and player:GetAttribute("Spectating") ~= true
		and os.clock() - lastVitalReport >= .25 then
		lastVitalReport = os.clock()
		vitalRemote:FireServer("spectatevital", {Key = "Battery", Value = batteryFraction})
	end
	if batteryFraction > 0.55 then warned50 = false end
	if batteryFraction > 0.30 then warned25 = false end
	if on and batteryFraction <= 0.25 and not warned25 then
		warned25 = true
		warnBlink(3)
	elseif on and batteryFraction <= 0.50 and not warned50 then
		warned50 = true
		warnBlink(1)
	end

	-- the readouts: the PC widget (07 B; THEIR LIGHT while spectating) and the touch LIGHT cell (14 A)
	local spectating = player:GetAttribute("Spectating") == true
	local shown, shining, empty = true, on, not on and battery <= MIN_TO_TURN_ON
	if spectating then
		local id = player:GetAttribute("SpectateTargetUserId")
		local watched = type(id) == "number" and Players:GetPlayerByUserId(id) or nil
		local char = watched and watched.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local value = watched and watched:GetAttribute("SpectateBattery")
		local valid = watched and watched:GetAttribute("InRound") == true
			and watched:GetAttribute("Escaped") ~= true and hum and hum.Health > 0
			and type(value) == "number"
		shown = valid == true and not UIDevice.ScreenOwningModalOpen()
		if valid then
			batteryFraction = math.clamp(value, 0, 1)
			local flag = char:FindFirstChild("FlashlightOn")
			shining = flag and flag.Value == true
			empty = not shining and batteryFraction * BATTERY_BASE <= MIN_TO_TURN_ON
		end
	end
	local s = widgetInput
	s.Fraction, s.Empty, s.On, s.Spectating = batteryFraction, empty, shining == true, spectating
	s.Charging, s.Refused = not on and battery < batteryMax(), time() < refusedUntil
	s.Advanced, s.Focused = player:GetAttribute("ZyntraOwnsAdvancedEquipment") == true, isFocused()
	paintWidget(s, shown)
	-- The LIGHT cell paints your own light; applyFlashlightTouchTarget owns its Visible, and hides it
	-- while spectating (D11), so the watched battery is never painted into it (owner, 2026-10-08).
	if not spectating then paintLight(s) end
end)
