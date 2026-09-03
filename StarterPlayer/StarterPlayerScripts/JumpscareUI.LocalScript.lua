-- JumpscareUI
-- First-person camera direction for the Blender-authored entity kill. The server
-- stages both rigs; this client owns the victim's view, impact shake and fade.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local remote = RS:WaitForChild("Remotes"):WaitForChild("Jumpscare")
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local BLACK_FADE = 0.16
local BLACK_HOLD = 1.65
local REVEAL = 0.65
local DIED_GRACE = 0.35
local CAMERA_BIND = "EntityKillCamera"

local dying = false
local capturing = false
local controls = nil
local overlay = nil

--[[
LEGACY IMAGE JUMPSCARE (disabled, intentionally preserved for rollback)
local JUMPSCARE_IMAGE = "rbxassetid://85716983692957"
local function legacyImageScare(gui)
	local img = Instance.new("ImageLabel")
	img.Size = UDim2.fromScale(1, 1)
	img.BackgroundTransparency = 1
	img.ScaleType = Enum.ScaleType.Crop
	img.Image = JUMPSCARE_IMAGE
	img.Parent = gui
	task.wait(0.7)
	TweenService:Create(img, TweenInfo.new(1.2), { ImageTransparency = 1 }):Play()
end
]]

local function getControls()
	if controls then return controls end
	pcall(function()
		controls = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")):GetControls()
	end)
	return controls
end

local function makeOverlay()
	if overlay then overlay:Destroy() end
	local gui = Instance.new("ScreenGui")
	gui.Name = "JumpscareGui"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1000
	gui.Parent = player:WaitForChild("PlayerGui")
	local black = Instance.new("Frame")
	black.Name = "Black"
	black.Size = UDim2.fromScale(1, 1)
	black.BackgroundColor3 = Color3.new(0, 0, 0)
	black.BackgroundTransparency = 1
	black.BorderSizePixel = 0
	black.Parent = gui
	overlay = gui
	return black
end

local function stopCapture()
	if not capturing then return end
	capturing = false
	RunService:UnbindFromRenderStep(CAMERA_BIND)
	local c = getControls()
	if c then c:Enable() end
end

local function fadeDeath()
	local black = overlay and overlay:FindFirstChild("Black") or makeOverlay()
	TweenService:Create(black, TweenInfo.new(BLACK_FADE, Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out), { BackgroundTransparency = 0 }):Play()
	task.wait(BLACK_FADE)
	black.BackgroundTransparency = 0
	stopCapture() -- SpectateController may now take over behind the black frame.
	task.wait(BLACK_HOLD)
	TweenService:Create(black, TweenInfo.new(REVEAL), { BackgroundTransparency = 1 }):Play()
	task.wait(REVEAL)
	if overlay then overlay:Destroy(); overlay = nil end
end

local function beginCapture(entity, duration, deathAt)
	if capturing or typeof(entity) ~= "Instance" then return end
	dying = true
	capturing = true
	makeOverlay()
	local c = getControls()
	if c then c:Disable() end
	camera.CameraType = Enum.CameraType.Scriptable
	local started = os.clock()
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	-- Resolved once: recursive per-frame lookups here hit during the
	-- heaviest frame of the kill sequence.
	local entityHead = entity:FindFirstChild("Head", true)
	local entityRoot = entity:FindFirstChild("HumanoidRootPart", true)

	RunService:BindToRenderStep(CAMERA_BIND, Enum.RenderPriority.Camera.Value + 1, function()
		if not (capturing and entity.Parent and head and head.Parent) then return end
		local elapsed = os.clock() - started
		local target = entityHead and entityHead:IsA("BasePart") and entityHead.Position
			or entityHead and (entityHead:IsA("Bone") or entityHead:IsA("Attachment")) and entityHead.WorldPosition
			or (entityRoot and entityRoot.Position + Vector3.new(0, 2.7, 0))
		if not target then return end

		-- The camera rolls slightly as the character is laid on the floor, then a
		-- single sharp damped impulse lands on the fatal fist marker.
		local shake = math.sin(elapsed * 19) * 0.008
		local hitAt = deathAt or (124 / 30)
		local d = elapsed - hitAt
		if d >= 0 and d < 0.24 then
			shake += math.sin(d * 125) * (1 - d / 0.24) * 0.095
		end
		local floorBlend = math.clamp((elapsed - 1.35) / 0.8, 0, 1)
		floorBlend = floorBlend * floorBlend * (3 - 2 * floorBlend)
		local eye = head.Position + Vector3.new(0, 0.12, 0)
		-- Keep the view first-person, but pull the near plane a few inches away
		-- from the Entity during the floor pin so the camera never enters its suit.
		local away = eye - target
		if away.Magnitude > 0.05 then eye += away.Unit * (0.85 * floorBlend) end
		camera.CFrame = CFrame.lookAt(eye, target)
			* CFrame.Angles(shake * 0.55, shake, math.rad(-9) * floorBlend + shake * 0.35)
		camera.FieldOfView = 70 + math.clamp(elapsed / math.max(duration or 5, 0.1), 0, 1) * 4
	end)
end

remote.OnClientEvent:Connect(function(eventName, entity, duration, deathAt)
	if eventName == "capture" then
		beginCapture(entity, duration, deathAt)
	elseif eventName == "death" then
		task.spawn(fadeDeath)
	end
end)

local function hookChar(char)
	stopCapture()
	dying = false
	camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70
	if overlay then overlay:Destroy(); overlay = nil end

	local hum = char:WaitForChild("Humanoid")
	hum.Died:Connect(function()
		task.wait(DIED_GRACE)
		if dying then return end -- entity sequence owns its precisely timed fade
		dying = true
		makeOverlay()
		task.spawn(fadeDeath) -- pit/other death: simple black transition
	end)
end

if player.Character then hookChar(player.Character) end
player.CharacterAdded:Connect(hookChar)
