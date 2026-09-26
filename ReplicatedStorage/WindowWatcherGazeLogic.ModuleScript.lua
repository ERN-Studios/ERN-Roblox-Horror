-- Pure client presentation math. No Roblox services, camera writes, audio,
-- animation changes, remotes or server timing. One state belongs to one actor.
-- Pass the SERVER appearance counter even after this client locally hides it.
local Gaze={}
local MAX_DISTANCE=145
local MAX_DT=.1 -- a stalled frame must not consume seconds of unseen exposure
local DECAY_PER_SECOND=.20
local MAX_FOV_DEGREES=1.5

local function finite(value)
	return type(value)=="number" and value==value and math.abs(value)<math.huge
end
local function clamp(value,low,high) return math.min(high,math.max(low,value)) end
local function smooth(value)
	local x=clamp(value,0,1)
	return x*x*(3-2*x)
end
local function distanceBlend(distance)
	return smooth((distance-12)/88)
end
local function measure(angle,distance,lineOfSight)
	local blend=finite(distance) and distanceBlend(distance) or 0
	if lineOfSight~=true or not finite(angle) or not finite(distance) or distance<0 or distance>=MAX_DISTANCE then
		return 0,0,blend
	end
	local angular=smooth((30-math.max(angle,0))/22)
	local farFade=1-smooth((distance-100)/(MAX_DISTANCE-100))
	local gazeStrength=angular*farFade
	local visualDistance=1-.65*blend
	return gazeStrength*visualDistance,gazeStrength,blend
end
local function bump(phase,startAt,endAt)
	if phase<=startAt or phase>=endAt then return 0 end
	local sine=math.sin(math.pi*(phase-startAt)/(endAt-startAt))
	return sine*sine
end
local function heartbeat(phase)
	-- Two smooth contractions with smaller rebounds. Ends and first derivatives
	-- meet at zero, including the 1->0 seam. Negative FOV means a slight zoom in.
	return bump(phase,.02,.14)-.50*bump(phase,.14,.25)
		+.65*bump(phase,.28,.40)-.30*bump(phase,.40,.52)
end
local function resetAppearance(state,appearanceId)
	local unit=state.randomUnit()
	assert(finite(unit),"Window Watcher gaze RNG must return a finite number")
	unit=clamp(unit,0,1)
	state.appearanceId=appearanceId
	-- One linked random draw per appearance; distance never reverses the order.
	state.closeThreshold=2.5+2*unit
	state.farThreshold=5+3*unit
	state.exposure=0;state.vanished=false;state.intensity=0;state.phase=0
end

function Gaze.New(randomUnit)
	assert(randomUnit==nil or type(randomUnit)=="function","Expected RNG callback")
	return {randomUnit=randomUnit or math.random,appearanceId=nil,closeThreshold=3.5,farThreshold=6.5,
		exposure=0,vanished=false,intensity=0,phase=0}
end

function Gaze.Step(state,deltaTime,input)
	input=input or {}
	local dt=finite(deltaTime) and clamp(deltaTime,0,MAX_DT) or 0
	local appearanceId=input.appearanceId
	local validAppearance=(type(appearanceId)=="number" and finite(appearanceId) and appearanceId>=1)
		or (type(appearanceId)=="string" and appearanceId~="")
	if validAppearance and appearanceId~=state.appearanceId then resetAppearance(state,appearanceId) end
	local active=validAppearance and input.active==true and not state.vanished
	local intensityTarget,gazeStrength=0,0
	local blend=finite(input.distance) and distanceBlend(input.distance) or 0
	if active then intensityTarget,gazeStrength,blend=measure(input.angleDegrees,input.distance,input.hasLineOfSight) end
	local threshold=state.closeThreshold+(state.farThreshold-state.closeThreshold)*blend
	local justVanished=false
	if active and gazeStrength>0 then
		state.exposure=clamp(state.exposure+dt*gazeStrength/threshold,0,1)
		if state.exposure>=1 then
			state.vanished=true;justVanished=true;intensityTarget=0
		end
	elseif not state.vanished then
		state.exposure=math.max(0,state.exposure-dt*DECAY_PER_SECOND)
	end
	-- The visual heartbeat fades independently after a look-away/disappearance.
	-- Keep stepping an inactive state until its returned offset settles to zero;
	-- teardown should remove the caller's last owned offset immediately.
	local responseSeconds=intensityTarget>state.intensity and .25 or .35
	state.intensity+=(intensityTarget-state.intensity)*(1-math.exp(-dt/responseSeconds))
	state.intensity=clamp(state.intensity,0,1)
	if state.intensity<.0001 and intensityTarget==0 then state.intensity=0 end
	local bpm=60+45*state.intensity
	state.phase=(state.phase+dt*bpm/60)%1
	local offset=-MAX_FOV_DEGREES*state.intensity*heartbeat(state.phase)
	return {
		hideForAppearance=state.vanished,justVanished=justVanished,
		fovOffset=offset,intensity=state.intensity,gazeStrength=gazeStrength,
		exposure=state.exposure,thresholdSeconds=threshold,beatsPerMinute=bpm,
		appearanceId=state.appearanceId,
	}
end

return Gaze
