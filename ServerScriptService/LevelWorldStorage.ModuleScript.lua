-- Inactive authored maps stay server-only; controllers own their entry/cleanup lifetimes.
local ServerStorage = game:GetService("ServerStorage")
local NAMES = {
	[4] = "Level 4 Cinema Blender",
	[5] = "Level 5 Void",
	[6] = "Level 6 Indoor Playground",
}
local Storage = {}

local function unique(parent, name)
	local found
	for _, child in parent:GetChildren() do
		if child.Name == name then
			assert(not found, "Duplicate authored map: " .. name)
			found = child
		end
	end
	assert(not found or found:IsA("Model"), "Authored map is not a Model: " .. name)
	return found
end

function Storage.Get(level)
	local name = assert(NAMES[level], "Unsupported authored level")
	local live, parked = unique(workspace, name), unique(ServerStorage, name)
	assert(not (live and parked), "Authored map exists in both containers: " .. name)
	return live or parked
end

function Storage.Activate(level)
	local model = Storage.Get(level)
	if model and model.Parent ~= workspace then model.Parent = workspace end
	return model
end

function Storage.Deactivate(level)
	local model = Storage.Get(level)
	if model and model.Parent ~= ServerStorage then model.Parent = ServerStorage end
	return model
end

return Storage
