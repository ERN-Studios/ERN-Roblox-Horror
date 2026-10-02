local fs=require('@lune/fs')
local luau=require('@lune/luau')
local serde=require('@lune/serde')
local rbx=require('@lune/roblox')
local process=require('@lune/process')
local root=assert(process.args[1],'Pass the input/record directory')
if string.sub(root,-1)~='/' then root..='/' end
local script=fs.readFile(root..'rebind-static-pbr-prepared.luau')
local before=fs.readFile(root..'manifest-before-zen-denied.json')
local after=fs.readFile(root..'manifest-laver-resolved-images.json')
local plan=serde.decode('json',fs.readFile(root..'rebind-plan.json'))
local function hash(s)return serde.hash('sha256',s)end
assert(hash(script)=='17b7cf616d75d2c5b1c1a4a8fbbf85501064ba047cdd27de026727eed80a8790')
assert(luau.compile(script))
local Enum={HashAlgorithm={Sha256='sha'},CompressionAlgorithm={Zstd='zstd'},ContentSourceType={Uri='Uri',None='None'},AlphaMode={Overlay='Overlay'}}
local mapContent={ColorMap='ColorMapContent',NormalMap='NormalMapContent',RoughnessMap='RoughnessMapContent'}
local props={color='ColorMap',normal='NormalMap',roughness='RoughnessMap'}
local function fixture()
 local state={nodes={},historyWrites=0,mapWrites=0,logs={},failedStage=nil}
 local instance
 instance=function(class,name,parent)
  local attrs,children,values={},{},{ClassName=class,Name=name,Parent=nil,Archivable=true}
  local object={}
  local methods={}
  function methods:GetAttribute(k)return attrs[k]end
  function methods:SetAttribute(k,v)
   if self==state.source and k=='Ready' and state.failReady==v then error('injected Ready write failure')end
   attrs[k]=v
  end
  function methods:GetChildren()return table.clone(children)end
  function methods:FindFirstChild(n)for _,c in children do if c.Name==n then return c end end end
  function methods:IsDescendantOf(target)local p=self.Parent;while p do if p==target then return true end;p=p.Parent end;return false end
  function methods:Clone()
   local clone=instance(self.ClassName,self.Name)
   for k,v in values do if k~='ClassName' and k~='Name' and k~='Parent' then clone[k]=v end end
   for k,v in attrs do clone:SetAttribute(k,v)end
   for _,c in children do local copied=c:Clone();copied.Parent=clone end
   return clone
  end
  setmetatable(object,{__index=function(_,k)
   if methods[k] then return methods[k]end
   if k=='ColorMapContent' or k=='NormalMapContent' or k=='RoughnessMapContent' or k=='MetalnessMapContent' then
    local prop=if k=='MetalnessMapContent' then 'MetalnessMap' else string.sub(k,1,#k-7)
    local value=values[prop]
    return {SourceType=if value and value~='' then 'Uri' else 'None',Uri=value or ''}
   end
   if k=='_children' then return children end
   return values[k]
  end,__newindex=function(_,k,v)
   if mapContent[k] and state.active then
    state.mapWrites+=1
    if state.failMapWrite==state.mapWrites then error('injected map write failure')end
   end
   if k=='Parent' then
    local old=values.Parent
    if old then for i,c in old._children do if c==object then table.remove(old._children,i);break end end end
    values.Parent=v;if v then table.insert(v._children,object)end
   else values[k]=v end
  end})
  if parent then object.Parent=parent end
  table.insert(state.nodes,object)
  return object
 end
 local ss=instance('ServerStorage','ServerStorage')
 local source=instance('Folder',plan.sourceName,ss);state.source=source
 source:SetAttribute('LobbyReimaginedOwned',true);source:SetAttribute('Ready',true)
 source:SetAttribute('ManifestSHA256',plan.beforeManifestSHA256);source:SetAttribute('RecoveryCaptureId','fresh-root-checkpoint')
 local manifest=instance('Folder','ManifestJSON',source);state.manifest=manifest
 manifest:SetAttribute('RawBytes',#before);manifest:SetAttribute('RawSHA256',hash(before));manifest:SetAttribute('CompressedBytes',#before)
 local piece=instance('StringValue','00000',manifest);piece.Value=before
 local templates=instance('Folder','StaticPBRMaterials',source);state.templates=templates
 templates:SetAttribute('LobbyReimaginedOwned',true)
 state.materials={}
 for _,row in plan.rows do
  local sa=state.materials[row.material]
  if not sa then
   sa=instance('SurfaceAppearance',row.material,templates);state.materials[row.material]=sa
   sa:SetAttribute('LobbyReimaginedOwned',true);sa.Color=rbx.Color3.new(1,1,1);sa.AlphaMode='Overlay';sa.MetalnessMap=''
  end
  sa[props[row.role]]='rbxassetid://'..row.oldDeniedAssetId;sa:SetAttribute(row.role..'PNG_SHA256',row.pngSHA256)
 end
 local hs={HttpEnabled=true,JSONDecode=function(_,s)return serde.decode('json',s)end,JSONEncode=function(_,s)return serde.encode('json',s)end,
  GetAsync=function(_,url)assert(url=='http://127.0.0.1:8896/manifest');if state.afterYield then state.afterYield()end;return state.served or after end}
 local enc={ComputeBufferHash=function(_,raw)
   local hex=hash(buffer.tostring(raw));local out=buffer.create(32)
   for i=0,31 do buffer.writeu8(out,i,tonumber(string.sub(hex,i*2+1,i*2+2),16))end
   return out
  end,Base64Decode=function(_,raw)return raw end,Base64Encode=function(_,raw)return raw end,
  CompressBuffer=function(_,raw)return raw end,DecompressBuffer=function(_,raw)return raw end}
 local run={IsRunning=function()return state.play==true end}
 local game={PlaceId=plan.placeId,GameId=plan.universeId,CreatorId=plan.groupId,
  GetService=function(_,name)return ({HttpService=hs,EncodingService=enc,ServerStorage=ss,RunService=run})[name]end}
 state.game=game;state.ss=ss;state.shared={};state.active=true;state.mapWrites=0
 state.env={game=game,Enum=Enum,buffer=buffer,Color3=rbx.Color3,
  Instance={new=function(c)return instance(c,c)end},shared=state.shared,
  print=function(v)table.insert(state.logs,v)end,warn=function(v)table.insert(state.logs,v)end}
 return state
end
local results={}
local function check(name,expected,setup,verify)
 local state=fixture();if setup then setup(state)end
 local exactSource=state.code or script
 local ok,err=pcall(luau.load(exactSource,{environment=state.env}))
 assert(ok==expected,name..': '..tostring(err))
 if verify then verify(state,ok,err)end
 table.insert(results,{name=name,expectedSuccess=expected,actualSuccess=ok,passed=true})
end
local function unchanged(s)
 assert(s.source:GetAttribute('Ready')==true and s.source:GetAttribute('ManifestSHA256')==plan.beforeManifestSHA256)
 assert(s.mapWrites==0 and not s.source:FindFirstChild(plan.historyName))
end
check('valid exact nine-Image rebind preserves old manifest and unchanged metadata',true,nil,function(s)
 assert(s.source:GetAttribute('Ready')==true and s.source:GetAttribute('ManifestSHA256')==plan.afterManifestSHA256)
 assert(s.mapWrites==9 and s.shared.__r4AssetRebindResult.success==true)
 local hist=s.source:FindFirstChild(plan.historyName);assert(hist and hist:GetAttribute('Complete')==true)
 assert(s.manifest.Name=='ManifestJSON_original' and s.manifest.Parent==hist)
 for _,row in plan.rows do assert(s.materials[row.material][props[row.role]]=='rbxassetid://'..row.newResolvedImageId)end
end)
check('wrong place rejects before writes',false,function(s)s.game.PlaceId=1 end,unchanged)
check('running Play rejects before writes',false,function(s)s.play=true end,unchanged)
check('old source hash mismatch rejects before writes',false,function(s)s.source:SetAttribute('ManifestSHA256','changed')end,function(s)assert(s.mapWrites==0 and not s.source:FindFirstChild(plan.historyName))end)
check('old template URI mismatch rejects before writes',false,function(s)s.materials.tunnel_concrete.ColorMap='rbxassetid://1';s.mapWrites=0 end,unchanged)
check('old PNG mismatch rejects before writes',false,function(s)s.materials.tunnel_concrete:SetAttribute('normalPNG_SHA256','changed')end,unchanged)
check('duplicate source identity rejects before writes',false,function(s)local duplicate=s.source:Clone();duplicate.Parent=s.ss;s.mapWrites=0 end,unchanged)
check('served manifest hash mismatch rejects before writes',false,function(s)s.served=after..' 'end,unchanged)
check('template changed during HTTP yield rejects inside write guard',false,function(s)s.afterYield=function()s.materials.tunnel_concrete.NormalMap='rbxassetid://2';s.mapWrites=0 end end,unchanged)
check('logical non-ID manifest change rejected despite correctly pinned altered bytes',false,function(s)
 local doc=serde.decode('json',after);doc.previewCenter[1]+=1
 s.served=serde.encode('json',doc)
 local alternate=table.clone(plan);alternate.afterManifestSHA256=hash(s.served);alternate.afterManifestBytes=#s.served
 local start,finish=string.find(script,'%[====%[.-%]====%]')
 assert(start and finish)
 s.code=string.sub(script,1,start-1)..'[====['..serde.encode('json',alternate)..']====]'..string.sub(script,finish+1)
end,unchanged)
check('fourth map failure retains history and leaves Ready=false with exact attempted/applied receipt',false,function(s)s.failMapWrite=4 end,function(s)
 assert(s.source:GetAttribute('Ready')==false and s.source:GetAttribute('ManifestSHA256')==plan.beforeManifestSHA256)
 local r=s.shared.__r4AssetRebindResult;assert(r.success==false and #r.attempted==4 and #r.applied==3)
 assert(s.source:FindFirstChild(plan.historyName) and s.manifest.Parent==s.source and s.manifest.Name=='ManifestJSON')
 assert(s.shared.__r4AssetRebindFailedStage)
end)
check('final Ready=true failure retains completed manifest but keeps Ready=false',false,function(s)s.failReady=true end,function(s)
 assert(s.source:GetAttribute('Ready')==false and s.source:GetAttribute('ManifestSHA256')==plan.afterManifestSHA256)
 assert(s.shared.__r4AssetRebindResult.success==false and #s.shared.__r4AssetRebindResult.applied==9)
 assert(s.source:FindFirstChild(plan.historyName):GetAttribute('Complete')==false)
end)
local report={schema='lobby-r4-pbr-rebind-guard-regression-v1',passed=true,completedCaseCount=#results,
 scriptSHA256=hash(script),beforeManifestSHA256=hash(before),afterManifestSHA256=hash(after),results=results,
 studioExecuted=false,limits='Exact prepared Luau runs with mocked Instance/services/property failures and identity buffer compression; native Color3 and SHA256. This validates guard/control flow only, not protected property permissions, native compression, texture loading, actual Play or publication.'}
fs.writeFile(root..'rebind-guard-regression.json',serde.encode('json',report,true)..'\n')
print(serde.encode('json',{passed=true,completedCaseCount=#results,scriptSHA256=report.scriptSHA256},true))
