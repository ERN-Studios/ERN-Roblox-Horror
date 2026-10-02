assert(R:IsServer(),"Run this inspector in Server Play context")
local E=game:GetService("EncodingService")
local raw=assert(game:GetService("ServerStorage"):FindFirstChild("LobbyReimaginedBlenderSource20261001R4"))
assert(raw:GetAttribute("Ready")==true and raw:GetAttribute("ManifestSHA256")==EXPECT.rawManifestSHA256,"Raw kit manifest changed")
local pieces=assert(raw:FindFirstChild("ManifestJSON")):GetChildren();table.sort(pieces,function(a,b)return a.Name<b.Name end)
local encoded={};for i,p in ipairs(pieces) do assert(p:IsA("StringValue") and p.Name==string.format("%05d",i-1));encoded[i]=p.Value end
local bytes=E:DecompressBuffer(E:Base64Decode(buffer.fromstring(table.concat(encoded))),Enum.CompressionAlgorithm.Zstd)
local digest=E:ComputeBufferHash(bytes,Enum.HashAlgorithm.Sha256);local hex={}
for i=0,buffer.len(digest)-1 do hex[i+1]=string.format("%02x",buffer.readu8(digest,i)) end
assert(table.concat(hex)==EXPECT.rawManifestSHA256,"Raw kit bytes differ")
local manifest=H:JSONDecode(buffer.tostring(bytes))
local candidates={};local extras={}
for _,x in ipairs(model:GetDescendants()) do if x:IsA("BasePart") and x.CanCollide then
 if x:GetAttribute("FurnitureEndBlocker")==true then table.insert(extras,x)
 elseif x:IsDescendantOf(model.PreviewCollisions) or x:IsDescendantOf(pads) then table.insert(candidates,x) end
end end
local used={};local colliderMissing={}
for i,item in ipairs(manifest.colliders) do
 local name=item.name=="Bay Floor" and "ChamberFloor" or item.name
 local size=v(item.size);local cf=CFrame.new(center+v(item.position))*CFrame.Angles(0,item.yaw or 0,0)
 if item.rotation then cf=CFrame.new(center+v(item.position))*CFrame.Angles(table.unpack(item.rotation)) end
 if item.shape=="Cylinder" then size=Vector3.new(item.size[2],item.size[1],item.size[3]);cf*=CFrame.Angles(0,0,math.pi/2) end
 local found
 for _,x in ipairs(candidates) do if not used[x] and x.Name==name and close(x.Size,size) and cfclose(x.CFrame,cf)
  and x.Anchored and x.CanQuery and not x.CanTouch then found=x;break end end
 if found then used[found]=true else table.insert(colliderMissing,{index=i,name=name,position=item.position}) end
end
local unmatched={};for _,x in ipairs(candidates) do if not used[x] then table.insert(unmatched,x:GetFullName()) end end
ck("830-original-colliders-exact",#manifest.colliders==830 and #colliderMissing==0 and #unmatched==0,
 {manifest=#manifest.colliders,actual=#candidates,missing=colliderMissing,unmatched=unmatched})
local extraRows={};local matchedExtras={}
for _,item in ipairs(EXPECT.clutterColliders) do
 local found
 for _,x in ipairs(extras) do if x.Name==item.name and close(x.Size,v(item.size)) and close(x.Position,center+v(item.position))
  and x.Anchored and x.CanQuery and not x.CanTouch then found=x;break end end
 ck("end-blocker-"..item.name,found~=nil);if found then matchedExtras[found]=true end
end
ck("66-bounded-end-blockers",#extras==66 and #EXPECT.clutterColliders==66,#extras)
local pile=assert(model.BlenderVisuals:FindFirstChild("Reference End Furniture Piles"))
ck("219-existing-family-pile-clones",#pile:GetChildren()==219 and pile:GetAttribute("AddedFurnitureInstances")==219,#pile:GetChildren())
local stages={};for _,p in ipairs(model.PreviewCollisions:GetChildren()) do if p.Name=="Stage Step" then table.insert(stages,p) end end
table.sort(stages,function(a,b)return a.Position.Y+a.Size.Y/2<b.Position.Y+b.Size.Y/2 end)
local stageRows={}
for i,p in ipairs(stages) do
 local top=p.Position.Y+p.Size.Y/2;local carpet=scene:FindFirstChild("Stage Carpet Tread "..i)
 local nosing=scene:FindFirstChild("Stage Step Nosing "..i)
 local gap=carpet and carpet.Position.Y-carpet.Size.Y/2-top
 ck("stage-tread-supported-"..i,carpet and nosing and near(gap,.001)
  and near(nosing.Position.Y-nosing.Size.Y/2-top,.001),{carpetGap=gap})
 local hit=workspace:Raycast(carpet.Position+Vector3.new(0,1,0),Vector3.new(0,-3,0),routeParams)
 ck("stage-tread-floor-ray-"..i,hit and hit.Instance==p,hit and hit.Instance:GetFullName())
 table.insert(stageRows,{index=i,collider=p:GetFullName(),topLocal=top-center.Y,clothGap=gap})
end
ck("six-stage-steps",#stages==6,#stages)
report.colliders={originalCount=#candidates,extraEndBlockers=#extras,stage=stageRows,rawManifestSHA256=EXPECT.rawManifestSHA256}
report.coverage.activeQueueVisuals="Run Client inspector during an actual active queue; server properties do not show client tweens"
report.coverage.perViewerGates="Client-only ownership; inspect per connected viewer"
report.propertyChecksPassed=#report.failures==0
report.playVisualsVerified=false;report.gameplayVerified=false;report.performanceVerified=false
return report
