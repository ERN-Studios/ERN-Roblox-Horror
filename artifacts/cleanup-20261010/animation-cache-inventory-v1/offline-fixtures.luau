-- Offline actual-collector replay. All game/SES/shared/Encoding/task boundaries
-- below are controlled tables; this is not native assets/gameplay/MP/streaming.
local serde=require('@lune/serde')
local builtinTypeof=typeof
local results={} local checks=0
local function check(ok,why) checks+=1 assert(ok,why) end
local function base64(data)
 local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/' local out={}
 for i=1,#data,3 do
  local a,b,c=string.byte(data,i,i+2) local value=a*65536+(b or 0)*256+(c or 0)
  out[#out+1]=alphabet:sub(math.floor(value/262144)%64+1,math.floor(value/262144)%64+1)
  out[#out+1]=alphabet:sub(math.floor(value/4096)%64+1,math.floor(value/4096)%64+1)
  out[#out+1]=if b then alphabet:sub(math.floor(value/64)%64+1,math.floor(value/64)%64+1) else '='
  out[#out+1]=if c then alphabet:sub(value%64+1,value%64+1) else '='
 end return table.concat(out)
end
local function fixture()
 local values,methods={},{} local writes=0 local yields=0 local onYield=nil local services={}
 local function node(row)
  row.children=row.children or {} row.attributes=row.attributes or {} row.tags=row.tags or {}
  row.Archivable=if row.Archivable==nil then true else row.Archivable
  local object=setmetatable({__kind='Instance'},{__index=function(_,key)
   if row.denied and row.denied[key] then error('controlled property unreadable: '..key)end
   return methods[key] or row[key]
  end,__newindex=function()writes+=1 error('Forbidden native Instance/property write')end})
  values[object]=row
  if row.Parent then table.insert(values[row.Parent].children,object)end
  return object
 end
 function methods:GetChildren()return table.clone(values[self].children)end
 function methods:GetDescendants()
  local out={} local function visit(parent)for _,child in values[parent].children do out[#out+1]=child visit(child)end end
  visit(self)return out
 end
 function methods:GetDebugId(depth)check(depth==16,'depth16');return values[self].id end
 function methods:GetFullName()
  local names={} local n=self while values[n].Parent do table.insert(names,1,values[n].Name)n=values[n].Parent end return table.concat(names,'.')
 end
 function methods:GetAttributes()return table.clone(values[self].attributes)end
 function methods:GetAttribute(name)return values[self].attributes[name]end
 function methods:GetTags()return table.clone(values[self].tags)end
 function methods:IsA(class)
  local own=values[self].ClassName
  return own==class or (class=='LuaSourceContainer' and (own=='ModuleScript' or own=='Script' or own=='LocalScript'))
   or (class=='BaseScript' and (own=='Script' or own=='LocalScript'))
   or (class=='AnimationClip' and (own=='KeyframeSequence' or own=='CurveAnimation'))
   or (class=='ValueBase' and (own=='StringValue' or own=='NumberValue'))
 end
 function methods:IsDescendantOf(ancestor)local n=self while values[n].Parent do n=values[n].Parent if n==ancestor then return true end end return false end
 local forbidden=function()error('Denied native write/require/upload/serialize/listener/task API')end
 function methods:Destroy()forbidden()end
 local game=node({Name='game',ClassName='DataModel',id='game',PlaceId=131311258779917,GameId=10559217407})
 local SS=node({Name='ServerStorage',ClassName='ServerStorage',id='SS',Parent=game})
 local scripts=node({Name='ServerScriptService',ClassName='ServerScriptService',id='scripts',Parent=game})
 local sourceRefs={}
 for i=1,213 do
  local class=if i%3==0 then 'ModuleScript' elseif i%3==1 then 'Script' else 'LocalScript'
  sourceRefs[i]=node({Name='Original'..i,ClassName=class,id='source'..i,Parent=scripts,
   Source='return '..i,editor='return '..i,LinkedSource='',Enabled=true,Disabled=false,RunContext='Enum.RunContext.Legacy'})
 end
 local entity=node({Name='MongoTVEntityAnimations',ClassName='Folder',id='entity',Parent=SS})
 local saves=node({Name='RBX_ANIMSAVES',ClassName='Model',id='saves',Parent=SS})
 local tops={}
 for _,spec in {{entity,117},{saves,27}}do
  for i=1,spec[2] do tops[#tops+1]=node({Name='clip'..i,ClassName='Folder',id=values[spec[1]].id..'top'..i,Parent=spec[1]})end
 end
 local cache={}
 for i,version in {'v1','v6','v10','v15'}do
  cache[i]=node({Name='MongoTV_Entity_Watch_'..version,ClassName='KeyframeSequence',id='cache'..i,Parent=tops[i],
   Loop=i%2==0,Priority='Enum.AnimationPriority.Action',AuthoredHipHeight=2.5,
   attributes={PublishedAssetId=if i%2==0 then 90000+i else tostring(80000+i),Version=version},tags={'cache','keep'}})
 end
 local animation=node({Name='PublishedAnimation',ClassName='Animation',id='animation',Parent=tops[5],AnimationId='rbxassetid://123456789'})
 local named=node({Name='PublishedAssetId',ClassName='StringValue',id='named',Parent=tops[6],Value='99887766'})
 local pose=node({Name='Pose',ClassName='Pose',id='pose',Parent=cache[1]})
 for i=1,1003 do node({Name='Keyframe'..i,ClassName='Keyframe',id='key'..i,Parent=cache[1]})end
 local scratch={}
 services.ServerStorage=SS
 services.RunService={IsRunning=function()return values[game].running==true end}
 services.HttpService={JSONEncode=function(_,value)return serde.encode('json',value)end}
 services.EncodingService={ComputeBufferHash=function(_,raw,algorithm)
  check(algorithm=='sha256','hashalgorithm')local hex=serde.hash('sha256',buffer.tostring(raw)) local bytes={}
  for i=1,#hex,2 do bytes[#bytes+1]=string.char(tonumber(hex:sub(i,i+1),16))end return buffer.fromstring(table.concat(bytes))
 end,Base64Encode=function(_,raw)return buffer.fromstring(base64(buffer.tostring(raw)))end}
 services.ScriptEditorService={GetEditorSource=function(_,object)return values[object].editor end,UpdateSourceAsync=forbidden}
 function methods:GetService(name)check(self==game,'onlygame services');return assert(services[name])end
 return {game=game,shared=scratch,values=values,node=node,entity=entity,saves=saves,SS=SS,tops=tops,
  cache=cache,animation=animation,named=named,pose=pose,sources=sourceRefs,forbidden=forbidden,
  task={wait=function()yields+=1 if onYield then onYield(yields)end end,spawn=forbidden,defer=forbidden,delay=forbidden},
  typeof=function(v)return if type(v)=='table' and rawget(v,'__kind') then v.__kind else builtinTypeof(v)end,
  onYield=function(callback)onYield=callback end,counts=function()return writes,yields end}
end
-- COLLECTOR_INSERTION: replaced only in this owned offline fixture by test.py.
local function collect(REQUEST,game,shared,task,typeof,Enum,Instance,require)
__COLLECTOR__
end
local function invoke(f,command,page,template)
 local text=collect({command=command,page=page,captureId='actual-offline-capture-20261010-001',templateSHA256=template or string.rep('a',64)},
  f.game,f.shared,f.task,f.typeof,{HashAlgorithm={Sha256='sha256'}},{new=f.forbidden},f.forbidden)
 check(type(text)=='string' and #text<=20000,'boundedactualcompletion')return serde.decode('json',text)
end
local function key()return '__MongoTVAnimationCacheInventory20261010V1_actual-offline-capture-20261010-001'end
local function empty(f)return f.shared[key()]==nil and f.shared[key()..'_owner']==nil end
local function pages(f,b)
 for page=0,b.pageCount-1 do
  local p=invoke(f,'page',page)
  check(p.page==page and p.manifestSHA256==b.manifestSHA256 and p.chunkBytes<=12000,'deterministicboundedpage')
  check(p.nativeInstanceWrites==0 and p.nativeSourceWrites==0 and p.nativePropertyWrites==0,'readonlypage')
 end
end
local function record(name,f,report,passed)
 local writes,yields=f.counts()check(writes==0,'actualcollector attempted no native writes')
 results[#results+1]={name=name,expectedVerdict=passed,pass=report.pass,cleanupPassed=report.collectorCleanupPassed,
  nativeWrites=writes,yields=yields,ownedScratchRemaining=not empty(f)}
end
do
 local f=fixture()local b=invoke(f,'begin')check(b.pass and b.sourceCount==213 and b.recordCount==150 and b.metadataComplete,'allversions/144tops+6')
 check(b.pageCount>1,'realmultichunkpages')pages(f,b)local e=invoke(f,'finish')
 check(e.pass and e.cleanup.closed and e.cleanup.collectorStateWrites==b.pageCount+4 and empty(f),'finish owncleanup/writecounts')record('success-all-versions',f,e,true)
end
for _,case in {'mode','place','source-count','initial-editor','root-missing','root-duplicate','root-class','root-topcount','unsupported-attribute','scan-yield-error','scan-source-drift','response-bound','manifest-bound'}do
 local f=fixture()local row=f.values
 if case=='mode'then row[f.game].running=true
 elseif case=='place'then row[f.game].PlaceId=1
 elseif case=='source-count'then f.node({Name='new',ClassName='ModuleScript',id='newSource',Parent=f.game,Source='',editor='',LinkedSource=''})
 elseif case=='initial-editor'then row[f.sources[1]].editor='foreign'
 elseif case=='root-missing'then row[f.entity].Name='wrong'
 elseif case=='root-duplicate'then f.node({Name='MongoTVEntityAnimations',ClassName='Folder',id='duplicate',Parent=f.SS})
 elseif case=='root-class'then row[f.entity].ClassName='Model'
 elseif case=='root-topcount'then f.node({Name='extra',ClassName='Folder',id='extraTop',Parent=f.entity})
 elseif case=='unsupported-attribute'then row[f.tops[1]].attributes.Unsupported={__kind='UnknownAttribute'}
 elseif case=='scan-yield-error'then f.onYield(function(n)if n==2 then error('controlled yield exception')end end)
 elseif case=='scan-source-drift'then f.onYield(function(n)if n==2 then row[f.sources[1]].Source='foreign';row[f.sources[1]].editor='foreign'end end)
 elseif case=='response-bound'then row[f.entity].attributes.Large=string.rep('x',30000)
 elseif case=='manifest-bound'then row[f.tops[1]].attributes.Large=string.rep('x',10000001)end
 local b=invoke(f,'begin')check(b.pass==false,'negativebeginrefused '..case)
 check(empty(f),'beginfailedownedcleanup '..case)record(case,f,b,false)
end
for _,case in {'Source','editor','ClassName','id','Parent','Enabled','Disabled','RunContext','Archivable','LinkedSource','source-attr','source-tag','root-id','root-name','root-parent','root-class','root-attr','root-tag','root-new-collision','topchild','animation-id','published-id','sequence-loop','sequence-priority','sequence-hip','cache-attr','cache-tag','named-id','child-count','wrong-page','finish-too-early','foreign-progress','foreign-slot','foreign-owner','template'}do
 local f=fixture()local b=invoke(f,'begin')check(b.pass,'validbaseline '..case)local row=f.values
 local source=row[f.sources[1]]
 if case=='Source'then source.Source='foreign'
 elseif case=='editor'then source.editor='foreign'
 elseif case=='ClassName'then source.ClassName='LocalScript'
 elseif case=='id'then source.id='foreign'
 elseif case=='Parent'then source.Parent=f.SS
 elseif case=='Enabled'then source.Enabled=false
 elseif case=='Disabled'then source.Disabled=true
 elseif case=='RunContext'then source.RunContext='Enum.RunContext.Client'
 elseif case=='Archivable'then source.Archivable=false
 elseif case=='LinkedSource'then source.LinkedSource='foreign'
 elseif case=='source-attr'then source.attributes.Foreign=1
 elseif case=='source-tag'then source.tags={'foreign'}
 elseif case=='root-id'then row[f.entity].id='foreign'
 elseif case=='root-name'then row[f.entity].Name='foreign'
 elseif case=='root-parent'then row[f.entity].Parent=f.game
 elseif case=='root-class'then row[f.entity].ClassName='Model'
 elseif case=='root-attr'then row[f.entity].attributes.Foreign=true
 elseif case=='root-tag'then row[f.entity].tags={'foreign'}
 elseif case=='root-new-collision'then f.node({Name='MongoTVEntityAnimations',ClassName='Folder',id='collision',Parent=f.SS})
 elseif case=='topchild'then f.node({Name='extra',ClassName='Folder',id='extra',Parent=f.entity})
 elseif case=='animation-id'then row[f.animation].AnimationId='rbxassetid://foreign'
 elseif case=='published-id'then row[f.cache[1]].attributes.PublishedAssetId='foreign'
 elseif case=='sequence-loop'then row[f.cache[1]].Loop=not row[f.cache[1]].Loop
 elseif case=='sequence-priority'then row[f.cache[1]].Priority='foreign'
 elseif case=='sequence-hip'then row[f.cache[1]].AuthoredHipHeight=7
 elseif case=='cache-attr'then row[f.cache[1]].attributes.Foreign=2
 elseif case=='cache-tag'then row[f.cache[1]].tags={'foreign'}
 elseif case=='named-id'then row[f.named].Value='foreign'
 elseif case=='child-count'then f.node({Name='extra',ClassName='Keyframe',id='extra',Parent=f.cache[1]})
 elseif case=='foreign-progress'then f.shared[key()].progress.nextPage=1
 elseif case=='foreign-slot'then f.shared[key()]=table.clone(f.shared[key()])
 elseif case=='foreign-owner'then f.shared[key()..'_owner']={foreign=true}end
 local r=invoke(f,if case=='finish-too-early'then 'finish'else 'page',if case=='wrong-page'then 1 else 0,if case=='template'then string.rep('b',64)else nil)
 check(r.pass==false,'negativecurrentguard '..case)
 local foreign=case=='foreign-progress' or case=='foreign-slot' or case=='foreign-owner' or case=='template'
 check(empty(f)==not foreign,'foreign scratch preserved / ownedscratchclosed '..case)record(case,f,r,false)
end
for _,case in {'nested-new-id','nested-new-animation','nested-new-source','new-global-source'}do
 local f=fixture()local b=invoke(f,'begin')pages(f,b)
 if case=='nested-new-id'then f.values[f.pose].attributes.PublishedAssetId='new'
 elseif case=='nested-new-animation'then f.node({Name='new',ClassName='Animation',id='newAnimation',Parent=f.pose,AnimationId='rbxassetid://new'})
 elseif case=='nested-new-source'then f.node({Name='new',ClassName='ModuleScript',id='newSource',Parent=f.pose,Source='',editor='',LinkedSource=''})
 elseif case=='new-global-source'then f.node({Name='new',ClassName='ModuleScript',id='newGlobalSource',Parent=f.game,Source='',editor='',LinkedSource=''})end
 local e=invoke(f,'finish')check(e.pass==false and empty(f),'fresh final coverage rejects additions '..case)record(case,f,e,false)
end
do local f=fixture()local b=invoke(f,'begin')check(b.pass,'abandonbaseline')local e=invoke(f,'abandon')check(e.closed and empty(f),'owned abandonment')record('abandon',f,e,true)end
do local f=fixture()local b=invoke(f,'begin')local e=invoke(f,'begin')check(e.pass==false and not empty(f),'secondbeginpreservesexisting')local a=invoke(f,'abandon')check(a.closed and empty(f),'existingpurposecanabandon')record('occupied-namespace',f,e,false)end
do
 local f=fixture()f.values[f.animation].denied={AnimationId=true}
 local b=invoke(f,'begin')check(b.pass and not b.metadataComplete,'unreadableprop remains explicitly incomplete')pages(f,b)
 local e=invoke(f,'finish')check(e.pass and empty(f),'incompletemanifest honestcollectorcompletion')record('unreadable-property-explicit-incomplete',f,e,true)
end
print(serde.encode('json',{passed=true,cases=#results,checks=checks,results=results,nativeCalls=0,productionWrites=0,
 limits='Actual collector text with synthetic tables/task/Encoding/JSON boundaries; no actual cache/native scheduling or asset/deletion/gameplay/performance certificate.'}))
