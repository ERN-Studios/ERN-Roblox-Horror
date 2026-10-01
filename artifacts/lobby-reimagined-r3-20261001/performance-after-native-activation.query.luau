local HS=game:GetService("HttpService") local stats=game:GetService("Stats") local RS=game:GetService("RunService") local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local function snapshot()
 local p=Players.LocalPlayer or Players:GetPlayers()[1] local root=p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
 local model=workspace:FindFirstChild("LobbyReimaginedPreview")
 local focusedTextBox=UIS:GetFocusedTextBox()
 return {focusedTextBox=focusedTextBox and focusedTextBox:GetFullName(),players=#Players:GetPlayers(),rootPosition=root and {root.Position.X,root.Position.Y,root.Position.Z},
  inRound=p and p:GetAttribute("InRound"),level6InRound=p and p:GetAttribute("Level6InRound"),roundActive=workspace:GetAttribute("RoundActive"),
  previewPresent=model~=nil,previewReady=model and model:GetAttribute("Ready"),registeredQueues=model and model:GetAttribute("RegisteredQueueCount"),
  previewBlend=model and model:GetAttribute("BlenderSourceSHA256")}
end
local before=snapshot() local began=os.clock() local samples={} local fields={"FrameTime","HeartbeatTime","PhysicsStepTime","RenderCPUFrameTime","RenderGPUFrameTime","SceneTriangleCount","SceneDrawcallCount","InstanceCount","PrimitivesCount"}
for frame=1,120 do
 local dt=RS.Heartbeat:Wait();local row={frame=frame,heartbeatDeltaSeconds=dt}
 for _,key in ipairs(fields) do local ok,v=pcall(function() return stats[key] end);if ok then row[key]=v end end
 if frame==1 or frame%20==0 then local ok,m=pcall(function() return stats:GetTotalMemoryUsageMb() end);if ok then row.totalMemoryMb=m end end
 samples[#samples+1]=row
 if os.clock()-began>12 then break end
end
local function summary(key)
 local a={} local total=0
 for _,row in ipairs(samples) do if type(row[key])=="number" then a[#a+1]=row[key];total+=row[key] end end
 if #a==0 then return {available=false} end
 table.sort(a) return {available=true,count=#a,min=a[1],max=a[#a],mean=total/#a,p50=a[math.max(1,math.ceil(#a*.5))],p95=a[math.max(1,math.ceil(#a*.95))]}
end
local summaries={};for _,key in ipairs(fields) do summaries[key]=summary(key) end summaries.heartbeatDeltaSeconds=summary("heartbeatDeltaSeconds");summaries.totalMemoryMb=summary("totalMemoryMb")
local memory={};if stats.MemoryTrackingEnabled then
 for _,tag in ipairs(Enum.DeveloperMemoryTag:GetEnumItems()) do if tag.Name=="Instances" or tag.Name=="PhysicsParts" or tag.Name=="PhysicsCollision" or tag.Name=="GraphicsMeshParts" or tag.Name=="GraphicsTexture" or tag.Name=="LuaHeap" then local ok,v=pcall(function() return stats:GetMemoryUsageMbForTag(tag) end);if ok then memory[tag.Name]=v end end end
end
return HS:JSONEncode({schema="r3-bounded-single-studio-performance-v1",mode=RS:IsClient() and "Client" or "Server",placeId=game.PlaceId,universeId=game.GameId,
 durationSeconds=os.clock()-began,samples=#samples,before=before,after=snapshot(),summaries=summaries,rawSamples=samples,memoryTagMb=memory,memoryTrackingEnabled=stats.MemoryTrackingEnabled,
 limitations={"Single Studio server/client on this Mac; root owns concurrent walking/entry tests.","No player, camera, UI, model, source or settings were modified by this sampler.","OS memory is whole Studio/session, not incremental R3 map memory.","FrameTime only meaningful on Client; Server rendering zeros are not FPS.","No mobile, multiplayer, isolated baseline, production teleport or full load benchmark."}})
