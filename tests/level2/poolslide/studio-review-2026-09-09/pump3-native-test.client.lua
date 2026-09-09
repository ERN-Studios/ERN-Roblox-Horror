-- TEMPORARY normal Play queue companion; NEVER publish. No entry/streaming handshake changes.
local RunService=game:GetService("RunService")
if not RunService:IsStudio() or game.PlaceId~=131311258779917 or game.GameId~=10559217407 then return end
if script.Name~="TEMP_Pump3NativeClient" then return end
local token=script:GetAttribute("TestToken"); if type(token)~="string" or #token<16 then return end
local RS=game:GetService("ReplicatedStorage"); local remote=RS:WaitForChild("TEMP_Pump3NativeRemote",30)
if not remote or remote:GetAttribute("TestToken")~=token then return end
local remotes=RS:WaitForChild("Remotes",30); if not remotes then return end
local status=remotes:WaitForChild("RoundStatus",10); local configure=remotes:WaitForChild("ConfigureQueue",10)
if not status or not configure then return end
local stopped=false; local connections={}
local function stop() if stopped then return end; stopped=true; for _,c in ipairs(connections) do c:Disconnect() end end
table.insert(connections,status.OnClientEvent:Connect(function(message,index)
 if stopped or message~="queuehost" or tonumber(index)~=remote:GetAttribute("QueueStation") then return end
 configure:FireServer(index,1,"public"); remote:FireServer(token,"configured",index)
end))
table.insert(connections,remote.OnClientEvent:Connect(function(inToken,command) if inToken==token and command=="stop" then stop() end end))
table.insert(connections,remote.Destroying:Connect(stop)); table.insert(connections,script.Destroying:Connect(stop))
remote:FireServer(token,"ready")
task.delay(250,stop)
