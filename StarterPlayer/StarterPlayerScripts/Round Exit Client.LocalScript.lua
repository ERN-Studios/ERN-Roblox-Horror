-- Round Exit Client  (BACK_TO_LOBBY_20260914, Trello card 74)
--
-- One player-local way out of a running level. An alive player gets a small
-- BACK TO LOBBY chip at the top-left of the safe area; a dead or escaped
-- player reaches the same confirm card from the spectate band
-- (SpectateController fires PlayerScripts.RoundExitPrompt). The server owns
-- the decision: GameManager's "leaveround" removes only this player from the
-- party, and the round goes on for everybody else.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local player = Players.LocalPlayer
local UIDevice = require(ReplicatedStorage:WaitForChild("UIDevice"))
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RoundStatus")
local playerScripts = player:WaitForChild("PlayerScripts")

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
gui.Parent = player:WaitForChild("PlayerGui")

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

local requestPending = false

local function applyLayout()
	local layout = UIDevice.Layout()
	local touch = layout.IsTouch
	local tap = touch and 44 or 30
	-- Top-left of the safe area. On touch the objectives button owns the very
	-- corner (12, 12 in the guide gui), so the chip takes the slot under it.
	local x, y = UIDevice.LocalOffset(gui, layout.SafeLeft + 12,
		layout.SafeTop + 12 + (touch and 52 or 0))
	chip.Size = UDim2.fromOffset(touch and 140 or 124, tap)
	chip.Position = UDim2.fromOffset(x, y)
	chip.TextSize = touch and 13 or 12

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

local function refresh()
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
	requestPending = false
	notice.Text = ""
	confirm.Text = "BACK TO LOBBY"
	UIDevice.SetEnabled(confirm, true)
	shade.Visible = true
	player:SetAttribute("RoundExitPromptOpen", true)
	refresh()
	if UIDevice.LastInput() == "Gamepad" then GuiService.SelectedObject = stay end
end

chip.Activated:Connect(function()
	if chipAvailable() then openCard() end
end)
prompt.Event:Connect(openCard)
stay.Activated:Connect(closeCard)
confirm.Activated:Connect(function()
	if not shade.Visible or requestPending then return end
	requestPending = true
	confirm.Text = "RETURNING..."
	UIDevice.SetEnabled(confirm, false)
	notice.Text = "Returning to the lobby..."
	remote:FireServer("leaveround")
	task.delay(8, function()
		-- No answer at all: let the player ask again rather than sit forever.
		if not requestPending or not shade.Visible then return end
		requestPending = false
		confirm.Text = "TRY AGAIN"
		UIDevice.SetEnabled(confirm, true)
		notice.Text = "No answer from the server yet."
	end)
end)

remote.OnClientEvent:Connect(function(event)
	if event == "leaveack" then
		requestPending = false
		notice.Text = "Returning to the lobby..."
	elseif event == "leavefailed" then
		requestPending = false
		confirm.Text = "BACK TO LOBBY"
		UIDevice.SetEnabled(confirm, true)
		notice.Text = "Not available in this test round."
	elseif event == "lobby" or event == "loadinggame" or event == "lose" or event == "win" then
		requestPending = false
		closeCard()
	end
end)

for _, attribute in ipairs({"InRound", "Spectating", "Escaped", "Level2_ExitTransition",
	"RoundEntryControlsReady", "DispatchBriefingOpen", "LevelOneGuideObjectivesOpen",
	"PartyDownCardOpen"}) do
	player:GetAttributeChangedSignal(attribute):Connect(function()
		if attribute == "InRound" and player:GetAttribute("InRound") ~= true then closeCard() end
		refresh()
	end)
end
workspace:GetAttributeChangedSignal("RoundActive"):Connect(function()
	if workspace:GetAttribute("RoundActive") ~= true then closeCard() end
	refresh()
end)
UIDevice.OnScreenOwningModalChanged(refresh)
GuiService:GetPropertyChangedSignal("MenuIsOpen"):Connect(function()
	if GuiService.MenuIsOpen then closeCard() end
	refresh()
end)
UIDevice.Changed:Connect(function()
	applyLayout()
	refresh()
end)

local function bindCharacter(character)
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
if player.Character then bindCharacter(player.Character) end

applyLayout()
refresh()
