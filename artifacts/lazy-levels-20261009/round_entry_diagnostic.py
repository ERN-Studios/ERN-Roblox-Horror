"""Explicit actual-asset diagnostics using exact exported Round Entry helper functions.

No Source/readiness/acknowledgement writes. Census/status only read; start warms real
assets through one engine worker. Stop never cancels an in-flight engine request.
Importing or --code-only invokes no native tool. Root owns the Play session.
"""
from pathlib import Path
import argparse
from datetime import datetime, timezone
import hashlib
import json
import re
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).parent
sys.path.insert(0, str(ROOT / 'tools'))
from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio, RELEASE_STUDIO_NAME
from push_repo_to_studio import luau_string

DEFAULT_SOURCE = ROOT / 'StarterPlayer/StarterPlayerScripts/Round Entry Client.LocalScript.lua'
STUDIO_ID = '1b603e69-7ae1-4572-b210-d5bf05c684ff'
PHASES = ('census', 'start', 'batch-start', 'status', 'stop', 'release')


def code_for(phase, session, source, index=1, count=1, budget=30):
    assert phase in PHASES and 1 <= index <= 10000 and 1 <= count <= 1024
    assert 1 <= budget <= 180
    assert re.fullmatch(r'[A-Za-z0-9_.-]{1,70}', session)
    raw = source.encode()
    digest = hashlib.sha256(raw).hexdigest()
    start = source.index('local CONTENT_PROPERTIES = {')
    end = source.index('\nlocal function finite(value)', start)
    helpers = source[start:end]
    assert 'local function collectAsset(instance, ids, carriers)' in helpers
    single_carrier = 'local function loadCarrier(carrier)' in helpers
    assert single_carrier or 'local function loadCarriers(carriers)' in helpers
    load_one = ('local loaded=loadCarrier(st.Carriers[i])' if single_carrier else
                'loadCarriers({st.Carriers[i]}) local loaded=st.Carriers[i].Loaded')
    prefix = f'''assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place")
local RS=game:GetService("RunService") assert(RS:IsRunning() and RS:IsStudio(),"Requires existing Studio Play")
local Players=game:GetService("Players") local player=assert(Players.LocalPlayer,"Requires Client DataModel")
local CP=game:GetService("ContentProvider") local HS=game:GetService("HttpService")
local KEY={luau_string('LazyLevel4EntryDiagnostic:' + session)} local SOURCE_SHA={luau_string(digest)}
local function encode(value) return HS:JSONEncode(value) end
local function states(keys)
 local out={{}} for _,key in ipairs(keys or {{}}) do
  local ok,status=pcall(CP.GetAssetFetchStatus,CP,key)
  out[#out+1]={{key=tostring(key),readable=ok,status=ok and tostring(status) or tostring(status)}}
 end return out
end
local function describe(carrier,index)
 local instance=carrier.Instance local out={{index=index,keys={{}},imageId=carrier.ImageId,
  class=instance and instance.ClassName or "temporary Decal",path=instance and instance:GetFullName() or "temporary Decal",
  statuses=states(carrier.Keys)}}
 for _,key in ipairs(carrier.Keys) do out.keys[#out.keys+1]=tostring(key) end
 if instance and instance:IsA("MeshPart") then
  for _,name in ipairs({{"MeshId","TextureID","MeshContent","TextureContent"}}) do
   local ok,value=pcall(function() return instance[name] end)
   if ok then out[name]=tostring(value) end
  end
 end
 return out
end
local function summary(st)
 local out={{sourceSHA256=SOURCE_SHA,session=KEY,phase=st.Phase,carriers=st.Carriers and #st.Carriers or 0,
  assetKeys=st.AssetKeys,workerBusy=st.WorkerBusy==true,cancelRequested=st.CancelRequested==true,
  requestedFirst=st.RequestedFirst,requestedLast=st.RequestedLast,stopReason=st.StopReason,
  processed=st.Processed or 0,failed=st.Failed or 0,callbackCount=st.CallbackCount or 0,
  lastCallback=st.LastCallback,current=st.Current,results=st.Results or {{}},error=st.Error,
  requestQueueSize=CP.RequestQueueSize,nativeSourceGuard=st.NativeSourceGuard,deadline=st.WorkDeadline,
  elapsed=st.StartedAt and os.clock()-st.StartedAt or 0,temporaryDecalActive=st.TemporaryDecal~=nil and st.TemporaryDecalDestroyed~=true,
  batch=st.Batch,batchCallbacks=st.BatchCallbacks,temporaryDecalsOwned=st.TemporaryDecals and #st.TemporaryDecals or 0,
  readinessWrites=0,acknowledgementsSent=0,sourceWrites=0}}
 if st.CurrentIndex and st.Carriers and st.Carriers[st.CurrentIndex] then out.currentStatuses=states(st.Carriers[st.CurrentIndex].Keys) end
 return out
end
'''
    if phase == 'census':
        return prefix + 'local ContentProvider=CP\n' + helpers + f'''
assert(not shared[KEY],"Use a fresh diagnostic session label")
local character=assert(player.Character,"No actual entry character")
local root=assert(character:FindFirstChild("HumanoidRootPart"),"No actual entry root")
local model=assert(workspace:FindFirstChild("Level 4 Cinema Blender"),"No actual cinema replica")
assert(workspace:GetAttribute("SelectedLevel")==4,"Wrong selected level")
local sourceObject=game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
sourceObject=sourceObject and sourceObject:FindFirstChild("Round Entry Client")
if not sourceObject then local scripts=player:FindFirstChild("PlayerScripts") sourceObject=scripts and scripts:FindFirstChild("Round Entry Client") end
local nativeGuard="runtime Source inaccessible; production fragments come from the recorded source SHA"
if sourceObject then
 local ok,value=pcall(function() return sourceObject.Source end)
 if ok then
  local b=game:GetService("EncodingService"):ComputeBufferHash(buffer.fromstring(value),Enum.HashAlgorithm.Sha256)
  local chars={{}} for i=0,buffer.len(b)-1 do chars[i+1]=string.format("%02x",buffer.readu8(b,i)) end
  assert(table.concat(chars)==SOURCE_SHA,"Native Round Entry source differs from exact exported diagnostic source")
  nativeGuard="actual runtime Source SHA matches"
 end
end
local position=root.Position local ids,carriers={{}},{{}} local scanned=0 local deadline=os.clock()+20
local function nearby(instance)
 local part=instance:IsA("BasePart") and instance or instance:FindFirstAncestorWhichIsA("BasePart")
 return part and part.Transparency<1 and (part.Position-position).Magnitude<=80+part.Size.Magnitude*0.5
end
local function scan(owner,isCharacter)
 for index,instance in ipairs(owner:GetDescendants()) do
  assert(os.clock()<deadline and player.Character==character and model.Parent==workspace,"Census changed/timed out")
  if (CONTENT_PROPERTIES[instance.ClassName] or instance:IsA("SurfaceAppearance")) and (isCharacter or nearby(instance)) then
   collectAsset(instance,ids,carriers)
  end
  scanned+=1 if index%200==0 then task.wait() end
 end
end
scan(character,true) scan(model,false)
local pad=workspace:FindFirstChild("ElevatorSpawn") if pad then scan(pad,false) end
local assetKeys=0 local statusCounts={{}} for key in pairs(ids) do
 assetKeys+=1 local ok,status=pcall(CP.GetAssetFetchStatus,CP,key)
 local label=ok and tostring(status) or "unreadable" statusCounts[label]=(statusCounts[label] or 0)+1
end
local st={{Phase="censused",Character=character,Model=model,Position=position,Carriers=carriers,
 AssetKeys=assetKeys,NativeSourceGuard=nativeGuard,Results={{}},SourceSHA=SOURCE_SHA,Scanned=scanned}}
shared[KEY]=st local out=summary(st) out.scanned=scanned out.statusCounts=statusCounts out.first={{}}
for i=1,math.min(#carriers,30) do out.first[#out.first+1]=describe(carriers[i],i) end
return encode(out)
'''
    ownership = '''local st=assert(shared[KEY],"Census this exact diagnostic session first")
assert(st.SourceSHA==SOURCE_SHA,"Diagnostic source changed between phases")
'''
    if phase == 'start':
        return prefix + ownership + '''assert(not st.WorkerBusy,"Prior engine request still owns this diagnostic")
assert(st.Carriers and player.Character==st.Character and st.Model.Parent==workspace,"Censused runtime changed")
local EngineInstance=Instance
local Instance={new=function(className)
 local instance=EngineInstance.new(className)
 if className=="Decal" then
  st.TemporaryDecal=instance st.TemporaryDecalDestroyed=false
  st.TemporaryDecalConnection=instance.Destroying:Connect(function() st.TemporaryDecalDestroyed=true end)
 end
 return instance
end}
local ContentProvider={}
function ContentProvider:PreloadAsync(list,callback)
 st.Phase="waiting-engine" st.EngineCallAt=os.clock() st.CallbackCount=0
 CP:PreloadAsync(list,function(id,status)
  st.CallbackCount+=1 st.LastCallback={id=tostring(id),status=tostring(status),at=os.clock()}
  callback(id,status) -- forward the real engine callback unchanged
 end)
 st.EngineReturnedAt=os.clock() st.Phase="engine-returned"
end
''' + helpers + f'''
local first,last={index},math.min(#st.Carriers,{index}+{count}-1)
assert(first<=last,"Requested carrier index is outside actual census")
st.WorkerBusy=true st.CancelRequested=false st.StartedAt=os.clock() st.WorkDeadline=os.clock()+30
st.RequestedFirst,st.RequestedLast,st.StopReason=first,last,nil st.Error=nil
st.Worker=task.spawn(function()
 local ok,problem=xpcall(function()
  for i=first,last do
   if st.CancelRequested then st.StopReason="requested-stop"; break end
   if os.clock()>=st.WorkDeadline then st.StopReason="between-request-budget"; break end
   if player.Character~=st.Character or st.Model.Parent~=workspace then st.StopReason="runtime-changed"; break end
   st.CurrentIndex=i st.Current=describe(st.Carriers[i],i) st.CallbackCount=0 st.LastCallback=nil
   st.EngineReturnedAt=nil st.TemporaryDecal=nil st.TemporaryDecalDestroyed=nil
   {load_one} -- exact production helper, including its owned Decal cleanup
   local decal=st.TemporaryDecal local parentLocked=true
   if decal then
    -- Destroying uses deferred delivery. Parent is locked by Destroy even while
    -- its notification is pending, unlike an unparented but still live Decal.
    local assignable=pcall(function() decal.Parent=nil end) parentLocked=not assignable
    task.wait() -- keep the connection alive until the deferred signal can run
   end
   st.Results[#st.Results+1]={{index=i,loaded=loaded,callbacks=st.CallbackCount,lastCallback=st.LastCallback,
    engineSeconds=st.EngineReturnedAt and st.EngineReturnedAt-st.EngineCallAt or nil,
    statuses=states(st.Carriers[i].Keys),temporaryDecalDestroyed=parentLocked,
    deferredDestroyingObserved=st.TemporaryDecalDestroyed==true}}
   if st.TemporaryDecalConnection then st.TemporaryDecalConnection:Disconnect(); st.TemporaryDecalConnection=nil end
   assert(parentLocked,"Exact loadCarrier did not lock its destroyed temporary Decal Parent")
   st.TemporaryDecal=nil st.Processed=(st.Processed or 0)+1
   if not loaded then st.Failed=(st.Failed or 0)+1 end
  end
 end,debug.traceback)
 if not ok then
  st.Error=tostring(problem)
  if st.TemporaryDecal then pcall(function() st.TemporaryDecal:Destroy() end) st.TemporaryDecal=nil end
  if st.TemporaryDecalConnection then st.TemporaryDecalConnection:Disconnect(); st.TemporaryDecalConnection=nil end
 end
 st.Phase=st.CancelRequested and "stopped-after-drain" or "drained" st.WorkerBusy=false st.Worker=nil
end)
return encode(summary(st))
'''.replace('st.WorkDeadline=os.clock()+30', f'st.WorkDeadline=os.clock()+{budget}')
    if phase == 'batch-start':
        return prefix + ownership + f'''assert(not st.WorkerBusy,"Prior engine request still owns this diagnostic")
assert(st.Carriers and player.Character==st.Character and st.Model.Parent==workspace,"Censused runtime changed")
local first,last={index},math.min(#st.Carriers,{index}+{count}-1)
assert(first<=last,"Requested carrier index is outside actual census")
st.WorkerBusy=true st.CancelRequested=false st.StartedAt=os.clock() st.WorkDeadline=os.clock()+{budget}
st.RequestedFirst,st.RequestedLast,st.StopReason=first,last,nil st.Error=nil
st.BatchCallbacks={{}} st.TemporaryDecals={{}} st.Batch={{requested=last-first+1,reported=0,missing=0,failed=0}}
st.CallbackCount=0 st.LastCallback=nil st.CurrentIndex=nil st.Current=nil
local function comparable(key)
 local value=tostring(key)
 local id=string.match(value,"^rbxassetid://(%d+)$") or string.match(value,"[?&]id=(%d+)")
 return id and "assetid:"..id or value
end
st.Worker=task.spawn(function()
 local requested,lookup,instances={{}},{{}},{{}}
 local function cleanup()
  local evidence={{}} local problem
  for _,decal in ipairs(st.TemporaryDecals) do
   local ok,err=pcall(function() decal:Destroy() end)
   local assignable=pcall(function() decal.Parent=nil end)
   evidence[#evidence+1]={{destroyReturned=ok,parentLocked=not assignable}}
   if not ok or assignable then problem=tostring(err or "destroyed Parent remained assignable") end
  end
  st.Batch.cleanup=evidence if not problem then st.TemporaryDecals=nil end
  return problem
 end
 local ok,problem=xpcall(function()
  for i=first,last do
   local carrier=st.Carriers[i] local instance=carrier.Instance
   if carrier.ImageId then
    instance=Instance.new("Decal") table.insert(st.TemporaryDecals,instance)
    instance.Texture=carrier.ImageId
   end
   assert(instance,"Censused carrier has no supported real instance") table.insert(instances,instance)
   local row={{index=i,keys={{}},reported={{}},failed=false}} table.insert(requested,row)
   for _,key in ipairs(carrier.Keys) do
    local normalized=comparable(key) row.keys[#row.keys+1]=tostring(key)
    lookup[normalized]=lookup[normalized] or {{}} table.insert(lookup[normalized],row)
   end
  end
  st.Batch.instances=#instances st.Batch.keys=st.AssetKeys st.Batch.carriers=requested
  st.Phase="waiting-engine-batch" st.EngineCallAt=os.clock()
  CP:PreloadAsync(instances,function(id,status)
   local normalized=comparable(id) local success=status==Enum.AssetFetchStatus.Success
   local record={{id=tostring(id),status=tostring(status),at=os.clock(),matched=lookup[normalized]~=nil}}
   st.BatchCallbacks[#st.BatchCallbacks+1]=record st.CallbackCount=(st.CallbackCount or 0)+1 st.LastCallback=record
   for _,row in ipairs(lookup[normalized] or {{}}) do row.reported[normalized]=success if not success then row.failed=true end end
   if not success then st.Batch.failedCallbacks=(st.Batch.failedCallbacks or 0)+1 end
  end)
  st.EngineReturnedAt=os.clock() st.Batch.engineSeconds=st.EngineReturnedAt-st.EngineCallAt
  for offset,row in ipairs(requested) do
   local reported=true
   for _,key in ipairs(st.Carriers[first+offset-1].Keys) do if row.reported[comparable(key)]~=true then reported=false end end
   row.loaded=reported and not row.failed
   if row.loaded then st.Batch.reported+=1 else st.Batch.missing+=1 end
   if row.failed then st.Batch.failed+=1 end
  end
  st.Processed=(st.Processed or 0)+#requested st.Failed=(st.Failed or 0)+st.Batch.missing
 end,debug.traceback)
 local cleanupProblem=cleanup()
 if not ok or cleanupProblem then st.Error=tostring(not ok and problem or cleanupProblem) end
 st.Phase=st.CancelRequested and "stopped-after-drain" or "batch-drained" st.WorkerBusy=false st.Worker=nil
end)
return encode(summary(st))
'''
    if phase == 'status':
        return prefix + ownership + 'return encode(summary(st))\n'
    if phase == 'stop':
        return prefix + ownership + '''st.CancelRequested=true
-- Do not cancel task or release ownership while PreloadAsync still holds a typed request.
return encode(summary(st))
'''
    if phase == 'release':
        return prefix + ownership + '''assert(not st.WorkerBusy,"Cannot release an engine-owned request before it drains")
assert(not st.TemporaryDecal,"Temporary carrier cleanup incomplete")
assert(not st.TemporaryDecals,"Batch temporary carrier cleanup incomplete")
local out=summary(st) st.Carriers=nil st.Character=nil st.Model=nil st.Current=nil st.Worker=nil
shared[KEY]=nil out.referencesReleased=true return encode(out)
'''
    raise AssertionError(phase)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=PHASES)
    parser.add_argument('--session', required=True)
    parser.add_argument('--source', type=Path, default=DEFAULT_SOURCE, help='fresh exact exported Round Entry source')
    parser.add_argument('--index', type=int, default=1)
    parser.add_argument('--count', type=int, default=1)
    parser.add_argument('--budget', type=int, default=30, help='1..180 seconds between sequential requests; never cancels an engine-owned call')
    parser.add_argument('--code-only', action='store_true')
    args = parser.parse_args()
    source = args.source.read_bytes().decode('utf-8')
    code = code_for(args.phase, args.session, source, args.index, args.count, args.budget)
    if args.code_only:
        print(code)
        return
    label = args.session + '-' + args.phase + '-' + uuid.uuid4().hex[:10]
    checkpoint = ROOT / '.git/lazy-levels-20261009' / ('entry-diagnostic-' + label + '.luau')
    checkpoint.parent.mkdir(parents=True, exist_ok=True)
    with checkpoint.open('x', encoding='utf-8', newline='\n') as handle:
        handle.write(code)
    receipt = {'task': 'lazy-levels-20261009', 'phase': args.phase, 'session': args.session,
               'sourceSHA256': hashlib.sha256(source.encode()).hexdigest(),
               'codeSHA256': hashlib.sha256(code.encode()).hexdigest(), 'passed': False}
    client = None
    try:
        client = StudioMcpClient(find_mcp_batch())
        client.initialize()
        studio = select_studio(client, RELEASE_STUDIO_NAME, 20)
        assert studio['id'] == STUDIO_ID, 'Authoritative Studio session changed'
        receipt['studio'] = studio
        result = json.loads(client.call('execute_luau', {'studio_id': studio['id'], 'datamodel_type': 'Client', 'code': code}))
        receipt['result'] = result
        receipt['passed'] = True
    except Exception as error:
        receipt['error'] = str(error)
        raise
    finally:
        if client:
            client.close()
        receipt['capturedAtUtc'] = datetime.now(timezone.utc).isoformat()
        receipt['limits'] = 'Exact production asset census/helper with forwarded real callback observations; no readiness/ack/source edits or renderer/gameplay certification'
        with (HERE / ('entry-diagnostic-' + label + '.json')).open('x', encoding='utf-8', newline='\n') as handle:
            json.dump(receipt, handle, ensure_ascii=False, indent=2)
            handle.write('\n')
    print(json.dumps(receipt))


if __name__ == '__main__':
    main()
