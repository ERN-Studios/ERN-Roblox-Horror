local player=game.Players.LocalPlayer
local run=game.RunService
local camera=workspace.CurrentCamera
local before={cf=camera.CFrame,type=camera.CameraType,fov=camera.FieldOfView,reduced=player:GetAttribute("ReduceCameraShake")}
local world=workspace["Level 5 Generated World"]
local owner=world.Level5WindowWatcherEncounters
local actor=owner.WindowWatcher
local gaze=player.PlayerScripts.WindowWatcherGazeClient
local report={status="RUNNING",started=os.clock(),samples={},fovMin=before.fov,fovMax=before.fov,failures={}}
_G.WWGazeNative=report
local phase="waiting"
local revealedAt=nil
local vanishedAt=nil
local bound="WindowWatcherGazeNativeView"
local connection
local function finish(reason)
 run:UnbindFromRenderStep(bound)
 if connection then connection:Disconnect() end
 player:SetAttribute("ReduceCameraShake",before.reduced)
 camera.CameraType=before.type;camera.CFrame=before.cf
 report.finishedReason=reason
 game.ReplicatedStorage.Remotes.RoundStatus:FireServer("leaveround")
 task.delay(1,function()
  report.fovAfterExit=camera.FieldOfView
  if math.abs(camera.FieldOfView-before.fov)>.001 then table.insert(report.failures,"FOV not restored") end
  report.status=#report.failures==0 and "PASS_OBSERVED_CHECKS" or "FAIL"
 end)
end
run:BindToRenderStep(bound,Enum.RenderPriority.Camera.Value+3,function()
 if not owner.Parent then return end
 local name=actor:GetAttribute("WindowAnchor")
 local anchor=name and world.Level5_IndoorSuburbs.F_BayWindowCanyon.WindowWatcherAnchors:FindFirstChild(name)
 if not anchor then return end
 local pane=anchor.WindowGlass.Value
 local head=actor:FindFirstChild("headfront",true)
 if not head then return end
 local origin=pane.CFrame:PointToWorldSpace(Vector3.new(3,.3,-11))
 local target=head.TransformedWorldCFrame.Position
 local cf=CFrame.lookAt(origin,target)
 if phase=="approach" then cf*=CFrame.Angles(0,math.rad(20),0)
 elseif phase=="away" then cf*=CFrame.Angles(0,math.rad(70),0) end
 camera.CameraType=Enum.CameraType.Custom;camera.CFrame=cf
end)
connection=run.Heartbeat:Connect(function()
 local now=os.clock()
 if now-report.started>28 then table.insert(report.failures,"Test timeout");finish("timeout");return end
 if phase=="waiting" then
  if owner:GetAttribute("Visible")==true and actor:GetAttribute("WindowWatcherVisualReady")==true then
   revealedAt=now;phase="approach";report.appearance=owner:GetAttribute("AppearanceCount");report.window=actor:GetAttribute("WindowAnchor")
  end
  return
 end
 local elapsed=now-revealedAt
 if elapsed<.7 then phase="approach"
 elseif elapsed<1 then phase="direct";player:SetAttribute("ReduceCameraShake",true)
 elseif elapsed<1.5 then phase="direct";player:SetAttribute("ReduceCameraShake",false)
 elseif elapsed<2.1 then phase="away"
 else phase="direct" end
 local hidden=actor:GetAttribute("WindowWatcherGazeHidden")==true
 if not report.lastSample or now-report.lastSample>.1 then
  report.lastSample=now
  table.insert(report.samples,{time=elapsed,phase=phase,fov=camera.FieldOfView,angle=gaze:GetAttribute("GazeAngle"),
   distance=gaze:GetAttribute("GazeDistance"),intensity=gaze:GetAttribute("GazeIntensity"),
   exposure=gaze:GetAttribute("GazeExposure"),threshold=gaze:GetAttribute("GazeThresholdSeconds"),
   hidden=hidden,los=gaze:GetAttribute("GazeLineOfSight")})
 end
 report.fovMin=math.min(report.fovMin,camera.FieldOfView);report.fovMax=math.max(report.fovMax,camera.FieldOfView)
 if elapsed>.78 and elapsed<.96 and math.abs(camera.FieldOfView-before.fov)>.001 then table.insert(report.failures,"Reduced motion still changes FOV") end
 if gaze:GetAttribute("GazeError") then table.insert(report.failures,gaze:GetAttribute("GazeError"));finish("client-error");return end
 if hidden and not vanishedAt then
  vanishedAt=now;report.vanishedAt=elapsed
  report.serverStillVisible=owner:GetAttribute("Visible")==true
  report.locallyHidden=actor.PrimaryPart.LocalTransparencyModifier==1
  report.playingOfficialTracks=#actor.AnimationController.Animator:GetPlayingAnimationTracks()
  report.guardStatus=actor:GetAttribute("WindowWatcherVisualStatus")
  if not report.serverStillVisible or not report.locallyHidden then table.insert(report.failures,"Vanish is not properly local") end
 end
 if vanishedAt and now-vanishedAt>.8 then
  if report.fovMax-report.fovMin<.1 then table.insert(report.failures,"No observable heartbeat FOV") end
  finish("local-vanish-and-fov-reset");return
 end
 if owner:GetAttribute("Visible")~=true and not vanishedAt then table.insert(report.failures,"Server encounter ended before gaze disappearance");finish("too-late");return end
end)
return {started=true,deadlineSeconds=28}
