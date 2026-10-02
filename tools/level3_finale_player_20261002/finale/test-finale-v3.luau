-- Run the exact v2 scenario harness against v3 plus focused overlap-filter cases.
local fs,luau=require("@lune/fs"),require("@lune/luau")
local source=fs.readFile("tools/level3_finale_player_20261002/finale/test-finale.luau")
source=source:gsub("Level 3 Mall Manager AI Controller%.v2%.candidate%.luau","Level 3 Mall Manager AI Controller.v3.candidate.luau")
source=source:gsub("finale%-mock%-receipt%.json","finale-mock-v3-receipt.json")
local extra=[=[
check("finale overlap ignores living, dead, escaped and non-round current avatars",function()
    local living,dead,escaped,spectator=player(1,220),player(2,400),player(3,400),player(4,400)
    dead.Character.Humanoid.Health=0;escaped:SetAttribute("Escaped",true);spectator:SetAttribute("InRound",false)
    roster={living,dead,escaped,spectator}
    local params=load(ai,{"local function spawnOverlapParams"},"spawnOverlapParams",{
        Players=Players,OverlapParams={new=function() return {} end},
    })
    local records={{Character=living.Character}}
    local finale=params(records,true)
    expect(#finale.FilterDescendantsInstances==4)
    for _,p in ipairs(roster) do expect(table.find(finale.FilterDescendantsInstances,p.Character)~=nil) end
    expect(finale.RespectCanCollide==true and finale.MaxParts==1)
    local normal=params(records)
    expect(#normal.FilterDescendantsInstances==1 and normal.FilterDescendantsInstances[1]==living.Character)
end)
check("dead avatar at endpoint cannot veto finale but authored wall still blocks exact endpoint",function()
    local live,dead=player(1,220),player(2,400);dead.Character.Humanoid.Health=0
    roster={live,dead};live.Character:SetAttribute("Level3_FinalHallCrossedGeneration",17)
    local wall={};local wallPresent=false;local positions={}
    local picker=load(ai,{"local function eligibleSpawnPlayers","local function spawnOverlapParams","local function chooseFinalHallSpawn"},"chooseFinalHallSpawn",{
        Players=Players,workspace=spawnWorkspace,PlayerProtection=protection,
        OverlapParams={new=function() return {} end},stateFolder=function() return attrs() end,
        Random={new=function() return {} end},planarDistance=planar,
        insideFinalHall=function() return true end,nearestRoomId=function() return "FinalHall" end,
        spawnVisibilityCount=function() return 1 end,
        spawnVolumeFits=function(position,params)
            table.insert(positions,position)
            expect(table.find(params.FilterDescendantsInstances,dead.Character)~=nil)
            expect(table.find(params.FilterDescendantsInstances,wall)==nil)
            return not wallPresent
        end,
    })
    expect(assert(picker({FinalHall=hall},17)).Position==hall.EndPoint)
    wallPresent=true;expect(picker({FinalHall=hall},17)==nil)
    expect(#positions==2 and positions[1]==hall.EndPoint and positions[2]==hall.EndPoint)
end)
]=]
local marker="local receipt={kind="
local at=assert(source:find(marker,1,true))
source=source:sub(1,at-1)..extra..source:sub(at)
luau.load(source,{environment={require=require}})()
