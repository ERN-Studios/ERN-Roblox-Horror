-- One server-owned prewarm job, shared by every public Level 3 admission.
-- Opaque Blender content is session-owned; never charge its bake to round entry.
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local Warmup = {}
Warmup.TimeoutSeconds = 1200
local REVISION_SHA = "d2eddfce3820a27f01cdd53b93b719ec8bf8d048b9313bc6cdf29610344acc6b"
local started, finished, startedAt, deadline, lastError = false, false, nil, nil, nil

local function readyKit()
 local kit = ServerStorage:FindFirstChild("Level6BlenderKit")
 return kit and kit:IsA("Folder") and kit:GetAttribute("Ready") == true
  and kit:GetAttribute("BlenderSourceSHA256") == REVISION_SHA and kit or nil
end

local function publish(state)
 workspace:SetAttribute("Level3KitReady", readyKit() ~= nil)
 workspace:SetAttribute("Level3KitState", state)
 workspace:SetAttribute("Level3KitError", lastError)
 if startedAt then workspace:SetAttribute("Level3KitWarmSeconds", math.round((os.clock()-startedAt)*100)/100) end
end

function Warmup.Start()
 assert(not RunService:IsClient(), "Level 3 kit prewarm is server-only")
 if started then return end
 started, startedAt = true, os.clock()
 deadline = startedAt + Warmup.TimeoutSeconds
 if readyKit() then finished = true; publish("ready"); return end
 publish("warming")
 -- Ensure itself owns concurrent callers from the original Level 6 DEV preview.
 -- A cancelled round never cancels this shared engine job or starts a second one.
 task.spawn(function()
  local ok, problem = pcall(function()
   local systems = assert(ServerScriptService:FindFirstChild("Level 6 Systems"), "Missing shared Blender systems")
   local module = assert(systems:FindFirstChild("Level6BlenderRuntimeBake"), "Missing shared Blender bake")
   assert(module:IsA("ModuleScript"), "Wrong shared Blender bake class")
   require(module).Ensure()
   assert(readyKit(), "Shared Blender bake did not produce the revised public kit")
  end)
  finished = true
  if not ok then
   lastError = string.sub(tostring(problem), 1, 500)
   publish("failed")
   warn("[Level 3 Kit Warmup] " .. lastError)
   return
  end
  lastError = nil
  publish("ready")
 end)
end

function Warmup.Status()
 return {Ready=readyKit() ~= nil, Started=started, Busy=started and not finished,
  Deadline=deadline, StartedAt=startedAt, LastError=lastError}
end

function Warmup.Await(allowed)
 Warmup.Start()
 while true do
  -- Recheck the caller's own cohort/epoch before returning a shared result.
  if allowed and allowed() ~= true then return false, "ADMISSION_CANCELLED" end
  if readyKit() then return true end
  if finished then return false, "LEVEL3_KIT_FAILED" end
  if os.clock() >= deadline then
   lastError = "Revised Blender kit prewarm exceeded its bounded server wait"
   publish("timeout")
   return false, "LEVEL3_KIT_TIMEOUT"
  end
  task.wait(.2)
 end
end

return Warmup
