-- NoiseReporter
-- PASTE INTO: StarterPlayer → StarterPlayerScripts → Insert Object → LocalScript → rename to "NoiseReporter"
-- Shift = sprint (loud); Ctrl / gamepad L3 / touch SNEAK = crouch (silent).

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local remotes = RS:WaitForChild("Remotes")
local remote = remotes:WaitForChild("ReportNoise")
local glowstickRemote = remotes:WaitForChild("DropGlowstick")
local crouchRemote = remotes:WaitForChild("SetCrouching")
local player = Players.LocalPlayer
local DevAccess = require(RS:WaitForChild("DevAccess"))
local UIDevice = require(RS:WaitForChild("UIDevice"))
local devAllowed = DevAccess.IsAllowed(player)
local previewAllowed = DevAccess.IsLevel6PreviewAllowed(player)
-- Level6 preview participates in local movement only; public progression attributes stay untouched.
local function inPreview() return previewAllowed and player:GetAttribute("Level6InRound") == true end
local function inRound() return player:GetAttribute("InRound") == true or inPreview() end
local function isHiding()
	return player:GetAttribute(if inPreview() then "Level6_Hiding" else "Level3_Hiding") == true
end
local function isEscaped()
	return player:GetAttribute(if inPreview() then "Level6Escaped" else "Escaped") == true
end
local vitalRemote = remotes:WaitForChild("RoundStatus")
local lastVitalReport = -math.huge

local WALK_SPEED, SPRINT_SPEED, CROUCH_SPEED = 16, 26, 8

-- loudness per movement state, 0..1 (server owns the real values)
local LOUDNESS = { sprint = 1.0, walk = 0.45, crouch = 0.0 }

local state = "walk"
local sprinting, crouching = false, false
local shiftSprintHeld, touchSprintHeld, gamepadSprintHeld = false, false, false
-- The touch RUN toggle, declared up here because the B2 RUN cell's paintRun reads it (HUD_B2_TOUCH, owner, 2026-10-08).
local touchSprintToggled = false
local windowFocused = true
local crouchInterrupted = false -- CROUCH_LATCH_20261010: a Control hold that the window losing focus cut short
local keyboardCrouchHeld, controllerCrouchToggled, touchSneakToggled = false, false, false
local lastPublishedCrouch: boolean? = nil
local crouchRequestSerial = 0
local GLOWSTICK_COOLDOWN = 5
local lastGlowstickDrop = -math.huge
local currentChar
-- Forward-declared exactly like currentChar above: the death/respawn reset a
-- few lines down has to clear the touch SNEAK toggle, and the toggle itself is
-- built later with the rest of the touch cluster.
local showSneakEngaged

local function dropGlowstick()
	-- ButtonX also exits a Level 3 table. Never let that one press spawn a
	-- glowstick underneath the table while the hide controller is releasing us.
	if inPreview() or not inRound() or isHiding()
		or os.clock() - lastGlowstickDrop < GLOWSTICK_COOLDOWN then return end
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
	if inPreview() then return STAMINA_BASE end
	return STAMINA_BASE * math.max(1, tonumber(player:GetAttribute("ZyntraStaminaMultiplier")) or 1)
end
local stamina, exhausted = staminaMax(), false

-- ADRENALINE: existing entities publish BeingChased; Level 2's pipe giant has
-- its own chase mark so Pool Foam cannot clear the giant's stamina boost.
-- Read the combined state only; never write either server-owned chase mark.
local ADRENALINE_MUL    = 3
local ADRENALINE_LINGER = 4   -- seconds the boost outlives the LAST active chase
local adrenalineUntil = 0
local function chaseActive()
	if inPreview() then return player:GetAttribute("Level6BeingChased") == true end
	return player:GetAttribute("BeingChased") == true
		or (workspace:GetAttribute("SelectedLevel") == 2
			and player:GetAttribute("Level2_PoolSlideChased") == true)
end
local wasChased = chaseActive()
local function updateChaseAdrenaline()
	local chased = chaseActive()
	if wasChased and not chased then
		adrenalineUntil = os.clock() + ADRENALINE_LINGER
	end
	wasChased = chased
end
player:GetAttributeChangedSignal("BeingChased"):Connect(updateChaseAdrenaline)
player:GetAttributeChangedSignal("Level6BeingChased"):Connect(updateChaseAdrenaline)
player:GetAttributeChangedSignal("Level6InRound"):Connect(updateChaseAdrenaline)
player:GetAttributeChangedSignal("Level2_PoolSlideChased"):Connect(updateChaseAdrenaline)
workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(updateChaseAdrenaline)
local function adrenalized()
	return chaseActive() or os.clock() < adrenalineUntil
end

-- dev cheat (DevCheats toggles the local DevUnlimited attribute): stamina never drains
local function devUnlimited() return player:GetAttribute("DevUnlimited") == true end

currentChar = function()
	local char = player.Character
	return char, char and char:FindFirstChild("Humanoid")
end

local CROUCH_BLOCKED_STATES = {
	[Enum.HumanoidStateType.Dead] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.Climbing] = true,
	[Enum.HumanoidStateType.Physics] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
	[Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.Seated] = true,
	[Enum.HumanoidStateType.Swimming] = true,
}

local function movementAvailable()
	if not inRound() or isEscaped()
		or isHiding()
		or player:GetAttribute("Spectating") == true
		or player:GetAttribute("ZyntraStoreOpen") == true
		or player:GetAttribute("DevPhoneOpen") == true
		or player:GetAttribute("ZyntraReentryOpen") == true
		or player:GetAttribute("QueueModalOpen") == true then
		return false
	end
	local character, humanoid = currentChar()
	return character ~= nil and humanoid ~= nil and humanoid.Health > 0
end

local function crouchAllowed()
	if not movementAvailable() or (player:GetAttribute("Level6PlaygroundPreview") ~= true
		and workspace:GetAttribute(if inPreview() then "Level6RoundActive" else "RoundActive") ~= true) then return false end
	local character, humanoid = currentChar()
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return character ~= nil and humanoid ~= nil and root ~= nil
		and root:IsA("BasePart") and not root.Anchored
		and character:GetAttribute("Level2_ForcedSliding") ~= true
		and character:GetAttribute("Level2_RagdollServerActive") ~= true
		and CROUCH_BLOCKED_STATES[humanoid:GetState()] ~= true
end

local function publishCrouch(active)
	active = active == true
	-- Local prediction removes a network round-trip from the owner's camera and
	-- pose. Other clients deliberately ignore this local-only attribute and use
	-- the server-owned Crouching attribute below.
	player:SetAttribute("LocalCrouching", active)
	if lastPublishedCrouch == active then return end
	lastPublishedCrouch = active
	crouchRequestSerial += 1
	crouchRemote:FireServer(active, crouchRequestSerial)
end

-- Speed Potion (ZYNTRA_SPEED_POTION_20260916). Forward-declared like currentChar
-- above so applySpeed can use it while the body stays below, beside the speeds
-- it scales -- which is also what keeps it inside the block the offline
-- controller test lifts out of this file (applySpeed down to refreshCrouch).
local speedBoost

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
	-- HUD_B3 (D6; owner, 2026-10-08): the raw movement state for Round HUD's marker, client-local,
	-- compare-first. Written here, before the hiding / slide early return, and never in the lobby.
	if player:GetAttribute("MoveNoise") ~= state then player:SetAttribute("MoveNoise", state) end
	-- ONE multiplier, applied after the movement state has chosen its speed, so
	-- crouch/walk/sprint all scale (8/16/26 -> 8.8/17.6/28.6) from the single
	-- existing writer instead of a competing WalkSpeed loop. `state` and the
	-- stamina drain keyed off it are deliberately untouched: the potion is speed,
	-- not stamina, and the noise a player makes must not change with it.
	desiredSpeed *= speedBoost()
	-- Level 4: carried film reels weigh the carrier down. The server owns the
	-- factor (Objective Controller); anything outside [0.5, 1) is ignored.
	local carry = workspace:GetAttribute("SelectedLevel") == 4 and player:GetAttribute("Level4_CarrySpeedFactor")
	if type(carry) == "number" and carry >= 0.5 and carry < 1 then desiredSpeed *= carry end
	-- Publish the intended speed separately from WalkSpeed. Deferred property
	-- signals can observe the slide controller's re-zero instead of this write;
	-- the attribute gives every movement lock an unambiguous restore target.
	character:SetAttribute("Level2_DesiredWalkSpeed", desiredSpeed)
	-- The hide controller and the Level 2 slide own physical movement while
	-- these locks are active. Keep their restore target current without fighting
	-- their authoritative WalkSpeed = 0 writes.
	if isHiding()
		or character:GetAttribute("Level2_ForcedSliding") == true
		or character:GetAttribute("Level2_RagdollServerActive") == true then
		return
	end
	hum.WalkSpeed = desiredSpeed
end

-- The SERVER owns the boost: ZyntraMonetization consumes the potion and then
-- writes ZyntraSpeedBoostUntil (a workspace server clock) and
-- ZyntraSpeedBoostMultiplier on the Player. This only reads them, and refuses
-- anything outside [1, 1.5] so a stray write can never become a speed hack.
-- Order matters: everything cheap and local is checked before the clock, so a
-- player with no boost -- the normal case, every frame -- costs two lookups.
function speedBoost()
	if inPreview() or not inRound() then return 1 end
	local expires = player:GetAttribute("ZyntraSpeedBoostUntil")
	-- NaN fails every comparison, so `expires > 0` rejects it along with 0/nil.
	if type(expires) ~= "number" or not (expires > 0) then return 1 end
	if expires <= workspace:GetServerTimeNow() then return 1 end
	local multiplier = player:GetAttribute("ZyntraSpeedBoostMultiplier")
	if type(multiplier) ~= "number" or not (multiplier >= 1 and multiplier <= 1.5) then return 1 end
	return multiplier
end

local function refreshCrouch()
	local requested = keyboardCrouchHeld or controllerCrouchToggled or touchSneakToggled
	crouching = requested and crouchAllowed()
	publishCrouch(crouching)
	applySpeed()
end

local function cancelCrouch()
	keyboardCrouchHeld = false
	controllerCrouchToggled = false
	if showSneakEngaged then
		showSneakEngaged(false)
	else
		touchSneakToggled = false
	end
	crouching = false
	publishCrouch(false)
	applySpeed()
end

-- Server acknowledgements keep the owner's predicted pose/speed honest when a
-- request is rejected (for example because another server system anchored the
-- root in the same frame). Replicated false transitions also cover later
-- server-side cancellation without waiting for another local input.
crouchRemote.OnClientEvent:Connect(function(acceptedState, responseSerial)
	if typeof(acceptedState) ~= "boolean" or typeof(responseSerial) ~= "number" then return end
	-- A lifecycle clear carries the latest request the server had processed when
	-- it happened. If we have since issued a newer transition, that older clear
	-- is stale and the response to our newer request is the one that decides.
	if responseSerial ~= crouchRequestSerial then return end
	if acceptedState == false and (crouching or keyboardCrouchHeld
		or controllerCrouchToggled or touchSneakToggled) then
		cancelCrouch()
	end
end)

-- The ONE definition of "the player is asking to sprint", across all three input
-- families. Every place that used to spell out `shiftSprintHeld or
-- touchSprintHeld` reads this instead, so a fourth source can never again be
-- added to one of them and missed in the other three -- which is exactly how
-- gamepad players ended up unable to sprint at all.
local function sprintRequested()
	return shiftSprintHeld or touchSprintHeld or gamepadSprintHeld
end

local function keyboardSprintHeld()
	-- Physical key state remains reliable when a Roblox core control (such as
	-- Shift Lock) consumes the event before this script sees it.
	if not windowFocused then return false end
	return UIS:IsKeyDown(Enum.KeyCode.LeftShift)
		or UIS:IsKeyDown(Enum.KeyCode.RightShift)
end

local function gamepadSprintDown()
	-- The physical read behind the ButtonL2 latch, and it exists for the same
	-- reason keyboardSprintHeld does: InputEnded is not guaranteed. A trigger
	-- held while the window loses focus, or while the controller is unplugged,
	-- never sends its release. Heartbeat repairs this in the lobby AND a round.
	-- Every connected slot, not just Gamepad1: InputBegan latches on whichever
	-- pad the press came from, so a repair that only ever asked Gamepad1 would
	-- clear a Gamepad2 player's latch on every frame. An unplugged
	-- controller is simply absent from this list, which is the release the
	-- missing InputEnded never sent.
	if not windowFocused then return false end
	for _, gamepad in ipairs(UIS:GetConnectedGamepads()) do
		if UIS:IsGamepadButtonDown(gamepad, Enum.KeyCode.ButtonL2) then return true end
	end
	return false
end

local function keyboardCrouchHeldNow()
	-- Releasing one Control key must not stand up while the other remains held.
	return UIS:IsKeyDown(Enum.KeyCode.LeftControl)
		or UIS:IsKeyDown(Enum.KeyCode.RightControl)
end

local function refreshSprint()
	sprinting = sprintRequested()
	applySpeed()
end

UIS.WindowFocusReleased:Connect(function()
	windowFocused = false
	shiftSprintHeld, gamepadSprintHeld = false, false
	refreshSprint()
	-- CROUCH_LATCH_20261010: Control is part of the Mac's own shortcuts (Spaces, Mission Control, screenshot to
	-- clipboard). The key-down reaches the game, the key-up goes with the focus, and the body stayed kneeling at half
	-- speed until Control or Space was pressed again.
	if keyboardCrouchHeld then
		keyboardCrouchHeld, crouchInterrupted = false, true
		refreshCrouch()
	end
end)
UIS.WindowFocused:Connect(function()
	windowFocused = true -- the next Heartbeat reads the current hardware state
end)

UIS.InputBegan:Connect(function(input, processed)
	-- Hold-to-sprint on the LEFT TRIGGER. ButtonA stays Roblox's own jump,
	-- ButtonL3 is crouch and ButtonX is the glowstick; L2 was unused across the
	-- whole project. Read before the `processed` gate for the same reason Shift
	-- is: this is a movement modifier, not a UI action, and a core control that
	-- claimed the press must not silently disable sprinting.
	if input.KeyCode == Enum.KeyCode.ButtonL2 then
		gamepadSprintHeld = true
		refreshSprint()
		return
	end
	local isSprintKey = input.KeyCode == Enum.KeyCode.LeftShift
		or input.KeyCode == Enum.KeyCode.RightShift
	if isSprintKey then
		-- Never bind gameplay shortcuts while typing, but accept Shift even when a
		-- Roblox core action marked it processed.
		if UIS:GetFocusedTextBox() then return end
		shiftSprintHeld = true
		refreshSprint()
		return
	end
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Space and crouching then
		cancelCrouch()
	elseif (input.KeyCode == Enum.KeyCode.LeftControl
		or input.KeyCode == Enum.KeyCode.RightControl) and crouchAllowed() then
		keyboardCrouchHeld = true
		refreshCrouch()
	elseif input.KeyCode == Enum.KeyCode.ButtonL3
		and (controllerCrouchToggled or crouchAllowed()) then
		controllerCrouchToggled = not controllerCrouchToggled
		refreshCrouch()
	elseif inRound() and (input.KeyCode == Enum.KeyCode.G or input.KeyCode == Enum.KeyCode.ButtonX) then
		dropGlowstick()
	end
end)

UIS.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		-- Releasing one Shift key must not cancel the other.
		shiftSprintHeld = keyboardSprintHeld()
		refreshSprint()
	elseif input.KeyCode == Enum.KeyCode.ButtonL2 then
		gamepadSprintHeld = false
		refreshSprint()
	elseif input.KeyCode == Enum.KeyCode.LeftControl
		or input.KeyCode == Enum.KeyCode.RightControl then
		keyboardCrouchHeld = keyboardCrouchHeldNow()
		refreshCrouch()
	end
end)

player.CharacterAdded:Connect(function()
	task.wait(0.5)
	-- The immediate CharacterAdded UI hook below already clears the old avatar's
	-- touch latch. Preserve a new RUN tap made during this startup delay instead
	-- of silently turning it off while leaving the button lit.
	shiftSprintHeld = keyboardSprintHeld()
	gamepadSprintHeld = gamepadSprintDown()
	sprinting = sprintRequested()
	keyboardCrouchHeld, controllerCrouchToggled, crouching = false, false, false
	lastPublishedCrouch = nil
	-- The touch SNEAK latch and its lit ring go with the crouch they stand for,
	-- or the button reads "sneaking" over a character that is standing up.
	if showSneakEngaged then showSneakEngaged(false) end
	publishCrouch(false)
	applySpeed()
end)

-- report at 5Hz, only while actually moving
task.spawn(function()
	while task.wait(0.2) do
		-- Level 1's Entity and Level 2's Pool Foam both hear the shared
		-- NoiseRegistry: EntityAI drains this remote during a Level 1 round, the
		-- live Pool Foam session drains it during a Level 2 one. Level 3's Mall
		-- Manager does not listen at all, so reporting there is pure traffic.
		-- Level 4's Usher hears it too (its controller drains the remote).
		local level = workspace:GetAttribute("SelectedLevel")
		if inPreview() or not inRound() or (level ~= 1 and level ~= 2 and level ~= 4)
			or player:GetAttribute("Level6PlaygroundPreview") == true then continue end -- nothing in the playground listens
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
-- UIDevice's 4 + 4 grid (GRID_CONTROL_PLAN_20261008): JUMP, RUN, SNEAK, LIGHT
-- along the bottom, GLOW, KIT, SHIELD above them and the developer-only POV in
-- the slot the template leaves empty. This file owns JUMP, RUN, SNEAK, GLOW, POV.
-- Form factor, not last input, and re-read on every UIDevice.Changed rather
-- than captured once at load.
local function touchControls() return UIDevice.IsTouch() end

-- C_LIVE_CONTROL_RECTS_20260831. Every button this file builds registers its
-- own rectangle with UIDevice, so `Zones.Controls` is the union of what is
-- ACTUALLY drawn instead of a 168x290 block guessed at the display's corner.
-- The guess was 290px tall; the real stack on a landscape phone starts far
-- lower, and every objective readout was being pushed toward screen centre to
-- dodge a rectangle that was mostly empty.
-- == B2 touch cells (14 A; owner, 2026-10-08) ==
-- HUD_B2_TOUCH. artifacts/hud-final-20261008/b2/B2-DESIGN.md 2.1-2.3 and 4. The five cells are clones
-- of ReplicatedStorage.ZyntraHUD.Templates.HUD_Touch, mounted once on every client, PC included, so
-- the registered roots never change. Looked up after game.Loaded and never waited for (critic C3):
-- RoundEntryControlsReady is this script's last line, and a place without the bundle must not stall
-- round entry. A missing template is RoundHud's warning by path and a nil cell (D14), which is not
-- drawn, not registered and, for JUMP, leaves Roblox's own jump unsuppressed. Code writes only
-- colours, Glyph / Label text and SneakEngaged; geometry is applyTouchControlLayout's and TextSize
-- is ShopBinder.scaleText's.
local touchRunButton, touchJumpButton, touchSneakButton, touchGlowButton, touchPOVButton
local touchLook = {} -- cell -> its stroke, Glyph and Label, with the template's own colours
local touchPalette -- ShopBinder.Palette, set once the cells exist
do
	if not game:IsLoaded() then game.Loaded:Wait() end
	local hudModule = RS:FindFirstChild("RoundHud")
	local shopUI = RS:FindFirstChild("ZyntraShopUI")
	local binderModule = shopUI and shopUI:FindFirstChild("ShopBinder")
	if hudModule and binderModule then
		local Hud, Binder = require(hudModule), require(binderModule)
		touchPalette = Binder.Palette
		local function mount(path, key, glyphText)
			local cell = Hud.Mount("HUD_Touch", "TouchCluster/" .. path, gui, {Name = key})
			if not cell then return nil end
			-- Selectable before the first SetInteractive: UIDevice remembers the first value it
			-- sees, and the template ships true (B2-DESIGN 2.2 rule 2).
			cell.AutoButtonColor, cell.Selectable, cell.Visible, cell.Active = false, false, false, false
			local stroke = cell:FindFirstChildOfClass("UIStroke")
			local glyph, label = Binder.text(Binder.find(cell, "Glyph")), Binder.text(Binder.find(cell, "Label"))
			if glyph and glyphText then glyph.Text = glyphText end
			touchLook[cell] = {Stroke = stroke, StrokeColor = stroke and stroke.Color, Glyph = glyph,
				GlyphColor = glyph and glyph.TextColor3, Label = label, LabelColor = label and label.TextColor3}
			return cell
		end
		-- RUN's glyph and GLOW's * are template copy and are never written.
		touchJumpButton = mount("Cell_Jump", "TouchJump", "\u{2191}")
		touchRunButton = mount("Cell_Run", "TouchRunHold")
		touchSneakButton = mount("Cell_Sneak", "TouchSneakHold", "\u{2193}")
		touchGlowButton = mount("Cell_Glow", "TouchDropGlowstick")
		touchPOVButton = mount("Cell_Jump", "TouchPOV") -- JUMP relabelled by refreshPOVButton
		if touchSneakButton then touchSneakButton:SetAttribute("SneakEngaged", false) end
	else
		warn("[NoiseReporter] ReplicatedStorage.RoundHud or ZyntraShopUI.ShopBinder is missing: no touch cells")
	end
end

-- RUN's one look, recomputed from state every frame, so it is the same after a respawn by
-- construction. The stroke is the stamina ring (critic C6, sampled off the approved phone frames):
-- Coral while winded, else Amber while the toggle is on or stamina is at or under 25 %, else the
-- template's Line. Glyph and label never change colour. It writes the stroke's Color only, never
-- its Thickness (scaleText owns that); keyed on the cell's width as well (critic C8). Its own
-- Heartbeat connection: the main one returns early in the lobby and while spectating.
local function paintRun()
	local look = touchRunButton and touchLook[touchRunButton]
	if not (look and look.Stroke) then return end
	local tone = if exhausted then "Coral"
		elseif touchSprintToggled or stamina / staminaMax() <= 0.25 then "Amber" else "Line"
	local width = touchRunButton.AbsoluteSize.X
	if look.Tone == tone and look.Width == width then return end
	look.Tone, look.Width = tone, width
	look.Stroke.Color = if tone == "Line" then look.StrokeColor else touchPalette[tone]
end
RunService.Heartbeat:Connect(paintRun)

-- SNEAK is a TOGGLE, not a hold like RUN, and deliberately so: crouch-silent is
-- a SUSTAINED stealth state -- you hold it for a whole corridor while the
-- Entity sweeps past -- so a hold-to-crouch button would pin the very thumb the
-- player needs on the thumbstick to steer, leaving a touch player able to be
-- silent OR moving but never both. RUN can be hold-shaped because a sprint is a
-- burst; sneaking is not. Tap to enter crouch, tap again to leave it.
-- Engaged: stroke, glyph and label in RailTeal; off is the template, at creation and on reset alike.
showSneakEngaged = function(engaged)
	touchSneakToggled = engaged
	local look = touchSneakButton and touchLook[touchSneakButton]
	if not look then return end
	local tone = engaged and touchPalette.RailTeal
	if look.Stroke then look.Stroke.Color = tone or look.StrokeColor end
	if look.Glyph then look.Glyph.TextColor3 = tone or look.GlyphColor end
	if look.Label then look.Label.TextColor3 = tone or look.LabelColor end
	-- The supported way to observe the toggle from outside this script (the UI
	-- regression suite reads it instead of reaching for a local).
	touchSneakButton:SetAttribute("SneakEngaged", engaged)
end

local function firstPersonEnabled()
	return player:GetAttribute("DevCheatThirdPerson") ~= true
end

-- POV over the view a tap switches to; no colour state.
local function refreshPOVButton()
	local look = touchPOVButton and touchLook[touchPOVButton]
	if not look then return end
	if look.Label then look.Label.Text = "POV" end
	if look.Glyph then look.Glyph.Text = if firstPersonEnabled() then "3RD" else "1ST" end
end
-- == end B2 touch cells ==

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
-- handed. On a screen with room the plan is the 4 + 4 grid (52 px cells on a
-- phone, 64 on a tablet). On a short landscape screen it is a row along the
-- bottom edge, sized to the daylight between the thumbstick's activation region
-- and the safe right edge.
-- HUD_B2_TOUCH: a cell is placed and sized from its slot on every pass (a mounted cell may be
-- resized, never re-mounted); a nil cell (missing template) is skipped; TextSize is scaleText's.
local function placeTouchControl(button, slot, bottomOverride)
	if not button then return end
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = UDim2.new(1, -slot.Right, 1, -(bottomOverride or slot.Bottom))
	button.Size = UDim2.fromOffset(slot.Width, slot.Height)
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
	-- HUD_B2_TOUCH (critic C14): only when RUN's columns actually meet the engine's
	-- button. At 844x390 RUN (x 673..725) is clear of it (749..819) and stays down;
	-- at 667x375 with no housing the two share 572..595 and RUN lifts. Measured
	-- through RightOffsetFor for the same reason as above.
	local run, jump = slots.TouchRunHold, layout.Zones.Jump
	local runBottom = run.Bottom
	if not inRound() and run.Right < UIDevice.RightOffsetFor(gui, jump.Left)
		and run.Right + run.Width > UIDevice.RightOffsetFor(gui, jump.Right) then
		runBottom = math.max(runBottom,
			UIDevice.BottomOffsetFor(gui, jump.Top) + plan.Gap)
	end

	placeTouchControl(touchJumpButton, slots.TouchJump)
	placeTouchControl(touchRunButton, slots.TouchRunHold, runBottom)
	-- SNEAK sits beside RUN and takes no lift: it is hidden in the lobby.
	placeTouchControl(touchSneakButton, slots.TouchSneakHold)
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

-- Tap once to sprint, tap again to stop. A held GUI touch no longer steals
-- the phone/tablet camera finger, so players can steer and look around freely.
-- The cell's look is paintRun's (the B2 section above), read from this toggle.
if touchRunButton then
	touchRunButton.Activated:Connect(function()
		touchSprintToggled = not touchSprintToggled
		touchSprintHeld = touchSprintToggled
		refreshSprint()
	end)
end

-- Drives the SAME `crouching` upvalue the LeftControl path drives, through the
-- SAME applySpeed(), so speed and LOUDNESS.crouch stay in exactly one place.
if touchSneakButton then
	touchSneakButton.Activated:Connect(function()
		if not crouchAllowed() and not touchSneakToggled then return end
		showSneakEngaged(not touchSneakToggled)
		refreshCrouch()
	end)
end

-- TOUCH_JUMP_GROUNDED_20261008 (owner: "people can double jump and some infinity hop"). This button has to force
-- the Jumping state (the control module writes Humanoid.Jump every frame, so setting it alone is lost), and a
-- forced state does not ask whether there is ground under the feet: every tap in the air was another jump, and
-- tapping on was flying. It jumps from the ground, a ladder or water only, and not twice within a jump's first
-- moments (the floor is still read for a frame or two after the feet have left it).
if touchJumpButton then -- HUD_B2_TOUCH: nil when its template is missing (D14)
	local lastJump = 0
	local FROM = {
		[Enum.HumanoidStateType.Running] = true, [Enum.HumanoidStateType.RunningNoPhysics] = true,
		[Enum.HumanoidStateType.Landed] = true, [Enum.HumanoidStateType.GettingUp] = true,
		[Enum.HumanoidStateType.Climbing] = true, [Enum.HumanoidStateType.Swimming] = true,
	}
	touchJumpButton.Activated:Connect(function()
		if not inRound() then return end
		local character, hum = currentChar()
		if character and character:GetAttribute("Level2_ForcedSliding") == true then return end
		if not (hum and hum.Health > 0) then return end
		local state = hum:GetState()
		if not FROM[state] or os.clock() - lastJump < 0.4 then return end
		local onSomething = hum.FloorMaterial ~= Enum.Material.Air
			or state == Enum.HumanoidStateType.Climbing or state == Enum.HumanoidStateType.Swimming
		if not onSomething then return end
		lastJump = os.clock()
		if crouching then cancelCrouch() end
		hum.Jump = true
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
	end)
end

if touchGlowButton then touchGlowButton.Activated:Connect(dropGlowstick) end

if touchPOVButton then
	touchPOVButton.Activated:Connect(function()
		if not (devAllowed and inRound()) then return end
		local command = player:WaitForChild("PlayerScripts"):FindFirstChild("DevCheatCommand")
		if command and command:IsA("BindableEvent") then
			command:Fire("thirdPerson")
		end
	end)
end
player:GetAttributeChangedSignal("DevCheatThirdPerson"):Connect(refreshPOVButton)
refreshPOVButton()

player.CharacterAdded:Connect(function()
	touchSprintToggled = false
	touchSprintHeld = false
	task.delay(0.75, refreshPOVButton)
end)

-- == B3 stamina bar (10 C; owner, 2026-10-08) ==
-- HUD_B3: artifacts/hud-final-20261008/b3/B3-DESIGN.md 4 and its critic findings K1, K4, K5 and K10.
-- The bar is a clone of ReplicatedStorage.ZyntraHUD.Templates.HUD_PC/StaminaBar, mounted through
-- RoundHud into StaminaGui: bottom-centre on PC and pad; on touch at half size in the corridor, and
-- hidden when the corridor cannot hold it, so the RUN ring is all there is (D9). Attention owns the
-- CanvasGroup's Visible: 100 % while draining or WINDED, 55 % recovering, hidden when full (D14).
-- Code writes only the Fill's width and colour, Winded.Visible and the root's placement. The numbers
-- below are pinned against Round HUD's marker by test_round_hud_local (B3-DESIGN 2.2): the bar root's
-- bottom above Safe.Bottom on PC and on touch, the touch scale, the lift over SpectateGui's caption,
-- and B1's PC kit row (24 + 232 + 8 + 280). When the right-hand slot cannot fit, a fixed upper band
-- clears the entire kit, refusal caption and detector; no obstacle-following jitter is introduced.
local BAR_BOTTOM, BAR_BOTTOM_TOUCH, BAR_TOUCH_SCALE, SPECTATE_LIFT = 24, 4, 0.5, 92
local BAR_BOTTOM_NARROW = 228 -- above the maximum kit, refusal caption and active detector band
local KIT_RIGHT, BAR_HALF = 544, 160
local barHud -- RoundHud, only when the B2 lookup above found it and ShopBinder (touchPalette ~= nil)
if touchPalette then barHud = require(RS:FindFirstChild("RoundHud")) end
-- Root, Attention, Fill, Winded, Scale, Room, Frac, Tone, Mode, Watched, WatchedDrain, WatchedId
local bar: any = {} -- typed any: the analyzer gives up inferring this table's shape otherwise
local lastDrainAt = -math.huge

-- (Re)mounts the bar when its scale changes (PC and pad 1, touch BAR_TOUCH_SCALE), then places it.
-- A device flip leaves exactly one StaminaBar. Runs from updateRoundState.
local function placeBar()
	local layout = UIDevice.Layout()
	local touch = layout.IsTouch == true
	local scale = if touch then BAR_TOUCH_SCALE else 1
	if scale ~= bar.Scale then
		if bar.Root then bar.Root:Destroy() end
		table.clear(bar)
		bar.Scale = scale
		if barHud then -- a plain if: `barHud and barHud.Mount(...)` would drop the second return
			bar.Root, bar.Attention = barHud.Mount("HUD_PC", "StaminaBar", gui, {Name = "StaminaBar",
				Scale = scale, Touch = touch, Attention = {Hold = 0, Rest = 0.55}})
		end
		if bar.Root then
			bar.Fill, bar.Winded = bar.Root:FindFirstChild("Fill", true), bar.Root:FindFirstChild("Winded", true)
			if bar.Fill and bar.Winded then
				bar.Winded.Visible = false -- the template ships its WINDED sample visible
				bar.Root.AnchorPoint = Vector2.new(0.5, 1)
			else
				warn("[NoiseReporter] HUD_PC/StaminaBar has no Fill or Winded: no stamina bar")
				bar.Root:Destroy()
				bar.Root = nil
			end
		end
	end
	local spectating = player:GetAttribute("Spectating") == true
	-- K1: out of spectating, forget the watched target, so watching the same player again later
	-- starts from a first sample, not from that player's value of the last spectate.
	if not spectating then bar.WatchedId = nil end
	if not bar.Root then return end
	local safe, corridor = layout.Safe, layout.Corridor
	local narrow = not touch and safe.Right - safe.Left < KIT_RIGHT + 8 + 2 * BAR_HALF
	local centre = if touch then (corridor.Left + corridor.Right) / 2
		elseif narrow then (safe.Left + safe.Right) / 2
		else math.max((safe.Left + safe.Right) / 2, safe.Left + KIT_RIGHT + 8 + BAR_HALF)
	local bottom = safe.Bottom - (if touch then BAR_BOTTOM_TOUCH elseif narrow then BAR_BOTTOM_NARROW else BAR_BOTTOM)
		- (if spectating then SPECTATE_LIFT else 0)
	bar.Room = if touch then corridor.Width >= 2 * BAR_HALF * BAR_TOUCH_SCALE + 8
		else safe.Right - safe.Left >= 2 * BAR_HALF and bottom - 26 >= safe.Top
	bar.Root.Position = UIDevice.LocalPosition(gui, centre, bottom)
end

-- frac nil = off. Writes the Fill and Winded on a change, and calls Attention only when the mode
-- changes: WINDED and DRAIN never dim, RECOVER rests at 55 %, FULL and OFF hide (B3-DESIGN 2.4).
local function paintBar(frac, winded, draining)
	if not bar.Root then return end
	if frac ~= nil then
		local tone = if winded then "Coral" elseif frac <= 0.25 then "Amber" else "Cream"
		if tone ~= bar.Tone or math.abs(frac - (bar.Frac or -1)) > 0.001 then
			bar.Frac, bar.Tone = frac, tone
			bar.Fill.Size = UDim2.fromScale(frac, 1)
			bar.Fill.BackgroundColor3 = touchPalette[tone]
			bar.Winded.Visible = winded == true
		end
	end
	local mode = if frac == nil or not bar.Room then "OFF" elseif winded then "WINDED"
		elseif draining then "DRAIN" elseif frac < 0.999 then "RECOVER" else "OFF"
	if mode == bar.Mode then return end
	bar.Mode = mode
	if mode == "OFF" then
		bar.Attention:Hide()
	elseif mode == "RECOVER" then
		bar.Attention:Show("bar")
	else
		bar.Attention:Show("bar", true)
	end
end

-- Spectating (D15, K1): the watched player's fraction, never WINDED (only the fraction replicates).
-- The remote reports at 4 Hz, so the trend comes from value changes; the first sample of a target,
-- and the first after an invalid frame, has none and reads RECOVER.
local function paintWatched(frac, id) -- id = SpectateTargetUserId
	if frac == nil or id ~= bar.WatchedId then bar.Watched, bar.WatchedDrain, bar.WatchedId = nil, nil, id end
	if frac == nil then paintBar(nil); return end
	if bar.Watched ~= nil and frac ~= bar.Watched then bar.WatchedDrain = frac < bar.Watched end
	bar.Watched = frac
	paintBar(frac, false, bar.WatchedDrain == true)
end
-- == end B3 stamina bar ==
local lastFrac, lastExhausted = -1, nil -- last values written; -1/nil force the first frame to write

-- The boost STARTS as an attribute change, but it ENDS when a server timestamp
-- passes and nothing fires at all. The in-round loop below watches this edge
-- rather than adding a second WalkSpeed loop just to count six seconds down.
local boostActive = false
local function refreshSpeedBoost()
	boostActive = speedBoost() > 1
	applySpeed()
end
player:GetAttributeChangedSignal("ZyntraSpeedBoostUntil"):Connect(refreshSpeedBoost)
player:GetAttributeChangedSignal("ZyntraSpeedBoostMultiplier"):Connect(refreshSpeedBoost)
player:GetAttributeChangedSignal("Level4_CarrySpeedFactor"):Connect(applySpeed)

-- POOL_EXIT_20261010 (owner: "no walking problems in Level 2"). A swimming body pressed against a pool's edge treads
-- water there for good: measured in the stepwell's pool, six seconds without an inch, while one jump put it on the
-- deck. Walking squarely at a deck now climbs out by itself. Level 2 only, only in the Swimming state, only onto a
-- top that is a real floor (two studs deep, level, with room to stand), so a pillar cap or a thin rim never throws
-- anybody anywhere. A dry level never runs more than the first two tests.
local poolExitStep
do
	local nextCheck, pressedSince, lastHop, lastWall, lastDir = 0, nil, 0, nil, nil
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater, params.RespectCanCollide = true, true
	local room = OverlapParams.new()
	room.FilterType = Enum.RaycastFilterType.Exclude
	room.RespectCanCollide = true
	local STANDING = Vector3.new(2.4, 4.6, 2.4) -- the round body's own box, a little slim so a wall beside the spot is fine
	local function idle() pressedSince, lastWall, lastDir = nil, nil, nil end
	poolExitStep = function()
		local now = os.clock()
		if now < nextCheck then return end
		nextCheck = now + 0.1
		if workspace:GetAttribute("SelectedLevel") ~= 2 or player:GetAttribute("InRound") ~= true then return idle() end
		local character, hum = currentChar()
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (hum and root and hum.Health > 0 and hum:GetState() == Enum.HumanoidStateType.Swimming)
			or root.Anchored or not movementAvailable()
			or character:GetAttribute("Level2_ForcedSliding") == true
			or character:GetAttribute("Level2_RagdollServerActive") == true then
			return idle()
		end
		local move, velocity = hum.MoveDirection, root.AssemblyLinearVelocity
		local flat = Vector3.new(move.X, 0, move.Z)
		if flat.Magnitude < 0.3 or Vector3.new(velocity.X, 0, velocity.Z).Magnitude > 2.5 then return idle() end
		local dir = flat.Unit
		params.FilterDescendantsInstances = {character}
		-- A wall squarely ahead, at the water line or just under it.
		local wall = workspace:Raycast(root.Position, dir * 3.5, params)
			or workspace:Raycast(root.Position - Vector3.new(0, 1.5, 0), dir * 3.5, params)
		if not wall or wall.Normal:Dot(dir) > -0.7 then return idle() end
		-- Its top: level, no more than three studs over the body, and still floor two studs further in.
		local over = Vector3.new(wall.Position.X, root.Position.Y + 5, wall.Position.Z)
		local top = workspace:Raycast(over + dir * 0.7, Vector3.new(0, -7, 0), params)
		local deck = top and workspace:Raycast(over + dir * 2.7, Vector3.new(0, -7, 0), params)
		if not (top and deck) or top.Normal.Y < 0.9 or math.abs(deck.Position.Y - top.Position.Y) > 0.6 then return idle() end
		local rise = top.Position.Y - root.Position.Y
		if rise < -1 or rise > 3 then return idle() end
		room.FilterDescendantsInstances = {character}
		local landing = CFrame.new(top.Position + dir * 1 + Vector3.new(0, STANDING.Y / 2 + 0.3, 0))
		if #workspace:GetPartBoundsInBox(landing, STANDING, room) > 0 then return idle() end
		-- The same edge, the same way, for a third of a second: that is somebody trying to get out.
		if lastWall ~= wall.Instance or not lastDir or lastDir:Dot(dir) < 0.95 then pressedSince = now end
		lastWall, lastDir = wall.Instance, dir
		if now - pressedSince < 0.3 or now - lastHop < 0.8 then return end
		lastHop = now
		idle()
		hum.Jump = true
		hum:ChangeState(Enum.HumanoidStateType.Jumping) -- the control module rewrites Jump every frame: force the state
	end
end

RunService.Heartbeat:Connect(function(dt)
	-- InputEnded can be lost on disconnect/focus loss in any phase. Reconcile
	-- physical holds without changing the independent touch RUN toggle.
	if player:GetAttribute("Spectating") == true then
		local id = player:GetAttribute("SpectateTargetUserId")
		local watched = type(id) == "number" and Players:GetPlayerByUserId(id) or nil
		local hum = watched and watched.Character and watched.Character:FindFirstChildOfClass("Humanoid")
		local value = watched and watched:GetAttribute("SpectateStamina")
		local valid = watched and watched:GetAttribute("InRound") == true
			and watched:GetAttribute("Escaped") ~= true and hum and hum.Health > 0
			and type(value) == "number"
		-- HUD_B3 (D15, K1): the watched player's stamina, lifted over the spectate caption by placeBar.
		paintWatched(valid and not UIDevice.ScreenOwningModalOpen() and math.clamp(value, 0, 1) or nil, id)
		-- Force the own-body display to refresh when spectating ends.
		lastFrac = -1
		return
	end
	local physicalShift = UIS:GetFocusedTextBox() == nil and keyboardSprintHeld()
	local physicalTrigger = gamepadSprintDown()
	if shiftSprintHeld ~= physicalShift or gamepadSprintHeld ~= physicalTrigger then
		shiftSprintHeld, gamepadSprintHeld = physicalShift, physicalTrigger
		refreshSprint() -- also repairs the in-round state used by stamina/noise
	end
	-- CROUCH_LATCH_20261010: the same repair for the Control hold. A crouch begins on a key-down; the only hold this
	-- puts back is one the window's own focus loss interrupted while the key stayed down.
	if windowFocused then
		local physicalCrouch = keyboardCrouchHeldNow()
		if keyboardCrouchHeld and not physicalCrouch then
			keyboardCrouchHeld = false
			refreshCrouch()
		elseif crouchInterrupted and physicalCrouch and not keyboardCrouchHeld
			and UIS:GetFocusedTextBox() == nil and crouchAllowed() then
			keyboardCrouchHeld = true
			refreshCrouch()
		end
		crouchInterrupted = false
	end
	poolExitStep()
	if not inRound() then
		stamina = staminaMax()
		exhausted = false

		-- Lobby sprint is unlimited and self-healing. Keep input state as the source
		-- of truth and repair WalkSpeed if avatar loading or a core script restores
		-- Roblox's default speed while the player is still holding RUN.
		sprinting = sprintRequested()
		state = sprinting and "sprint" or "walk"
		local character, hum = currentChar()
		local desiredSpeed = sprinting and SPRINT_SPEED or WALK_SPEED
		if character and hum and hum.Health > 0 then
			if character:GetAttribute("Level2_DesiredWalkSpeed") ~= desiredSpeed then
				character:SetAttribute("Level2_DesiredWalkSpeed", desiredSpeed)
			end
			if hum.WalkSpeed ~= desiredSpeed then hum.WalkSpeed = desiredSpeed end
		end

		-- Lobby stamina never moves, so the attribute is compared before it is
		-- written. Deliberately NOT through lastFrac/lastExhausted: those are the
		-- in-round report's dirty cache. HUD_B3: the bar keeps its own (paintBar),
		-- and the lobby never shows it.
		if player:GetAttribute("Stamina") ~= 1 then player:SetAttribute("Stamina", 1) end
		paintBar(nil)
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local moving = root
		and Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude > 2
	if (speedBoost() > 1) ~= boostActive then refreshSpeedBoost() end

	if devUnlimited() then
		stamina = staminaMax() -- dev cheat: never drains
		exhausted = false
	elseif state == "sprint" and moving
		and not (char and char:GetAttribute("Level2_ForcedSliding") == true) then
		-- adrenaline: the Entity is (or was just) on you → stamina lasts 3x longer
		lastDrainAt = os.clock() -- HUD_B3: the bar reads "draining" for 0.5 s after this (D14)
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
	if not inPreview() and os.clock() - lastVitalReport >= .25 then
		lastVitalReport = os.clock()
		vitalRemote:FireServer("spectatevital", {Key = "Stamina", Value = math.clamp(frac, 0, 1)})
	end
	if exhausted ~= lastExhausted or math.abs(frac - lastFrac) > 0.001 then
		lastFrac, lastExhausted = frac, exhausted
		-- publish stamina (0–1) so SoundController can drive the winded-breathing sound
		player:SetAttribute("Stamina", frac)
	end
	-- HUD_B3: dead or escaped, the bar stands down; so does it under the touch Level 4 keypad (K5,
	-- until B7). The Level 6 playground keeps it, as before (K10).
	local _, hum = currentChar()
	paintBar(hum and hum.Health > 0 and not isEscaped() and player:GetAttribute("Level4CardOpen") ~= true
		and frac or nil, exhausted, os.clock() - lastDrainAt < 0.5)
end)

-- Every state in which the movement cluster must not be usable. Hiding alone is
-- not enough: a TextButton left Active keeps swallowing taps through a
-- transparent background, so all five go through UIDevice.SetInteractive, which
-- clears Active/Selectable/Modal as well as Visible.
-- HUD_B2_TOUCH (D13): the cells stand down under all eight screen-owning modals, UIDevice's one
-- predicate (UIDevice.Changed fires, forced, on each of them). movementAvailable(), which drives
-- gameplay, keeps its own four.
local function controlsAvailable()
	if not touchControls() then return false end
	return movementAvailable() and not UIDevice.ScreenOwningModalOpen()
end

-- A modal owns the screen whether or not a round is running. `controlsAvailable`
-- answers false out of a round for a different reason -- there is no round --
-- and the RUN exception below rides on that, so the lobby's RUN button stayed
-- live and Active underneath the Zyntra terminal, competing with a modal that
-- now uses the whole safe area. Stated separately so the exception cannot
-- swallow it. HUD_B2_TOUCH (D13): the same eight modals as controlsAvailable.
local function modalOwnsScreen()
	return UIDevice.ScreenOwningModalOpen()
end

local wasRoundActive = inRound()
local function updateRoundState()
	placeBar() -- HUD_B3: remount on a device flip, re-place on Spectating
	local active = inRound()
	local usable = controlsAvailable()
	if not movementAvailable() and (crouching or keyboardCrouchHeld
		or controllerCrouchToggled or touchSneakToggled) then
		cancelCrouch()
	end
	gui.Enabled = true
	-- RUN stays available in the lobby (it is how a player sprints to a station)
	-- but is gated on every other unavailable state once a round starts -- and,
	-- in or out of a round, on no modal owning the screen.
	-- HUD_B2_TOUCH: each cell is nil when its template is missing (D14), and a nil cell is not drawn.
	if touchRunButton then
		UIDevice.SetInteractive(touchRunButton,
			touchControls() and (usable or not active) and not modalOwnsScreen())
	end
	if touchJumpButton then UIDevice.SetInteractive(touchJumpButton, usable) end
	-- SNEAK is a level-only control: there is nothing to crouch away from in the
	-- lobby, and applySpeed() ignores crouch out of a round anyway.
	if touchSneakButton then UIDevice.SetInteractive(touchSneakButton, usable) end
	if touchPOVButton then UIDevice.SetInteractive(touchPOVButton, usable and devAllowed) end
	-- MOBILE_QA_20261008: not in the live levels either (5 and 6, which carry Level6PlaygroundPreview): GameManager's
	-- drop handler only serves its own rounds, so the button was there and did nothing.
	if touchGlowButton then
		UIDevice.SetInteractive(touchGlowButton, usable and not inPreview() and player:GetAttribute("Level6PlaygroundPreview") ~= true)
	end
	-- Own the jump control only while in a round. In the lobby the default
	-- touch jump comes back, because that is the only jump there is there.
	-- Without our JUMP cell (D14) the default is never suppressed: a phone must always have a jump.
	UIDevice.SuppressDefaultJump(touchControls() and active and touchJumpButton ~= nil)
	-- The RUN slot depends on whether the engine's jump button is showing.
	applyTouchControlLayout()
	if not active then
		lastGlowstickDrop = -math.huge
		-- Reset level-only latches once on the round→lobby transition. Ordinary
		-- lobby UI/layout refreshes must not switch RUN off underneath the player.
		if wasRoundActive then
			-- The touch latch is a UI toggle and is dropped. Shift and the left
			-- trigger are PHYSICAL holds, so a player who leaves a round still
			-- holding one keeps sprinting in the lobby instead of stopping dead
			-- until they let go and press again.
			shiftSprintHeld, touchSprintHeld = keyboardSprintHeld(), false
			sprinting = sprintRequested()
			cancelCrouch()
			touchSprintToggled = false
		end
		applySpeed()
	elseif not isHiding() then
		-- The hiding controller restores the speed it captured on entry. Reapply
		-- the CURRENT aggregate input state on exit so crouch -> hide -> stand
		-- cannot leave the player stuck at the old 8-stud crouch speed.
		applySpeed()
	end
	wasRoundActive = active
end
player:GetAttributeChangedSignal("InRound"):Connect(updateRoundState)
player:GetAttributeChangedSignal("Level6InRound"):Connect(updateRoundState)
for _, attribute in ipairs({"Escaped", "Level3_Hiding", "Level6Escaped", "Level6_Hiding", "Spectating",
	"ZyntraStoreOpen", "DevPhoneOpen", "ZyntraReentryOpen", "QueueModalOpen"}) do
	player:GetAttributeChangedSignal(attribute):Connect(updateRoundState)
end
UIDevice.Changed:Connect(updateRoundState)
local function bindLife(character)
	local humanoid = character:WaitForChild("Humanoid", 8)
	if humanoid then
		humanoid.Died:Connect(updateRoundState)
		humanoid.StateChanged:Connect(function(_, newState)
			if crouching and CROUCH_BLOCKED_STATES[newState] then cancelCrouch() end
		end)
	end
	local function cancelForLevel2Lock()
		if crouching and (character:GetAttribute("Level2_ForcedSliding") == true
			or character:GetAttribute("Level2_RagdollServerActive") == true) then
			cancelCrouch()
		end
	end
	character:GetAttributeChangedSignal("Level2_ForcedSliding"):Connect(cancelForLevel2Lock)
	character:GetAttributeChangedSignal("Level2_RagdollServerActive"):Connect(cancelForLevel2Lock)
	-- HIP_HEIGHT_20261010 (owner, with pictures: "gliding in the floor and almost cant move"; in Level 2 "cannot really
	-- walk forward and slides back all the time"). The round body can reach this client in pieces (5 of its 16 parts at
	-- CharacterAdded, the legs a tenth of a second later). The engine works the hip height out from what is there
	-- (0, -0.1 or 0.94 instead of 2.6) and never again: the body stands in the floor, finds no ground under it, and in
	-- Level 2's ankle-deep water it "swims". Measured 2026-10-10: four of four round starts in a row. The server
	-- always has the whole rig, so its figure is the truth; this client simulates the body, so it is put right here.
	local function holdHipHeight()
		local want = character:GetAttribute("ZyntraHipHeight")
		if humanoid and type(want) == "number" and want >= 0.5 and want <= 6 and math.abs(humanoid.HipHeight - want) > 0.01 then
			humanoid.HipHeight = want
		end
	end
	character:GetAttributeChangedSignal("ZyntraHipHeight"):Connect(holdHipHeight)
	if humanoid then humanoid:GetPropertyChangedSignal("HipHeight"):Connect(holdHipHeight) end
	holdHipHeight()
	updateRoundState()
end
if player.Character then task.spawn(bindLife, player.Character) end
player.CharacterAdded:Connect(bindLife)
updateRoundState()
-- Client-local readiness: all gameplay input and lifecycle handlers are wired.
player:SetAttribute("RoundEntryControlsReady", true)
