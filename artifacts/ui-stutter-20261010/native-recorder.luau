
assert(not _G.__UIStutterRecorder20261010,"recorder exists")
local player=game:GetService("Players").LocalPlayer
local pg=player:WaitForChild("PlayerGui")
local UIS=game:GetService("UserInputService")
local device=require(game:GetService("ReplicatedStorage"):WaitForChild("UIDevice"))
local watched={ResultsWindow=true,DeathCause=true,DeathCauseDocked=true,LoadingCard=true,PartyDown=true,PartyDownCard=true,SpectateBanner=true}
local state={started=os.clock(),dt={},raw={},changed={},added={},connections={},initial={},lastInput=UIS:GetLastInputType().Name}
local function cards()
 local found={}
 for _,i in ipairs(pg:GetDescendants()) do if watched[i.Name] and i:IsA("GuiObject") then found[i.Name]=i:GetDebugId() end end
 return found
end
state.initial=cards()
table.insert(state.connections,UIS.LastInputTypeChanged:Connect(function(input)
 if #state.raw<200 then table.insert(state.raw,{t=os.clock()-state.started,input=input.Name,normalized=device.LastInput()}) end
end))
table.insert(state.connections,device.Changed:Connect(function()
 if #state.changed<200 then table.insert(state.changed,{t=os.clock()-state.started,input=UIS:GetLastInputType().Name,viewport=tostring(workspace.CurrentCamera.ViewportSize),queue=player:GetAttribute("QueueModalOpen"),ending=player:GetAttribute("RoundEndingOpen"),kit=player:GetAttribute("KitFanOpen")}) end
end))
table.insert(state.connections,pg.DescendantAdded:Connect(function(i)
 if watched[i.Name] and i:IsA("GuiObject") and #state.added<200 then table.insert(state.added,{t=os.clock()-state.started,name=i.Name,identity=i:GetDebugId()}) end
end))
table.insert(state.connections,game:GetService("RunService").RenderStepped:Connect(function(dt)
 if #state.dt<6000 then table.insert(state.dt,dt*1000) end
end))
state.finish=function()
 for _,c in ipairs(state.connections) do c:Disconnect() end
 local values=table.clone(state.dt);table.sort(values)
 local sum=0;local over50=0;for _,v in ipairs(values) do sum+=v;if v>50 then over50+=1 end end
 local n=#values
 local out={elapsed=os.clock()-state.started,raw=state.raw,changed=state.changed,added=state.added,initial=state.initial,final=cards(),frames=n,frameIntervalMS={mean=n>0 and sum/n or 0,p50=values[math.max(1,math.ceil(n*.5))],p95=values[math.max(1,math.ceil(n*.95))],max=values[n],over50=over50},gamepad=UIS.GamepadEnabled,viewport=tostring(workspace.CurrentCamera.ViewportSize),inRound=player:GetAttribute("InRound")}
 _G.__UIStutterRecorder20261010=nil
 return game:GetService("HttpService"):JSONEncode(out)
end
_G.__UIStutterRecorder20261010=state
return game:GetService("HttpService"):JSONEncode({started=true,cards=state.initial,lastInput=state.lastInput,gamepad=UIS.GamepadEnabled})
