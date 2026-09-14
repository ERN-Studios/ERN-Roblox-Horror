local R=game.ReplicatedStorage.CodexMultiplayerProbe
local b=game.Players.Player2
R:InvokeClient(b,{op="remote",name="RoundStatus",args={"leaveround"}})
task.wait(2)
local count=game.Players.Player1:GetAttribute("SpectatorCount")
assert(not count or count==0,"departed spectator count remains")
assert(b:GetAttribute("InRound")~=true,"spectator did not return to lobby")
local a=game.Players.Player1
R:InvokeClient(a,{op="remote",name="RoundStatus",args={"leaveround"}})
task.wait(3)
assert(a:GetAttribute("InRound")~=true,"living player did not return to lobby")
return {spectatorLeft=true,aliveLeft=true,countCleared=true,roundActive=workspace:GetAttribute("RoundActive")}
