
local R=game:GetService("RunService") local world=workspace["Level 6 Generated World"]
local fills={} for _,d in world:GetDescendants() do if d:IsA("PointLight") and d:GetAttribute("Level6_CeilingBounce") then fills[#fills+1]=d end end
local function sample()
 local frames={} for _=1,120 do frames[#frames+1]=R.RenderStepped:Wait() end
 local sum=0 for _,dt in frames do sum+=dt end table.sort(frames)
 return {frames=#frames,seconds=sum,fps=#frames/sum,meanFrameMs=sum*1000/#frames,p95FrameMs=frames[math.ceil(#frames*.95)]*1000}
end
for _,d in fills do d.Range=0 end local without=sample()
for _,d in fills do d.Range=28 end local with=sample()
return game:GetService("HttpService"):JSONEncode({method="Same stationary active Studio Play viewport; new-fill Range0 versus normal28; two bounded120-frame samples, not multiplayer/mobile benchmark",fillCount=#fills,withoutFill=without,withFill=with,health=game.Players.LocalPlayer.Character.Humanoid.Health})
