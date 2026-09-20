local Research=require("../../ReplicatedStorage/ZyntraDailyResearch.ModuleScript")
local DailyResearch=Research
local DAILY_REWARDS={Milestones={{Minutes=5},{Minutes=15},{Minutes=35}}}
local function wholeCount(v) return type(v)=="number" and v==v and v>=0 and v<math.huge and v%1==0 and v or 0 end
local function normalizeDaily(value)
	local saved = type(value) == "table" and value or {}
	local function savedDay(field)
		local day = saved[field]
		return type(day) == "string" and #day == 10 and day or nil
	end
	local claimed = {}
	local savedClaimed = type(saved.Claimed) == "table" and saved.Claimed or {}
	for _, milestone in ipairs(DAILY_REWARDS.Milestones or {}) do
		local key = tostring(milestone.Minutes)
		if savedClaimed[key] == true then claimed[key] = true end
	end
	local wheelDay = savedDay("WheelDay")
	local wheelLast
	local savedLast = type(saved.WheelLast) == "table" and saved.WheelLast or nil
	if savedLast and type(savedLast.Key) == "string"
		and #savedLast.Key > 0 and #savedLast.Key <= 64 then
		local lastDay = savedLast.Day
		wheelLast = {
			Day = type(lastDay) == "string" and #lastDay == 10 and lastDay or wheelDay,
			Key = savedLast.Key,
			Serial = wholeCount(savedLast.Serial),
		}
	end
	local flushId = saved.FlushId
	return {
		-- Deliberately left nil when a save has none: "these counters belong to no
		-- day yet" is exactly right for a profile written before daily rewards
		-- existed, and the first daily transaction rolls it onto today. Reading the
		-- clock here instead would make normalization depend on it.
		Day = savedDay("Day"),
		Research = DailyResearch.Normalize(saved.Research),
		PlaytimeSeconds = wholeCount(saved.PlaytimeSeconds),
		Claimed = claimed,
		WheelDay = wheelDay,
		WheelLast = wheelLast,
		FlushId = type(flushId) == "string" and #flushId > 0 and #flushId <= 128 and flushId or nil,
	}
end

local function rollDaily(data, today)
	local daily = data.Daily
	if daily.Day == today then return false end
	daily.Day = today
	daily.PlaytimeSeconds = 0
	daily.Claimed = {}
	daily.Research = DailyResearch.Normalize(nil)
	return true
end


local passed=0
local function check(condition,message) assert(condition,message) passed+=1 end
local d={Tokens=10,Daily=normalizeDaily({Day="2026-09-20",PlaytimeSeconds=300,Claimed={["5"]=true}})}
check(#Research.Public(d.Daily.Research,true)==3,"three goals")
check(Research.Complete(d,"Fuse") and d.Tokens==11,"fuse award")
check(not Research.Complete(d,"Fuse") and d.Tokens==11,"duplicate completion")
local rejoined={Tokens=d.Tokens,Daily=normalizeDaily(d.Daily)}
check(not Research.Complete(rejoined,"Fuse") and rejoined.Tokens==11,"saved completion survives normalization/rejoin")
check(Research.Complete(rejoined,"Lever") and rejoined.Tokens==12,"lever reward")
check(Research.Complete(rejoined,"Clear") and rejoined.Tokens==14,"escape reward")
check(not Research.Complete(rejoined,"Clear") and rejoined.Tokens==14,"lost response retry is idempotent")
check(not Research.Complete(rejoined,"invented") and rejoined.Tokens==14,"unknown goal refused")
check(not rollDaily(rejoined,"2026-09-20") and rejoined.Daily.Research.Fuse,"same-day no reroll")
local yesterday=Research.Public(rejoined.Daily.Research,false)
check(not yesterday[1].Complete and not yesterday[2].Complete and not yesterday[3].Complete,"midnight read hides yesterday")
check(rollDaily(rejoined,"2026-09-21") and not rejoined.Daily.Research.Fuse and next(rejoined.Daily.Claimed)==nil and rejoined.Daily.PlaytimeSeconds==0,"one shared UTC reset")
check(Research.Complete(rejoined,"Fuse") and rejoined.Tokens==15,"next day can earn again")
check(not rollDaily(rejoined,"2026-09-21") and not Research.Complete(rejoined,"Fuse"),"second rollover cannot reset twice")
local corrupt=Research.Normalize({Fuse="true",Lever=1,Clear=true,Fake=true})
check(not corrupt.Fuse and not corrupt.Lever and corrupt.Clear and corrupt.Fake==nil,"bounded schema")
local full={Tokens=9007199254740991,Daily={Research=Research.Normalize(nil)}}
check(not Research.Complete(full,"Fuse") and not full.Daily.Research.Fuse,"overflow cannot consume completion")
print("Daily research:",passed,"checks passed")
