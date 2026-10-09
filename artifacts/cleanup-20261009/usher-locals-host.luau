-- Actual targeting/think/Stop are inserted verbatim; unrelated private systems
-- are controlled boundaries, not a native navigation/capture/physics claim.
local numericVectorMultiply=vec.__mul
vec.__mul=function(a,b)
    if type(a)=="table" and type(b)=="table" then return Vector3.new(a.X*b.X,a.Y*b.Y,a.Z*b.Z) end
    return numericVectorMultiply(a,b)
end
function vec:Lerp(other,alpha) return self+(other-self)*alpha end
local function usherPort(e)
    local Players=e.Players
    local HttpService={GenerateGUID=function() e.guidCalls+=1; return "FIXTURE-GUID" end}
    local Usher={}
    local C={ThinkSeconds=.1,StunSeconds=.3,StunCooldownSeconds=2,Height=8,SightRange=40,HearingRange=80,
        AttackRange=4,ShushSeconds=1,HopMinPlayerDistance=20,HopMaxTargetDistance=80}
    local BLINK_HOP_MIN_DISTANCE=12
    __STATE__
    local function now() return e.clock end
    local function bodyOf(player) return player.Character,{},player.Root end
    local function huntable(player) return player.Huntable end
    local function rayClear(_,_) return e.clearRay end
    local function eyes() return position+Vector3.new(0,C.Height-.6,0) end
    local function validRound() return e.valid end
    local function tickBatteries(elapsed) e.batteryTicks[#e.batteryTicks+1]=elapsed end
    local function beamedBy() return e.beam end
    local function nodeDark(_) return e.dark end
    local function pickHopNode(_,_,_) return e.hopNode end
    local function hopTo(index,reason,minD)
        e.hops[#e.hops+1]={Index=index,Reason=reason,Min=minD}
        nextHopAt=e.clock+1
    end
    local function goTowards(pos) e.paths[#e.paths+1]=pos; return e.pathAvailable end
    local function syncProxy(force) e.syncs[#e.syncs+1]=force end
    local function startCapture(player) e.captures[#e.captures+1]=player.UserId end
    local function finishCapture(record,cancelled) e.finish[#e.finish+1]={Player=record.Player.UserId,Cancelled=cancelled} end
    local function onZoneChanged() end
    local NoiseRegistry={Prune=function() e.prunes+=1 end,GetBest=function() return e.noise end}
    __SETSTATE__
    __BEAMERS__
    __CHOOSE__
    __THINK__
    __STOP__
    local function snapshot()
        return {State=state,Target=target and target.UserId,LastKnown=lastKnown,SearchUntil=searchUntil,
            NextHopAt=nextHopAt,NextReplanAt=nextReplanAt,BeamTime=beamTime,StunCooldownUntil=stunCooldownUntil,
            Hidden=hidden,Path=path,PathIndex=pathIndex,Shush=shush and {Player=shush.Player.UserId,EndsAt=shush.EndsAt},
            StateAttributes=stateFolder:GetAttributes(),PlayerAttributes=e.player:GetAttributes(),Events=e.events,Hops=e.hops,
            Paths=e.paths,BatteryTicks=e.batteryTicks,Prunes=e.prunes,Finish=e.finish,GuidCalls=e.guidCalls}
    end
    local function setMode(mode)
        target=nil; lastKnown=nil; searchUntil=0; nextHopAt=0; nextReplanAt=0
        hidden=false; active=true; finale=false; current=1; state="Stalk"; path=nil; shush=nil; capture=nil
        position=Vector3.zero; beamTime=0; stunCooldownUntil=0
        e.beam={}; e.noise=nil; e.valid=true; e.dark=true; e.clearRay=false; e.hopNode=nil; e.pathAvailable=true
        e.player.Huntable=true; e.player.Root.Position=Vector3.new(20,0,0)
        objectives={BreakerHolder=function() return mode=="holder" and e.player or nil end,LivingParticipants=function() return {} end}
        if mode=="sight" then e.clearRay=true end
        if mode=="noise" then e.noise={SourcePlayer=e.player,pos=Vector3.new(25,0,0)} end
        if mode=="finale" then finale=true; e.player.Root.Position=Vector3.new(100,0,0) end
    end
    stateFolder=e.new("Folder","Usher State")
    clientEvent={FireAllClients=function(_,payload) e.events[#e.events+1]=payload end}
    manifest={Audio={Shush=0}}
    lights={OnZoneChanged=onZoneChanged}
    local rows={}
    for _,mode in ipairs({"holder","sight","noise","finale"}) do
        setMode(mode); e.clock=10
        think(.17)
        check(target==e.player,"actual chooseTarget selects "..mode)
        check(state==(mode=="noise" and "Stalk" or "Chase"),"reason still controls target mode "..mode)
        rows[#rows+1]=snapshot()
    end
    setMode("none"); e.player.Huntable=false; e.noise={pos=Vector3.new(30,0,0)}
    e.clock=20; searchUntil=20; think(.1)
    check(target==nil and state=="Search" and lastKnown.X==30,"anonymous noise remains search target")
    rows[#rows+1]=snapshot()
    setMode("sight"); e.player.Root.Position=Vector3.new(2,0,0); e.clock=30
    think(.1); check(state=="Shush" and shush.Player==e.player,"close target enters windup")
    e.clock=30.5; think(.1); check(#e.captures==0,"windup does not capture early")
    e.clock=31.1; think(.1); check(#e.captures==1,"windup reaches existing capture boundary")
    rows[#rows+1]=snapshot()
    setMode("holder"); e.clock=40; e.beam={e.player}; e.hopNode=7
    think(.1); think(.1)
    check(state=="Stunned" and e.player:GetAttribute("Level4_BeamingUsher")==true,"flashlight freeze and authored beamer attribute")
    think(.1)
    check(beamTime==0 and stunCooldownUntil==42,"held stun keeps existing cooldown")
    check(e.hops[#e.hops].Reason=="stunned" and e.hops[#e.hops].Min==50,"stun retreat retains 50-stud boundary")
    check(e.player:GetAttribute("Level4_BeamingUsher")==nil and e.events[#e.events].Type=="Stun","beamer cleanup and Stun payload")
    e.clock=40.1; think(.1)
    check(state=="Chase" and beamTime==0,"cooldown suppresses repeated stun")
    rows[#rows+1]=snapshot()
    e.clock=43; e.beam={e.player}; think(.1)
    check(state=="Stunned","stun becomes eligible after cooldown")
    e.valid=false; think(.1)
    check(path==nil and e.player:GetAttribute("Level4_BeamingUsher")==nil,"invalid round clears beam/path")
    proxy=e.new("Model","Usher Proxy"); root=e.new("Part","Root",proxy); head=e.new("Part","Head",proxy)
    local disconnected=0
    connections={{Disconnect=function() disconnected+=1 end},{Disconnect=function() disconnected+=1 end}}
    capture={Player=e.player}
    Usher.Stop()
    check(state=="Dormant" and hidden and not active and not finale and beamTime==0 and stunCooldownUntil==0 and nextHopAt==0,"Stop resets only active lifecycle state")
    check(target==nil and path==nil and capture==nil and #connections==0 and disconnected==2,"Stop clears active targets/capture/connections")
    check(lights.OnZoneChanged==nil and proxy==nil and e.finish[#e.finish].Cancelled,"Stop removes hook/proxy and cancels capture at boundary")
    rows[#rows+1]=snapshot()
    Usher.Stop(); check(#connections==0,"Stop reentry safe")
    stateFolder:Destroy()
    return rows
end

local function usherFixture(port)
    local e=dressingEngine()
    e.guidCalls=0; e.batteryTicks={}; e.hops={}; e.paths={}; e.syncs={}; e.captures={}; e.finish={}; e.prunes=0
    e.player=e.new("Player","Fixture Player")
    e.Players._children={}
    e.player.UserId=71; e.player.Parent=e.Players
    function e.Players:GetPlayers() return {e.player} end
    e.player.Root=e.new("Part","Player Root")
    local rows=port(e)
    e.player.Parent=nil; e.player.Root:Destroy(); e.player:Destroy()
    for _,o in ipairs(e.allocated) do check(o.Parent==nil,"Usher fixture cleans allocated objects") end
    return rows
end
