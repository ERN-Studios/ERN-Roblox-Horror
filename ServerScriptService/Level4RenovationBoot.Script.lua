-- Applies the Level 4-only renovation when an existing or freshly built preview appears.
local renovation = require(script.Parent:WaitForChild("Level4Renovation"))
local previewName = "Level 4 Cinema Preview"

local function apply(model)
	if not (model:IsA("Model") and model.Name == previewName
		and model:GetAttribute("Level4Preview") == true
		and model:GetAttribute("PreviewOnly") == true) then return end
	local extension = model:FindFirstChild("ExtendedCinema")
	if not (extension and extension:GetAttribute("Complete") == true) then return end
	local ok, result, reason = pcall(renovation.Apply, model)
	if not ok or not result then
		warn("[Level4RenovationBoot] Level 4 renovation failed:", if ok then reason else result)
	end
end

local function watch(model)
	if not (model:IsA("Model") and model.Name == previewName) then return end
	model.ChildAdded:Connect(function(child)
		if child.Name == "ExtendedCinema" then task.defer(apply, model) end
	end)
	task.defer(apply, model)
end

workspace.ChildAdded:Connect(watch)
local existing = workspace:FindFirstChild(previewName)
if existing then watch(existing) end
