-- First Entry Guide: the WELCOME card (2026-10-04, owner request). The beam trail this script once drew was
-- retired on 2026-09-24 (source in git at 8e623de); the script was empty until now.
--
-- A brand-new player (ZyntraFirstLogin, published by ZyntraMonetization once the profile has loaded) gets one
-- card in the middle of the screen as soon as the lobby cover is gone: what the game is, how to start a level in
-- three steps, the controls for their device, and a line about the two of us who make it. GOT IT, Enter, Escape
-- or the gamepad's A closes it. It never shows again for that profile, on a round server, or in a round.
-- `workspace.DevShowWelcome = true` (Studio) shows it regardless, for testing.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer

local function wanted()
	if RunService:IsStudio() and workspace:GetAttribute("DevShowWelcome") == true then return true end
	return player:GetAttribute("ZyntraFirstLogin") == true
end
-- wait for the lobby to be on screen and for the profile to say whether this is a first visit
local deadline = os.clock() + 90
while os.clock() < deadline and player:GetAttribute("LobbyLoadingDone") ~= true do task.wait(0.25) end
local profileDeadline = os.clock() + 20
while os.clock() < profileDeadline and player:GetAttribute("ZyntraFirstLogin") == nil and not wanted() do task.wait(0.25) end
if workspace:GetAttribute("ReservedRoundServer") == true or player:GetAttribute("InRound") == true or not wanted() then return end
-- The COMMAND CENTER briefing types across the middle of the screen for a new player. It goes first; the card
-- comes up when it has finished (or straight away if no briefing starts).
do
	local began = os.clock()
	while os.clock() - began < 3 and player:GetAttribute("LobbyBriefingActive") ~= true do task.wait(0.2) end
	while os.clock() - began < 120 and player:GetAttribute("LobbyBriefingActive") == true do task.wait(0.3) end
	if player:GetAttribute("InRound") == true then return end
end

local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled or workspace:GetAttribute("ForceTouchUI") == true
local GREEN, PAPER, INK, SOFT = Color3.fromRGB(120, 255, 190), Color3.fromRGB(240, 244, 236), Color3.fromRGB(9, 14, 12), Color3.fromRGB(176, 190, 180)
local gui = Instance.new("ScreenGui")
gui.Name = "WelcomeCard"
gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = false, true, 60
local shade = Instance.new("Frame")
shade.Name = "Shade"
shade.Size, shade.BackgroundColor3, shade.BackgroundTransparency, shade.BorderSizePixel = UDim2.fromScale(1, 1), Color3.new(0, 0, 0), 1, 0
shade.Active = true
shade.Parent = gui
local card = Instance.new("Frame")
card.Name = "Card"
card.AnchorPoint, card.Position, card.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(620, 520)
card.BackgroundColor3, card.BackgroundTransparency, card.BorderSizePixel = INK, 0.03, 0
card.Parent = shade
Instance.new("UICorner", card).CornerRadius = UDim.new(0, 16)
local stroke = Instance.new("UIStroke", card)
stroke.Color, stroke.Thickness, stroke.Transparency = GREEN, 2, 0.25
local scale = Instance.new("UIScale", card)
local function fit()
	local view = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	scale.Scale = math.clamp(math.min((view.X - 28) / 620, (view.Y - 28) / 520), 0.5, 1.3)
end
fit()
local resized = workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
local function text(name, content, size, colour, y, height, font)
	local item = Instance.new("TextLabel")
	item.Name, item.Text, item.TextSize, item.TextColor3 = name, content, size, colour
	item.Font = font or Enum.Font.GothamMedium
	item.BackgroundTransparency, item.TextWrapped = 1, true
	item.TextXAlignment, item.TextYAlignment = Enum.TextXAlignment.Left, Enum.TextYAlignment.Top
	item.Position, item.Size = UDim2.fromOffset(34, y), UDim2.new(1, -68, 0, height)
	item.Parent = card
	return item
end
text("Kicker", "ZYNTRA  //  NEW ARRIVAL", 13, GREEN, 26, 16, Enum.Font.Code)
text("Title", "WELCOME TO THE BACKROOMS", 32, PAPER, 46, 40, Enum.Font.GothamBlack)
text("Lead", "A co-op horror game. Get your team through each level and out again. Things in there can hear you.", 17, SOFT, 92, 46)
local steps = {
	{"1", "WALK TO A LEVEL GATE", "Start with LEVEL 1 along the tunnel. Every level is open."},
	{"2", "STEP ON A PAD", "Pick 1–6 players and press CREATE PARTY. Friends can step on the same pad."},
	{"3", "STAY QUIET, GET OUT", touch and "Use the on-screen buttons to sneak, sprint and switch your flashlight."
		or "Ctrl sneaks, Shift sprints (it is loud), F is your flashlight, Space jumps."},
}
for index, step in ipairs(steps) do
	local y = 150 + (index - 1) * 74
	local badge = Instance.new("TextLabel")
	badge.Name = "Step" .. index
	badge.Position, badge.Size = UDim2.fromOffset(34, y), UDim2.fromOffset(44, 44)
	badge.BackgroundColor3, badge.BorderSizePixel = Color3.fromRGB(24, 60, 44), 0
	badge.Text, badge.TextSize, badge.TextColor3, badge.Font = step[1], 24, GREEN, Enum.Font.GothamBlack
	badge.Parent = card
	Instance.new("UICorner", badge).CornerRadius = UDim.new(1, 0)
	local head = text("Head" .. index, step[2], 19, PAPER, y, 22, Enum.Font.GothamBold)
	head.Position, head.Size = UDim2.fromOffset(94, y), UDim2.new(1, -128, 0, 22)
	local body = text("Body" .. index, step[3], 15, SOFT, y + 24, 40)
	body.Position, body.Size = UDim2.fromOffset(94, y + 24), UDim2.new(1, -128, 0, 40)
end
local rule = Instance.new("Frame")
rule.Position, rule.Size = UDim2.fromOffset(34, 378), UDim2.new(1, -68, 0, 1)
rule.BackgroundColor3, rule.BackgroundTransparency, rule.BorderSizePixel = GREEN, 0.6, 0
rule.Parent = card
text("Team", "We are a team of only 2 people making this game. A like, a favourite or a note in our Discord (#bugs and #feedback) goes a long way. Thank you for playing.",
	15, PAPER, 390, 58)
local go = Instance.new("TextButton")
go.Name = "GotIt"
go.AnchorPoint, go.Position, go.Size = Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -18), UDim2.fromOffset(260, 52)
go.BackgroundColor3, go.BorderSizePixel = Color3.fromRGB(42, 150, 100), 0
go.Text, go.TextSize, go.TextColor3, go.Font = "GOT IT", 20, Color3.new(1, 1, 1), Enum.Font.GothamBlack
go.Parent = card
Instance.new("UICorner", go).CornerRadius = UDim.new(0, 10)
gui.Parent = player:WaitForChild("PlayerGui")
player:SetAttribute("WelcomeCardOpen", true)
TweenService:Create(shade, TweenInfo.new(0.35), {BackgroundTransparency = 0.45}):Play()

local closed = false
local input
local function close()
	if closed then return end
	closed = true
	resized:Disconnect()
	if input then input:Disconnect() end
	player:SetAttribute("WelcomeCardOpen", nil)
	gui:Destroy()
end
go.Activated:Connect(close)
input = UserInputService.InputBegan:Connect(function(event)
	local key = event.KeyCode
	if key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter or key == Enum.KeyCode.Escape or key == Enum.KeyCode.ButtonA then close() end
end)
player:GetAttributeChangedSignal("InRound"):Connect(function()
	if player:GetAttribute("InRound") == true then close() end
end)
