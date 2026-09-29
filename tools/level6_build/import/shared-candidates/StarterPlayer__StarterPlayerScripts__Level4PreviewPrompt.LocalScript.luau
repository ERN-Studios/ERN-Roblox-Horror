-- Hides the Level 4, Level 5 and Level 6 developer preview prompts from players outside DevAccess.
-- Cosmetic only: preview access and GameManager re-check DevAccess on every entry.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PROMPTS = {
	Level4DeveloperPreviewPrompt = true,
	Level4DeveloperPreviewReturnPrompt = true,
	Level5DeveloperPreviewPrompt = true,
	Level5DeveloperPreviewReturnPrompt = true,
	Level6DeveloperPreviewPrompt = true,
	Level6DeveloperPreviewReturnPrompt = true,
}

-- Fail closed: a missing or erroring allowlist hides the prompts.
local accessModule = ReplicatedStorage:WaitForChild("DevAccess", 10)
local ok, allowed = pcall(function()
	return accessModule ~= nil and require(accessModule).IsAllowed(Players.LocalPlayer)
end)
if ok and allowed == true then return end

local watching = setmetatable({}, {__mode = "k"})
local function hide(instance)
	if not PROMPTS[instance.Name] or not instance:IsA("ProximityPrompt") then return end
	if not watching[instance] then
		watching[instance] = true
		instance:GetPropertyChangedSignal("Enabled"):Connect(function()
			if instance.Enabled then instance.Enabled = false end
		end)
	end
	if instance.Enabled then instance.Enabled = false end
end

workspace.DescendantAdded:Connect(hide)
for _, descendant in ipairs(workspace:GetDescendants()) do hide(descendant) end
