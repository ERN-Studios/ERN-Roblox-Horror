local a,b=game.Players.Player1,game.Players.Player2
local R=game.ReplicatedStorage.CodexMultiplayerProbe
workspace:SetAttribute("EntityPaused",true)
local untilTime=os.clock()+25
while workspace:GetAttribute("RoundActive")~=true and os.clock()<untilTime do task.wait(.25) end
assert(workspace:GetAttribute("RoundActive")==true,"round did not start")
b:SetAttribute("Escaped",true)
task.wait(2)
local watched=R:InvokeClient(a,{op="snapshot",filter="SpectatorCounter"})
local observer=R:InvokeClient(b,{op="snapshot",filter="Spectate"})
return {count=a:GetAttribute("SpectatorCount"),watched=watched,observer=observer}
