-- Read-only Play SERVER diagnostic for the one Staff Nook NoPath probe.
-- ComputeAsync creates only temporary Path objects; no world/character mutations.
local HttpService=game:GetService("HttpService")
local PathfindingService=game:GetService("PathfindingService")
local world=assert(workspace:FindFirstChild("Level 6 Generated World"),"Enter Level 6 with real E prompt first")
local staff
for _, item in ipairs(world:GetDescendants()) do
    if item:IsA("BasePart") and item.Name=="RoomStaffNook"
        and item:GetAttribute("Level6_BlenderGatewayRoom")==true then staff=item break end
end
assert(staff,"Seed has no live Staff Nook carrier")
local corridor=staff.Parent and staff.Parent.Parent
local function xyz(v) return {math.round(v.X*100)/100,math.round(v.Y*100)/100,math.round(v.Z*100)/100} end
local function point(offset)
    return staff.CFrame:PointToWorldSpace(Vector3.new(0,3,offset))
end
local function floorAndNearby(position)
    local rayParams=RaycastParams.new()
    rayParams.FilterType=Enum.RaycastFilterType.Include
    rayParams.FilterDescendantsInstances={world}
    rayParams.RespectCanCollide=true
    local hit=workspace:Raycast(position+Vector3.new(0,2,0),Vector3.new(0,-15,0),rayParams)
    local overlap=OverlapParams.new()
    overlap.FilterType=Enum.RaycastFilterType.Include
    overlap.FilterDescendantsInstances={world}
    local nearby={}
    for _, part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(position),Vector3.new(10,8,10),overlap)) do
        if part.CanCollide and part.Name~="Level 6 Corridor Floor"
            and not part.Name:find("Floor",1,true) then
            table.insert(nearby,{name=part.Name,path=part:GetFullName(),center=xyz(part.Position)})
        end
    end
    table.sort(nearby,function(a,b) return a.path<b.path end)
    while #nearby>10 do table.remove(nearby) end
    return {floor=hit and hit.Instance:GetFullName() or nil,
        floorY=hit and math.round(hit.Position.Y*100)/100 or nil,nearbyColliders=nearby}
end
local results={seed=world:GetAttribute("Level6_ResolvedSeed"),
    section=staff:GetFullName(),sectionCFrame=tostring(staff.CFrame),
    corridor=corridor and corridor:GetFullName() or nil,endpoints={},paths={}}
for _, offset in ipairs({-20,-15,-10,0,10,15,20}) do
    local position=point(offset)
    results.endpoints[tostring(offset)]={position=xyz(position),observation=floorAndNearby(position)}
end
local configs={{name="QA_R5_H8",radius=5,height=8},{name="Manager_R4_H10",radius=4,height=10}}
for _, config in ipairs(configs) do
    for _, span in ipairs({10,15,20}) do
        local path=PathfindingService:CreatePath({AgentRadius=config.radius,
            AgentHeight=config.height,AgentCanJump=false})
        local ok,err=pcall(function() path:ComputeAsync(point(-span),point(span)) end)
        table.insert(results.paths,{config=config.name,span=span,ok=ok,
            error=if ok then nil else tostring(err),
            status=if ok then path.Status.Name else nil,
            waypoints=if ok then #path:GetWaypoints() else 0})
    end
end
return HttpService:JSONEncode(results)
