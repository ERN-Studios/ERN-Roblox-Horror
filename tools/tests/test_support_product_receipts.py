"""Actual receipt/mutation/normalization/ranking code, with offline fake DataStores."""
from pathlib import Path
import os, shutil, subprocess, tempfile

ROOT = Path(__file__).resolve().parents[2]
SERVER = (ROOT / 'ServerScriptService/ZyntraMonetization.Script.lua').read_text(encoding='utf-8')
CONFIG = (ROOT / 'ReplicatedStorage/ZyntraConfig.ModuleScript.lua').read_text(encoding='utf-8')
def section(start, stop):
    begin = SERVER.index(start)
    return SERVER[begin:SERVER.index(stop, begin)]

COMMON = r'''
local checks=0
local function check(v,m) checks+=1;assert(v,m) end
local function eq(v,e,m) check(v==e,m..": expected "..tostring(e)..", got "..tostring(v)) end
local function clone(v)
    if type(v)~="table" then return v end
    local r={};for k,c in pairs(v) do r[k]=clone(c) end;return r
end
local Color3={fromRGB=function(r,g,b)return {R=r/255,G=g/255,B=b/255}end}
local Config=(function()
'''
WORLD = r'''
end)()
local function world(opts)
    opts=opts or {}
    local w={db=opts.db or {},ranks=opts.ranks or {u_999=900},now=0,calls=0,callbacks=0,writes=0,
        cacheCalls=0,reads=0,tasks={},waiting={},pushes={},reentries=0,studio=opts.studio==true}
    local function warn(...) end
    local Players={roster={}}
    function Players:GetPlayerByUserId(id) return self.roster[id] end
    function Players:GetNameFromUserIdAsync(id) return "Player"..id end
    local player={Name="Buyer",UserId=123,Parent=Players,attributes={}}
    function player:SetAttribute(k,v) self.attributes[k]=v end
    function player:GetAttribute(k) return self.attributes[k] end
    Players.roster[123]=player
    local RunService={IsStudio=function()return w.studio end}
    local Enum={ProductPurchaseDecision={PurchaseGranted="Granted",NotProcessedYet="Retry"}}
    local MarketplaceService={}
    local sessions,mutationLocks={},{}
    local ACCESSIBILITY_SETTINGS=Config.AccessibilitySettings
    local PERCENT_PER_LEVEL=math.floor(Config.TokenPercentPerLevel*100+.5)
    local SUPPORT_LEADERBOARD_SIZE=Config.SupportLeaderboardSize
    local supportStatus,supportRows={},{}
    for n=1,SUPPORT_LEADERBOARD_SIZE do supportRows[n]={} end
    local task={}
    local function enqueue(co,delay)table.insert(w.tasks,{co=co,at=w.now+(delay or 0)})end
    function task.spawn(fn,...)local a={...};enqueue(coroutine.create(function()fn(unpack(a))end))end
    task.defer=task.spawn
    function task.wait(delay)return coroutine.yield(delay or 0)end
    function w:run()
        local steps=0
        while #self.tasks>0 do
            steps+=1;assert(steps<1000,"scheduler did not settle")
            table.sort(self.tasks,function(a,b)return a.at<b.at end)
            local item=table.remove(self.tasks,1);self.now=item.at
            local ok,delay=coroutine.resume(item.co);assert(ok,delay)
            if coroutine.status(item.co)~="dead" then
                if type(delay)=="string" then table.insert(self.waiting,item.co)else enqueue(item.co,delay)end
            end
        end
    end
    function w:resumeWaiting()for _,co in ipairs(self.waiting)do enqueue(co)end;table.clear(self.waiting)end
    local store={}
    function store:UpdateAsync(key,transform)
        w.calls+=1
        if w.failBefore then error("Profile write unavailable")end
        w.callbacks+=1;local result=transform(clone(w.db[key]))
        if w.conflict then
            local fn=w.conflict;w.conflict=nil;fn()
            w.callbacks+=1;result=transform(clone(w.db[key]))
        end
        if result then w.db[key]=clone(result);w.writes+=1 end
        if w.failAfter then w.failAfter=false;error("Committed; response lost")end
        return clone(result)
    end
    local supportStore={}
    function supportStore:UpdateAsync(key,transform)
        w.cacheCalls+=1
        if w.pauseCache then coroutine.yield("CACHE_WAIT")end
        if w.cacheFailures and w.cacheFailures>0 then w.cacheFailures-=1;error("Ranking unavailable")end
        local result=transform(w.ranks[key]);w.ranks[key]=result;return result
    end
    function supportStore:GetSortedAsync(_,count)
        w.reads+=1;local rows={}
        for k,v in pairs(w.ranks)do table.insert(rows,{key=k,value=v})end
        table.sort(rows,function(a,b)return a.value>b.value end)
        while #rows>count do table.remove(rows)end
        return {GetCurrentPage=function()return rows end}
    end
    local function applyHazmatColor()end
    local function reassertPendingAccessibility()end
    local function reentryEligible()return w.eligible==true end
    local function useReentry()w.reentries+=1 end
'''
PUSH = r'''
    local function pushProfile(p,message,tone)
        table.insert(w.pushes,{data=publicProfile(sessions[p].data),message=message,tone=tone})
    end
'''
TAIL = r'''
    if not w.db.u_123 then
        w.db.u_123=normalizeProfile({Tokens=2,ReentryCredits=1,DonationRobux=75,UtilityRobux=0,
            ReceiptIds={"legacy-utility"},SupportRobux=12345,UnknownLegacy={kept=true}})
    end
    sessions[player]={data=normalizeProfile(clone(w.db.u_123)),persistent=not w.studio}
    w.player,w.sessions,w.market,w.status,w.rows=player,sessions,MarketplaceService,supportStatus,supportRows
    w.pending,w.workers=pendingSupportSync,supportSyncWorkers
    w.normalize,w.total,w.public,w.sync,w.queue=normalizeProfile,recordedSupportRobux,publicProfile,syncSupportTotal,queueSupportTotalSync
    w.product=function(n)return Config.Products[n]or Config.Donations[n]end
    function w:receipt(n,amount,id)
        return MarketplaceService.ProcessReceipt({PlayerId=123,ProductId=self.product(n).Id,
            PurchaseId=id or "new",CurrencySpent=amount})
    end
    function w:data()return self.db.u_123 end
    function w:load()
        sessions[player]={data=normalizeProfile(clone(self.db.u_123)),persistent=not self.studio}
        LOAD_REPAIR
    end
    function w:retryDirty()
        DIRTY_RETRY
    end
    function w:leaveRepair()
        local session=sessions[player]
        LEAVE_REPAIR
    end
    return w
end
'''
TESTS = r'''
for _,r in ipairs({{"Tokens4",7,4,0},{"Tokens20",19,20,0},{"EmergencyReentry",3,0,1},{"DonationSignal",2,0,0}})do
    local w=world();local n,paid,tokens,credits=unpack(r)
    eq(w:receipt(n,paid),"Granted",n.." granted")
    local d=w:data()
    eq(d.Tokens,2+tokens,"exact token grant");eq(d.ReentryCredits,1+credits,"exact credit grant")
    eq(d.DonationRobux,n=="DonationSignal"and 77 or 75,"separate donation stream")
    eq(d.UtilityRobux,n=="DonationSignal"and 0 or paid,"utility paid amount, not catalog")
    eq(w.total(d),75+paid,"combined support");eq(#d.ReceiptIds,2,"receipt stored with grant")
    eq(w.calls,1,"one transaction");eq(w.writes,1,"one commit")
    check(d.SupportRobux==12345 and d.UnknownLegacy.kept,"legacy retained, not summed")
    eq(w.player.attributes.ZyntraRecordedSupportRobux,75+paid,"replicated total")
    eq(w.pushes[#w.pushes].data.RecordedSupportRobux,75+paid,"public total")
    eq(w:receipt(n,paid),"Granted","replay acknowledged")
    eq(w:data().Tokens,2+tokens,"no duplicate grant");eq(w.total(w:data()),75+paid,"no duplicate amount")
    eq(w.writes,1,"replay cancels write");w:run()
    eq(w.ranks.u_123,75+paid,"combined ranking");eq(w.ranks.u_999,900,"absent donor kept")
end
do
    local w=world()
    eq(w:receipt("Tokens4",49,"legacy-utility"),"Granted","legacy acknowledged")
    eq(w:data().UtilityRobux,0,"legacy never backfilled");eq(w:data().Tokens,2,"legacy not granted again")
    eq(w:receipt("Tokens4",nil,"legacy-utility"),"Granted","old ID needs no new amount")
    eq(w.writes,0,"legacy no writes")
end
for _,n in ipairs({"Tokens4","DonationSignal"})do
    local w=world();eq(w:receipt(n,0),"Granted","zero paid accepted")
    eq(w.total(w:data()),75,"zero never becomes catalog price")
end
for _,v in ipairs({-1,1.5,0/0,math.huge,-math.huge,9007199254740992,"49",{},true})do
    local w=world();eq(w:receipt("Tokens4",v),"Retry","bad amount rejected")
    eq(w.writes,0,"bad amount no write");eq(w:data().Tokens,2,"bad amount no grant")
    eq(#w:data().ReceiptIds,1,"bad amount no ID");eq(w.sessions[w.player].data.UtilityRobux,0,"no local mutation")
end
for _,id in ipairs({"",string.rep("x",129),123,{}})do
    local w=world();eq(w:receipt("Tokens4",1,id),"Retry","bad ID");eq(w.calls,0,"bad ID before store")
end
for _,kind in ipairs({"support","donation","tokens","credits","combined"})do
    local w=world();local d=w:data();local n="Tokens4"
    if kind=="support"then d.UtilityRobux=9007199254740991-75
    elseif kind=="donation"then d.DonationRobux=9007199254740991;n="DonationSignal"
    elseif kind=="tokens"then d.Tokens=9007199254740991
    elseif kind=="credits"then d.ReentryCredits=9007199254740991;n="EmergencyReentry"
    else d.DonationRobux=9007199254740991;d.UtilityRobux=1 end
    eq(w:receipt(n,1),"Retry",kind.." overflow refused");eq(w.writes,0,"overflow no save")
    eq(#w:data().ReceiptIds,1,"overflow no ID")
end
do
    local w=world();w.failBefore=true
    eq(w:receipt("Tokens4",7),"Retry","failed commit");eq(w:data().Tokens,2,"no grant before commit")
    w.failBefore=false;eq(w:receipt("Tokens4",7),"Granted","retry commits");eq(w:data().UtilityRobux,7,"one paid amount")
end
for _,n in ipairs({"Tokens4","EmergencyReentry","DonationSignal"})do
    local w=world();w.failAfter=true;w.eligible=true
    eq(w:receipt(n,7),"Retry","lost response unresolved");eq(w.total(w:data()),82,"committed before response lost")
    eq(w:receipt(n,7),"Granted","replay recovers");eq(w.total(w:data()),82,"no double amount")
    eq(w.writes,1,"one durable commit");w:run()
    eq(w.ranks.u_123,82,"replay repairs cache");eq(w.reentries,0,"replay never repeats re-entry")
end
do
    local a=world();local b=world({db=a.db,ranks=a.ranks})
    a.conflict=function()eq(b:receipt("Tokens4",7),"Granted","other server commits")end
    eq(a:receipt("Tokens4",7),"Granted","conflicting receipt acknowledges")
    eq(a.callbacks,2,"callback reruns");eq(a:data().Tokens,6,"two servers one grant")
    eq(a:data().UtilityRobux,7,"two servers one amount");eq(#a:data().ReceiptIds,2,"one ID")
    eq(a.writes,0,"loser cancels write");a:run();b:run();eq(a.ranks.u_123,82,"shared ranking")
end
do
    local w=world();w.conflict=function()w:data().Tokens+=10;w:data().DonationRobux+=5 end
    eq(w:receipt("Tokens20",13),"Granted","unrelated concurrent save")
    eq(w:data().Tokens,32,"grant uses latest balance");eq(w:data().DonationRobux,80,"latest donation kept")
    eq(w:data().UtilityRobux,13,"callback adds amount once")
end
do
    local w=world();w.cacheFailures=5
    eq(w:receipt("Tokens4",7),"Granted","cache failure cannot delay ack");w:run()
    eq(w.cacheCalls,5,"bounded retries");eq(w.pending[123],82,"failed total stays dirty")
    eq(w.workers[123],nil,"exhausted worker released");w:retryDirty();w:run()
    eq(w.ranks.u_123,82,"periodic dirty retry repairs");eq(w.pending[123],nil,"confirmed target clears")
end
do
    local w=world();w.pauseCache=true
    eq(w:receipt("Tokens4",7),"Granted","first receipt");w:run()
    eq(w:receipt("Tokens20",11,"second"),"Granted","receipt during cache yield")
    eq(w.pending[123],93,"new pending total");eq(w.cacheCalls,1,"one worker")
    w.pauseCache=false;w:resumeWaiting();w:run()
    eq(w.ranks.u_123,93,"newest survives older write");eq(w.pending[123],nil,"newest clears")
    check(w.sync(123,75),"old server writes");eq(w.ranks.u_123,93,"old donation-only cannot lower total")
end
do
    local a=world();a:receipt("Tokens4",7)
    local b=world({db=a.db,ranks=a.ranks});b:load();b:run();eq(b.ranks.u_123,82,"rejoin repairs")
    b.ranks.u_123=nil;b:leaveRepair();b:run();eq(b.ranks.u_123,82,"leave repairs")
end
for _,mode in ipairs({"missing","unpersisted","closing"})do
    local w=world()
    if mode=="missing"then w.sessions[w.player]=nil
    elseif mode=="unpersisted"then w.sessions[w.player].persistent=false
    else w.sessions[w.player].closing=true end
    eq(w:receipt("Tokens4",7),"Retry",mode.." profile refuses");eq(w.writes,0,"no commit")
end
do
    local w=world();w.eligible=true;eq(w:receipt("EmergencyReentry",7),"Granted","fresh re-entry")
    w:run();eq(w.reentries,1,"fresh auto re-entry");w:receipt("EmergencyReentry",7);w:run()
    eq(w.reentries,1,"duplicate no auto re-entry")
end
for _,n in ipairs({"Tokens4","DonationSignal","EmergencyReentry"})do
    local w=world({studio=true});eq(w:receipt(n,9999),"Granted","Studio free grant")
    eq(w.sessions[w.player].data.UtilityRobux,0,"Studio no paid utility")
    eq(w.sessions[w.player].data.DonationRobux,75,"Studio no paid donation")
    w:run();eq(w.calls,0,"Studio no profile access");eq(w.cacheCalls,0,"Studio no ordered access")
end
do
    local w=world();local d=w.normalize({SupportRobux=999,ReceiptIds={old=true},DonationRobux="75"})
    eq(d.UtilityRobux,0,"missing utility defaults zero");eq(d.DonationRobux,75,"donation retained")
    eq(d.SupportRobux,999,"legacy intact");eq(d.ReceiptIds[1],"old","legacy dedupe retained")
    eq(w.total(d),75,"legacy not merged")
    for _,v in ipairs({0/0,math.huge,-math.huge,-1,9007199254740992})do
        eq(w.total(w.normalize({DonationRobux=v,UtilityRobux=v})),0,"invalid saved amounts cannot poison ranking")
    end
end
print(string.format("support product receipts: %d checks passed",checks))
'''

def main():
    luau=os.environ.get('LUAU_BIN') or shutil.which('luau')
    if not luau: raise SystemExit('Set LUAU_BIN or put luau on PATH')
    load=next(l.strip() for l in SERVER.splitlines() if 'queueSupportTotalSync(player.UserId, recordedSupportRobux(sessions[player]' in l)
    leave=next(l.strip() for l in SERVER.splitlines() if 'queueSupportTotalSync(player.UserId, recordedSupportRobux(session.data))' in l)
    dirty=section('\t\tfor userId, total in pairs(pendingSupportSync)','\n\t\trefreshSupportLeaderboard()')
    tail=TAIL.replace('LOAD_REPAIR',load).replace('DIRTY_RETRY',dirty).replace('LEAVE_REPAIR',leave)
    pieces=[COMMON,CONFIG,WORLD,
        section('local function colorData','local function isDispatchPredecessorClosed'),
        section('local function accessibilityValue','-- The switch a player'),
        section('local function publicProfile','local function addSupporterTag'),
        section('local function applyAttributes','local function enrichedPublicProfile'),PUSH,
        section('local function acquireMutation','-- Developer token gifts'),
        section('local supportNameCache','-- Outer retries are safe'),
        section('local queueSupportTotalSync','\ntask.spawn(function()\n\ttask.wait(1)'),
        section('local productById','\nPlayers.PlayerAdded:Connect(setupPlayer)'),tail,TESTS]
    with tempfile.TemporaryDirectory(prefix='support-receipts-') as directory:
        path=Path(directory)/'receipts.luau';path.write_text('\n'.join(pieces),encoding='utf-8')
        result=subprocess.run([luau,str(path)],capture_output=True,text=True,timeout=30)
    print(result.stdout,end='')
    if result.stderr: print(result.stderr,end='')
    raise SystemExit(result.returncode)

if __name__=='__main__': main()
