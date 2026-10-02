-- Deterministic tests of extracted candidate function bodies with fake dependencies.
-- No Studio/real character/physics/replication/Datastore behavior is exercised.
local fs, luau = require("@lune/fs"), require("@lune/luau")
local r = require("@lune/roblox")
local ROOT = "tools/level3_promotion_20261002/gameplay_boards/candidates/"
local objective = fs.readFile(ROOT .. "ServerScriptService.Level 3 Systems.Level 3 Objective Controller.candidate.luau")
local ai = fs.readFile(ROOT .. "ServerScriptService.Level 3 Systems.Level 3 Mall Manager AI Controller.candidate.luau")
local builder = fs.readFile(ROOT .. "ServerScriptService.LobbyReimaginedPreview.Builder.candidate.luau")
local lighting = fs.readFile(ROOT .. "StarterPlayer.StarterPlayerScripts.Level 3 Lighting Controller.candidate.luau")
local results = {}
local function check(name, fn)
    fn()
    table.insert(results, name)
end
local function extract(source, marker)
    local first = assert(source:find(marker, 1, true))
    local last = assert(source:find("\nend", first, true))
    return source:sub(first, last + 3)
end
local function loadFunctions(source, markers, returns, env)
    local pieces = {}
    for _, marker in ipairs(markers) do table.insert(pieces, extract(source, marker)) end
    table.insert(pieces, "return " .. returns)
    local environment = {Vector3=r.Vector3, CFrame=r.CFrame, Enum=r.Enum}
    for key, value in pairs(env or {}) do environment[key] = value end
    return luau.load(table.concat(pieces, "\n\n"), {environment=environment})()
end
local function attrs(initial)
    local object = {Attrs=initial or {}, Writes={}}
    function object:GetAttribute(name) return self.Attrs[name] end
    function object:SetAttribute(name, value)
        self.Attrs[name] = value
        table.insert(self.Writes, name)
    end
    return object
end

do
    local state, world, fakeWorkspace = attrs({Level3_RoomSongPhase="DONE"}), attrs(), attrs()
    local participant = {Character={}, Position=r.Vector3.new(200, 0, 0), Valid=true, Alive=true}
    local hall = {Model={Parent={}}, Forward=r.Vector3.new(1,0,0), StartPoint=r.Vector3.zero,
        Length=400, HalfwayProgress=.5, Width=24, Height=20, FloorY=0}
    local update = loadFunctions(objective, {"local function updateFinalHallChase"}, "updateFinalHallChase", {
        Players={GetPlayers=function() return {participant} end}, workspace=fakeWorkspace,
        Configuration={Layout={FinalHallHalfwayProgress=.5}},
        validPlayer=function(player) return player.Valid end,
        livingCharacter=function(player)
            if player.Alive then return player.Character, {}, {Position=player.Position} end
            return nil, nil, nil
        end,
    })
    local function session()
        return {ExitUnlocked=true, State=state, Manifest={FinalHall=hall,World=world}, FinalHallCrossed={}}
    end
    check("strict midpoint equality does not trigger", function()
        participant.Position=r.Vector3.new(200,0,0)
        local s=session(); update(s); assert(not s.FinalHallChaseTriggered)
    end)
    check("first living survivor strictly beyond midpoint triggers in order", function()
        participant.Position=r.Vector3.new(200.001,0,0)
        local s=session(); update(s); assert(s.FinalHallChaseTriggered)
        assert(table.find(fakeWorkspace.Writes,"Level3FinalHallChaseActive")
            < table.find(fakeWorkspace.Writes,"Level3MallManagerHuntActive"))
    end)
    check("lateral outside hall does not trigger", function()
        participant.Position=r.Vector3.new(201,0,15)
        local s=session(); update(s); assert(not s.FinalHallChaseTriggered)
    end)
    check("dead survivor does not trigger", function()
        participant.Position=r.Vector3.new(201,0,0); participant.Alive=false
        local s=session(); update(s); assert(not s.FinalHallChaseTriggered and s.FinalHallEligibleCount==0)
        participant.Alive=true
    end)
    check("character latch does not carry across a rejoin", function()
        participant.Position=r.Vector3.new(199,0,0)
        local s=session(); s.FinalHallCrossed[participant]={}
        update(s); assert(not s.FinalHallChaseTriggered)
    end)
end

do
    local records = {{Player={UserId=1},Position=r.Vector3.new(200,0,0)}}
    local hall={Model={Parent={}}, StartPoint=r.Vector3.zero, EndPoint=r.Vector3.new(400,0,0),FloorY=0,SpawnProgress=.97}
    local blockedX
    local spawn = loadFunctions(ai, {"local function chooseFinalHallSpawn"}, "chooseFinalHallSpawn", {
        Tuning={FinalHallSpawnProgress=.97,SpawnMinimumDistance=90},
        eligibleSpawnPlayers=function() return records end,
        stateFolder=function() return attrs({Level3_RoomSongCycle=1}) end,
        Random={new=function() return {} end},
        spawnOverlapParams=function(got) assert(got==records); return {} end,
        spawnVolumeFits=function(position) return blockedX==nil or math.abs(position.X-blockedX)>.001 end,
        planarDistance=function(a,b) return (r.Vector3.new(a.X,0,a.Z)-r.Vector3.new(b.X,0,b.Z)).Magnitude end,
        insideFinalHall=function(_,position) return position.Z==0 end,
        nearestRoomId=function() return "FinalHall" end,
        spawnVisibilityCount=function() return 1 end,
    })
    check("finale selects configured far end and reports actual clearance distance", function()
        local got=assert(spawn({FinalHall=hall},3)); assert(math.abs(got.Position.X-388)<.001)
        assert(math.abs(got.NearestDistance-188)<.001 and got.SpawnClearanceValidated)
    end)
    check("second living participant near far end blocks every candidate", function()
        table.insert(records,{Player={UserId=2},Position=r.Vector3.new(375,0,0)})
        assert(spawn({FinalHall=hall},3)==nil)
        table.remove(records)
    end)
    check("blocked first volume tries next safe far-end candidate", function()
        blockedX=388
        local got=assert(spawn({FinalHall=hall},3));assert(math.abs(got.Position.X-380)<.001)
        blockedX=nil
    end)
    local speed = loadFunctions(ai, {"local function currentSpeed"}, "currentSpeed", {
        Tuning={FinaleApproachSpeed=28},
        profile=function() return {PatrolSpeed=8,InvestigateSpeed=12,SearchSpeed=10,ChaseSpeed=24} end,
    })
    check("finale keeps fixed configured pace; normal hunt pace remains", function()
        assert(speed({FinalHallChase=true,State="CHASE"})==28)
        assert(speed({FinalHallChase=false,State="CHASE"})==24)
    end)
end

do
    local function part(cf, chunk)
        local p=attrs({Level3_KitVisualChunk=chunk});p.CFrame=cf;p.Transparency=1;p.Destroyed=false
        function p:IsA(class) return class=="BasePart" end
        function p:Destroy() self.Destroyed=true end
        return p
    end
    local carrier=part(r.CFrame.new(10,5,8),false)
    local localCF=r.CFrame.new(.3,.2,-.4)*r.CFrame.Angles(.1,.2,.3)
    local chunk=part(carrier.CFrame*localCF,true)
    function carrier:GetDescendants() return {chunk} end
    local funcs=loadFunctions(objective,
        {"local function configureRuntimeDiscPart","local function setDiscVisualCFrame"},
        "{configure=configureRuntimeDiscPart,move=setDiscVisualCFrame}", {})
    check("carry/drop restores every faded authored chunk",function()
        funcs.configure(carrier,true,false)
        assert(chunk.Transparency==0 and not chunk.CanCollide and not chunk.CanTouch and not chunk.CanQuery)
    end)
    check("carry/drop moves authored chunk preserving its local transform",function()
        local target=r.CFrame.new(100,3,200)*r.CFrame.Angles(.2,.8,.4)
        funcs.move(carrier,target)
        assert((chunk.CFrame.Position-(target*localCF).Position).Magnitude<.0001)
        assert((chunk.CFrame.LookVector-(target*localCF).LookVector).Magnitude<.0001)
    end)
end

do
    local original, destination = {}, {}
    local panel={Position=r.Vector3.new(-30,37.15,-795)}
    function panel:IsA(class) return class=="BasePart" end
    function panel:FindFirstChild(name) if name=="DonationLeaderboardDisplay" then return {} end end
    local nilParents=0
    local board={Name="ZyntraDonationLeaderboardBoard",_parent=original,_pivot=r.CFrame.new(-30,37.15,-795)}
    setmetatable(board,{
        __index=function(self,key) if key=="Parent" then return self._parent end end,
        __newindex=function(self,key,value)
            if key=="Parent" then if value==nil then nilParents+=1 end; self._parent=value else rawset(self,key,value) end
        end,
    })
    function board:IsA(class) return class=="Model" end
    function board:GetPivot() return self._pivot end
    function board:PivotTo(cf)
        panel.Position=(cf*self._pivot:Inverse()):PointToWorldSpace(panel.Position)
        self._pivot=cf
    end
    function board:FindFirstChild(name) if name=="LeaderboardPanel" then return panel end end
    local originals={board}
    local lobby={GetDescendants=function() return originals end}
    function destination:FindFirstChild(name)
        if name==board.Name and board.Parent==self then return board end
    end
    local functions=loadFunctions(builder,
        {"local function supportBoardTransfer","local function applySupportBoardTransfer","local function restoreSupportBoardTransfer"},
        "{capture=supportBoardTransfer,apply=applySupportBoardTransfer,restore=restoreSupportBoardTransfer}", {
            workspace={FindFirstChild=function(_,name) if name=="ServerLobby" then return lobby end end},
        })
    local center=r.Vector3.new(220,30,-760)
    check("original board moves to exact relative position without nil parent",function()
        local transfer=assert(functions.capture(destination,center));functions.apply(transfer,destination)
        assert(board.Parent==destination and nilParents==0)
        assert((panel.Position-(center+r.Vector3.new(-30,7.15,-35))).Magnitude<.001)
        functions.restore(transfer)
        assert(board.Parent==original and nilParents==0)
    end)
    check("failure rollback restores original parent and pivot before target teardown",function()
        local oldPivot=board:GetPivot()
        local transfer=assert(functions.capture(destination,center));functions.apply(transfer,destination)
        functions.restore(transfer)
        assert(board.Parent==original and board:GetPivot()==oldPivot and nilParents==0)
    end)
    check("re-entry uses installed original board and creates no second transfer",function()
        local transfer=assert(functions.capture(destination,center));functions.apply(transfer,destination)
        assert(functions.capture(destination,center)==nil)
        functions.restore(transfer)
    end)
    check("ambiguous original boards fail before moving either",function()
        table.insert(originals,board)
        local ok=pcall(functions.capture,destination,center)
        assert(not ok and board.Parent==original and nilParents==0)
        table.remove(originals)
    end)
end

do
    local visualWall = {Parent={}}
    local collisionWall = {Parent={},CanCollide=true}
    local model, world = attrs(), attrs()
    local state=attrs()
    local portal={Model=model,Wall=collisionWall,VisualWall=visualWall,FrameParts={}}
    local tweens={}
    local unlock=loadFunctions(objective,{"unlockExit = function"},"unlockExit",{
        workspace={GetServerTimeNow=function() return 25 end,SetAttribute=function() end},
        Configuration={MusicSequence={CompletionDimSeconds=8}},
        validSession=function() return true end,updateSharedState=function() end,
        TweenInfo={new=function() return {} end},
        playTween=function(_,object,_,goals) table.insert(tweens,{Object=object,Goals=goals}) end,
        firePayload=function() end,fireSound=function() end,
    })
    check("public unlock fades separate reactive Blender wall and disables collision",function()
        unlock({State=state,Manifest={World=world,ExitPortal=portal},ModuleCount=5,ModuleGoal=5},"Exit")
        assert(not collisionWall.CanCollide and collisionWall.CanQuery)
        assert(#tweens==1 and tweens[1].Object==visualWall and tweens[1].Goals.Transparency==1)
    end)
end

do
    local blackoutParts, blackoutPartSeen = {}, {}
    local capture=loadFunctions(lighting,{"local function captureAuthoredRoomGlow"},"captureAuthoredRoomGlow",{
        blackoutParts=blackoutParts,blackoutPartSeen=blackoutPartSeen,
    })
    local carriers={}
    local connections=0
    for index=1,8 do
        local frame=attrs({Level3_HiddenExitFrame=true,Level3_KitAsset="FluorescentDiffuser"})
        frame.Material=r.Enum.Material.Neon;frame.Color=r.Color3.new(1,1,1);frame.Transparency=.08
        function frame:IsA(class) return class=="BasePart" end
        function frame:FindFirstChildWhichIsA(class) assert(class=="Light");return nil end
        function frame:GetPropertyChangedSignal()
            return {Connect=function(_,fn) connections+=1;return {Callback=fn} end}
        end
        local chunk=attrs({Level3_KitVisualChunk=true});chunk.MaterialVariant="Authored"
        function chunk:IsA(class) return class=="MeshPart" end
        function frame:GetChildren() return {chunk} end
        frame.Chunk=chunk;table.insert(carriers,frame)
    end
    check("all eight tagged portal frames are captured once without child lights",function()
        for _,frame in ipairs(carriers) do capture(frame);capture(frame) end
        assert(#blackoutParts==8)
    end)
    local functions=loadFunctions(lighting,
        {"local function syncKitFixtureVisuals","local function tryWatchKitFixture"},
        "{sync=syncKitFixtureVisuals,watch=tryWatchKitFixture}",{
            kitFixtureSeen={},kitFixtureConnections={},kitVisualVariants={},
        })
    check("all tagged portal carriers watch and synchronize client-local dark chunks",function()
        for _,frame in ipairs(carriers) do
            functions.watch(frame);functions.watch(frame)
            frame.Material=r.Enum.Material.SmoothPlastic;frame.Color=r.Color3.new(.05,.05,.05)
            functions.sync(frame)
            assert(frame.Chunk.Material==frame.Material and frame.Chunk.Color==frame.Color
                and frame.Chunk.Transparency==frame.Transparency and frame.Chunk.MaterialVariant=="")
        end
        assert(connections==24)
    end)
end

print("Passed " .. #results .. " extracted-function cases with mocked dependencies:")
for _, name in ipairs(results) do print("  " .. name) end
print("This does not verify live gameplay, character physics, board subscriptions or replication.")
