-- JumpscareUI: first-person capture direction and matching cancellation.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local remote = RS:WaitForChild("Remotes"):WaitForChild("Jumpscare")
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local BLACK_FADE, BLACK_HOLD, REVEAL, DIED_GRACE = 0.16, 1.65, 0.65, 0.35
local CAMERA_BIND = "EntityKillCamera"
local dying, capturing = false, false
local controls, overlay = nil, nil
local captureRecord, fadeRecord, lastCaptureId = nil, nil, nil

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
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then return nil end
	if overlay then overlay:Destroy() end
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.IgnoreGuiInset, gui.ResetOnSpawn, gui.DisplayOrder = "JumpscareGui", true, false, 1000
	gui.Parent = playerGui
	local black = Instance.new("Frame")
	black.Name, black.Size = "Black", UDim2.fromScale(1, 1)
	black.BackgroundColor3, black.BackgroundTransparency = Color3.new(0, 0, 0), 1
	black.BorderSizePixel, black.Parent = 0, gui
	overlay = gui
	return black
end

local function stopCapture(restoreCamera)
	local record = captureRecord
	if not capturing and not record then return end
	capturing, captureRecord = false, nil
	RunService:UnbindFromRenderStep(CAMERA_BIND)
	if controls then controls:Enable() end
	if restoreCamera and record and player.Character == record.Character
		and workspace.CurrentCamera == record.Camera then
		record.Camera.CameraType = record.CameraType
		record.Camera.CameraSubject = record.CameraSubject
		record.Camera.FieldOfView = record.FieldOfView
		record.Camera.CFrame = record.CFrame
	end
end

local function clearFade()
	local record = fadeRecord
	fadeRecord = nil
	if record and record.Tween then record.Tween:Cancel() end
	if overlay then overlay:Destroy(); overlay = nil end
end

local function cancelCapture(id, character)
	local record = captureRecord
	if not record or record.Id ~= id or record.Character ~= character then return end
	clearFade()
	stopCapture(true)
	dying = false
end

local function fadeDeath(character)
	if player.Character ~= character or fadeRecord then return end
	local black = overlay and overlay:FindFirstChild("Black") or makeOverlay()
	if not black then return end
	local record = {Character = character, Overlay = overlay}
	fadeRecord = record
	local function current() return fadeRecord == record and player.Character == character end
	record.Tween = TweenService:Create(black, TweenInfo.new(BLACK_FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0})
	record.Tween:Play()
	task.wait(BLACK_FADE)
	if not current() then return end
	black.BackgroundTransparency = 0
	stopCapture() -- SpectateController takes over behind the black frame.
	task.wait(BLACK_HOLD)
	if not current() then return end
	record.Tween = TweenService:Create(black, TweenInfo.new(REVEAL), {BackgroundTransparency = 1})
	record.Tween:Play()
	task.wait(REVEAL)
	if not current() then return end
	if overlay == record.Overlay then overlay:Destroy(); overlay = nil end
	fadeRecord = nil
end

local function beginCapture(entity, duration, deathAt, id, character)
	if capturing or typeof(entity) ~= "Instance" or type(id) ~= "string" or id == lastCaptureId
		or player.Character ~= character then return end
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	camera = workspace.CurrentCamera
	local record = {Id = id, Character = character, Camera = camera,
		CameraType = camera.CameraType, CameraSubject = camera.CameraSubject,
		FieldOfView = camera.FieldOfView, CFrame = camera.CFrame}
	captureRecord, lastCaptureId = record, id
	dying, capturing = true, true
	if not makeOverlay() then cancelCapture(id, character); return end
	local c = getControls()
	-- PlayerModule loading can yield. A cancel/respawn owns the state now if
	-- this record changed while it loaded; never disable that newer character.
	if captureRecord ~= record then return end
	if player.Character ~= character or hum.Health <= 0 then cancelCapture(id, character); return end
	if c then c:Disable() end
	camera.CameraType = Enum.CameraType.Scriptable
	local started = os.clock()
	local head = character:FindFirstChild("Head")
	local entityHead = entity:FindFirstChild("Head", true)
	local entityRoot = entity:FindFirstChild("HumanoidRootPart", true)
	RunService:BindToRenderStep(CAMERA_BIND, Enum.RenderPriority.Camera.Value + 1, function()
		if captureRecord ~= record or player.Character ~= character
			or not (capturing and entity.Parent and head and head.Parent) then return end
		local elapsed = os.clock() - started
		local target = entityHead and entityHead:IsA("BasePart") and entityHead.Position
			or entityHead and (entityHead:IsA("Bone") or entityHead:IsA("Attachment")) and entityHead.WorldPosition
			or (entityRoot and entityRoot.Position + Vector3.new(0, 2.7, 0))
		if not target then return end
		local shake = math.sin(elapsed * 19) * 0.008
		local d = elapsed - (deathAt or (124 / 30))
		if d >= 0 and d < 0.24 then shake += math.sin(d * 125) * (1 - d / 0.24) * 0.095 end
		local floorBlend = math.clamp((elapsed - 1.35) / 0.8, 0, 1)
		floorBlend = floorBlend * floorBlend * (3 - 2 * floorBlend)
		local eye = head.Position + Vector3.new(0, 0.12, 0)
		local away = eye - target
		if away.Magnitude > 0.05 then eye += away.Unit * (0.85 * floorBlend) end
		camera.CFrame = CFrame.lookAt(eye, target) * CFrame.Angles(shake * 0.55, shake, math.rad(-9) * floorBlend + shake * 0.35)
		camera.FieldOfView = 70 + math.clamp(elapsed / math.max(duration or 5, 0.1), 0, 1) * 4
	end)
end

remote.OnClientEvent:Connect(function(eventName, entity, duration, deathAt, id, character)
	if eventName == "capture" then
		beginCapture(entity, duration, deathAt, id, character)
	elseif eventName == "cancel" then
		cancelCapture(id, character)
	elseif eventName == "death" then
		local record = captureRecord
		if record and record.Id == id and record.Character == character and not record.Death then
			record.Death = true
			task.spawn(fadeDeath, character)
		end
	end
end)

local function hookChar(char)
	clearFade()
	stopCapture()
	dying = false
	camera = workspace.CurrentCamera
	camera.CameraType, camera.FieldOfView = Enum.CameraType.Custom, 70
	local hum = char:WaitForChild("Humanoid")
	if player.Character ~= char then return end
	hum.Died:Connect(function()
		task.wait(DIED_GRACE)
		if player.Character ~= char or dying then return end
		dying = true
		makeOverlay()
		task.spawn(fadeDeath, char)
	end)
end
if player.Character then hookChar(player.Character) end
player.CharacterAdded:Connect(hookChar)
