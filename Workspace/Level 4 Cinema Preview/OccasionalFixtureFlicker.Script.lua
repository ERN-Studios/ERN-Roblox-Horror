local model = script.Parent
local fixtures = {}
for _, part in model:GetDescendants() do
	if part:IsA("BasePart") and part:GetAttribute("OccasionalFlicker") then
		table.insert(fixtures, part)
	end
end
while model:IsDescendantOf(workspace) and #fixtures > 0 do
	task.wait(math.random(12, 24))
	if not model:IsDescendantOf(workspace) then break end
	local part = fixtures[math.random(1, #fixtures)]
	local point = part:FindFirstChildOfClass("PointLight")
	if part:IsDescendantOf(model) then
		local oldMaterial, oldColor, oldTransparency = part.Material, part.Color, part.Transparency
		local oldLight = point and point.Enabled
		if point then point.Enabled = false end
		part.Material = Enum.Material.SmoothPlastic
		part.Color = oldColor:Lerp(Color3.new(0, 0, 0), 0.8)
		part.Transparency = math.min(0.8, oldTransparency + 0.55)
		task.wait(0.08)
		if part.Parent then
			part.Material, part.Color, part.Transparency = oldMaterial, oldColor, oldTransparency
			if point and point.Parent then point.Enabled = oldLight end
		end
	end
end
