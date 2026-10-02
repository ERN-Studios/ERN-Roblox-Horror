-- Exact candidate helpers/onReturn/queue-ready fragments on a graph fixture.
-- Uses native Vector3/CFrame; no Studio write or real streaming/Play claim.
local fs=require('@lune/fs')
local luau=require('@lune/luau')
local serde=require('@lune/serde')
local rbx=require('@lune/roblox')
local process=require('@lune/process')
local dir=(process.args[1] or '/private/tmp/lobby-r4-return-anchor-review-20261002')..'/'
local source=fs.readFile(dir..'Level6PreviewAccess.candidate.luau')
local before=fs.readFile(dir..'Level6PreviewAccess.before.luau')
assert(serde.hash('sha256',before)=='0829dc2fed34719fde2937a51a7a18f22f7ea64aa5d89ae06cbc2bb54b193868')
assert(serde.hash('sha256',source)=='bc8e8f0722f023e22f5daedffa9929d4232eef62a170d592c473a7852f48d8f3')
assert(pcall(luau.compile,source))
local constants=source:match('(local RETURN_ANCHOR =.-)local transport')
local helpers=source:match('(local onReturn.-)local function onEnter')
local callback=source:match('(onReturn = function.-)\n%-%- R4 queue')
local ready=source:match('ready = function%(%)(.-)\n   end,\n   launch = function')
assert(constants and helpers and callback and ready)
local fragment=constants..'\n'..helpers..'\n'..callback..'\nlocal function queueReady()'..ready..'\nend\n'..
 'return {hook=hookExit, valid=validReturnPrompt, lookup=returnPrompt, run=onReturn, ready=queueReady, ensure=ensurePrompt}\n'
local methods={}
function methods:IsA(name) return self.ClassName==name or (self.ClassName=='Part' and name=='BasePart') end
function methods:GetAttribute(name) return self.attrs[name] end
function methods:SetAttribute(name,value) self.attrs[name]=value end
function methods:FindFirstChild(name) for _,child in self.children do if child.Name==name then return child end end end
local function instance(class,name,parent)
 local data={ClassName=class,Name=name or class,attrs={},children={},Position=rbx.Vector3.zero,connections={}}
 local obj=setmetatable({}, {
  __index=function(_,key)return methods[key] or data[key] end,
  __newindex=function(self,key,value)
   if key=='Parent' then
    if data.Parent then local index=table.find(data.Parent.children,self);if index then table.remove(data.Parent.children,index) end end
    data.Parent=value
    if value then table.insert(value.children,self) end
   else data[key]=value end
  end,
 })
 if class=='ProximityPrompt' then
  obj.Enabled=true
  obj.Triggered={Connect=function(_,fn) table.insert(obj.connections,fn);return {Disconnect=function()end} end}
 end
 obj.Parent=parent
 return obj
end
local function fixture()
 local world=instance('Model','Level 6 Generated World')
 local exit=instance('Part','Level6Exit',world)
 exit.Position=rbx.Vector3.new(19962.869,27.8536,90)
 exit.CFrame=rbx.CFrame.lookAt(exit.Position,exit.Position+rbx.Vector3.xAxis)
 local spawn=instance('Part','LobbySpawn');spawn.Position=rbx.Vector3.new(0,33,-860);spawn.CFrame=rbx.CFrame.new(spawn.Position)
 local root=instance('Part','HumanoidRootPart');root.Position=exit.Position-rbx.Vector3.new(0,.7,0)
 local character=instance('Model','Character');character.moves={}
 function character:PivotTo(cf) table.insert(self.moves,cf) end
 local player=instance('Player','ZenMeister02');player.attrs.Level6InRound=true
 local state={world=world,exit=exit,spawn=spawn,root=root,character=character,player=player,ready=true,floor=true,
  authorized=true,leave=0,release=0,streams=0,warnings={},nextUse={},hooked=setmetatable({},{__mode='k'})}
 local env={Vector3=rbx.Vector3,ENTER='Level6DeveloperPreviewPrompt',RETURN='Level6DeveloperPreviewReturnPrompt',
  Instance={new=function(class)return instance(class)end},hooked=state.hooked,nextUse=state.nextUse,
  previewReady=function() if state.ready then return state.world,state.exit end end,
  playerReady=function(p) if state.authorized and p==player then return state.character,state.root end end,
  lobbyPart=function(name) if name=='LobbySpawn' then return state.spawn end end,
  floorAt=function()return state.floor end,
  streamReady=function() state.streams+=1;if state.mutate then state.mutate() end;return state.streamOK~=false end,
  upright=function(cf)return cf end,
  Runtime={Leave=function(p)assert(p==player);state.leave+=1 end},
  release=function()state.release+=1;state.nextUse[player]=nil end,
  warn=function(message)table.insert(state.warnings,message)end,
 }
 state.api=luau.load(fragment,{environment=env})()
 return state
end
local results={}
local function test(name,fn)
 fn();table.insert(results,{name=name,passed=true})
end
local function mounted(s)
 s.api.hook();local a=s.exit:FindFirstChild('Level6DeveloperPreviewReturnAnchor');local p=a and a:FindFirstChild('Level6DeveloperPreviewReturnPrompt');assert(a and p);return a,p
end
test('creates owned visible anchor and enabled queue-ready prompt',function()
 local s=fixture();local a,p=mounted(s)
 assert(a:IsA('Attachment') and a:GetAttribute('Level6PreviewReturnOwned')==true and a.Position==rbx.Vector3.new(1,1.5,-4))
 assert(p.Parent==a and p.ActionText=='RETURN TO LOBBY' and p.MaxActivationDistance==7.5 and p.HoldDuration==.5 and p.RequiresLineOfSight==false)
 assert(s.api.valid(p,s.exit) and s.api.lookup(s.exit)==p and s.api.ready()==s.world)
 local world= s.exit.CFrame:PointToWorldSpace(a.Position)
 local fromExit=world-s.exit.Position
 assert(math.abs(fromExit:Dot(s.exit.CFrame.LookVector)-4)<.002)
 assert(math.abs(fromExit:Dot(s.exit.CFrame.RightVector)-1)<.002)
 assert((world-s.root.Position).Magnitude<7.5)
end)
test('hook is idempotent with exactly one callback',function()
 local s=fixture();local a,p=mounted(s);s.api.hook();s.api.hook()
 assert(#s.exit.children==1 and #a.children==1 and #p.connections==1 and s.api.lookup(s.exit)==p)
end)
test('legacy prompt moves without replacing properties or existing hookup',function()
 local s=fixture();local p=s.api.ensure(s.exit,'Level6DeveloperPreviewReturnPrompt','OLD',s.api.run)
 p.Enabled=false;p.MaxActivationDistance=9;p.HoldDuration=.75;p.ActionText='UNCHANGED';local count=#p.connections
 local a,m=mounted(s);assert(m==p and p.Parent==a and #p.connections==count)
 assert(p.Enabled==false and p.MaxActivationDistance==7.5 and p.HoldDuration==.75 and p.ActionText=='UNCHANGED' and s.api.ready()==nil)
end)
test('legacy direct-exit RETURN remains compatible and successful',function()
 local s=fixture();local p=s.api.ensure(s.exit,'Level6DeveloperPreviewReturnPrompt','OLD',s.api.run)
 assert(s.api.valid(p,s.exit));s.api.run(s.player,p);assert(s.leave==1 and #s.character.moves==1 and s.release==1)
end)
test('owned mounted RETURN succeeds through stream recheck',function()
 local s=fixture();local _,p=mounted(s);p.connections[1](s.player)
 assert(s.streams==1 and s.leave==1 and #s.character.moves==1 and s.release==1)
 assert(s.character.moves[1].Position==s.spawn.Position+rbx.Vector3.new(0,4,0))
end)
test('unowned anchor collision is not adopted or changed',function()
 local s=fixture();local a=instance('Attachment','Level6DeveloperPreviewReturnAnchor',s.exit);a.Position=rbx.Vector3.new(1,1.5,-4)
 s.api.hook();assert(a:GetAttribute('Level6PreviewReturnOwned')==nil and #a.children==0 and s.api.lookup(s.exit)==nil and #s.warnings==1)
end)
test('wrong class anchor collision is preserved without mounting',function()
 local s=fixture();local a=instance('Folder','Level6DeveloperPreviewReturnAnchor',s.exit)
 s.api.hook();assert(#a.children==0 and #s.exit.children==1 and s.api.lookup(s.exit)==nil)
end)
test('wrong offset owned anchor fails closed',function()
 local s=fixture();local a,p=mounted(s);a.Position=rbx.Vector3.new(1,1.5,-3)
 assert(not s.api.valid(p,s.exit));s.api.hook();assert(s.api.lookup(s.exit)==nil and a.Position.Z==-3 and #s.warnings==1)
 s.api.run(s.player,p);assert(s.streams==0 and s.leave==0)
end)
test('RETURN on a different exit is rejected',function()
 local s=fixture();local a,p=mounted(s);a.Parent=instance('Part','Level6Exit',s.world)
 assert(not s.api.valid(p,s.exit));s.api.run(s.player,p);assert(s.streams==0 and s.leave==0)
end)
test('mounted wrong prompt class is preserved and rejected',function()
 local s=fixture();local a,p=mounted(s);p.Parent=nil;local foreign=instance('Folder','Level6DeveloperPreviewReturnPrompt',a)
 s.api.hook();assert(s.api.lookup(s.exit)==nil and foreign.Parent==a and #s.warnings==1)
end)
test('mounted plus legacy conflict is not silently replaced',function()
 local s=fixture();local a,p=mounted(s);local legacy=instance('ProximityPrompt','Level6DeveloperPreviewReturnPrompt',s.exit)
 s.api.hook();assert(legacy.Parent==s.exit and p.Parent==a and #s.warnings==1)
end)
test('legacy wrong prompt class is preserved without creating anchor',function()
 local s=fixture();local p=instance('Folder','Level6DeveloperPreviewReturnPrompt',s.exit)
 s.api.hook();assert(#s.exit.children==1 and p.Parent==s.exit and s.api.lookup(s.exit)==nil)
end)
test('ownership changed during streaming prevents Leave and teleport',function()
 local s=fixture();local a,p=mounted(s);s.mutate=function()a:SetAttribute('Level6PreviewReturnOwned',false)end
 s.api.run(s.player,p);assert(s.streams==1 and s.leave==0 and #s.character.moves==0 and s.release==1)
end)
test('prompt reparented during streaming prevents Leave and teleport',function()
 local s=fixture();local _,p=mounted(s);s.mutate=function()p.Parent=s.spawn end
 s.api.run(s.player,p);assert(s.leave==0 and #s.character.moves==0 and s.release==1)
end)
test('character changed during streaming prevents Leave and teleport',function()
 local s=fixture();local _,p=mounted(s);local original=s.character;s.mutate=function()s.character=instance('Model','Respawned')end
 s.api.run(s.player,p);assert(s.leave==0 and #original.moves==0 and s.release==1)
end)
test('unauthorized player still rejected before streaming',function()
 local s=fixture();local _,p=mounted(s);s.authorized=false;s.api.run(s.player,p);assert(s.streams==0 and s.leave==0)
end)
test('player beyond unchanged12stud exit range rejected',function()
 local s=fixture();local _,p=mounted(s);s.root.Position=s.exit.Position+rbx.Vector3.new(13,0,0)
 s.api.run(s.player,p);assert(s.streams==0 and s.leave==0)
end)
test('existing cooldown lock still rejects return',function()
 local s=fixture();local _,p=mounted(s);s.nextUse[s.player]=math.huge;s.api.run(s.player,p);assert(s.streams==0 and s.leave==0)
end)
test('stream timeout releases lock without teleport',function()
 local s=fixture();local _,p=mounted(s);s.streamOK=false;s.api.run(s.player,p);assert(s.streams==1 and s.leave==0 and s.release==1 and #s.warnings==1)
end)
test('queue-ready rejects missing floor disabledprompt and absent world',function()
 local s=fixture();local _,p=mounted(s);s.floor=false;assert(s.api.ready()==nil)
 s.floor=true;p.Enabled=false;assert(s.api.ready()==nil);p.Enabled=true;s.ready=false;assert(s.api.ready()==nil)
end)
test('all displayed root activation sphere fits preserved12stud exit guard',function()
 local s=fixture();local a,p=mounted(s)
 assert(a.Position.Magnitude+p.MaxActivationDistance<12)
 local anchor=s.exit.CFrame:PointToWorldSpace(a.Position)
 -- Tight extremum is along the exit->anchor radial ray; verify that and representative directions.
 local radial=(anchor-s.exit.Position).Unit
 for _,direction in {radial,-radial,rbx.Vector3.xAxis,-rbx.Vector3.xAxis,rbx.Vector3.yAxis,-rbx.Vector3.yAxis,rbx.Vector3.zAxis,-rbx.Vector3.zAxis} do
  local point=anchor+direction*p.MaxActivationDistance
  assert((point-s.exit.Position).Magnitude<12)
 end
end)
test('arrival activation and narrowportrait horizontal framing fit',function()
 local s=fixture();local a,p=mounted(s);local point=s.exit.CFrame:PointToWorldSpace(a.Position)
 assert((point-s.root.Position).Magnitude<p.MaxActivationDistance)
 local camera=s.root.Position+rbx.Vector3.new(0,1.5,0)
 local delta=point-camera
 local forward=delta:Dot(s.exit.CFrame.LookVector)
 local side=math.abs(delta:Dot(s.exit.CFrame.RightVector))
 local horizontal=math.atan2(side,forward)
 local vertical=math.atan2(math.abs(delta.Y),forward)
 local halfVertical=math.rad(35)
 local halfHorizontalPortrait=math.atan(math.tan(halfVertical)*9/16)
 assert(horizontal<halfHorizontalPortrait and vertical<halfVertical)
end)
test('ENTER prompt remains original10stud activation distance',function()
 local s=fixture();local doorway=instance('Part','Level6SealedDoor')
 local enter=s.api.ensure(doorway,'Level6DeveloperPreviewPrompt','ENTER',function()end)
 assert(enter.MaxActivationDistance==10);mounted(s);assert(enter.MaxActivationDistance==10)
end)
local report={schema='lobby-r4-level6-return-anchor-regression-v1',passed=true,completedTestCount=#results,
 beforeSHA256=serde.hash('sha256',before),afterSHA256=serde.hash('sha256',source),syntaxPassed=true,
 tests=results,studioExecuted=false,limits='Actual changed helper/onReturn/queue-ready source fragments executed with native Vector3/CFrame and mocked Instance/player/streaming graph. No actual Play visibility/E/stream/multiplayer claim.'}
fs.writeFile(dir..'return-anchor-regression.json',serde.encode('json',report,true)..'\n')
print(serde.encode('json',{passed=true,count=#results,afterSHA256=report.afterSHA256},true))
