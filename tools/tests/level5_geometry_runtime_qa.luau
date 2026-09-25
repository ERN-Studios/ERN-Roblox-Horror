-- Usage and limitations: docs/LEVEL5_QA_2026-09-25.md.
-- Read-only server inspection for an ALREADY BUILT Level 5 preview.
-- Does not start/stop Play, build, move a character, alter instances or attributes.
-- Potential foreign-lane collisions and waypoint anomalies require review;
-- they are not a substitute for character traversal.
local world = workspace:FindFirstChild("Level 5 Generated World")
assert(world, "Build/enter Level 5 before running this read-only inspection")
local root = world:FindFirstChild("Level5_IndoorSuburbs")
assert(root, "Missing Level5_IndoorSuburbs")
local result = {houses = {inspected=0,rays=0,foreignHits=0,embeddedSamples=0,candidates={}},
    chute={samples=0,rays=0,gaps={}}, waypoints={inspected=0,candidates={}}}
local function xyz(v) return {x=math.round(v.X*100)/100,y=math.round(v.Y*100)/100,z=math.round(v.Z*100)/100} end
local function path(p) return p and p:GetFullName() or nil end
local function params(included)
    local p=RaycastParams.new()
    p.FilterType=Enum.RaycastFilterType.Include
    p.FilterDescendantsInstances=included
    p.RespectCanCollide=true
    return p
end
local onlyWorld=params({world})
local characters={}
for _,p in ipairs(game:GetService("Players"):GetPlayers()) do if p.Character then table.insert(characters,p.Character) end end
local function ignored(h)
    local p=RaycastParams.new()
    p.FilterType=Enum.RaycastFilterType.Exclude
    local list=table.clone(characters);table.insert(list,h)
    p.FilterDescendantsInstances=list;p.RespectCanCollide=true
    return p
end
local function addCandidate(t,v) if #t<80 then table.insert(t,v) end end
for _,home in ipairs(root:GetDescendants()) do
    local carpet=home:IsA("Model") and home:FindFirstChild("InteriorCarpet")
    if carpet and carpet:IsA("BasePart") and not home:FindFirstChild("ClosedPanelDoor") then
        local apron=home:FindFirstChild("CutawayWallApron")
        local closedCutaway=apron and apron.Size.X>=carpet.Size.X-1
        if not closedCutaway then
            result.houses.inspected+=1
            local frame=carpet.CFrame*CFrame.new(0,.6,-carpet.Size.Z/2)
            local depth=math.min(carpet.Size.Z*.5,10)
            local p=ignored(home)
            local seen={}
            for _,x in ipairs({-1.2,0,1.2}) do for _,y in ipairs({2.25,4.5}) do
                local start=frame:PointToWorldSpace(Vector3.new(x,y,-3))
                local finish=frame:PointToWorldSpace(Vector3.new(x,y,depth))
                result.houses.rays+=1
                local hit=workspace:Raycast(start,finish-start,p)
                if hit and hit.Instance:IsDescendantOf(world) then
                    result.houses.foreignHits+=1
                    if not seen[hit.Instance] then
                        seen[hit.Instance]=true
                        addCandidate(result.houses.candidates,{house=path(home),kind="Foreign entry-lane collider",collider=path(hit.Instance),position=xyz(hit.Position)})
                    end
                end
            end end
            -- A ray starting inside a foreign solid can miss that same solid.
            -- Point containment catches the filled-room case independently.
            local overlap=OverlapParams.new();overlap.FilterType=Enum.RaycastFilterType.Include;overlap.FilterDescendantsInstances={world}
            overlap.RespectCanCollide=true
            for _,z in ipairs({1,4,depth}) do
                local point=frame:PointToWorldSpace(Vector3.new(0,2.5,z))
                for _,other in ipairs(workspace:GetPartBoundsInBox(CFrame.new(point),Vector3.new(.12,.12,.12),overlap)) do
                    if other.CanCollide and not other:IsDescendantOf(home) and other:IsA("Part") and other.Shape==Enum.PartType.Block then
                        local v=other.CFrame:PointToObjectSpace(point);local half=other.Size*.5
                        if math.abs(v.X)<half.X-.02 and math.abs(v.Y)<half.Y-.02 and math.abs(v.Z)<half.Z-.02 then
                            result.houses.embeddedSamples+=1
                            if not seen[other] then seen[other]=true;addCandidate(result.houses.candidates,{house=path(home),kind="Interior standing point embedded in foreign solid",collider=path(other),position=xyz(point)}) end
                        end
                    end
                end
            end
        end
    end
end

local chute=root:FindFirstChild("NarrowDescent",true)
if chute then
    local floors,slopes={},{}
    for _,p in ipairs(chute:GetDescendants()) do
        if p:IsA("BasePart") and (p.Name=="SmoothSlopingFloor" or p.Name=="DarkArrivalFloor") then
            table.insert(floors,p)
            if p.Name=="SmoothSlopingFloor" then table.insert(slopes,p) end
        end
    end
    table.sort(slopes,function(a,b) return a.Position.Z<b.Position.Z end)
    local floorParams=params(floors)
    local chuteParams=params({chute})
    local positions={}
    -- Midpoints and tightly sampled joins. The original floors extend .325 at
    -- each end; midpoint+LookVector recovers the authored shared bend.
    for i,p in ipairs(slopes) do
        table.insert(positions,p.Position.Z)
        if i<#slopes then
            local bend=p.Position+p.CFrame.UpVector*.43+p.CFrame.LookVector*((p.Size.Z-.65)/2)
            for _,dz in ipairs({-2,-1,0,.5,1,1.5,2,2.5,3,4,5,6}) do table.insert(positions,bend.Z+dz) end
        end
    end
    local sampleX=slopes[1] and slopes[1].Position.X or chute:GetPivot().Position.X
    local topY=0
    for _,p in ipairs(slopes) do topY=math.max(topY,p.Position.Y+p.Size.Z/2+20) end
    for _,z in ipairs(positions) do
        local floorHit=workspace:Raycast(Vector3.new(sampleX,topY,z),Vector3.new(0,-300,0),floorParams)
        if floorHit then
            for _,height in ipairs({2.5,4.5,6.5}) do
                local point=floorHit.Position+Vector3.new(0,height,0)
                result.chute.samples+=1
                for _,sign in ipairs({-1,1}) do
                    result.chute.rays+=1
                    local hit=workspace:Raycast(point,Vector3.new(sign*10,0,0),chuteParams)
                    if not hit then addCandidate(result.chute.gaps,{kind=sign<0 and "Missing west enclosure" or "Missing east enclosure",position=xyz(point)}) end
                end
            end
            local point=floorHit.Position+Vector3.new(0,2.5,0)
            result.chute.rays+=1
            if not workspace:Raycast(point,Vector3.new(0,14,0),chuteParams) then addCandidate(result.chute.gaps,{kind="Missing overhead enclosure",position=xyz(point)}) end
        else
            addCandidate(result.chute.gaps,{kind="No authored chute floor",z=z})
        end
    end
else result.chute.warning="NarrowDescent not found; adapt names to revised architecture" end

local adapterScript=game:GetService("ServerScriptService"):FindFirstChild("Level 5 Round Adapter",true)
local manifest=adapterScript and require(adapterScript).GetManifest()
if manifest then
    local points=table.clone(manifest.Waypoints or {})
    -- Representative optional routes from the authored geometry, HRP height.
    for _,p in ipairs({Vector3.new(-65,3,810),Vector3.new(-65,18,849),Vector3.new(-79,33,810),
        Vector3.new(65,3,970),Vector3.new(65,18,930),Vector3.new(79,33,970),
        Vector3.new(-58,11,1042),Vector3.new(-65,11,1100),Vector3.new(73,19,1069),Vector3.new(123,19,1150)}) do
        table.insert(points,manifest.Origin+p)
    end
    for index,p in ipairs(points) do
        result.waypoints.inspected+=1
        local ground=workspace:Raycast(p+Vector3.new(0,1,0),Vector3.new(0,-12,0),onlyWorld)
        if not ground or ground.Normal.Y<.6 or math.abs((p.Y-3)-ground.Position.Y)>2 then
            addCandidate(result.waypoints.candidates,{index=index,kind="Support/height needs traversal check",position=xyz(p),hit=ground and path(ground.Instance),hitPosition=ground and xyz(ground.Position)})
        else
            local overhead=workspace:Raycast(ground.Position+Vector3.new(0,.15,0),Vector3.new(0,5.6,0),onlyWorld)
            if overhead then addCandidate(result.waypoints.candidates,{index=index,kind="Potential headroom obstruction",position=xyz(p),hit=path(overhead.Instance),hitPosition=xyz(overhead.Position)}) end
        end
    end
else result.waypoints.warning="No active adapter manifest" end
local parts,lights,windows=0,0,0
for _,p in ipairs(root:GetDescendants()) do
    if p:IsA("BasePart") then parts+=1 end
    if p:IsA("Light") then lights+=1 end
    if p:GetAttribute("Level5TintedWindow")==true then windows+=1 end
end
result.budget={parts=parts,lights=lights,windows=windows,descendants=#world:GetDescendants(),limit=18000}
return result
