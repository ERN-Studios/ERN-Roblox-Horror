local checks=0
local function check(ok,why) checks+=1;assert(ok,why) end
local function fresh()
 local shared={} local KEY="test" local allowed=true
 local function mode()assert(allowed,"mode changed")end
 local originalList,originalMap={},{}
local token,ownedConnections={},{}
local state={token=token,connections=ownedConnections,phase="captured"}
local function ownedLease()
 return shared[KEY]==state and state.token==token and state.connections==ownedConnections
  and next(ownedConnections)==nil and state.phase=="captured"
end
local function claimLease()
 mode()
 -- No yield between this fresh compare and claim: the earlier census can yield.
 assert(shared[KEY]==nil,"A foreign room probe lease appeared during census")
 shared[KEY]=state
end
local function releaseLease()
 if not ownedLease() then return false end
 shared[KEY]=nil
 return true
end
local function guard(fullCensus)
 mode() assert(ownedLease(),"Probe state/token/connections ownership changed")
 for _,n in originalList do
  local saved=originalMap[n] local m=metadata(n)
  assert(n.Parent==saved.metadata.parent and m.path==saved.metadata.path and m.className==saved.metadata.className,"Original identity/Parent/class changed")
  assert(n.Source==saved.source and SES:GetEditorSource(n)==saved.source,"Authoritative Source/editor changed")
  assert(stable(m.properties)==saved.props and stable(m.attributes)==saved.attrs and stable(m.tags)==saved.tags,"Authoritative properties/attrs/tags changed")
 end
 if fullCensus then
  local count=0 for index,n in game:GetDescendants() do
   if n:IsA("LuaSourceContainer") then assert(originalMap[n],"New authoritative Source appeared");count+=1 end
   if index%10000==0 then task.wait();mode();assert(ownedLease(),"Lease changed during final census") end
  end
  assert(count==#originalList,"Authoritative Source removed")
  -- Repeat after the yielding census; point-in-time guard, not a continuous epoch claim.
  guard(false)
 end
end

 return {shared=shared,key=KEY,state=state,token=token,connections=ownedConnections,
 claim=claimLease,release=releaseLease,guard=guard,owned=ownedLease,
 setMode=function(v)allowed=v end}
end
local a=fresh();a.claim();a.guard(false)
check(a.owned(),"normal lease owns exact state/token/connections")
check(a.release() and a.shared[a.key]==nil,"normal release clears only owned key")
local b=fresh();local foreign={token={},connections={},phase="foreign",report={keep=true}}
b.shared[b.key]=foreign;local ok=pcall(b.claim)
check(not ok,"post-census foreign lease rejects claim")
check(b.shared[b.key]==foreign and foreign.report.keep,"foreign preclaim state preserved")
for _,kind in {"token","connections","nonempty","phase","shared"} do
 local c=fresh();c.claim();local replacement={token={},connections={},phase="other",report={keep=true}}
 if kind=="token" then c.state.token={} elseif kind=="connections" then c.state.connections={}
 elseif kind=="nonempty" then c.connections.foreign=true elseif kind=="phase" then c.state.phase="foreign"
 else c.shared[c.key]=replacement end
 local saved=c.shared[c.key];local token=saved.token;local connections=saved.connections;local phase=saved.phase
 check(not pcall(function()c.guard(false)end),kind.." exact guard rejects")
 check(not c.release(),kind.." release refuses foreign ownership")
 check(c.shared[c.key]==saved and saved.token==token and saved.connections==connections and saved.phase==phase,
  kind.." foreign metadata preserved")
end
local d=fresh();d.setMode(false)
check(not pcall(d.claim) and d.shared[d.key]==nil,"mode guard rejects before claim")
print("OWNERSHIP_CHECKS="..checks)
