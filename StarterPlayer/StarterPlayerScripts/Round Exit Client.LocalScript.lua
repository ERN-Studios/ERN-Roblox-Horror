-- Round Exit Client  (BACK_TO_LOBBY_20260914, Trello card 74)
--
-- One player-local way out of a running level. An alive player HOLDS a chip at
-- the top-left of the safe area -- the L key on a keyboard, a finger on the chip
-- on touch; a dead or escaped player reaches a confirm card from the spectate
-- band (SpectateController fires PlayerScripts.RoundExitPrompt), because there
-- the cursor is already free and a question with two buttons reads better. The
-- server owns the decision either way: GameManager's "leaveround" removes only
-- this player from the party, and the round goes on for everybody else.
--
-- HOLD_TO_LEAVE_20260916 (card 74, second pass). WHY A HOLD: in a live round the
-- first-person camera owns the mouse, so a chip that has to be CLICKED is
-- unreachable unless the cursor is unlocked mid-chase, which the owner rejected.
-- A hold needs no pointer at all, on either device.
--
-- THE CONTRACT, stated once here because it is spread over a dozen call sites:
--
--   * HOLD_SECONDS = 1.5 seconds of held time, accumulated from RenderStepped's
--     own delta, so the bar fills in the same wall-clock time at 15 FPS and at
--     240. Deliberately NOT os.clock(): in this project os.clock is process CPU
--     time (see the Studio note in CLAUDE.md), which is not what a player holds
--     a key for. The frame delta is wall time by definition.
--   * A tap, a click or an early release leaves NOTHING behind -- progress goes
--     back to 0 the instant the hold stops, and only a full 1.5 s sends.
--   * Every frame re-reads holdBlocked(). Typing in chat, the Roblox menu, any
--     screen-owning modal (store, terminal, queue, re-entry), the dispatch
--     briefing, the Level 1 guide, the PARTY DOWN card, losing window focus,
--     dying, respawning, escaping, the Level 2 exit transition and the round
--     ending all stop the hold and reset the bar. The per-frame re-read is the
--     authority; the signals below only make the same cancel happen sooner.
--   * AT MOST ONE REQUEST. Both paths share `requestPending`, and a completed
--     hold latches until the key or finger physically lifts, so a player who
--     keeps holding after the answer cannot fire a second "leaveround".
--   * The transport is untouched: RoundStatus "leaveround" out, and
--     "leaveack" / "leavefailed" / the round events back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local UIDevice = require(ReplicatedStorage:WaitForChild("UIDevice"))
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RoundStatus")
local playerScripts = player:WaitForChild("PlayerScripts")
local playerGui = player:WaitForChild("PlayerGui")

local HOLD_SECONDS = 1.5
-- L was the one letter left: the 2026-09-16 binding sweep found WASD, Space,
-- Shift, Ctrl, Tab, Esc, F, Q, E, G, H, M, N, R, J, B, V, P, C, F4, I/O and "/"
-- already spoken for by this game or by Roblox's own core scripts.
local HOLD_KEY = Enum.KeyCode.L
local MESSAGE_SECONDS = 3   -- how long a refusal stays on the chip
local NO_ANSWER_SECONDS = 8 -- silence after which the player may ask again
local HINT_HEIGHT = 36      -- two wrapped lines of the explanation band

local prompt = playerScripts:FindFirstChild("RoundExitPrompt")
if not prompt then
	prompt = Instance.new("BindableEvent")
	prompt.Name = "RoundExitPrompt"
	prompt.Parent = playerScripts
end

-- UI_STYLE_20260915 (Trello #98). Chrome and faces only -- the chip, the
-- confirm card and the "leaveround" request behave exactly as card 74 froze
-- them. The teal accent this file invented is gone; the card now wears the
-- Mission Brief card's own surface, stroke and typography.
local UIStyle = require(ReplicatedStorage:WaitForChild("UIStyle"))
local MUTED = UIStyle.Color.Muted

local gui = Instance.new("ScreenGui")
gui.Name = "RoundExitGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 70 -- above the HUD and spectate band, under PARTY DOWN (100)
gui.Parent = playerGui

local function makeButton(parent, name, text)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = true
	button.Text = text
	button.Parent = parent
	return UIStyle.button(button)
end

local chip = makeButton(gui, "LeaveChip", "BACK TO LOBBY")
chip.Visible = false
chip.Active = false
-- The refusal copy is longer than the chip is wide, and the chip is sized to the
-- resting prompt rather than to its worst case, so it wraps instead of clipping.
chip.TextWrapped = true
chip.ClipsDescendants = true

-- The progress bar. It is a CHILD of the chip, and under ZIndexBehavior.Sibling
-- every descendant draws over its ancestor's own text no matter what ZIndex
-- says -- so it is a translucent wash the label stays readable through, not an
-- opaque fill that would hide the very words it is counting down.
local fill = Instance.new("Frame")
fill.Name = "HoldFill"
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = UIStyle.Color.Accent
fill.BackgroundTransparency = 0.62
fill.BorderSizePixel = 0
fill.Parent = chip
-- Rounded to the chip's own radius: ClipsDescendants alone leaves a square
-- corner poking out of the chip's left edge on engine versions that clip to the
-- rectangle rather than to the UICorner.
local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, UIStyle.Radius.Control)
fillCorner.Parent = fill

-- The confirm card. The shade is Active so a stray tap behind the card cannot
-- reach the movement controls or the HUD while the question is up.
local shade = Instance.new("Frame")
shade.Name = "RoundExitShade"
shade.Size = UDim2.fromScale(1, 1)
shade.BackgroundColor3 = Color3.new(0, 0, 0)
shade.BackgroundTransparency = 0.55
shade.BorderSizePixel = 0
shade.Active = true
shade.Visible = false
shade.Parent = gui

local card = Instance.new("Frame")
card.Name = "RoundExitCard"
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.Position = UDim2.fromScale(0.5, 0.5)
card.Size = UDim2.fromOffset(340, 176)
card.Parent = shade
UIStyle.panel(card, {
	Background = UIStyle.Color.Card,
	Transparency = UIStyle.Transparency.Card,
	Radius = UIStyle.Radius.Card,
	StrokeTransparency = UIStyle.Stroke.CardTransparency,
})

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Position = UDim2.fromOffset(16, 14)
title.Size = UDim2.new(1, -32, 0, 24)
title.BackgroundTransparency = 1
UIStyle.title(title, {TextSize = 17})
title.Text = "RETURN TO THE LOBBY?"
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = card

local body = Instance.new("TextLabel")
body.Name = "Body"
body.Position = UDim2.fromOffset(16, 42)
body.Size = UDim2.new(1, -32, 0, 40)
body.BackgroundTransparency = 1
UIStyle.body(body, {TextSize = 14})
body.Text = "Your run ends here. The others keep playing."
body.TextWrapped = true
body.TextXAlignment = Enum.TextXAlignment.Left
body.TextYAlignment = Enum.TextYAlignment.Top
body.Parent = card

local notice = Instance.new("TextLabel")
notice.Name = "Notice"
notice.Position = UDim2.fromOffset(16, 84)
notice.Size = UDim2.new(1, -32, 0, 18)
notice.BackgroundTransparency = 1
UIStyle.readout(notice, {TextColor = MUTED, TextSize = 12})
notice.Text = ""
notice.TextXAlignment = Enum.TextXAlignment.Left
notice.Parent = card

local confirm = makeButton(card, "Confirm", "BACK TO LOBBY")
local stay = makeButton(card, "Stay", "STAY")
-- One step quieter than the action it sits next to: same chrome, body face.
stay.TextColor3 = UIStyle.Color.Body

-- What the hold is FOR, in the player's own words, under the chip while it runs.
-- The round does not pause and nothing here pretends it does.
local hint = Instance.new("TextLabel")
hint.Name = "HoldHint"
hint.Visible = false
hint.Text = "Leaving ends your run. The others keep playing."
hint.TextWrapped = true
hint.TextXAlignment = Enum.TextXAlignment.Left
UIStyle.caption(hint)
UIStyle.body(hint, {TextColor = MUTED, TextSize = 12})
hint.Parent = gui
local hintPad = Instance.new("UIPadding")
hintPad.PaddingLeft = UDim.new(0, 8)
hintPad.PaddingRight = UDim.new(0, 8)
hintPad.Parent = hint

local requestPending = false
local requestSerial = 0 -- bumped by every answer, so an old timeout stays dead
local label = nil       -- transient chip copy; nil means "the resting prompt"
local labelSerial = 0
local holdConn = nil    -- non-nil exactly while a hold is running
local holdInput = nil   -- the touch/mouse/gamepad InputObject driving that hold
local held = 0          -- seconds accumulated by the current hold
local holdLatched = false -- a finished hold, waiting for the key/finger to lift

-- "HOLD L • LOBBY" on a keyboard, "HOLD • LOBBY" on a phone. UIDevice.Binding
-- returns "" for every touchscreen (and for a gamepad-only device, where no L
-- key exists), so a finger is never told to press a key it does not have.
local function paint()
	if label then
		chip.Text = label
		return
	end
	local binding = UIDevice.Binding(HOLD_KEY.Name, "")
	chip.Text = binding == "" and "HOLD • LOBBY" or ("HOLD " .. binding .. " • LOBBY")
end

-- `seconds` nil means the copy stays until something replaces it. The serial is
-- what stops a stale timer from wiping a newer message.
local function say(text, seconds)
	labelSerial += 1
	label = text
	paint()
	if not text or not seconds then return end
	local serial = labelSerial
	task.delay(seconds, function()
		if labelSerial ~= serial then return end
		label = nil
		paint()
	end)
end

local hudObstacles = {
	{"PuzzleGui", "Level1Objectives"},
	{"PuzzleGui", "Level1ObjectivesToggle"},
	{"Level2ObjectiveGui", "Level2ObjectivePanel"},
	{"Level3ReaderGui", "ReaderPanel"},
	{"LevelOneGuideGui", "ObjectivesButton"},
}

local function applyLayout()
	local layout = UIDevice.Layout()
	local touch = layout.IsTouch
	local tap = touch and 44 or 30
	-- Sized to the resting prompt, not measured: TextService is not available to
	-- the offline fit tests, so the widths are stated and the copy is kept short.
	local chipWidth = touch and 164 or 156
	local left, top = layout.SafeLeft + 12, layout.SafeTop + 12
	if touch then
		-- A portrait objective card reaches into the left column. Reserve its
		-- actual height, then the Mission Brief below it, instead of a fixed row.
		for _, names in ipairs(hudObstacles) do
			local owner = playerGui:FindFirstChild(names[1])
			local object = owner and owner:FindFirstChild(names[2])
			if object and owner.Enabled and object.Visible then
				local pos, size = object.AbsolutePosition, object.AbsoluteSize
				if left < pos.X + size.X + 8 and left + chipWidth > pos.X - 8 then
					top = math.max(top, pos.Y + size.Y + 8)
				end
			end
		end
	end
	local x, y = UIDevice.LocalOffset(gui, left, top)
	chip.Size = UDim2.fromOffset(chipWidth, tap)
	chip.Position = UDim2.fromOffset(x, y)
	chip.TextSize = touch and 13 or 12

	-- The explanation band sits directly under the chip and never wider than the
	-- safe rect, so it cannot reach the objectives/briefing column on its right.
	-- It is drawn only during a hold, so it costs the corner nothing at rest.
	local room = layout.SafeRight - layout.SafeLeft - 24
	hint.Size = UDim2.fromOffset(math.max(chipWidth, math.min(chipWidth + 120, room)),
		HINT_HEIGHT)
	hint.Position = UDim2.fromOffset(x, y + tap + 6)

	local width = math.min(340, math.max(240, layout.SafeRight - layout.SafeLeft - 24))
	local height = 110 + tap + 14
	card.Size = UDim2.fromOffset(width, height)
	confirm.Size = UDim2.new(0.5, -22, 0, tap)
	confirm.Position = UDim2.new(0, 14, 1, -(tap + 14))
	stay.Size = UDim2.new(0.5, -22, 0, tap)
	stay.Position = UDim2.new(0.5, 8, 1, -(tap + 14))
end

local function alive()
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function chipAvailable()
	return player:GetAttribute("InRound") == true
		and workspace:GetAttribute("RoundActive") == true
		and alive()
		and player:GetAttribute("Spectating") ~= true
		and player:GetAttribute("Escaped") ~= true
		and player:GetAttribute("Level2_ExitTransition") ~= true
		and player:GetAttribute("RoundEntryControlsReady") == true
		and player:GetAttribute("DispatchBriefingOpen") ~= true
		and player:GetAttribute("LevelOneGuideObjectivesOpen") ~= true
		and player:GetAttribute("PartyDownCardOpen") ~= true
		and not UIDevice.ScreenOwningModalOpen()
		and not GuiService.MenuIsOpen
		and not shade.Visible
end

-- A focused text box blocks the HOLD but deliberately not the CHIP: someone
-- typing in chat should still see the way out, they just must not trigger it by
-- typing the letter L. Everything else that hides the chip also stops a hold.
local function holdBlocked()
	return not chipAvailable() or UserInputService:GetFocusedTextBox() ~= nil
end

-- Stops the bar. `holdInput` deliberately SURVIVES: a finished or cancelled
-- hold still has to recognise the finger that started it when it finally lifts,
-- and a touch InputObject is the only handle there is on that finger.
local function stopHold()
	if holdConn then holdConn:Disconnect() end
	holdConn, held = nil, 0
	fill.Size = UDim2.fromScale(0, 1)
	hint.Visible = false
end

-- The key or finger physically came up. That, and only that, clears the latch a
-- finished hold leaves behind.
local function releaseHold()
	holdLatched = false
	holdInput = nil
	stopHold()
end

local function refresh()
	if holdConn and holdBlocked() then stopHold() end
	UIDevice.SetInteractive(chip, chipAvailable())
end

local function closeCard()
	if not shade.Visible then return end
	shade.Visible = false
	player:SetAttribute("RoundExitPromptOpen", nil)
	if GuiService.SelectedObject == stay or GuiService.SelectedObject == confirm then
		GuiService.SelectedObject = nil
	end
	refresh()
end

local function openCard()
	if shade.Visible or player:GetAttribute("InRound") ~= true
		or workspace:GetAttribute("RoundActive") ~= true then return end
	stopHold()
	-- The card RENDERS the shared latch rather than clearing it: a request that
	-- is already in flight (held down, then died) must not become a second one.
	confirm.Text = requestPending and "RETURNING..." or "BACK TO LOBBY"
	notice.Text = requestPending and "Returning to the lobby..." or ""
	UIDevice.SetEnabled(confirm, not requestPending)
	shade.Visible = true
	player:SetAttribute("RoundExitPromptOpen", true)
	refresh()
	if UIDevice.LastInput() == "Gamepad" then GuiService.SelectedObject = stay end
end

-- Back to "nothing is in flight". The latch a finished hold left is NOT cleared
-- here: only a real release does that, so a still-held key cannot re-arm.
local function resetRequest()
	requestSerial += 1
	requestPending = false
	stopHold()
	say(nil)
	confirm.Text = "BACK TO LOBBY"
	UIDevice.SetEnabled(confirm, true)
	notice.Text = ""
end

-- The one place that talks to the server. Both the hold and the card come here.
local function sendLeave()
	if requestPending then return end
	requestPending = true
	requestSerial += 1
	local serial = requestSerial
	say("RETURNING...")
	confirm.Text = "RETURNING..."
	UIDevice.SetEnabled(confirm, false)
	notice.Text = "Returning to the lobby..."
	remote:FireServer("leaveround")
	task.delay(NO_ANSWER_SECONDS, function()
		-- No answer at all: let the player ask again rather than sit forever.
		if requestSerial ~= serial then return end
		requestPending = false
		say("NO ANSWER — HOLD AGAIN", MESSAGE_SECONDS)
		confirm.Text = "TRY AGAIN"
		UIDevice.SetEnabled(confirm, true)
		notice.Text = "No answer from the server yet."
	end)
end

local function step(delta)
	-- Re-read the whole cancel list every frame. Some of it has no signal this
	-- file listens to (a modal another script opens, a humanoid that dies inside
	-- a transition), and a hold must never outlive the state that allowed it.
	if holdBlocked() then
		stopHold()
		return
	end
	held += delta
	fill.Size = UDim2.fromScale(math.min(1, held / HOLD_SECONDS), 1)
	if held < HOLD_SECONDS then return end
	holdLatched = true -- no auto-repeat: the key/finger has to come up first
	stopHold()
	sendLeave()
end

local function beginHold(input)
	if holdConn or holdLatched or requestPending or holdBlocked() then return end
	holdInput = input
	held = 0
	fill.Size = UDim2.fromScale(0, 1)
	hint.Visible = true
	holdConn = RunService.RenderStepped:Connect(step)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode ~= HOLD_KEY or processed then return end
	if input.UserInputState ~= Enum.UserInputState.Begin then return end
	beginHold(input)
end)
UserInputService.InputEnded:Connect(function(input)
	-- Matched on the input OBJECT for a finger that slid off the chip before
	-- lifting: the chip's own InputEnded cannot be relied on to see that one.
	if input.KeyCode == HOLD_KEY or (holdInput ~= nil and input == holdInput) then
		releaseHold()
	end
end)
-- A key held while the window loses focus never reports its InputEnded, so this
-- is the only thing that can clear the latch in that case.
UserInputService.WindowFocusReleased:Connect(releaseHold)
UserInputService.TextBoxFocused:Connect(refresh)
UserInputService.TextBoxFocusReleased:Connect(refresh)

chip.InputBegan:Connect(function(input)
	local kind = input.UserInputType
	if kind ~= Enum.UserInputType.Touch and kind ~= Enum.UserInputType.MouseButton1
		and kind ~= Enum.UserInputType.Gamepad1 then return end
	beginHold(input)
end)
chip.InputEnded:Connect(function(input)
	if holdInput ~= nil and input == holdInput then releaseHold() end
end)

prompt.Event:Connect(openCard)
stay.Activated:Connect(closeCard)
confirm.Activated:Connect(function()
	-- sendLeave() is the single authority on "one request at a time"; repeating
	-- the test here would be a second place for that rule to drift out of.
	if shade.Visible then sendLeave() end
end)

remote.OnClientEvent:Connect(function(event)
	if event == "leaveack" then
		requestSerial += 1 -- answered; the armed no-answer timer belongs to the past
		say("RETURNING TO LOBBY...")
		notice.Text = "Returning to the lobby..."
	elseif event == "leavefailed" then
		requestSerial += 1
		requestPending = false
		say("NOT AVAILABLE IN THIS TEST ROUND", MESSAGE_SECONDS)
		confirm.Text = "BACK TO LOBBY"
		UIDevice.SetEnabled(confirm, true)
		notice.Text = "Not available in this test round."
	elseif event == "lobby" or event == "loadinggame" or event == "lose" or event == "win" then
		resetRequest()
		closeCard()
	end
end)

for _, attribute in ipairs({"InRound", "Spectating", "Escaped", "Level2_ExitTransition",
	"RoundEntryControlsReady", "DispatchBriefingOpen", "LevelOneGuideObjectivesOpen",
	"PartyDownCardOpen"}) do
	player:GetAttributeChangedSignal(attribute):Connect(function()
		if attribute == "InRound" and player:GetAttribute("InRound") ~= true then
			resetRequest()
			closeCard()
		end
		refresh()
	end)
end
workspace:GetAttributeChangedSignal("RoundActive"):Connect(function()
	if workspace:GetAttribute("RoundActive") ~= true then
		resetRequest()
		closeCard()
	end
	refresh()
end)
UIDevice.OnScreenOwningModalChanged(refresh)
GuiService:GetPropertyChangedSignal("MenuIsOpen"):Connect(function()
	if GuiService.MenuIsOpen then closeCard() end
	refresh()
end)
UIDevice.Changed:Connect(function()
	applyLayout()
	paint() -- the binding glyph is device-dependent
	refresh()
end)

local function watchHudObstacle(object)
	for _, names in ipairs(hudObstacles) do
		if object.Name == names[2] and object.Parent and object.Parent.Name == names[1] then
			for _, property in ipairs({"Visible", "AbsolutePosition", "AbsoluteSize"}) do
				object:GetPropertyChangedSignal(property):Connect(applyLayout)
			end
			object.Parent:GetPropertyChangedSignal("Enabled"):Connect(applyLayout)
			applyLayout()
			break
		end
	end
end
playerGui.DescendantAdded:Connect(watchHudObstacle)
for _, object in ipairs(playerGui:GetDescendants()) do watchHudObstacle(object) end

local function bindCharacter(character)
	stopHold()
	closeCard()
	refresh()
	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid then return end
		humanoid.HealthChanged:Connect(refresh)
		humanoid.Died:Connect(refresh)
		refresh()
	end)
end
player.CharacterAdded:Connect(bindCharacter)
player.CharacterRemoving:Connect(function()
	stopHold()
	closeCard()
	refresh()
end)
if player.Character then bindCharacter(player.Character) end

applyLayout()
paint()
refresh()
