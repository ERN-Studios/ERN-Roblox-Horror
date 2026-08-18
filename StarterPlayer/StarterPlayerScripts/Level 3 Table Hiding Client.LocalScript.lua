--!strict
-- Level 3 Table Hiding Client
-- Mobile/desktop leave control. EntityShakeController exclusively owns the
-- under-table CameraOffset. Entry uses one cross-device ProximityPrompt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local requestRemote: RemoteEvent? = nil

local hiding = false

local gui = Instance.new("ScreenGui")
gui.Name = "Level3TableHideUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 92
gui.Enabled = false
gui.Parent = playerGui

local shade = Instance.new("Frame")
shade.Name = "UnderTableShade"
shade.Size = UDim2.fromScale(1, 1)
shade.BackgroundColor3 = Color3.fromRGB(6, 5, 5)
shade.BackgroundTransparency = .76
shade.BorderSizePixel = 0
shade.Active = false
shade.Parent = gui

local topBar = Instance.new("Frame")
topBar.Name = "TableEdgeTop"
topBar.Size = UDim2.new(1, 0, 0, 34)
topBar.BackgroundColor3 = Color3.fromRGB(23, 18, 15)
topBar.BackgroundTransparency = .08
topBar.BorderSizePixel = 0
topBar.Parent = gui

local bottomBar = topBar:Clone()
bottomBar.Name = "TableEdgeBottom"
bottomBar.AnchorPoint = Vector2.new(0, 1)
bottomBar.Position = UDim2.fromScale(0, 1)
bottomBar.Parent = gui

local message = Instance.new("TextLabel")
message.Name = "HiddenStatus"
message.AnchorPoint = Vector2.new(.5, 0)
message.Position = UDim2.new(.5, 0, 0, 45)
message.Size = UDim2.new(0, 360, 0, 42)
message.BackgroundColor3 = Color3.fromRGB(8, 10, 11)
message.BackgroundTransparency = .24
message.BorderSizePixel = 0
message.Font = Enum.Font.GothamBold
message.Text = "HIDDEN UNDER TABLE"
message.TextColor3 = Color3.fromRGB(186, 245, 225)
message.TextScaled = true
message.Parent = gui
local messageCorner = Instance.new("UICorner")
messageCorner.CornerRadius = UDim.new(0, 8)
messageCorner.Parent = message
local messageStroke = Instance.new("UIStroke")
messageStroke.Color = Color3.fromRGB(79, 183, 157)
messageStroke.Transparency = .2
messageStroke.Thickness = 1.5
messageStroke.Parent = message

local leave = Instance.new("TextButton")
leave.Name = "LeaveHiding"
leave.AnchorPoint = Vector2.new(.5, 1)
leave.Position = UDim2.new(.5, 0, 1, -54)
leave.Size = UDim2.new(0, 330, 0, 58)
leave.BackgroundColor3 = Color3.fromRGB(17, 22, 23)
leave.BackgroundTransparency = .08
leave.BorderSizePixel = 0
leave.AutoButtonColor = true
leave.Font = Enum.Font.GothamBold
leave.TextColor3 = Color3.fromRGB(236, 248, 243)
leave.TextScaled = true
leave.Text = if UserInputService.TouchEnabled then "LEAVE HIDING  //  TAP" else "LEAVE HIDING  //  E"
leave.Parent = gui
local leaveCorner = Instance.new("UICorner")
leaveCorner.CornerRadius = UDim.new(0, 10)
leaveCorner.Parent = leave
local leaveStroke = Instance.new("UIStroke")
leaveStroke.Color = Color3.fromRGB(101, 224, 187)
leaveStroke.Transparency = .05
leaveStroke.Thickness = 2
leaveStroke.Parent = leave

local function requestExit()
	if not hiding or not requestRemote then return end
	requestRemote:FireServer("EXIT")
end

local function apply()
	local shouldHide = player:GetAttribute("Level3_Hiding") == true
		and player:GetAttribute("InRound") == true
		and workspace:GetAttribute("SelectedLevel") == 3
	if shouldHide == hiding then
		gui.Enabled = shouldHide
		return
	end
	hiding = shouldHide
	gui.Enabled = hiding
	-- CameraOffset is applied by EntityShakeController so there is only one writer.
end

leave.Activated:Connect(requestExit)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not hiding then return end
	if input.KeyCode == Enum.KeyCode.E
		or input.KeyCode == Enum.KeyCode.ButtonB
		or input.KeyCode == Enum.KeyCode.ButtonX then
		requestExit()
	end
end)

player:GetAttributeChangedSignal("Level3_Hiding"):Connect(apply)
player:GetAttributeChangedSignal("InRound"):Connect(apply)
workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(apply)
player.CharacterAdded:Connect(function()
	hiding = false
	task.defer(apply)
end)

task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("Level 3 Remotes")
	local candidate = folder:WaitForChild("Level3HideRequest")
	if candidate:IsA("RemoteEvent") then requestRemote = candidate end
end)

apply()
