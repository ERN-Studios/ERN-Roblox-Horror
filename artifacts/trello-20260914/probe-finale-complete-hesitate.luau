local stage0=(function()
local R=game.ReplicatedStorage.CodexMultiplayerProbe
local a,b=game.Players:WaitForChild("Player1",30),game.Players:WaitForChild("Player2",30)
assert(a and b,"test clients did not connect")
while not a.Character or not b.Character do task.wait(.25) end
local z=workspace.ServerLobby.LevelQueueRooms.Level3QueueRoom.LaunchZone9
for _,p in ipairs({a,b}) do
 R:InvokeClient(p,{op="controls",enabled=false})
 p:SetAttribute("DevFastQueue",true)
end
a.Character:PivotTo(z.CFrame*CFrame.new(-2,3,0))
task.wait(1)
b.Character:PivotTo(z.CFrame*CFrame.new(2,3,0))
R:InvokeClient(a,{op="remote",name="ConfigureQueue",args={9,2,"public"}})
local deadline=os.clock()+45
while os.clock()<deadline do
 if a:GetAttribute("InRound")==true and b:GetAttribute("InRound")==true
  and workspace:GetAttribute("RoundLoadingState")=="ready" then break end
 task.wait(.5)
end
return {a=a:GetAttributes(),b=b:GetAttributes(),world=workspace:GetAttributes()}

end)()
local stage1=(function()
local systems=game.ServerScriptService["Level 3 Systems"]
local Adapter=require(systems["Level 3 Round Adapter"])
local Objective=require(systems["Level 3 Objective Controller"])
local Music=require(systems["Level 3 Music Sequence Controller"])
local Manager=require(systems["Level 3 Mall Manager AI Controller"])
local a,b=game.Players.Player1,game.Players.Player2
local R=game.ReplicatedStorage.CodexMultiplayerProbe
local deadline=os.clock()+30
while workspace:GetAttribute("RoundActive")~=true and os.clock()<deadline do task.wait(.25) end
assert(workspace:GetAttribute("SelectedLevel")==3 and workspace:GetAttribute("RoundActive"),"no Level 3 round")
local m=assert(Adapter.GetManifest())
local function pos(v) return {v.X,v.Y,v.Z} end
for _,p in ipairs({a,b}) do
 p:SetAttribute("Escaped",false)
 R:InvokeClient(p,{op="controls",enabled=false})
end
assert(not workspace:GetAttribute("Level3FinalHallChaseTriggered"),"premature finale")
a.Character.HumanoidRootPart:SetNetworkOwner(nil)
a.Character.Humanoid:Move(Vector3.zero)
local function promptPosition(prompt)
 return prompt.Parent:IsA("Attachment") and prompt.Parent.WorldPosition or prompt.Parent.Position
end
for i,cd in ipairs(m.Modules) do
 if bit32.band(a:GetAttribute("Level3_HeldCDMask") or 0,bit32.lshift(1,i-1))==0 then
  a.Character:PivotTo(CFrame.new(promptPosition(cd.Prompt)+Vector3.new(0,0,3)))
  assert(Objective.DebugCollectCD(a,i),"could not collect CD "..i)
 end
end
assert(not workspace:GetAttribute("Level3FinalHallChaseTriggered"),"collection triggered finale before deposit")
a.Character:PivotTo(CFrame.new(promptPosition(m.DiscPlayer.Prompt)+Vector3.new(0,0,3)))
assert(Objective.DebugInsertHeldCDs(a)==5,"not all CDs deposited")
task.wait(1)
assert(not workspace:GetAttribute("Level3FinalHallChaseTriggered"),"deposit alone triggered finale")
b:SetAttribute("Escaped",true) -- second client is the observer for the run
local start=m.FinalHall.StartPoint+m.FinalHall.Forward*2+Vector3.new(0,3,0)
a.Character:PivotTo(CFrame.new(start,start+m.FinalHall.Forward))
task.wait(.3)
a.Character.HumanoidRootPart:SetNetworkOwnershipAuto()
return {entry=pos(m.MazeStart.Position),hallStart=pos(m.FinalHall.StartPoint),hallEnd=pos(m.FinalHall.EndPoint),
 forward=pos(m.FinalHall.Forward),length=m.FinalHall.Length,floor=m.FinalHall.FloorY,
 objective=Objective.GetSnapshot(),managerExists=Manager.GetSnapshot()~=nil}

end)()
local stage2=(function()
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

end)()
return {round=stage0,prepare=stage1,run=stage2}