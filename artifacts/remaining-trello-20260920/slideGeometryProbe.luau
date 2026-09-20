local f=game.ServerScriptService["Level 3 Systems"]
local layout=require(f["Level 3 Layout Generator"]).Generate(90920)
local manifest=require(f["Level 3 World Builder"]).Build(layout,90920)
local world=manifest.World;world.Parent=workspace
local tube=world:FindFirstChild("Level 2 Exit Slide Continuation",true)
local safe=require(game.ReplicatedStorage.SlideContinuationSafety)
local mouth=tube:GetAttribute("Level3_SlideMouthPosition")
local length=tube:GetAttribute("Level3_SlideLength") local rise=tube:GetAttribute("Level3_SlideRise")
local resume=mouth+Vector3.new(-length*.8,rise*.8*.8,0)
local ready=safe.Ready(tube,resume)
local corrected,_,inside=safe.Resolve(tube,resume-Vector3.new(0,20,0),true)
local _,_,released=safe.Resolve(tube,mouth,false)
local shell=tube:FindFirstChild("Level 2 Exit Slide Fiberglass Shell")
local runout=tube:FindFirstChild("Level 2 Exit Slide Runout")
local old=shell.CanCollide shell.CanCollide=false local partial=safe.Ready(tube,resume) shell.CanCollide=old
local result={ready=ready,partialRejected=not partial,rescued=corrected~=nil and inside,mouthReleased=not released,shellThickness=shell.Size.Y,runoutThickness=runout.Size.Y,expectedParts=tube:GetAttribute("Level3_SlideCollisionPartCount"),atomic=tostring(tube.ModelStreamingMode),worldParts=#world:GetDescendants()}
assert(ready and not partial and corrected and inside and not released,"slide safety regression")
return game.HttpService:JSONEncode(result)
