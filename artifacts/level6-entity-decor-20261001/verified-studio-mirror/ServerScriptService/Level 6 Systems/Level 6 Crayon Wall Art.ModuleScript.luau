--!strict
-- Alpha crayon marks sit directly on the Blender wall skins. All placement is
-- owned by this generated world: no heartbeat jobs, physical blockers or remotes.
local Configuration = require(script.Parent:WaitForChild("Level 6 Configuration"))
local Art = {}

local LIBRARIES = {
    {Mood="Wholesome", Image="rbxassetid://122680678983418", Pixels=1024},
    {Mood="Unsettling", Image="rbxassetid://86367389253858", Pixels=1024},
    {Mood="Disturbing", Image="rbxassetid://117801916744224", Pixels=1024},
}
local GRID = 4
local REVISION = "20261001-crayon-progression"

local function shuffled(rng, items)
    local result = table.clone(items)
    for i=#result,2,-1 do
        local j=rng:NextInteger(1,i)
        result[i],result[j]=result[j],result[i]
    end
    return result
end

local function graphDepth(layout)
    local distances = {Arrival=0}
    local queue = {"Arrival"}
    local head = 1
    while head<=#queue do
        local id=queue[head]
        head+=1
        for _,other in ipairs(layout.Adjacency[id] or {}) do
            if distances[other]==nil then
                distances[other]=distances[id]+1
                table.insert(queue,other)
            end
        end
    end
    local bounds={}
    for _,room in ipairs(layout.Rooms) do
        local section=tonumber(room.SectionIndex) or 0
        local distance=distances[room.Id] or 0
        local bound=bounds[section] or {Min=distance,Max=distance}
        bound.Min=math.min(bound.Min,distance)
        bound.Max=math.max(bound.Max,distance)
        bounds[section]=bound
    end
    local progress={}
    for _,room in ipairs(layout.Rooms) do
        local section=tonumber(room.SectionIndex) or 0
        if room.Role=="Arrival" then progress[room.Id]=0
        elseif room.Role=="Exit" then progress[room.Id]=1
        else
            local bound=bounds[section]
            local localDepth=(distances[room.Id]-bound.Min)/math.max(1,bound.Max-bound.Min)
            progress[room.Id]=math.clamp(((section-1)+localDepth*.8)/3,0,1)
        end
    end
    return distances,progress
end

function Art.Apply(manifest)
    local world=assert(manifest.World)
    assert(not world:GetAttribute("Level6_CrayonRevision"),"Crayon art already applied")
    local rng=Random.new((manifest.Layout.ResolvedSeed+703777)%2147483646)
    local distances,progress=graphDepth(manifest.Layout)
    local report={Total=0,Wholesome=0,Unsettling=0,Disturbing=0,Rooms={},Revision=REVISION}
    local cellOrder,cellSerial={},{0,0,0}
    for tier=1,3 do
        local cells={} for i=1,16 do table.insert(cells,i) end
        cellOrder[tier]=shuffled(rng,cells)
    end
    local function chooseTier(depth)
        local pick=rng:NextNumber()
        if depth<1/3 then return if pick<.90-depth*.18 then 1 else 2 end
        if depth<2/3 then
            return if pick<.12 then 1 elseif pick<.80 then 2 else 3
        end
        return if pick<.05 then 1 elseif pick<.15 then 2 else 3
    end
    local function mark(parent,position,inward,size,depth,roomId,distance,tierOverride)
        local tier=tierOverride or chooseTier(depth)
        local library=LIBRARIES[tier]
        cellSerial[tier]+=1
        local cell=cellOrder[tier][(cellSerial[tier]-1)%16+1]
        local carrier=Instance.new("Part")
        carrier.Name="Crayon "..library.Mood.." "..cell
        carrier.Anchored=true
        carrier.Size=Vector3.new(size.X,size.Y,.006)
        carrier.CFrame=CFrame.lookAt(position,position+inward)
            *CFrame.Angles(0,0,math.rad(rng:NextNumber(-5,5)))
        carrier.Transparency=1
        carrier.CanCollide=false
        carrier.CanQuery=false
        carrier.CanTouch=false
        carrier.CastShadow=false
        carrier:SetAttribute("Level6_KidsWallArt",true)
        carrier:SetAttribute("Level6_NewCrayonArt",true)
        carrier:SetAttribute("Level6_DrawingMood",library.Mood)
        carrier:SetAttribute("Level6_DrawingTier",tier)
        carrier:SetAttribute("Level6_AtlasCell",cell)
        carrier:SetAttribute("Level6_ArtProgress",depth)
        carrier:SetAttribute("Level6_ArtGraphDepth",distance)
        carrier:SetAttribute("Level6_ArtRoomId",roomId)
        local surface=Instance.new("SurfaceGui")
        surface.Name="Crayon On Wall"
        surface.Face=Enum.NormalId.Front
        surface.AlwaysOnTop=false
        surface.LightInfluence=.92
        surface.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud
        surface.PixelsPerStud=64
        surface.ZOffset=.02
        surface.Parent=carrier
        local image=Instance.new("ImageLabel")
        image.Name="Crayon Pigment"
        image.BackgroundTransparency=1
        image.BorderSizePixel=0
        image.Size=UDim2.fromScale(1,1)
        image.Image=library.Image
        image.ImageTransparency=.055
        image.ScaleType=Enum.ScaleType.Stretch
        local column,row=(cell-1)%GRID,math.floor((cell-1)/GRID)
        local x,y=math.floor(column*library.Pixels/GRID),math.floor(row*library.Pixels/GRID)
        local right,bottom=math.floor((column+1)*library.Pixels/GRID),math.floor((row+1)*library.Pixels/GRID)
        image.ImageRectSize=Vector2.new(right-x,bottom-y)
        image.ImageRectOffset=Vector2.new(x,y)
        image.Parent=surface
        carrier.Parent=parent
        report.Total+=1
        report[library.Mood]+=1
        return carrier
    end

    for _,room in ipairs(manifest.Layout.Rooms) do
        local model=assert(manifest.Rooms[room.Id])
        local depth=progress[room.Id]
        local section=tonumber(room.SectionIndex) or 0
        local count=if room.Role=="Arrival" then 3
            elseif room.Role=="Exit" then 8
            elseif section==1 then rng:NextInteger(5,7)
            elseif section==2 then rng:NextInteger(8,11)
            else rng:NextInteger(13,16)
        local slots={}
        for _,wall in ipairs(model:GetChildren()) do
            if not wall:IsA("BasePart") then continue end
            local side=wall.Name:match("^Level 6 (%a+) Wall")
            if not side then continue end
            local horizontal=side=="North" or side=="South"
            local length=if horizontal then wall.Size.X else wall.Size.Z
            local thickness=if horizontal then wall.Size.Z else wall.Size.X
            local inward=if side=="North" then Vector3.zAxis
                elseif side=="South" then -Vector3.zAxis
                elseif side=="West" then Vector3.xAxis else -Vector3.xAxis
            local slotCount=math.floor((length-2)/7)
            for index=1,slotCount do
                local along=(index-(slotCount+1)/2)*7
                local offset=if horizontal then Vector3.new(along,0,0) else Vector3.new(0,0,along)
                local center=wall.Position+offset+inward*(thickness*.5+.042)
                table.insert(slots,{Center=center,Inward=inward})
            end
        end
        slots=shuffled(rng,slots)
        local folder=Instance.new("Folder")
        folder.Name="Progressive Crayon Drawings"
        folder.Parent=model
        local placed=math.min(count,#slots)
        report.Rooms[room.Id]={Count=placed,Progress=depth,GraphDepth=distances[room.Id],Section=section}
        model:SetAttribute("Level6_ArtProgress",depth)
        model:SetAttribute("Level6_NewDrawingCount",placed)
        for i=1,placed do
            local slot=slots[i]
            local width=rng:NextNumber(3.2,4.3)
            local height=width*rng:NextNumber(.86,1.05)
            local y=Configuration.WorldOrigin.Y+rng:NextNumber(3.8,5.1)
            mark(folder,Vector3.new(slot.Center.X,y,slot.Center.Z),slot.Inward,
                Vector2.new(width,height),depth,room.Id,distances[room.Id])
        end
    end

    -- The last unlit stretch becomes a continuous, worsening crayon trail.
    -- Its navigation bore and the exit interactions remain completely clear.
    local hall=manifest.FinalHall
    if hall then
        local folder=Instance.new("Folder")
        folder.Name="Final Corridor Crayon Drawings"
        folder.Parent=hall.Model
        local right=hall.Forward:Cross(Vector3.yAxis)
        for i=1,18 do
            local alpha=.06+(i-1)*.052
            local side=if i%2==0 then 1 else -1
            local p=hall.StartPoint:Lerp(hall.EndPoint,alpha)
                +right*side*(hall.Width*.5-.044)+Vector3.new(0,rng:NextNumber(4,5.1),0)
            mark(folder,p,-right*side,Vector2.new(3.6,3.8),.90+alpha*.10,
                "FinalHall",(distances.Exit or 0)+alpha,if i<=2 then 2 else 3)
        end
    end
    world:SetAttribute("Level6_CrayonRevision",REVISION)
    world:SetAttribute("Level6_NewCrayonDrawingCount",report.Total)
    world:SetAttribute("Level6_NewWholesomeDrawingCount",report.Wholesome)
    world:SetAttribute("Level6_NewUnsettlingDrawingCount",report.Unsettling)
    world:SetAttribute("Level6_NewDisturbingDrawingCount",report.Disturbing)
    return report
end

return Art
