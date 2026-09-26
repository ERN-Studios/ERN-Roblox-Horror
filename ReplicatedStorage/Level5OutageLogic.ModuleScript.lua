-- Pure, shared outage timing. No services, Instances or clock reads.
local Logic = {}
Logic.FALL_SECONDS = 5
Logic.BLACKOUT_SECONDS = 60
Logic.RESTORE_SECONDS = 1.5
Logic.FIXTURE_FALL_SECONDS = .5
Logic.REFLASH_POWER = .28
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function integer(n,lo,hi) return finite(n) and n%1==0 and n>=lo and n<=hi end
local function clamp01(n) return math.clamp(n,0,1) end
local function smooth(n) n=clamp01(n);return n*n*(3-2*n) end

function Logic.ValidateSchedule(s)
	return type(s)=="table" and finite(s.startedAt) and finite(s.blackoutAt) and finite(s.restoreAt)
		and integer(s.gate,1,7) and integer(s.serial,1,9007199254740991)
		and math.abs((s.blackoutAt-s.startedAt)-Logic.FALL_SECONDS)<.00001
		and s.restoreAt>=s.blackoutAt+Logic.BLACKOUT_SECONDS-.00001
end

function Logic.NewSchedule(previous,now,gate,serial)
	assert(finite(now),"A finite server time is required")
	assert(integer(gate,1,7),"Gate must be an integer from 1 to 7")
	assert(integer(serial,1,9007199254740991),"Serial must be a positive safe integer")
	if Logic.ValidateSchedule(previous) and now<previous.restoreAt+Logic.RESTORE_SECONDS then
		-- Extend the existing cycle, including during recovery. Recovery interruption
		-- returns straight to black instead of flashing back up to full brightness.
		return {startedAt=previous.startedAt,blackoutAt=previous.blackoutAt,
			restoreAt=math.max(previous.restoreAt,now+Logic.BLACKOUT_SECONDS,previous.blackoutAt+Logic.BLACKOUT_SECONDS),
			gate=previous.gate,serial=serial}
	end
	return {startedAt=now,blackoutAt=now+Logic.FALL_SECONDS,
		restoreAt=now+Logic.FALL_SECONDS+Logic.BLACKOUT_SECONDS,gate=gate,serial=serial}
end

function Logic.Phase(schedule,now)
	if not Logic.ValidateSchedule(schedule) or not finite(now) or now<schedule.startedAt then return "NORMAL" end
	if now<schedule.blackoutAt then return "FALLING" end
	if now<schedule.restoreAt then return "BLACKOUT" end
	if now<schedule.restoreAt+Logic.RESTORE_SECONDS then return "RECOVERING" end
	return "NORMAL"
end

-- Nearest section first; equal-distance ties travel forward before backward.
-- For gate 4: sections 4,5,3,6,2,7,1,8. The result is zero-based, 0..7.
local sectionRanks = {}
for gate=1,7 do
	local ranks={};local order=0
	for distance=0,7 do
		local ahead=gate+distance
		if ahead<=8 then ranks[ahead]=order;order+=1 end
		if distance>0 then local behind=gate-distance;if behind>=1 then ranks[behind]=order;order+=1 end end
	end
	sectionRanks[gate]=ranks
end
function Logic.SectionRank(gate,section)
	assert(integer(gate,1,7) and integer(section,1,8),"Gate/section outside the map")
	return sectionRanks[gate][section]
end

function Logic.FixtureOffTime(schedule,section,order)
	assert(Logic.ValidateSchedule(schedule),"Valid outage schedule required")
	assert(integer(section,1,8) and finite(order) and order>=0 and order<=1,"Valid section and normalized fixture order required")
	local rank=sectionRanks[schedule.gate][section]
	-- Every section occupies a different time band. Last rank/order reaches t=5 exactly.
	return schedule.startedAt+Logic.FALL_SECONDS*(rank+1+order*.5)/8.5
end

function Logic.AmbientPower(schedule,now)
	local phase=Logic.Phase(schedule,now)
	if phase=="NORMAL" then return 1 end
	if phase=="BLACKOUT" then return 0 end
	if phase=="RECOVERING" then return smooth((now-schedule.restoreAt)/Logic.RESTORE_SECONDS) end
	return 1-smooth((now-schedule.startedAt)/Logic.FALL_SECONDS)
end

function Logic.FixturePower(schedule,now,section,order,reduceFlashing)
	local phase=Logic.Phase(schedule,now)
	if phase=="NORMAL" then return 1 end
	if phase=="BLACKOUT" then return 0 end
	if phase=="RECOVERING" then return smooth((now-schedule.restoreAt)/Logic.RESTORE_SECONDS) end
	if not integer(section,1,8) or not finite(order) then return Logic.AmbientPower(schedule,now) end
	order=clamp01(order)
	local offAt=Logic.FixtureOffTime(schedule,section,order)
	local progress=(now-(offAt-Logic.FIXTURE_FALL_SECONDS))/Logic.FIXTURE_FALL_SECONDS
	if progress<=0 then return 1 end
	if progress>=1 then return 0 end
	-- Treat an unknown preference as reduced. The standard branch has one dim reflash,
	-- never a full-power flash; it does not change the server's outage duration.
	if reduceFlashing~=false then return 1-smooth(progress) end
	if progress<.24 then return 1-smooth(progress/.24) end
	if progress<.44 then return 0 end
	if progress<.58 then return Logic.REFLASH_POWER*smooth((progress-.44)/.14) end
	if progress<.68 then return Logic.REFLASH_POWER end
	return Logic.REFLASH_POWER*(1-smooth((progress-.68)/.32))
end
return Logic
