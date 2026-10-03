-- Level 5 map preview: one per-client lighting owner, with exact restoration
-- of each property it changes. No Level 4 objects, terrain or cloud changes.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local LIGHTING_KEYS = {
	"ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "ColorShift_Top",
	"ColorShift_Bottom", "GlobalShadows", "EnvironmentDiffuseScale",
	"EnvironmentSpecularScale", "ExposureCompensation", "FogColor", "FogStart", "FogEnd",
}
local AIR_KEYS = {"Density", "Offset", "Haze", "Glare", "Color", "Decay"}
local snapshot, airSnapshot, air = nil, nil, nil
local stateConnection = nil
local watchedState = nil
local pending = false

local function restore()
	if snapshot then
		for property, value in pairs(snapshot) do Lighting[property] = value end
	end
	if airSnapshot and air and air.Parent == Lighting then
		for property, value in pairs(airSnapshot) do air[property] = value end
	end
	snapshot, airSnapshot, air = nil, nil, nil
end

local function sync()
	local state = ReplicatedStorage:FindFirstChild("Level 5 State")
	local world = workspace:FindFirstChild("Level 5 Generated World")
	local owns = world ~= nil and workspace:GetAttribute("SelectedLevel") == 5
		and workspace:GetAttribute("Level5LightingOwnedByController") == true
		and player:GetAttribute("InRound") == true
		and state ~= nil and state:GetAttribute("Level5_MapOnly") == true
	if not owns then restore(); return end
	if not snapshot then
		snapshot = {}
		for _, property in ipairs(LIGHTING_KEYS) do snapshot[property] = Lighting[property] end
		air = Lighting:FindFirstChildOfClass("Atmosphere")
		if air then
			airSnapshot = {}
			for _, property in ipairs(AIR_KEYS) do airSnapshot[property] = air[property] end
		end
	end
	for _, property in ipairs(LIGHTING_KEYS) do
		local value = state:GetAttribute("Lighting_" .. property)
		if value ~= nil then Lighting[property] = value end
	end
	if air and air.Parent == Lighting then
		for _, property in ipairs(AIR_KEYS) do
			local value = state:GetAttribute("Atmosphere_" .. property)
			if value ~= nil then air[property] = value end
		end
	end
end

local function queueSync()
	if pending then return end
	pending = true
	task.defer(function()
		pending = false
		sync()
	end)
end

local function watchState()
	local state = ReplicatedStorage:FindFirstChild("Level 5 State")
	if state == watchedState then return end
	if stateConnection then stateConnection:Disconnect(); stateConnection = nil end
	watchedState = state
	if state then stateConnection = state.AttributeChanged:Connect(queueSync) end
	queueSync()
end

workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(queueSync)
workspace:GetAttributeChangedSignal("Level5LightingOwnedByController"):Connect(queueSync)
player:GetAttributeChangedSignal("InRound"):Connect(queueSync)
workspace.ChildAdded:Connect(function(child)
	if child.Name == "Level 5 Generated World" then queueSync() end
end)
workspace.ChildRemoved:Connect(function(child)
	if child.Name == "Level 5 Generated World" then queueSync() end
end)
ReplicatedStorage.ChildAdded:Connect(watchState)
ReplicatedStorage.ChildRemoved:Connect(watchState)
script.Destroying:Connect(restore)
watchState()
queueSync()
