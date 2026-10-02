local fs, luau = require("@lune/fs"), require("@lune/luau")
local r = require("@lune/roblox")
local source = fs.readFile("tools/level3_finale_player_20261002/reader/Reader.v4.candidate.luau")
luau.compile(source)
local start = assert(source:find("-- L3_CD_PLAYER_GUIDANCE_PURE_BEGIN", 1, true))
local finish = assert(source:find("-- L3_CD_PLAYER_GUIDANCE_PURE_END", start, true))
local mode, bearing, heading, project = luau.load(source:sub(start, finish-1)
    .. "\nreturn readerTargetMode, precisePlanarBearing, precisePlanarHeading, projectGuidePoint")()
local checks = 0
local function check(value, message) assert(value, message); checks += 1 end
local function near(a, b) return math.abs(a-b) < .000001 end
local boundsStart=assert(source:find("-- L3_GUIDE_MOVEMENT_BOUNDS_BEGIN",1,true))
local boundsEnd=assert(source:find("-- L3_GUIDE_MOVEMENT_BOUNDS_END",boundsStart,true))
local ceiling=luau.load(source:sub(boundsStart,boundsEnd-1).."\nreturn guideMovementCeiling")()
local capped,fits=ceiling(264,126,238,208,260)
check(capped==154 and fits and capped+46+8<=208,"whole phone card clears all movement zones")
capped,fits=ceiling(264,126,100,208,260)
check(capped==46 and not fits,"short landscape keeps compass and hides scene projection")
capped,fits=ceiling(264,126,math.huge,math.huge,math.huge)
check(capped==264 and fits,"desktop/no-zones bounds remain unchanged")
check(mode({"WORLD","WORLD","WORLD","WORLD","WORLD"},5,0,false)=="SCAN", "remaining world CDs")
check(mode({"CARRIED","CARRIED","CARRIED","CARRIED","CARRIED"},5,0,false)=="PLAYER", "all team carried")
check(mode({"INSERTED","CARRIED","INSERTED","CARRIED","CARRIED"},5,2,false)=="PLAYER", "mixed inserted/carried")
check(mode({"INSERTED","INSERTED","INSERTED","INSERTED","INSERTED"},5,4,false)=="EXIT", "state-complete beats lagging count")
check(mode({"INSERTED","CARRIED","DROPPED","CARRIED","CARRIED"},5,1,false)=="SCAN", "dropped restores scanner")
check(mode({"INSERTED","CARRIED","WORLD","CARRIED","CARRIED"},5,1,false)=="SCAN", "WORLD without position is not secured")
check(mode({"CARRIED","CARRIED",nil,"CARRIED","CARRIED"},5,0,false)=="SCAN", "missing state is not secured")
check(mode({},5,5,false)=="EXIT" and mode({},5,0,true)=="EXIT", "inserted/unlocked authority")
check(near(bearing(0,-1,0,-10),0), "ahead0")
check(near(bearing(0,-1,10,0),math.pi*.5), "right90")
check(near(bearing(0,-1,-10,0),-math.pi*.5), "left-90")
check(near(math.abs(bearing(0,-1,0,10)),math.pi), "behind180")
check(near(bearing(1,0,10,0),0), "camera yaw rotates target bearing")
check(near(bearing(0,-1,0,0),0) and near(bearing(0,0,1,1),0), "zero vectors bounded")
local fx,fz=heading(0,0,0,1,0,-1)
check(near(fx,1) and near(fz,0) and near(bearing(fx,fz,10,0),0),"vertical pitch preserves camera yaw right90")
fx,fz=heading(0,0,0,-1,0,-1)
check(near(fx,-1) and near(fz,0) and near(bearing(fx,fz,-10,0),0),"vertical pitch preserves camera yaw left90")
fx,fz=heading(0,-1,0,1,1,0)
check(near(fx,0) and near(fz,-1),"horizontal look takes priority")
fx,fz=heading(0,0,0,0,0,-1)
check(near(fx,0) and near(fz,-1),"invalid camera axes use subject fallback")
for _, bounds in ipairs({{20,80,980,680}, {70,140,305,620}, {76,70,492,206}}) do
    local lx,ly,hx,hy = table.unpack(bounds)
    local cx,cy=(lx+hx)*.5,(ly+hy)*.5
    local x,y,rot,on=project(cx,cy,1,0,lx,ly,hx,hy)
    check(near(x,cx) and near(y,cy) and on, "on-screen exact point")
    x,y,rot,on=project(-999,-999,-1,0,lx,ly,hx,hy)
    check(near(x,cx) and near(y,ly) and near(rot,0) and not on, "behind projection never mirrored ahead incorrectly")
    x,y,rot,on=project(-999,-999,-1,math.pi,lx,ly,hx,hy)
    check(near(x,cx) and near(y,hy) and near(math.abs(rot),180) and not on, "behind180 points lower edge")
    x,y,rot,on=project(-999,-999,-1,math.pi*.5,lx,ly,hx,hy)
    check(near(x,hx) and near(y,cy) and near(rot,90) and not on, "behind-right stable edge")
    x,y,rot,on=project(99999,cy,1,0,lx,ly,hx,hy)
    check(near(x,hx) and near(y,cy) and near(rot,90) and not on, "positive-depth offscreen clamp")
    for _, point in ipairs({{-999,-999},{9999,-999},{9999,9999},{-999,9999}}) do
        x,y,rot,on=project(point[1],point[2],1,0,lx,ly,hx,hy)
        check(x>=lx-.000001 and x<=hx+.000001 and y>=ly-.000001 and y<=hy+.000001 and not on,
            "edge/corner remains in safe bounds")
    end
end

-- Test the unchanged complete gate with fake live players, including spectate.
local function extract(marker)
    local a=assert(source:find(marker,1,true)); local b=assert(source:find("\nend",a,true))
    return source:sub(a,b+3)
end
-- Exercise the actual pooled beacon reader across pickup/drop replication.
local poolStart=assert(source:find("local cdBeaconBuffer:",1,true))
local poolEnd=assert(source:find("local function signedPlanarAngle",poolStart,true))
local attrs={Level3_CD1State="WORLD",Level3_CD1Position=r.Vector3.new(2,0,3),Level3_CD1Room="R1",
    Level3_CD2State="CARRIED",Level3_CD2Position=r.Vector3.new(50,0,50)}
local pick,states=luau.load(source:sub(poolStart,poolEnd-1).."\nreturn pickableCDs, cdStateBuffer",{environment={
    stateAttribute=function(k) return attrs[k] end,
}})()
local beacons=pick(2)
check(#beacons==1 and beacons[1].Index==1 and beacons[1].Room=="R1","existing world scanner excludes carried")
local originalBeacon=beacons[1]
attrs.Level3_CD1State="CARRIED"; local reused=pick(2)
check(reused==beacons and #reused==0 and states[1]=="CARRIED","pickup reuses cleared buffer")
attrs.Level3_CD1State="DROPPED"; attrs.Level3_CD1Position=r.Vector3.new(8,0,9)
reused=pick(2)
check(reused[1]==originalBeacon and reused[1].X==8 and states[1]=="DROPPED","drop restores current position and pooled record")
attrs.Level3_CD1Position=nil; reused=pick(2)
check(#reused==0 and mode(states,2,0,false)=="SCAN","missing position preserves remaining-CD mode")
local function fakePlayer(attrs, alive)
    local p={Attrs=attrs,Character={}}
    function p:GetAttribute(key) return self.Attrs[key] end
    function p.Character:FindFirstChildOfClass() return {Health=alive and 100 or 0} end
    function p.Character:FindFirstChild() return {} end
    return p
end
local player=fakePlayer({InRound=true},true)
local watched=fakePlayer({InRound=true},true)
local level,modal,studio = 3,false,false
local active=luau.load(extract("local function spectateSubject").."\n"
    ..extract("local function readerSubject").."\n"..extract("local function isActive").."\nreturn isActive", {environment={
    LEVEL=3, player=player, Players={GetPlayerByUserId=function() return watched end},
    workspace={GetAttribute=function() return level end}, RunService={IsStudio=function() return studio end},
    UIDevice={ScreenOwningModalOpen=function() return modal end},
}})()
check(active(), "public in-round active")
player.Attrs.Escaped=true; check(not active(),"escaped excludes")
player.Attrs.Spectating=true; player.Attrs.SpectateTargetUserId=42
check(active(), "escaped spectator sees living watched subject")
watched.Attrs.Level3_Hiding=true; check(not active(),"watched hiding gates")
watched.Attrs.Level3_Hiding=nil; watched.Attrs.Escaped=true; check(not active(),"escaped subject rejected")
watched.Attrs.Escaped=nil; modal=true; check(not active(),"modal excludes")
modal=false; player.Attrs.ZyntraDispatchClientActive=true; check(not active(),"dispatch excludes")
player.Attrs.ZyntraDispatchClientActive=nil; level=6; check(not active(),"preview level excludes")

-- Geometry uses cached fields/scalars and fixed literals, never allocates tables,
-- formats strings, scans descendants, or connects signals in its frame path.
local geometry=extract("local function updatePlayerGuideGeometry")
check(not geometry:find("{}",1,true) and not geometry:find("table.",1,true)
    and not geometry:find("string.format",1,true) and not geometry:find("FindFirstChild",1,true)
    and not geometry:find(":Connect",1,true),"bounded frame geometry")
-- Reproduce native evidence: viewport Y=300.59, screen/AbsolutePosition
-- Y=242.59 with a 58px topbar. The actual geometry must use screen projection,
-- then the cached GUI-local origin conversion exactly once.
local guide,compass,pin={}, {}, {}
local projectionCalls=0
local target={X=0,Y=0,Z=-12}
local camera={CFrame={LookVector={X=0,Y=0,Z=-1},RightVector={X=1,Y=0,Z=0}}}
function camera:WorldToScreenPoint(given)
    assert(given==target); projectionCalls+=1
    return {X=624.26,Y=242.59,Z=11.54}
end
function camera:WorldToViewportPoint() error("viewport space would reproduce native 58px offset") end
local env={guideRoot={Parent=true,Position={X=0,Y=0,Z=0},CFrame=camera.CFrame},guideTarget=target,
    guidePlayerMode=true,guideProjectionFits=true,panel={Visible=true},playerGuide=guide,
    playerCompassArrow=compass,guideArrow=pin,guideMinX=76,guideMinY=126,guideMaxX=1174,guideMaxY=423,
    guideOffsetX=0,guideOffsetY=0,workspace={CurrentCamera=camera},UDim2=r.UDim2,
    isActive=function() return true end,precisePlanarBearing=bearing,precisePlanarHeading=heading,projectGuidePoint=project}
local update=luau.load(geometry.."\nreturn updatePlayerGuideGeometry",{environment=env})()
update()
check(projectionCalls==1 and guide.Visible and guide.Position.X.Offset==624 and guide.Position.Y.Offset==242,
    "native 58px inset evidence: pin exactly follows screen projection")
check(pin.Text=="◆" and compass.Rotation==0,"correct projected pin keeps exact compass")
env.guideOffsetX,env.guideOffsetY=62,58
update=luau.load(geometry.."\nreturn updatePlayerGuideGeometry",{environment=env})()
update()
check(guide.Position.X.Offset-62==624 and guide.Position.Y.Offset-58==242,
    "notched/inset-free GUI local origin conversion applied exactly once")
check(source:find("guidePlayerMode, guideTarget, guideRoot = false, nil, nil",1,true)~=nil,"teardown clears target/root")
check(source:find('if mode == "EXIT" then cd = nil end',1,true)~=nil,"inserted authority ignores stale world states")
print("Reader syntax compiled; "..checks.." focused source-function checks passed.")
print("No live UI/replication/spectating/performance claim implied.")
