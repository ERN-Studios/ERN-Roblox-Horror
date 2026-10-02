-- Executes exact candidate functions/blocks against deterministic dependency mocks.
-- This is not Studio physics, transport, navigation, rendering, or performance proof.
local fs, luau, serde = require("@lune/fs"), require("@lune/luau"), require("@lune/serde")
local r = require("@lune/roblox")
local V = r.Vector3
local ROOT = "tools/level3_finale_player_20261002/finale/"
local objective = fs.readFile(ROOT .. "Level 3 Objective Controller.v2.candidate.luau")
local ai = fs.readFile(ROOT .. "Level 3 Mall Manager AI Controller.v2.candidate.luau")
luau.compile(objective); luau.compile(ai)
local results, assertions = {}, 0
local function expect(value, message) assertions += 1; assert(value, message) end
local function check(name, fn) fn(); table.insert(results, name) end
local function extract(source, marker)
    local first = assert(source:find(marker, 1, true))
    local last = assert(source:find("\nend", first, true))
    return source:sub(first, last + 3)
end
local function load(source, markers, returns, env)
    local pieces = {}
    for _, marker in ipairs(markers) do table.insert(pieces, extract(source, marker)) end
    table.insert(pieces, "return " .. returns)
    local e = {Vector3=V, CFrame=r.CFrame, Enum=r.Enum, Color3=r.Color3}
    for k,v in pairs(env or {}) do e[k]=v end
    return luau.load(table.concat(pieces,"\n"),{environment=e})()
end
local function attrs(initial, log, prefix)
    local o={Attrs=initial or {}, Parent={}}
    function o:GetAttribute(k) return self.Attrs[k] end
    function o:SetAttribute(k,v)
        self.Attrs[k]=v
        if log then table.insert(log,{name=(prefix or "")..k,value=v}) end
    end
    return o
end
local roster={}
local Players={GetPlayers=function() return roster end}
local function character(position)
    local c=attrs(); c.Humanoid={Health=100}; c.Root={Position=position or V.zero,AssemblyLinearVelocity=V.zero}
    function c.Root:IsA(class) return class=="BasePart" end
    function c:FindFirstChildOfClass(class) if class=="Humanoid" then return self.Humanoid end end
    function c:FindFirstChild(name) if name=="HumanoidRootPart" then return self.Root end end
    return c
end
local function player(id, x, z)
    local p=attrs({InRound=true}); p.UserId=id; p.Parent=Players; p.Character=character(V.new(x or 0,0,z or 0))
    return p
end
local hall={Model={Parent={}},Forward=V.new(1,0,0),StartPoint=V.zero,EndPoint=V.new(400,0,0),
    Length=400,HalfwayProgress=.5,Width=14,Height=15,FloorY=0,SpawnProgress=.97}
local barrier, s, workspaceMock, log, stopCount
local function resetBarrier(players)
    roster=players; log={}; stopCount=0
    workspaceMock=attrs({RoundActive=true,SelectedLevel=3},log,"workspace.")
    s={Generation=17,ExitUnlocked=true,State=attrs({Level3_RoomSongPhase="DONE"},log,"state."),
        Manifest={FinalHall=hall,World=attrs({},log,"world.")},FinalHallCrossed={}}
    barrier=load(objective,{"local function updateFinalHallChase"},"updateFinalHallChase",{
        Players=Players,workspace=workspaceMock,
        validPlayer=function(p) return p.Parent==Players and p:GetAttribute("InRound")==true and p:GetAttribute("Escaped")~=true end,
        MallManagerController={Stop=function() stopCount+=1;table.insert(log,{name="STOP"}) end},
    })
end
check("one of two living participants beyond halfway does not trigger",function()
    resetBarrier({player(1,240),player(2,196)});barrier(s)
    expect(not s.FinalHallChaseTriggered);expect(s.FinalHallEligibleCount==2 and s.FinalHallCrossedCount==1);expect(stopCount==0)
end)
check("exact midpoint is excluded, smallest positive crossing opens all-player barrier",function()
    resetBarrier({player(1,240),player(2,200)});barrier(s);expect(not s.FinalHallChaseTriggered)
    roster[2].Character.Root.Position=V.new(200.0001,0,0);barrier(s)
    expect(s.FinalHallChaseTriggered and stopCount==1);expect(s.FinalHallCrossedCount==2)
end)
check("latched crossing survives backtracking on same living character",function()
    resetBarrier({player(1,220),player(2,190)});barrier(s)
    roster[1].Character.Root.Position=V.new(100,0,0);roster[2].Character.Root.Position=V.new(201,0,0);barrier(s)
    expect(s.FinalHallChaseTriggered);expect(roster[1].Character:GetAttribute("Level3_FinalHallCrossedGeneration")==17)
end)
check("normal Manager stops before finale flag and fresh hunt edge",function()
    resetBarrier({player(1,201)});barrier(s)
    local names={};for _,item in ipairs(log) do table.insert(names,item.name) end
    local stop=assert(table.find(names,"STOP")); local final=assert(table.find(names,"workspace.Level3FinalHallChaseActive"))
    local edges={};for i,item in ipairs(log) do if item.name=="workspace.Level3MallManagerHuntActive" then table.insert(edges,{i,item.value}) end end
    expect(#edges==2 and edges[1][2]==false and edges[2][2]==true)
    expect(edges[1][1]<stop and stop<final and final<edges[2][1])
    barrier(s);expect(stopCount==1)
end)
check("dead, escaped, disconnected, and outside-round players are excluded",function()
    local live,dead,escaped,left,outside=player(1,220),player(2,1),player(3,1),player(4,1),player(5,1)
    dead.Character.Humanoid.Health=0;escaped:SetAttribute("Escaped",true);left.Parent=nil;outside:SetAttribute("InRound",false)
    resetBarrier({live,dead,escaped,left,outside});barrier(s)
    expect(s.FinalHallChaseTriggered and s.FinalHallEligibleCount==1)
end)
check("no living participants does not create a finale",function()
    local p=player(1,220);p.Character.Humanoid.Health=0;resetBarrier({p});barrier(s)
    expect(not s.FinalHallChaseTriggered and s.FinalHallEligibleCount==0);expect(stopCount==0)
end)
check("a living participant without root blocks admission",function()
    local p=player(2,220);p.Character.Root=nil;resetBarrier({player(1,220),p});barrier(s)
    expect(s.FinalHallEligibleCount==2 and s.FinalHallCrossedCount==1);expect(not s.FinalHallChaseTriggered)
end)
check("a replacement life cannot inherit an earlier crossing",function()
    resetBarrier({player(1,220),player(2,190)});barrier(s)
    roster[1].Character=character(V.new(199,0,0));roster[2].Character.Root.Position=V.new(201,0,0);barrier(s)
    expect(not s.FinalHallChaseTriggered and s.FinalHallCrossedCount==1)
    expect(roster[1].Character:GetAttribute("Level3_FinalHallCrossedGeneration")==nil)
end)
check("lateral, height, and beyond-end positions cannot count as a crossing",function()
    for _,position in ipairs({V.new(220,0,9.51),V.new(220,21.01,0),V.new(402.51,0,0)}) do
        local p=player(1,220);p.Character.Root.Position=position;resetBarrier({p});barrier(s)
        expect(not s.FinalHallChaseTriggered)
    end
end)
check("halfway is fixed at 50 percent despite an alternate manifest threshold",function()
    local saved=hall.HalfwayProgress;hall.HalfwayProgress=.25
    resetBarrier({player(1,160)});barrier(s);expect(not s.FinalHallChaseTriggered);hall.HalfwayProgress=saved
end)
check("music phase and exit-unlock fence all crossing activation",function()
    resetBarrier({player(1,240)});s.ExitUnlocked=false;barrier(s);expect(not s.FinalHallChaseTriggered)
    s.ExitUnlocked=true;s.State:SetAttribute("Level3_RoomSongPhase","PLAYING");barrier(s);expect(not s.FinalHallChaseTriggered)
end)
check("post-trigger observations stamp replacement life only after its own crossing",function()
    resetBarrier({player(1,220)});barrier(s);roster[1].Character=character(V.new(199,0,0));barrier(s)
    expect(roster[1].Character:GetAttribute("Level3_FinalHallCrossedGeneration")==nil)
    roster[1].Character.Root.Position=V.new(201,0,0);barrier(s)
    expect(roster[1].Character:GetAttribute("Level3_FinalHallCrossedGeneration")==17 and stopCount==1)
end)

local protection={IsActive=function(p) return p.Protected==true end}
local fits, fitCalls=true,{}
local spawnWorkspace=attrs({RoundActive=true,SelectedLevel=3})
local function planar(a,b) return (V.new(a.X,0,a.Z)-V.new(b.X,0,b.Z)).Magnitude end
local spawn=load(ai,{"local function eligibleSpawnPlayers","local function chooseFinalHallSpawn"},"chooseFinalHallSpawn",{
    Players=Players,workspace=spawnWorkspace,PlayerProtection=protection,
    stateFolder=function() return attrs({Level3_RoomSongCycle=1}) end,
    Random={new=function() return {} end},
    spawnOverlapParams=function(records) return records end,
    spawnVolumeFits=function(position) table.insert(fitCalls,position);return fits end,
    planarDistance=planar,insideFinalHall=function(_,position) return position.Z==0 end,
    nearestRoomId=function() return "FinalHall" end,spawnVisibilityCount=function() return 9 end,
})
local function prepareSpawn(players)
    roster=players;fits=true;fitCalls={}
    for _,p in ipairs(players) do p.Character:SetAttribute("Level3_FinalHallCrossedGeneration",17) end
end
check("fixed far endpoint ignores percentage preferences and near-player distance",function()
    prepareSpawn({player(1,390),player(2,201)})
    local got=assert(spawn({FinalHall=hall},17));expect(got.Position==hall.EndPoint)
    expect(got.NearestDistance==10 and got.GroupSize==2);expect(#fitCalls==1 and fitCalls[1]==hall.EndPoint)
    expect(got.Visibility==9 and got.FinalHallChase and got.SpawnClearanceValidated)
end)
check("blocked endpoint defers once per call and retries only the same endpoint",function()
    prepareSpawn({player(1,220)});fits=false;expect(spawn({FinalHall=hall},17)==nil)
    expect(#fitCalls==1 and fitCalls[1]==hall.EndPoint)
    fits=true;local got=assert(spawn({FinalHall=hall},17));expect(got.Position==hall.EndPoint)
    expect(#fitCalls==2 and fitCalls[2]==hall.EndPoint)
end)
check("new life during clearance retry must cross again",function()
    prepareSpawn({player(1,220)});fits=false;expect(spawn({FinalHall=hall},17)==nil)
    roster[1].Character=character(V.new(201,0,0));fits=true;expect(spawn({FinalHall=hall},17)==nil)
    roster[1].Character:SetAttribute("Level3_FinalHallCrossedGeneration",17)
    expect(assert(spawn({FinalHall=hall},17)).Position==hall.EndPoint)
end)
check("wrong crossing generation and living missing root both block deferred spawn",function()
    prepareSpawn({player(1,220),player(2,240)});roster[2].Character:SetAttribute("Level3_FinalHallCrossedGeneration",16)
    expect(spawn({FinalHall=hall},17)==nil);roster[2].Character:SetAttribute("Level3_FinalHallCrossedGeneration",17)
    roster[2].Character.Root=nil;expect(spawn({FinalHall=hall},17)==nil)
end)
check("departure, death and escape while blocked exclude retired roster entries",function()
    for _,kind in ipairs({"death","escape","departure"}) do
        prepareSpawn({player(1,220),player(2,190)});roster[2].Character:SetAttribute("Level3_FinalHallCrossedGeneration",nil)
        if kind=="death" then roster[2].Character.Humanoid.Health=0
        elseif kind=="escape" then roster[2]:SetAttribute("Escaped",true) else roster[2].Parent=nil end
        expect(assert(spawn({FinalHall=hall},17)).GroupSize==1)
    end
end)
check("all protected living players remain eligible for fixed finale spawn",function()
    prepareSpawn({player(1,220),player(2,390)});for _,p in ipairs(roster) do p.Protected=true end
    expect(assert(spawn({FinalHall=hall},17)).GroupSize==2)
end)
check("normal eligibility still excludes protected players",function()
    local eligible=load(ai,{"local function eligibleSpawnPlayers"},"eligibleSpawnPlayers",{
        Players=Players,workspace=spawnWorkspace,PlayerProtection=protection,
    })
    prepareSpawn({player(1,220),player(2,390)});roster[1].Protected=true
    expect(#eligible()==1 and #eligible(true)==2)
end)

local env={Players=Players,PlayerProtection=protection,validRound=function(session) return not session.Paused end,
    planarDistance=planar,insideFinalHall=function(_,p) return p.Z==0 end,
    flat=function(p,y) return V.new(p.X,y,p.Z) end,
    HidingController={GetAnchor=function() return nil end,IsHidden=function() return false end,
        IsFlushImmune=function() return false end,OccupantCount=function() return 1 end},
    Tuning={BlackoutTargetLeadSeconds=.15,BlackoutTargetLeadMaximumDistance=6,GoalTolerance=3,
        ThinkIntervalSeconds=.1,BlackoutThinkIntervalSeconds=.08,VerticalAttackTolerance=8},
    volumeFits=function() return true end,
    setGoal=function(session,p) session.FinalGoal=p end,
    clearGoal=function(session) session.FinalGoal=nil end,
    publishTarget=function(session,p) session.Target=p end,
    publishState=function(session,state) session.State=state end,
    publishTargetTelemetry=function() end,arrivalGoal=function() return nil end,
    choosePatrolGoal=function(session) session.RandomPatrolCalled=true;session.State="PATROL" end,
    liveSession=function() return true end,endTableCheck=function(session) session.CheckEnded=true end,
    hasSightRay=function() return true end,
}
local chase=load(ai,{"local function livingPlayer","local function nearestLivingPlayer","local function trackNearestBlackoutPlayer"},"trackNearestBlackoutPlayer",env)
local living=load(ai,{"local function livingPlayer"},"livingPlayer",env)
local forget=load(ai,{"local function forgetProtectedPlayer"},"forgetProtectedPlayer",env)
local attackEnv=table.clone(env);attackEnv.livingPlayer=living
local attack=load(ai,{"local function attackLineClear"},"attackLineClear",attackEnv)
local function chaseSession()
    return {Generation=17,FinalHallChase=true,Root={Position=hall.EndPoint},FloorY=0,Manifest={FinalHall=hall},
        AttackToken=0,AttackCooldownUntil=0,Suspicion={},ThinkAccumulator=0}
end
check("finale immediately chooses protected nearest exit runner and CHASE",function()
    roster={player(1,240),player(2,350)};for _,p in ipairs(roster) do p.Protected=true end
    local session=chaseSession();expect(chase(session,10));expect(session.State=="CHASE" and session.Target==roster[2])
    expect(session.FinalGoal==roster[2].Character.Root.Position)
end)
check("exit-lane runner has priority over closer adjacent-room player",function()
    roster={player(1,395,15),player(2,300,0)};local session=chaseSession();chase(session,10)
    expect(session.Target==roster[2])
end)
check("finale without living targets waits and never chooses random patrol",function()
    roster={};local session=chaseSession();session.PatrolGoal=V.zero;session.FinalGoal=V.zero;chase(session,10)
    expect(session.State=="WAITING" and session.FinalGoal==nil and session.PatrolGoal==nil)
    expect(not session.RandomPatrolCalled)
end)
check("normal no-target behavior keeps its existing patrol fallback",function()
    roster={};local session=chaseSession();session.FinalHallChase=false;chase(session,10)
    expect(session.State=="PATROL" and session.RandomPatrolCalled)
end)
check("protection activation retains finale pursuit but cancels attack windup",function()
    roster={player(1,395)};local p=roster[1];p.Protected=true;local session=chaseSession()
    session.Target=p;session.LastKnownPlayer=p;session.LastKnownCharacter=p.Character;session.LastKnownPosition=p.Character.Root.Position
    session.FinalGoal=p.Character.Root.Position;session.Attacking=true;session.AttackPlayer=p;session.AttackCharacter=p.Character
    session.State="ATTACK_WINDUP";forget(session,p,p.Character)
    expect(session.Target==p and session.LastKnownPlayer==p and session.FinalGoal~=nil)
    expect(not session.Attacking and session.AttackToken==1 and session.State=="CHASE")
    expect(session.AttackPlayer==nil and session.AttackCharacter==nil)
end)
check("normal protection activation retains existing target-forgetting behavior",function()
    roster={player(1,395)};local p=roster[1];p.Protected=true;local session=chaseSession();session.FinalHallChase=false
    session.Target=p;session.LastKnownPlayer=p;session.FinalGoal=V.zero;forget(session,p,p.Character)
    expect(session.Target==nil and session.LastKnownPlayer==nil and session.FinalGoal==nil)
    expect(session.State=="PATROL_LISTEN")
end)
check("finale protected attack cannot start; unprotected contact still uses existing ray/range gate",function()
    roster={player(1,395)};local p=roster[1];local session=chaseSession();p.Protected=true
    expect(attack(session,p,6)==false);p.Protected=false;expect(attack(session,p,6)==true)
    p.Character.Root.Position=V.new(390,0,0);expect(attack(session,p,6)==false)
end)
check("paused round never treats any character as an active target",function()
    roster={player(1,395)};local session=chaseSession();session.Paused=true
    expect(living(roster[1],session)==nil)
end)

check("coincident runner preserves exact fixed pivot and valid backward orientation",function()
    local first=assert(ai:find("\tlocal rootPosition = spawnPosition +",1,true))
    local last=assert(ai:find("\n\tmodel.Parent =",first,true))
    local block=ai:sub(first,last-1)
    local orientation=luau.load("return function(manifest, spawnPosition, facePosition, groundOffset, model)\n"..block.."\nend",
        {environment={Vector3=V,CFrame=r.CFrame}})()
    local model={PivotTo=function(self,cf) self.CFrame=cf end}
    orientation({FinalHall=hall},hall.EndPoint,hall.EndPoint,2,model)
    expect(model.CFrame.Position==hall.EndPoint+V.new(0,2,0))
    expect(model.CFrame.LookVector:Dot(-hall.Forward)>.999)
    orientation({FinalHall=hall},hall.EndPoint,V.new(390,0,0),2,model)
    expect(model.CFrame.Position==hall.EndPoint+V.new(0,2,0) and model.CFrame.LookVector:Dot(-hall.Forward)>.999)
end)
check("finale ignores ordinary spawn grace and enters CHASE before heartbeat; pause resume holds same rig",function()
    local first=assert(ai:find("\tlocal function roundChanged()",1,true))
    local last=assert(ai:find("\n\ttable.insert(session.Connections",first,true))
    local roundBlock=ai:sub(first,last-1)
    local acquireFirst=assert(ai:find("\tapplyBlackout(session, blackoutProfileRequested())\n\troundChanged()",last,true))
    local acquireLast=assert(ai:find("\n\tpublishMotion(session, 0, true)",acquireFirst,true))
    local acquire=ai:sub(acquireFirst,acquireLast-1)
    roster={player(1,300)};local session=chaseSession();session.SpawnSerial=42
    local w=attrs({RoundActive=true,SelectedLevel=3,Level3MallManagerHuntActive=true})
    local runner=luau.load("return function(session)\n"..roundBlock.."\n"..acquire.."\nreturn roundChanged\nend",{environment={
        Vector3=V,workspace=w,os={clock=function() return 100 end},Tuning={SpawnGraceSeconds=9},
        liveSession=function() return true end,validRound=env.validRound,
        publishState=env.publishState,dormant=function(ss,state) ss.State=state end,
        applyBlackout=function(ss,enabled) ss.Blackout=enabled end,blackoutProfileRequested=function() return true end,
        trackNearestBlackoutPlayer=chase,nearestLivingPlayer=function() return roster[1],roster[1].Character.Root end,
        flat=env.flat,setGoal=env.setGoal,
    }})()
    local roundChanged=runner(session)
    expect(session.ActivatedAt==100 and session.State=="CHASE" and session.Target==roster[1])
    session.Paused=true;expect(living(roster[1],session)==nil);session.Paused=false;chase(session,101)
    expect(session.State=="CHASE" and session.SpawnSerial==42)
    session.FinalHallChase=false;roundChanged();expect(session.ActivatedAt==109)
end)

check("device displays concise status, exact progress and five insertion lamps",function()
    local display=load(objective,{"local function updateDiscPlayerVisuals"},"updateDiscPlayerVisuals")
    local slots={};for i=1,5 do slots[i]={Parent={}} end
    local device={Model=attrs(),StatusLabel={Parent={}},InstructionLabel={Parent={}},ProgressLabel={Parent={}},ScreenSlots=slots,Prompt={}}
    local session={DiscPlayer=device,ModuleGoal=5,InsertedCount=2};display(session,false)
    expect(device.StatusLabel.Text=="AWAITING DISCS" and device.ProgressLabel.Text=="2 / 5 CDS")
    expect(device.InstructionLabel.Text=="INSERT CARRIED CDS" and device.Prompt.Enabled==true)
    expect(slots[2].BackgroundColor3==r.Color3.fromRGB(56,255,176) and slots[3].BackgroundColor3==r.Color3.fromRGB(20,37,35))
    session.InsertedCount=5;display(session,false)
    expect(device.StatusLabel.Text=="SIGNAL RESTORED" and device.ProgressLabel.Text=="5 / 5 CDS")
    expect(device.InstructionLabel.Text=="EXIT SIGNAL RESTORED" and device.Prompt.Enabled==false)
    expect(slots[5].BackgroundColor3==r.Color3.fromRGB(56,255,176))
end)
check("classic device safely omits optional Blender progress and screen slots",function()
    local display=load(objective,{"local function updateDiscPlayerVisuals"},"updateDiscPlayerVisuals")
    local device={Model=attrs(),StatusLabel={Parent={}},InstructionLabel={Parent={}},Prompt={}}
    display({DiscPlayer=device,ModuleGoal=5,InsertedCount=0},false)
    expect(device.StatusLabel.Text=="AWAITING DISCS" and device.Prompt.Enabled)
end)
check("reader target uses actual post-Visual device position; absent device clears both mirrors",function()
    local first=assert(objective:find("\tlocal playerPosition = session.DiscPlayer",1,true))
    local last=assert(objective:find("\n\tlocal insertedCount =",first,true))
    local publish=luau.load("return function(session)\n"..objective:sub(first,last-1).."\nend",{environment={workspace=workspaceMock}})()
    local state=attrs();local position=V.new(199,11,35)
    publish({State=state,DiscPlayer={Position=position}})
    expect(state:GetAttribute("Level3_CDPlayerPosition")==position and workspaceMock:GetAttribute("Level3CDPlayerPosition")==position)
    publish({State=state});expect(state:GetAttribute("Level3_CDPlayerPosition")==nil and workspaceMock:GetAttribute("Level3CDPlayerPosition")==nil)
    expect(objective:find('session.State:SetAttribute("Level3_CDPlayerPosition", nil)',1,true)~=nil)
    expect(objective:find('workspace:SetAttribute("Level3CDPlayerPosition", nil)',1,true)~=nil)
end)
check("same-character death clears crossing before carry-drop, allowing a revive to recross",function()
    local first=assert(objective:find("\tlocal function dropDeadCharacter(character: Model)",1,true))
    local last=assert(objective:find("\n\tlocal function bindCharacter",first,true))
    local block=objective:sub(first,last-1)
    local p=player(1,220);local c=p.Character;c:SetAttribute("Level3_FinalHallCrossedGeneration",17)
    c.Humanoid.Health=0;local session={FinalHallCrossed={[p]=c}};local dropped=false
    local death=luau.load("return function(session, player, watchedCharacter)\n"..block.."\nreturn dropDeadCharacter\nend",{environment={
        Players=Players,liveSession=function() return true end,
        dropHeldCDs=function() expect(c:GetAttribute("Level3_FinalHallCrossedGeneration")==nil);dropped=true end,
    }})()(session,p,c)
    death(c);expect(session.FinalHallCrossed[p]==nil and dropped)
end)
local receipt={kind="deterministic extracted-source dependency mocks",studioGameplayClaim=false,
    syntaxCandidates=2,scenarios=#results,assertions=assertions,passed=results,
    limits={"No actual character physics or world overlap", "No navigation/CPU measurement", "No transport or replication proof", "No multiplayer Studio server"}}
fs.writeFile("artifacts/level3-finale-player-20261002/finale-mock-receipt.json",serde.encode("json",receipt,true))
print(serde.encode("json",{syntaxCandidates=2,scenarios=#results,assertions=assertions,passed=true}))
