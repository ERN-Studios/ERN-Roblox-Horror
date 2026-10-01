-- Temporary Studio Play probe. It is never installed in the Edit place.
assert(game:GetService("RunService"):IsStudio())
local folder=game:GetService("ServerScriptService"):WaitForChild("Level 6 Systems")
local Runtime=require(folder:WaitForChild("Level 6 Preview Runtime"))
local Objective=require(folder:WaitForChild("Level 6 Objective Controller"))
local Music=require(folder:WaitForChild("Level 6 Music Sequence Controller"))
local Manager=require(folder:WaitForChild("Level 6 Mall Manager AI Controller"))
local HS=game:GetService("HttpService")
local function clean(value,depth)
    if (depth or 0)>9 then return "<depth>" end
    local kind=typeof(value)
    if kind=="table" then local out={} for k,v in pairs(value) do
        out[if typeof(k)=="Instance" then k:GetFullName() else k]=clean(v,(depth or 0)+1)
        end return out
    elseif kind=="Vector3" then return {value.X,value.Y,value.Z}
    elseif kind=="Instance" then return value:GetFullName()
    elseif kind=="CFrame" then return {value:GetComponents()}
    elseif kind=="string" or kind=="number" or kind=="boolean" or value==nil then return value
    else return tostring(value) end
end
local probe=Instance.new("BindableFunction")
probe.Name="__Level6EntityDecorQA"
probe.Parent=script
probe.OnInvoke=function(command,arg)
    local m=assert(Runtime.GetManifest(),"Actual preview manifest unavailable")
    local player=game:GetService("Players"):GetPlayers()[1]
    local result
    if command=="snapshot" then
        result={Runtime=Runtime.GetSnapshot(),Objective=Objective.GetSnapshot(),
            Music=Music.GetSnapshot(),Manager=Manager.GetSnapshot(),Visual=m.VisualReport,
            FinalHall=m.FinalHall,Rooms=m.Layout.Rooms,Links=m.Layout.Links,
            CDPlayer=m.DiscPlayer.Model,EscapeTrigger=m.EscapeTrigger}
    elseif command=="collect" then
        result={Collected=Objective.DebugCollectCD(player,arg)}
    elseif command=="insert" then
        result={Inserted=Objective.DebugInsertHeldCDs(player)}
    elseif command=="elapsed" then
        Music.DebugSetElapsed(arg)
        result={Music=Music.GetSnapshot()}
    elseif command=="freeze-normal" then
        Music.DebugSetElapsed(182)
        local began=os.clock()
        while not Manager.GetSnapshot() and os.clock()-began<5 do task.wait(.05) end
        assert(Manager.GetSnapshot(),"Normal Manager did not spawn")
        Manager.DebugSetMovementPaused(true)
        result={Manager=Manager.GetSnapshot(),Music=Music.GetSnapshot()}
    elseif command=="setup-exit" then
        -- Explicit synthetic setup; collect/insert still use real server validation.
        local collected={}
        for i,module in ipairs(m.Modules) do
            player.Character:PivotTo(module.Model:GetPivot()+Vector3.new(0,3,0))
            table.insert(collected,Objective.DebugCollectCD(player,i))
        end
        local prompt=m.DiscPlayer.Prompt
        local target=if prompt and prompt.Parent:IsA("BasePart") then prompt.Parent.CFrame else m.DiscPlayer.Model:GetPivot()
        player.Character:PivotTo(target+Vector3.new(0,3,0))
        local inserted=Objective.DebugInsertHeldCDs(player)
        result={Collected=collected,Inserted=inserted,Objective=Objective.GetSnapshot()}
    elseif command=="pause" then
        result=Manager.DebugSetMovementPaused(arg)
    elseif command=="manager-stop" then
        workspace:SetAttribute("Level6MallManagerHuntActive",false)
        result={Stopped=Manager.GetSnapshot()==nil}
    elseif command=="manager" then result=Manager.GetSnapshot()
    elseif command=="threshold" then result=Objective.DebugEvaluateFinalHallChase()
    else error("Unknown QA command") end
    return HS:JSONEncode(clean(result))
end
script:SetAttribute("ProbeReady",true)
