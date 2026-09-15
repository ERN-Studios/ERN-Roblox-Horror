--!strict
-- Card #86 probe (a) + (b): install the Pool Slide stall recorder.
--
-- Run ONCE in a play-session Server datamodel; it returns immediately and the
-- sampler keeps running in the background. Read it back with
-- 86-recorder-read.luau. Nothing in the place is edited: the probe adds one
-- workspace folder and one workspace attribute, both removed by
-- 86-recorder-stop.luau.
--
-- It reads ATTRIBUTES ONLY. require() inside execute_luau is a separate module
-- instance, so Controller.GetDebugSnapshot() is unreachable from here; the
-- controller publishes the navigator fields this needs while
-- workspace.Level2_PoolSlideDiagnostics is true.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local SAMPLE_INTERVAL = .25
local STALL_SPEED = .5          -- studs/s below which the rig counts as standing
local STALL_SECONDS = 4         -- ... for this long, with a target, is a stall
local MAX_LOG_BYTES = 400000

local previous = workspace:FindFirstChild("Probe86")
if previous then previous:Destroy() end

local folder = Instance.new("Folder")
folder.Name = "Probe86"
local samples = Instance.new("StringValue")
samples.Name = "Samples"
samples.Parent = folder
local stalls = Instance.new("StringValue")
stalls.Name = "Stalls"
stalls.Parent = folder
folder:SetAttribute("Running", true)
folder:SetAttribute("Samples", 0)
folder:SetAttribute("Stalls", 0)
folder.Parent = workspace

workspace:SetAttribute("Level2_PoolSlideDiagnostics", true)

local COLUMNS = {"wall", "cpu", "seed", "pinned", "pumps", "paused", "state",
	"phase", "path", "computing", "waypoints", "clearanceProbes", "moving",
	"speed", "x", "y", "z", "targetId", "targetDist", "stillFor", "failure"}
samples.Value = table.concat(COLUMNS, ",") .. "\n"
stalls.Value = "wall,seconds,state,path,computing,waypoints,clearanceProbes,"
	.. "x,z,targetId,targetX,targetZ,failure\n"

local function state()
	local node = ReplicatedStorage:FindFirstChild("Level 2 State")
	return node and node:IsA("Folder") and node or nil
end

local function attr(name, fallback)
	local node = state()
	local value = node and node:GetAttribute("Level2_PoolSlide" .. name)
	if value == nil then return fallback end
	return value
end

local function slideModel()
	local world = workspace:FindFirstChild("Level 2 World", true)
	local runtime = (world or workspace):FindFirstChild("Level 2 Pool Slide Runtime", true)
	local model = runtime and runtime:FindFirstChild("Level 2 Pool Slide")
	return model and model:IsA("Model") and model or nil
end

local function targetRoot(userId)
	if userId == 0 then return nil end
	local player = Players:GetPlayerByUserId(userId)
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and root:IsA("BasePart") and root or nil
end

local function csv(values)
	local out = table.create(#values)
	for index, value in ipairs(values) do
		if type(value) == "number" then
			out[index] = string.format("%.3f", value)
		else
			out[index] = string.gsub(tostring(value), "[,\n\r]", " ")
		end
	end
	return table.concat(out, ",")
end

task.spawn(function()
	local lastPosition, stillSince, stallOpen = nil, nil, false
	while folder.Parent and folder:GetAttribute("Running") == true do
		local wall = workspace:GetServerTimeNow()
		local model = slideModel()
		local position = model and model:GetPivot().Position or Vector3.zero
		local moved = lastPosition and (position - lastPosition).Magnitude or 0
		lastPosition = position

		local targetId = attr("TargetUserId", 0)
		local root = targetRoot(targetId)
		local speed = attr("Speed", 0)
		local standing = (moved / SAMPLE_INTERVAL) < STALL_SPEED
		if standing and targetId ~= 0 and model then
			stillSince = stillSince or wall
		else
			stillSince, stallOpen = nil, false
		end
		local stillFor = stillSince and (wall - stillSince) or 0

		if #samples.Value < MAX_LOG_BYTES then
			samples.Value ..= csv({wall, os.clock(),
				workspace:GetAttribute("Level2Seed") or 0,
				tostring(workspace:GetAttribute("Level2_SeedPinned")),
				workspace:GetAttribute("Level2Pumps") or 0,
				tostring(workspace:GetAttribute("EntityPaused") == true),
				attr("State", "?"), attr("Phase", "?"), attr("PathStatus", "?"),
				tostring(attr("Computing", "?")), attr("Waypoints", -1),
				attr("ClearanceProbes", -1), tostring(attr("Moving", "?")),
				speed, position.X, position.Y, position.Z, targetId,
				root and (root.Position - position).Magnitude or -1,
				stillFor, attr("PathFailure", "")}) .. "\n"
			folder:SetAttribute("Samples", folder:GetAttribute("Samples") + 1)
		end

		-- One line per stall EPISODE, written the moment it qualifies.
		if stillFor >= STALL_SECONDS and not stallOpen then
			stallOpen = true
			stalls.Value ..= csv({wall, stillFor, attr("State", "?"),
				attr("PathStatus", "?"), tostring(attr("Computing", "?")),
				attr("Waypoints", -1), attr("ClearanceProbes", -1),
				position.X, position.Z, targetId,
				root and root.Position.X or 0, root and root.Position.Z or 0,
				attr("PathFailure", "")}) .. "\n"
			folder:SetAttribute("Stalls", folder:GetAttribute("Stalls") + 1)
		end
		task.wait(SAMPLE_INTERVAL)
	end
end)

return ("Probe86 recording every %.2fs; stall = under %.1f studs/s for %.0fs with a target")
	:format(SAMPLE_INTERVAL, STALL_SPEED, STALL_SECONDS)
