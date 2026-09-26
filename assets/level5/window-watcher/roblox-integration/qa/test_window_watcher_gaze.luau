-- Pure tests of the actual helper. No camera/Roblox fake is required.
local Gaze=require("../../../../../ReplicatedStorage/WindowWatcherGazeLogic.ModuleScript")
local assertions=0
local function check(value,message) assertions+=1;assert(value,message) end
local function close(a,b,tolerance) return math.abs(a-b)<=(tolerance or 1e-9) end
local function input(id,distance,angle,los,active)
	return {appearanceId=id,distance=distance,angleDegrees=angle,hasLineOfSight=los,active=active}
end
local function fixed(unit) return Gaze.New(function() return unit end) end
local function stare(unit,distance,fps,angle)
	local state=fixed(unit)
	local dt=1/fps;local time=0;local result
	repeat
		result=Gaze.Step(state,dt,input(1,distance,angle or 0,true,true));time+=dt
		check(time<=20,"reasonable bound for direct steady gaze")
	until result.hideForAppearance
	return time,state,result
end

local draws=0
local state=Gaze.New(function() draws+=1;return .5 end)
local idle=Gaze.Step(state,1/60,input(0,12,0,true,true))
check(draws==0 and idle.intensity==0 and idle.exposure==0,"no real appearance means no gaze effect or RNG draw")
for _=1,30 do Gaze.Step(state,1/60,input(1,12,0,true,true)) end
check(draws==1,"one randomized tolerance per appearance, never per frame")
check(close(state.exposure,.5/3.5),"close exposure accumulates in normalized threshold units")
Gaze.Step(state,0,input(1,12,0,true,true))
check(draws==1,"zero dt does not redraw tolerance")

for _,fps in ipairs({30,60,144}) do
	for _,spec in ipairs({{0,12,2.5},{.5,12,3.5},{1,12,4.5},{0,100,5},{.5,100,6.5},{1,100,8}}) do
		local time,_,result=stare(spec[1],spec[2],fps)
		check(time>=spec[3]-.000001 and time<=spec[3]+1/fps+.000001,"distance/random threshold is frame-rate independent")
		check(result.justVanished and result.exposure==1,"exactly one threshold crossing causes local disappearance")
	end
end

local nearTime,vanished=stare(.5,12,120)
local farTime=stare(.5,100,120)
check(farTime>nearTime,"near watcher disappears faster under sustained eye contact")
local halfTime=stare(.5,12,120,19)
check(close(halfTime,7,1/120+.000001),"edge-of-gaze buildup is weaker than direct gaze")
local result=Gaze.Step(vanished,1/60,input(1,12,0,true,true))
check(result.hideForAppearance and not result.justVanished,"vanish remains latched without a second trigger")
for _=1,300 do result=Gaze.Step(vanished,1/60,input(1,12,90,false,false)) end
check(result.hideForAppearance and result.fovOffset==0,"look-away cannot resurrect this appearance; FOV settles to zero")
result=Gaze.Step(vanished,0,input(2,12,0,true,true))
check(not result.hideForAppearance and result.exposure==0 and result.intensity==0,"new server appearance resets the local latch")

local decaying=fixed(.5)
for _=1,120 do Gaze.Step(decaying,1/60,input(1,12,0,true,true)) end
local before=decaying.exposure
for _=1,90 do result=Gaze.Step(decaying,1/60,input(1,12,90,true,true)) end
check(close(decaying.exposure,before-.3,1e-8),"look-away decays exposure at 0.20 per second")
check(result.intensity<.02,"heartbeat fades gently after look-away")
for _=1,300 do result=Gaze.Step(decaying,1/60,input(1,12,0,false,true)) end
check(result.exposure==0 and result.intensity==0,"occlusion blocks gaze and clears accumulated attention")

for _,spec in ipairs({{12,30,true},{12,90,true},{12,0,false},{145,0,true},{250,0,true}}) do
	local outside=fixed(.5)
	for _=1,600 do result=Gaze.Step(outside,1/60,input(1,spec[1],spec[2],spec[3],true)) end
	check(result.exposure==0 and result.intensity==0 and not result.hideForAppearance,"outside cone/range/LOS has no visual or timer effect")
end
local invalid=fixed(.5)
for _,bad in ipairs({0/0,math.huge,-math.huge,-1}) do
	result=Gaze.Step(invalid,bad,input(1,12,0,true,true))
	check(result.exposure==0 and result.intensity==0,"invalid or negative dt cannot poison state")
end
result=Gaze.Step(invalid,100,input(1,12,0,true,true))
check(close(result.exposure,.1/3.5) and not result.hideForAppearance,"a long stalled frame cannot instantly consume gaze tolerance")
result=Gaze.Step(invalid,1/60,input(1,0/0,0,true,true))
check(result.gazeStrength==0,"invalid spatial data fails inactive")

local a,b=fixed(.35),fixed(.35)
local minFov,maxFov=0,0
for frame=1,720 do
	local id=math.floor((frame-1)/120)+1
	local args=input(id,12,0,true,true)
	local x=Gaze.Step(a,1/60,args)
	local y=Gaze.Step(b,1/60,args)
	check(x.fovOffset==y.fovOffset and x.exposure==y.exposure,"same inputs/RNG produce deterministic camera-free output")
	check(math.abs(x.fovOffset)<=1.5+.000001,"heartbeat never exceeds 1.5 degrees")
	check(x.beatsPerMinute>=60 and x.beatsPerMinute<=105,"heartbeat stays within 60-105 bpm")
	minFov=math.min(minFov,x.fovOffset);maxFov=math.max(maxFov,x.fovOffset)
end
check(minFov<-1 and maxFov>.3,"heartbeat includes smooth zoom-in contraction and smaller zoom-out rebound")
local playerA,playerB=fixed(0),fixed(1)
local ax,bx
for _=1,180 do
	ax=Gaze.Step(playerA,1/60,input(1,12,0,true,true))
	bx=Gaze.Step(playerB,1/60,input(1,12,0,true,true))
end
check(ax.hideForAppearance and not bx.hideForAppearance,"independent clients can vanish at different local thresholds")

print("PASS Window Watcher gaze: "..assertions.." assertions; near median "..string.format("%.3f",nearTime).."s, far median "..string.format("%.3f",farTime).."s; no camera/native rendering claim")
