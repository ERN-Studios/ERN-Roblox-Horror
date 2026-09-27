-- Read-only native snapshot. No generation, input, property writes, camera moves,
-- or Instances are created. Rays establish sampled visibility, not reachability.
local HttpService=game:GetService("HttpService")
local world=workspace:FindFirstChild("Level 5 Generated World")
assert(world,"Start the existing Level 5 round before inspecting its clues")
local owner=assert(world:FindFirstChild("Level5SectionProgression"),"Progression is not running")
local V=Vector3.new
local function xyz(v) return {v.X,v.Y,v.Z} end
local function fullname(o) return o and o:GetFullName() or nil end
local report={scope="Bounded read-only clue visibility and gate snapshot",clues={},gates={},limitations={
    "A clear sampled ray is not an actual player walk or a first-person rendering test.",
    "TextFits is renderer evidence only when inspected in an active native client.",
    "Seven normal wrong/correct submissions and shared multiplayer opens must be exercised separately."}}
local params=RaycastParams.new()
params.FilterType=Enum.RaycastFilterType.Include
params.FilterDescendantsInstances={world}
params.RespectCanCollide=true
local function inspect(board,gui,home,gate,slot)
    local face=board.CFrame.LookVector
    local front=board.Position+face*(board.Size.Z/2+.01)
    local eye=front+face*6-V(0,1,0)
    local hit=workspace:Raycast(eye,front-eye,params)
    local ground=workspace:Raycast(eye+V(0,2,0),V(0,-12,0),params)
    local labels={}
    for _,label in ipairs(gui:GetDescendants()) do
        if label:IsA("TextLabel") and label.Text~="" then
            table.insert(labels,{text=label.Text,textFits=label.TextFits,size=xyz(V(label.AbsoluteSize.X,label.AbsoluteSize.Y,0)),
                bounds=xyz(V(label.TextBounds.X,label.TextBounds.Y,0)),position={label.AbsolutePosition.X,label.AbsolutePosition.Y}})
        end
    end
    table.sort(labels,function(a,b) if a.position[2]~=b.position[2] then return a.position[2]<b.position[2] end;return a.position[1]<b.position[1] end)
    table.insert(report.clues,{gate=gate,slot=slot,home=fullname(home),board=fullname(board),position=xyz(board.Position),
        frontNormal=xyz(face),face=tostring(gui.Face),size=xyz(board.Size),alwaysOnTop=gui.AlwaysOnTop,
        lightInfluence=gui.LightInfluence,brightness=gui.Brightness,maxDistance=gui.MaxDistance,
        sampleEye=xyz(eye),obstruction=fullname(hit and hit.Instance),support=fullname(ground and ground.Instance),
        labels=labels})
end
for _,object in ipairs(world:GetDescendants()) do
    if object:IsA("SurfaceGui") and (object.Name=="PuzzleClueGui" or object.Name=="Level5ColourClue") then
        local board=object.Parent
        if board and board:IsA("BasePart") then
            if object.Name=="Level5ColourClue" then
                inspect(board,object,board.Parent,1,board:GetAttribute("ClueIndex"))
            else
                local model=board.Parent
                local reference=model:FindFirstChild("SourceHome")
                inspect(board,object,reference and reference.Value,model:GetAttribute("PuzzleGateIndex"),model:GetAttribute("PuzzleClueSlot"))
            end
        end
    end
end
for index=1,7 do
    local gate=owner:FindFirstChild("SectionGate"..index)
    local lock=gate and gate:FindFirstChild("ColourPadlock")
    local prompt=lock and lock:FindFirstChild("ColourLockPrompt")
    table.insert(report.gates,{gate=index,exists=gate~=nil,lockPosition=lock and xyz(lock.Position),
        unlocked=gate and gate:GetAttribute("Unlocked"),fullyOpen=gate and gate:GetAttribute("FullyOpen"),
        solved=owner:GetAttribute("Puzzle"..index.."Solved"),mode=gate and gate:GetAttribute("PuzzleMode"),
        prompt=prompt and {enabled=prompt.Enabled,maxDistance=prompt.MaxActivationDistance,requiresLineOfSight=prompt.RequiresLineOfSight}})
end
return HttpService:JSONEncode(report)
