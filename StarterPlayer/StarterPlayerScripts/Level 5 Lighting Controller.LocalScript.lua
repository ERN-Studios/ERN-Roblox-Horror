-- Level 5, the void rooms: one per-client lighting owner while the local character is inside the map's
-- bounds, with exact restoration of each property it changes.
--
-- The look depends on there being NO light that the level's own lamps do not make: the rooms are lit by
-- PointLights at walkway height and above, and everything below them has to fall to black. So inside the
-- bounds the sky's contribution and the lobby's atmosphere are taken out. RoundUI stands down while
-- `Level5LightingOwned` is set (the same arrangement as the Level 4 cinema).
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local MODEL_NAME = "Level 5 Void"
local WANT = {
	ClockTime = 0, Brightness = 0, Ambient = Color3.new(0, 0, 0), OutdoorAmbient = Color3.new(0, 0, 0),
	EnvironmentDiffuseScale = 0, EnvironmentSpecularScale = 0, ExposureCompensation = 0.55,
	FogColor = Color3.new(0, 0, 0), FogStart = 0, FogEnd = 100000, GlobalShadows = true,
}
local snapshot, airDensity, air = nil, nil, nil
local grade = nil

local function inside()
	local model = workspace:FindFirstChild(MODEL_NAME)
	local centre, size = model and model:GetAttribute("BoundsCenter"), model and model:GetAttribute("BoundsSize")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if typeof(centre) ~= "Vector3" or typeof(size) ~= "Vector3" or not root then return false end
	local offset = root.Position - centre
	return math.abs(offset.X) <= size.X / 2 + 30 and math.abs(offset.Z) <= size.Z / 2 + 30
		and math.abs(offset.Y) <= size.Y / 2 + 200
end

local function restore()
	if snapshot then
		for property, value in pairs(snapshot) do Lighting[property] = value end
		snapshot = nil
	end
	if air and airDensity and air.Parent == Lighting then air.Density = airDensity end
	air, airDensity = nil, nil
	if grade then grade:Destroy(); grade = nil end
	player:SetAttribute("Level5LightingOwned", nil)
end

local function own()
	if not snapshot then
		snapshot = {}
		for property in pairs(WANT) do snapshot[property] = Lighting[property] end
		air = Lighting:FindFirstChildOfClass("Atmosphere")
		airDensity = air and air.Density or nil
		grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "Level5VoidGrade"
		grade.Saturation, grade.Contrast, grade.Brightness = 0.08, -0.06, 0
		grade.Parent = Lighting
		player:SetAttribute("Level5LightingOwned", true)
	end
	for property, value in pairs(WANT) do
		if Lighting[property] ~= value then Lighting[property] = value end
	end
	if air and air.Parent == Lighting and air.Density ~= 0 then air.Density = 0 end
	local lobby = Lighting:FindFirstChild("LobbyLocalGrade")
	if lobby and lobby:IsA("ColorCorrectionEffect") and lobby.Enabled then lobby.Enabled = false end
end

local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed < 0.2 then return end
	elapsed = 0
	if inside() then own() elseif snapshot then restore() end
end)
script.Destroying:Connect(restore)
