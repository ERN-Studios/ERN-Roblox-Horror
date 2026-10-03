-- Offline-authored developer-preview builder. Installed kit schema: KIT_SPEC section 10.
-- Build does not import/bake assets, replace the live builder, or start encounter tasks.
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local Terrain = workspace.Terrain
local Configuration = require(script.Parent:WaitForChild("Level 2 Configuration"))
local WorldBuilder = {}

local WHITE = Color3.fromRGB(241, 237, 220)
local LOCKED = Color3.fromRGB(214,96,78)
local SLIDE_PHYSICS = PhysicalProperties.new(.7, .05, .05, 1, 1)

local function container(parent, name, class)
    local object = Instance.new(class or "Folder")
    object.Name, object.Parent = name, parent
    return object
end

local function part(parent, name, size, cf, variant, color, ground)
    local p = Instance.new("Part")
    p.Name, p.Size, p.CFrame = name, size, cf
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, true, true, false
    p.Material, p.MaterialVariant, p.Color = Enum.Material.SmoothPlastic, variant or "PR Tile", color or WHITE
    if p.MaterialVariant=="PR Tile" or p.MaterialVariant=="PR Tile Aqua" then p.Reflectance=.06 end
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    p.CollisionGroup = "Default"
    if ground then p:SetAttribute("Level2_EntityGround", true) end
    p.Parent = parent
    return p
end

local function invisible(p, collidable)
    p.Transparency, p.CastShadow = 1, false
    p.CanCollide, p.CanQuery, p.CanTouch = collidable == true, collidable == true, false
    return p
end

local function marker(parent, name, position, size)
    return invisible(part(parent, name, size or Vector3.new(1.5,.2,1.5), CFrame.new(position)), false)
end

local function center(hall)
    -- Kit Center already contains FloorY; the live layout's Center did not.
    return Vector3.new(hall.Center.X, hall.FloorY or 0, hall.Center.Z)
end

local function vector(record) return Vector3.new(record[1], record[2], record[3]) end
local function frame(record)
    if record.position then
        return CFrame.fromMatrix(vector(record.position), vector(record.right), vector(record.up), vector(record.back))
    end
    return CFrame.new(record[1],record[2],record[3]) * CFrame.Angles(0,math.rad(record[4] or 0),0)
end

local function attributes(object, values)
    for name, value in pairs(values or {}) do
        -- Only the exported gameplay vector is an array-valued runtime attribute.
        if name == "Level2_SlideDirection" then value = vector(value) end
        if type(value) ~= "table" then object:SetAttribute(name, value) end
    end
end

local function roof(p)
    p:SetAttribute("Level2_EntityGround", nil)
    p:SetAttribute("Level2_NoEntityGround", true)
    local modifier = p:FindFirstChildWhichIsA("PathfindingModifier")
    if not modifier then modifier = Instance.new("PathfindingModifier"); modifier.Parent = p end
    modifier.Label, modifier.PassThrough = "Level2Roof", false
end

-- Kit readers and placement. Markers are local CFrameValues, including duplicate
-- Socket/Light names: retain the complete list before destroying the authoring folder.
local function readKit()
    local kit = ServerStorage:FindFirstChild("Level2BlenderKit")
    assert(kit and kit:IsA("Folder"), "[Level 2 Kit] missing ServerStorage.Level2BlenderKit; install the approved kit first")
    assert(kit:GetAttribute("Ready") == true, "[Level 2 Kit] Level2BlenderKit.Ready must be true (installer sets it last)")
    assert(type(kit:GetAttribute("KitBuild"))=="string" and kit:GetAttribute("KitBuild")~="",
        "[Level 2 Kit] Level2BlenderKit.KitBuild is missing")
    assert(type(kit:GetAttribute("ManifestSha256"))=="string" and kit:GetAttribute("ManifestSha256")~="",
        "[Level 2 Kit] Level2BlenderKit.ManifestSha256 is missing")
    local components, templates, data = kit:FindFirstChild("Components"), kit:FindFirstChild("SlideTemplates"), kit:FindFirstChild("Data")
    assert(components and templates and data, "[Level 2 Kit] incomplete install: Components, SlideTemplates and Data are required")
    local chunks = {}
    for _, child in ipairs(data:GetChildren()) do
        if child:IsA("StringValue") and child.Name:match("^SlidesJSON%-%d+$") then table.insert(chunks, child) end
    end
    table.sort(chunks, function(a,b) return a.Name < b.Name end)
    assert(#chunks > 0, "[Level 2 Kit] missing Data.SlidesJSON-001")
    local strings = {}
    for index, chunk in ipairs(chunks) do
        assert(chunk.Name == string.format("SlidesJSON-%03d", index), "[Level 2 Kit] missing or misnumbered SlidesJSON chunk")
        strings[index] = chunk.Value
    end
    local ok, slides = pcall(function() return HttpService:JSONDecode(table.concat(strings)) end)
    assert(ok and type(slides) == "table" and slides.slides and slides.prefabs and slides.prefabParts and slides.slideProfiles,
        "[Level 2 Kit] invalid SlidesJSON: slides, prefabs, prefabParts and slideProfiles are required")
    return kit, components, templates, slides
end

local function cloneComponent(ctx, name, parent, cf, flatten)
    local template = ctx.components:FindFirstChild(name)
    assert(template and template:IsA("Model"), "[Level 2 Kit] missing Components." .. name)
    local model = template:Clone()
    local markers = {}
    local authoring = model:FindFirstChild("Markers")
    if authoring then
        for _, m in ipairs(authoring:GetChildren()) do
            if m:IsA("CFrameValue") then
                table.insert(markers, {Name=m.Name, CFrame=cf*m.Value, LocalCFrame=m.Value, Attributes=m:GetAttributes()})
            end
        end
        authoring:Destroy()
    end
    model:PivotTo(cf)
    model.Name = "L2K " .. name
    model:SetAttribute("Level2_KitComponent", name)
    model.Parent = parent
    for _, p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") then
            p.CollisionGroup = "Default"
            if p.MaterialVariant=="PR Tile" or p.MaterialVariant=="PR Tile Aqua" then p.Reflectance=.06 end
            p.Name = p.Name:gsub("{i}", tostring(ctx.hallIndex or 0))
            -- Authoring names must not accidentally invoke the live roof pass.
            if not p.Name:find("Roof",1,true) then
                p.Name = p.Name:gsub("Skylight", "LightWell"):gsub("Ceiling", "Overhead Tile")
            elseif p.CanCollide then
                roof(p)
            end
            p:SetAttribute("Level2_KitComponent", name)
            if p:IsA("MeshPart") then
                p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
            end
            if p:GetAttribute("Level2_SlideCollision") then
                p:SetAttribute("Level2_NoEntityGround", true)
                if p:GetAttribute("Level2_SlideFloor") then p:SetAttribute("Level2_SlideDirection",p.CFrame.LookVector) end
            end
        end
    end
    if flatten then
        for _, child in ipairs(model:GetChildren()) do child.Parent = parent end
        model:Destroy()
    end
    return model, markers
end

local function findMarker(markers, name)
    for _, m in ipairs(markers) do if m.Name == name then return m end end
    return nil
end

local function addLight(ctx, parent, class, brightness, range, face)
    assert(ctx.lights < 80, "[Level 2 Kit] light budget exceeded")
    local light = Instance.new(class)
    light.Brightness, light.Range, light.Shadows, light.Color = brightness, range, false, WHITE
    if face then light.Face = face end
    light.Parent = parent
    ctx.lights += 1
    return light
end

local function water(ctx, position, size, label)
    local region = {CFrame=typeof(position)=="CFrame" and position or CFrame.new(position), Size=size, Label=label}
    Terrain:FillBlock(region.CFrame,region.Size,Enum.Material.Water)
    table.insert(ctx.waterRegions,region)
    return region
end

-- Openings are derived from actual From/To geometry, never the A/B ordering.
local function hallDoors(layout)
    local byHall = {}
    for _, h in ipairs(layout.Halls) do byHall[h.Index]={East={},West={},North={},South={}} end
    for _, c in ipairs(layout.Corridors) do
        local a,b=layout.Halls[c.A],layout.Halls[c.B]
        local first,last=a,b
        if (c.Axis=="X" and a.Center.X>b.Center.X) or (c.Axis=="Z" and a.Center.Z>b.Center.Z) then first,last=b,a end
        assert(math.abs(first.FloorY-c.FromY)<.01 and math.abs(last.FloorY-c.ToY)<.01,
            "[Level 2 Kit] corridor mouth floor differs from its hall floor: "..c.Index)
        local record={Cross=c.Cross,Width=c.Kind=="Narrow" and 12 or 34,Height=c.Kind=="Narrow" and 14 or 34,Corridor=c}
        table.insert(byHall[first.Index][c.Axis=="X" and "East" or "South"],record)
        table.insert(byHall[last.Index][c.Axis=="X" and "West" or "North"],record)
    end
    return byHall
end

-- The foam route is centre axes plus door-to-axis spokes. Keep prop AABBs
-- outside all of them and the final-art spawn reservation.
local function clearPocket(hall, doors, position, width, depth, reservations, margin,spacing)
    local x,z=position.X,position.Z
    margin=margin or 6
    if x-width/2<hall.MinX+margin or x+width/2>hall.MaxX-margin or z-depth/2<hall.MinZ+margin or z+depth/2>hall.MaxZ-margin then return false end
    if math.abs(x-hall.Center.X)<17+width/2 or math.abs(z-hall.Center.Z)<17+depth/2 then return false end
    for side, list in pairs(doors) do
        for _, d in ipairs(list) do
            if side=="West" or side=="East" then
                if math.abs(z-d.Cross)<17+depth/2
                    and (side=="West" and x-width/2<hall.Center.X or side=="East" and x+width/2>hall.Center.X) then return false end
            elseif math.abs(x-d.Cross)<17+width/2
                and (side=="North" and z-depth/2<hall.Center.Z or side=="South" and z+depth/2>hall.Center.Z) then return false end
        end
    end
    for _, r in ipairs(reservations or {}) do
        if math.abs(x-r.Position.X)<(width+r.Width)/2+(spacing or 4)
            and math.abs(z-r.Position.Z)<(depth+r.Depth)/2+(spacing or 4) then return false end
    end
    return true
end

local function reserveAt(hall,doors,position,width,depth,reservations,margin,spacing)
    if not clearPocket(hall,doors,position,width,depth,reservations,margin,spacing) then return false end
    table.insert(reservations,{Position=position,Width=width,Depth=depth})
    return true
end

local function reservePocket(hall,doors,width,depth,reservations)
    -- Edge-first deterministic scan, bounded by a room's maximum 272 footprint.
    for _, sx in ipairs({1,-1}) do
        for _, sz in ipairs({1,-1}) do
            for dx=6+width/2,hall.Width/2,4 do
                for dz=6+depth/2,hall.Depth/2,4 do
                    local p=Vector3.new(sx>0 and hall.MaxX-dx or hall.MinX+dx,hall.FloorY,sz>0 and hall.MaxZ-dz or hall.MinZ+dz)
                    if clearPocket(hall,doors,p,width,depth,reservations) then
                        table.insert(reservations,{Position=p,Width=width,Depth=depth})
                        return p
                    end
                end
            end
        end
    end
    return nil
end

-- Poolrooms shells leave real openings around the exported round panels.
local function basinDepth(hall)
    if hall.Type=="Arrival" or hall.Type=="PumpHall" or (hall.PoolType=="Dry" and hall.Type~="PaddlingRoom") then return 0 end
    return hall.Type=="PaddlingRoom" and .8 or math.clamp(hall.DeepEnd or 1.6,1.6,3.5)
end

local function floorShell(ctx,parent,hall)
    local c=center(hall)
    local deep=basinDepth(hall)
    if deep==0 then
        part(parent,"Level 2 Hall Floor "..hall.Index,Vector3.new(hall.Width,1,hall.Depth),
            CFrame.new(c-Vector3.yAxis*.5),"PR Tile",WHITE,true)
        return false
    end
    local shallow=hall.Type=="PaddlingRoom" and .8 or .8
    local run=hall.PoolAxis=="X" and hall.Width or hall.Depth
    local tilt=math.atan((deep-shallow)/run)
    local rotation=hall.PoolAxis=="X" and CFrame.Angles(0,0,-tilt) or CFrame.Angles(tilt,0,0)
    local length=math.sqrt(run*run+(deep-shallow)^2)
    local size=hall.PoolAxis=="X" and Vector3.new(length,.8,hall.Depth)
        or Vector3.new(hall.Width,.8,length)
    local top=CFrame.new(c-Vector3.yAxis*(deep+shallow)/2)*rotation
    part(parent,"Level 2 Hall Water Floor "..hall.Index,size,top*CFrame.new(0,-.4,0),"PR Tile Aqua",WHITE,true)
    water(ctx,c+Vector3.new(0,(.1-deep)/2,0),Vector3.new(hall.Width-2.5,deep+.1,hall.Depth-2.5),"Hall "..hall.Index)
    return true
end

local function wallPose(hall,side,along,inset)
    local y=hall.FloorY
    inset+=1 -- the kit collar projects 1.75 inward from the layout boundary
    if side=="North" then return CFrame.new(along,y,hall.MinZ+inset)*CFrame.Angles(0,math.pi,0) end
    if side=="South" then return CFrame.new(along,y,hall.MaxZ-inset) end
    if side=="West" then return CFrame.new(hall.MinX+inset,y,along)*CFrame.Angles(0,-math.pi/2,0) end
    return CFrame.new(hall.MaxX-inset,y,along)*CFrame.Angles(0,math.pi/2,0)
end

local function coveRun(ctx,parent,hall,side,a,b,top)
    local alongX=side=="North" or side=="South"
    a=math.max(a,(alongX and hall.MinX or hall.MinZ)+.5)
    b=math.min(b,(alongX and hall.MaxX or hall.MaxZ)-.5)
    if b-a<=.05 then return end
    local cf=wallPose(hall,side,(a+b)/2,.75)*CFrame.new(0,top and hall.CeilingClass-3 or 0,0)
        *CFrame.Angles(0,math.pi,0)
    local model=cloneComponent(ctx,top and "CoveTop64" or "CoveBase64",parent,cf,false)
    local factor=(b-a+1)/64 -- half a stud into the adjoining corner cove or collar at either end
    for _,p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") then
            local localCF=cf:ToObjectSpace(p.CFrame)
            p.Size=Vector3.new(p.Size.X*factor,p.Size.Y,p.Size.Z)
            p.CFrame=cf*CFrame.new(localCF.Position.X*factor,localCF.Position.Y,localCF.Position.Z)*localCF.Rotation
        end
    end
    for _,child in ipairs(model:GetChildren()) do child.Parent=parent end
    model:Destroy()
end

local function wallShell(ctx,parent,hall,side,doors,exitGap)
    local alongX=side=="North" or side=="South"
    local low,high=alongX and hall.MinX or hall.MinZ,alongX and hall.MaxX or hall.MaxZ
    local fixed=side=="North" and hall.MinZ+.875 or side=="South" and hall.MaxZ-.875
        or side=="West" and hall.MinX+.875 or hall.MaxX-.875
    local y,h=hall.FloorY,hall.CeilingClass
    local base=-basinDepth(hall)-4
    local crown=h+2
    local holes={}
    for _,d in ipairs(doors) do
        table.insert(holes,{low=d.Cross-d.Width/2,high=d.Cross+d.Width/2,bottom=-2,top=d.Height-2,Door=d})
    end
    if exitGap then
        table.insert(holes,{low=exitGap.center-exitGap.width/2,high=exitGap.center+exitGap.width/2,
            bottom=exitGap.bottom-y,top=exitGap.top-y})
    end
    local sunWall=hall.Type=="Arrival" and (hall.Width>=hall.Depth and "North" or "West")
        or hall.Type=="CorridorHall" and (hall.Width>=hall.Depth and "South" or "East")
    if side==sunWall then
        local from,to=hall.Type=="Arrival" and (low+high)/2 or low+16,
            hall.Type=="Arrival" and (low+high)/2 or high-16
        for at=from,to,24 do
            local clear=true
            for _,hole in ipairs(holes) do
                if at+6>hole.low and at-6<hole.high then clear=false; break end
            end
            if clear then table.insert(holes,{low=at-1,high=at+1,bottom=h-17,top=h-3,Sun=true}) end
        end
    end
    table.sort(holes,function(a,b) return a.low<b.low end)
    local function slab(a,b,bottom,top,name)
        if b-a<.05 or top-bottom<.05 then return end
        local pos=alongX and Vector3.new((a+b)/2,y+(bottom+top)/2,fixed)
            or Vector3.new(fixed,y+(bottom+top)/2,(a+b)/2)
        local size=alongX and Vector3.new(b-a,top-bottom,1.75) or Vector3.new(1.75,top-bottom,b-a)
        part(parent,name.." "..hall.Index.." "..side,size,CFrame.new(pos),"PR Tile",WHITE,true)
    end
    local cursor=low
    for _,hole in ipairs(holes) do
        assert(hole.low>=cursor-.01 and hole.high<=high+.01,"[Level 2 Kit] overlapping/out-of-wall opening in "..hall.Id)
        slab(cursor,hole.low,base,crown,"Level 2 Hall Wall")
        coveRun(ctx,parent,hall,side,cursor,hole.low,true)
        coveRun(ctx,parent,hall,side,cursor,hole.low,false)
        slab(hole.low,hole.high,base,hole.bottom,"Level 2 Hall Sill")
        slab(hole.low,hole.high,hole.top,crown,"Level 2 Hall Lintel")
        if hole.Sun then
            cloneComponent(ctx,"SunSlit",parent,wallPose(hall,side,(hole.low+hole.high)/2,1.2)
                *CFrame.new(0,h-20,0),true)
        end
        cursor=hole.high
    end
    slab(cursor,high,base,crown,"Level 2 Hall Wall")
    coveRun(ctx,parent,hall,side,cursor,high,true)
    coveRun(ctx,parent,hall,side,cursor,high,false)
end

local function cornerCoves(ctx,parent,hall)
    local radius=hall.Type=="PaddlingRoom" and 24
        or math.min(hall.Width,hall.Depth)<112 and 8
        or math.max(hall.Width,hall.Depth)>200 and 24 or 16
    local sourceHeight=math.min(hall.CeilingClass,52)
    if sourceHeight~=34 and sourceHeight~=42 and sourceHeight~=52 then sourceHeight=52 end
    for _,corner in ipairs({
        {hall.MinX,hall.MinZ,math.pi},{hall.MaxX,hall.MinZ,math.pi/2},
        {hall.MinX,hall.MaxZ,-math.pi/2},{hall.MaxX,hall.MaxZ,0}
    }) do
        local cf=CFrame.new(corner[1],hall.FloorY,corner[2])*CFrame.Angles(0,corner[3],0)
        local model=cloneComponent(ctx,"CornerCove_R"..radius.."_H"..sourceHeight,parent,cf,false)
        if hall.CeilingClass>sourceHeight then
            local factor=hall.CeilingClass/sourceHeight
            for _,p in ipairs(model:GetDescendants()) do
                if p:IsA("BasePart") then
                    local localCF=cf:ToObjectSpace(p.CFrame)
                    p.Size=Vector3.new(p.Size.X,p.Size.Y*factor,p.Size.Z)
                    p.CFrame=cf*CFrame.new(localCF.Position.X,localCF.Position.Y*factor,localCF.Position.Z)*localCF.Rotation
                end
            end
        end
        for _,p in ipairs(model:GetDescendants()) do
            if p:IsA("BasePart") and p.Name:find("Corner Block",1,true) then p:Destroy() end
        end
        local base=-basinDepth(hall)-4
        local height=hall.CeilingClass+2-base
        local seal=invisible(part(model,"Level 2 Corner Seal",Vector3.new(5,height,5),
            cf*CFrame.new(-2.5,(hall.CeilingClass+2+base)/2,-2.5),"PR Tile"),true)
        seal:SetAttribute("Level2_KitComponent","CornerCove_R"..radius.."_H"..sourceHeight)
        for _,child in ipairs(model:GetChildren()) do child.Parent=parent end
        model:Destroy()
        cloneComponent(ctx,"CoveTopCorner_R"..radius,parent,cf*CFrame.new(0,hall.CeilingClass-3,0),true)
        cloneComponent(ctx,"CoveBaseCorner_R"..radius,parent,cf,true)
    end
end

local function openSky(ctx,parent,hall,position,radius,kind,panel)
    local opening=marker(parent,"Level 2 Open Sky "..hall.Index.."."..(ctx.skyCount+1),
        Vector3.new(position.X,hall.FloorY+hall.CeilingClass+1,position.Z),Vector3.new(.4,.4,.4))
    ctx.skyCount+=1
    opening:SetAttribute("Level2_OpenSkyRadius",radius)
    opening:SetAttribute("Level2_OpenSkyKind",kind)
    return {X=position.X,Z=position.Z,Half=panel/2,Radius=radius}
end

local function ceilingShell(ctx,parent,hall,openings)
    local c=center(hall)
    local xs,zs={hall.MinX,hall.MaxX},{hall.MinZ,hall.MaxZ}
    for _,hole in ipairs(openings) do
        table.insert(xs,hole.X-hole.Half); table.insert(xs,hole.X+hole.Half)
        table.insert(zs,hole.Z-hole.Half); table.insert(zs,hole.Z+hole.Half)
    end
    table.sort(xs); table.sort(zs)
    local function strip(x0,x1,z0,z1)
        local w,d=x1-x0,z1-z0
        if w<=.05 or d<=.05 then return end
        local cf=CFrame.new((x0+x1)/2,c.Y+hall.CeilingClass+1.25,(z0+z1)/2)
        local tile=part(parent,"Level 2 Overhead Tile "..hall.Index,Vector3.new(w,2.5,d),cf,"PR Tile")
        tile.CanCollide,tile.CanQuery=false,false
        roof(invisible(part(parent,"Level 2 Hall Roof Collider",Vector3.new(w,1,d),
            cf*CFrame.new(0,.75,0),"PR Tile"),true))
    end
    for zi=1,#zs-1 do
        local z0,z1=zs[zi],zs[zi+1]
        local z=(z0+z1)/2
        local start=nil
        for xi=1,#xs-1 do
            local x=(xs[xi]+xs[xi+1])/2
            local covered=false
            for _,hole in ipairs(openings) do
                if math.abs(x-hole.X)<hole.Half-.01 and math.abs(z-hole.Z)<hole.Half-.01 then
                    covered=true
                    break
                end
            end
            if not covered and not start then start=xs[xi] end
            if covered and start then strip(start,xs[xi],z0,z1); start=nil end
        end
        if start then strip(start,xs[#xs],z0,z1) end
    end
end

local function placeWalkways(ctx,parent,hall,doors)
    if hall.Type=="Arrival" then return end -- dry floor is the 32x30 clear spawn apron and reaches its door
    local c=center(hall)
    local side=hall.Width>=hall.Depth and "North" or "West"
    local alongX=side=="North"
    local low=alongX and hall.MinX or hall.MinZ
    local high=alongX and hall.MaxX or hall.MaxZ
    for _,wall in ipairs({side,alongX and "South" or "East"}) do
        local pos=alongX and Vector3.new((low+high)/2,c.Y,wall=="North" and hall.MinZ+6.25 or hall.MaxZ-6.25)
            or Vector3.new(wall=="West" and hall.MinX+6.25 or hall.MaxX-6.25,c.Y,(low+high)/2)
        local cf=CFrame.new(pos)*CFrame.Angles(0,alongX and 0 or math.pi/2,0)
        local strip=cloneComponent(ctx,"Walkway_Straight32",parent,cf,false)
        local factor=(high-low-3)/32
        for _,p in ipairs(strip:GetDescendants()) do
            if p:IsA("BasePart") then
                local localCF=cf:ToObjectSpace(p.CFrame)
                p.Size=Vector3.new(p.Size.X*factor,p.Size.Y,p.Size.Z)
                p.CFrame=cf*CFrame.new(localCF.Position.X*factor,localCF.Position.Y,localCF.Position.Z)*localCF.Rotation
            end
        end
        for _,child in ipairs(strip:GetChildren()) do child.Parent=parent end
        strip:Destroy()
    end
    for wall,list in pairs(doors) do
        for _,d in ipairs(list) do
            local pos=wall=="North" and Vector3.new(d.Cross,c.Y,hall.MinZ+5)
                or wall=="South" and Vector3.new(d.Cross,c.Y,hall.MaxZ-5)
                or wall=="West" and Vector3.new(hall.MinX+5,c.Y,d.Cross)
                or Vector3.new(hall.MaxX-5,c.Y,d.Cross)
            local yaw=wall=="North" and math.pi or wall=="South" and 0
                or wall=="West" and -math.pi/2 or math.pi/2
            local cf=CFrame.new(pos)*CFrame.Angles(0,yaw,0)
            local curved=hall.Type=="PaddlingRoom"
            local steps=cloneComponent(ctx,curved and "PoolSteps_Curved" or "PoolSteps_Straight12",parent,cf,false)
            if curved then
                for _,p in ipairs(steps:GetDescendants()) do
                    if p:IsA("BasePart") and p.Name:find("Ground",1,true) then p:Destroy() end
                end
                local threshold=part(steps,"Level 2 Paddling Threshold Ground",Vector3.new(12,.7,12),
                    cf*CFrame.new(0,-.35,-4),"PR Tile",WHITE,true)
                threshold:SetAttribute("Level2_KitComponent","PoolSteps_Curved")
            end
            for _,child in ipairs(steps:GetChildren()) do child.Parent=parent end
            steps:Destroy()
        end
    end
end

local function placeObstacle(ctx,parent,hall,doors,reservations,name,width,depth)
    local pos=reservePocket(hall,doors,width,depth,reservations)
    if not pos then return nil end
    local model=cloneComponent(ctx,name,parent,CFrame.new(pos),false)
    model:SetAttribute("Level2_Dressing",true)
    return model,pos
end

local function fitVaultPier(model,pos,height)
    for _,p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") then
            p.Size=Vector3.new(p.Size.X,height,p.Size.Z)
            p.CFrame=CFrame.new(pos+Vector3.yAxis*(height/2))
        end
    end
end

local function placeVaultBay(ctx,parent,height,cf)
    local model=cloneComponent(ctx,"VaultBay32_H"..height,parent,cf,false)
    for _,p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") then
            assert(p.Size.Y>12 and p.Size.Y<13,"[Level 2 Kit] unexpected vault bay height")
            p.Size=Vector3.new(p.Size.X,12,p.Size.Z)
            p.CFrame=CFrame.new(p.Position.X,cf.Position.Y+height-6,p.Position.Z)*p.CFrame.Rotation
        end
    end
    for _,child in ipairs(model:GetChildren()) do child.Parent=parent end
    model:Destroy()
end

local function dressHall(ctx,parent,hall,doors,reservations)
    local rng=Random.new((hall.LocalSeed or ctx.layout.Seed+hall.Index)+918273)
    local h=math.min(hall.CeilingClass,52)
    local suffix="_H"..h
    local openings={}
    local kind=hall.Type
    local function patterned(name,width,depth,x,z)
        local pos=Vector3.new(hall.Center.X+x,hall.FloorY,hall.Center.Z+z)
        if not reserveAt(hall,doors,pos,width,depth,reservations) then return nil end
        local model=cloneComponent(ctx,name,parent,CFrame.new(pos),false)
        model:SetAttribute("Level2_Dressing",true)
        return model,pos
    end
    if kind=="ColumnHall" then
        local sign=rng:NextInteger(0,1)==0 and -1 or 1
        local landmarkX=math.min(64,hall.Width/2-17)
        local landmarkZ=math.min(64,hall.Depth/2-17)
        for _,s in ipairs({sign,-sign}) do
            if not patterned("Column_D16"..suffix,20,20,s*landmarkX,s*landmarkZ) then
                placeObstacle(ctx,parent,hall,doors,reservations,"Column_D16"..suffix,20,20)
            end
        end
        for _,cell in ipairs({{-1,-1},{1,-1},{-1,1},{1,1}}) do
            local x=cell[1]*math.min(32,hall.Width/2-14)+rng:NextInteger(-2,2)
            local z=cell[2]*math.min(32,hall.Depth/2-14)+rng:NextInteger(-2,2)
            if not patterned("Column_D10"..suffix,14,14,x,z) then
                placeObstacle(ctx,parent,hall,doors,reservations,"Column_D10"..suffix,14,14)
            end
        end
    elseif kind=="BigPool" then
        local alongX=hall.PoolAxis=="X"
        local crossHalf=(alongX and hall.Depth or hall.Width)/2
        local cross=math.min(crossHalf-15,math.max(30,crossHalf*.55))
        local island
        for _,slot in ipairs({{-64,-1},{-32,-1},{32,-1},{-32,1},{32,1}}) do
            local x=alongX and slot[1] or slot[2]*cross
            local z=alongX and slot[2]*cross or slot[1]
            local model,pos=patterned("Column_D10"..suffix,14,14,x,z)
            if not model then model,pos=placeObstacle(ctx,parent,hall,doors,reservations,"Column_D10"..suffix,14,14) end
            island=island or pos
        end
        if island then
            cloneComponent(ctx,"Walkway_End",parent,CFrame.new(island-Vector3.xAxis*5),true)
            cloneComponent(ctx,"Walkway_End",parent,CFrame.new(island+Vector3.xAxis*5)*CFrame.Angles(0,math.pi,0),true)
        end
        for ix=-3,3 do for iz=-3,3 do
            local p=center(hall)+Vector3.new(ix*16,hall.CeilingClass-.6,iz*16)
            if math.abs(ix*16)<hall.Width/2-12 and math.abs(iz*16)<hall.Depth/2-12 then
                local _,marks=cloneComponent(ctx,"LightRound",parent,CFrame.new(p),true)
                if ((ix+3)*7+iz+3)%3==0 and ctx.lights<ctx.hallLightLimit then
                    local m=findMarker(marks,"Light")
                    local emitter=marker(parent,"Level 2 Hall Round Light "..hall.Index,m and m.CFrame.Position or p)
                    addLight(ctx,emitter,"PointLight",1.2,25)
                end
            end
        end
        end
        local side=hall.PoolAxis=="X" and "East" or "South"
        local low=side=="East" and hall.MinZ or hall.MinX
        local high=side=="East" and hall.MaxZ or hall.MaxX
        for i=2,5 do
            local along=low+(high-low)*i/7
            local clear=true
            for _,d in ipairs(doors[side]) do
                if math.abs(along-d.Cross)<d.Width/2+8 then clear=false; break end
            end
            if clear then cloneComponent(ctx,"WallVoid",parent,wallPose(hall,side,along,1.2),true) end
        end
    elseif kind=="VaultArcade" then
        local bayHeight=h==52 and 42 or h
        local bayCount,fallbackBay=0,nil
        local walkwayAnchor
        for _,cell in ipairs({{-1,-1},{1,-1},{-1,1},{1,1}}) do
            local x=cell[1]*math.min(32,hall.Width/2-15)
            local z=cell[2]*math.min(32,hall.Depth/2-15)
            local model,pos=patterned("VaultPier",9,9,x,z)
            local onGrid=model~=nil
            if not model then model,pos=placeObstacle(ctx,parent,hall,doors,reservations,"VaultPier",9,9) end
            if pos then
                fitVaultPier(model,pos,hall.CeilingClass)
                walkwayAnchor=walkwayAnchor or pos
                if onGrid then
                    local bay=Vector3.new(hall.Center.X+cell[1]*16,hall.FloorY,
                        hall.Center.Z+cell[2]*16)
                    placeVaultBay(ctx,parent,bayHeight,
                        CFrame.new(bay+Vector3.yAxis*(hall.CeilingClass-bayHeight)))
                    bayCount+=1
                else
                    fallbackBay=fallbackBay or pos
                end
            end
        end
        if bayCount==0 and fallbackBay then
            placeVaultBay(ctx,parent,bayHeight,
                CFrame.new(fallbackBay+Vector3.yAxis*(hall.CeilingClass-bayHeight)))
        end
        local walk=reservePocket(hall,doors,24,24,reservations)
        if not walk and walkwayAnchor then
            -- The bend is walkable ground; keep it beside a pier when its
            -- obstacle reservation occupies the only open quadrant.
            walk=walkwayAnchor+Vector3.new(walkwayAnchor.X>hall.Center.X and -20 or 20,0,0)
        end
        if walk then cloneComponent(ctx,"Walkway_Bend16",parent,
            CFrame.new(walk-Vector3.new(10.7,0,10.7)),true) end
    elseif kind=="CurvedChannel" then
        local longX=hall.PoolAxis=="X"
        local longHalf=(longX and hall.Width or hall.Depth)/2
        local shortHalf=(longX and hall.Depth or hall.Width)/2
        local sign=rng:NextInteger(0,1)==0 and -1 or 1
        local sPlaced=false
        local walkwayAnchor
        if longHalf>=88 then
            -- S48 occupies 97.3 x 17.4 studs before scaling. Fit its entire
            -- collider footprint inside one quadrant, beyond the 34-wide route.
            local scale=math.min(.9,(longHalf-25)/100)
            local width,depth=100*scale,20*scale
            for _,s in ipairs({sign,-sign}) do
                local along=s*(18+width/2)
                local across=-s*(18+depth/2)
                local pos=center(hall)+(longX and Vector3.new(along,0,across)
                    or Vector3.new(across,0,along))
                local w,d=longX and width or depth,longX and depth or width
                if reserveAt(hall,doors,pos,w,d,reservations) then
                    local cf=CFrame.new(pos)*CFrame.Angles(0,longX and 0 or math.pi/2,0)
                    local model=cloneComponent(ctx,"CurveWall_S48"..suffix,parent,cf,false)
                    model:SetAttribute("Level2_Dressing",true)
                    model:SetAttribute("Level2_HorizontalScale",scale)
                    for _,p in ipairs(model:GetDescendants()) do
                        if p:IsA("BasePart") then
                            local localCF=cf:ToObjectSpace(p.CFrame)
                            p.Size=Vector3.new(p.Size.X*scale,p.Size.Y,p.Size.Z*scale)
                            p.CFrame=cf*CFrame.new(localCF.Position.X*scale,localCF.Position.Y,
                                localCF.Position.Z*scale)*localCF.Rotation
                        end
                    end
                    sPlaced=true
                    sign=s
                    walkwayAnchor=pos
                    break
                end
            end
        end
        local function reserveCurve(trial,scale,preferred)
            local footprint=20*scale -- exported Q16 footprint is 17.6 x 17.6
            for _,sx in ipairs({preferred,-preferred}) do
                for _,sz in ipairs({-preferred,preferred}) do
                    for dx=6+footprint/2,hall.Width/2,2 do
                        for dz=6+footprint/2,hall.Depth/2,2 do
                            local pos=Vector3.new(sx>0 and hall.MaxX-dx or hall.MinX+dx,
                                hall.FloorY,sz>0 and hall.MaxZ-dz or hall.MinZ+dz)
                            if reserveAt(hall,doors,pos,footprint,footprint,trial,6,0) then
                                return {Position=pos,Scale=scale,Footprint=footprint}
                            end
                        end
                    end
                end
            end
            return nil
        end
        local options=sPlaced and {{1},{.8},{.6},{.4},{.3}}
            or {{1,.65},{.8,.8},{.6,.6},{.4,.4},{.3,.3}}
        local curves
        for _,scales in ipairs(options) do
            local trial=table.clone(reservations)
            local found={}
            for i,scale in ipairs(scales) do
                local q=reserveCurve(trial,scale,i==1 and sign or -sign)
                if not q then break end
                table.insert(found,q)
            end
            if #found==#scales then curves=found; break end
        end
        assert(curves,"[Level 2 Kit] no safe curved partition pair in "..hall.Id)
        for i,q in ipairs(curves) do
            table.insert(reservations,{Position=q.Position,Width=q.Footprint,Depth=q.Footprint})
            -- Rotate alternating quarter arcs around their exported footprint
            -- centre, then shrink horizontally only when a hall is crowded.
            local base=CFrame.new(q.Position)*CFrame.Angles(0,i%2==0 and math.pi or 0,0)
            local cf=base*CFrame.new(-8.8,0,-8.8)
            local model=cloneComponent(ctx,"CurveWall_Q16"..suffix,parent,cf,false)
            model:SetAttribute("Level2_Dressing",true)
            model:SetAttribute("Level2_HorizontalScale",q.Scale)
            if q.Scale<1 then
                for _,p in ipairs(model:GetDescendants()) do
                    if p:IsA("BasePart") then
                        local localCF=base:ToObjectSpace(p.CFrame)
                        p.Size=Vector3.new(p.Size.X*q.Scale,p.Size.Y,p.Size.Z*q.Scale)
                        p.CFrame=base*CFrame.new(localCF.Position.X*q.Scale,localCF.Position.Y,
                            localCF.Position.Z*q.Scale)*localCF.Rotation
                    end
                end
            end
            walkwayAnchor=q.Position
        end
        local walk=reservePocket(hall,doors,24,24,reservations)
        if not walk then
            -- The bend is walkable ground. Keep it alongside the partition
            -- when the only safe obstacle pocket is already occupied.
            walk=walkwayAnchor+Vector3.new(walkwayAnchor.X>hall.Center.X and -20 or 20,0,0)
        end
        cloneComponent(ctx,"Walkway_Bend16",parent,CFrame.new(walk-Vector3.new(10.7,0,10.7)),false)
    elseif kind=="SpiralWell" then
        local model,pos,scale
        for _,footprint in ipairs({40,32,26,20,16}) do
            pos=reservePocket(hall,doors,footprint,footprint,reservations)
            if pos then
                scale=math.min(1,(footprint-2)/32)
                local cf=CFrame.new(pos)
                model=cloneComponent(ctx,"SpiralStairWell"..suffix,parent,cf,false)
                model:SetAttribute("Level2_Dressing",true)
                model:SetAttribute("Level2_HorizontalScale",scale)
                if scale<1 then
                    for _,p in ipairs(model:GetDescendants()) do
                        if p:IsA("BasePart") then
                            local localCF=cf:ToObjectSpace(p.CFrame)
                            p.Size=Vector3.new(p.Size.X*scale,p.Size.Y,p.Size.Z*scale)
                            p.CFrame=cf*CFrame.new(localCF.Position.X*scale,localCF.Position.Y,localCF.Position.Z*scale)*localCF.Rotation
                        end
                    end
                end
                break
            end
        end
        assert(pos,"[Level 2 Kit] no clear spiral well in "..hall.Id)
        table.insert(openings,openSky(ctx,parent,hall,pos,12*scale,"SpiralWell",32*scale))
        for _=1,2 do placeObstacle(ctx,parent,hall,doors,reservations,"Column_D10"..suffix,14,14) end
    elseif kind=="CorridorHall" then
        local longX=hall.Width>=hall.Depth
        local half=longX and hall.Width/2 or hall.Depth/2
        for at=-half+24,half-24,24 do
            local p=center(hall)+(longX and Vector3.new(at,0,-hall.Depth/2+12)
                or Vector3.new(-hall.Width/2+12,0,at))
            if reserveAt(hall,doors,p,8,8,reservations,7) then
                local model=cloneComponent(ctx,"VaultPier",parent,CFrame.new(p),false)
                model:SetAttribute("Level2_Dressing",true)
                fitVaultPier(model,p,hall.CeilingClass)
            end
        end
    elseif kind=="PaddlingRoom" then
        for _=1,2 do placeObstacle(ctx,parent,hall,doors,reservations,"Column_D6_H34",10,10) end
    end
    if kind=="PumpHall" or hall.PumpIndex then
        local p=center(hall)
        cloneComponent(ctx,"LightWell_R6",parent,CFrame.new(p+Vector3.yAxis*(hall.CeilingClass-8)),false)
        table.insert(openings,openSky(ctx,parent,hall,p,6,"PumpHall",24))
    elseif kind=="ExitHall" then
        local p=center(hall)+Vector3.new(76,0,-69.25)
        cloneComponent(ctx,"ExitSkylight",parent,CFrame.new(p),false)
        table.insert(openings,openSky(ctx,parent,hall,p,14,"ExitHall",32))
    elseif kind~="BigPool" and kind~="Arrival" and kind~="SpiralWell" then
        local p=reservePocket(hall,doors,36,36,reservations) or center(hall)
        cloneComponent(ctx,"LightWell_R6",parent,CFrame.new(p+Vector3.yAxis*(hall.CeilingClass-8)),false)
        table.insert(openings,openSky(ctx,parent,hall,p,6,"LightWell",24))
    end
    if kind~="Arrival" and kind~="ExitHall" then
        local side=hall.Width>=hall.Depth and "South" or "East"
        local along=side=="South" and hall.Center.X+hall.Width*.25 or hall.Center.Z+hall.Depth*.25
        local clear=true
        for _,d in ipairs(doors[side]) do if math.abs(along-d.Cross)<d.Width/2+10 then clear=false end end
        if clear then cloneComponent(ctx,"WallVoid",parent,wallPose(hall,side,along,1.2)
            *CFrame.new(0,hall.CeilingClass*.6,0),true) end
    end
    if kind~="Arrival" and kind~="PumpHall" and kind~="ExitHall" then
        local count=math.min(4,math.floor(hall.Area/1500))
        for i=1,count do
            local p
            if kind=="CorridorHall" then
                local along=(i-(count+1)/2)*24
                p=center(hall)+(hall.PoolAxis=="X" and Vector3.new(along,0,0) or Vector3.new(0,0,along))
            else
                p=reservePocket(hall,doors,10,10,reservations)
            end
            if p then cloneComponent(ctx,"DrainHole",parent,CFrame.new(p-Vector3.yAxis*.7),true) end
        end
    end
    return openings
end

local function makeKids(ctx,parent,hall,doors,reservations)
    if hall.PumpIndex then table.insert(reservations,{Position=center(hall),Width=28,Depth=28}) end
    local spawn=reservePocket(hall,doors,8,8,reservations)
    assert(spawn,"[Level 2 Kit] no safe 8x8 Pool Foam pocket in "..hall.Id)
    local p=marker(ctx.entity,"Level 2 Pool Foam Spawn "..hall.Index,spawn+Vector3.yAxis*2)
    attributes(p,{Level2_HallId=hall.Id,Level2_HallIndex=hall.Index,Level2_KidsIndex=hall.KidsIndex or 0,Level2_PoolFoamSpawn=true})
    p:SetAttribute("Level2_SpawnPocketSize",Vector3.new(8,8,8))
    attributes(parent,{Level2_ContainsPump=hall.PumpIndex~=nil,Level2_PlayArchetype="PaddlingRoom",
        Level2_CoreSetPiecePlaced=true,Level2_CoreSizeTier="Poolrooms"})
end

local buildTube

-- Small prefab socket plugs: compare the fresh rotated world positions with
-- each connected wall socket. Other plugs and authored contents stay intact.
local function makeSmall(ctx,parent,hall,doors)
    local cf=CFrame.new(center(hall))*CFrame.Angles(0,math.rad(hall.Rotation or 0),0)
    local model=cloneComponent(ctx,hall.Prefab,parent,cf,false)
    local chamberWater={Chamber_A={32,36},Chamber_B={32,52},Chamber_C={48,52},Chamber_D={24,44}}
    local waterSize=assert(chamberWater[hall.Prefab],"[Level 2 Kit] unknown escape chamber "..tostring(hall.Prefab))
    water(ctx,cf*CFrame.new(0,-.75,2),Vector3.new(waterSize[1],1.7,waterSize[2]),"Chamber "..hall.Index)
    for _,p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") and p.Name:find("Level 2 Room Curved Side",1,true) then p:Destroy() end
    end
    local w,d=model:GetAttribute("Width") or hall.Width,model:GetAttribute("Depth") or hall.Depth
    for _,sx in ipairs({-1,1}) do for _,sz in ipairs({-1,1}) do
        local seal=invisible(part(model,"Level 2 Room Corner Seal",Vector3.new(8,15,8),
            cf*CFrame.new(sx*(w/2-4),7.5,sz*(d/2-4)),"PR Tile"),true)
        seal:SetAttribute("Level2_KitComponent",hall.Prefab)
    end end
    for _,p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") and p:GetAttribute("SocketPlug") then
            for side,list in pairs(doors) do
                for _,d in ipairs(list) do
                    local across=(side=="East" or side=="West") and p.Position.Z or p.Position.X
                    local edge=(side=="East" and hall.MaxX) or (side=="West" and hall.MinX) or (side=="North" and hall.MinZ) or hall.MaxZ
                    local actual=(side=="East" or side=="West") and p.Position.X or p.Position.Z
                    if math.abs(across-d.Cross)<.1 and math.abs(actual-edge)<2 then p:Destroy(); break end
                end
            end
        end
    end
    return model
end

-- Collision pieces use the exported full frames. Only unit template geometry
-- is copied; SlideTemplates never leak as templates into the generated world.
local function slidePiece(ctx,parent,record,cf,index,name,length)
    local template=ctx.templates:FindFirstChild(record.profile)
    assert(template and template:IsA("MeshPart"),"[Level 2 Kit] missing SlideTemplates."..tostring(record.profile))
    assert(template.CollisionFidelity==Enum.CollisionFidelity.PreciseConvexDecomposition,
        "[Level 2 Kit] slide template must use PreciseConvexDecomposition: "..record.profile)
    local piece=template:Clone()
    piece.Name=(name or record.name or "Level 2 Slide Entry Support"):gsub("{i}",tostring(index))
    piece.Size, piece.CFrame=Vector3.new(record.size[1],record.size[2],length or record.size[3]),cf*frame(record.cframe)
    piece.Anchored,piece.Transparency,piece.CastShadow=true,1,false
    piece.CanCollide,piece.CanQuery,piece.CanTouch=true,true,false
    piece.CollisionGroup,piece.CustomPhysicalProperties="Default",SLIDE_PHYSICS
    attributes(piece,record.attrs)
    piece:SetAttribute("Level2_NoEntityGround",true)
    if piece:GetAttribute("Level2_SlideFloor") then piece:SetAttribute("Level2_SlideDirection",piece.CFrame.LookVector) end
    piece.Parent=parent
    return piece
end

buildTube=function(ctx,parent,key,cf,index,leadStart,skipVisual)
    local tube=assert(ctx.slides.slides[key],"[Level 2 Kit] missing slide record "..key)
    local model=container(parent,tube.model:gsub("{i}",tostring(index)),"Model")
    attributes(model,tube.attrs)
    local mouthShift=leadStart and (leadStart-vector(tube.collisionPoints[1])) or Vector3.zero
    for _,component in ipairs(skipVisual and {} or tube.visualChunks) do
        local placement=tube.visualPlacements[component]
        local visualCF=cf
        local lead=leadStart and component==tube.leadIn.visualComponent
        if lead then
            local endPoint=vector(tube.collisionPoints[2])
            visualCF=cf*CFrame.lookAt((leadStart+endPoint)/2,endPoint)
        elseif placement then visualCF=cf*frame(placement.cframe)
        elseif leadStart and (component==tube.tub.mouthComponent or component==key.."_Handles") then visualCF=cf*CFrame.new(mouthShift) end
        local before=#model:GetChildren()
        cloneComponent(ctx,component,model,visualCF,true)
        if placement and placement.scaleZ then
            for _,p in ipairs(model:GetChildren()) do
                if p:IsA("MeshPart") and p:GetAttribute("Level2_KitComponent")==component then
                    p.Size=Vector3.new(p.Size.X,p.Size.Y,p.Size.Z*(lead and (vector(tube.collisionPoints[2])-leadStart).Magnitude or placement.scaleZ))
                    -- The unit visual's own chunk offset is preserved by PivotTo.
                    if lead then p.CFrame=visualCF end
                end
            end
        end
        assert(#model:GetChildren()>before,"[Level 2 Kit] empty slide visual "..component)
    end
    for _,segment in ipairs(tube.segments) do
        for _,record in ipairs(segment.pieces) do
            local piece=slidePiece(ctx,model,record,cf,index,nil,segment.len)
            if leadStart and segment.i==1 then
                local b=vector(tube.collisionPoints[2])
                piece.CFrame=cf*CFrame.lookAt((leadStart+b)/2,b)
                piece.Size=Vector3.new(piece.Size.X,piece.Size.Y,(b-leadStart).Magnitude+tube.overlap)
                piece:SetAttribute("Level2_SlideDirection",piece.CFrame.LookVector)
            end
        end
        if segment.i%40==0 then task.wait() end
    end
    for i,record in ipairs(tube.tub and tube.tub.collisionPlacements or {}) do
        slidePiece(ctx,model,record,cf*CFrame.new(mouthShift),index,model.Name.." Entry Support "..i)
    end
    return model
end

-- The reviewed exit collision stays in SlidesJSON; Poolrooms C supplies its visible shell.
local function prefabExitPart(ctx,parent,record,cf)
    local name=record.name
    local p=part(parent,name,vector(record.size),cf*frame(record.cframe or record.cf),
        name:find("Room Wooden Door",1,true) and "PR Iron" or "PR Tile",WHITE,record.ground)
    attributes(p,record.attrs)
    for key,value in pairs(record.properties or {}) do
        if key=="CanCollide" or key=="CanQuery" or key=="CanTouch" or key=="Transparency" or key=="CastShadow" then
            p[key]=value
        end
    end
    if p:GetAttribute("Level2_SlideCollision") then
        invisible(p,true)
        p.CustomPhysicalProperties=SLIDE_PHYSICS
        p:SetAttribute("Level2_NoEntityGround",true)
        if p:GetAttribute("Level2_SlideFloor") then p:SetAttribute("Level2_SlideDirection",p.CFrame.LookVector) end
    end
    if p.Name:find("Roof",1,true) or p.Name:find("Overhead Tile",1,true) then roof(p) end
    return p
end

local function makeExit(ctx,parent,hallModel,layout,hall)
    local tube=ctx.slides.slides.ExitFlume_Tube
    assert(tube and tube.anchor and tube.pathPoints and tube.recycle,"[Level 2 Kit] incomplete ExitFlume_Tube record")
    assert((hall.Rotation or 0)==0,"[Level 2 Kit] exit helix must not rotate")
    local deckZ=hall.Center.Z-79.25
    local anchor=Vector3.new(layout.Bounds.MaxX-19,hall.FloorY+83.3,deckZ)
    local cf=CFrame.new(anchor)
    local start=Vector3.new(hall.MaxX-14,hall.FloorY+83.3,deckZ)
    local localStart=start-anchor
    assert(localStart.X<-.1,"[Level 2 Kit] exit lead-in must travel east")
    local platformCF=CFrame.new(hall.MaxX-36,hall.FloorY,deckZ+10)
    cloneComponent(ctx,"ExitPlatform",hallModel,platformCF,false)
    cloneComponent(ctx,"ExitSpiral",hallModel,platformCF,false)
    local model=container(parent,"Level 2 Exit Flume","Model")
    model:PivotTo(cf)
    model.ModelStreamingMode=Enum.ModelStreamingMode.Persistent
    attributes(model,tube.attrs)
    for _,record in ipairs(ctx.slides.prefabParts.ExitFlume) do prefabExitPart(ctx,model,record,cf) end
    local mouthModel=cloneComponent(ctx,"ExitMouth",model,platformCF,false)
    local mouth
    for _,p in ipairs(mouthModel:GetDescendants()) do
        if p:IsA("MeshPart") then mouth=p; break end
    end
    assert(mouth,"[Level 2 Kit] ExitMouth lacks its recolorable MeshPart")
    for i=1,5 do
        cloneComponent(ctx,i==1 and "ExitTubeVisual" or "ExitTubeVisual_0"..i,model,cf,true)
    end
    -- The export's first visual has a fixed 25-stud lead; bridge the extra
    -- 3.5 studs on the wider inset without covering the slide detection floor.
    local visualStart=anchor.X-25
    local mouthEnd=hall.MaxX-7.5
    if visualStart>mouthEnd+.05 then
        local run=visualStart-mouthEnd
        for _,panel in ipairs({
            {"Floor",Vector3.new(run,.35,12.4),Vector3.new(0,-7.55,0)},
            {"Top",Vector3.new(run,.35,12.4),Vector3.new(0,7.55,0)},
            {"Left",Vector3.new(run,14.4,.35),Vector3.new(0,0,-7.55)},
            {"Right",Vector3.new(run,14.4,.35),Vector3.new(0,0,7.55)}
        }) do
            local p=part(model,"Level 2 Exit Lead Tile "..panel[1],panel[2],
                CFrame.new((visualStart+mouthEnd)/2,start.Y,start.Z)*CFrame.new(panel[3]),"PR Tile")
            p.CanCollide,p.CanQuery=false,false
        end
    end
    local built=buildTube(ctx,model,"ExitFlume_Tube",cf,hall.SlideHallIndex,localStart,true)
    for _,child in ipairs(built:GetChildren()) do child.Parent=model end
    built:Destroy()
    local shift=localStart-vector(tube.collisionPoints[1])
    local entry=model:FindFirstChild("Level 2 Exit Flume Entry Collision Floor")
    assert(entry,"[Level 2 Kit] missing exit entry floor")
    entry.CFrame+=shift
    local points={}
    for i,p in ipairs(tube.pathPoints) do points[i]=anchor+vector(p) end
    points[1]=start
    local r=tube.recycle
    local recycle={DeltaY=r.DeltaY,Radius=r.Radius,Turns=r.Turns,CenterX=anchor.X+r.CenterX,CenterZ=anchor.Z+r.CenterZ,
        TopY=anchor.Y+r.TopY,BottomY=anchor.Y+r.BottomY,TriggerY=anchor.Y+r.TriggerY,LandingY=anchor.Y+r.LandingY}
    attributes(model,{Level2_RecycleActive=true,Level2_RecycleTriggerY=recycle.TriggerY,Level2_RecycleDeltaY=recycle.DeltaY,
        Level2_HelixCenterX=recycle.CenterX,Level2_HelixCenterZ=recycle.CenterZ,Level2_HelixRadius=recycle.Radius,
        Level2_HelixTopY=recycle.TopY,Level2_HelixBottomY=recycle.BottomY,Level2_FlumeBoreRadius=tube.r})
    local minimum,maximum=points[1],points[1]
    for _,p in ipairs(points) do
        minimum=Vector3.new(math.min(minimum.X,p.X),math.min(minimum.Y,p.Y),math.min(minimum.Z,p.Z))
        maximum=Vector3.new(math.max(maximum.X,p.X),math.max(maximum.Y,p.Y),math.max(maximum.Z,p.Z))
    end
    assert(recycle.BottomY>workspace.FallenPartsDestroyHeight+40,"[Level 2 Kit] exit too low for FallenPartsDestroyHeight")
    local function required(name) return assert(model:FindFirstChild(name,true),"[Level 2 Kit] missing "..name) end
    local trigger,backstop=required("Level 2 Exit Completion Beam"),required("Level 2 Exit Completion Backstop")
    invisible(trigger,false); invisible(backstop,false)
    local safe=required("Level 2 Exit Safe Spawn")
    invisible(safe,false)
    roof(required("Level 2 Recovery Chamber Overhead Tile"))
    return {Trigger=trigger,Backstop=backstop,SafeSpawn=safe,Mouth=mouth,
        EndPosition=required("Level 2 Exit Room Wooden Door").Position,StartPoint=start,RoomEntry=points[tube.plungeEndIndex],
        RoomFloorTop=anchor.Y+tube.pathPoints[tube.plungeEndIndex][2]-tube.r*.9,
        Door=required("Level 2 Exit Room Wooden Door"),TransitionStart=anchor+vector(tube.TransitionStart),
        TransitionEnd=points[#points],TransitionLength=tube.TransitionLength,FlumeBoundsCenter=(minimum+maximum)/2,
        FlumeBoundsSize=maximum-minimum+Vector3.one*(tube.r+24)*2,FlumeModel=model,PathPoints=points,BoreRadius=tube.r,Recycle=recycle,
        HallWallGap={center=deckZ,width=18.5,bottom=start.Y-9.25,top=start.Y+9.25}}
end

local function corridorComponent(components,c)
    local requested=(c.Kind=="Narrow" and "Pipe_" or "RoundTunnel_")..c.Variant.."_"..c.Length
    if components:FindFirstChild(requested) then return requested,requested end
    return requested,nil
end

local function makeCorridor(ctx,parent,c)
    local narrow=c.Kind=="Narrow"
    local component,source=corridorComponent(ctx.components,c)
    assert(source,"[Level 2 Kit] layout requests unavailable Components."..component)
    local descending=c.ToY<c.FromY
    local yaw=c.Axis=="X" and 90 or 0
    if descending then yaw+=180 end
    local pos=c.Axis=="X" and Vector3.new((c.From+c.To)/2,math.min(c.FromY,c.ToY),c.Cross)
        or Vector3.new(c.Cross,math.min(c.FromY,c.ToY),(c.From+c.To)/2)
    local cf=CFrame.new(pos)*CFrame.Angles(0,math.rad(yaw),0)
    local model,markers=cloneComponent(ctx,source,parent,cf,false)
    model.Name="Level 2 Corridor "..c.Index
    model:SetAttribute("Level2_CorridorIndex",c.Index)
    local rise=math.abs(c.FromY-c.ToY)
    if rise>0 then
        local crown=narrow and 12 or 30
        local width=narrow and 12 or 34
        local roofName=narrow and "Level 2 Passage Stair Roof Collider" or "Level 2 Corridor Stair Roof Collider"
        -- The kit's stair bore climbs evenly from mouth to mouth; the collars
        -- are flat and capped by the kit itself.
        local run=c.Length
        local ramp=part(model,roofName.." Ramp",Vector3.new(width,2,math.sqrt(run*run+rise*rise)+.1),
            cf*CFrame.new(0,crown+rise/2+1,0)*CFrame.Angles(-math.atan(rise/run),0,0),"PR Tile")
        roof(invisible(ramp,true))
    end
    for _,p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") and p.Name:find("Roof",1,true) then
            p.Name=(narrow and "Level 2 Passage Roof Collider " or "Level 2 Corridor Roof Collider ")..c.Index
        end
    end
    local lampMarker=findMarker(markers,"LampLight")
    assert(lampMarker,"[Level 2 Kit] missing LampLight marker in "..component)
    local lightPosition=lampMarker.CFrame.Position
    local emitter=marker(model,"Level 2 Corridor Vault Light "..c.Index,lightPosition,Vector3.new(1.2,.4,1.2))
    if not narrow or ctx.narrowLights<ctx.narrowLightBudget then
        local light=addLight(ctx,emitter,"PointLight",lampMarker.Attributes.Brightness,lampMarker.Attributes.Range)
        light.Color=Color3.fromRGB(245,232,207)
        if narrow then ctx.narrowLights+=1 end
    end
    local record={Corridor=c,Center=pos,Model=model}
    if c.Variant=="Wet" or (narrow and c.Variant=="Flat") then
        record.Water=water(ctx,cf*CFrame.new(0,narrow and .75 or -.7,0),
            Vector3.new(narrow and 6.55 or 13.6,narrow and .7 or 1.6,c.Length),"Corridor "..c.Index)
    end
    if c.Kind=="PressureDoor" then
        local doorPos=c.Axis=="X" and Vector3.new(c.To,c.ToY+14,c.Cross) or Vector3.new(c.Cross,c.ToY+14,c.To)
        local size=c.Axis=="X" and Vector3.new(2.2,36,34) or Vector3.new(34,36,2.2)
        local door=part(ctx.doors,"Level 2 Pressure Door "..c.Index,size,CFrame.new(doorPos),"PR Iron",LOCKED,true)
        door:SetAttribute("Level2_CorridorIndex",c.Index)
        local stripeSize=c.Axis=="X" and Vector3.new(2.4,1.2,30) or Vector3.new(30,1.2,2.4)
        local stripe=part(ctx.doors,"Level 2 Pressure Door Stripe "..c.Index,stripeSize,
            CFrame.new(doorPos+Vector3.yAxis*4),"PR Iron",LOCKED)
        stripe.CanCollide,stripe.CanQuery=false,false
        stripe.Material=Enum.Material.Neon
        record.Door,record.Stripe=door,stripe
    end
    return record
end

-- The authored shell replaces the old 77-instance cabinet, while the controls
-- keep the exact fields and moving parts consumed by Objective Controller.
local function shuffledLeverHandleColors(seed,generation)
    local palette={
        {Name="Green",Color=Configuration.SlideColors[1]},
        {Name="Red",Color=Configuration.SlideColors[2]},
        {Name="Yellow",Color=Configuration.SlideColors[3]},
        {Name="Blue",Color=Configuration.SlideColors[4]},
    }
    local mixed=math.floor(math.abs((tonumber(seed) or 1)+(tonumber(generation) or 0)*104729))%2147483646
    local rng=Random.new(math.max(1,mixed))
    for i=#palette,2,-1 do
        local j=rng:NextInteger(1,i)
        palette[i],palette[j]=palette[j],palette[i]
    end
    return palette
end

local function weldTo(root,child)
    child.Anchored,child.Massless=false,true
    local weld=Instance.new("WeldConstraint")
    weld.Name="Level 2 Pump Control Weld"
    weld.Part0,weld.Part1,weld.Parent=root,child,root
end

local function makePumpStation(ctx,hall,index,handleSpec)
    local c=center(hall)
    local model=container(ctx.objectives,"Level 2 Pump Station "..index,"Model")
    model:PivotTo(CFrame.new(c))
    model.ModelStreamingMode=Enum.ModelStreamingMode.Persistent
    attributes(model,{Level2_PumpIndex=index,Level2_HallId=hall.Id,Level2_InKidsArea=hall.Role=="Kids Area",
        Level2_LeverHandleColor=handleSpec.Name,Level2_LeverHandleColorValue=handleSpec.Color,
        Level2_PressurePercent=0,Level2_PressureRestored=false,Level2_PumpRunning=false})
    cloneComponent(ctx,"PumpStation",model,CFrame.new(c),true)
    local shell=assert(model:FindFirstChild("Level 2 Pump Body Collider"),"[Level 2 Kit] PumpStation lacks body collider")
    model.PrimaryPart=shell
    local intake=model:FindFirstChild("Level 2 Pump Intake Pipe")
    assert(intake,"[Level 2 Kit] PumpStation lacks intake pipe")
    for _,p in ipairs(model:GetChildren()) do
        if p.Name=="Level 2 Pump Intake Pipe" then p.CanQuery=false end
    end
    local gaugeFace=assert(model:FindFirstChild("Level 2 Pump Pressure Gauge Face"))
    gaugeFace.CanQuery=false
    local statusRing=assert(model:FindFirstChild("Level 2 Pump Lever Status Ring"))
    statusRing.Color,statusRing.Shape=LOCKED,Enum.PartType.Cylinder
    statusRing.Size=Vector3.new(.12,.95,.95)
    statusRing.CFrame*=CFrame.Angles(0,math.pi/2,0)
    statusRing.CanCollide,statusRing.CanQuery=false,false
    local leverAssembly=container(model,"Level 2 Pump Lever Assembly","Model")
    attributes(leverAssembly,{Level2_LeverHandleColor=handleSpec.Name,Level2_LeverHandleColorValue=handleSpec.Color})
    local leverModel=cloneComponent(ctx,"PumpLever",leverAssembly,CFrame.new(c),false)
    local lever=assert(leverModel:FindFirstChild("Level 2 Pump Lever Animated Pivot"))
    local grip=assert(leverModel:FindFirstChild("Level 2 Pump Lever Colored Plastic Grip"))
    for _,p in ipairs(leverModel:GetDescendants()) do
        if p:IsA("BasePart") and p~=lever then weldTo(lever,p) end
    end
    lever.Transparency,lever.CanCollide,lever.CanQuery=1,false,false
    lever.CFrame*=CFrame.Angles(math.rad(38),0,0)
    leverAssembly.PrimaryPart=lever
    grip.Color,grip.CanQuery=handleSpec.Color,true
    local prompt=Instance.new("ProximityPrompt")
    prompt.Name,prompt.ActionText,prompt.ObjectText="Level 2 Pump Prompt","START PUMP","Pump station "..index
    prompt.HoldDuration,prompt.MaxActivationDistance,prompt.RequiresLineOfSight=1.6,10,true
    prompt.Parent=grip
    local needleModel=cloneComponent(ctx,"PumpNeedle",model,CFrame.new(c),false)
    local gaugeNeedlePivot=assert(needleModel:FindFirstChild("Level 2 Pump Pressure Gauge Needle Pivot"))
    local gaugeNeedle=assert(needleModel:FindFirstChild("Level 2 Pump Pressure Gauge Needle"))
    weldTo(gaugeNeedlePivot,gaugeNeedle)
    gaugeNeedlePivot.Transparency,gaugeNeedlePivot.CanCollide,gaugeNeedlePivot.CanQuery=1,false,false
    gaugeNeedlePivot.CFrame*=CFrame.Angles(0,0,math.rad(65))
    gaugeNeedle.Material=Enum.Material.Neon
    local gaugePressureValue=Instance.new("NumberValue")
    gaugePressureValue.Name,gaugePressureValue.Value,gaugePressureValue.Parent="Level 2 Pump Pressure Value",0,model
    local gui=Instance.new("SurfaceGui")
    gui.Name,gui.Face,gui.Parent="Level 2 Pump Pressure Gauge Surface",Enum.NormalId.Back,gaugeFace
    local gaugePressureText=Instance.new("TextLabel")
    gaugePressureText.Name,gaugePressureText.Text,gaugePressureText.TextScaled="Level 2 Pump Pressure Percent","0%",true
    gaugePressureText.Size=UDim2.fromScale(1,.5)
    gaugePressureText.Position=UDim2.fromScale(0,.5)
    gaugePressureText.BackgroundTransparency=1
    gaugePressureText.TextColor3=LOCKED
    gaugePressureText.Parent=gui
    local lampModel=cloneComponent(ctx,"PumpLamp",model,CFrame.new(c),false)
    local lamp=assert(lampModel:FindFirstChild("Level 2 Pump Status Lamp"))
    lamp.Color,lamp.Material,lamp.Shape=LOCKED,Enum.Material.Neon,Enum.PartType.Cylinder
    lamp.Size=Vector3.new(.05,.38,.38)
    lamp.CFrame*=CFrame.Angles(0,math.pi/2,0)
    lamp.CanCollide,lamp.CanQuery=false,false
    local lampGlow=addLight(ctx,lamp,"PointLight",.294,12)
    lampGlow.Color=LOCKED
    return {Index=index,Model=model,Prompt=prompt,Lamp=lamp,LampGlow=lampGlow,Lever=lever,
        LeverAssembly=leverAssembly,LeverHandle=grip,LeverStatusRing=statusRing,LeverRestCFrame=lever.CFrame,
        GaugeNeedlePivot=gaugeNeedlePivot,GaugeNeedle=gaugeNeedle,
        GaugeNeedleZeroCFrame=gaugeNeedlePivot.CFrame,
        GaugeNeedleFullCFrame=gaugeNeedlePivot.CFrame*CFrame.Angles(0,0,math.rad(-130)),
        GaugePressureValue=gaugePressureValue,GaugePressureText=gaugePressureText,Housing=shell}
end

local function makeArrival(ctx,parent,hall,layout)
    local concourse=container(parent,"Level 2 Arrival Concourse","Model")
    local direction=Vector3.zAxis
    for _,c in ipairs(layout.Corridors) do
        if c.A==hall.Index or c.B==hall.Index then
            local other=layout.Halls[c.A==hall.Index and c.B or c.A]
            local delta=other.Center-hall.Center
            direction=math.abs(delta.X)>=math.abs(delta.Z) and Vector3.new(math.sign(delta.X),0,0) or Vector3.new(0,0,math.sign(delta.Z))
            break
        end
    end
    local back=center(hall)-direction*((math.abs(direction.X)>.5 and hall.Width or hall.Depth)/2-.8)
    local spawnPosition=back+direction*5.5
    local apronCenter=spawnPosition+direction*15
    local apronCF=CFrame.lookAt(apronCenter,apronCenter+direction)
    part(concourse,"Level 2 Arrival Clear Apron",Vector3.new(32,1,30),apronCF*CFrame.new(0,-.48,0),"PR Tile",WHITE,true)
    local gateCF=CFrame.lookAt(back,back+direction)
    cloneComponent(ctx,"ArrivalDoor",concourse,gateCF,true)
    local result={}
    local cf=CFrame.lookAt(spawnPosition+Vector3.yAxis*.1,spawnPosition+Vector3.yAxis*.1+direction)
    result.ArrivalSpawn=marker(ctx.world,"Level 2 Arrival Spawn",cf.Position+Vector3.yAxis*.2,Vector3.new(9,.4,9))
    result.ArrivalSpawn.CFrame=cf*CFrame.new(0,.2,0)
    result.Elevator=container(workspace,"Elevator","Model")
    result.Elevator:SetAttribute("Level2_CompatibilityMarker",true)
    table.insert(ctx.compatibility,result.Elevator)
    local shell=marker(result.Elevator,"Level 2 Arrival Elevator Shell",center(hall)+Vector3.yAxis*5,Vector3.new(18,10,18))
    result.Elevator.PrimaryPart=shell
    for _,side in ipairs({-1,1}) do marker(result.Elevator,side<0 and "DoorL" or "DoorR",center(hall)+Vector3.new(side*4.5,5,8.8),Vector3.new(8.5,10,.6)) end
    for name,p in pairs({MazeStart=center(hall)+Vector3.yAxis*.2,ElevatorSpawn=cf.Position,EntityStart=center(layout.EntityDen)+Vector3.yAxis*4}) do
        result[name]=marker(workspace,name,p,name=="ElevatorSpawn" and Vector3.new(7,.2,7) or Vector3.new(4,.2,4))
        result[name]:SetAttribute("Level2_CompatibilityMarker",true)
        table.insert(ctx.compatibility,result[name])
    end
    result.ElevatorSpawn.CFrame=cf
    return result
end

local function nodes(ctx,hall)
    local c=center(hall)
    local node=marker(ctx.navigation,"Level 2 Navigation Node "..hall.Index,c+Vector3.yAxis,Vector3.new(2,.2,2))
    attributes(node,{Level2_HallId=hall.Id,Level2_Role=hall.Role})
    for i,sign in ipairs({{-1,-1},{1,-1},{-1,1},{1,1}}) do
        local patrol=marker(ctx.entity,"Level 2 Entity Patrol Node "..hall.Index.."."..i,c+Vector3.new(sign[1]*hall.Width*.32,2,sign[2]*hall.Depth*.32))
        patrol:SetAttribute("Level2_HallId",hall.Id)
    end
end

local function buildWorld(ctx,generation)
    local layout=ctx.layout
    local world=container(workspace,"Level 2 Generated World","Model"); ctx.world=world
    attributes(world,{Level2_Seed=layout.Seed,Level2_Generation=generation,Level2_GenerationAttempt=layout.Attempt,
        Level2_Theme="Poolrooms",Level2_KitBuild=ctx.kit:GetAttribute("KitBuild")})
    if workspace:GetAttribute("Level2BlenderPreviewActive")==true then
        attributes(world,{Level2_PoolroomsPreview=true,Level2_PoolroomsAmbient=Color3.fromRGB(70,170,150)})
    end
    local geometry=container(world,"Level 2 Geometry")
    local halls=container(geometry,"Level 2 Halls")
    local corridors=container(geometry,"Level 2 Corridors")
    local kids=container(geometry,"Level 2 Kids Wing")
    local objectives=container(world,"Level 2 Objectives"); ctx.objectives=objectives
    ctx.doors=container(objectives,"Level 2 Pressure Doors")
    ctx.lighting=container(world,"Level 2 Lighting")
    ctx.navigation=container(world,"Level 2 Navigation")
    ctx.entity=container(world,"Level 2 Entity Nodes")
    local byHall=hallDoors(layout)
    local exit
    for i,h in ipairs(layout.Halls) do
        ctx.hallIndex=h.Index
        local hallModel
        if h.Role=="Small" then hallModel=makeSmall(ctx,halls,h,byHall[h.Index])
        else hallModel=container(h.Role=="Kids Area" and kids or halls,h.Id.." "..h.Type,"Model") end
        hallModel.Name=h.Id.." "..h.Type
        attributes(hallModel,{Level2_HallId=h.Id,Level2_HallIndex=h.Index,Level2_Role=h.Role,Level2_PoolType=h.PoolType,
            Level2_Archetype=h.Archetype,Level2_PoolroomsType=h.Type,Level2_GraphDepth=h.GraphDepth,Level2_Height=h.CeilingClass,
            Level2_FloorY=h.FloorY,Level2_PumpIndex=h.PumpIndex or 0})
        if h.Role~="Small" then
            if h.Type=="ExitHall" then exit=makeExit(ctx,geometry,hallModel,layout,h) end
            floorShell(ctx,hallModel,h)
            local reservations={}
            if h.Role=="Kids Area" then makeKids(ctx,hallModel,h,byHall[h.Index],reservations) end
            for _,side in ipairs({"West","East","North","South"}) do wallShell(ctx,hallModel,h,side,byHall[h.Index][side],h.IsGrand and side=="East" and exit.HallWallGap or nil) end
            cornerCoves(ctx,hallModel,h)
            placeWalkways(ctx,hallModel,h,byHall[h.Index])
            local openings=dressHall(ctx,hallModel,h,byHall[h.Index],reservations)
            ceilingShell(ctx,hallModel,h,openings)
        end
        nodes(ctx,h)
        if i%4==0 then task.wait() end
    end
    ctx.narrowLightBudget=math.max(0,80-ctx.tunnelCount-3-ctx.lights)
    local records,drains,pressure={}, {}, {}
    for i,c in ipairs(layout.Corridors) do
        local record=makeCorridor(ctx,corridors,c)
        records[c.Index]=record
        if c.DrainGroup then assert(record.Water,"[Level 2 Kit] drain corridor has no water"); drains[c.DrainGroup]=record end
        if record.Door then table.insert(pressure,record) end
        if i%2==0 then task.wait() end
    end
    local pumps={}
    local colors=shuffledLeverHandleColors(layout.Seed,generation)
    for i,h in ipairs(layout.PumpHalls) do pumps[i]=makePumpStation(ctx,h,i,colors[i]); pumps[i].Hall=h end
    local arrival=makeArrival(ctx,geometry,layout.Arrival,layout)
    local den=marker(ctx.entity,"Level 2 Entity Den A Spawn",center(layout.EntityDen)+Vector3.yAxis*3,Vector3.new(10,.4,10))
    den:SetAttribute("Level2_HallId",layout.EntityDen.Id)
    ctx.entity:SetAttribute("Level2_DenAPosition",center(layout.EntityDen))
    if layout.EntityDenB then
        local denB=marker(ctx.entity,"Level 2 Entity Den B Spawn",center(layout.EntityDenB)+Vector3.yAxis*3,Vector3.new(10,.4,10))
        denB:SetAttribute("Level2_HallId",layout.EntityDenB.Id)
        ctx.entity:SetAttribute("Level2_DenBPosition",center(layout.EntityDenB))
    end
    local bounds=layout.Bounds
    local terrainCenter=Vector3.new((bounds.MinX+bounds.MaxX)/2,-16,(bounds.MinZ+bounds.MaxZ)/2)
    local extent=math.max(bounds.MaxX-bounds.MinX,bounds.MaxZ-bounds.MinZ)
    local terrainSize=Vector3.new(extent+700,200,extent+700)
    attributes(world,{Level2_TerrainCenter=terrainCenter,Level2_TerrainSize=terrainSize,Level2_HallCount=#layout.Halls,
        Level2_CorridorCount=#layout.Corridors,Level2_KidsRoomCount=#layout.KidsArea,Level2_SlideHallCount=#layout.SlideHalls})
    local yieldAt=os.clock()+.008
    for _,p in ipairs(world:GetDescendants()) do
        if p:IsA("BasePart") and p.Name:find("Roof",1,true) then roof(p) end
        if os.clock()>=yieldAt then task.wait(); yieldAt=os.clock()+.008 end
    end
    world:SetAttribute("Level2_WorldDescendants",#world:GetDescendants())
    world:SetAttribute("Level2_KitLightCount",ctx.lights)
    return {World=world,Layout=layout,Pumps=pumps,PressureDoors=pressure,Drains=drains,Corridors=records,Exit=assert(exit,"[Level 2 Kit] no grand hall exit"),
        Arrival=arrival,EntityDen=den,EntityNodes=ctx.entity,Navigation=ctx.navigation,WaterRegions=ctx.waterRegions,
        PreviousWaterAppearance=ctx.previousWater,TerrainCenter=terrainCenter,TerrainSize=terrainSize,Generation=generation}
end

function WorldBuilder.Build(layout,generation)
    local kit,components,templates,slides=readKit()
    assert(type(layout)=="table" and layout.Version=="kit-v1","[Level 2 Kit] Build requires a Kit Layout Generator layout")
    assert(type(generation)=="number","[Level 2 Kit] generation must be a number")
    assert(not workspace:FindFirstChild("Level 2 Generated World"),"[Level 2 Kit] Round Adapter must clean the previous world before Build")
    for _,name in ipairs({"Elevator","ElevatorSpawn","MazeStart","EntityStart"}) do
        assert(not workspace:FindFirstChild(name),"[Level 2 Kit] compatibility object already exists: "..name.."; cleanup before Build")
    end
    -- Validate all required corridor assets before writing terrain or the world.
    for _,c in ipairs(layout.Corridors) do
        local name,source=corridorComponent(components,c)
        assert(source,"[Level 2 Kit] layout requests unavailable Components."..name)
        assert(math.abs(c.FromY-c.ToY)<=8,"[Level 2 Kit] corridor height exceeds eight studs")
        if c.DrainGroup or c.Kind=="PressureDoor" then assert(c.FromY==c.ToY,"[Level 2 Kit] drain/pressure corridor must be flat") end
    end
    local tunnelCount=0
    for _,c in ipairs(layout.Corridors) do if c.Kind~="Narrow" then tunnelCount+=1 end end
    assert(tunnelCount+3<=80,"[Level 2 Kit] required tunnel/status lights exceed 80")
    local previous={WaterColor=Terrain.WaterColor,WaterTransparency=Terrain.WaterTransparency,WaterReflectance=Terrain.WaterReflectance,
        WaterWaveSize=Terrain.WaterWaveSize,WaterWaveSpeed=Terrain.WaterWaveSpeed}
    local ctx={kit=kit,components=components,templates=templates,slides=slides,layout=layout,lights=0,
        hallLightLimit=80-tunnelCount-3,tunnelCount=tunnelCount,narrowLightBudget=0,narrowLights=0,skyCount=0,
        waterRegions={},compatibility={},previousWater=previous}
    Terrain.WaterColor=Color3.fromRGB(70,170,150)
    Terrain.WaterTransparency,Terrain.WaterReflectance,Terrain.WaterWaveSize,Terrain.WaterWaveSpeed=.35,.1,.035,1.65
    local ok,result=xpcall(function() return buildWorld(ctx,generation) end,debug.traceback)
    if not ok then
        -- Adapter does not receive a manifest when Build raises. Undo only our
        -- partial world/markers/water, never an unrelated workspace object.
        if ctx.world then ctx.world:Destroy() end
        for _,object in ipairs(ctx.compatibility) do object:Destroy() end
        for _,region in ipairs(ctx.waterRegions) do Terrain:FillBlock(region.CFrame,region.Size+Vector3.one*8,Enum.Material.Air) end
        for name,value in pairs(previous) do Terrain[name]=value end
        error("[Level 2 Kit] Build failed: "..tostring(result),0)
    end
    return result
end

return WorldBuilder
