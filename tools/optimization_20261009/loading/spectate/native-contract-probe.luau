return function()

local checks=0
local function check(v,message) assert(v,message); checks+=1 end
local function signal()
 local listeners={}
 return {
  Connect=function(_,fn) table.insert(listeners,fn); return {Disconnect=function() end} end,
  Fire=function(_,...) for _,fn in ipairs(listeners) do fn(...) end end,
  Count=function() return #listeners end,
 }
end
local function scenario()
 local c={Roster={},inRound={},Tasks={},Warnings={}}
 c.World={}
 c.Players={PlayerRemoving=signal()}
 function c.Players:GetPlayers() return c.Roster end
 function c.Players:GetPlayerByUserId(id)
  for _,p in ipairs(c.Roster) do if p.UserId==id and p.Parent==self then return p end end
 end
 function c:Character(p,health,withRoot)
  local char={Parent=self.World,Humanoid={Health=health},Root=nil}
  function char:FindFirstChildOfClass(class) return class=="Humanoid" and self.Humanoid end
  function char:FindFirstChild(name) return name=="HumanoidRootPart" and self.Root end
  if withRoot~=false then self:AddRoot(char) end
  p.Character=char; p.hum=char.Humanoid
  return char
 end
 function c:AddRoot(char)
  local root={Parent=char}
  function root:IsA(class) return class=="BasePart" end
  function root:IsDescendantOf(parent) return self.Parent and self.Parent.Parent==parent end
  char.Root=root; return root
 end
 function c:Player(id,health)
  local p={UserId=id,Parent=self.Players,attrs={},Foci={},AddCalls=0,RemoveCalls=0,
   Peak=0,ReplicationFocus={Own=true},FocusEvents={}}
  function p:GetAttribute(k) return self.attrs[k] end
  function p:SetAttribute(k,v) self.attrs[k]=v end
  function p:AddReplicationFocus(part)
   self.AddCalls+=1
   if self.FailAdd then self.FailAdd=false; error("synthetic add error") end
   assert(part:IsA("BasePart") and part:IsDescendantOf(c.World),"focus must be live BasePart")
   assert(not self.Foci[part],"same focus added twice")
   self.Foci[part]=true; table.insert(self.FocusEvents,{"add",part})
   local n=0 for _ in pairs(self.Foci) do n+=1 end self.Peak=math.max(self.Peak,n)
  end
  function p:RemoveReplicationFocus(part)
   self.RemoveCalls+=1
   if self.FailRemove then self.FailRemove=false; error("synthetic remove error") end
   assert(self.Foci[part],"foreign or already removed focus")
   self.Foci[part]=nil; table.insert(self.FocusEvents,{"remove",part})
  end
  self:Character(p,health or 100)
  table.insert(self.Roster,p); self.inRound[p]=true
  return p
 end
 function c:Tick()
  for _,thread in ipairs(self.Tasks) do
   local ok,problem=coroutine.resume(thread)
   assert(ok,problem)
  end
 end
 local Players,workspace,inRound=c.Players,c.World,c.inRound
 local spectateTargets={}
 local task={
  spawn=function(fn) table.insert(c.Tasks,coroutine.create(fn)) end,
  wait=function() coroutine.yield(); return true end,
 }
 local function warn(message) table.insert(c.Warnings,message) end
local function validSpectatePair(player, target)
 if target == player or player.Parent ~= Players or target.Parent ~= Players
  or inRound[player] ~= true or inRound[target] ~= true
  or target:GetAttribute("Escaped") == true then return false end
 local ownHumanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
 local targetHumanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
 return (player:GetAttribute("Escaped") == true or not ownHumanoid or ownHumanoid.Health <= 0)
  and targetHumanoid ~= nil and targetHumanoid.Health > 0
end
-- PERFORMANCE_STREAMING_20261009: a Scriptable spectator camera follows another
-- body. Keep that body's region streamed with one extra focus; never replace the
-- spectator's default own-character focus. The existing 1 s reconciliation owns
-- character/root changes, death and respawn; no per-target connections accumulate.
local spectateFocus = {Records = {}}
function spectateFocus:Clear(player)
 local record = self.Records[player]
 if not record then return true end
 if record.Part and player.Parent == Players then
  local ok, problem = pcall(function() player:RemoveReplicationFocus(record.Part) end)
  if not ok then
   -- Keep ownership and retry next reconciliation. Never add a second focus
   -- while removal of the first has not been confirmed.
   warn("[SpectateStreaming] remove focus: " .. tostring(problem))
   return false
  end
 end
 self.Records[player] = nil
 return true
end
function spectateFocus:Sync(player, target)
 local record = self.Records[player]
 if record and record.Character ~= player.Character then
  self:Clear(player)
  return false -- a respawn ends the previous camera owner
 end
 local character = target.Character
 local root = character and character:FindFirstChild("HumanoidRootPart")
 if root and (not root:IsA("BasePart") or not root:IsDescendantOf(workspace)) then root = nil end
 if record and record.Part == root then return true end
 if not self:Clear(player) then return true end
 record = {Character = player.Character}
 self.Records[player] = record
 if root then
  local ok, problem = pcall(function() player:AddReplicationFocus(root) end)
  if ok then
   record.Part = root
  else
   warn("[SpectateStreaming] add focus: " .. tostring(problem))
  end
 end
 return true
end
local function republishSpectatorCounts()
 local counts = {}
 for spectator, target in pairs(spectateTargets) do
  if validSpectatePair(spectator, target) and spectateFocus:Sync(spectator, target) then
   counts[target] = (counts[target] or 0) + 1
  else
   spectateTargets[spectator] = nil
   spectateFocus:Clear(spectator)
  end
 end
 for spectator in pairs(spectateFocus.Records) do
  if not spectateTargets[spectator] then spectateFocus:Clear(spectator) end
 end
 for _, subject in ipairs(Players:GetPlayers()) do
  if subject:GetAttribute("SpectatorCount") ~= counts[subject] then
   subject:SetAttribute("SpectatorCount", counts[subject])
  end
 end
end
local function setSpectateTarget(player, targetUserId)
 local target = nil
 if type(targetUserId) == "number" and targetUserId == targetUserId
  and math.abs(targetUserId) < 2^53 and targetUserId % 1 == 0 then
  -- Studio's actual multiplayer clients have negative UserIds. Resolve the
  -- current roster instead of assuming positive production account ids.
  target = Players:GetPlayerByUserId(targetUserId)
 end
 if target and not validSpectatePair(player, target) then target = nil end
 if spectateTargets[player] == target then return end
 spectateTargets[player] = target
 republishSpectatorCounts()
end
local function clearSpectatorCounts()
 if next(spectateTargets) == nil and next(spectateFocus.Records) == nil then return end
 table.clear(spectateTargets)
 republishSpectatorCounts()
end
-- Clear stale reports even when a client stops reporting after its target dies,
-- leaves, escapes, or the spectator respawns. No names are replicated.
task.spawn(function()
 while task.wait(1) do
  if next(spectateTargets) ~= nil or next(spectateFocus.Records) ~= nil then republishSpectatorCounts() end
 end
end)

-- PlayerRemoving fires before Parent leaves Players: detach owned foci now.
Players.PlayerRemoving:Connect(function(leaving)
 for spectator, target in pairs(spectateTargets) do
  if spectator == leaving or target == leaving then
   spectateTargets[spectator] = nil
   spectateFocus:Clear(spectator)
  end
 end
 spectateFocus:Clear(leaving)
 republishSpectatorCounts()
end)


 c.Select=setSpectateTarget; c.Reconcile=republishSpectatorCounts; c.Clear=clearSpectatorCounts
 c.Targets=spectateTargets; c.Records=spectateFocus.Records
 function c:Foci(p) local n=0 for _ in pairs(p.Foci) do n+=1 end return n end
 return c
end
local function count(p,n)
 check((p:GetAttribute("SpectatorCount") or 0)==n,"count "..tostring(n))
end
do -- Retain the existing spectator-count validation contract.
 local c=scenario(); local a,b,d=c:Player(-1),c:Player(-2),c:Player(42)
 c.Select(b,a.UserId); count(a,0); check(c:Foci(b)==0,"living spectator rejected")
 b.attrs.Escaped=true; c.Select(b,a.UserId); count(a,1)
 check(c:Foci(b)==1 and b.Foci[a.Character.Root],"validated negative Studio UserId can focus target")
 local own=b.ReplicationFocus
 c.Select(b,a.UserId); count(a,1)
 check(b.AddCalls==1,"duplicate selection does not add focus twice")
 c.Select(b,d.UserId); count(a,0); count(d,1)
 check(c:Foci(b)==1 and b.Foci[d.Character.Root] and b.Peak==1,"selection changes remove before add")
 check(b.FocusEvents[2][1]=="remove" and b.FocusEvents[3][1]=="add","focus handover order")
 c.Select(b,b.UserId); count(b,0); count(d,0); check(c:Foci(b)==0,"self target cleans previous focus")
 c.Select(b,math.huge); count(a,0)
 c.Select(b,a.UserId+.5); count(a,0)
 c.Select(b,a.UserId); a.attrs.Escaped=true; c.Reconcile(); count(a,0)
 check(c:Foci(b)==0,"escaped target cleared")
 a.attrs.Escaped=false; c.Select(b,a.UserId); a.hum.Health=0; c.Reconcile(); count(a,0)
 check(c:Foci(b)==0,"dead target cleared")
 a.hum.Health=100; c.Select(b,a.UserId); b.attrs.Escaped=false; c.Reconcile(); count(a,0)
 check(c:Foci(b)==0,"spectator revival invalidates pair")
 b.hum.Health=0; c.Select(b,a.UserId); count(a,1)
 c.inRound[a]=false; c.Reconcile(); count(a,0)
 check(c:Foci(b)==0,"target leaving round clears focus")
 c.inRound[a]=true; c.Select(b,a.UserId); c.Clear(); count(a,0)
 check(c:Foci(b)==0 and next(c.Records)==nil and next(c.Targets)==nil,"round reset clears all ownership")
 check(b.ReplicationFocus==own,"default own-character focus unchanged")
 check(c.Players.PlayerRemoving:Count()==1,"one lifetime leaving connection, no per-pair connections")
end
do
 local c=scenario(); local a,b,d=c:Player(1),c:Player(2,0),c:Player(3,0)
 c.Select(b,a.UserId); c.Select(d,a.UserId); count(a,2)
 check(c:Foci(b)==1 and c:Foci(d)==1,"multiple spectators each own one focus")
 c.Players.PlayerRemoving:Fire(a); count(a,0)
 check(c:Foci(b)==0 and c:Foci(d)==0 and next(c.Records)==nil,"target departure detaches every watcher before Parent changes")
 check(next(c.Targets)==nil,"departing target references removed")
end
do
 local c=scenario(); local a,b=c:Player(1),c:Player(2,0)
 c.Select(b,a.UserId); c.Players.PlayerRemoving:Fire(b)
 check(c:Foci(b)==0 and c.Targets[b]==nil and c.Records[b]==nil,"spectator departure immediate cleanup")
end
do
 local c=scenario(); local a,b=c:Player(1),c:Player(2,0)
 c.Select(b,a.UserId)
 local old=a.Character.Root
 local replacement=c:Character(a,100,false); c.Reconcile()
 check(c:Foci(b)==0 and not b.Foci[old],"target character replacement releases old root without waiting for new one")
 local fresh=c:AddRoot(replacement); c.Reconcile()
 check(c:Foci(b)==1 and b.Foci[fresh] and b.Peak==1,"new target root adopted once")
 c.Reconcile(); check(b.AddCalls==2,"steady reconciliation is idempotent")
 fresh.Parent=nil; c.Reconcile()
 check(c:Foci(b)==0,"detached root never retains focus")
 local newer=c:AddRoot(replacement); c.Reconcile()
 check(c:Foci(b)==1 and b.Foci[newer],"replacement root recovered")
end
do
 local c=scenario(); local a,b=c:Player(1),c:Player(2)
 b.attrs.Escaped=true; c.Select(b,a.UserId)
 c:Character(b,100); c.Reconcile(); count(a,0)
 check(c:Foci(b)==0 and c.Targets[b]==nil and c.Records[b]==nil,"escaped spectator respawn ends old camera owner")
end
do
 local c=scenario(); local a,b=c:Player(1),c:Player(2,0)
 b.FailAdd=true; c.Select(b,a.UserId)
 check(c:Foci(b)==0 and #c.Warnings==1,"add error does not fabricate ownership")
 c.Reconcile()
 check(c:Foci(b)==1 and b.AddCalls==2,"existing reconciliation retries failed add")
 c.Clear(); check(c:Foci(b)==0 and next(c.Records)==nil,"retry ownership clears on end")
end
do
 local c=scenario(); local a,b,d=c:Player(1),c:Player(2,0),c:Player(3)
 c.Select(b,a.UserId); b.FailRemove=true; c.Select(b,d.UserId)
 check(c:Foci(b)==1 and b.Foci[a.Character.Root] and b.AddCalls==1,"failed removal prevents a second focus")
 c.Reconcile()
 check(c:Foci(b)==1 and b.Foci[d.Character.Root] and b.Peak==1,"next reconciliation finishes handover safely")
 check(b.RemoveCalls==2 and #c.Warnings==1,"failed remove retry remains bounded")
end
do
 local c=scenario(); local a,b=c:Player(1),c:Player(2,0)
 c.Select(b,a.UserId); b.FailRemove=true; c.Clear()
 check(next(c.Targets)==nil and c.Records[b]~=nil,"failed end removal retains ownership for retry")
 c:Tick(); c:Tick()
 check(c:Foci(b)==0 and next(c.Records)==nil,"existing one-second task retries even when target map is empty")
end
do
 local c=scenario(); local a,b=c:Player(1),c:Player(2,0)
 c.Select(b,a.UserId); b.Parent=nil; c.Reconcile()
 check(c.Targets[b]==nil and c.Records[b]==nil,"already departed player cannot retain source references")
 -- Engine destroys that player's streaming state; no API request targets an absent Player.
 check(b.RemoveCalls==0,"no remove operation on departed Player")
end
print("spectator focus contract checks: "..checks)

end
