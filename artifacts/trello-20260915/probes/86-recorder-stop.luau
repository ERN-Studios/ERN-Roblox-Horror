--!strict
-- Card #86 probe: stop the recorder and leave the place as it was found.
-- Read 86-recorder-read.luau FIRST; this destroys the samples.

local folder = workspace:FindFirstChild("Probe86")
local samples = folder and folder:GetAttribute("Samples") or 0
local stalls = folder and folder:GetAttribute("Stalls") or 0
if folder then
	folder:SetAttribute("Running", false)
	task.defer(function() folder:Destroy() end)
end
workspace:SetAttribute("Level2_PoolSlideDiagnostics", nil)
return ("Probe86 removed after %s samples / %s stalls; diagnostics attribute cleared."
	.. " Run 86-round-control.luau with ACTION=\"restore\" as well.")
	:format(tostring(samples), tostring(stalls))
