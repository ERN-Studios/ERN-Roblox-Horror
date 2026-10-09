-- NoiseReporter
-- PASTE INTO: StarterPlayer → StarterPlayerScripts → Insert Object → LocalScript → rename to "NoiseReporter"
-- Shift = sprint (loud), Ctrl = crouch (silent), walking = quiet.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local remote = RS:WaitForChild("Remotes"):WaitForChild("ReportNoise")
local glowstickRemote = RS:WaitForChild("Remotes"):WaitForChild("DropGlowstick")
local player = Players.LocalPlayer
local DevAccess = require(RS:WaitForChild("DevAccess"))
local UIDevice = require(RS:WaitForChild("UIDevice"))
local devAllowed = DevAccess.IsAllowed(player)
local function inRound() return player:GetAttribute("InRound") == true end

local WALK_SPEED, SPRINT_SPEED, CROUCH_SPEED = 16, 26, 8

-- loudness per movement state, 0..1 (server owns the real values)
local LOUDNESS = { sprint = 1.0, walk = 0.45, crouch = 0.0 }

local state = "walk"
local sprinting, crouching = false, false
local shiftSprintHeld, touchSprintHeld = false, false
local GLOWSTICK_COOLDOWN = 5
local lastGlowstickDrop = -math.huge
local currentChar
-- Forward-declared exactly like currentChar above: the death/respawn reset a
-- few lines down has to clear the touch SNEAK toggle, and the toggle itself is
-- built later with the rest of the touch cluster.
local showSneakEngaged

local function dropGlowstick()
	if not inRound() or os.clock() - lastGlowstickDrop < GLOWSTICK_COOLDOWN then return end
	local char, hum = currentChar()
	if not (char and hum and hum.Health > 0) then return end
	lastGlowstickDrop = os.clock()
	glowstickRemote:FireServer()
end

-- stamina: sprint is limited, drains while sprinting, recovers otherwise
local STAMINA_BASE     = 100
local SPRINT_DRAIN     = 16   -- ~6s of sprint on a full bar
local STAMINA_RECHARGE = 10   -- recovers while not sprinting
local STAMINA_RECOVER  = 25   -- must reach this after exhaustion before sprinting again
local function staminaMax()
	return STAMINA_BASE * math.max(1, tonumber(player:GetAttribute("ZyntraStaminaMultiplier")) or 1)
end
local stamina, exhausted = staminaMax(), false

-- ADRENALINE: while the Entity is on YOU (chasing, or blindly tracking you for
-- the few seconds after it loses sight — the server marks you "BeingChased"),
-- your stamina lasts ADRENALINE_MUL times longer, lingering a moment after.
local ADRENALINE_MUL    = 3
local ADRENALINE_LINGER = 4   -- seconds the boost outlives the chase itself
local adrenalineUntil = 0
player:GetAttributeChangedSignal("BeingChased"):Connect(function()
	if player:GetAttribute("BeingChased") ~= true then
		adrenalineUntil = os.clock() + ADRENALINE_LINGER -- chase just ended → linger
	end
end)
local function adrenalized()
	return player:GetAttribute("BeingChased") == true or os.clock() < adrenalineUntil
end

-- dev cheat (DevCheats toggles the local DevUnlimited attribute): stamina never drains
local function devUnlimited() return player:GetAttribute("DevUnlimited") == true end

currentChar = function()
	local char = player.Character
	return char, char and char:FindFirstChild("Humanoid")
end

local function applySpeed()
	local character, hum = currentChar()
	if not hum then return end
	local desiredSpeed
	if not inRound() then
		-- Lobby sprint is unlimited: it uses the regular sprint speed without
		-- touching the level stamina/exhaustion state.
		state = sprinting and "sprint" or "walk"
		desiredSpeed = sprinting and SPRINT_SPEED or WALK_SPEED
		character:SetAttribute("Level2_DesiredWalkSpeed", desiredSpeed)
		hum.WalkSpeed = desiredSpeed
		return
	end

	if crouching then
		state = "crouch"
		desiredSpeed = CROUCH_SPEED
	elseif sprinting and stamina > 0 and not exhausted then
		state = "sprint"
		desiredSpeed = SPRINT_SPEED
	else
		state = "walk"
		desiredSpeed = WALK_SPEED
	end
	-- Publish the intended speed separately from WalkSpeed. Deferred property
	-- signals can observe the slide controller's re-zero instead of this write;
	-- the attribute gives every movement lock an unambiguous restore target.
	character:SetAttribute("Level2_DesiredWalkSpeed", desiredSpeed)
	hum.WalkSpeed = desiredSpeed
end

local function refreshSprint()
	sprinting = shiftSprintHeld or touchSprintHeld
	applySpeed()
end

UIS.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.LeftShift then
		shiftSprintHeld = true; refreshSprint()
	elseif inRound() and input.KeyCode == Enum.KeyCode.LeftControl then
		crouching = true; applySpeed()
	elseif inRound() and (input.KeyCode == Enum.KeyCode.G or input.KeyCode == Enum.KeyCode.ButtonX) then
		dropGlowstick()
	end
end)

UIS.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		shiftSprintHeld = false; refreshSprint()
	elseif input.KeyCode == Enum.KeyCode.LeftControl then
		crouching = false; applySpeed()
	end
end)

player.CharacterAdded:Connect(function()
	task.wait(0.5)
	shiftSprintHeld, touchSprintHeld = false, false
	sprinting, crouching = false, false
	-- The touch SNEAK latch and its lit ring go with the crouch they stand for,
	-- or the button reads "sneaking" over a character that is standing up.
	if showSneakEngaged then showSneakEngaged(false) end
	applySpeed()
end)

-- report at 5Hz, only while actually moving
task.spawn(function()
	while task.wait(0.2) do
		if not inRound() or workspace:GetAttribute("SelectedLevel") ~= 1 then continue end
		local char, hum = currentChar()
		if not (char and hum and hum.Health > 0) then continue end

		local root = char:FindFirstChild("HumanoidRootPart")
		if not root then continue end

		-- only make noise if actually in motion
		if root.AssemblyLinearVelocity.Magnitude < 2 then continue end

		local loud = LOUDNESS[state]
		if loud > 0 then
			remote:FireServer(state)
		end
	end
end)

-- ── stamina bar ───────────────────────────────────────────
-- Matches the rest of the HUD: near-black translucent backdrop, rounded corners,
-- white fill that blushes red as it empties (same white→red as the battery).
-- Bottom-centre, slim; fades IN when you spend stamina, fades OUT when full.
local BAR_W, BAR_H  = 300, 14
local STA_FULL      = Color3.fromRGB(235, 235, 235) -- fill at full stamina
local STA_EMPTY     = Color3.fromRGB(230, 80, 60)   -- fill near empty / exhausted
local BAR_BG_ALPHA  = 0.6   -- backdrop transparency when shown
local BAR_FADE      = 5     -- how fast the bar fades in / out

local gui = Instance.new("ScreenGui")
gui.Name = "StaminaGui"
gui.ResetOnSpawn = false
-- Roblox's TouchGui sits at DisplayOrder 5. This cluster used to sit at the
-- default 0, which put our JUMP button UNDERNEATH Roblox's own -- two jump
-- buttons stacked to within nine pixels, with the ungated default one taking
-- every tap. We now own the jump control outright and draw above the default.
gui.DisplayOrder = 60
-- Keep the container alive in the lobby for the mobile RUN button. The actual
-- stamina bar remains fully hidden there, and the level-only controls are
-- hidden explicitly by updateRoundState().
gui.Enabled = true
gui.Parent = player:WaitForChild("PlayerGui")

-- Compact touch control cluster. Keyboard/controller paths remain unchanged.
-- RUN and JUMP form the right column; POV sits above the upright flashlight
-- immediately to their left, keeping the camera-dragging area clear.
-- Form factor, not last input, and re-read on every UIDevice.Changed rather
-- than captured once at load.
local function touchControls() return UIDevice.IsTouch() end

-- C_LIVE_CONTROL_RECTS_20260831. Every button this file builds registers its
-- own rectangle with UIDevice, so `Zones.Controls` is the union of what is
-- ACTUALLY drawn instead of a 168x290 block guessed at the display's corner.
-- The guess was 290px tall; the real stack on a landscape phone starts far
-- lower, and every objective readout was being pushed toward screen centre to
-- dodge a rectangle that was mostly empty.
local function makeTouchButton(name, text)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(1, 1)
	button.BackgroundColor3 = Color3.fromRGB(8, 10, 9)
	button.BackgroundTransparency = 0.52
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBold
	button.Text = text
	button.TextColor3 = Color3.fromRGB(235, 238, 232)
	button.TextSize = 17
	button.TextWrapped = true
	button.Visible = touchControls()
	button.ZIndex = 20
	button.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(220, 228, 218)
	stroke.Transparency = 0.48
	stroke.Thickness = 1.5
	stroke.Parent = button
	return button, stroke
end

local touchRunButton, runStroke = makeTouchButton("TouchRunHold", "RUN  »")
local touchJumpButton = makeTouchButton("TouchJump", "JUMP  ↑")
local touchPOVButton, povStroke = makeTouchButton("TouchPOV", "POV\n1ST")
local touchGlowButton = makeTouchButton("TouchDropGlowstick", "DROP\nGLOW")
touchPOVButton.TextSize = 13
touchPOVButton.Visible = touchControls() and devAllowed
touchGlowButton.TextSize = 12
-- Touch crouch. Same helper, same column, same layout pass as the rest of the
-- cluster. The label is constant: the engaged state is carried by the stroke
-- and tint below, the way POV carries its own, and NO key glyph is shown --
-- LeftControl stays a keyboard-only affordance.
local touchSneakButton, sneakStroke = makeTouchButton("TouchSneakHold", "SNEAK")
touchSneakButton:SetAttribute("SneakEngaged", false)

-- Registered AFTER all five exist, so the union is never partial.
for _, entry in ipairs({
	{"TouchRunHold", touchRunButton}, {"TouchJump", touchJumpButton},
	{"TouchPOV", touchPOVButton}, {"TouchDropGlowstick", touchGlowButton},
	{"TouchSneakHold", touchSneakButton},
}) do
	UIDevice.RegisterControlRect(entry[1], entry[2])
end

-- The whole cluster is laid out from UIDevice's control PLAN, so every other HUD
-- element in the game can avoid exactly the rectangle these buttons occupy. The
-- flashlight toggle takes its slot from the same plan (it used to sit
-- bottom-left, inside the movement thumbstick's activation region).
--
-- C_SHORT_SCREEN_CLUSTER_20260831 -- WHAT SHIPPED BROKEN.
--
-- The edge / buttonSize / gap arithmetic used to live here, a second copy of it
-- lived in FlashlightController, and a third lived in UIDevice to build the
-- reserved rectangle from. All three agreed on a vertical stack 242px tall. On a
-- 568x320 landscape phone the safe area is 262px tall, so the cluster owned the
-- screen and the objective readout -- which needs 56px above it -- abandoned the
-- safe right edge and drew itself in the middle of the display instead.
--
-- The arrangement is now UIDevice's decision, because UIDevice is the only place
-- that knows what has to fit above it, and this file positions whatever it is
-- handed. On a screen with room the plan is the column, unchanged to the pixel.
-- On a short landscape screen it is a row along the bottom edge, sized to the
-- daylight between the thumbstick's activation region and the safe right edge,
-- which reserves 67px instead of 242.
local function placeTouchControl(button, slot, bottomOverride)
	button.Position = UDim2.new(1, -slot.Right, 1, -(bottomOverride or slot.Bottom))
	button.Size = UDim2.fromOffset(slot.Width, slot.Height)
	if slot.TextSize then button.TextSize = slot.TextSize end
end

local function applyTouchControlLayout()
	if not touchControls() then return end
	local layout = UIDevice.Layout()
	local plan = layout.ControlPlan
	local slots = plan.Slots

	-- In a round our JUMP owns the thumb-nearest slot and Roblox's is suppressed.
	-- In the LOBBY the default jump is restored (it is the only jump there) and it
	-- occupies roughly that same slot, so RUN -- the one control the lobby leaves
	-- usable -- lifts clear of the engine's button rather than sitting on it.
	-- Measured through BottomOffsetFor, because the lift converts an ABSOLUTE
	-- edge into this gui's own bottom-relative offsets and the gui is inset to
	-- the safe area, not to the display.
	local runBottom = slots.TouchRunHold.Bottom
	if not inRound() then
		runBottom = math.max(runBottom,
			UIDevice.BottomOffsetFor(gui, layout.Zones.Jump.Top) + plan.Gap)
	end
	local lift = runBottom - slots.TouchRunHold.Bottom

	placeTouchControl(touchJumpButton, slots.TouchJump)
	placeTouchControl(touchRunButton, slots.TouchRunHold, runBottom)
	-- SNEAK stacks directly above RUN in the COLUMN, so it inherits the lobby
	-- lift and can never land on it. In the ROW it sits beside RUN instead and
	-- takes no lift: it is hidden in the lobby, and lifting it there would push a
	-- hidden button into the readout's headroom for no one's benefit.
	local sneakBottom = slots.TouchSneakHold.Bottom
	if plan.Mode == "column" then sneakBottom += lift end
	placeTouchControl(touchSneakButton, slots.TouchSneakHold, sneakBottom)
	placeTouchControl(touchPOVButton, slots.TouchPOV)
	placeTouchControl(touchGlowButton, slots.TouchDropGlowstick)
end

applyTouchControlLayout()
UIDevice.Changed:Connect(applyTouchControlLayout)

-- This game draws its own JUMP, with round/death/hiding gating the default
-- control knows nothing about, so Roblox's is suppressed while ours is the
-- owner. Ownership is per-round, NOT permanent: the cluster deliberately
-- provides no jump in the lobby, and suppressing the default there as well
-- would leave a touch player in the tunnel hub with no way to jump at all.
-- updateRoundState below re-evaluates this on every state change.

local touchSprintToggled = false
local touchSneakToggled = false
local function showRunEnabled(enabled)
	touchRunButton.BackgroundTransparency = enabled and 0.25 or 0.52
	touchRunButton.TextColor3 = enabled and Color3.fromRGB(125, 255, 175) or Color3.fromRGB(235, 238, 232)
	runStroke.Color = enabled and Color3.fromRGB(125, 255, 175) or Color3.fromRGB(220, 228, 218)
	touchRunButton.Text = enabled and "RUN  ON" or "RUN  »"
end

-- SNEAK is a TOGGLE, not a hold like RUN, and deliberately so: crouch-silent is
-- a SUSTAINED stealth state -- you hold it for a whole corridor while the
-- Entity sweeps past -- so a hold-to-crouch button would pin the very thumb the
-- player needs on the thumbstick to steer, leaving a touch player able to be
-- silent OR moving but never both. RUN can be hold-shaped because a sprint is a
-- burst; sneaking is not. Tap to enter crouch, tap again to leave it.
showSneakEngaged = function(engaged)
	touchSneakToggled = engaged
	touchSneakButton.BackgroundTransparency = engaged and 0.25 or 0.52
	touchSneakButton.TextColor3 = engaged and Color3.fromRGB(150, 205, 255)
		or Color3.fromRGB(235, 238, 232)
	sneakStroke.Color = engaged and Color3.fromRGB(150, 205, 255)
		or Color3.fromRGB(220, 228, 218)
	-- The supported way to observe the toggle from outside this script (the UI
	-- regression suite reads it instead of reaching for a local).
	touchSneakButton:SetAttribute("SneakEngaged", engaged)
end

-- Tap once to sprint, tap again to stop. A held GUI touch no longer steals
-- the phone/tablet camera finger, so players can steer and look around freely.
touchRunButton.Activated:Connect(function()
	touchSprintToggled = not touchSprintToggled
	touchSprintHeld = touchSprintToggled
	showRunEnabled(touchSprintToggled)
	refreshSprint()
end)

-- Drives the SAME `crouching` upvalue the LeftControl path drives, through the
-- SAME applySpeed(), so speed and LOUDNESS.crouch stay in exactly one place.
touchSneakButton.Activated:Connect(function()
	if not inRound() then return end
	showSneakEngaged(not touchSneakToggled)
	crouching = touchSneakToggled
	applySpeed()
end)

touchJumpButton.Activated:Connect(function()
	if not inRound() then return end
	local character, hum = currentChar()
	if character and character:GetAttribute("Level2_ForcedSliding") == true then return end
	if hum and hum.Health > 0 and hum:GetState() ~= Enum.HumanoidStateType.Dead then
		hum.Jump = true
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end)

touchGlowButton.Activated:Connect(dropGlowstick)

local function firstPersonEnabled()
	return player:GetAttribute("DevCheatThirdPerson") ~= true
end

local function refreshPOVButton()
	local firstPerson = firstPersonEnabled()
	touchPOVButton.Text = firstPerson and "POV\n3RD" or "POV\n1ST"
	touchPOVButton.TextColor3 = firstPerson and Color3.fromRGB(130, 220, 255)
		or Color3.fromRGB(235, 238, 232)
	povStroke.Color = firstPerson and Color3.fromRGB(130, 220, 255)
		or Color3.fromRGB(220, 228, 218)
end

touchPOVButton.Activated:Connect(function()
	if not (devAllowed and inRound()) then return end
	local command = player:WaitForChild("PlayerScripts"):FindFirstChild("DevCheatCommand")
	if command and command:IsA("BindableEvent") then
		command:Fire("thirdPerson")
	end
end)
player:GetAttributeChangedSignal("DevCheatThirdPerson"):Connect(refreshPOVButton)
refreshPOVButton()

player.CharacterAdded:Connect(function()
	touchSprintToggled = false
	touchSprintHeld = false
	showRunEnabled(false)
	task.delay(0.75, refreshPOVButton)
end)

local staBg = Instance.new("Frame")
staBg.AnchorPoint = Vector2.new(0.5, 1)
staBg.Position = UDim2.new(0.5, 0, 1, -22)
staBg.Size = UDim2.new(0, BAR_W, 0, BAR_H)
-- The rectangle the objective readout will occupy on this device, asked for at
-- the WIDEST footprint any level declares. Read from UIDevice.ObjectivePanelSize
-- rather than copied out of it, so a level that grows its panel moves the bar out
-- of the way instead of quietly ending up underneath it.
local function objectiveReserve()
	local width, height = 0, 0
	for _, size in pairs(UIDevice.ObjectivePanelSize) do
		width = math.max(width, size.X)
		height = math.max(height, size.Y)
	end
	return UIDevice.TopRightPanel(width, height)
end

-- The fixed 300px bar overflowed a 375-wide portrait screen and sat on top of
-- the movement zone. It is now capped to the safe width and lifted into the
-- content band on touch.
local function applyStaminaLayout()
	local layout = UIDevice.Layout()
	staBg.AnchorPoint = Vector2.new(0.5, 1)
	if not layout.IsTouch then
		staBg.Size = UDim2.new(0, BAR_W, 0, BAR_H)
		staBg.Position = UDim2.new(0.5, 0, 1, -22)
		return
	end
	-- On touch the bar lives in the lane BETWEEN the two movement zones. A
	-- landscape phone leaves only about 65 vertical pixels clear above the
	-- controls -- not enough to share with the alert banner -- but the corridor
	-- down the middle is free at any height.
	local corridor = layout.Corridor
	-- Both branches place an ABSOLUTE centre and an ABSOLUTE bottom, and both are
	-- converted. The X used to be written straight in as a gui offset (and in
	-- portrait as a 0.5 scale of the GUI, which is the housing's centre rather
	-- than the safe area's whenever a device has a horizontal inset).
	local centre, bottom
	if corridor.Width >= 120 then
		staBg.Size = UDim2.new(0, math.min(BAR_W, corridor.Width), 0, BAR_H)
		centre = (corridor.Left + corridor.Right) * .5
		bottom = layout.Display.Bottom - 18
	else
		-- Portrait, or a SHORT landscape screen where the cluster now spans the
		-- bottom edge and closes the corridor entirely. Fall back to the safe
		-- band -- but keep out of the objective readout, which since
		-- C_OBJECTIVE_ALWAYS_THE_SAFE_EDGE_20260831 genuinely owns the upper-right
		-- corner and is a full 101px tall there. A 300px bar centred on a 568px
		-- screen reaches x 434 and the readout starts at 312, so the two crossed:
		-- the stamina bar was drawn straight through the objective text.
		--
		-- Capped only when the two actually share a band. In portrait the bar sits
		-- hundreds of pixels below the readout and keeps its full width.
		bottom = layout.SafeBottom - 10
		local right = layout.Safe.Right
		local reserve = objectiveReserve()
		if reserve.Height > 0 and bottom > reserve.Top and bottom - BAR_H < reserve.Bottom then
			right = math.min(right, reserve.Left - 8)
		end
		local lane = math.max(0, right - layout.Safe.Left)
		staBg.Size = UDim2.new(0, math.min(BAR_W, lane), 0, BAR_H)
		centre = (layout.Safe.Left + right) * .5
	end
	staBg.Position = UDim2.new(0, select(1, UIDevice.LocalOffset(gui, centre, 0)),
		1, -UIDevice.BottomOffsetFor(gui, bottom))
end
staBg.BackgroundColor3 = Color3.new(0, 0, 0)
staBg.BackgroundTransparency = 1 -- starts hidden (full stamina)
staBg.BorderSizePixel = 0
staBg.Parent = gui
local bgc = Instance.new("UICorner"); bgc.CornerRadius = UDim.new(0, 5); bgc.Parent = staBg

local staFill = Instance.new("Frame")
staFill.AnchorPoint = Vector2.new(0, 0.5)
staFill.Position = UDim2.new(0, 2, 0.5, 0)
staFill.Size = UDim2.new(1, -4, 1, -4)
staFill.BackgroundColor3 = STA_FULL
staFill.BackgroundTransparency = 1
staFill.BorderSizePixel = 0
staFill.Parent = staBg
local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(0, 4); fc.Parent = staFill
applyStaminaLayout()
UIDevice.Changed:Connect(applyStaminaLayout)

local barShown = 0 -- eased 0–1 visibility

RunService.Heartbeat:Connect(function(dt)
	if not inRound() then
		stamina = staminaMax()
		exhausted = false
		state = "walk"
		player:SetAttribute("Stamina", 1)
		barShown = 0
		staBg.BackgroundTransparency = 1
		staFill.BackgroundTransparency = 1
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local moving = root
		and Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude > 2

	if devUnlimited() then
		stamina = staminaMax() -- dev cheat: never drains
		exhausted = false
	elseif state == "sprint" and moving
		and not (char and char:GetAttribute("Level2_ForcedSliding") == true) then
		-- adrenaline: the Entity is (or was just) on you → stamina lasts 3x longer
		stamina = stamina - (SPRINT_DRAIN / (adrenalized() and ADRENALINE_MUL or 1)) * dt
		if stamina <= 0 then
			stamina = 0
			exhausted = true
			applySpeed() -- drop out of sprint
		end
	else
		stamina = math.min(staminaMax(), stamina + STAMINA_RECHARGE * dt)
		if exhausted and stamina >= STAMINA_RECOVER then
			exhausted = false
			applySpeed() -- sprint available again if shift still held
		end
	end

	local frac = stamina / staminaMax()
	-- publish stamina (0–1) so SoundController can drive the winded-breathing sound
	player:SetAttribute("Stamina", frac)

	-- bar: width + white→red colour (solid red while exhausted), fade with use
	staFill.Size = UDim2.new(frac, -4, 1, -4)
	staFill.BackgroundColor3 = exhausted and STA_EMPTY
		or STA_FULL:Lerp(STA_EMPTY, math.clamp(1 - frac, 0, 1) * 0.85)
	local wantShown = (frac < 0.999) and 1 or 0
	barShown = barShown + (wantShown - barShown) * math.clamp(dt * BAR_FADE, 0, 1)
	staBg.BackgroundTransparency = 1 - barShown * (1 - BAR_BG_ALPHA)
	staFill.BackgroundTransparency = 1 - barShown
end)

-- Every state in which the movement cluster must not be usable. Hiding alone is
-- not enough: a TextButton left Active keeps swallowing taps through a
-- transparent background, so all four go through UIDevice.SetInteractive, which
-- clears Active/Selectable/Modal as well as Visible.
local function controlsAvailable()
	if not touchControls() then return false end
	if not inRound() then return false end
	if player:GetAttribute("Escaped") == true then return false end
	if player:GetAttribute("Level3_Hiding") == true then return false end
	if player:GetAttribute("Spectating") == true then return false end
	-- A modal owns the screen: the store terminal, the dev phone, the Zyntra
	-- re-entry prompt, or the post-round panel.
	if player:GetAttribute("ZyntraStoreOpen") == true then return false end
	if player:GetAttribute("DevPhoneOpen") == true then return false end
	if player:GetAttribute("ZyntraReentryOpen") == true then return false end
	-- ...and the party dialog, which was the one screen-owning modal missing
	-- from this list while `modalOwnsScreen` below already carried it. The two
	-- disagreeing is how the cluster stayed drawn under a modal that UIDevice,
	-- the Level 3 reader and the Zyntra opener all treat as owning the screen.
	if player:GetAttribute("QueueModalOpen") == true then return false end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return false end
	return true
end

-- A modal owns the screen whether or not a round is running. `controlsAvailable`
-- answers false out of a round for a different reason -- there is no round --
-- and the RUN exception below rides on that, so the lobby's RUN button stayed
-- live and Active underneath the Zyntra terminal, competing with a modal that
-- now uses the whole safe area. Stated separately so the exception cannot
-- swallow it.
local function modalOwnsScreen()
	return player:GetAttribute("ZyntraStoreOpen") == true
		or player:GetAttribute("DevPhoneOpen") == true
		or player:GetAttribute("ZyntraReentryOpen") == true
		or player:GetAttribute("QueueModalOpen") == true
end

local function updateRoundState()
	local active = inRound()
	local usable = controlsAvailable()
	gui.Enabled = true
	-- RUN stays available in the lobby (it is how a player sprints to a station)
	-- but is gated on every other unavailable state once a round starts -- and,
	-- in or out of a round, on no modal owning the screen.
	UIDevice.SetInteractive(touchRunButton,
		touchControls() and (usable or not active) and not modalOwnsScreen())
	UIDevice.SetInteractive(touchJumpButton, usable)
	-- SNEAK is a level-only control: there is nothing to crouch away from in the
	-- lobby, and applySpeed() ignores crouch out of a round anyway.
	UIDevice.SetInteractive(touchSneakButton, usable)
	UIDevice.SetInteractive(touchPOVButton, usable and devAllowed)
	UIDevice.SetInteractive(touchGlowButton, usable)
	-- Own the jump control only while in a round. In the lobby the default
	-- touch jump comes back, because that is the only jump there is there.
	UIDevice.SuppressDefaultJump(touchControls() and active)
	-- The RUN slot depends on whether the engine's jump button is showing.
	applyTouchControlLayout()
	-- Stamina is only meaningful while the player is the one running. Dead,
	-- escaped or spectating, the bar is stale information sitting in the same
	-- band as the spectate caption, so it stands down with the controls.
	staBg.Visible = active
		and player:GetAttribute("Escaped") ~= true
		and player:GetAttribute("Spectating") ~= true
	if not active then
		lastGlowstickDrop = -math.huge
		shiftSprintHeld, touchSprintHeld = false, false
		sprinting, crouching = false, false
		touchSprintToggled = false
		showRunEnabled(false)
		showSneakEngaged(false)
		applySpeed()
	end
end
player:GetAttributeChangedSignal("InRound"):Connect(updateRoundState)
for _, attribute in ipairs({"Escaped", "Level3_Hiding", "Spectating",
	"ZyntraStoreOpen", "DevPhoneOpen", "ZyntraReentryOpen", "QueueModalOpen"}) do
	player:GetAttributeChangedSignal(attribute):Connect(updateRoundState)
end
UIDevice.Changed:Connect(updateRoundState)
local function bindLife(character)
	local humanoid = character:WaitForChild("Humanoid", 8)
	if humanoid then humanoid.Died:Connect(updateRoundState) end
	updateRoundState()
end
if player.Character then task.spawn(bindLife, player.Character) end
player.CharacterAdded:Connect(bindLife)
updateRoundState()
