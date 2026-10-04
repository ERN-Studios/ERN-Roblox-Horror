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
