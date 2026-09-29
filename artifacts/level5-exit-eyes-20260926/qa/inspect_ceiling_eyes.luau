-- Read-only native client snapshot. Does not fabricate participants, move rigs,
-- set attributes, send remotes or change lighting/camera/player state.
local Audit={}
function Audit.Snapshot()
	local Players=game:GetService("Players")
	local RunService=game:GetService("RunService")
	local world=workspace:FindFirstChild("Level 5 Generated World")
	local architecture=world and world:FindFirstChild("Level5_IndoorSuburbs")
	local H=architecture and architecture:FindFirstChild("H_LastHouse")
	local group=H and H:FindFirstChild("ExitCeilingEyes")
	local report={context=RunService:IsClient() and "Client" or "Server",failures={},rigs={},
		parts=0,meshes=0,lenses=0,targets={},maxPivotPositionError=0,maxPartFramePositionError=0,
		limitations={"Single snapshot does not prove motion or settled aiming; compare after moving a real player",
			"Server snapshots see rest geometry; client snapshots are required to observe tracking",
			"Mocked selection tests do not establish native multiplayer behavior"}}
	local function fail(code,rig,detail) table.insert(report.failures,{code=code,rig=rig and rig.Name,detail=detail}) end
	if not group then fail("MISSING_EYES",nil);report.pass=false;return report end
	report.active=group:GetAttribute("TrackingActive");report.status=group:GetAttribute("TrackingStatus")
	report.ready=group:GetAttribute("TrackingReadyCount");report.participants=group:GetAttribute("TrackingParticipantCount")
	for _,rig in ipairs(group:GetChildren()) do
		if not rig:IsA("Model") or rig:GetAttribute("Level5CeilingEye")~=true then continue end
		local home=rig:GetAttribute("HomeCFrame")
		if typeof(home)~="CFrame" then fail("MISSING_HOME",rig);continue end
		local pivot=rig:GetPivot();local positionError=(pivot.Position-home.Position).Magnitude
		report.maxPivotPositionError=math.max(report.maxPivotPositionError,positionError)
		if positionError>.02 then fail("MOUNT_TRANSLATED",rig,tostring(positionError)) end
		local row={name=rig.Name,index=rig:GetAttribute("EyeIndex"),targetUserId=rig:GetAttribute("TargetUserId") or 0,
			position={pivot.Position.X,pivot.Position.Y,pivot.Position.Z},look={pivot.LookVector.X,pivot.LookVector.Y,pivot.LookVector.Z},
			positionError=positionError,parts=0,ceilingClearance=rig:GetAttribute("CeilingClearance")}
		local _,angle=home:ToObjectSpace(pivot):ToAxisAngle();row.angleFromRest=math.abs(angle)
		if row.ceilingClearance and row.ceilingClearance<.49 then fail("ROTATION_CEILING_CLEARANCE",rig,tostring(row.ceilingClearance)) end
		if not rig.PrimaryPart or rig:GetAttribute("ExpectedPartCount")~=4 or rig:GetAttribute("ExpectedMeshCount")~=4 then fail("RIG_CONTRACT",rig) end
		for _,part in ipairs(rig:GetChildren()) do
			if part:IsA("BasePart") then
				row.parts+=1;report.parts+=1
				local mesh=part:FindFirstChild("EyeEllipsoid")
				if mesh and mesh:IsA("SpecialMesh") and mesh.MeshType==Enum.MeshType.Sphere then report.meshes+=1
				else fail("ELLIPSOID_MESH_MISSING",rig,part.Name) end
				if not part.Anchored or part.CanCollide or part.CanTouch or part.CanQuery or part.CastShadow then fail("PHYSICAL_INTERFERENCE",rig,part.Name) end
				local localFrame=part:GetAttribute("HomeLocalCFrame")
				if typeof(localFrame)~="CFrame" then fail("MISSING_PART_REST",rig,part.Name) else
					local expected=pivot*localFrame
					local error=(expected.Position-part.Position).Magnitude
					report.maxPartFramePositionError=math.max(report.maxPartFramePositionError,error)
					if error>.03 then fail("STREAMED_PART_OFFSET_CORRUPTION",rig,part.Name..":"..error) end
				end
				if part.Name:match("^LuminousLens") then
					report.lenses+=1
					if part.Material~=Enum.Material.Neon then fail("NON_EMISSIVE_LENS",rig,part.Name) end
				end
			end
		end
		if row.parts~=4 then fail("PART_COUNT",rig,tostring(row.parts)) end
		if row.targetUserId~=0 then
			report.targets[tostring(row.targetUserId)]=(report.targets[tostring(row.targetUserId)] or 0)+1
			local target=Players:GetPlayerByUserId(row.targetUserId)
			local character=target and target.Character
			local head=character and character:FindFirstChild("Head")
			local humanoid=character and character:FindFirstChildOfClass("Humanoid")
			row.targetAlive=humanoid and humanoid.Health>0 or false
			row.targetInRound=target and target:GetAttribute("InRound")==true or false
			if head then
				local delta=head.Position-pivot.Position
				row.distance=delta.Magnitude
				row.lookDot=delta.Magnitude>.01 and pivot.LookVector:Dot(delta.Unit) or nil
			end
		end
		table.insert(report.rigs,row)
	end
	table.sort(report.rigs,function(a,b) return (a.index or 0)<(b.index or 0) end)
	if #report.rigs~=48 or report.parts~=192 or report.meshes~=192 or report.lenses~=96 then fail("TOTAL_COUNTS",nil,string.format("rigs%d parts%d meshes%d lenses%d",#report.rigs,report.parts,report.meshes,report.lenses)) end
	report.pass=#report.failures==0
	return report
end
return Audit
