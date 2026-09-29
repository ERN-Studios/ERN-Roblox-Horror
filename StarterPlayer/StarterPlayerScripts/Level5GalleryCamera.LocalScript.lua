-- Camera arrival aid for the developer-only, view-only Level 5 rework gallery.
-- The server owns access and travel. This client only sets an initial Custom
-- camera heading/FOV and a small status label; normal camera input remains free.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local DevAccess = require(ReplicatedStorage:WaitForChild("DevAccess"))
if not DevAccess.IsAllowed(player) then return end

local PREVIEW_NAME = "Level 5 Architecture Preview"
local GALLERY_VERSION = "reference-gallery-2026-09-27-v1"
local CAMERA_BIND = "Level5GalleryArrivalCamera"
local SECTION_NAMES = {
	"COURTYARD", "TOWNHOUSE CORRIDOR", "BRIGHT ATRIUM", "TOWER CANYON",
	"SLOPED HOUSES", "GABLED LAWN", "STAIR CUTAWAY", "UPPER WALKWAY",
	"SKYBRIDGE CANYON", "EMPTY ROOMS",
}

local rootPart, rootConnection, characterGeneration = nil, nil, 0
local activeKey, activeModel, activePosition, activeFov = nil, nil, nil, nil
local originalFov, ownedCamera, lastAppliedFov = nil, nil, nil
local screenGui, statusText = nil, nil
local cameraBound, desiredLook, desiredUp, desiredFov = false, nil, nil, nil
local stopped = false
local connections = {}

local function connect(signal, callback)
	table.insert(connections, signal:Connect(callback))
end

local function hideStatus()
	if screenGui and screenGui.Parent then screenGui.Enabled = false end
end

local function showStatus(location)
	if not screenGui or not screenGui.Parent then
		local playerGui = player:FindFirstChildOfClass("PlayerGui")
		if not playerGui then return end
		screenGui = Instance.new("ScreenGui")
		screenGui.Name = "Level5GalleryStatus"
		screenGui.ResetOnSpawn = false
		screenGui.IgnoreGuiInset = false
		screenGui.DisplayOrder = 15
		local panel = Instance.new("Frame")
		panel.Name = "StatusPanel"
		panel.AnchorPoint = Vector2.new(0.5, 0)
		panel.Position = UDim2.new(0.5, 0, 0, 8)
		panel.Size = UDim2.new(0.9, 0, 0, 58)
		panel.BackgroundColor3 = Color3.fromRGB(24, 28, 29)
		panel.BackgroundTransparency = 0.14
		panel.BorderSizePixel = 0
		panel.Parent = screenGui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = panel
		local limit = Instance.new("UISizeConstraint")
		limit.MaxSize = Vector2.new(520, 58)
		limit.Parent = panel
		statusText = Instance.new("TextLabel")
		statusText.Name = "StatusText"
		statusText.Size = UDim2.fromScale(1, 1)
		statusText.BackgroundTransparency = 1
		statusText.Font = Enum.Font.GothamSemibold
		statusText.TextColor3 = Color3.fromRGB(245, 240, 218)
		statusText.TextSize = 14
		statusText.TextWrapped = true
		statusText.Parent = panel
		screenGui.Parent = playerGui
	end
	statusText.Text = if location.id == 0
		then "LEVEL 5 / DEV PREVIEW / VIEW ONLY\nFront row: 01–05. Rear row: 06–10. Approach a stand and press E."
		else string.format("LEVEL 5 / SECTION %02d / %s / WIP\nUse RETURN TO HUB on this view pad.",
			location.id, SECTION_NAMES[location.id])
	screenGui.Enabled = true
end

local function stopCameraArrival()
	if cameraBound then
		RunService:UnbindFromRenderStep(CAMERA_BIND)
		cameraBound = false
	end
	desiredLook, desiredUp, desiredFov = nil, nil, nil
end

local function restoreFov()
	local camera = workspace.CurrentCamera
	-- Another camera owner may have changed FOV while the gallery was open.
	if camera and camera == ownedCamera and originalFov and lastAppliedFov
		and math.abs(camera.FieldOfView - lastAppliedFov) < 0.05 then
		camera.FieldOfView = originalFov
	end
	originalFov, ownedCamera, lastAppliedFov = nil, nil, nil
end

local function leaveGallery()
	if activeKey == nil then return end
	activeKey, activeModel, activePosition, activeFov = nil, nil, nil, nil
	stopCameraArrival()
	restoreFov()
	hideStatus()
end

local function validPreview()
	local model = workspace:FindFirstChild(PREVIEW_NAME)
	if model and model:IsA("Model")
		and model:GetAttribute("Level5Preview") == true
		and model:GetAttribute("PreviewOnly") == true
		and model:GetAttribute("PreviewReady") == true
		and model:GetAttribute("GalleryContentVersion") == GALLERY_VERSION then
		return model
	end
	return nil
end

local function nearMarker(marker, position)
	if not (marker and marker:IsA("BasePart")) then return false end
	local delta = marker.Position - position
	return math.abs(delta.X) <= 12 and math.abs(delta.Z) <= 12 and math.abs(delta.Y) <= 12
end

local function findLocation(model, position)
	local hub = model:FindFirstChild("Level5DeveloperPreviewArrival")
	if nearMarker(hub, position) then
		return {key = "hub", id = 0, model = model, position = hub.Position,
			look = hub.CFrame.LookVector, up = hub.CFrame.UpVector}
	end
	for id = 1, 10 do
		local cell = model:FindFirstChild(("GallerySection_%02d"):format(id))
		if cell and cell:IsA("Model") and cell:GetAttribute("GallerySectionId") == id then
			local marker = cell:FindFirstChild("GalleryViewpointMarker")
			if nearMarker(marker, position) then
				local reference = marker:GetAttribute("ReferenceCameraCFrame")
				if typeof(reference) == "CFrame" then
					local fov = marker:GetAttribute("ReferenceCameraFov")
					if typeof(fov) ~= "number" or fov < 30 or fov > 110 then fov = nil end
					return {key = id, id = id, model = model, position = marker.Position,
						look = reference.LookVector, up = reference.UpVector, fov = fov}
				end
			end
		end
	end
	return nil
end

local function beginCameraArrival(location)
	stopCameraArrival()
	desiredLook, desiredUp, desiredFov = location.look, location.up, location.fov
	local frames, deadline = 0, os.clock() + 2
	cameraBound = true
	RunService:BindToRenderStep(CAMERA_BIND, Enum.RenderPriority.Camera.Value + 1, function()
		if stopped or activeKey ~= location.key or activeModel ~= location.model then
			stopCameraArrival()
			return
		end
		local camera = workspace.CurrentCamera
		local character = player.Character
		local subject = camera and camera.CameraSubject
		if not camera or camera.CameraType ~= Enum.CameraType.Custom or not character
			or not subject or not subject:IsDescendantOf(character) then
			if os.clock() > deadline then stopCameraArrival() end
			return
		end
		if originalFov == nil then originalFov = camera.FieldOfView end
		local fov = desiredFov or originalFov
		if fov then
			camera.FieldOfView = fov
			ownedCamera, lastAppliedFov = camera, fov
		end
		-- CameraModule has already updated this frame. Change heading only;
		-- the player's zoom, position, controls and ProximityPrompts stay intact.
		camera.CFrame = CFrame.lookAt(camera.CFrame.Position,
			camera.CFrame.Position + desiredLook, desiredUp)
		frames += 1
		if frames >= 2 then stopCameraArrival() end
	end)
end

local function refresh()
	if stopped then return end
	if player:GetAttribute("InRound") == true or workspace:GetAttribute("ReservedRoundServer") == true
		or not rootPart or not rootPart:IsDescendantOf(workspace) then
		leaveGallery()
		return
	end
	local model = validPreview()
	local position = rootPart.Position
	local location = model and findLocation(model, position) or nil
	if not location then
		-- Streaming can temporarily remove a marker while the avatar remains
		-- on its pad. Keep the active camera state until the player moves away.
		if activePosition and (position - activePosition).Magnitude <= 40 then return end
		leaveGallery()
		return
	end
	local camera = workspace.CurrentCamera
	if activeKey ~= location.key or activeModel ~= location.model then
		activeKey, activeModel, activePosition, activeFov =
			location.key, location.model, location.position, location.fov
		showStatus(location)
		beginCameraArrival(location)
	elseif activeFov ~= location.fov or (camera and ownedCamera ~= camera) then
		-- Marker attributes or CurrentCamera may arrive after the teleport.
		activeFov = location.fov
		beginCameraArrival(location)
	end
	if not screenGui or not screenGui.Parent then showStatus(location) end
end

local function trackCharacter(character)
	characterGeneration += 1
	local generation = characterGeneration
	if rootConnection then rootConnection:Disconnect(); rootConnection = nil end
	rootPart = nil
	leaveGallery()
	task.spawn(function()
		local root = character:FindFirstChild("HumanoidRootPart")
			or character:WaitForChild("HumanoidRootPart", 10)
		if not root or generation ~= characterGeneration or stopped then return end
		rootPart = root
		local lastPosition = root.Position
		rootConnection = root:GetPropertyChangedSignal("CFrame"):Connect(function()
			local position = root.Position
			if (position - lastPosition).Magnitude >= 70 then task.defer(refresh) end
			lastPosition = position
		end)
		refresh()
	end)
end

connect(player.CharacterAdded, trackCharacter)
connect(player.CharacterRemoving, function()
	characterGeneration += 1
	if rootConnection then rootConnection:Disconnect(); rootConnection = nil end
	rootPart = nil
	leaveGallery()
end)
connect(player:GetAttributeChangedSignal("InRound"), refresh)
connect(workspace:GetAttributeChangedSignal("ReservedRoundServer"), refresh)
connect(workspace:GetPropertyChangedSignal("CurrentCamera"), refresh)
connect(workspace.ChildAdded, function(child)
	if child.Name == PREVIEW_NAME then task.defer(refresh) end
end)
connect(workspace.ChildRemoved, function(child)
	if child == activeModel then task.defer(refresh) end
end)
if player.Character then trackCharacter(player.Character) end

-- Bounded fallback for streamed markers and camera replacement. The client
-- reads at most eleven direct markers twice a second, never the full map.
task.spawn(function()
	while not stopped and script.Parent do
		refresh()
		task.wait(0.5)
	end
end)
script.Destroying:Connect(function()
	stopped = true
	for _, connection in ipairs(connections) do connection:Disconnect() end
	if rootConnection then rootConnection:Disconnect() end
	leaveGallery()
	if screenGui then screenGui:Destroy() end
end)
