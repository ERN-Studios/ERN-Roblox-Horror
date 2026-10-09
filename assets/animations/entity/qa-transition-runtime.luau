-- Read-only eight-second observer for the real Level 1 entity in Server/Client
-- Play. It never changes AI, tracks, velocity, rig, players or round flags.
local HS = game:GetService("HttpService")
local RunService = game:GetService("RunService")
assert(RunService:IsRunning(), "Run in a Play datamodel")
local entity = workspace:FindFirstChild("Entity")
local humanoid = entity and entity:FindFirstChildOfClass("Humanoid")
local root = entity and entity:FindFirstChild("HumanoidRootPart")
local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
assert(entity and humanoid and root and animator, "Actual Level 1 entity/animator required")
local result = {mode = RunService:IsServer() and "Server" or "Client", samples = {}, tracks = {},
	states = {}, transitionPhases = {}, checks = {}, failures = {}, unverified = {}}
local function check(ok, label)
	result.checks[#result.checks+1] = {passed = ok == true, label = label}
	if ok ~= true then result.failures[#result.failures+1] = label end
end
check(workspace:GetAttribute("SelectedLevel") == 1 and workspace:GetAttribute("RoundActive") == true,
	"Observer samples an actual active Level 1 round")
local expected = {
	Watch = {id="92831421568704", loop=true, priority="Idle", base=1},
	Walk = {id="121187609243437", loop=true, priority="Movement", base=9},
	Run_Chase = {id="90840395594409", loop=true, priority="Movement", base=15},
	Yell_Howl = {id="102035504530432", loop=false, priority="Action4"},
	Yell_FromRun = {id="132425538759403", loop=false, priority="Action4"},
	Lunge = {id="70970124497806", loop=false, priority="Action4"},
	Lunge_FromRun = {id="132839013239254", loop=false, priority="Action4"},
	Kill_GroundPinPunch = {id="94135265462008", loop=false, priority="Action4"},
}
local observed, movementDistance, previousPosition, previousDominant = {}, 0, root.Position, nil
local began = os.clock()
while os.clock()-began < 8 and root.Parent and entity:IsDescendantOf(workspace) do
	local now = os.clock()
	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X,0,velocity.Z).Magnitude
	local delta = root.Position - previousPosition
	movementDistance += Vector3.new(delta.X,0,delta.Z).Magnitude
	previousPosition = root.Position
	local state = tostring(workspace:GetAttribute("EntityState"))
	result.states[state] = (result.states[state] or 0)+1
	local sample = {at=now-began, state=state, speed=speed, anchored=root.Anchored,
		kill=workspace:GetAttribute("EntityKillActive")==true, tracks={}}
	local dominant
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		local rule = expected[track.Name]
		if rule then
			local clip = track.Animation
			local item = {name=track.Name, length=track.Length, speed=track.Speed,
				phase=track.Length>0 and track.TimePosition/track.Length or 0,
				weight=track.WeightCurrent, target=track.WeightTarget, playing=track.IsPlaying}
			sample.tracks[#sample.tracks+1] = item
			if not observed[track.Name] then
				observed[track.Name] = true
				result.tracks[track.Name] = {id=clip and clip.AnimationId, length=track.Length,
					loop=track.Looped, priority=track.Priority.Name}
				check(track.Length>0, "Real clip loaded: "..track.Name)
				check(clip ~= nil and clip.AnimationId=="rbxassetid://"..rule.id,
					"Published clip identity: "..track.Name)
				check(track.Looped==rule.loop and track.Priority.Name==rule.priority,
					"Real loop/priority: "..track.Name)
			end
			if rule.priority=="Movement" and item.weight>.01 and (not dominant or item.weight>dominant.weight) then
				dominant=item
			end
		end
	end
	if dominant and previousDominant and dominant.name~=previousDominant.name then
		local expectedPhase=(previousDominant.phase+(now-previousDominant.at)*previousDominant.speed/previousDominant.length)%1
		local phaseError=math.abs(dominant.phase%1-expectedPhase)
		phaseError=math.min(phaseError,1-phaseError)
		result.transitionPhases[#result.transitionPhases+1]={from=previousDominant.name,to=dominant.name,
			phaseError=phaseError,at=now-began}
	end
	previousDominant=dominant and {name=dominant.name,phase=dominant.phase,speed=dominant.speed,
		length=dominant.length,at=now} or nil
	result.samples[#result.samples+1]=sample
	task.wait(.1)
end
result.elapsedSeconds=os.clock()-began
result.horizontalDistance=movementDistance
check(movementDistance>1,"Real entity moved while sampled")
if not observed.Walk then result.unverified[#result.unverified+1]="Walk not observed in this window" end
if not observed.Run_Chase then result.unverified[#result.unverified+1]="Chase run not observed in this window" end
if #result.transitionPhases==0 then result.unverified[#result.unverified+1]="Walk/run crossfade not observed in this window" end
result.unverified[#result.unverified+1]="Visual feet/rig deformation must be viewed on the actual client"
result.unverified[#result.unverified+1]="Kill/hit timings and cancellation need a separate owned capture test"
result.passed=#result.failures==0
return HS:JSONEncode(result)
