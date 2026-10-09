local KEYS={"l6_chase_shriek","l6_chase_loop","l6_rage_scream","l6_rage_loop","l6_kill_grab","l6_kill_breath"}
local checks=0
local function check(value,message) checks+=1; assert(value,message) end
local function equal(actual,expected,message)
 check(actual==expected,message..": expected "..tostring(expected)..", got "..tostring(actual))
end
local function signal()
 local out={Connections={}}
 function out:Connect(callback)
  local connection={Connected=true,Callback=callback}
  function connection:Disconnect() self.Connected=false end
  self.Connections[#self.Connections+1]=connection return connection
 end
 function out:Once(callback)
  local connection
  connection=self:Connect(function(...) connection:Disconnect(); callback(...) end)
  return connection
 end
 function out:Fire(...)
  for _,connection in ipairs(table.clone(self.Connections)) do
   if connection.Connected then connection.Callback(...) end
  end
 end
 return out
end
local function environment()
 local env={Time=0,Jobs={},Errors={},Calls={},Plans={},EngineActive=0,EngineMaxActive=0,Clones={},VoiceWaits=0,Warnings={}}
 local function resume(job)
  local ok,delay=coroutine.resume(job.Thread)
  if not ok then env.Errors[#env.Errors+1]=tostring(delay); job.Done=true; return end
  if coroutine.status(job.Thread)=="dead" then job.Done=true
  else job.Due=env.Time+(type(delay)=="number" and delay or 0.03) end
 end
 env.Task={}
 function env.Task.wait(delay) return coroutine.yield(delay or 0.03) end
 function env.Task.spawn(callback,...)
  local args=table.pack(...)
  local job={Thread=coroutine.create(function() callback(table.unpack(args,1,args.n)) end),Due=env.Time}
  env.Jobs[#env.Jobs+1]=job resume(job) return job.Thread
 end
 function env.Task.defer(callback,...)
  local args=table.pack(...)
  return env.Task.spawn(function() env.Task.wait(0.001); callback(table.unpack(args,1,args.n)) end)
 end
 function env:Advance(duration)
  local deadline=self.Time+duration local steps=0
  while true do
   local job
   for _,candidate in ipairs(self.Jobs) do
    if not candidate.Done and candidate.Due<=deadline and (not job or candidate.Due<job.Due) then job=candidate end
   end
   if not job then break end
   self.Time=job.Due resume(job) steps+=1 assert(steps<20000,"Scheduler did not settle")
  end
  self.Time=deadline
 end
 env.Player={Attributes={},Signals={}}
 function env.Player:GetAttribute(key) return self.Attributes[key] end
 function env.Player:GetAttributeChangedSignal(key)
  if not self.Signals[key] then self.Signals[key]=signal() end return self.Signals[key]
 end
 function env.Player:SetAttribute(key,value)
  local previous=self.Attributes[key] self.Attributes[key]=value
  if previous~=value then self:GetAttributeChangedSignal(key):Fire() end
 end
 local function sound(key)
  local out={Name=key,SoundId="rbxassetid://"..key,Ended=signal(),Played=false,Destroyed=false}
  function out:Clone()
   local copy=sound(self.Name) env.Clones[#env.Clones+1]=copy return copy
  end
  function out:Play() self.Played=true end
  function out:Destroy() self.Destroyed=true end
  return out
 end
 env.Voice={Sounds={}}
 for _,key in ipairs(KEYS) do env.Voice.Sounds[key]=sound(key) end
 function env.Voice:FindFirstChild(key) return self.Sounds[key] end
 env.Counter={Voice=env.Voice}
 function env.Counter:FindFirstChild(key) return key=="Voice" and self.Voice or nil end
 function env.Counter:WaitForChild(key,timeout)
  env.VoiceWaits+=1
  if env.FailVoiceWait then error("Synthetic Voice setup error") end
  local deadline=env.Time+(timeout or 30)
  while not self:FindFirstChild(key) and env.Time<deadline do env.Task.wait(0.05) end
  return self:FindFirstChild(key)
 end
 env.CP={}
 function env.CP:PreloadAsync(objects,callback)
  local call={Objects=table.clone(objects),Key=objects[1] and objects[1].Name,Returned=false}
  env.Calls[#env.Calls+1]=call
  env.EngineActive+=1 env.EngineMaxActive=math.max(env.EngineMaxActive,env.EngineActive)
  local plan=env.Plans[#env.Calls] or {}
  while plan.Gate and not plan.Gate.Open do env.Task.wait(0.05) end
  env.EngineActive-=1
  if plan.Throw then error("Synthetic sound preload exception") end
  for _,status in ipairs(plan.Statuses or {"Success"}) do callback(objects[1].SoundId,status) end
  if plan.ThrowAfterCallbacks then error("Synthetic sound preload exception after callback") end
  call.Returned=true
 end
 env.Game={GetService=function(_,name) assert(name=="ContentProvider","Unexpected service "..name); return env.CP end}
 env.Enum={AssetFetchStatus={Success="Success",Failure="Failure",Loading="Loading"}}
 return env
end
local function install(env)
 local task,player,counter,game,Enum,IN_PREVIEW,AUDIO_ENABLED,audio,GENERAL,soft,warn =
  env.Task,env.Player,env.Counter,env.Game,env.Enum,"Level6PlaygroundPreview",true,{},1,function(object,volume) object.Volume=volume end,
  function(message) env.Warnings[#env.Warnings+1]=message end
 -- __ACTUAL_LEVEL6_AUDIO_SOURCE__
 return {Refused=refused,OneShot=oneShot}
end
local function enter(env) env.Player:SetAttribute("Level6PlaygroundPreview",true) end
local function leave(env) env.Player:SetAttribute("Level6PlaygroundPreview",false) end
local function noErrors(env,label) equal(#env.Errors,0,label.." unhandled errors: "..table.concat(env.Errors,"; ")) end

-- Lobby and Level 5 share the preview flag, but neither may start these six
-- Level 6-specific real sound preloads.
do
 local env=environment() local api=install(env)
 env:Advance(0.2)
 equal(#env.Calls,0,"Lobby has zero Level 6 effect requests")
 equal(env.VoiceWaits,0,"Lobby has no Voice wait owner")
 env.Player:SetAttribute("Level5VoidRound",true) enter(env) env:Advance(0.2)
 equal(#env.Calls,0,"Shared Level 5 preview flag remains ineligible")
 env.Player:SetAttribute("Level5VoidRound",false) env:Advance(0.2)
 equal(#env.Calls,6,"Leaving Level 5 gate while preview remains true starts Level 6 pass")
 for i,key in ipairs(KEYS) do equal(env.Calls[i].Key,key,"Real sound order "..i) end
 equal(env.EngineMaxActive,1,"Successful pass has one engine owner")
 leave(env) enter(env) env:Advance(0.2)
 equal(#env.Calls,6,"Completed pass never repeats on reentry")
 noErrors(env,"Eligibility and completion")
end

-- Leave during an uncancellable request; attribute callbacks cannot create a
-- second owner. After the old engine call drains no next sound is loaded until
-- eligible again. A full pass can then complete and stay complete.
do
 local env=environment() local gate={Open=false} env.Plans[1]={Gate=gate}
 local api=install(env) enter(env)
 equal(#env.Calls,1,"First eligible call starts") equal(env.EngineActive,1,"Yielding engine owns request")
 leave(env) env:Advance(0.2)
 equal(#env.Calls,1,"Leaving does not start later sound calls")
 equal(env.EngineActive,1,"Leaving retains in-flight engine owner")
 enter(env) leave(env) enter(env) leave(env) env:Advance(0.2)
 equal(#env.Calls,1,"Reentry while draining cannot overlap owners")
 gate.Open=true env:Advance(0.2)
 equal(env.EngineActive,0,"Old engine drains before new work")
 equal(#env.Calls,1,"Gate checked again before every next engine call")
 enter(env) env:Advance(0.3)
 equal(#env.Calls,6,"Reentry resumes remaining sounds without duplicate fetches")
 for i,key in ipairs(KEYS) do equal(env.Calls[i].Key,key,"Resumed real sound order "..i) end
 local loaded={} for _,call in ipairs(env.Calls) do loaded[call.Key]=true end
 for _,key in ipairs(KEYS) do check(loaded[key],"Reentry eventually checks "..key) end
 equal(env.EngineMaxActive,1,"Reentry never overlaps engine owners")
 local completeCount=#env.Calls leave(env) enter(env) env:Advance(0.2)
 equal(#env.Calls,completeCount,"Completed resumed pass stays complete")
 noErrors(env,"Leaving and reentry")
end

-- Reentry can happen before the old engine returns and remain eligible. The
-- same owner continues after drain; no lost signal or second owner is needed.
do
 local env=environment() local gate={Open=false} env.Plans[1]={Gate=gate}
 local api=install(env) enter(env) leave(env) enter(env) env:Advance(0.2)
 equal(#env.Calls,1,"Early eligible reentry waits for in-flight call")
 gate.Open=true env:Advance(0.2)
 equal(#env.Calls,6,"Existing owner resumes eligible reentry after drain")
 equal(env.EngineMaxActive,1,"Early reentry has one engine owner")
 noErrors(env,"Early eligible reentry")
end

-- Level 5 becoming active during the first call also stops later calls. Its
-- marker removal alone restarts the remaining checks while preview stays true.
do
 local env=environment() local gate={Open=false} env.Plans[1]={Gate=gate}
 local api=install(env) enter(env) env.Player:SetAttribute("Level5VoidRound",true)
 gate.Open=true env:Advance(0.2)
 equal(#env.Calls,1,"Level 5 gate is checked before later sound calls")
 env.Player:SetAttribute("Level5VoidRound",false) env:Advance(0.2)
 equal(#env.Calls,6,"Level 5 marker signal resumes only remaining sounds")
 equal(env.EngineMaxActive,1,"Level 5 gate transition has one engine owner")
 noErrors(env,"Level 5 transition")
end

-- Enter/leave while waiting for Voice also retains one preparation owner and
-- checks eligibility after the child arrives before any engine work starts.
do
 local env=environment() local voice=env.Voice env.Counter.Voice=nil
 local api=install(env) enter(env) env:Advance(0.1)
 equal(env.VoiceWaits,1,"Waiting for Voice owns one worker")
 leave(env) enter(env) leave(env) env:Advance(0.1)
 equal(env.VoiceWaits,1,"Reentry does not overlap Voice preparation owner")
 env.Counter.Voice=voice env:Advance(0.2)
 equal(#env.Calls,0,"Voice arriving after exit cannot load Level 6 sounds")
 enter(env) env:Advance(0.2)
 equal(#env.Calls,6,"Later eligible entry uses arriving Voice")
 equal(env.EngineMaxActive,1,"Voice retry maintains one engine owner")
 noErrors(env,"Voice wait ownership")
end

-- A missing Voice times out without falsely completing the pass. A later
-- eligible entry can retry. An outer setup error likewise releases ownership.
do
 local env=environment() local voice=env.Voice env.Counter.Voice=nil
 local api=install(env) enter(env) env:Advance(30.1)
 equal(#env.Calls,0,"Voice timeout has zero engine calls")
 equal(env.VoiceWaits,1,"Voice timeout drains one owned wait")
 env.Counter.Voice=voice leave(env) enter(env) env:Advance(0.2)
 equal(#env.Calls,6,"Voice timeout never marks pass completed")
 equal(env.VoiceWaits,2,"Later entry retries Voice preparation")
 noErrors(env,"Voice timeout retry")
end
do
 local env=environment() env.FailVoiceWait=true
 local api=install(env) enter(env) env:Advance(0.2)
 equal(#env.Calls,0,"Outer setup error invokes no engine")
 equal(#env.Warnings,1,"Outer setup error reports bounded warning")
 env.FailVoiceWait=false leave(env) enter(env) env:Advance(0.2)
 equal(#env.Calls,6,"Outer setup error releases owner for later retry")
 equal(env.EngineMaxActive,1,"Outer setup retry does not overlap engine calls")
 noErrors(env,"Outer setup retry")
end

-- Script initialization during a real eligible Level 6 entry still checks
-- effects once; a missing authored Sound keeps oneShot's normal fallback.
do
 local env=environment() env.Player:SetAttribute("Level6PlaygroundPreview",true)
 env.Voice.Sounds[KEYS[1]]=nil
 local api=install(env) env:Advance(0.2)
 equal(#env.Calls,5,"Initially eligible player checks available authored sounds")
 equal(api.OneShot(KEYS[1],0.5),nil,"Missing authored source uses normal fallback")
 equal(api.Refused[KEYS[1]],nil,"Missing source fabricates no fetch result")
 leave(env) enter(env) env:Advance(0.2)
 equal(#env.Calls,5,"Completed available-sound pass never repeats")
 noErrors(env,"Initially eligible missing source")
end

-- Refused-key behavior is supplied by actual callbacks. The exact oneShot
-- consumer returns nil so its caller uses the existing fallback.
do
 local env=environment() env.Plans[1]={Statuses={"Failure","Success"}} env.Plans[2]={Statuses={"Loading"}}
 local api=install(env) enter(env) env:Advance(0.2)
 check(api.Refused[KEYS[1]]==true,"Failed real callback retains refused key after later Success")
 check(api.Refused[KEYS[2]]==true,"Non-success Loading callback retains refused key")
 equal(api.OneShot(KEYS[1],0.5),nil,"Refused key uses caller fallback")
 equal(api.OneShot(KEYS[2],0.5),nil,"Loading status also uses fallback")
 equal(#env.Clones,0,"Refused key never plays silent clone")
 equal(api.OneShot(KEYS[3],0.5),true,"Successful sound still plays")
 equal(#env.Clones,1,"Supported sound has one clone") check(env.Clones[1].Played,"Successful source clone plays")
 equal(#env.Calls,6,"Failure callback does not abandon full check pass")
 noErrors(env,"Callback fallback")
end

-- Baseline pcall semantics remain: an engine exception does not fabricate a
-- callback or refused result, and the next sound is still checked. A refusal
-- genuinely delivered before an exception is preserved.
do
 local env=environment() env.Plans[1]={Throw=true} env.Plans[2]={Statuses={"Failure"},ThrowAfterCallbacks=true}
 local api=install(env) enter(env) env:Advance(0.2)
 equal(api.Refused[KEYS[1]],nil,"Engine exception does not fabricate refused callback")
 equal(api.Refused[KEYS[2]],true,"Real refusal before engine error persists")
 equal(#env.Calls,6,"Caught engine errors preserve remaining checks")
 equal(api.OneShot(KEYS[2],0.5),nil,"Refusal before exception still selects fallback")
 equal(env.EngineMaxActive,1,"Caught errors do not create overlapping owners")
 noErrors(env,"Exception semantics")
end

print("Level 6 deferred audio actual-source contract: "..checks.." checks passed")
