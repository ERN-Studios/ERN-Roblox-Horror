local R=game.ReplicatedStorage.CodexMultiplayerProbe
local a,b=game.Players.Player1,game.Players.Player2
local connection=game:GetService("RunService").Heartbeat:Connect(function()
 a:SetAttribute("SpectateStamina",.37)
 a:SetAttribute("SpectateBattery",.4)
 a:SetAttribute("PlayerProtectionActive",true)
 a:SetAttribute("PlayerProtectionExpiresAt",workspace:GetServerTimeNow()+3)
end)
task.wait(.7)
local result=R:InvokeClient(b,{op="snapshot",filter="Protection"})
connection:Disconnect()
a:SetAttribute("PlayerProtectionActive",false)
a:SetAttribute("PlayerProtectionExpiresAt",0)
return {stamina=result.stamina,battery=result.battery,guis=result.guis,target=result.attributes.SpectateTargetUserId}
