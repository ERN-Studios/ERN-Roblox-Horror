local H=game:GetService("HttpService")
local AS=game:GetService("AssetService")
local storage=game:GetService("ServerStorage")
local container=assert(storage:FindFirstChild("Level5WindowWatcher"),"Import model first")
local rig=assert(container:FindFirstChild("WindowWatcherRig"),"Prepared rig missing")
local old=H.HttpEnabled
H.HttpEnabled=true
local ok,result=xpcall(function()
 local manifest=H:JSONDecode(H:GetAsync("http://127.0.0.1:8769/mesh-import/manifest.json"))
 local parents={}
 for _,bone in ipairs(manifest.bones) do
  local native=rig:FindFirstChild(bone.name,true)
  assert(native and native:IsA("Bone"),"Missing bone "..bone.name)
  parents[bone.name]=bone.parent
 end
 local folder=container:FindFirstChild("Animations")
 if not folder then folder=Instance.new("Folder");folder.Name="Animations";folder.Parent=container end
 local results={}
 local saved=container:FindFirstChild("AuthoredClips")
 if not saved then saved=Instance.new("Folder");saved.Name="AuthoredClips";saved.Parent=container end
 for _,clip in ipairs(manifest.clips) do
  if _G.WWPublishClipName and clip.name~=_G.WWPublishClipName then continue end
  local existing=folder:FindFirstChild(clip.name)
  if existing and existing:IsA("Animation") and existing:GetAttribute("WindowWatcherSourceSha256")==manifest.sourceGlbSha256 then
   table.insert(results,{name=clip.name,id=existing.AnimationId,reused=true})
  else
   assert(not existing,"Conflicting animation preserved: "..clip.name)
   local data=H:JSONDecode(H:GetAsync("http://127.0.0.1:8769/mesh-import/"..clip.path))
   local sequence=Instance.new("KeyframeSequence")
   sequence.Name="Level5_WindowWatcher_"..data.name.."_20260925"
   -- All 25 first/last bone transforms match; loop the complete gestures so
   -- each 8–14 second appearance stays animated without returning to bind pose.
   sequence.Loop=true;sequence.Priority=Enum.AnimationPriority.Idle
   for _,frame in ipairs(data.frames) do
    local key=Instance.new("Keyframe");key.Time=frame.time
    local poses={}
    for _,v in ipairs(frame.poses) do
     local pose=Instance.new("Pose");pose.Name=v[1]
     pose.CFrame=CFrame.new(table.unpack(v,2,8));pose.Weight=1
     pose.EasingStyle=Enum.PoseEasingStyle.Linear;pose.EasingDirection=Enum.PoseEasingDirection.InOut
     poses[pose.Name]=pose
    end
    for name,pose in pairs(poses) do pose.Parent=parents[name] and assert(poses[parents[name]]) or key end
    key.Parent=sequence
   end
   _G.WWPublishStatus={clip=clip.name,stage="upload",started=os.clock(),sequence=sequence}
   sequence.Parent=saved -- Preserve the authored clip and match the existing successful publisher.
   local called,status,id=pcall(function()
    return AS:CreateAssetAsync(sequence,Enum.AssetType.Animation,{
     Name="Level 5 Window Watcher "..data.name,
     Description="Window Watcher Blender-authored window pose for BACKROOMS STAY QUIET",
     CreatorId=1039373905,CreatorType=Enum.AssetCreatorType.Group,
    })
   end)
   -- Retain local KeyframeSequence for Animation Editor recovery and native backup.
   _G.WWPublishStatus.stage=called and tostring(status) or "call-error"
   _G.WWPublishStatus.result=tostring(id or status)
   assert(called,"Animation publish call failed: "..tostring(status))
   assert(status==Enum.CreateAssetResult.Success,"Animation publish failed: "..tostring(status).." / "..tostring(id))
   local animation=Instance.new("Animation");animation.Name=data.name;animation.AnimationId="rbxassetid://"..tostring(id)
   animation:SetAttribute("WindowWatcherSourceSha256",manifest.sourceGlbSha256)
   animation:SetAttribute("AuthoredDuration",data.duration)
   animation.Parent=folder
   sequence:SetAttribute("PublishedAssetId",tostring(id))
   table.insert(results,{name=data.name,id=animation.AnimationId,duration=data.duration,frames=#data.frames})
  end
 end
 H:PostAsync("http://127.0.0.1:8769/qa/integration-animation-assets.json",H:JSONEncode(results),Enum.HttpContentType.ApplicationJson)
 return results
end,debug.traceback)
H.HttpEnabled=old
if not ok then error(result) end
return result
