-- Bounded read-only collision geometry audit. Server Play only; no movement,
-- camera, properties, queue, physics, sources or gameplay state are changed.
local HS = game:GetService("HttpService")
local Run = game:GetService("RunService")
assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407 and Run:IsRunning(), "Wrong authoritative Play target")
local model = assert(workspace:FindFirstChild("LobbyReimaginedPreview"), "Preview not built")
assert(model:GetAttribute("Ready") == true, "Preview not ready")
local collisions = assert(model:FindFirstChild("PreviewCollisions"))
local center = model:GetAttribute("PreviewCenter")
assert(typeof(center) == "Vector3", "Missing preview center")
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = {collisions}
params.RespectCanCollide = true
local rayCount = 0
local function sample(x, z)
	rayCount += 1
	local hit = workspace:Raycast(center + Vector3.new(x, 9, z), Vector3.new(0, -14, 0), params)
	return hit and {name = hit.Instance.Name, y = hit.Position.Y - center.Y} or false
end
local gates = {}
for _, side in ipairs({-1, 1}) do
	for _, row in ipairs({-80, 0, 80}) do
		local failures, centerHeights = {}, {}
		for _, offset in ipairs({-9.5, -5, 0, 5, 9.5}) do
			for quarter = 108, 168 do
				local x = side * quarter / 4
				local hit = sample(x, row + offset)
				if not hit then table.insert(failures, {x = x, z = row + offset}) end
				if offset == 0 and quarter % 4 == 0 then table.insert(centerHeights, {x = x, hit = hit}) end
			end
		end
		table.insert(gates, {side = side, row = row, failedSamples = failures, centerHeights = centerHeights})
	end
end
local stage, topSeamDrops = {}, {}
for tenth = 1050, 1130 do
	local z = tenth / 10
	local hit = sample(0, z)
	table.insert(stage, {z = z, hit = hit})
	if tenth >= 1111 and tenth <= 1115 and (not hit or hit.y < 4.49) then table.insert(topSeamDrops, {z = z, hit = hit}) end
end
return HS:JSONEncode({
	schema = "lobby-preview-play-floor-ray-audit-v1",
	timestampUTC = DateTime.now():ToIsoDate(),
	placeId = game.PlaceId, universeId = game.GameId, placeVersion = game.PlaceVersion,
	mode = "Server Play", readonly = true,
	previewSourceBlendSHA = model:GetAttribute("BlenderSourceSHA256"),
	previewCenter = {center.X, center.Y, center.Z}, colliderCount = #collisions:GetChildren(),
	rayCount = rayCount, gates = gates, stage = stage, stageTopSeamDrops = topSeamDrops,
	limits = "Collision-only vertical ray grid: not a Humanoid traversal, replication, gameplay or performance test."
})
