-- Local gaze tension only. No camera direction, movement, damage or server state writes.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local UserInputService=game:GetService("UserInputService")
local GuiService=game:GetService("GuiService")
local Gaze=require(ReplicatedStorage:WaitForChild("WindowWatcherGazeLogic"))
local UIDevice=require(ReplicatedStorage:WaitForChild("UIDevice"))
local player=Players.LocalPlayer
local SHA="cbf260ff36b8c7226f27271456eae6bf4db7fd266bdce82dda8b0eae7cbc051e"
local BIND="Level5WindowWatcherGaze"
local random=Random.new()
local actor,head,pane,appearance,logic,generation
local rayClock,diagnosticClock=0,0
local hasLineOfSight=false
local appliedCamera,lastAppliedFov,ownOffset=nil,nil,0
local stopped=false

local function removeOwnFov()
	if appliedCamera and lastAppliedFov and math.abs(appliedCamera.FieldOfView-lastAppliedFov)<.0001 then
		appliedCamera.FieldOfView=math.clamp(appliedCamera.FieldOfView-ownOffset,1,120)
	end
	appliedCamera,lastAppliedFov,ownOffset=nil,nil,0
end
local function diagnostic(name,value)
	if script:GetAttribute(name)~=value then script:SetAttribute(name,value) end
end
local function detach(preserveGaze)
	if actor and actor.Parent and not preserveGaze then actor:SetAttribute("WindowWatcherGazeHidden",nil) end
	actor,head,pane,appearance=nil,nil,nil,nil
	if not preserveGaze then logic,generation=nil,nil end
	hasLineOfSight=false;rayClock=0
	removeOwnFov()
	diagnostic("GazeIntensity",0);diagnostic("GazeHidden",false)
end
local function ownedActor()
	local world=workspace:FindFirstChild("Level 5 Generated World")
	if not world or world:GetAttribute("Level5_MapOnly")~=true then return nil end
	local owner=world:FindFirstChild("Level5WindowWatcherEncounters")
	local candidate=owner and owner:FindFirstChild("WindowWatcher")
	if not candidate or not candidate:IsA("Model") or candidate:GetAttribute("Level5WindowWatcherOwned")~=true
		or candidate:GetAttribute("SourceGlbSha256")~=SHA or owner:GetAttribute("Level5WindowWatcherOwned")~=true then return nil end
	return candidate,owner,world
end
local function participant(camera)
	local character=player.Character
	local humanoid=character and character:FindFirstChildOfClass("Humanoid")
	return workspace:GetAttribute("SelectedLevel")==5 and workspace:GetAttribute("RoundActive")==true
		and player:GetAttribute("InRound")==true and player:GetAttribute("Escaped")~=true
		and player:GetAttribute("Spectating")~=true and humanoid and humanoid.Health>0
		and camera.CameraType==Enum.CameraType.Custom
		and player:GetAttribute("RoundEntryControlsReady")==true
		and player:GetAttribute("DispatchBriefingOpen")~=true
		and not GuiService.MenuIsOpen and not UIDevice.ScreenOwningModalOpen()
		and not UserInputService:GetFocusedTextBox()
end
local function frame(dt)
	removeOwnFov() -- subtract only our prior contribution; preserve other camera owners
	local camera=workspace.CurrentCamera
	if not camera then return end -- temporary camera replacement cannot reset a stare
	local current,owner,world=ownedActor()
	if not current then
		local preserve=workspace:GetAttribute("RoundActive")==true and workspace:GetAttribute("SelectedLevel")==5
		if actor or (logic and not preserve) then detach(preserve) end
		return
	end
	if current~=actor then
		local nextGeneration=world:GetAttribute("Level5_Generation")
		detach(logic and nextGeneration~=nil and generation==nextGeneration);actor=current
		if not logic then logic=Gaze.New(function() return random:NextNumber() end) end
		generation=nextGeneration
		head=actor:FindFirstChild("headfront",true) or actor:FindFirstChild("Head",true)
	end
	local count=owner:GetAttribute("AppearanceCount") or 0
	if count~=appearance then
		appearance=count;actor:SetAttribute("WindowWatcherGazeHidden",false)
		hasLineOfSight=false;rayClock=.1
	end
	if not head or not head:IsDescendantOf(actor) then
		head=actor:FindFirstChild("headfront",true) or actor:FindFirstChild("Head",true)
	end
	local allowed=participant(camera) and owner:GetAttribute("Visible")==true
		and actor:GetAttribute("WindowWatcherVisualReady")==true
	local target=head and head:IsA("Bone") and head.TransformedWorldCFrame.Position
		or actor:GetPivot():PointToWorldSpace(Vector3.new(0,7,0))
	local delta=target-camera.CFrame.Position
	local distance=delta.Magnitude
	local angle=distance>.001 and math.deg(math.acos(math.clamp(camera.CFrame.LookVector:Dot(delta.Unit),-1,1))) or 180
	rayClock+=math.min(dt,.1)
	if not allowed or angle>=30 or distance>145 then hasLineOfSight=false
	elseif rayClock>=.1 then
		rayClock=0
		-- Attribute/streaming order is not atomic. Resolve the actual pane again
		-- at each bounded ray tick, including arrivals during an appearance.
		local district=world:FindFirstChild("Level5_IndoorSuburbs")
		district=district and district:FindFirstChild("F_BayWindowCanyon")
		local anchors=district and district:FindFirstChild("WindowWatcherAnchors")
		local anchor=anchors and anchors:FindFirstChild(actor:GetAttribute("WindowAnchor") or "")
		local reference=anchor and anchor:FindFirstChild("WindowGlass")
		pane=reference and reference:IsA("ObjectValue") and reference.Value or nil
		local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances=player.Character and {actor,player.Character} or {actor}
		local hit=workspace:Raycast(camera.CFrame.Position,delta,params)
		hasLineOfSight=hit==nil or hit.Instance==pane
	end
	local result=Gaze.Step(logic,dt,{appearanceId=count,active=allowed==true,
		angleDegrees=angle,distance=distance,hasLineOfSight=hasLineOfSight})
	if actor:GetAttribute("WindowWatcherGazeHidden")~=result.hideForAppearance then
		actor:SetAttribute("WindowWatcherGazeHidden",result.hideForAppearance)
	end
	if result.hideForAppearance and actor.PrimaryPart then actor.PrimaryPart.LocalTransparencyModifier=1 end
	local motionReduced=player:GetAttribute("ReduceCameraShake")==true or player:GetAttribute("ReduceFlashing")==true
	local offset=allowed and not motionReduced and result.fovOffset or 0
	if math.abs(offset)>.00001 then
		appliedCamera=camera;local base=camera.FieldOfView
		lastAppliedFov=math.clamp(base+offset,1,120);ownOffset=lastAppliedFov-base
		camera.FieldOfView=lastAppliedFov
	end
	diagnosticClock+=dt
	if diagnosticClock>=.1 then
		diagnosticClock=0
		diagnostic("GazeIntensity",math.round(result.intensity*100)/100)
		diagnostic("GazeExposure",math.round(result.exposure*100)/100)
		diagnostic("GazeThresholdSeconds",result.thresholdSeconds)
		diagnostic("GazeHidden",result.hideForAppearance)
		diagnostic("GazeDistance",math.round(distance*10)/10)
		diagnostic("GazeAngle",math.round(angle*10)/10)
		diagnostic("GazeLineOfSight",hasLineOfSight)
		diagnostic("GazeAppearance",count)
	end
end
RunService:BindToRenderStep(BIND,Enum.RenderPriority.Camera.Value+4,function(dt)
	if stopped then return end
	local ok,detail=pcall(frame,dt)
	if not ok then
		removeOwnFov();diagnostic("GazeError",tostring(detail))
	else diagnostic("GazeError",nil) end
end)
script.Destroying:Connect(function()
	stopped=true;RunService:UnbindFromRenderStep(BIND);detach()
end)
