-- Pure local presentation state. No Instances, remotes, clock reads or gameplay writes.
local Logic = {}
Logic.GATE_REASON_GRACE_SECONDS = 1
local function finite(value)
	return type(value)=="number" and value==value and math.abs(value)<math.huge
end
function Logic.AssetId(value)
	if finite(value) and value>0 and value%1==0 then return "rbxassetid://"..string.format("%.0f",value) end
	if type(value)=="string" then
		local digits=value:match("^rbxassetid://(%d+)$") or value:match("^(%d+)$")
		if digits and finite(tonumber(digits)) and tonumber(digits)>0 then return "rbxassetid://"..digits end
	end
	return nil
end
function Logic.New()
	return {gates={},power={},watcher={}}
end
function Logic.Gate(state,index,token,unlocked,reason,now)
	if not finite(index) or index%1~=0 or index<1 or index>7 or type(unlocked)~="boolean" or token==nil then return false,false end
	local old=state.gates[index]
	local record=old and old.token==token and old or {token=token}
	local opened=old~=nil and old.token==token and old.unlocked==false and unlocked==true
	record.unlocked=unlocked;state.gates[index]=record
	-- First replication, world entry and a replacement streamed model establish
	-- a baseline. A completed gate must never replay its opening on arrival.
	if opened and finite(now) then record.reasonDeadline=now+Logic.GATE_REASON_GRACE_SECONDS end
	local unlockCue=false
	if record.reasonDeadline then
		if not unlocked or not finite(now) or now>record.reasonDeadline then
			record.reasonDeadline=nil
		elseif type(reason)=="string" and reason~="" then
			-- Unlocked replicates before OpenReason on the server. Keep only this
			-- observed edge pending briefly; never infer it from an initial true.
			unlockCue=reason=="SOLVED";record.reasonDeadline=nil
		end
	end
	return opened,unlockCue
end
function Logic.Power(state,phase,cycle,exempt)
	local old=state.power
	state.power={phase=phase,cycle=cycle,exempt=exempt==true,ready=true}
	if not old.ready or exempt==true or old.exempt then return nil end
	if phase=="FALLING" and old.phase~="FALLING" and cycle~=nil and cycle~=old.cycle then return "power_fall" end
	if phase=="RECOVERING" and (old.phase=="BLACKOUT" or old.phase=="FALLING") and cycle==old.cycle then return "power_restart" end
	return nil
end
function Logic.Watcher(state,input,now)
	input=input or {}
	local w=state.watcher
	local cues={}
	if not input.present or not finite(now) or not finite(input.appearance) or input.appearance<1 then
		w.continuous=false;w.eligible=false
		return 0,cues
	end
	if w.appearance~=input.appearance then
		w={appearance=input.appearance};state.watcher=w
	end
	local hidden=input.hidden==true
	local valid=input.allowed==true and input.visible==true
	local near=finite(input.distance) and input.distance>=0 and input.distance<145
	local intensity=finite(input.intensity) and math.clamp(input.intensity,0,1) or 0
	local eligible=valid and input.lineOfSight==true and near and not hidden and intensity>.005
	if valid and input.lineOfSight==true and near and hidden and input.recedeAudible==true
		and w.continuous and w.eligible and not w.hidden and not w.receded then
		w.receded=true;table.insert(cues,"watcher_recede")
	end
	if eligible then
		w.firstSeenAt=w.firstSeenAt or now
		if not w.glass and input.glassAudible==true then
			w.glass=true;table.insert(cues,"watcher_glass")
		end
		if not w.breath and input.breathAudible==true and input.distance<=50 and intensity>=.18 and now-w.firstSeenAt>=1.7 then
			w.breath=true;table.insert(cues,"watcher_breath")
		end
	end
	w.continuous=true;w.eligible=eligible;w.hidden=hidden
	return eligible and intensity or 0,cues
end
return table.freeze(Logic)
