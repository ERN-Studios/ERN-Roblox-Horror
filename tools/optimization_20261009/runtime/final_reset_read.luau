-- Read-only post-acknowledgement observation; world parking is asynchronous.
assert(game:GetService("RunService"):IsRunning())
local deadline=os.clock()+5
repeat
 if workspace:FindFirstChild("Level 6 Indoor Playground")==nil and workspace:GetAttribute("Level6InUse")==false then break end
 task.wait(.1)
until os.clock()>deadline
assert(workspace:FindFirstChild("Level 6 Indoor Playground")==nil)
assert(game.ServerStorage:FindFirstChild("Level 6 Indoor Playground")~=nil)
assert(workspace:GetAttribute("Level6InUse")==false)
local out={}
for _,p in ipairs(game.Players:GetPlayers()) do
 assert(p:GetAttribute("InRound")==false and p.Character.Humanoid.Health>0 and p.Character.HumanoidRootPart.Position.X<1000)
 table.insert(out,{name=p.Name,inRound=false,health=p.Character.Humanoid.Health,
  position={p.Character.HumanoidRootPart.Position.X,p.Character.HumanoidRootPart.Position.Y,p.Character.HumanoidRootPart.Position.Z}})
end
return game.HttpService:JSONEncode({complete=true,kind="actual-final-normal-reset",players=out,
 level6InUse=false,mapParkedInServerStorage=true,immediateParkingNotAssumed=true})
