-- DisableWalkingSound
-- Place in StarterPlayer > StarterCharacterScripts

local character = script.Parent
local root = character:WaitForChild("HumanoidRootPart")

local function disableRunningSound(object)
	if object:IsA("Sound") and object.Name == "Running" then
		object.Volume = 0
		object.Playing = false
	end
end

for _, object in ipairs(root:GetChildren()) do
	disableRunningSound(object)
end

root.ChildAdded:Connect(disableRunningSound)

print("[DisableWalkingSound] Default Roblox walking sound disabled")