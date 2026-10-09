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

-- B6: authored Framewisp controls, shared request/hold lifecycle below.
local Hud = require(ReplicatedStorage:WaitForChild("RoundHud"))
local Binder = require(ReplicatedStorage:WaitForChild("ZyntraShopUI"):WaitForChild("ShopBinder"))
local gui = Instance.new("ScreenGui")
gui.Name = "RoundExitGui"
gui.ResetOnSpawn = false
gui.ScreenInsets = Enum.ScreenInsets.None
gui.DisplayOrder = 70
gui.Parent = playerGui
local restChip = Hud.Mount("HUD_PC", "LeaveChip", gui)
local wideChip = Hud.Mount("HUD_PC", "LeaveChipWide", gui)
local touchChip = Hud.Mount("HUD_Touch", "LeaveChipTouch", gui)
local noticeRoot = Hud.Mount("HUD_PC", "RoundExitNotice", gui)
local shade = Instance.new("Frame")
shade.Name = "RoundExitShade"
shade.Size = UDim2.fromScale(1, 1)
shade.BackgroundColor3 = Color3.new(0, 0, 0)
shade.BackgroundTransparency = 0.55
shade.BorderSizePixel = 0
shade.Active = true
shade.Visible = false
shade.Parent = gui
local card = Hud.Mount("HUD_PC", "RoundExitCard", shade, {Touch = UIDevice.Layout().IsTouch})
if not (restChip and wideChip and touchChip and noticeRoot and card) then
	warn("Round Exit Client: missing imported HUD templates")
	gui:Destroy()
	return
end
local chip = restChip
local hovered = false
local fill = Binder.at(wideChip, "HoldFill")
local fillWidth = fill.Size.X.Scale
local hint = Binder.text(Binder.at(wideChip, "HoldHint"))
local notice = Binder.text(Binder.at(noticeRoot, "Notice"))
local wideLabel = Binder.text(Binder.at(wideChip, "Label"))
local confirm = Binder.at(card, "BackToLobby")
local stay = Binder.at(card, "Stay")
stay.Modal = true -- release first-person cursor while this confirmation is visible
local confirmLabel = Binder.text(Binder.at(confirm, "Label"))
local ring = Hud.Ring(Binder.at(touchChip, "RingSlot"))
Hud.Keycap(Binder.at(wideChip, "KeyChip"), HOLD_KEY, Enum.KeyCode.ButtonSelect)
restChip.Selectable, wideChip.Selectable, touchChip.Selectable = false, false, false
for _, control in ipairs({restChip, wideChip, touchChip}) do
	control.Visible = false
	control.Active = false
end
notice.Text, noticeRoot.Visible, hint.Visible = "", false, false
local function setFill(fraction)
	fill.Size = UDim2.new(fillWidth * fraction, 0, fill.Size.Y.Scale, fill.Size.Y.Offset)
	ring(fraction, Binder.Palette.RailTeal)
end
local function placeControls()
	local layout = UIDevice.Layout()
	local safe = layout.Safe
	local left = safe.Left + (layout.IsTouch and 12 or 24)
	local top = safe.Top + (layout.IsTouch and 6 or 16)
	for _, control in ipairs({restChip, wideChip, touchChip}) do
		control.Position = UIDevice.LocalPosition(gui, left, top)
	end
	chip = layout.IsTouch and touchChip or restChip
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UIDevice.LocalPosition(gui, (safe.Left + safe.Right) / 2, (safe.Top + safe.Bottom) / 2)
	card.Size = UDim2.fromOffset(math.min(380, safe.Right - safe.Left - 24), 144)
	-- Keep both confirmation targets at least 44 high on a phone.
	if layout.IsTouch then
		confirm.Size = UDim2.new(confirm.Size.X.Scale, 0, 0, 44)
		stay.Size = UDim2.new(stay.Size.X.Scale, 0, 0, 44)
	end
	noticeRoot.Position = UIDevice.LocalPosition(gui, left, top + 48)
end

local requestPending = false
local requestSerial = 0 -- bumped by every answer, so an old timeout stays dead
local label = nil       -- transient chip copy; nil means "the resting prompt"
local labelSerial = 0
local holdConn = nil    -- non-nil exactly while a hold is running
local holdInput = nil   -- the touch/mouse/gamepad InputObject driving that hold
local held = 0          -- seconds accumulated by the current hold
local holdLatched = false -- a finished hold, waiting for the key/finger to lift

-- "HOLD L \u{2022} LOBBY" on a keyboard, "HOLD \u{2022} LOBBY" on a phone. UIDevice.Binding
-- returns "" for every touchscreen (and for a gamepad-only device, where no L
-- key exists), so a finger is never told to press a key it does not have.
local function paint()
	wideLabel.Text = "\u{B7} BACK TO LOBBY"
	-- The separate notice preserves a 44px phone door even for a long refusal.
	if label then notice.Text = label end
	noticeRoot.Visible = label ~= nil and label ~= ""
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

local function applyLayout()
	placeControls()
	paint()
end

local function alive()
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function chipAvailable()
	return player:GetAttribute("InRound") == true
		and (workspace:GetAttribute("RoundActive") == true or player:GetAttribute("Level6PlaygroundPreview") == true)
		and alive()
		and player:GetAttribute("Spectating") ~= true
		and player:GetAttribute("Escaped") ~= true
		and player:GetAttribute("Level2_ExitTransition") ~= true
		and player:GetAttribute("RoundEntryControlsReady") == true
		and player:GetAttribute("DispatchBriefingOpen") ~= true
				and player:GetAttribute("Level4CardOpen") ~= true      -- Level 4's keypad or note, on touch (MOBILE_QA_20261008)
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
	setFill(0)
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
	local available = chipAvailable()
	local touch = UIDevice.Layout().IsTouch
	local expanded = not touch and (hovered or holdConn ~= nil)
	UIDevice.SetInteractive(restChip, available and not touch and not expanded)
	UIDevice.SetInteractive(wideChip, available and expanded)
	UIDevice.SetInteractive(touchChip, available and touch)
	hint.Visible = available and not touch and holdConn ~= nil
	-- Quiet resting chrome, bright during a deliberate hold or hover.
	for _, control in ipairs({restChip, touchChip}) do
		for _, node in ipairs(control:GetDescendants()) do
			if node:IsA("UIStroke") then node.Transparency = holdConn and 0.12 or 0.5 end
		end
	end
	if shade.Visible then
		noticeRoot.Position = UIDevice.LocalPosition(gui,
			card.AbsolutePosition.X, card.AbsolutePosition.Y + card.AbsoluteSize.Y + 8)
	end
end

local function closeCard()
	if not shade.Visible then return end
	shade.Visible = false
	placeControls()
	player:SetAttribute("RoundExitPromptOpen", nil)
	if GuiService.SelectedObject == stay or GuiService.SelectedObject == confirm then
		GuiService.SelectedObject = nil
	end
	refresh()
end

local function openCard()
	if shade.Visible or player:GetAttribute("InRound") ~= true
		or not (workspace:GetAttribute("RoundActive") == true or player:GetAttribute("Level6PlaygroundPreview") == true) then return end
	stopHold()
	-- The card RENDERS the shared latch rather than clearing it: a request that
	-- is already in flight (held down, then died) must not become a second one.
	confirmLabel.Text = requestPending and "RETURNING..." or "BACK TO LOBBY"
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
	confirmLabel.Text = "BACK TO LOBBY"
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
	confirmLabel.Text = "RETURNING..."
	UIDevice.SetEnabled(confirm, false)
	notice.Text = "Returning to the lobby..."
	remote:FireServer("leaveround")
	task.delay(NO_ANSWER_SECONDS, function()
		-- No answer at all: let the player ask again rather than sit forever.
		if requestSerial ~= serial then return end
		requestPending = false
		say("NO ANSWER \u{B7} HOLD AGAIN", MESSAGE_SECONDS)
		confirmLabel.Text = "TRY AGAIN"
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
		refresh()
		return
	end
	held += delta
	setFill(math.min(1, held / HOLD_SECONDS))
	if held < HOLD_SECONDS then return end
	holdLatched = true -- no auto-repeat: the key/finger has to come up first
	stopHold()
	sendLeave()
	refresh()
end

local function beginHold(input)
	if holdConn or holdLatched or requestPending or holdBlocked() then return end
	holdInput = input
	held = 0
	setFill(0)
	hint.Visible = true
	holdConn = RunService.RenderStepped:Connect(step)
	refresh()
end

UserInputService.InputBegan:Connect(function(input, processed)
	if (input.KeyCode ~= HOLD_KEY and input.KeyCode ~= Enum.KeyCode.ButtonSelect) or processed then return end
	if input.UserInputState ~= Enum.UserInputState.Begin then return end
	beginHold(input)
end)
UserInputService.InputEnded:Connect(function(input)
	-- Matched on the input OBJECT for a finger that slid off the chip before
	-- lifting: the chip's own InputEnded cannot be relied on to see that one.
	if input.KeyCode == HOLD_KEY or input.KeyCode == Enum.KeyCode.ButtonSelect or (holdInput ~= nil and input == holdInput) then
		releaseHold()
		refresh()
	end
end)
-- A key held while the window loses focus never reports its InputEnded, so this
-- is the only thing that can clear the latch in that case.
UserInputService.WindowFocusReleased:Connect(function() releaseHold() refresh() end)
UserInputService.TextBoxFocused:Connect(refresh)
UserInputService.TextBoxFocusReleased:Connect(refresh)

for _, control in ipairs({restChip, wideChip, touchChip}) do
	control.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1 then beginHold(input) end
	end)
	control.InputEnded:Connect(function(input)
		if holdInput ~= nil and input == holdInput then releaseHold() refresh() end
	end)
end
restChip.MouseEnter:Connect(function() hovered = true refresh() end)
wideChip.MouseLeave:Connect(function() hovered = false refresh() end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.ButtonB and shade.Visible
		and not GuiService.MenuIsOpen and UserInputService:GetFocusedTextBox() == nil then closeCard() end
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
		confirmLabel.Text = "BACK TO LOBBY"
		UIDevice.SetEnabled(confirm, true)
		notice.Text = "Not available in this test round."
	elseif event == "lobby" or event == "loadinggame" or event == "lose" or event == "win" then
		resetRequest()
		closeCard()
	end
end)

for _, attribute in ipairs({"InRound", "Spectating", "Escaped", "Level2_ExitTransition",
	"RoundEntryControlsReady", "DispatchBriefingOpen", "LevelOneGuideObjectivesOpen", "Level4CardOpen",
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
	releaseHold()
	hovered = false
	applyLayout()
	paint() -- the binding glyph is device-dependent
	refresh()
end)

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
