local S=game.ServerScriptService["Level 3 Systems"]
local A=require(S["Level 3 Round Adapter"])
local M=require(S["Level 3 Mall Manager AI Controller"])
local R=game.ReplicatedStorage.CodexMultiplayerProbe
local a=game.Players.Player1
local hall=A.GetManifest().FinalHall
local destination=A.GetManifest().EscapeTrigger.Position+hall.Forward*3
a.Character.Humanoid.WalkSpeed=26
R:InvokeClient(a,{op="walk",position={destination.X,destination.Y,destination.Z}})
local t=os.clock()
local samples={}
local spawn=nil
local function pos(v) return v and {v.X,v.Y,v.Z} end
local lastMove=-math.huge
while os.clock()-t<35 do
 if os.clock()-lastMove>3 then
  lastMove=os.clock()
  R:InvokeClient(a,{op="walk",position={destination.X,destination.Y,destination.Z}})
 end
 local root=a.Character and a.Character:FindFirstChild("HumanoidRootPart")
 local snap=M.GetSnapshot()
 if snap and not spawn then spawn=pos(snap.Position) end
 table.insert(samples,{time=os.clock()-t,runner=pos(root and root.Position),entity=pos(snap and snap.Position),
  speed=snap and snap.Speed,movementSpeed=snap and snap.MovementSpeed,state=snap and snap.State,
  finalHall=snap and snap.FinalHallChase,health=a.Character.Humanoid.Health,
  escaped=a:GetAttribute("Escaped")})
 if a:GetAttribute("Escaped")==true or a.Character.Humanoid.Health<=0 then break end
 task.wait(.5)
end
return {spawn=spawn,samples=samples,elapsed=os.clock()-t,escaped=a:GetAttribute("Escaped")}
