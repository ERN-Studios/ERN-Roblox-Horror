-- Server-owned cosmetic choice and placement. The native R15 StarterCharacter
-- remains the only Humanoid, camera subject, collision body and gameplay rig.
-- HazmatSkinDriver on each client poses the separate Meshy Bones from that
-- R15 body's actual movement, then reveals this initially hidden visual.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Config = require(ReplicatedStorage:WaitForChild("ZyntraConfig"))
local Skins = require(ReplicatedStorage:WaitForChild("ZyntraSkins"))

local VISUAL_NAME = "ZyntraHazmatSkinVisual"
local PREVIEW_FOLDER_NAME = "HazmatSkinPreviewTemplates"
local TEMPLATE_PREFIX = "HazmatSkin_"
local TEMPLATE_SUFFIX = "_20260924"
local PREMIUM_TOPPERS = {
	-- Candidate size/placement from read-only Studio bounds. Check both from
	-- behind during an active round before making premium visuals public.
	StaticWraith = {Template = "HazmatStaticWraithTopper_20260924",
		Scale = 2, Y = 1.15, Z = 1.15},
	FalseSun = {Template = "HazmatFalseSunTopper_20260924",
		Scale = 2, Y = 0.25, Z = 1.45},
}
local active = {}
local playerConnections = {}
local warned = {}

local function warnOnce(key, message)
	if warned[key] then return end
	warned[key] = true
	warn("[HazmatSkinVisuals] " .. message)
end

local function keepsAdvancedColor(player, skinId)
	if skinId ~= Skins.DefaultId
		or player:GetAttribute("ZyntraOwnsAdvancedEquipment") ~= true then
		return false
	end
	local chosen = player:GetAttribute("ZyntraHazmatColor")
	local default = Config.Colors.HazmatDefault
	return typeof(chosen) == "Color3" and (
		math.abs(chosen.R - default.R) > 0.01
		or math.abs(chosen.G - default.G) > 0.01
		or math.abs(chosen.B - default.B) > 0.01)
end

local function destroyVisual(player)
	local state = active[player]
	if not state then return end
	active[player] = nil
	if state.Visual.Parent then state.Visual:Destroy() end
end

local function rootToFootSole(model)
	if not model then return nil end
	local root = model:FindFirstChild("HumanoidRootPart")
	local left = model:FindFirstChild("LeftFoot")
	local right = model:FindFirstChild("RightFoot")
	if not root or not root:IsA("BasePart")
		or not left or not left:IsA("BasePart")
		or not right or not right:IsA("BasePart") then return nil end
	local function lowest(part)
		local relative = root.CFrame:ToObjectSpace(part.CFrame)
		local half = part.Size * 0.5
		local radius = math.abs(relative.XVector.Y) * half.X
			+ math.abs(relative.YVector.Y) * half.Y
			+ math.abs(relative.ZVector.Y) * half.Z
		return relative.Position.Y - radius
	end
	return -math.min(lowest(left), lowest(right))
end

local function publishPreviews()
	local authoredRig = StarterPlayer:FindFirstChild("StarterCharacter")
		or ServerStorage:FindFirstChild("StarterCharacter")
	local root = authoredRig and authoredRig:FindFirstChild("HumanoidRootPart")
	local upperTorso = authoredRig and authoredRig:FindFirstChild("UpperTorso")
	local rootToFloor = rootToFootSole(authoredRig)
	if not root or not upperTorso or not rootToFloor then
		warnOnce("PreviewRig", "native R15 preview rig unavailable")
		return
	end
	local previous = ReplicatedStorage:FindFirstChild(PREVIEW_FOLDER_NAME)
	if previous then previous:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = PREVIEW_FOLDER_NAME
	for _, skinId in ipairs(Skins.Order) do
		local templateName = TEMPLATE_PREFIX .. skinId .. TEMPLATE_SUFFIX
		local template = ServerStorage:FindFirstChild(templateName)
		local topperConfig = PREMIUM_TOPPERS[skinId]
		local topperTemplate = topperConfig
			and ServerStorage:FindFirstChild(topperConfig.Template) or nil
		if not template or not template:IsA("Model")
			or topperConfig and (not topperTemplate or not topperTemplate:IsA("Model")) then
			warnOnce(skinId .. "Preview", "missing canonical preview asset for " .. skinId)
			continue
		end
		local preview = template:Clone()
		preview.Name = skinId
		preview.Archivable = true
		local mesh = preview:FindFirstChild("char1", true)
		if not mesh or not mesh:IsA("MeshPart")
			or not mesh:FindFirstChildWhichIsA("Bone", true) then
			preview:Destroy()
			warnOnce(skinId .. "PreviewShape", "invalid preview rig for " .. skinId)
			continue
		end
		local partCount = 0
		for _, descendant in ipairs(preview:GetDescendants()) do
			if descendant:IsA("BasePart") then
				partCount += 1
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanTouch = false
				descendant.CanQuery = false
				descendant.Transparency = 0
			elseif descendant:IsA("BaseScript") then
				descendant:Destroy()
			end
		end
		if partCount ~= 1 then
			preview:Destroy()
			warnOnce(skinId .. "PreviewParts", "preview requires one skinned MeshPart")
			continue
		end
		local boundsCFrame, boundsSize = preview:GetBoundingBox()
		local pivotToBounds = preview:GetPivot():ToObjectSpace(boundsCFrame)
		preview:PivotTo(root.CFrame
			* CFrame.new(0, boundsSize.Y * 0.5 - rootToFloor, 0)
			* pivotToBounds:Inverse())
		if topperConfig then
			local topper = topperTemplate:Clone()
			topper.Name = "ZyntraPremiumTopper"
			local topperPartCount = 0
			for _, descendant in ipairs(topper:GetDescendants()) do
				if descendant:IsA("BasePart") then
					topperPartCount += 1
					descendant.Anchored = true
					descendant.CanCollide = false
					descendant.CanTouch = false
					descendant.CanQuery = false
					descendant.Transparency = 0
				elseif descendant:IsA("BaseScript") then
					descendant:Destroy()
				end
			end
			if topperPartCount ~= 1 then
				topper:Destroy()
				preview:Destroy()
				warnOnce(skinId .. "PreviewTopper", "premium preview topper is invalid")
				continue
			end
			topper:ScaleTo(topperConfig.Scale)
			topper:PivotTo(upperTorso.CFrame
				* CFrame.new(0, topperConfig.Y, topperConfig.Z))
			topper.Parent = preview
		end
		preview.Parent = folder
	end
	folder.Parent = ReplicatedStorage
end

local function buildVisual(player, character, skinId)
	local templateName = TEMPLATE_PREFIX .. skinId .. TEMPLATE_SUFFIX
	local template = ServerStorage:FindFirstChild(templateName)
	if not template or not template:IsA("Model") then
		warnOnce(templateName, "missing ServerStorage." .. templateName)
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart")
		or humanoid.Health <= 0 then return nil end
	local topperConfig = PREMIUM_TOPPERS[skinId]
	local topperTemplate, upperTorso
	if topperConfig then
		topperTemplate = ServerStorage:FindFirstChild(topperConfig.Template)
		upperTorso = character:FindFirstChild("UpperTorso")
		if not topperTemplate or not topperTemplate:IsA("Model")
			or not upperTorso or not upperTorso:IsA("BasePart") then
			warnOnce(skinId .. "Topper", "premium topper unavailable; keeping the native suit")
			return nil
		end
	end

	local visual = template:Clone()
	visual.Name = VISUAL_NAME
	visual:SetAttribute("SkinId", skinId)
	if topperConfig then visual:SetAttribute("RequiresTopper", true) end
	local mesh = visual:FindFirstChild("char1", true)
	if not mesh or not mesh:IsA("MeshPart")
		or not mesh:FindFirstChildWhichIsA("Bone", true) then
		warnOnce(templateName .. "Shape", "invalid skinned rig in " .. templateName)
		visual:Destroy()
		return nil
	end
	local parts = 0
	for _, descendant in ipairs(visual:GetDescendants()) do
		if descendant:IsA("BasePart") then
			parts += 1
			-- The full-body model is visual only. It must never change hit tests,
			-- mass, movement, light collision, or physical ragdoll behavior.
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			descendant.Transparency = 1
		elseif descendant:IsA("BaseScript") then
			descendant.Enabled = false
		end
	end
	if parts ~= 1 then
		warnOnce(templateName .. "Parts", "expected one skinned MeshPart in " .. templateName)
		visual:Destroy()
		return nil
	end
	-- Studio's imported Model pivot is at the mesh *center*, even though the
	-- source glTF used a feet-origin. Align the actual lower bound with the
	-- authored R15 floor, using the measured bounds rather than a pivot guess.
	local boundsCFrame, boundsSize = visual:GetBoundingBox()
	local pivotToBounds = visual:GetPivot():ToObjectSpace(boundsCFrame)
	local authoredRig = StarterPlayer:FindFirstChild("StarterCharacter")
		or ServerStorage:FindFirstChild("StarterCharacter")
	local rootToFloor = rootToFootSole(authoredRig) or rootToFootSole(character)
	if not rootToFloor then
		warnOnce("NativeFeet", "could not measure native R15 feet; keeping the native suit")
		visual:Destroy()
		return nil
	end
	local targetBounds = root.CFrame * CFrame.new(0, boundsSize.Y * 0.5 - rootToFloor, 0)
	visual:PivotTo(targetBounds * pivotToBounds:Inverse())
	visual.Parent = character
	local weld = Instance.new("WeldConstraint")
	weld.Name = "ZyntraHazmatRootWeld"
	weld.Part0 = root
	weld.Part1 = mesh
	weld.Parent = mesh
	if topperConfig then
		local topper = topperTemplate:Clone()
		topper.Name = "ZyntraPremiumTopper"
		local topperPart
		for _, descendant in ipairs(topper:GetDescendants()) do
			if descendant:IsA("BasePart") then
				if topperPart then
					topper:Destroy()
					visual:Destroy()
					warnOnce(skinId .. "TopperShape", "premium topper must contain one part")
					return nil
				end
				topperPart = descendant
				descendant.Anchored = false
				descendant.CanCollide = false
				descendant.CanTouch = false
				descendant.CanQuery = false
				descendant.Massless = true
				descendant.Transparency = 1
			elseif descendant:IsA("BaseScript") then
				descendant.Enabled = false
			end
		end
		if not topperPart then
			topper:Destroy()
			visual:Destroy()
			warnOnce(skinId .. "TopperShape", "premium topper has no part")
			return nil
		end
		topper:ScaleTo(topperConfig.Scale)
		topper:PivotTo(upperTorso.CFrame
			* CFrame.new(0, topperConfig.Y, topperConfig.Z))
		topper.Parent = visual
		local topperWeld = Instance.new("WeldConstraint")
		topperWeld.Name = "ZyntraPremiumTopperWeld"
		topperWeld.Part0 = upperTorso
		topperWeld.Part1 = topperPart
		topperWeld.Parent = topperPart
	end
	-- The Level 1 mimic clones player Characters. It should use the native
	-- outfit and animations; copied cosmetic Bones would freeze in that clone.
	visual.Archivable = false
	return visual
end

local function refresh(player)
	local character = player.Character
	if player.Parent ~= Players or player:GetAttribute("InRound") ~= true
		or workspace:GetAttribute("RoundActive") ~= true
		or not character or not character.Parent then
		destroyVisual(player)
		return
	end
	-- A nil ID means the persistent profile has not loaded yet. Wait for its
	-- server-authored attribute instead of guessing a cosmetic on a lobby body.
	local skinId = player:GetAttribute("ZyntraSkinId")
	if type(skinId) ~= "string" or not Skins.Get(skinId)
		or keepsAdvancedColor(player, skinId) then
		destroyVisual(player)
		return
	end
	local state = active[player]
	if state and state.Character == character and state.SkinId == skinId
		and state.Visual.Parent == character then return end
	destroyVisual(player)
	local visual = buildVisual(player, character, skinId)
	if not visual then return end
	if player.Parent ~= Players or player.Character ~= character
		or player:GetAttribute("InRound") ~= true
		or player:GetAttribute("ZyntraSkinId") ~= skinId then
		visual:Destroy()
		return
	end
	active[player] = {Character = character, SkinId = skinId, Visual = visual}
end

local function addPlayer(player)
	local connections = {}
	playerConnections[player] = connections
	local characterChildConnection
	local function queueRefresh()
		task.defer(refresh, player)
	end
	for _, attribute in ipairs({"InRound", "ZyntraSkinId", "ZyntraHazmatColor",
		"ZyntraOwnsAdvancedEquipment"}) do
		table.insert(connections, player:GetAttributeChangedSignal(attribute):Connect(queueRefresh))
	end
	local function watchCharacter(character)
		if characterChildConnection then characterChildConnection:Disconnect() end
		characterChildConnection = character.ChildAdded:Connect(function(child)
			if child.Name == "HumanoidRootPart" or child:IsA("Humanoid") then
				queueRefresh()
			end
		end)
		queueRefresh()
	end
	table.insert(connections, player.CharacterAdded:Connect(watchCharacter))
	table.insert(connections, player.CharacterRemoving:Connect(function()
		if characterChildConnection then
			characterChildConnection:Disconnect()
			characterChildConnection = nil
		end
		destroyVisual(player)
	end))
	if player.Character then watchCharacter(player.Character) else queueRefresh() end
	table.insert(connections, {Disconnect = function()
		if characterChildConnection then characterChildConnection:Disconnect() end
	end})
end

workspace:GetAttributeChangedSignal("RoundActive"):Connect(function()
	for _, player in ipairs(Players:GetPlayers()) do task.defer(refresh, player) end
end)
Players.PlayerAdded:Connect(addPlayer)
Players.PlayerRemoving:Connect(function(player)
	destroyVisual(player)
	for _, connection in ipairs(playerConnections[player] or {}) do connection:Disconnect() end
	playerConnections[player] = nil
end)
for _, player in ipairs(Players:GetPlayers()) do addPlayer(player) end
publishPreviews()
