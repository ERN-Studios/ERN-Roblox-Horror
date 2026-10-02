assert(R:IsClient(),"Run this inspector in Client Play context")
local player=assert(game:GetService("Players").LocalPlayer)
local gates=model:FindFirstChild("R4ClientDevGates")
ck("client-gates-owned",gates and gates:GetAttribute("R4DevGateControllerOwned")==true)
local gateRows={}
for _,level in ipairs({5,6}) do
 local gate=gates and gates:FindFirstChild("Level"..level.." Client Gate")
 local allowed=gate and gate:GetAttribute("PreviewAllowed")
 local status=gate and gate:FindFirstChild("Mounted Access Subtitle")
 local shutter=gate and gate:FindFirstChild("Coming Soon Shutter")
 local header=signs:FindFirstChild("LEVEL "..level.." Door Header")
 local _,hhigh=ybounds(header,header.CFrame);local statusLow=status and ybounds(status,header.CFrame)
 ck("gate-status-"..level,gate and type(allowed)=="boolean" and status
  and label(status).Text==(allowed and "DEV PREVIEW" or "COMING SOON") and (shutter~=nil)==not allowed
  and (not shutter or shutter.CanCollide),{allowed=allowed,text=status and label(status).Text})
 ck("gate-status-header-separated-"..level,statusLow and statusLow-hhigh>.1,statusLow and statusLow-hhigh)
 for _,row in ipairs(qrows) do if row.level==level then
  ck("viewer-queue-label-"..row.id,allowed or (row.titleVisible==false and row.subtitleVisible==false))
 end end
 table.insert(gateRows,{level=level,allowed=allowed,status=status and label(status).Text,shutter=shutter~=nil})
end
report.viewer={name=player.Name,userId=player.UserId,reduceFlashing=player:GetAttribute("ReduceFlashing"),gates=gateRows}
-- Allow existing renderer tweens to settle. No state is changed to create coverage.
task.wait(1.15)
local active,idle=0,0;local animationRows={}
for index,station in ipairs(stations) do
 local isActive=station:GetAttribute("QueueActive")==true;local ring=station:FindFirstChild("Active Queue Ring")
 local expectedAlpha=isActive and .18 or .52;local expectedColor=isActive and Color3.fromRGB(123,231,197) or Color3.fromRGB(224,209,154)
 ck("observed-ring-"..index,ring and near(ring.Transparency,expectedAlpha) and close(ring.Color,expectedColor),
  {active=isActive,transparency=ring and ring.Transparency})
 local bandRows={};local previous=-math.huge;local faded=true
 for band=1,10 do
  local wall=station:FindFirstChild(string.format("HologramBand%02d",band));assert(wall,"Band absent")
  local full=wall:GetAttribute("HologramFullSize");local target=wall:GetAttribute("HologramFullCFrame")
  local alpha=.74+.26*((band-1)/9)^.85
  if isActive then
   if not near(wall.Transparency,alpha) or not close(wall.Size,full) or not cfclose(wall.CFrame,target) then faded=false end
   if wall.Transparency<previous then faded=false end
  else
   if not near(wall.Transparency,1) or not near(wall.Size.Y,.015)
    or not cfclose(wall.CFrame,station:GetAttribute("HologramBase")*CFrame.new(0,.008,0)) then faded=false end
  end
  previous=wall.Transparency;table.insert(bandRows,{index=band,transparency=wall.Transparency,height=wall.Size.Y})
 end
 ck((isActive and "active-upward-fade-" or "idle-collapsed-bands-")..index,faded,bandRows)
 if isActive then active+=1 else idle+=1 end
 table.insert(animationRows,{station=station:GetFullName(),active=isActive,bands=bandRows})
end
report.holograms={active=active,idle=idle,rows=animationRows,activeVisualCoverage=active>0,idleVisualCoverage=idle>0}
if active==0 then table.insert(report.coverage,"Active hologram fade was not observed; rerun during a real queue") end
local discs,needles={},{},{}
for _,p in ipairs(model:GetDescendants()) do if p:IsA("MeshPart") then
 if p:GetAttribute("PreviewVinylDisc")==true then table.insert(discs,{object=p,before=p.CFrame,pivot=p:GetAttribute("RecordPivot"),offset=p:GetAttribute("RecordMeshOffset")}) end
 if p:GetAttribute("BlenderSourceSHA256")==EXPECT.djConsoleSHA256 then table.insert(needles,{object=p,before=p.CFrame}) end
end end
ck("two-records-and-static-console",#discs==2 and #needles==1,{records=#discs,console=#needles})
local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
local inRange=root and (root.Position-center).Magnitude<=220
local enabled=player:GetAttribute("ReduceFlashing")==false and inRange
local t0=os.clock();task.wait(3.05);local elapsed=os.clock()-t0
local sameEligibility=player:GetAttribute("ReduceFlashing")==false and root and root.Parent
 and (root.Position-center).Magnitude<=220
local vinylRows={}
for _,row in ipairs(discs) do
 local p=row.object;local diff=row.before:Inverse()*p.CFrame;local _,angle=diff:ToAxisAngle()
 local beforePivot=row.before*row.offset:Inverse();local afterPivot=p.CFrame*row.offset:Inverse()
 local centerDrift=(afterPivot.Position-beforePivot.Position).Magnitude
 local degrees=math.deg(math.abs(angle));local expected=elapsed*12
 ck("vinyl-center-stable-"..p.Name,centerDrift<.004,centerDrift)
 if enabled and sameEligibility then ck("vinyl-12-degrees-per-second-"..p.Name,math.abs(degrees-expected)<1.8,{degrees=degrees,expected=expected,elapsed=elapsed})
 elseif not enabled then ck("vinyl-reduced-or-distant-stable-"..p.Name,degrees<.01,{degrees=degrees}) end
 table.insert(vinylRows,{name=p.Name,degrees=degrees,elapsed=elapsed,centerDrift=centerDrift,animationEligible=enabled and sameEligibility})
end
for _,row in ipairs(needles) do ck("integral-tonearms-fixed-"..row.object.Name,cfclose(row.before,row.object.CFrame,.00001)) end
report.vinyl={rows=vinylRows,animationEligibility=enabled==true,scope="Two separate discs; known DJConsole mesh containing tonearms/needles observed fixed for the same interval"}
if not enabled then table.insert(report.coverage,"Vinyl motion not covered: existing ReduceFlashing setting or avatar distance disables animation") end
report.propertyChecksPassed=#report.failures==0
report.playVisualsVerified=false;report.gameplayVerified=false;report.performanceVerified=false
return report
