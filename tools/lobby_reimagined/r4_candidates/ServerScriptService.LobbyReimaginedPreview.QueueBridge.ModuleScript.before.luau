-- R3 adapter only. GameManager retains all admission, countdown and launch logic.
local Bridge = {}
local NAME = "LobbyReimaginedPreview"
local FIRST_ID, COUNT = 101, 24

function Bridge.IsLobby(model)
	return typeof(model) == "Instance" and model:IsA("Model") and model.Name == NAME
		and model.Parent == workspace and model:GetAttribute("LobbyReimaginedOwned") == true
		and model:GetAttribute("R3QueueRevision") == 3 and model:GetAttribute("Ready") == true
end

function Bridge.Build(model)
	assert(Bridge.IsLobby(model), "R3 queue model is not ready/owned")
	local found, result = {}, {}
	for _, zone in ipairs(model:GetDescendants()) do
		local id = zone:GetAttribute("R3QueueId")
		if id ~= nil then
			assert(zone:IsA("BasePart") and type(id) == "number" and id % 1 == 0
				and id >= FIRST_ID and id < FIRST_ID + COUNT, "Invalid R3 queue zone/id")
			assert(not found[id], "Duplicate R3 queue id")
			local ordinal = id - FIRST_ID
			local level, displayIndex = math.floor(ordinal / 4) + 1, ordinal % 4 + 1
			assert(zone:GetAttribute("LevelNumber") == level
				and zone:GetAttribute("QueueDisplayIndex") == displayIndex, "R3 queue metadata mismatch")
			assert(zone.Anchored and not zone.CanCollide and not zone.CanTouch and not zone.CanQuery,
				"Queue detector must be anchored/nonphysical")
			local radius = zone:GetAttribute("QueueRadius")
			assert(zone:GetAttribute("QueueDetectorShape") == "Circle" and type(radius) == "number"
				and radius == radius and radius > 0 and radius < math.huge
				and radius <= math.min(zone.Size.X, zone.Size.Z) * .5, "Invalid circular detector")
			local bay = zone.Parent
			local floor = bay and bay:FindFirstChild("ChamberFloor")
			local diameter = bay and bay:GetAttribute("CircularBayDiameter")
			assert(bay and bay:IsA("Model") and floor and floor:IsA("BasePart")
				and type(diameter) == "number" and diameter > radius * 2,
				"Queue zone requires direct bay parent, ChamberFloor and diameter")
			local ownerRef = zone:FindFirstChild("QueueRenderOwner")
			local owner = ownerRef and ownerRef:IsA("ObjectValue") and ownerRef.Value
			assert(owner and owner:IsA("Model") and owner:IsDescendantOf(model), "Missing queue render owner")
			local title, sub = owner:FindFirstChild("QueueTitle", true), owner:FindFirstChild("QueueSubtitle", true)
			assert(title and title:IsA("TextLabel") and sub and sub:IsA("TextLabel"), "Missing queue text labels")
			found[id] = {index = id, displayIndex = displayIndex, level = level,
				zone = zone, title = title, sub = sub, color = zone.Color, busy = false,
				revisionOwned = true, lobbyOwner = model, renderOwner = owner, previewOnly = level > 3}
		end
	end
	for id = FIRST_ID, FIRST_ID + COUNT - 1 do
		assert(found[id], "Missing R3 queue id " .. id)
		table.insert(result, found[id])
	end
	return result
end

-- Called by existing DEV preview handlers before AND after their streaming yield.
-- This does not replace their allowlist, living-avatar, reach, cooldown or floor checks.
function Bridge.IsPreviewEntry(part, level)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") or level < 4 or level > 6 then return false end
	local model = workspace:FindFirstChild(NAME)
	return Bridge.IsLobby(model) and part:IsDescendantOf(model)
		and part:GetAttribute("R3DeveloperPreviewEntry") == level
end

function Bridge.GetPreviewEntries(model, level)
	local result = {}
	if not Bridge.IsLobby(model) then return result end
	for _, part in ipairs(model:GetDescendants()) do
		if Bridge.IsPreviewEntry(part, level) then table.insert(result, part) end
	end
	return result
end

return Bridge
