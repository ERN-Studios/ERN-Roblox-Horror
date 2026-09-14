local S=game.ServerScriptService["Level 3 Systems"]
local A=require(S["Level 3 Round Adapter"])
local M=require(S["Level 3 Mall Manager AI Controller"])
local R=game.ReplicatedStorage.CodexMultiplayerProbe
local a,b=game.Players.Player1,game.Players.Player2
local hall=A.GetManifest().FinalHall
local destination=A.GetManifest().EscapeTrigger.Position+hall.Forward*3
a.Character.Humanoid.WalkSpeed=26
local t=os.clock()
local samples={}
local audio
local paused=false
local function pos(v) return v and {v.X,v.Y,v.Z} end
local lastMove=-math.huge
while os.clock()-t<38 do
 local elapsed=os.clock()-t
 if elapsed>=10 and not audio then audio=R:InvokeClient(b,{op="snapshot",filter="spectat"}) end
 if elapsed>=11 and elapsed<15 then
  if not paused then
   paused=true
   local at=a.Character.HumanoidRootPart.Position
   R:InvokeClient(a,{op="walk",position=pos(at)})
  end
 elseif elapsed-lastMove>1 then
  lastMove=elapsed
  R:InvokeClient(a,{op="walk",position=pos(destination)})
 end
 local snap=M.GetSnapshot()
 table.insert(samples,{time=os.clock()-t,runner=pos(a.Character.HumanoidRootPart.Position),entity=pos(snap and snap.Position),
  speed=snap and snap.Speed,health=a.Character.Humanoid.Health,escaped=a:GetAttribute("Escaped")})
 if a:GetAttribute("Escaped")==true or a.Character.Humanoid.Health<=0 then break end
 task.wait(.5)
end
return {samples=samples,audio=audio,paused=paused,elapsed=os.clock()-t,escaped=a:GetAttribute("Escaped")}
