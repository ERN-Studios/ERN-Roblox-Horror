-- Offline syntax and actual pure-generator/corridor fixtures.
-- Host uses Park-Miller RNG, not Roblox Random; this is no gameplay/performance pass.
local fs, luau, serde = require("@lune/fs"), require("@lune/luau"), require("@lune/serde")
local r = require("@lune/roblox")
local V, CF = r.Vector3, r.CFrame
local root = "tools/level3_promotion_20261002/public3/"
local folder = root.."layout-world-candidates/"
local names = {"Level 3 Configuration","Level 3 Layout Generator","Level 3 World Builder",
    "Level 3 Worn Party Visual Adapter","Level 3 Worn Party Room Dressing",
    "Level 3 Balloon Dressing","Level 3 Crayon Wall Art","Level 3 Round Adapter"}
local result={Scope="Offline syntax and mocked geometry only; gameplay, engine RNG, and performance unverified",
    Syntax={},Layouts={},Checks=0}
local function check(value,message) result.Checks+=1 assert(value,message) end
local function source(name) return fs.readFile(folder..name..".ModuleScript.candidate.luau") end
for _,name in ipairs(names) do
    local s=source(name)
    luau.compile(s)
    table.insert(result.Syntax,{Name=name,Bytes=#s,SHA256=serde.hash("sha256",s),Passed=true})
end
local config=luau.load(source(names[1]),{environment={Vector3=V,Color3=r.Color3}})()
local metadata=luau.load(fs.readFile(root.."layout-world-baseline/Level_6_Systems__Level_6_Kit_Metadata.luau"))()
local Random={}
function Random.new(seed)
    local state=math.floor(math.abs(seed))%2147483646+1
    local function nextUnit()
        state=(state*16807)%2147483647
        return (state-1)/2147483646
    end
    return {
        NextInteger=function(_,low,high)return low+math.floor(nextUnit()*(high-low+1))end,
        NextNumber=function(_,low,high)return(low or 0)+nextUnit()*((high or 1)-(low or 0))end,
    }
end
local genSource=source(names[2])
genSource=genSource:gsub('local Configuration = require[^\n]+','')
genSource=genSource:gsub('local KitMetadata = require[^\n]+','')
genSource=genSource:gsub('local Master = require[^\n]+','')
local generator=luau.load(genSource,{environment={Configuration=config,KitMetadata=metadata,
    Master={Overlay=function(base,namespace)check(namespace=="L3Layout","public override namespace")return base end},Random=Random}})()
check(config.WorldOrigin==V.new(6200,24,0),"public origin")
check(config.WorldName=="Level 3 Generated World" and config.StateFolderName=="Level 3 State"
    and config.RemotesFolderName=="Level 3 Remotes","public namespace")
check(config.MallManager.FinalHallSpawnProgress==.97 and config.MallManager.FinaleApproachSpeed==28,"coherent finale")
local seeds={101,7331,65537,1900813}
for index=1,100 do table.insert(seeds,104729*index+1) end
local hashes={}
for _,seed in ipairs(seeds) do
    local layout=generator.Generate(seed)
    local valid,problem=generator.Validate(layout)
    check(valid,tostring(problem))
    check(#layout.Rooms==32 and #layout.Links==37 and layout.HideSpotCount==30,"revised counts")
    check(#layout.BlenderRooms==3 and #layout.ServiceRooms==3,"authored gateways/service pockets")
    check(layout.GatewayColumns[1]~=layout.GatewayColumns[2],"distinct district bridge columns")
    check(layout.RoomById.Arrival.H==30,"tall arrival")
    check(layout.Roles.FirstCDRoomId==layout.Roles.EntryDistrictRoomId,"entry CD")
    check(layout.LayoutHash:sub(1,5)=="L3-6-","public hash prefix")
    check(generator.Generate(seed).LayoutHash==layout.LayoutHash,"seed repeatability")
    check(not hashes[layout.LayoutHash],"seed diversity") hashes[layout.LayoutHash]=true
    local record={Seed=seed,Hash=layout.LayoutHash,Attempt=layout.Attempt,Fallback=layout.UsedFallbackSeed}
    table.insert(result.Layouts,record)
end
local function fragment(s,a,b)
    local start=assert(s:find(a,1,true));local finish=assert(s:find(b,start+1,true));return s:sub(start,finish-1)
end
local builder=source(names[3])
local baseline=fs.readFile(root.."layout-world-baseline/Level_3_Systems__Level_3_World_Builder.luau")
local oldArrival=fragment(baseline,"local function makeArrivalElevator(","local function makeExitSet(")
local newArrival=fragment(builder,"local function makeArrivalElevator(","local function makeExitSet(")
check(oldArrival==newArrival,"production arrival function exact preserved")
result.ArrivalFunctionSHA256=serde.hash("sha256",newArrival)
local activeLayout
local function part(parent,name,cf,size,color,material,transparency)
    local x=r.Instance.new("Part");x.Name=name;x.CFrame=cf;x.Size=size;x.Color=color
    x.Material=material;x.Transparency=transparency or 0;x.Parent=parent;return x
end
local corridorFn=luau.load(fragment(builder,"local function makeCorridor(","local function makeModule(").."\nreturn makeCorridor",
    {environment={Configuration=config,Vector3=V,CFrame=CF,Color3=r.Color3,Enum=r.Enum,Instance=r.Instance,
        C=config.Colors,TEXTURES=config.Textures,
        roomById=function(id)return activeLayout.RoomById[id]end,
        worldPosition=function(room)return config.WorldOrigin+V.new(room.X,0,room.Z)end,
        floorStyle=function()return r.Color3.new(1,1,1),r.Enum.Material.SmoothPlastic,nil,1 end,
        usesWallpaper=function()return false end,wallColor=function()return r.Color3.new(1,1,1)end,
        part=part,texture=function()end,decorative=function()end,
        makeCorridorWallDecor=function()end,makeExitCorridorSpeaker=function()end,makeFixture=function()end}})()
local geometryRecords={}
for _,seed in ipairs({101,7331}) do
    activeLayout=generator.Generate(seed)
    local parent=r.Instance.new("Folder")
    for index,link in ipairs(activeLayout.Links) do
        local corridor=corridorFn(parent,link,index)
        check(#corridor.ScreamOpenings==2,"both spatial scream openings")
        check(#corridor.Segments==(if link.BlenderRoom then 2 else 1),"actual corridor stub count")
        if link.BlenderRoom then
            local first,last=link.BlenderRoom.StartDistance,link.BlenderRoom.StartDistance+link.BlenderRoom.Length
            for _,object in ipairs(corridor.Model:GetChildren()) do
                if object:IsA("BasePart") then
                    local projected=(object.CFrame.Position-corridor.StartPoint):Dot(corridor.Forward)
                    local halfLength=if math.abs(corridor.Forward.X)>.5 then object.Size.X*.5 else object.Size.Z*.5
                    check(projected+halfLength<=first+.001 or projected-halfLength>=last-.001,"no stub collider crosses authored room")
                end
            end
        end
        if link.Door=="HiddenExit" then check(math.abs(corridor.Length-560)<.001,"public finale length") end
    end
    table.insert(geometryRecords,{Seed=seed,Corridors=#activeLayout.Links,Passed=true})
    parent:Destroy()
end
result.Corridors=geometryRecords
result.Passed=true
fs.writeFile(root.."layout-world-test-receipt-v2.json",serde.encode("json",result,true).."\n")
print(serde.encode("json",{Passed=true,Checks=result.Checks,Syntax=#result.Syntax,Layouts=#result.Layouts,CorridorSeeds=2},true))
