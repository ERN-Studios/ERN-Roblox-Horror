-- ISOLATED VALUE-MOCK FIXTURE: no Instances, world writes, real waits, or gameplay changes.
-- The two methods below are byte-identical to the cache candidate after the
-- three replacements in route-install-budget-patch.json. Only dependencies mocked.
local now=0
local os={clock=function() return now end}
local planningThreads={}
local Navigator={}
local function horizontalDistance(a,b) return Vector3.new(a.X-b.X,0,a.Z-b.Z).Magnitude end
function Navigator:_smoothStableRoute(points, origin, deadline)
	-- Shortcutting is optional: never spend the installation deadline on an
	-- already-certified route. Native edge checks share this short budget.
	local context = planningThreads[coroutine.running()]
	local hardDeadline = context and context.Deadline
	deadline = math.min(deadline - .2, os.clock() + .1)
	if os.clock() >= deadline then return points end
	if context then context.Deadline = deadline end
	local result, from, first, queries = {}, origin, 1, 0
	while first <= #points do
		if queries >= 8192 or os.clock() >= deadline then
			for rest=first,#points do table.insert(result,points[rest]) end
			break
		end
		local chosen = first
		for index=math.min(#points,first+15),first+1,-1 do
			if queries >= 8192 or os.clock() >= deadline then break end
			if horizontalDistance(from,points[index]) <= 128 then
				local clear, reached, used = self:_walkingEdgeClear(from,points[index])
				queries += used or 0
				if clear and reached and math.abs(reached.Y-points[index].Y) <= self.Tuning.MaxStepHeight then
					chosen = index
					break
				end
			end
		end
		table.insert(result,points[chosen])
		from, first = points[chosen], chosen+1
	end
	if context then context.Deadline = hardDeadline end
	return result
end

function Navigator:_joinStableRoute(points, requestStart)
 local from=self.FootPosition
 local context=planningThreads[coroutine.running()]
 if self.Destroyed or (context and
  (self.RequestId~=context.RequestId or os.clock()>=context.Deadline)) then return nil,0 end
 -- No splice is needed when certification started at this exact XYZ foot.
 -- Step still sweeps every live stride; moving incumbents use the join below.
 if from==requestStart then return points,0 end
 local joined,skipped=self:_certifiedJoin(points,requestStart)
 if not joined or self.Destroyed or (context and
  (self.RequestId~=context.RequestId or os.clock()>=context.Deadline)) then return nil,0 end
 if horizontalDistance(from,self.FootPosition)<=.001 then return joined,skipped end
 if context then context.Atomic=true end
 local fresh,extra=self:_shortAtomicJoin(joined,from)
 if context then context.Atomic=false;context.SliceAt=os.clock() end
 return fresh,(skipped or 0)+(extra or 0)
end

local checks={}
local function check(name,pass) table.insert(checks,{Name=name,Pass=pass==true}); assert(pass,name) end
local function equal(a,b)
 if #a~=#b then return false end
 for i,p in ipairs(a) do if p~=b[i] then return false end end
 return true
end
local thread=coroutine.running()
local origin=Vector3.zero
local points={Vector3.new(4,0,0),Vector3.new(8,0,0),Vector3.new(12,0,0)}
local function create()
 now=0
 local context={RequestId=7,Deadline=10,SliceAt=0}
 planningThreads[thread]=context
 local nav=setmetatable({FootPosition=origin,RequestId=7,Tuning={MaxStepHeight=3.5},JoinCalls=0,AtomicCalls=0,EdgeCalls=0},{__index=Navigator})
 function nav:_certifiedJoin(input)
  self.JoinCalls+=1; if self.JoinHook then return self:JoinHook(input) end
  return input,2
 end
 function nav:_shortAtomicJoin(input,from)
  self.AtomicCalls+=1; self.SawAtomic=context.Atomic; self.AtomicFrom=from; return input,3
 end
 function nav:_walkingEdgeClear(from,to)
  self.EdgeCalls+=1; self.EdgeDeadline=planningThreads[thread] and planningThreads[thread].Deadline
  if self.EdgeHook then return self:EdgeHook(from,to) end
  return true,to,3
 end
 return nav,context
end
do
 local n,c=create(); local got,skipped=n:_joinStableRoute(points,origin)
 check("exact XYZ uses existing certified points",got==points and skipped==0 and n.JoinCalls==0)
 check("exact fast join preserves hard deadline",c.Deadline==10)
end
do
 local n=create(); n.Destroyed=true
 local got=n:_joinStableRoute(points,origin)
 check("destroyed navigator rejects exact-origin fast join",got==nil and n.JoinCalls==0)
end
do
 local n,c=create(); c.Deadline=0
 check("expired context rejects exact-origin fast join",n:_joinStableRoute(points,origin)==nil and n.JoinCalls==0)
end
do
 local n=create(); n.RequestId=8
 check("replacement request rejects exact-origin fast join",n:_joinStableRoute(points,origin)==nil and n.JoinCalls==0)
end
do
 local n=create(); n.FootPosition=Vector3.new(1,0,0)
 local got,skipped=n:_joinStableRoute(points,origin)
 check("moving incumbent retains certified join",got==points and skipped==2 and n.JoinCalls==1 and n.AtomicCalls==0)
end
do
 local n=create(); n.FootPosition=Vector3.new(0,1,0)
 local got=n:_joinStableRoute(points,origin)
 check("Y-only displacement does not enter exact XYZ fast join",got==points and n.JoinCalls==1)
end
do
 local n,c=create(); n.FootPosition=Vector3.new(1,0,0)
 function n:JoinHook(input) self.FootPosition=Vector3.new(2,0,0); now=.03; return input,2 end
 local got,skipped=n:_joinStableRoute(points,origin)
 check("movement during certification invokes atomic live-foot bridge",got==points and skipped==5 and n.AtomicCalls==1 and n.SawAtomic==true and n.AtomicFrom==Vector3.new(1,0,0))
 check("atomic state restored after bridge",c.Atomic==false and c.SliceAt==.03 and c.Deadline==10)
end
do
 local n=create(); n.FootPosition=Vector3.new(1,0,0)
 function n:JoinHook(input) self.RequestId=8; return input,2 end
 check("replacement during yielding join cannot install",n:_joinStableRoute(points,origin)==nil and n.AtomicCalls==0)
end
do
 local n=create(); n.FootPosition=Vector3.new(1,0,0)
 function n:JoinHook(input) now=10; return input,2 end
 check("deadline during yielding join cannot install",n:_joinStableRoute(points,origin)==nil and n.AtomicCalls==0)
end
do
 local n=create(); n.FootPosition=Vector3.new(1,0,0)
 function n:JoinHook() return nil,0 end
 check("uncertified moving join remains rejected",n:_joinStableRoute(points,origin)==nil and n.AtomicCalls==0)
end
do
 local n,c=create(); c.Deadline=.15
 local got=n:_smoothStableRoute(points,origin,.15)
 check("insufficient installation reserve skips optional smoothing",got==points and n.EdgeCalls==0)
 check("early smoothing return preserves original context",c.Deadline==.15)
end
do
 local n,c=create()
 function n:EdgeHook(from,to) now=.11; return false,from,12 end
 local got=n:_smoothStableRoute(points,origin,10)
 check("soft budget is visible to native predicate dependency",n.EdgeDeadline==.1)
 check("soft expiry retains certified original suffix",equal(got,points) and n.EdgeCalls==1)
 check("soft expiry restores hard installation deadline",c.Deadline==10)
 local joined=n:_joinStableRoute(got,origin)
 check("restored hard deadline allows stationary route installation",joined==got and n.JoinCalls==0)
end
do
 local n,c=create()
 function n:EdgeHook(from,to) return false,from,3 end
 local got=n:_smoothStableRoute(points,origin,10)
 check("failed shortcuts never discard mandatory certified vertices",equal(got,points))
 check("all-blocked smoothing restores hard context",c.Deadline==10)
end
do
 local n,c=create(); local got=n:_smoothStableRoute(points,origin,10)
 check("successful certified shortcut retains actual endpoint",#got==1 and got[1]==points[3] and n.EdgeCalls==1)
 check("successful smoothing restores original context",c.Deadline==10)
end
do
 local n,c=create(); c.Deadline=.25
 local got=n:_smoothStableRoute(points,origin,.25)
 check("smoothing reserves final 0.2 seconds from hard deadline",math.abs(n.EdgeDeadline-.05)<1e-8 and c.Deadline==.25 and #got==1)
end
do
 local n=create(); planningThreads[thread]=nil
 local got=n:_smoothStableRoute(points,origin,10)
 check("standalone diagnostic smoothing works without planning context",#got==1 and got[1]==points[3])
end
do
 local n,c=create()
 function n:EdgeHook() error("injected predicate error") end
 -- Match actual _requestPath error boundary: it always removes the per-thread
 -- planning context after xpcall, including a predicate exception.
 local ok=pcall(function() n:_smoothStableRoute(points,origin,10) end)
 planningThreads[thread]=nil
 check("predicate errors fail closed through request error boundary",ok==false)
 check("request cleanup removes temporary context after predicate error",planningThreads[thread]==nil)
end
planningThreads[thread]=nil
return {Pass=#checks,Total=#checks,Checks=checks,FixtureOnly=true,
 Limitations="Mocks certify control flow, ownership and deadline restoration, not real geometry, moving doors, CPU cost or live gameplay. Input routes are assumed already certified by the production caller."}

