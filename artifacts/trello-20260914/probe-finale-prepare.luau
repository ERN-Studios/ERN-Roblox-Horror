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
