"""Execute actual loading source with deterministic engine-boundary fixtures.

Defaults to promoted repository mirrors. --candidate uses this task's candidates.
The complete Round Entry Client is executed. Lobby tests execute the unmodified
asset census/preload/prefetch regions extracted from the selected real script;
they do not reproduce the implementation. This is not cold-cache gameplay QA.
"""
import argparse
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
TASK = Path(__file__).parent
spec = importlib.util.spec_from_file_location('entry_fixture', ROOT / 'tools/tests/test_round_entry_client.py')
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)

HARNESS = fixture.HARNESS
HARNESS = HARNESS.replace('''local function signal()
    local listeners={}
    return {Connect=function(_,fn) table.insert(listeners,fn); return {Disconnect=function() end} end,
        Fire=function(_,...) for _,fn in listeners do fn(...) end end}
end''', '''local function signal()
    local listeners={}
    return {Connect=function(_,fn)
        local item={Fn=fn,Active=true}; table.insert(listeners,item)
        return {Disconnect=function() item.Active=false end}
    end,Fire=function(_,...) for _,item in listeners do if item.Active then item.Fn(...) end end end,
    Count=function() local total=0;for _,item in listeners do if item.Active then total+=1 end end;return total end}
end''')
HARNESS = HARNESS.replace('Children={},Attributes={}', 'Children={},Attributes={},DescendantAdded=signal()')
HARNESS = HARNESS.replace('function nodeMethods:GetDescendants()\n', '''function nodeMethods:FindFirstAncestorWhichIsA(class)
    local parent=self.Parent
    while parent do if parent:IsA(class) then return parent end; parent=parent.Parent end
end
function nodeMethods:GetDescendants()
    self.DescendantScans=(self.DescendantScans or 0)+1
''')
HARNESS = HARNESS.replace('AssetFetchStatus={Success="Success",Failure="Failure"}',
    'AssetFetchStatus={Success="Success",Failure="Failure"},ContentSourceType={Uri="Uri",None="None",Opaque="Opaque"}')
HARNESS = HARNESS.replace('node("MeshPart","BodyMesh",character)', '''local body=node("MeshPart","BodyMesh",character)
        body.MeshContent={Kind="Content",SourceType="Uri",Uri="rbxassetid://1001"}
        body.TextureContent={Kind="Content",SourceType="None"}
        body.MeshId="rbxassetid://1001"; body.Size=Vector3.new(2,4,2)
        body.Position=Vector3.new(0,5,0); body.Transparency=0''')
HARNESS = HARNESS.replace('function ctx.Task.wait(delay) return coroutine.yield(delay or .03) end',
    'function ctx.Task.wait(delay) ctx.Yields=(ctx.Yields or 0)+1; return coroutine.yield(delay or .03) end')
HARNESS = HARNESS.replace('if ctx.AssetsDelay>0 then ctx.Task.wait(ctx.AssetsDelay) end',
    'local delay=ctx.LoadDelays and ctx.LoadDelays[ctx.PreloadCalls] or ctx.AssetsDelay; if delay>0 then ctx.Task.wait(delay) end')
HARNESS = HARNESS.replace('''        if ctx.PreloadError then error("preload failed") end
        for _ in assets do callback("asset",ctx.RefuseAssets and "Failure" or "Success") end''', '''        if ctx.PreloadError then error("preload failed") end
        if ctx.NoCallbacks then return end
        for _,asset in assets do
            if ctx.SkipEmbeddedCallbacks and asset.MeshContent and asset.MeshContent.SourceType=="Opaque"
                and asset.MeshId=="" and asset.TextureID=="" then continue end
            local refused=ctx.RefuseAssets or (ctx.RefuseId and asset.Texture==ctx.RefuseId)
            callback(ctx.CallbackAlias or "asset",refused and "Failure" or "Success")
        end''')
HARNESS = HARNESS.replace('    local services={Players=', '''    ctx.CreatedDecals=0; ctx.DestroyedDecals=0
    ctx.Instance={new=function(class)
        check(class=="Decal","only test-owned image carriers are allocated")
        ctx.CreatedDecals+=1
        local value={ClassName=class,Kind="Instance",IsA=function(self,name) return name==self.ClassName end}
        function value:Destroy() ctx.DestroyedDecals+=1; self.Destroyed=true end
        return value
    end}
    ctx.Content=content; ctx.Warns={}
    local services={StarterGui={SetCore=function(_,key,value) ctx.ResetAllowed=value end},Players=''')
HARNESS = HARNESS.replace('    local game,workspace,task=ctx.Game,ctx.Workspace,ctx.Task', '''    local game,workspace,task,Instance=ctx.Game,ctx.Workspace,ctx.Task,ctx.Instance
    local warn=function(message) table.insert(ctx.Warns,message) end''')
HARNESS = HARNESS.replace('local os={clock=function() return ctx.Now end}', '''local os={clock=function()
        ctx.ClockReads=(ctx.ClockReads or 0)+1
        if ctx.ClockLimit then assert(ctx.ClockReads<ctx.ClockLimit,"busy live-cover loop did not yield") end
        return ctx.Now
    end}''')

ENTRY_TESTS = fixture.TESTS.replace('{1,3,4,5}', '{1,3,4}')
ENTRY_TESTS = ENTRY_TESTS.replace('ctx.World.Name=level==1 and "Maze" or ("Level "..level.." Generated World")',
    'ctx.World.Name=level==1 and "Maze" or level==4 and "Level 4 Cinema Blender" or ("Level "..level.." Generated World")')
ENTRY_TESTS = ENTRY_TESTS.replace('ctx:Advance(.29)', 'ctx:Advance(.69)').replace('ctx:Advance(.3)', 'ctx:Advance(.69)')
ENTRY_TESTS = ENTRY_TESTS.replace('ctx:Prepare({Token="attempt-2"}); ctx:Advance(1)',
    'ctx:Prepare({Token="attempt-2"}); ctx:Advance(1.6)')
ENTRY_TESTS = ENTRY_TESTS.replace('print("Round Entry Client:', 'print("Existing entry contracts + candidate readiness:')

EXTRA_ENTRY = r'''
local function mesh(parent,name,x,y,key)
    local part=node("MeshPart",name,parent)
    part.MeshContent={Kind="Content",SourceType="Uri",Uri=key or "rbxassetid://2001"}
    part.TextureContent={Kind="Content",SourceType="None"}; part.MeshId=part.MeshContent.Uri
    part.Position=Vector3.new(x or 0,y or 14,0); part.Size=Vector3.new(24,1,24)
    part.Transparency=0; part.CanQuery=false
    return part
end
do
    local ctx=fresh(); local ceiling=mesh(ctx.World,"Ceiling",0,14)
    local far=mesh(ctx.World,"DistantCeiling",500,14,"rbxassetid://2999")
    ctx.AssetsDelay=.5; ctx:Prepare(); ctx:Advance(.69)
    check(#ctx.Acks==0,"visible ground does not release before nearby ceiling mesh finishes")
    ctx:Advance(.8)
    check(#ctx.Acks>0,"entry releases after nearby ceiling fetch resolves")
    local offered,remote=false,false
    for _,list in ctx.Preloaded do for _,value in list do
        offered=offered or value==ceiling; remote=remote or value==far
    end end
    check(offered,"CanQuery=false ceiling is actually offered as typed mesh carrier")
    check(not remote,"distant whole-map ceiling asset is not requested by entry")
end
do
    local ctx=fresh(); local ceiling=mesh(ctx.World,"Ceiling",0,14)
    local pbr=node("SurfaceAppearance","PBR",ceiling)
    pbr.ColorMapContent={Kind="Content",SourceType="Uri",Uri="rbxassetid://3001"}
    pbr.NormalMapContent={Kind="Content",SourceType="Uri",Uri="rbxassetid://3002"}
    pbr.RoughnessMapContent={Kind="Content",SourceType="None"}
    pbr.MetalnessMapContent={Kind="Content",SourceType="None"}
    ctx.RefuseId="rbxassetid://3001"; ctx:Prepare(); ctx:Advance(1.5)
    check(#ctx.Acks==0,"nearby failed PBR image cannot claim entry assets ready")
    check(ctx.CreatedDecals==3 and ctx.DestroyedDecals==3,"two PBR images plus one retry leave no temporary Decals")
    for _,list in ctx.Preloaded do for _,value in list do check(value~=pbr,"unsupported SurfaceAppearance is never offered") end end
end
do
    local ctx=fresh(); ctx.NoCallbacks=true; ctx:Prepare(); ctx:Advance(1.5)
    check(#ctx.Acks==0,"a successful call with no callback cannot claim entry success")
    check(ctx.PreloadCalls==2,"unreported asset receives one bounded retry")
end
do
    local ctx=fresh(); local ceiling=mesh(ctx.World,"EmbeddedCeiling",0,14)
    ceiling.MeshContent={Kind="Content",SourceType="Opaque"};ceiling.TextureContent={Kind="Content",SourceType="Opaque"}
    ceiling.MeshId="";ceiling.TextureID="";ctx.SkipEmbeddedCallbacks=true
    ctx:Prepare();ctx:Advance(.9)
    check(#ctx.Acks>0,"nearby embedded mesh without remote IDs does not block entry")
    check(ctx.PreloadCalls==1 and #ctx.Warns==0,"embedded ceiling is not requested or reported as a failed remote asset")
end
do
    local ctx=fresh(); ctx:Prepare(); ctx:Advance(.69); local count=#ctx.Acks
    local ceiling=mesh(ctx.World,"LateCeiling",0,14,"rbxassetid://4001")
    ctx.AssetsDelay=.7; ctx.World.DescendantAdded:Fire(ceiling); ctx:Advance(.4)
    check(#ctx.Acks==count and ctx.Player:GetAttribute("RoundEntryReadyToken")==nil,
        "late nearby ceiling invalidates readiness while it fetches")
    ctx:Advance(.8); check(#ctx.Acks>count,"late nearby visual can resolve without re-preparing entry")
    local calls=ctx.PreloadCalls; local scans=ctx.World.DescendantScans
    ctx:Advance(.5)
    check(ctx.PreloadCalls==calls and ctx.World.DescendantScans==scans,"steady entry never rescans or reloads world")
    ctx.Remote.OnClientEvent:Fire("entryreleased",{Token="attempt-1"})
    check(ctx.World.DescendantAdded:Count()==0 and ctx.Player.Character.DescendantAdded:Count()==0,
        "entry release disconnects world and character watchers")
    local afterRelease=ctx.PreloadCalls
    ctx.World.DescendantAdded:Fire(mesh(ctx.World,"AfterRelease",0,14,"rbxassetid://4999")); ctx:Advance(.5)
    check(ctx.PreloadCalls==afterRelease,"entry release disconnects visual arrival listeners")
end
do
    local ctx=fresh(); ctx.AssetsDelay=.7; ctx:Prepare(); ctx:Advance(.1)
    ctx:Prepare({Token="attempt-2"}); ctx:Advance(.3)
    check(ctx.PreloadCalls==1,"replacement entry waits for old engine request to drain")
    ctx:Advance(1.5)
    for _,ack in ctx.Acks do check(ack.Payload.Token=="attempt-2","late old fetch cannot ack new entry") end
end
do
    local ctx=fresh()
    for index=1,501 do mesh(ctx.World,"Ceiling"..index,500,14,"rbxassetid://5000") end
    ctx:Prepare(); ctx:Advance(.9)
    check(ctx.Yields>8,"large initial world census yields to other tasks")
    check(ctx.PreloadCalls==1,"501 distant meshes never become entry preload work")
end
print("Loading entry regressions: "..checks.." checks passed")
'''

LOBBY_PREFIX = r'''
    local ContentProvider=ctx.Content
    local originalPreload=ContentProvider.PreloadAsync
    function ContentProvider:PreloadAsync(assets,callback)
        ctx.ActiveLoads=(ctx.ActiveLoads or 0)+1
        ctx.MaxLoads=math.max(ctx.MaxLoads or 0,ctx.ActiveLoads)
        ctx.LoadStarts=ctx.LoadStarts or {};table.insert(ctx.LoadStarts,ctx.Now)
        local ok,problem=pcall(originalPreload,self,assets,callback)
        ctx.ActiveLoads-=1
        if not ok then error(problem) end
    end
    local retryToken,enterAnyway,progress=0,false,0
    local status={Text=""}
    local function touch() if ctx.TouchError then error("unexpected presentation error") end end
    local function devFlag(name) return ctx[name]==true end
'''
LOBBY_SUFFIX = r'''
    return {Census=census,Collect=collectAsset,Load=loadCarrier,Pending=pendingCarriers,Preload=preload,
        Fetch=fetch,Reset=resetFetch,Needs=needsFetch,Failed=failedFetch,Busy=function() return fetching end,
        LiveFetch=function(model,still)
__LIVE_FETCH_LOOP__
        end,
        Incomplete=function(model)
__LIVE_INCOMPLETE__
            return incomplete
        end,
        State=function(key) return seen[key] end,Queue=function() return #queued end,
        PreloadBusy=function() return preloadBusy end,Progress=function() return progress end,
        Settled=function() return settledCount end,Text=function() return status.Text end,
        SetRetry=function() retryToken+=1 end,Skip=function() enterAnyway=true end}
end
local function fresh() local ctx=context(); return ctx,boot(ctx) end
local function run(ctx,fn,seconds) ctx.Task.spawn(fn); ctx:Advance(seconds or .5) end
'''
LOBBY_TESTS = r'''
local function mesh(parent,key)
    local part=node("MeshPart","Mesh",parent)
    part.MeshContent={Kind="Content",SourceType="Uri",Uri=key or "rbxassetid://8001"}
    part.TextureContent={Kind="Content",SourceType="None"};part.MeshId=part.MeshContent.Uri
    return part
end
local function work(ctx,api,count,base)
    local ids,carriers={},{}
    for index=1,count do api.Collect(mesh(ctx.World,"rbxassetid://"..(base+index)),ids,carriers) end
    return ids,carriers
end
do
    local ctx,api=fresh();local ids,carriers=work(ctx,api,9,9000)
    ctx.AssetsDelay=.4;local finished=false;local failed
    run(ctx,function() failed=api.Preload(ids,carriers,9);finished=true end,.1)
    check(ctx.PreloadCalls==4 and ctx.ActiveLoads==4,"initial lobby starts four typed carriers concurrently")
    ctx:Advance(.4)
    check(ctx.PreloadCalls==8 and ctx.MaxLoads==4,"next carriers use the same bounded pool")
    ctx:Advance(.9)
    check(finished and failed==0 and not api.PreloadBusy(),"more than four delayed loads finish through bounded parallel work")
    check(ctx.PreloadCalls==9 and api.Settled()==9 and api.Progress()==1,"all pending keys settle truthfully once")
    local offered={}
    for _,list in ctx.Preloaded do
        check(#list==1 and not offered[list[1]],"each typed carrier is claimed exactly once")
        offered[list[1]]=true
    end
    for _,state in pairs(ids) do check(state=="ok","each completed carrier has final success status") end
end
do
    local ctx,api=fresh();local oldIds,oldCarriers=work(ctx,api,8,9100)
    ctx.LoadDelays={1,2,3,4};local returned,restarted=false,false
    run(ctx,function() local _;_,restarted=api.Preload(oldIds,oldCarriers,8);returned=true end,.1)
    api.SetRetry();ctx:Advance(.11)
    check(returned and restarted and api.PreloadBusy(),"retry returns presentation while all four engine workers retain ownership")
    local initialProgress,initialText=api.Progress(),api.Text()
    local newIds,newCarriers=work(ctx,api,2,9200);local nextDone=false
    run(ctx,function() api.Preload(newIds,newCarriers,2);nextDone=true end,.9)
    check(ctx.PreloadCalls==4 and ctx.ActiveLoads==3 and api.PreloadBusy() and not nextDone,
        "first old worker drain cannot release the owner to a retry")
    ctx:Advance(2.7)
    check(ctx.PreloadCalls==4 and ctx.ActiveLoads==1 and api.PreloadBusy(),"retry still waits for the staggered final worker")
    check(api.Settled()==0 and api.Progress()==initialProgress and api.Text()==initialText,
        "cancelled workers never update shared progress or presentation")
    for _,state in pairs(oldIds) do check(state=="pending","cancelled worker cannot settle an old key") end
    ctx:Advance(.7)
    check(nextDone and not api.PreloadBusy() and ctx.PreloadCalls==6,"retry begins after all prior worker calls drain")
    check(ctx.LoadStarts[5]>=104 and ctx.MaxLoads==4,"new owner never overlaps any prior engine call")
    for _,state in pairs(newIds) do check(state=="ok","replacement pass settles its own keys") end
end
do
    local ctx,api=fresh();local ids,carriers=work(ctx,api,8,9300)
    ctx.LoadDelays={1,2,3,4};local returned=false
    run(ctx,function() api.Preload(ids,carriers,8);returned=true end,.1)
    api.Skip();ctx:Advance(.11)
    check(returned and api.PreloadBusy(),"skip returns presentation without releasing four worker ownership")
    ctx:Advance(3.6)
    check(api.PreloadBusy() and ctx.PreloadCalls==4 and ctx.ActiveLoads==1,"skip keeps ownership until the final staggered request drains")
    ctx:Advance(.3)
    check(not api.PreloadBusy() and ctx.ActiveLoads==0 and api.Settled()==0,"skip final drain releases owner without stale progress")
    for _,state in pairs(ids) do check(state=="pending","skip completion cannot claim cancelled assets loaded") end
end
do
    local ctx,api=fresh();local finished=false
    run(ctx,function() local failed=api.Preload({}, {},0);finished=failed==0 end)
    check(finished and not api.PreloadBusy() and ctx.PreloadCalls==0,"zero carriers return and leave no owner")
    local ids,carriers=work(ctx,api,6,9400);ctx.NoCallbacks=true;local failed
    run(ctx,function() failed=api.Preload(ids,carriers,6) end)
    check(failed==6 and api.Settled()==6 and not api.PreloadBusy(),"pool retains missing-callback failures and releases after every worker")
    for _,state in pairs(ids) do check(state=="failed","callback-free real URI remains failed in parallel pool") end
end
do
    local ctx,api=fresh();local ids,carriers=work(ctx,api,8,9500);ctx.TouchError=true;local failed
    run(ctx,function() failed=api.Preload(ids,carriers,8) end)
    check(not api.PreloadBusy() and ctx.ActiveLoads==0,"protected worker completion releases owner after unexpected presentation error")
    check(failed==4 and api.Settled()==8,"work unreported after worker errors is failed rather than falsely successful")
end
do
    local ctx,api=fresh();local ids,carriers={},{}
    local part=mesh(ctx.World); api.Collect(part,ids,carriers)
    check(#carriers==1 and carriers[1].Instance==part,"mesh URI is dedup key; actual typed instance is preloaded")
    ctx.CallbackAlias="http://www.roblox.com/asset/?id=991"
    run(ctx,function() api.Preload(ids,carriers,1) end)
    check(ids[part.MeshId]=="ok","callback alias is bound to its actual carrier")
    for _,failure in {"RefuseAssets","PreloadError","NoCallbacks"} do
        local failedIds,failedCarriers={},{};api.Collect(part,failedIds,failedCarriers)
        ctx[failure]=true;run(ctx,function() api.Preload(failedIds,failedCarriers,1) end)
        check(failedIds[part.MeshId]=="failed",failure.." cannot become false success")
        ctx[failure]=false
    end
end
do
    local ctx,api=fresh();local ids,carriers={},{}
    local part=mesh(ctx.World); local pbr=node("SurfaceAppearance","PBR",part)
    pbr.ColorMapContent={Kind="Content",SourceType="Uri",Uri="rbxassetid://8101"}
    pbr.NormalMapContent={Kind="Content",SourceType="Uri",Uri="rbxassetid://8102"}
    pbr.RoughnessMapContent={Kind="Content",SourceType="None"};pbr.MetalnessMapContent={Kind="Content",SourceType="None"}
    setmetatable(pbr,{__index=function(self,key)
        if key=="ColorMap" or key=="NormalMap" then error("PluginSecurity") end
        return nodeMethods[key]
    end})
    api.Collect(pbr,ids,carriers)
    check(#carriers==2 and carriers[1].ImageId=="rbxassetid://8101","readable PBR URI maps create supported image work")
    run(ctx,function() api.Preload(ids,carriers,2) end)
    check(ids["rbxassetid://8101"]=="ok" and ids["rbxassetid://8102"]=="ok","PBR raw image callbacks are measured")
    check(ctx.CreatedDecals==2 and ctx.DestroyedDecals==2,"PBR carriers are destroyed after success")
    ctx.PreloadError=true
    check(not api.Load(carriers[1]),"thrown request reports failure")
    check(ctx.CreatedDecals==3 and ctx.DestroyedDecals==3,"PBR carrier cleanup runs after failure")
end
do
    local ctx,api=fresh();local ids,carriers={},{}
    local part=mesh(ctx.World);part.MeshContent={Kind="Content",SourceType="Opaque"}
    local clone=mesh(ctx.World);clone.MeshContent={Kind="Content",SourceType="Opaque"}
    api.Collect(part,ids,carriers);api.Collect(clone,ids,carriers)
    check(#carriers==1,"opaque clones dedup by readable stable MeshId, not Content hash identity")
    part.MeshId="";clone.MeshId="";part.TextureID="";clone.TextureID=""
    part.TextureContent={Kind="Content",SourceType="Opaque"};clone.TextureContent={Kind="Content",SourceType="Opaque"}
    ids,carriers={},{}
    api.Collect(part,ids,carriers);api.Collect(part,ids,carriers);api.Collect(clone,ids,carriers)
    check(#carriers==0 and next(ids)==nil,"embedded opaque mesh and texture without asset IDs create no remote requirements")
    ctx.NoCallbacks=true;run(ctx,function() api.Preload(ids,carriers,0) end)
    check(ctx.PreloadCalls==0 and #ctx.Warns==0,"callback-free embedded content is neither fetched nor falsely failed")
    ctx.NoCallbacks=false;part.TextureContent={Kind="Content",SourceType="Uri",Uri="rbxassetid://8151"}
    api.Collect(part,ids,carriers)
    check(#carriers==1 and carriers[1].Instance==part and carriers[1].Keys[1]=="rbxassetid://8151",
        "embedded mesh with real external texture retains its typed texture carrier")
    run(ctx,function() api.Preload(ids,carriers,1) end)
    check(ids["rbxassetid://8151"]=="ok","mixed embedded mesh and URI texture still waits for real texture callback")
end
do
    local ctx,api=fresh()
    for index=1,501 do mesh(ctx.World,"rbxassetid://8201") end
    local total
    run(ctx,function() total=api.Census({ctx.World},{},{}) end)
    check(total==1 and ctx.Yields>=2,"large census yields while shared meshes dedup")
end
do
    local ctx,api=fresh();local part=mesh(ctx.World,"rbxassetid://8301")
    local second=mesh(ctx.World,"rbxassetid://8302")
    ctx.AssetsDelay=2
    run(ctx,function() api.Fetch({ctx.World},.2) end,.4)
    check(api.Busy() and ctx.PreloadCalls==1,"cap does not release in-flight request ownership")
    run(ctx,function() api.Fetch({ctx.World},.2) end,.2)
    check(ctx.PreloadCalls==1,"next capped prefetch cannot overlap old engine request")
    ctx:Advance(2)
    check(not api.Busy() and api.State(second.MeshId)=="pending","unstarted capped work remains pending")
    ctx.AssetsDelay=0;run(ctx,function() api.Fetch({ctx.World},.5) end)
    check(api.State(second.MeshId)=="ok" and ctx.PreloadCalls==2,"later pass completes pending work")
    local scans=ctx.World.DescendantScans
    run(ctx,function() api.Fetch({ctx.World},.5) end)
    check(ctx.World.DescendantScans==scans and ctx.PreloadCalls==2,"steady world is never rescanned or reloaded")
    local late=mesh(ctx.World,"rbxassetid://8303");ctx.World.DescendantAdded:Fire(late)
    run(ctx,function() api.Fetch({ctx.World},.5) end)
    check(api.State(late.MeshId)=="ok" and ctx.World.DescendantScans==scans,"late visual is queued without map rescan")
end
do
    local ctx,api=fresh();local part=mesh(ctx.World,"rbxassetid://8401");ctx.RefuseAssets=true
    run(ctx,function() api.Fetch({ctx.World},.5) end)
    check(api.State(part.MeshId)=="failed","world failure is retained")
    ctx.RefuseAssets=false;run(ctx,function() api.Fetch({ctx.World},.5) end)
    check(api.State(part.MeshId)=="ok" and ctx.PreloadCalls==2,"failed world asset is retried even with no fresh IDs")
end
do
    local ctx,api=fresh();local part=mesh(ctx.World,"rbxassetid://8501");ctx.AssetsDelay=2
    run(ctx,function() api.Fetch({ctx.World},.2) end,.3);api.Reset()
    check(api.State(part.MeshId)==nil and api.Queue()==0,"reset releases asset and queue references")
    check(ctx.World.DescendantAdded:Count()==0,"world reset disconnects its owned watcher")
    local other=mesh(ctx.World,"rbxassetid://8502");ctx.World.DescendantAdded:Fire(other)
    check(api.Queue()==0,"reset disconnects arrival listeners")
    ctx:Advance(2)
    check(api.State(part.MeshId)==nil and not api.Busy(),"old engine completion cannot repopulate reset generation")
end
do
    local ctx,api=fresh()
    for index=1,2201 do mesh(ctx.World,"rbxassetid://8601") end
    local late=mesh(ctx.World,"rbxassetid://8602")
    run(ctx,function()
        api.LiveFetch(ctx.World,function() return true end)
    end,4.2)
    check(api.State(late.MeshId)=="ok" and not api.Needs(),"bounded repeated pass reaches assets beyond first 2000 descendants")
    check(ctx.World.DescendantScans==1,"multiple initial slices still use one native descendants snapshot")
    check(not api.Incomplete(ctx.World),"indexed model with completed successful work can claim ready")
end
do
    local ctx,api=fresh();local part=mesh(ctx.World,"rbxassetid://8701");ctx.AssetsDelay=2
    run(ctx,function() api.Fetch({ctx.World},.2) end,.3)
    check(api.Busy(),"old capped worker still owns engine request before new live cover")
    api.Reset();ctx.AssetsDelay=0;ctx.ClockReads=0;ctx.ClockLimit=500
    local completed=false
    run(ctx,function() api.LiveFetch(ctx.World,function() return true end);completed=true end,3.5)
    check(completed and not api.Busy(),"actual live-cover repeat yields until old engine request drains")
    check(api.State(part.MeshId)=="ok" and ctx.PreloadCalls==2,"new live generation fetches after old worker releases ownership")
end
do
    local ctx,api=fresh();mesh(ctx.World,"rbxassetid://8801");ctx.AssetsDelay=9
    run(ctx,function() api.Fetch({ctx.World},.2) end,.3);api.Reset();ctx.ClockReads=0;ctx.ClockLimit=500
    local expired=false
    run(ctx,function() api.LiveFetch(ctx.World,function() return true end);expired=true end,8.2)
    check(expired and api.Busy(),"older worker can hold the whole new live-cover eight-second budget")
    ctx:Advance(1)
    check(not api.Busy() and not api.Needs() and not api.Failed(),"old lock drains during settling with new model still unindexed")
    check(api.Incomplete(ctx.World),"actual final status cannot claim ready for an unindexed model after lock drains")
    check(api.Incomplete(nil),"missing live model cannot claim ready")
end
print("Loading lobby regressions: "..checks.." checks passed")
'''


def run(binary, text, name, expect_failure=False):
    with tempfile.TemporaryDirectory(prefix='loading-regressions-') as directory:
        path=Path(directory)/name
        path.write_text(text,encoding='utf-8')
        result=subprocess.run([binary,str(path)],capture_output=True,text=True,timeout=30)
        if expect_failure:
            if result.returncode==0: raise AssertionError(f'Mutation survived: {name}')
            print(f'Mutation caught: {name}: '+next((line for line in result.stderr.splitlines() if ':3:' in line),result.stderr.splitlines()[0]))
            return
        print(result.stdout,end='')
        if result.returncode:
            print(result.stderr,end='')
            raise SystemExit(result.returncode)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--candidate',action='store_true')
    parser.add_argument('--mutations',action='store_true')
    parser.add_argument('--luau',default=os.environ.get('LUAU_BIN') or shutil.which('luau'))
    args=parser.parse_args()
    if not args.luau: raise SystemExit('Set LUAU_BIN or supply --luau; no tests executed.')
    paths=(TASK/'candidates/Lobby Loading Screen.luau',TASK/'candidates/Round Entry Client.luau') if args.candidate else (
        ROOT/'ReplicatedFirst/Lobby Loading Screen.LocalScript.lua',ROOT/'StarterPlayer/StarterPlayerScripts/Round Entry Client.LocalScript.lua')
    lobby,entry=(path.read_text(encoding='utf-8') for path in paths)
    def entry_program(source): return HARNESS+source+ENTRY_TESTS+EXTRA_ENTRY
    def lobby_program(source):
        helpers=source[source.index('local CONTENT_PROPERTIES = {'):source.index('---------------------------------------------------------------------------\n-- The sequence')]
        fetch=source[source.index('\t-- Index each streamed root once;'):source.index('\tlocal function quiet(')]
        start=source.index('\t\t\tlocal fetchDeadline = os.clock() + 8')
        end=source.index('\t\t\tcover.stage("FINISHING TEXTURES"',start)
        live_loop=source[start:end]
        start=source.index('\t\tlocal incomplete = ')
        end=source.index('\n',start)
        final_status=source[start:end]
        suffix=LOBBY_SUFFIX.replace('__LIVE_FETCH_LOOP__',live_loop).replace('__LIVE_INCOMPLETE__',final_status)
        return HARNESS+LOBBY_PREFIX+helpers+fetch+suffix+LOBBY_TESTS
    run(args.luau,entry_program(entry),'entry_test.luau')
    run(args.luau,lobby_program(lobby),'lobby_test.luau')
    if args.mutations:
        mutations=[
            ('no-callback-false-success.luau',lobby_program,lobby,'return ok and reported and not failed','return ok and not failed'),
            ('unreadable-pbr-maps.luau',entry_program,entry,'{ "ColorMapContent", "NormalMapContent", "RoughnessMapContent", "MetalnessMapContent" }','{ "ColorMap", "NormalMap", "RoughnessMap", "MetalnessMap" }'),
            ('distant-world-assets.luau',entry_program,entry,'<= 80 + part.Size.Magnitude','<= 800 + part.Size.Magnitude'),
            ('overlapping-prefetch.luau',lobby_program,lobby,'if fetching then return 0 end','if false then return 0 end'),
            ('stale-generation-write.luau',lobby_program,lobby,'if generation ~= fetchGeneration then break end','if false then break end'),
            ('entry-watcher-leak.luau',entry_program,entry,'connection:Disconnect()','local unused = connection'),
            ('busy-live-cover-no-yield.luau',lobby_program,lobby,'task.wait(0.1) -- An older generation may still own the engine request.','-- missing yield'),
            ('unindexed-live-cover-false-ready.luau',lobby_program,lobby,'local incomplete = not model or not watched[model] or needsFetch() or failedFetch()','local incomplete = needsFetch() or failedFetch()'),
            ('embedded-opaque-false-failure.luau',entry_program,entry,'key = readable and type(id) == "string" and id ~= "" and id or nil','key = readable and type(id) == "string" and id ~= "" and id or instance'),
            ('pool-unbounded-workers.luau',lobby_program,lobby,'math.min(4, #carriers)','math.min(8, #carriers)'),
            ('pool-first-worker-releases-owner.luau',lobby_program,lobby,'if running == 0 then\n\t\t\t\tif token == retryToken','if true then\n\t\t\t\tif token == retryToken'),
            ('pool-cancelled-first-worker-releases-owner.luau',lobby_program,lobby,'if running == 0 then\n\t\t\t\tif token == retryToken','if running == 0 or token ~= retryToken then\n\t\t\t\tif token == retryToken'),
        ]
        for name,program,source,before,after in mutations:
            if before not in source: raise AssertionError(f'Mutation anchor missing: {name}')
            run(args.luau,program(source.replace(before,after)),name,expect_failure=True)


if __name__=='__main__': main()
